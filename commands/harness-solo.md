---
docmeta:
  id: harness-solo
  title: /harness-solo — 비상용 Single-Agent Fallback
  type: input
  createdAt: 2026-04-20T00:00:00Z
  updatedAt: 2026-05-07T00:00:00Z
  source:
    producer: user
    skillId: harness
  inputs:
    - documentId: skill-conductor
      uri: ../skills/conductor/SKILL.md
      relation: output-from
      sections:
        - sourceRange: { startLine: 115, endLine: 145 }   # §7.5 모드 결정 위임 룰 + user_override 채널
          targetRange: { startLine: 17, endLine: 22 }     # 본 명령의 v6.0 override 안내 블록
    - documentId: config-template
      uri: ../assets/templates/config.json
      relation: output-from
      sections:
        - sourceRange: { startLine: 345, endLine: 372 }   # mode_selection 룰 (force_solo_when 등)
          targetRange: { startLine: 17, endLine: 22 }
  tags: [harness, solo-mode, command, override, v6]
---

# /harness-solo — 비상용 Single-Agent Fallback (v6.0+)

> v6.0 의 정상 경로는 회사형 자동 루프입니다. 본 명령은 그 루프를 일시적으로 벗어나는 **비상용 override** 입니다.
>
> **효과**: `progress.json.mode = "solo"` 강제 + `mode_decision.user_override = "solo"` 기록. 현재 sprint 끝까지 유지. 다음 sprint 진입 시 Conductor 가 재자동결정. **Auto 복귀**: 사용자 발화 "auto 로 돌려" 또는 "Conductor 결정으로".

디버깅, 스크립트 장애, 수동 hotfix 같은 예외 상황에서만 사용합니다.
회사 루프에서 전환 시, 진행 중이던 피처의 상태를 보존하고 단일 에이전트 fallback 으로 이어갑니다.

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
jq '.mode = "solo" | .mode_decision.user_override = "solo" | .team_state.active_teams = 0 | .team_state.paused_at = (now | todate)' .harness/progress.json > /tmp/progress_tmp.json && mv /tmp/progress_tmp.json .harness/progress.json
```

**paused → solo 전환 시:**
```bash
jq '.mode = "solo" | .mode_decision.user_override = "solo"' .harness/progress.json > /tmp/progress_tmp.json && mv /tmp/progress_tmp.json .harness/progress.json
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
- **next_agent = "planner"** → Planner 단계가 다음입니다. SessionStart / 내부 handoff가 연결돼 있으면 자동 진입, 아니면 해당 스킬을 수동 호출합니다.
- **next_agent = "generator-backend"** → Backend generator 단계가 다음입니다.
- **next_agent = "generator-frontend"** → Frontend generator 단계가 다음입니다.
- **next_agent = "evaluator-functional"** → Functional evaluator 단계가 다음입니다.
- **next_agent = "evaluator-visual"** → Visual evaluator 단계가 다음입니다.

### Step 4: Solo 모드 진행

각 에이전트는 완료 즉시 **내부 handoff(`harness-next.sh` 또는 SessionStart hook)** 로 다음 에이전트에 넘겨집니다. Owner가 `/harness-next` 를 직접 다룬다는 전제는 6.0 회사 모델과 맞지 않습니다.

**예외 — 사용자 승인 게이트가 있는 단계:**
- **Brainstorming**: brainstorm-spec.md 완성 후 사용자 승인 대기 → 승인 시 내부 handoff
- **Planner**: plan.md / api-contract.json 완성 후 사용자 승인 대기 → 승인 시 내부 handoff

흐름이 멈췄다면 원인은 보통 내부 handoff 스크립트/훅 미설치 또는 `next_agent` 불일치입니다. 이 경우 상태 파일과 hook 설치 상태를 먼저 점검합니다.

feature-queue.json이 존재하는 경우:
- 피처 완료(evaluator PASS) 시 `bash scripts/harness-queue-manager.sh pass {FEATURE_ID} .`를 호출하여 공유 상태 업데이트
- Team 모드로 전환해도 이미 완료된 피처는 skip됨

## 사용 권장 상황

- 프롬프트로 각 에이전트 순차 실행
- 내부 handoff 스크립트 장애 시 응급 복구
- 아주 짧은 수동 hotfix / 상태 수선
- 정상 회사 루프로 복귀: `/harness-team`
