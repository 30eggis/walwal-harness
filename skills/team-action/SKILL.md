---
name: harness-team-action
description: "v4 Agent Teams 가동. feature-queue를 초기화하고 3개 Teammate를 생성하여 Feature 단위 Gen→Eval 병렬 실행을 시작한다. 트리거: '/harness-team-action', 'team 시작', 'agent team 가동', '팀 시작', '팀 가동'"
disable-model-invocation: false
---

# /harness-team-action — Agent Teams 가동

## 전제 조건

- `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` 이 `.claude/settings.json`에 설정되어 있어야 함
- `.harness/actions/feature-list.json`이 존재해야 함 (Planner가 생성)

## 실행 절차

### Step 1: Feature Queue 초기화

먼저 feature-queue.json을 확인/생성합니다:

```bash
if [ ! -f .harness/actions/feature-queue.json ]; then
  bash scripts/harness-queue-manager.sh init .
else
  bash scripts/harness-queue-manager.sh recover .
fi
bash scripts/harness-queue-manager.sh status .
```

### Step 2: Teammate 생성

**아래 내용을 그대로 실행합니다** — 3명의 Teammate를 생성하여 Feature Queue에서 작업을 분배합니다.

`.harness/actions/feature-queue.json`의 `ready` 큐에서 최대 3개 Feature를 가져와 각 Teammate에게 할당합니다.
Teammate가 Feature를 완료하면 queue에서 다음 ready Feature를 가져옵니다.

**Teammate 생성 요청:**

3명의 Teammate를 생성하세요:

1. **team-1** (Generator + Evaluator):
   - `.harness/actions/feature-queue.json`의 `ready` 배열에서 첫 번째 Feature를 가져옴
   - 해당 Feature에 대해: 코드 생성 → `tsc --noEmit` + `eslint` 검증 → AC 기반 기능 평가
   - PASS 시: `bash scripts/harness-queue-manager.sh pass {FEATURE_ID} .` 실행 후 다음 Feature
   - FAIL 시: 최대 3회 재시도, 3회 실패 시 `bash scripts/harness-queue-manager.sh fail {FEATURE_ID} .`
   - AGENTS.md의 파일 소유권 규칙 준수

2. **team-2** (동일 역할): ready 배열에서 두 번째 Feature

3. **team-3** (동일 역할): ready 배열에서 세 번째 Feature

**각 Teammate 공통 규칙:**
- `.harness/actions/feature-list.json`에서 자신의 Feature 정보(AC, depends_on) 읽기
- `.harness/actions/api-contract.json`에서 관련 엔드포인트 확인
- `CONVENTIONS.md` 존재 시 준수
- Feature 완료 시 `feature-list.json`의 해당 Feature `passes`에 `["generator-frontend", "evaluator-functional"]` 추가
- 다른 Teammate의 Feature 코드를 수정하지 않음
- 완료/실패 시 Lead에게 `SendMessage`로 결과 보고

## 실행 후

- Lead(이 세션)는 **오케스트레이터** — Teammate 진행 모니터링
- 상태 확인: `bash scripts/harness-queue-manager.sh status .`
- 실패 Feature 재큐: `bash scripts/harness-queue-manager.sh requeue F-XXX .`
- 중지: `/harness-team-stop`
