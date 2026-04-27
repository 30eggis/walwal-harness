---
docmeta:
  id: harness-solo
  title: /harness-solo — Solo Mode 시작/전환
  type: input
  createdAt: 2026-04-20T00:00:00Z
  updatedAt: 2026-04-27T00:00:00Z
  source:
    producer: user
    skillId: harness
  inputs: []
  tags: [harness, solo-mode, command]
---

# /harness-solo — Solo Mode 시작/전환

프롬프트 기반으로 하네스 파이프라인을 순차 진행합니다.
Team 모드에서 전환 시, 진행 중이던 피처의 상태를 보존하고 Solo로 이어갑니다.

## 실행 절차

### Step 1: 현재 모드 확인 + 전환

```bash
# 현재 mode 읽기
MODE=$(jq -r '.mode // "solo"' .harness/progress.json 2>/dev/null)
echo "현재 모드: $MODE"
```

**team → solo 전환 시:**
```bash
# in_progress features를 ready로 복구
bash scripts/harness-queue-manager.sh recover .

# mode를 solo로 설정
jq '.mode = "solo" | .team_state.active_teams = 0 | .team_state.paused_at = (now | todate)' .harness/progress.json > /tmp/progress_tmp.json && mv /tmp/progress_tmp.json .harness/progress.json
```

**paused → solo 전환 시:**
```bash
jq '.mode = "solo"' .harness/progress.json > /tmp/progress_tmp.json && mv /tmp/progress_tmp.json .harness/progress.json
```

### Step 2: 현재 진행 상태 표시

```bash
# progress.json 상태 확인
cat .harness/progress.json | jq '{mode, sprint, current_agent, agent_status, next_agent}'

# feature-queue.json이 있으면 남은 피처 표시
if [ -f .harness/actions/feature-queue.json ]; then
  echo "=== Feature Queue ==="
  bash scripts/harness-queue-manager.sh status .
fi
```

### Step 3: 다음 에이전트 안내

progress.json의 `next_agent` 필드를 확인하여 다음 단계를 안내합니다:

- **next_agent = "dispatcher"** → "프롬프트로 요구사항을 입력하면 자동으로 dispatcher가 분석합니다."
- **next_agent = "planner"** → "/harness-planner 를 호출하거나, 계획을 요청하세요."
- **next_agent = "generator-backend"** → "/harness-generator-backend 를 호출하세요."
- **next_agent = "generator-frontend"** → "/harness-generator-frontend 를 호출하세요."
- **next_agent = "evaluator-functional"** → "/harness-evaluator-functional 를 호출하세요."
- **next_agent = "evaluator-visual"** → "/harness-evaluator-visual 를 호출하세요."

### Step 4: Solo 모드 진행

각 에이전트는 완료 즉시 **`/harness-next` 슬래시 명령을 자동 호출** 하여 다음 에이전트로 핸드오프합니다 (사용자가 매번 bash 명령을 칠 필요 없음).

**예외 — 사용자 승인 게이트가 있는 단계:**
- **Brainstorming**: brainstorm-spec.md 완성 후 사용자 승인 대기 → 승인 시 자동 `/harness-next`
- **Planner**: plan.md / api-contract.json 완성 후 사용자 승인 대기 → 승인 시 자동 `/harness-next`

흐름이 멈췄거나 수동으로 다음 단계를 트리거하고 싶으면 사용자가 직접 `/harness-next` 입력 가능.

feature-queue.json이 존재하는 경우:
- 피처 완료(evaluator PASS) 시 `bash scripts/harness-queue-manager.sh pass {FEATURE_ID} .`를 호출하여 공유 상태 업데이트
- Team 모드로 전환해도 이미 완료된 피처는 skip됨

## Solo 모드에서 가능한 작업

- 프롬프트로 각 에이전트 순차 실행
- 코드 직접 수정 및 디버깅
- 피처 단위 작업 선택
- Team 모드로 언제든 전환: `/harness-team`
