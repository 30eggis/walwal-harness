# /harness-team — Team Mode 시작/재개

Planner가 완료한 feature-list.json의 피처들을 최대 3개 팀이 병렬로 Gen→Eval 사이클을 수행합니다.

## 프로세스 설계 원칙

1. **Worker = 1 Feature Only**: 각 Worker는 단일 피처만 처리하고 반환. 자동 다음 피처 획득하지 않음.
2. **Lead = Orchestration Loop**: Lead가 Worker 완료 알림을 받고, merge → unblock 확인 → 새 Worker 생성을 반복.
3. **Background Agent**: Worker를 `run_in_background: true`로 생성하여 Lead가 개별 완료에 즉시 반응.
4. **Merge 후 재투입**: Worker PASS → Lead가 worktree merge → queue pass (unblock) → 새 Worker 생성.

## 실행 절차

### Step 0: 선행 조건 확인

```bash
[ -f .harness/actions/feature-list.json ] && [ -f .harness/actions/api-contract.json ] && echo "READY" || echo "NOT_READY"
```

- **NOT_READY** → "Planner가 먼저 완료되어야 합니다." 안내 후 중단.
- **READY** → Step 1로 진행.

### Step 1: 모드 전환 + Queue 초기화

```bash
# progress.json에 mode=team 설정
jq '.mode = "team" | .team_state.active_teams = 3 | .team_state.paused_at = null' .harness/progress.json > /tmp/progress_tmp.json && mv /tmp/progress_tmp.json .harness/progress.json

# Queue 초기화 또는 복구
if [ ! -f .harness/actions/feature-queue.json ]; then
  bash scripts/harness-queue-manager.sh init .
else
  bash scripts/harness-queue-manager.sh recover .
fi

# Queue 상태 확인
bash scripts/harness-queue-manager.sh status .
```

### Step 2: tmux Studio 레이아웃 구축

```bash
bash scripts/harness-tmux.sh --team
```

### Step 3: 초기 Worker 생성

Queue에서 ready 피처를 최대 3개 dequeue하고, **각각 background Agent로 생성**합니다.

```bash
# 각 팀마다 dequeue
bash scripts/harness-queue-manager.sh dequeue 1 .
bash scripts/harness-queue-manager.sh dequeue 2 .
bash scripts/harness-queue-manager.sh dequeue 3 .
```

dequeue 성공한 피처마다 **background Agent**를 생성합니다:

```
Agent({
  description: "Team-{N}: {FEATURE_ID}",
  isolation: "worktree",
  run_in_background: true,
  prompt: "<아래 Team Worker 프롬프트>"
})
```

**중요: `run_in_background: true`로 생성**하면 Lead가 블록되지 않고, 각 Worker 완료 시 알림을 받습니다.

초기 생성 후 **Step 4 (Orchestration Loop)**로 진입합니다.

### Step 4: Orchestration Loop (Lead 핵심 루프)

**이 루프가 Team Mode의 핵심입니다. 모든 Sprint가 완료될 때까지 반복합니다.**

```
ORCHESTRATION LOOP:

  Background Agent 완료 알림을 받으면:

  1. Worker 결과 분석:
     - PASS인 경우 → Step 4a (Merge + Unblock)
     - FAIL (재시도 가능)인 경우 → Step 4b (Retry)
     - ESCALATED인 경우 → 사용자에게 알림, 해당 팀 유휴

  2. Queue 상태 확인:
     bash scripts/harness-queue-manager.sh status .

  3. ready > 0 이면:
     → 새 Worker를 background Agent로 생성 (Step 3과 동일)
     → LOOP 계속

  4. ready = 0 AND in_progress > 0 이면:
     → 다른 Worker 완료를 대기
     → LOOP 계속

  5. ready = 0 AND in_progress = 0 이면:
     → Sprint 전환 시도:
       bash scripts/harness-queue-manager.sh next-sprint .
       - "Advancing" → Step 3으로 (새 Sprint 피처 dequeue + Worker 생성)
       - "ALL SPRINTS COMPLETE" → 최종 보고. LOOP 종료.
       - "Cannot advance" → 실패 피처 사용자 개입 요청. LOOP 종료.
```

#### Step 4a: Merge + Unblock (PASS 처리)

Worker가 PASS로 반환되면:

1. **Worktree branch 확인**: Agent 반환 결과에서 worktree path와 branch 확인
2. **Main에 merge**:
   ```bash
   git merge {BRANCH_NAME} --no-edit
   ```
   - 충돌 시: 자동 해결 시도 → 실패 시 사용자 개입 요청
3. **Queue 업데이트** (unblock 포함):
   ```bash
   bash scripts/harness-queue-manager.sh pass {FEATURE_ID} .
   ```
   → 의존 피처가 자동으로 blocked → ready로 전이
4. **진행 로그**:
   ```bash
   echo "$(date +'%Y-%m-%d %H:%M') | lead | pass | {FEATURE_ID} merged + unblocked deps" >> .harness/progress.log
   ```

#### Step 4b: Retry (FAIL 처리)

Worker가 FAIL (재시도 가능)로 반환되면:

1. 시도 횟수 확인 (최대 5회)
2. 5회 미만:
   ```bash
   bash scripts/harness-queue-manager.sh requeue {FEATURE_ID} .
   bash scripts/harness-queue-manager.sh dequeue {TEAM_NUMBER} .
   ```
   → 새 background Agent Worker 생성 (이전 Eval feedback 포함)
3. 5회 도달:
   ```bash
   bash scripts/harness-queue-manager.sh fail {FEATURE_ID} .
   echo "$(date +'%Y-%m-%d %H:%M') | lead | escalate | {FEATURE_ID} ESCALATED after 5 attempts" >> .harness/progress.log
   ```
   → 사용자 개입 요청

---

## Team Worker 프롬프트

```
당신은 Harness Team-{N} 워커입니다. **단일 Feature**에 대해 Gen→Eval 사이클을 수행합니다.
완료 후 결과를 반환합니다. 다음 Feature는 Lead가 할당합니다.

## 할당된 Feature
- Feature ID: {FEATURE_ID}
- 프로젝트 루트: 현재 디렉토리 (worktree 복사본)
- 하네스 루트: 메인 프로젝트 루트 (worktree가 아닌 원본)

## 실시간 로깅 (필수)

**로깅 설정:**
```bash
HARNESS_ROOT=$(git worktree list | head -1 | awk '{print $1}')
LOG="$HARNESS_ROOT/.harness/progress.log"
logev() { echo "$(date +'%Y-%m-%d %H:%M') | team-{N} | $1 | $2" >> "$LOG"; }
```

| ACTION | 사용 시점 | DETAIL 예시 |
|--------|-----------|-------------|
| `gen-start`  | Gen Phase 시작 | `F-001 start — 6 AC` |
| `gen-read`   | 소스/계약 읽기 | `read api-contract.json (POST /users)` |
| `gen-write`  | 파일 생성/수정 | `write apps/service-user/src/user.controller.ts` |
| `gen-test`   | 자체 게이트 | `tsc OK · eslint 0 · jest 12/12` |
| `gen-done`   | Gen Phase 종료 | `F-001 done — 5 files, 142 LOC` |
| `eval-start` | Evaluator 시작 | `F-001 spawning evaluator` |
| `eval-check` | AC 검증 | `AC-3 — verify POST /users returns 201` |
| `eval-done`  | Eval 결과 | `verdict=PASS score=2.95` |
| `result`     | PASS 확정 | `F-001 PASS` |
| `fail`       | FAIL 확정 | `FAIL #1 — AC-2 missing` |

**queue phase 업데이트:**
```bash
bash "$HARNESS_ROOT/scripts/harness-queue-manager.sh" update_phase {FEATURE_ID} {PHASE} "$HARNESS_ROOT"
```

## Phase 1: Generator (코드 생성)

```bash
logev gen-start "{FEATURE_ID} start"
bash "$HARNESS_ROOT/scripts/harness-queue-manager.sh" update_phase {FEATURE_ID} gen "$HARNESS_ROOT"
```

1. Feature 정보 확인 (feature-list.json, api-contract.json)
2. 코드 생성 (AGENTS.md IA-MAP 준수, AC 전체 충족)
3. Pre-eval 게이트 (tsc, eslint — 에러 있으면 직접 수정)

```bash
logev gen-done "{FEATURE_ID} done — {파일수} files"
```

## Phase 2: Evaluator (독립 평가)

```bash
logev eval-start "{FEATURE_ID} spawning evaluator"
bash "$HARNESS_ROOT/scripts/harness-queue-manager.sh" update_phase {FEATURE_ID} eval "$HARNESS_ROOT"
```

**별도 Agent 생성** (Generator의 추론 과정을 모르는 독립 평가):

```
Agent({
  description: "Eval: {FEATURE_ID}",
  prompt: "당신은 독립 Evaluator입니다. Generator가 작성한 코드를 AC 기준으로 냉정하게 평가합니다.
Generator의 의도나 추론 과정은 알 수 없습니다. 오직 코드와 결과만 봅니다.

## 평가 대상
- Feature ID: {FEATURE_ID}
- AC: jq '.features[] | select(.id == \"{FEATURE_ID}\").acceptance_criteria' .harness/actions/feature-list.json

## 평가 기준
1. AC 100% 충족 (부분 통과 = FAIL)
2. api-contract.json 일치
3. tsc/eslint 통과
4. OWASP Top 10 보안
5. Regression 여부

## 출력 형식
VERDICT: PASS 또는 FAIL
SCORE: X.XX / 3.00
EVIDENCE:
- AC-1: [PASS/FAIL] 근거
- ...
FEEDBACK: (FAIL만) 구체적 수정 지시"
})
```

## Phase 3: 결과 처리 + 반환

### PASS (SCORE >= 2.80):
```bash
logev result "{FEATURE_ID} PASS score={SCORE}"
```
Lead에게 반환: `PASS | {FEATURE_ID} | score={SCORE} | files={변경파일목록}`

### FAIL (재시도 가능):
```bash
logev fail "{FEATURE_ID} FAIL #{ATTEMPT} — {사유}"
```
시도 횟수가 5회 미만이면:
- Evaluator FEEDBACK으로 코드 수정 → Phase 1로 돌아감 (같은 Worker 내에서 재시도)
- 새 Evaluator Agent 생성 (이전 Eval 기억 없음)

5회 모두 FAIL:
```bash
logev fail "{FEATURE_ID} FINAL FAIL after 5 attempts"
```
Lead에게 반환: `ESCALATED | {FEATURE_ID} | attempts=5 | last_feedback={마지막_피드백}`
```

---

## 핵심 원칙

### Worker = 1 Feature Only
- Worker는 할당된 단일 피처만 처리하고 반환
- 다음 피처 dequeue, next-sprint 시도는 **Lead만** 수행
- Worktree는 해당 피처 전용 — 다른 피처 작업 금지

### Lead = Merge + Orchestrate
- Worker PASS 시 Lead가 branch merge → queue pass → unblock
- 새로 ready된 피처에 즉시 Worker 재생성
- Sprint 전환도 Lead가 판단

### Background Agent로 비차단 실행
- `run_in_background: true`로 Worker 생성
- Lead가 각 Worker 완료에 즉시 반응
- 3팀이 서로 다른 속도로 작업해도 유휴 팀 즉시 재활용

### 자기 의식 편향 차단
- Evaluator는 항상 새 Agent (Generator의 추론 과정 모름)
- FAIL 후 재시도 시에도 새 Evaluator 생성

### 에스컬레이션 (5회 초과)
- 5회 연속 FAIL 시 사용자 개입 요청
- 해당 피처는 failed 상태로 남음
- 다른 피처는 계속 진행 (의존하지 않는 경우)
