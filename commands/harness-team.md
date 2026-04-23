---
docmeta:
  id: harness-team
  title: /harness-team — Team Mode 시작/재개
  type: input
  createdAt: 2026-04-20T00:00:00Z
  updatedAt: 2026-04-20T00:00:00Z
  source:
    producer: user
    skillId: harness
  inputs: []
  tags: [harness, team-mode, tmux, command]
---

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
bash scripts/harness-tmux.sh --team --force-tmux
```

**`--force-tmux` 필수**: iTerm2 감지 경로는 백그라운드에 iTerm2가 떠 있기만 해도 활성화되어 AppleScript 실패 시 팀 레이아웃이 조용히 사라짐. Team Mode는 항상 tmux로 강제하여 재현 가능한 레이아웃을 보장.

### Step 2.5: Worker Pre-flight Bundle 빌드 (v5.6.6+)

Worker 는 plain Agent 로 실행되어 SKILL.md Startup 체크리스트를 자동 주입받지 못한다. Lead 가 Worker spawn 직전에 **역할별 바인딩 문서를 프롬프트에 직접 주입**한다. 이렇게 하면 "Worker 가 읽어야 함" → "이미 읽은 상태로 시작" 으로 전환되어 스킵이 구조적으로 불가능해진다.

```bash
# Generator-{be|fe} / Evaluator-{functional|visual|code-quality} 별 번들 빌드
build_preflight_bundle() {
  local role="$1"   # generator-frontend | generator-backend | evaluator-functional | ...
  local hroot="$2"  # HARNESS_ROOT (worktree 가 아닌 원본 루트)
  {
    echo "===== ROOT CONVENTIONS.md ====="
    [ -f "$hroot/CONVENTIONS.md" ] && cat "$hroot/CONVENTIONS.md" || echo "(none)"
    echo
    echo "===== AGENTS.md ====="
    [ -f "$hroot/AGENTS.md" ] && cat "$hroot/AGENTS.md" || echo "(none)"
    echo
    echo "===== .harness/conventions/shared.md ====="
    [ -f "$hroot/.harness/conventions/shared.md" ] && cat "$hroot/.harness/conventions/shared.md" || echo "(empty)"
    echo
    echo "===== .harness/conventions/$role.md ====="
    [ -f "$hroot/.harness/conventions/$role.md" ] && cat "$hroot/.harness/conventions/$role.md" || echo "(empty)"
    echo
    echo "===== .harness/gotchas/$role.md ====="
    [ -f "$hroot/.harness/gotchas/$role.md" ] && cat "$hroot/.harness/gotchas/$role.md" || echo "(empty)"
    echo
    echo "===== .harness/memory.md ====="
    [ -f "$hroot/.harness/memory.md" ] && cat "$hroot/.harness/memory.md" || echo "(empty)"
  }
}
```

Worker/내부 Evaluator Agent 프롬프트 상단에 이 번들 출력을 `## Binding Rules (pre-loaded)` 섹션으로 삽입한다. Worker 는 이를 **추가 조회 없이 이미 적용되는 규범**으로 취급한다.

### Step 3: 초기 Worker 생성 (Auto-Dispatch)

**v5.6.4+**: 개별 dequeue 대신 **`auto-dispatch`** 한 번으로 모든 idle team 에 ready feature 를 원자적으로 배정합니다. 의존성 없는 작업은 병렬로 즉시 시작됩니다.

```bash
# 모든 idle team ↔ ready feature 쌍을 한 번에 배정
bash scripts/harness-queue-manager.sh auto-dispatch .
# → [{"team":1,"feature":"F-001"},{"team":2,"feature":"F-002"},{"team":3,"feature":"F-003"}]
```

출력(JSON 배열)을 파싱해 각 `{team, feature}` 쌍마다 **background Agent** 를 생성합니다.

> **Fallback**: 단일 팀만 배정하려면 `dequeue <team_id>` 도 계속 사용 가능.

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

  1. Worker 결과 분석 (반환 메시지 첫 줄 태그로 분기):
     - `PASS` → Step 4a (Merge + Unblock)
     - `FAIL` (재시도 가능) → Step 4b (Retry)
     - `RATE_LIMIT` → Step 4c (Rate-Limit Hold, 10m probe)
     - `ESCALATED` → 사용자에게 알림, 해당 팀 유휴

  2. **Auto-Dispatch (필수)** — worker 완료 직후 idle 이 된 팀뿐 아니라
     모든 idle team 에 ready feature 를 즉시 재배정:

     bash scripts/harness-queue-manager.sh auto-dispatch .

     반환된 모든 (team, feature) 쌍에 대해 즉시 background Agent 생성.
     한 작업의 merge 지연이 다른 idle team 을 놀게 두지 않는다.

  3. Queue 상태 확인 (로그용):
     bash scripts/harness-queue-manager.sh idle-slots .
     bash scripts/harness-queue-manager.sh status .

  4. auto-dispatch 가 pairs=[] (= ready 도 0, idle 도 0 혹은 idle 만 있고 ready 가 0) 이면:
     → ready=0 AND in_progress>0 → 다른 worker 완료 대기. LOOP 계속
     → ready=0 AND in_progress=0 → Sprint 전환 시도:
       bash scripts/harness-queue-manager.sh next-sprint .
       - "Advancing" → auto-dispatch 다시 실행 (Step 2로 복귀)
       - "ALL SPRINTS COMPLETE" → 최종 보고. LOOP 종료.
       - "Cannot advance" → 실패 피처 사용자 개입 요청. LOOP 종료.
```

**핵심 원칙**: worker 완료 알림 → **즉시 auto-dispatch** → 반환된 모든 쌍에 대해 병렬 spawn. 팀 간 의존성이 없으면 idle 시간은 "Agent 생성에 걸리는 수초" 로 수렴한다.

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

#### Step 4c: Rate-Limit Hold (토큰 한도 대응 · v5.6.7+)

Worker 반환 첫 줄이 `RATE_LIMIT` 으로 시작하면 Lead 는 **에러 아닌 hold 모드**로 전환한다. 나머지 Worker 들은 자연 완료까지 계속 실행되고, 그 결과도 RATE_LIMIT 이면 합쳐서 hold 상태에 누적된다.

```bash
# 1) Checkpoint 기록 (current in_progress + ready 스냅샷 저장)
bash "$HARNESS_ROOT/scripts/harness-queue-manager.sh" hold rate_limit 600 .

# 2) 로그 + tmux pane 타이틀 변경
echo "$(date +'%Y-%m-%d %H:%M') | lead | hold | rate-limit detected, pausing 10m" >> .harness/progress.log
tmux rename-window "⏸ HOLD (resume ~$(date -v+10M +%H:%M 2>/dev/null || date -d '+10 min' +%H:%M))" 2>/dev/null || true

# 3) 실패한 feature 는 requeue (WIP worktree 는 유지 — merge 없이 재사용)
bash "$HARNESS_ROOT/scripts/harness-queue-manager.sh" requeue {FEATURE_ID} .
```

4) **ScheduleWakeup 으로 10분 뒤 재진입 스케줄**:
```
ScheduleWakeup({
  delaySeconds: 600,
  prompt: "/harness-team resume",
  reason: "rate-limit hold — 10m probe"
})
```

5) Lead LOOP return (중단 아님 — wake-up 이 재진입 트리거).

**Wake-up 재진입 시 Lead 동작** (`/harness-team resume` 처리):

```bash
# Probe: claude CLI 가 실제로 응답하는지 최소 호출로 확인
bash "$HARNESS_ROOT/scripts/harness-queue-manager.sh" resume-probe .
# 종료 코드: 0=clear, 1=still held, 2=escalated(>12h)
```

- **0 (clear)** → 체크포인트 삭제됨. 즉시 `auto-dispatch` 실행 → Step 4 LOOP 복귀.
- **1 (still held)** → 다시 `ScheduleWakeup(600, "/harness-team resume", "rate-limit still held — cycle N")` 스케줄. hold_count 증가.
- **2 (escalated)** → 72 사이클(12시간) 초과. 사용자 개입 알림 후 LOOP 종료. 체크포인트 파일 (`.harness/actions/team-checkpoint.json`) 에 전체 상태가 남아있으므로 사용자가 수동 복구 가능.

**핵심 원칙**: 토큰 리밋은 "실패"가 아닌 "일시 정지". 진행 중이던 worktree/queue 상태는 그대로 보존되고, 10분 간격 probe 로 해제 즉시 이어서 진행한다. Session 을 닫아도 이어지길 원한다면 `ScheduleWakeup` 대신 `schedule` 스킬(CronCreate) 로 cron-backed 재시도 설정 가능.

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

## Binding Rules (pre-loaded — 스킵 금지, 이미 적용됨)

Lead 가 Step 2.5 에서 build_preflight_bundle 로 생성한 번들이 아래에 주입됩니다.
당신은 이 규칙을 이미 읽은 상태로 시작합니다. 추가 조회 불필요:

{PREFLIGHT_BUNDLE}

**작업 시작 전 필수 출력**: 위 번들에서 이번 Feature 작업에 **적용되는 규칙**을 3~8 줄로 요약한 뒤 진행하라. 비어있으면 "(empty)" 로 명시. 이 요약 없이 Phase 1 로 진입하면 Self-FAIL 처리하고 재시작한다. 내부 Evaluator Agent 를 생성할 때도 같은 번들을 `{PREFLIGHT_BUNDLE}` 자리에 그대로 전달하라 (Evaluator 도 plain Agent 이므로 자동주입 없음).

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

| ACTION | 사용 시점 | DETAIL 예시 (필수 포함 정보) |
|--------|-----------|------------------------------|
| `gen-start`  | Gen Phase 시작 (1회) | `F-001 "사용자 회원가입 API" start — goal=POST /users, 6 AC` — **Feature 제목+목표** 포함 필수 |
| `gen-plan`   | 작업 계획 공표 (1회) | `plan: create controller+service+dto, wire module, add 3 unit tests` |
| `gen-read`   | 소스/계약 읽기 (매 파일) | `read api-contract.json#/paths/~1users` |
| `gen-write`  | 파일 생성/수정 (**매 파일**) | `write apps/service-user/src/user.controller.ts (+82 LOC, create)` — **경로+LOC+action(create/edit/delete)** 필수 |
| `gen-test`   | 자체 게이트 | `tsc OK · eslint 0 warn · jest 12/12 pass` |
| `gen-done`   | Gen Phase 종료 | `F-001 done — 5 files: controller.ts, service.ts, dto.ts, module.ts, spec.ts (total +142 LOC)` — **변경 파일 전체 나열** 필수 |
| `eval-start` | Evaluator 시작 | `F-001 evaluating — 6 ACs + regression + security` — **AC 개수+검증 축** 필수 |
| `eval-ac`    | AC 본문 선언 (**매 AC 시작 시 1회**) | `AC-3: "POST /users returns 201 with created user id"` — **AC 원문** 필수 |
| `eval-check` | AC 검증 수행/증거 | `AC-3 [PASS] — curl POST /users → 201, body.id matches` — **판정+증거** 필수 |
| `eval-gate`  | 자동 게이트 | `gate: tsc OK, eslint OK, security scan 0 high` |
| `eval-done`  | Eval 결과 | `F-001 VERDICT=PASS SCORE=2.95/3.00 (AC 6/6, gates OK)` |
| `result`     | PASS 확정 (**SCORE ≥ 2.80**) | `F-001 PASS score=2.95` |
| `fail`       | FAIL 확정 | `F-001 FAIL #1 — AC-2 "email uniqueness" missing DB constraint` |

**중요: 로깅 가독성 규칙 (필수)**
1. `gen-start`에는 반드시 Feature **제목과 목표**를 함께 기록 (무슨 일을 시작하는가 명확히).
2. `gen-write`는 **변경되는 파일마다 1건씩** 기록. 묶어서 요약 금지 ("2 files edit" 같은 표기 금지).
3. `gen-done`은 **변경 파일 전체 목록**을 나열. "(2 files)" 같은 개수만 기록 금지.
4. `eval-ac`로 **AC 원문을 먼저 선언**한 뒤 `eval-check`로 증거/판정 기록. "AC-1 count=0" 같은 수치 단독 기록 금지.
5. `result` PASS는 **SCORE ≥ 2.80** 인 경우에만 기록. score=1.00인데 PASS로 기록하는 실수 금지.

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

## 실시간 로깅 (필수)

평가 진행 상황을 실시간으로 기록합니다. **각 AC 검증마다 반드시 logev를 호출**하세요.

```bash
HARNESS_ROOT=$(git worktree list | head -1 | awk '{print $1}')
LOG=\"$HARNESS_ROOT/.harness/progress.log\"
logev() { echo \"$(date +'%Y-%m-%d %H:%M') | team-{N} | $1 | $2\" >> \"$LOG\"; }
```

**로깅 시점:**
1. 평가 시작 즉시: `logev eval-start \"{FEATURE_ID} evaluating — {AC수} ACs\"`
2. 각 AC 검증 후: `logev eval-check \"{FEATURE_ID} AC-{N}: [PASS/FAIL] {근거 요약}\"`
3. tsc/eslint 검증 후: `logev eval-check \"{FEATURE_ID} gate: tsc {OK/FAIL}, eslint {OK/FAIL}\"`
4. 최종 판정: `logev eval-done \"{FEATURE_ID} VERDICT={PASS/FAIL} SCORE={X.XX}/3.00\"`

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

### RATE_LIMIT (토큰 한도 감지 시 — v5.6.7+)

Gen 또는 Eval Phase 중 429 / "rate_limit" / "quota" / "overloaded_error" / "token limit" / "usage limit" 메시지를 만나면:

```bash
logev hold "{FEATURE_ID} rate-limit hit — returning RATE_LIMIT to Lead"
```
Lead에게 반환 **첫 줄에 반드시 `RATE_LIMIT` 태그 포함**:
`RATE_LIMIT | {FEATURE_ID} | phase={gen|eval} | attempt={N} | err={원문요약}`

작업을 **포기하지 말고** 현재까지의 변경분을 worktree 에 그대로 commit (WIP). Lead 가 hold 해제 후 같은 worktree 로 resume.
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
