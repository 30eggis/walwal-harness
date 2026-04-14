---
name: harness-team-action
description: "v4 Agent Teams 가동. Studio 레이아웃 구축 → Queue 초기화 → Gen↔Eval 분리 사이클 팀 병렬 실행. 트리거: '/harness-team-action', 'team 시작', '팀 가동'"
disable-model-invocation: false
---

# /harness-team-action — Agent Teams 가동

## Step 0: Studio 레이아웃 자동 구축

3-column 대시보드 레이아웃을 자동 구축합니다:

```bash
bash scripts/harness-studio-setup.sh .
```

스크립트 출력을 확인합니다:

- **`Layout ready`** → 현재 터미널에 split 완료. 바로 Step 1로.
- **`ATTACH_TMUX=harness-studio`** → 새 tmux 세션이 생성됨 (tmux 밖에서 실행한 경우).
  사용자에게 아래 안내를 출력하고 **STOP**합니다:

  ```
  Studio 레이아웃이 준비되었습니다!
  다른 터미널에서 아래 명령을 실행하세요:

    tmux attach -t harness-studio

  새 창에서 Claude가 자동 실행됩니다. 거기서 "팀 가동"을 입력하면 Teams가 시작됩니다.
  ```

- **`already set up`** → 이미 구축됨. 바로 Step 1로.

## Step 1: Queue 초기화

```bash
if [ ! -f .harness/actions/feature-queue.json ]; then bash scripts/harness-queue-manager.sh init .; else bash scripts/harness-queue-manager.sh recover .; fi && bash scripts/harness-queue-manager.sh status .
```

## Step 2: Feature 할당 (dequeue)

Queue status 결과를 확인하여 `ready` 큐에 feature가 있는지 확인합니다.
ready feature 수와 설정된 concurrency 중 작은 값만큼 팀을 생성합니다 (최대 3).

**각 팀마다** dequeue 명령으로 feature를 원자적으로 할당합니다:

```bash
bash scripts/harness-queue-manager.sh dequeue {TEAM_NUMBER} .
```

dequeue 결과로 feature ID가 반환됩니다. 빈 결과면 해당 팀은 생성하지 않습니다.

## Step 3: Agent 도구로 팀 생성 (Gen↔Eval 분리 사이클)

dequeue로 할당받은 feature마다 **Agent 도구**를 호출합니다.
**반드시 `isolation: "worktree"`를 사용**하여 각 팀이 독립된 코드 복사본에서 작업합니다.

**독립적인 팀들은 단일 메시지에서 병렬로 호출**하세요 (한 번의 응답에 여러 Agent 도구 호출).

```
Agent({
  description: "Team-{N}: {FEATURE_ID}",
  isolation: "worktree",
  prompt: "<아래 Team Worker 프롬프트>"
})
```

### Team Worker 프롬프트

```
당신은 Harness Team-{N} 워커입니다. 하나의 Feature에 대해 Gen→Eval 사이클을 수행합니다.

## 할당된 Feature
- Feature ID: {FEATURE_ID}
- 프로젝트 루트: 현재 디렉토리 (worktree 복사본)
- 하네스 루트: 메인 프로젝트 루트 (worktree가 아닌 원본)

## 실시간 로깅 (필수)

모든 Phase 전환 시 반드시 아래 두 명령을 실행하세요. Monitor 대시보드에 실시간 반영됩니다.

**progress.log 기록** (하네스 루트의 progress.log에 append):
```bash
echo "$(date +'%Y-%m-%d %H:%M') | team-{N} | {ACTION} | {DETAIL}" >> {HARNESS_ROOT}/.harness/progress.log
```

**queue phase 업데이트** (feature-queue.json의 팀 상태 갱신):
```bash
bash {HARNESS_ROOT}/scripts/harness-queue-manager.sh update_phase {FEATURE_ID} {PHASE} .
```

> {HARNESS_ROOT}는 worktree의 원본 프로젝트 경로입니다. `git worktree list` 첫 줄에서 확인 가능합니다.
> 워커 시작 시 먼저 실행: `HARNESS_ROOT=$(git worktree list | head -1 | awk '{print $1}')`

## Phase 1: Generator (코드 생성)

**시작 시 로깅:**
```bash
HARNESS_ROOT=$(git worktree list | head -1 | awk '{print $1}')
echo "$(date +'%Y-%m-%d %H:%M') | team-{N} | gen | {FEATURE_ID} start" >> "$HARNESS_ROOT/.harness/progress.log"
bash "$HARNESS_ROOT/scripts/harness-queue-manager.sh" update_phase {FEATURE_ID} gen "$HARNESS_ROOT"
```

1. Feature 정보 확인:
   - `jq '.features[] | select(.id == "{FEATURE_ID}")' .harness/actions/feature-list.json`
   - `.harness/actions/api-contract.json`에서 관련 엔드포인트 확인
   - AC(Acceptance Criteria) 목록을 정확히 파악

2. 코드 생성:
   - AGENTS.md의 IA-MAP에 따라 올바른 디렉토리에 코드 작성
   - AC의 모든 항목을 충족하도록 구현

3. Pre-eval 게이트 (자체):
   - tsc (타입 체크) 실행
   - eslint (린트) 실행
   - 컴파일 에러가 있으면 직접 수정 (Eval에 넘기지 않음)

**Gen 완료 로깅:**
```bash
echo "$(date +'%Y-%m-%d %H:%M') | team-{N} | gen | {FEATURE_ID} done — {변경파일수} files" >> "$HARNESS_ROOT/.harness/progress.log"
```

## Phase 2: Evaluator (독립 평가 — Agent 도구 사용)

**Eval 시작 로깅:**
```bash
echo "$(date +'%Y-%m-%d %H:%M') | team-{N} | eval | {FEATURE_ID} eval start" >> "$HARNESS_ROOT/.harness/progress.log"
bash "$HARNESS_ROOT/scripts/harness-queue-manager.sh" update_phase {FEATURE_ID} eval "$HARNESS_ROOT"
```

코드 생성이 완료되면 **별도 Agent를 생성하여 평가**합니다.
이 Evaluator Agent는 당신(Generator)의 추론 과정을 모릅니다.
오직 코드와 AC만 보고 판단합니다.

```
Agent({
  description: "Eval: {FEATURE_ID}",
  prompt: "<아래 Evaluator 프롬프트>"
})
```

#### Evaluator 프롬프트

```
당신은 독립 Evaluator입니다. Generator가 작성한 코드를 AC 기준으로 냉정하게 평가합니다.
Generator의 의도나 추론 과정은 알 수 없습니다. 오직 코드와 결과만 봅니다.

## 평가 대상
- Feature ID: {FEATURE_ID}
- AC 확인: `jq '.features[] | select(.id == "{FEATURE_ID}").acceptance_criteria' .harness/actions/feature-list.json`

## 평가 기준
1. AC 100% 충족 여부 (부분 통과 = FAIL)
2. api-contract.json과의 일치 여부 (엔드포인트, 요청/응답 스키마)
3. tsc, eslint 통과 여부
4. 보안 취약점 여부 (OWASP Top 10)
5. 기존 코드와의 regression 여부

## 출력 형식
반드시 아래 형식으로 결과를 반환하세요:

VERDICT: PASS 또는 FAIL
SCORE: X.XX / 3.00
EVIDENCE:
- AC-1: [PASS/FAIL] 근거
- AC-2: [PASS/FAIL] 근거
- ...
FEEDBACK: (FAIL인 경우만) 구체적 수정 지시
```

## Phase 3: 결과 처리

Evaluator Agent 결과를 확인합니다:

### PASS인 경우 (VERDICT: PASS, SCORE ≥ 2.80):
```bash
echo "$(date +'%Y-%m-%d %H:%M') | team-{N} | pass | {FEATURE_ID} PASS score={SCORE}" >> "$HARNESS_ROOT/.harness/progress.log"
bash "$HARNESS_ROOT/scripts/harness-queue-manager.sh" pass {FEATURE_ID} "$HARNESS_ROOT"
```
변경 파일 목록과 AC 충족 요약을 Lead에게 반환.

### FAIL인 경우:
```bash
echo "$(date +'%Y-%m-%d %H:%M') | team-{N} | fail | {FEATURE_ID} FAIL #{ATTEMPT} — {사유요약}" >> "$HARNESS_ROOT/.harness/progress.log"
```
1. Evaluator의 FEEDBACK을 읽고 코드를 수정 (Phase 1로 돌아감)
2. 수정 후 다시 Phase 2 (새 Evaluator Agent 생성 — 이전 Eval 컨텍스트 없음)
3. 최대 3회 시도. 3회 모두 FAIL이면:
   ```bash
   echo "$(date +'%Y-%m-%d %H:%M') | team-{N} | fail | {FEATURE_ID} FINAL FAIL after 3 attempts" >> "$HARNESS_ROOT/.harness/progress.log"
   bash "$HARNESS_ROOT/scripts/harness-queue-manager.sh" fail {FEATURE_ID} "$HARNESS_ROOT"
   ```
   실패 사유와 마지막 Eval 결과를 Lead에게 반환.
```

## Step 4: 결과 수집 및 다음 라운드

모든 Team Agent가 완료되면:
1. 각 Agent 반환 메시지에서 PASS/FAIL 확인
2. Queue 상태 재확인: `bash scripts/harness-queue-manager.sh status .`
3. ready 큐에 새로 unblock된 feature가 있으면 → **Step 2로 돌아가서** 추가 팀 생성
4. ready=0, in_progress=0이면 → 최종 결과 보고

## 핵심 원칙

### 자기 의식 편향 차단
- Generator가 자기 코드를 평가하지 않음
- Evaluator는 항상 새 Agent (Generator의 추론 과정을 모름)
- FAIL 후 재시도 시에도 새 Evaluator를 생성 (이전 Eval 기억 없음)

### 중복 방지
- dequeue는 원자적 (lock 사용) — 같은 feature를 두 번 할당 불가
- ready가 0이면 팀을 생성하지 않음

### 격리
- 각 팀은 `isolation: "worktree"`로 독립 코드 복사본에서 작업
- 팀 간 코드 충돌 없음
