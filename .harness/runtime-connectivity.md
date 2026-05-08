# Harness Runtime Connectivity

2026-05-07 기준 `walwal-harness` 6.0 연결 상태를 요약한다.

## Active

| Surface | Status | Notes |
|---|---|---|
| `harness-dispatcher` | active | `config.agents` 와 `UserPromptSubmit` 개념에 연결됨 |
| `harness-brainstorming` | active | canonical id를 `brainstorming` 으로 통일 |
| `harness-planner` | active | `planner(COO)` 로서 `meeting-manager` / `cto` 사이에 연결됨 |
| `generator-backend/frontend` | active | 기존 구현 파이프라인 |
| `evaluator-code-quality/functional/visual` | active | 기존 평가 체인 |
| `/harness-team` `/harness-stop` | active-but-script-dependent | 기본 회사 루프 제어면. queue/tmux scripts 필요 |
| `/harness-solo` | active-but-script-dependent | 비상용 단일 에이전트 fallback. 정상 경로는 아님 |

## Partial

| Surface | Status | Gap |
|---|---|---|
| `harness-conductor` | partial | `dispatcher -> meeting-manager -> planner -> cto -> gen/eval -> cqo -> service-ops -> meeting-manager` 기본 루프를 재작성한다. 다만 daemon, richer meeting scheduling, backlog materialization은 아직 얕다 |
| `harness-meeting-manager` | partial | CEO intake / goal drift / ops batch 회의로 라우팅되며 notice/prep/meeting skeleton 및 decision JSON을 생성한다. 실제 참석자별 LLM prep 자동 실행은 아직 별도 필요 |
| `harness-service-ops` | partial | `service-ops + requested_mode` 방식과 `drift_classification` 필드는 붙었지만 ops-report 실생성/cadence 계산은 부분 구현 |
| `harness-cto` | partial | planner handoff와 ops batch 후 재기획 분기는 붙었지만 실제 hotfix feature materialization은 별도 필요 |
| `harness-cqo` | partial | evaluator 이후 CQO audit 분기는 붙었지만 실제 audit artifact 생성과 회귀 스위트 통합은 별도 필요 |
| `task session isolation` | partial | `harness-next` 가 에이전트별 task-session 문서를 만들고 `UserPromptSubmit` 가 혼선 호출을 hard block 한다. 완전한 별도 runtime session 생성은 아직 외부 실행기가 필요 |

## Documented Only

| Surface | Status | Gap |
|---|---|---|
| `generator-designer` `generator-devops` | documented_only | registry에는 추가했지만 sprint selection 미연결 |
| `evaluator-architecture` `evaluator-security` | documented_only | hardening 축으로만 서술되고 chain 미연결 |

## Patched In This Pass

- `brainstormer` / `brainstorming` 명칭 불일치 제거
- `service-ops/monitor`, `cto-review` 같은 비정규 spawn 명칭을 canonical agent id 기준으로 정리
- `progress.json` 에 `mode`, `mode_decision`, `team_state`, `service_ops.requested_mode` 추가
- `/harness-solo` `/harness-team` 문서가 `mode_decision.user_override` 를 실제로 갱신하도록 정리
- Owner 노출용 `/harness-next` 문구를 내부 handoff 개념으로 교체

## Still Missing For Full 6.0 Runtime

1. daemon 모드와 richer meeting scheduling 구현
2. `PostToolUse:Write` 훅의 실제 실행체
3. Goal 문서(`.harness/actions/goals.md`)와 CTO/CQO/Service-Ops 산출물의 실제 생성 루프
4. `generator-designer` / `generator-devops` / `evaluator-architecture` / `evaluator-security` 의 실전 자동 분배
