---
docmeta:
  id: harness-next
  title: /harness-next — 다음 에이전트로 자동 진행
  type: input
  createdAt: 2026-04-27T00:00:00Z
  updatedAt: 2026-04-27T00:00:00Z
  source:
    producer: user
    skillId: harness
  inputs: []
  tags: [harness, solo-mode, orchestration, command]
---

# /harness-next — 다음 에이전트로 자동 진행

현재 에이전트의 완료 상태(`progress.json`)를 읽고 파이프라인 시퀀스에 따라 **다음 에이전트로 자동 진행**합니다. Solo 모드에서 매 단계마다 사용자가 직접 bash 명령을 칠 필요 없이 자동 핸드오프합니다.

## 실행 절차

### Step 1: harness-next.sh 실행

```bash
bash scripts/harness-next.sh .
```

스크립트가 수행하는 작업:
- `progress.json` 읽기 → `current_agent`, `agent_status`, `next_agent` 확인
- Pre-Eval Gate (lint/type/test) 실행 — Generator → Evaluator 전환 시
- Artifact prerequisite 검증
- `.harness/handoff.json` 생성 (다음 에이전트 컨텍스트)
- 에스컬레이션 체크 (3회 실패 시 → Planner)
- 마지막 에이전트면 자동 archive 실행

### Step 2: handoff.json 읽고 다음 에이전트 호출

```bash
cat .harness/handoff.json | jq '{from, to, sprint, prompt, model, thinking_mode, failure_context}'
```

`to` 필드 값에 따라 자동으로 해당 스킬을 호출합니다:

| `to` 값 | 호출할 스킬 |
|---------|------------|
| `dispatcher` | `harness-dispatcher` |
| `brainstorming` | `harness-brainstorming` |
| `planner` | `harness-planner` |
| `generator-backend` | `harness-generator-backend` |
| `generator-frontend` | `harness-generator-frontend` |
| `generator-frontend-flutter` | `harness-generator-frontend-flutter` |
| `evaluator-code-quality` | `harness-evaluator-code-quality` |
| `evaluator-functional` | `harness-evaluator-functional` |
| `evaluator-functional-flutter` | `harness-evaluator-functional-flutter` |
| `evaluator-visual` | `harness-evaluator-visual` |
| `archive` | (자동 처리됨, 새 dispatch 대기) |
| `null` (blocked) | 멈춤. 사용자에게 차단 사유 안내 |

### Step 3: 호출된 스킬이 handoff.json을 컨텍스트로 사용

`handoff.json.prompt` 에 thinking mode, sprint, 실패 컨텍스트가 포함되어 있으므로 그대로 사용합니다.

## 사용 시점

- **자동 호출** (스킬이 알아서):
  - Dispatcher, Generator-*, Evaluator-* 완료 직후 (사용자 검토 게이트 없음)
  - Planner / Brainstorming은 **사용자 승인 후** 스킬이 호출
- **수동 호출** (사용자가 직접 입력):
  - 흐름이 멈춰서 다시 진행시키고 싶을 때
  - Eval FAIL 후 재시도를 시작할 때
  - `/harness-stop` 이후 재개

## Team 모드와의 관계

Team 모드는 Lead worker가 자체 오케스트레이션 루프를 돌리므로 `/harness-next`가 필요 없습니다. 이 명령은 **Solo 모드 전용**입니다.

## 관련 명령

- `/harness-solo` — Solo 모드 진입/전환
- `/harness-team` — Team 모드 진입
- `/harness-stop` — 진행 중단
