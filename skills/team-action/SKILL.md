---
name: harness-team-action
description: "v4 Agent Teams 가동. feature-queue를 초기화하고 3개 Teammate를 생성하여 Feature 병렬 실행. 트리거: '/harness-team-action', 'team 시작', '팀 가동'"
disable-model-invocation: false
---

# /harness-team-action — Agent Teams 가동

## Step 1: Queue 초기화

```bash
if [ ! -f .harness/actions/feature-queue.json ]; then bash scripts/harness-queue-manager.sh init .; else bash scripts/harness-queue-manager.sh recover .; fi && bash scripts/harness-queue-manager.sh status .
```

## Step 2: Teammate 생성

Queue의 `ready` 배열에서 Feature를 읽고, **3명의 Teammate를 즉시 생성**하세요.

각 Teammate에게 전달할 지시:
- `.harness/actions/feature-queue.json`의 ready에서 Feature 1개를 담당
- 해당 Feature의 코드를 생성하고, AC(Acceptance Criteria)를 기준으로 자체 검증
- PASS 시: `bash scripts/harness-queue-manager.sh pass {FEATURE_ID} .` 실행
- FAIL 시: 재시도 (최대 3회), 3회 실패 시 `bash scripts/harness-queue-manager.sh fail {FEATURE_ID} .`
- 완료 후 Lead에게 결과 보고

**Teammate 이름**: team-1, team-2, team-3
