---
docmeta:
  id: pipeline-definitions
  title: Pipeline Definitions
  type: output
  createdAt: 2026-04-09T00:00:00Z
  updatedAt: 2026-04-09T00:00:00Z
  source:
    producer: agent
    skillId: harness-dispatcher
  inputs:
    - documentId: harness-dispatcher-skill
      uri: ../SKILL.md
      relation: output-from
      sections:
        - sourceRange:
            startLine: 58
            endLine: 70
          targetRange:
            startLine: 30
            endLine: 95
  tags:
    - dispatcher
    - pipeline
    - fe-stack
    - flutter
---

# Pipeline Definitions

> **FE Stack 차원**: 모든 FE 관련 파이프라인은 `fe_stack` 필드로 React/Flutter를 구분한다.
> Planner가 scan-result.json(`tech_stack.fe_stack`) 또는 사용자 질문으로 확정한다.

## fe_stack + fe_target 스위치 매트릭스

| fe_stack | fe_target | FE Generator | Eval-Functional | Eval-Visual |
|----------|-----------|--------------|----------------|-------------|
| `react`  | (n/a)     | `generator-frontend` | `evaluator-functional` (Playwright) | `evaluator-visual` |
| `flutter`| **`web`** | `generator-frontend-flutter` | **`evaluator-functional`** (Playwright!) | **`evaluator-visual`** (Playwright!) |
| `flutter`| `mobile`  | `generator-frontend-flutter` | `evaluator-functional-flutter` (정적 분석) | **SKIP** |
| `flutter`| `desktop` | `generator-frontend-flutter` | `evaluator-functional-flutter` (정적 분석) | **SKIP** |

> **Flutter Web**: 컴파일 결과가 HTML+JS+CSS 이므로 React 경로의 Playwright evaluator 가 정상 동작.
> Generator-Frontend-Flutter 의 Self-Verification 에서 `flutter analyze` / `flutter test` /
> `flutter build web --release` 가 이미 통과한 상태로 handoff 됨이 전제.

Dispatcher는 `next_agent`를 설정할 때 `pipeline.json` 의 `fe_stack` + `fe_target` 두 값을 보고 치환한다:

```
if pipeline.json.fe_stack == "flutter":
    "generator-frontend" → "generator-frontend-flutter"  (모든 fe_target 공통)

    if fe_target == "web":
        "evaluator-functional" → "evaluator-functional"  (그대로, Playwright 사용)
        "evaluator-visual"     → "evaluator-visual"      (그대로)
    elif fe_target in ("mobile", "desktop"):
        "evaluator-functional" → "evaluator-functional-flutter"
        "evaluator-visual"     → __skip__
```

## FE-ONLY

```yaml
trigger: 외부 API 존재 + FE 작업 요청
agents:
  - planner (light):
      skip: MSA 서비스 설계, BE 기능 목록
      do: OpenAPI → api-contract.json 변환, FE 컴포넌트 설계, feature-list (layer: frontend만), fe_stack 확정
  - generator-frontend OR generator-frontend-flutter  # fe_stack에 따라
  - evaluator-functional OR evaluator-functional-flutter
  - evaluator-visual  # fe_stack == "flutter" 이면 SKIP
skip:
  - generator-backend
notes:
  - api-contract.json은 OpenAPI에서 파생 (Planner가 변환)
  - Eval-Func(React)의 API Health Check는 외부 서버 대상
  - AGENTS.md IA-MAP에 BE 경로 없음 (외부 서버)
  - fe_stack=flutter 인 경우 evaluator-visual 생략
```

## BE-ONLY

```yaml
trigger: 기존 서버 + BE 기능 추가 요청
agents:
  - planner:
      skip: FE 컴포넌트 설계, 비주얼 요구사항
      do: 기존 코드 분석, 신규 API 설계, api-contract.json 확장
  - generator-backend
  - evaluator-functional:
      mode: api-only
      skip: browser 테스트
      do: curl/httpie로 API 엔드포인트 직접 검증
skip:
  - generator-frontend
  - evaluator-visual
notes:
  - Eval-Func는 Playwright 대신 CLI 기반 API 테스트
```

## FULLSTACK

```yaml
trigger: 신규 PRD / 제품 설명
agents:
  - planner (full)
  - generator-backend
  - generator-frontend
  - evaluator-functional
  - evaluator-visual
skip: none
```

## pipeline.json Output Format

```json
{
  "decided_at": "ISO 8601",
  "user_request_summary": "요약",
  "detected_signals": ["시그널1", "시그널2"],
  "pipeline": "FE-ONLY | BE-ONLY | FULLSTACK",
  "agents_active": ["agent1", "agent2"],
  "agents_skipped": ["agent3"],
  "planner_mode": "light | full",
  "evaluator_mode": "browser | api-only",
  "api_source": { "type": "openapi | internal", "location": "URL or path" },
  "notes": "추가 컨텍스트"
}
```

## Disambiguation (불명확 시 질문)

1. "백엔드 API가 이미 존재합니까? (OpenAPI/Swagger 문서 있음?)"
2. "프론트엔드 UI가 필요합니까?"
3. "신규 프로젝트입니까, 기존 프로젝트에 추가입니까?"
