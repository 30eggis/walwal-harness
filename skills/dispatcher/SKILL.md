---
name: harness-dispatcher
description: "AI 하네스 파이프라인 선택 및 Gotcha 관리. 사용자 요청을 분석하여 FULLSTACK/FE-ONLY/BE-ONLY 파이프라인을 결정하고, 실수 지적 시 해당 에이전트의 gotchas에 기록한다. 트리거: '하네스 엔지니어링 시작', '하네스 시작', 'harness start'"
disable-model-invocation: false
---

# Dispatcher — Pipeline Selector + Gotcha Manager

## progress.json 업데이트 규칙 (v5.6.3+)

⚠️ **절대로 progress.json 을 통째로 재작성하지 마라**. `Write` 도구로 전체 파일을
덮어쓰면 `mode` / `team_state` / 기타 top-level 필드가 누락되어 Team Mode 가 Solo 로
되돌아가는 등 런타임 오류가 발생한다.

**올바른 방법** — 반드시 partial update 로 갱신:

```bash
# 헬퍼 스크립트 (권장)
bash scripts/harness-progress-set.sh . '.current_agent = "planner" | .agent_status = "running"'

# 또는 직접 jq 로 partial update
jq '.agent_status = "completed" | .completed_agents += ["planner"]'   .harness/progress.json > .harness/progress.json.tmp &&   mv .harness/progress.json.tmp .harness/progress.json
```

위 두 방식은 파일의 나머지 필드를 보존한다. Read → 수정 → Write 패턴은 사용 금지.

## Session Boundary Protocol

### On Start
1. `.harness/progress.json` 읽기 — `next_agent`가 `"dispatcher"`인지 확인
2. progress.json 업데이트: `current_agent` → `"dispatcher"`, `agent_status` → `"running"`, `updated_at` 갱신
3. `.harness/memory.md` 읽기 — **프로젝트 공유 학습 규칙 적용**

### On Complete
1. progress.json 업데이트:
   - `agent_status` → `"completed"`
   - `completed_agents`에 `"dispatcher"` 추가
   - `next_agent` → **브레인스토밍 결정 트리에 따라 결정** ([섹션 6](#6-brainstormer-routing-decision) 참조)
     - 신규/재플래닝 + 사용자가 브레인스토밍 선택 → `"brainstorming"`
     - 신규/재플래닝 + 사용자가 건너뛰기 선택 → `"planner"`
     - 특정 에이전트 직접 명령 → 해당 에이전트 (예: `"evaluator-functional"`)
     - Gotcha 교정 후 재작업 → `failure.retry_target` (해당 에이전트)
   - `pipeline` → 선택된 파이프라인 (FULLSTACK/FE-ONLY/BE-ONLY)
   - `sprint.number` → `1`, `sprint.status` → `"in_progress"` (신규 파이프라인인 경우에만)
   - **신규 파이프라인인 경우** `dispatch.id` 가 `null` 이면 counter 를 올리고 새 ID 를 발급 (v5.7+):
     ```bash
     # dispatch.id 가 이미 있으면 기존 dispatch 유지, 없으면 새로 발급
     cur=$(jq -r '.dispatch.id // ""' .harness/progress.json)
     if [ -z "$cur" ]; then
       next=$(jq -r '((.dispatch.counter // 0) + 1)' .harness/progress.json)
       new_id=$(printf 'D-%03d' "$next")
       bash scripts/harness-progress-set.sh . \
         ".dispatch.counter = $next | .dispatch.id = \"$new_id\""
     fi
     ```
     아카이빙 후 `dispatch.id` 는 `null` 로 리셋되므로, 다음 dispatcher 실행 시 새 D-NNN 이 할당된다.
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

- **실수 지적 (부정)** ("아니", "잘못", "그렇게 하면 안 돼", "~하지 마") → **Gotcha Flow**
- **긍정 규범** ("~해야 해", "~이렇게 해줘", "항상 ~", "우리는 ~ 방식") → **Convention Flow**
- **기능 요청** ("만들어", "추가", "시작", PRD, OpenAPI) → **Pipeline Flow**
- **혼합** → Gotcha/Convention 먼저 기록 → Pipeline 이어서
- **메타/인사/Claude 자체 질문** → Dispatcher skip, 짧은 일반 응답 허용

**부정 vs 긍정 구분법**: "X 하지 마 / X 가 틀렸어 / 그렇게 하면 안 돼" 는 **Gotcha**. "X 를 해야 해 / X 로 해줘 / 항상 X" 는 **Convention**. 동일 주제도 시그널에 따라 저장 위치가 달라집니다.

## 2. Feedback Taxonomy — Gotcha / Convention / Memory

사용자의 교정/가이드를 받으면 **먼저 분류**:

| 유형 | 성격 | 저장 위치 | ID | 예시 |
|------|------|----------|-----|------|
| **Gotcha** | 특정 에이전트의 **일회성 실수(사고)** 기록 (negative) | `.harness/gotchas/<agent>.md` | `[G-NNN]` | "Generator-BE 가 MockServer 무시하고 실 DB 붙지 마" |
| **Convention** | 에이전트/스코프의 **하우스 스타일(norm)** (positive) | `.harness/conventions/<scope>.md` | `[C-NNN]` | "API 응답 필드는 snake_case" |
| **Memory** | **모든 에이전트** 공통 구조적 교훈 | `.harness/memory.md` | `[M-NNN]` | "Playwright 스크린샷은 단계 완료 후 항상 삭제" |

Scope 가 특정 에이전트를 넘어서면 Memory. 특정 에이전트에 해당하면 Gotcha(부정) 혹은 Convention(긍정).

### Gotcha Flow (에이전트별 실수)

실수 지적 감지 시 → [Gotcha 상세 가이드](references/gotcha-flow.md)

핵심:
1. 교정 시그널 감지 (HIGH/MEDIUM만 기록)
2. 도메인 분석 → 대상 에이전트 판별
3. `.harness/gotchas/[agent].md`에 `[G-NNN]` 추가 (중복 시 Occurrences 증가)
4. 사용자에게 기록 확인

### Convention Flow (에이전트별 하우스 스타일)

긍정 가이드 감지 시 → [Convention 상세 가이드](references/convention-flow.md)

핵심:
1. 긍정 시그널 감지 ("해야 해", "이렇게 해줘", "항상" 등)
2. 스코프 판별: 특정 에이전트(`generator-backend` 등) / `shared` / 프로젝트 전체(루트 `CONVENTIONS.md`)
3. `.harness/conventions/<scope>.md` 에 `[C-NNN]` 추가
4. 사용자에게 기록 확인

### Memory Flow (프로젝트 공유 규칙)

구조적/반복적 교훈 감지 시:
1. 이것이 특정 에이전트의 일회성 실수가 아니라 **전체 에이전트가 따라야 할 규칙**인지 판단
2. **맞으면**: `.harness/memory.md`에 항목 추가 (ID: `[M-NNN]`, 날짜, 규칙, 적용 범위)
3. 관련 스킬의 SKILL.md에 구조적 변경이 필요하면 → 사용자에게 "이건 스킬 자체에 반영해야 합니다" 안내 (Dispatcher가 직접 SKILL.md를 수정하지는 않음)
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

### Mode Recommendation (v5.7.1+)

⚠️ **Dispatcher → Planner 전환 시에는 mode 질문을 하지 않는다.** Planner 는 mode 와 무관한 단일 실행이다. 과거의 "harness-solo 를 입력하세요" 안내는 제거.

파이프라인이 확정되면 (Planner 호출 직전) **단 한 문단** 으로 Mode 추천을 출력하되, 응답을 기다리지 않고 **default=solo 로 그대로 진행**한다. 사용자가 team 을 원하면 언제든 `/harness-team` 으로 전환 가능.

추천 로직:
- Planner 가 feature-list.json 을 확정한 뒤 `features.length >= 3` 이고 서로 의존성이 낮으면 → "Team 모드 권장" 안내
- `features.length < 3` 또는 단일 feature 연속 작업 → "Solo 모드 권장" 안내
- Dispatcher 단계에서는 feature 수를 모를 수 있으므로 **기본은 Solo 진행**, Planner 완료 후 자동으로 재평가

출력 예:
```
Pipeline: FULLSTACK 확정. Solo 모드로 자동 진행합니다.
(병렬 3팀 실행을 원하면 Planner 완료 후 /harness-team 입력)
```

**금지**:
- "solo 입력하세요 / team 입력하세요" 식의 선택 강요
- mode 결정을 기다리며 Planner 호출을 보류하는 것
- 이미 mode 가 설정된 상태(`progress.json.mode` 존재)에서 재질문하는 것

### evaluator_chain 필드 (모든 파이프라인 필수)

`pipeline.json` 에 **`evaluator_chain`** 배열을 기록한다. `config.json.flow.pipeline_selection.evaluator_chains.<pipeline>` 의 값을 복사:

- FULLSTACK / FE-ONLY: `["evaluator-code-quality", "evaluator-functional", "evaluator-visual"]`
- BE-ONLY: `["evaluator-code-quality", "evaluator-functional"]` (functional 은 api-only 모드)

스택 특성(예: Flutter mobile 에서 Visual skip) 이 필요하면 해당 스택 ref-docs (`.harness/ref/fe-<stack>.md`) 의 `validation.visual.enabled` 를 false 로 두면 evaluator-visual 이 MANUAL_REQUIRED 로 우아하게 우회한다. 별도 치환 에이전트는 사용하지 않는다.

### Evaluator 체인 라우팅 규칙

Generator 완료 후 `next_agent` 는 chain[0] (항상 `evaluator-code-quality`).

각 평가자의 On Complete:
- **PASS**: chain 상 다음 평가자로 `next_agent` 설정. 마지막 평가자면 `archive`.
- **FAIL**: chain 나머지 **건너뛰고** `failure.retry_target` (해당 결함 위치의 Generator) 로 리라우팅.

Gotcha retry 시에도 체인 시작점은 chain[0] 부터 재실행.

### fe_stack 필드 (FE 파이프라인에서 필수)

FE-ONLY 또는 FULLSTACK 선택 시, `pipeline.json`에 **`fe_stack`** 필드를 포함해야 한다:

- `scan-result.json.tech_stack.fe_stack` 값을 기본으로 사용 (예: `react`, `nextjs`, `vue`, `flutter`, `swift` 등)
- 값이 없거나 불명확하면 Planner가 확정하도록 위임 (Dispatcher는 `"unknown"` 기록 + `notes` 에 메모)
- **에이전트 이름 치환은 하지 않는다** (v5.6.5+). 모든 FE 스택은 공통 `generator-frontend` / `evaluator-functional` / `evaluator-visual` 을 사용하고, 스택 특성은 `.harness/ref/fe-<stack>.md` (adaptive ref-docs) 에서 로드한다.

## 6. Brainstormer Routing Decision

**원칙**: Brainstormer 는 파이프라인의 고정 스텝이 **아니다**. Dispatcher 가 조건부로 삽입한다.

### 6.1 결정 트리

Dispatcher 는 사용자 요청을 분류한 뒤 아래 순서로 판단:

```
1. Gotcha / 실수 지적인가?
   → YES: gotcha 기록 → next_agent = failure.retry_target (해당 에이전트)
         (브레인스토밍 없음)

2. 특정 에이전트 직접 명령인가?
   ("evaluator 다시 돌려", "generator-frontend 재작업", "planner plan.md 고쳐" 등)
   → YES: next_agent = <대상 에이전트> (브레인스토밍 없음)

3. Planner 가 동작해야 하는 케이스인가?
   (신규 파이프라인 / 신규 PRD / 기존 plan.md 대폭 수정 / 신규 feature 대규모 추가)
   → YES: 사용자에게 확인 질문 → 6.2 "브레인스토밍 확인 플로우"
   → NO:  다른 에이전트로 라우팅 (generator 이어서 등)

4. 그 외 (메타/인사/Claude 자체 질문) → Dispatcher skip
```

### 6.2 브레인스토밍 확인 플로우

Planner 를 호출해야 한다고 판단되면, **사용자에게 단 하나의 질문을 출력한 뒤 대기한다:**

```
이 요청은 Planner 가 처리할 신규/재플래닝 건으로 보입니다.
러프한 요구사항을 먼저 구체화하는 Brainstormer 과정을 거칠까요?

  (Y) 예 — Brainstormer 와 대화하며 요구사항을 fit 하게 만든 뒤 Planner
  (N) 아니오 — 이미 PRD/OpenAPI 가 명확하므로 바로 Planner

답변: Y / N
```

사용자 응답 처리:
- **Y (긍정)** — "네", "y", "yes", "필요해", "해줘" 등
  → `next_agent = "brainstorming"`
- **N (부정)** — "아니오", "n", "no", "필요없어", "바로", "skip" 등
  → `next_agent = "planner"`
- **불명확 / 무응답** — 한 번 더 "Y 또는 N 으로 답해주세요" 요청

### 6.3 Skip 케이스 정리

브레인스토밍이 **실행되지 않는** 경우 (Dispatcher 가 직접 다른 에이전트로 라우팅):

| 상황 | next_agent |
|------|-----------|
| "Eval, X 다시 검증해" | `evaluator-functional` (또는 `evaluator-visual`) |
| "Generator-FE, Y 버그 고쳐" | `generator-frontend` |
| "Generator-BE, API 재생성해" | `generator-backend` |
| Eval FAIL → retry | `failure.retry_target` |
| Gotcha 수정 | `failure.retry_target` 또는 현재 에이전트 |
| 기존 plan.md 소폭 수정 (Dispatcher 판단) | `planner` (직접) |
| 사용자가 "Brainstormer 없이" / "skip brainstorming" 명시 | `planner` (직접) |

### 6.4 강제 호출 케이스

사용자가 명시적으로 원하면 브레인스토밍은 언제든 재호출 가능:

- "Brainstormer 다시 돌려줘"
- "요구사항 다시 잡자"
- "plan 처음부터"

이 경우 기존 `.harness/actions/brainstorm-spec.md` 는 Brainstormer 의 On Start 에서
`.harness/archive/brainstorm-spec-<timestamp>.md` 로 백업된다.

## 7. Handoff 라우팅

Dispatcher 가 `next_agent` 를 세팅할 때 **스택별 에이전트 이름 치환은 하지 않는다** (v5.6.5+). 모든 FE 스택이 공통 `generator-frontend` / `evaluator-functional` / `evaluator-visual` 을 사용하고, 스택 특성은 adaptive ref-docs(`.harness/ref/fe-<stack>.md`) 에서 로드한다.

예외적 스킵 규칙은 ref-docs 의 `validation.visual.enabled` 플래그로 제어 — false 면 evaluator-visual 이 MANUAL_REQUIRED 로 우아하게 우회한다 (별도 에이전트 이름 변경 없음).
