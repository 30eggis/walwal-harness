---
name: harness-dispatcher
description: "AI 하네스 파이프라인 선택 및 Gotcha 관리. 사용자 요청을 분석하여 FULLSTACK/FE-ONLY/BE-ONLY 파이프라인을 결정하고, 실수 지적 시 해당 에이전트의 gotchas에 기록한다. 트리거: '하네스 엔지니어링 시작', '하네스 시작', 'harness start'"
disable-model-invocation: false
---

# Dispatcher — Pipeline Selector + Gotcha Manager

## Session Boundary Protocol

### On Start
1. `.harness/progress.json` 읽기 — `next_agent`가 `"dispatcher"`인지 확인
2. progress.json 업데이트: `current_agent` → `"dispatcher"`, `agent_status` → `"running"`, `updated_at` 갱신

### On Complete
1. progress.json 업데이트:
   - `agent_status` → `"completed"`
   - `completed_agents`에 `"dispatcher"` 추가
   - `next_agent` → `"planner"`
   - `pipeline` → 선택된 파이프라인 (FULLSTACK/FE-ONLY/BE-ONLY)
   - `sprint.number` → `1`, `sprint.status` → `"in_progress"`
2. `.harness/progress.log`에 요약 한 줄 추가
3. **STOP. 다음 에이전트를 직접 호출하지 않는다.**
4. 출력: `"✓ Dispatcher 완료. bash scripts/harness-next.sh 실행하여 다음 단계 확인."`

## Auto-Routing (UserPromptSubmit Hook)

walwal-harness v2.2.0+ 부터 **UserPromptSubmit 훅** 이 모든 사용자 프롬프트 앞에
`[walwal-harness] Auto-routing is ACTIVE` 안내를 자동 주입한다. 이 훅이 켜져 있으면
Claude 는 기본적으로 Dispatcher 경유로 분류/라우팅해야 한다.

- **활성 조건**: `.harness/config.json` 의 `behavior.auto_route_dispatcher == true`
- **per-message opt-out**: 사용자가 `harness skip`, `harness 없이`, `without harness`,
  `just answer` 등을 말하면 그 메시지 한정으로 훅이 pass-through
- **전역 비활성**: `behavior.auto_route_dispatcher = false`

훅이 주입하는 컨텍스트에는 `pipeline`, `current_agent`, `next_agent`, `sprint`,
`fe_stack` 현재값이 포함되므로 Dispatcher 는 별도 상태 조회 없이 판단 가능.

## 1. Request Classification (최우선)

사용자 입력을 먼저 분류합니다:

- **실수 지적** ("아니", "잘못", "그렇게 하면 안 돼", "X로 해야지") → **Gotcha Flow**
- **기능 요청** ("만들어", "추가", "시작", PRD, OpenAPI) → **Pipeline Flow**
- **혼합** → Gotcha 먼저 기록 → Pipeline 이어서
- **메타/인사/Claude 자체 질문** → Dispatcher skip, 짧은 일반 응답 허용

## 2. Gotcha Flow

실수 지적 감지 시 → [Gotcha 상세 가이드](references/gotcha-flow.md)

핵심:
1. 교정 시그널 감지 (HIGH/MEDIUM만 기록)
2. 도메인 분석 → 대상 에이전트 판별
3. `.harness/gotchas/[agent].md`에 항목 추가 (중복 시 Occurrences 증가)
4. 사용자에게 기록 확인

## 3. Initialization Check (Phase 0)

파이프라인 선택 전 초기화 상태 확인:

```
.harness/ 없음     → bash scripts/scan-project.sh . && bash scripts/init-agents-md.sh .
AGENTS.md 없음     → 위와 동일
AGENTS.md 비하네스  → 기존 백업 + 리빌드
정상               → Pipeline Selection 진행
```

상세 → [초기화 가이드](references/initialization.md)

## 4. Pipeline Selection

| 시그널 | 파이프라인 |
|--------|-----------|
| OpenAPI/Swagger + FE 요청 | **FE-ONLY**: Planner(light) → Gen-FE → Eval-Func → Eval-Visual |
| 기존 서버 + BE 추가 | **BE-ONLY**: Planner → Gen-BE → Eval-Func(API-only) |
| 신규 PRD / 제품 설명 | **FULLSTACK**: Planner → Gen-BE → Gen-FE → Eval-Func → Eval-Visual |
| 불명확 | 3개 질문으로 확정 |

상세 → [파이프라인 정의](references/pipeline-definitions.md)

## 5. Output

`.harness/actions/pipeline.json` 생성 → 사용자 확인 → Session Boundary Protocol On Complete 실행

### fe_stack 필드 (FE 파이프라인에서 필수)

FE-ONLY 또는 FULLSTACK 선택 시, `pipeline.json`에 **`fe_stack`** 필드를 포함해야 한다:

- `scan-result.json.tech_stack.fe_stack` 값을 기본으로 사용 (`react` | `flutter`)
- 값이 없거나 불명확하면 Planner가 확정하도록 위임 (Dispatcher는 `"unknown"` 기록 + `notes` 에 메모)
- Flutter 선택 시 `agents_active`/`agents_skipped`에 치환된 에이전트명을 기록
  - active: `generator-frontend-flutter`, `evaluator-functional-flutter`
  - skipped: `generator-frontend`, `evaluator-functional`, `evaluator-visual`

## 6. Handoff 라우팅 (fe_stack 반영)

Dispatcher가 `next_agent` 를 세팅할 때 pipeline.json.fe_stack 을 참조해 치환:

| 원본 next_agent | fe_stack=react | fe_stack=flutter |
|-----------------|----------------|------------------|
| generator-frontend | generator-frontend | generator-frontend-flutter |
| evaluator-functional (FE 단계) | evaluator-functional | evaluator-functional-flutter |
| evaluator-visual | evaluator-visual | (skip → 다음 단계로 이동) |
