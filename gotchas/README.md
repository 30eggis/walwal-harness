# Gotchas — Agent Mistake Registry

> 이 디렉토리는 각 에이전트가 반복하는 실수를 누적 기록합니다.
> Dispatcher가 사용자의 실수 지적을 감지하면 해당 에이전트의 gotchas 파일에 추가합니다.
> 각 에이전트는 세션 시작 시 자신의 gotchas 파일을 읽고 같은 실수를 반복하지 않습니다.

## 파일 구조

```
.harness/gotchas/
├── README.md                      # 이 파일 (형식·관리 규칙)
│
├── conductor.md                   # Conductor (자율 실행 엔진)
├── dispatcher.md                  # Dispatcher (CEO)
├── meeting-manager.md             # Meeting-Manager (회의 사회)
├── planner.md                     # Planner (COO + HR)
├── cto.md                         # CTO (Gen 총괄)
├── cqo.md                         # CQO (Eval 총괄)
├── service-ops.md                 # Service-Ops (운용)
│
├── coo-developer.md               # COO Hypothesis Cell — Developer
├── documentationer.md             # COO Hypothesis Cell — Documentationer
│
├── generator-backend.md           # Generator-Backend
├── generator-frontend.md          # Generator-Frontend
├── generator-designer.md          # Generator-Designer
├── generator-devops.md            # Generator-DevOps
│
├── evaluator-code-quality.md      # Eval-Code-Quality
├── evaluator-functional.md        # Eval-Functional
├── evaluator-visual.md            # Eval-Visual
├── evaluator-architecture.md      # Eval-Architecture
├── evaluator-security.md          # Eval-Security
│
└── generator-backend-<stack>.md   # 스택별 가드 (예: -laravel)
```

## 항목 형식

```markdown
### [G-NNN] 간결한 제목  <!-- rule_id: <unique-key> -->
- **Status**: unverified | verified | resolved
- **Date**: YYYY-MM-DD
- **Source**: <작성 주체>        (예: "evaluator-functional:F-003" / "dispatcher:manual" / "meeting:M-...:track-2")
- **Trigger**: 사용자가 한 말 또는 "Eval 자동 감지" 또는 "track abandon"
- **Wrong**: 에이전트가 했던 잘못된 행동
- **Right**: 올바른 행동
- **Why**: 왜 잘못인지 근거
- **Scope**: 이 규칙이 적용되는 조건/범위
- **Occurrences**: 1
- **Last-Seen**: YYYY-MM-DD
```

### Source 필드 (v6.2 — parallel tracks 추적)

`Source` 는 항목이 어디서 생겼는지 추적한다. 가능한 형식:

| 형식 | 의미 |
|---|---|
| `dispatcher:manual` | 사용자가 명시적으로 지적 |
| `evaluator-<axis>:F-<id>` | Evaluator 가 자동 감지한 사건 (gotcha_candidates) |
| `service-ops:incident-<id>` | Service-Ops 인시던트에서 도출 |
| `meeting:M-<id>:track-<n>` | parallel-tracks 회의의 특정 트랙에서 도출 (v6.2) |
| `meeting:M-<id>:rendezvous` | followup-review 통합 결정에서 도출 |
| `planner:manual` | Planner 가 sprint 전환 시 등록 |

## 작성 주체

- **Dispatcher**: 사용자의 명시적 실수 지적을 Gotcha Flow 로 기록
- **Evaluator (code-quality / functional / visual)**: evaluation-*.md 의 `gotcha_candidates` JSON 블록을 통해 자동 등록 (v5.7.1+). `harness-next.sh` 가 Evaluator 완료 직후 `scripts/harness-gotcha-register.sh --scan-evaluations` 로 처리.

## Status 라이프사이클 (v5.7.1+)

- **unverified**: 신규 자동/수동 등록 기본값. Generator 는 참조하지만 페널티 강도 낮음.
- **verified**: Planner/사용자 리뷰 후 승격. 이후 위반 시 하드 페널티.
- **resolved**: 근본 원인이 코드/스킬/컨벤션에 반영되어 더 이상 재발하지 않는 항목. 삭제 대신 태그 유지.

Planner 는 스프린트 전환 시 `unverified` 항목을 검토해 `verified` 또는 제거 판정을 내린다 (AGENTS.md "메모리 오염 방어" 섹션).

## 관리 규칙

- Dispatcher + Evaluator 만 gotchas 파일에 쓰기 가능 (자동 등록 포함)
- 각 에이전트는 자신의 gotchas 파일을 읽기 전용으로 참조
- 중복 항목 금지 — 동일 `rule_id` 는 `Occurrences` + `Last-Seen` 만 갱신
- 해결된 항목: `Status: resolved` 또는 제목 뒤 `[RESOLVED]` 태그
- 항목이 20개 초과 시 가장 오래된 resolved 항목부터 정리
