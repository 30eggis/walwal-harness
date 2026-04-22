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

> **FE Stack 차원**: 모든 FE 관련 파이프라인은 `fe_stack` 필드로 스택을 기록한다.
> Planner가 scan-result.json(`tech_stack.fe_stack`) 또는 사용자 질문으로 확정한다.

## 단일 에이전트 체인 (v5.6.5+)

**에이전트 이름 치환은 하지 않는다**. 모든 FE 스택(React, Next.js, Vue, Svelte, Flutter, Swift, 기타) 은 공통 `generator-frontend` / `evaluator-functional` / `evaluator-visual` 을 사용하며, 스택 특성(runner, paths, API, validation) 은 **adaptive ref-docs** (`.harness/ref/fe-<stack>.md`) 에서 로드한다.

| 스택별 스킵/우회 | 방법 |
|------------------|------|
| Visual 렌더 검증이 불가능한 네이티브 모바일/데스크톱 | ref-docs 의 `validation.visual.enabled = false` — `evaluator-visual` 이 MANUAL_REQUIRED 로 우아하게 우회 |
| Playwright 대신 스택 네이티브 E2E (예: XCUITest, Flutter `flutter_driver`) | ref-docs 의 `validation.functional_tests` 에 해당 명령 나열 — `evaluator-functional` 이 로드 실행 |

Dispatcher 는 `fe_stack` 을 `pipeline.json` 에 기록만 하고, 에이전트 이름은 변경하지 않는다. Generator/Evaluator 는 세션 시작 시 스스로 ref-docs 를 로드해 스택에 맞는 동작을 한다.

## Evaluator Chain (공통)

모든 파이프라인의 Generator 이후 단계는 **평가자 체인**으로 처리한다. 직렬 실행 + 조기 종료:

```
Generator → evaluator-code-quality → evaluator-functional → evaluator-visual → archive
                    │                        │                      │
                    └─ FAIL ─ reroute ────────┴──────────────────────┘
                              → Generator (failure.retry_target)
```

- **code-quality** (정적, 저비용, 브라우저 없음): BE/FE/libs 공통 코드 품질
- **functional** (동작, 중비용): API·E2E 행동 검증
- **visual** (렌더, 고비용): 레이아웃/접근성

앞단 FAIL 시 뒷단은 실행하지 않는다. 구조가 깨진 코드에 동작 테스트 낭비 방지.

## FE-ONLY

```yaml
trigger: 외부 API 존재 + FE 작업 요청
agents:
  - planner (light):
      skip: MSA 서비스 설계, BE 기능 목록
      do: OpenAPI → api-contract.json 변환, FE 컴포넌트 설계, feature-list (layer: frontend만), fe_stack 확정
  - generator-frontend                                 # 모든 스택 공통 (ref-docs 로드)
  - evaluator-code-quality                             # 공통 — 브라우저 없음
  - evaluator-functional                               # 모든 스택 공통
  - evaluator-visual                                   # ref.validation.visual.enabled=false 면 MANUAL_REQUIRED 로 우회
evaluator_chain:
  - evaluator-code-quality
  - evaluator-functional
  - evaluator-visual
skip:
  - generator-backend
notes:
  - api-contract.json은 OpenAPI에서 파생 (Planner가 변환)
  - Eval-Func 의 API Health Check는 외부 서버 대상 (ref.api.base_url)
  - AGENTS.md IA-MAP에 BE 경로 없음 (외부 서버)
  - 네이티브 모바일/데스크톱 스택은 ref-docs 에서 visual.enabled=false 로 설정
```

## BE-ONLY

```yaml
trigger: 기존 서버 + BE 기능 추가 요청
agents:
  - planner:
      skip: FE 컴포넌트 설계, 비주얼 요구사항
      do: 기존 코드 분석, 신규 API 설계, api-contract.json 확장
  - generator-backend
  - evaluator-code-quality                  # 공통
  - evaluator-functional:
      mode: api-only
      skip: browser 테스트
      do: curl/httpie로 API 엔드포인트 직접 검증
evaluator_chain:
  - evaluator-code-quality
  - evaluator-functional
skip:
  - generator-frontend
  - evaluator-visual
notes:
  - Eval-Func는 Playwright 대신 CLI 기반 API 테스트
  - Code-Quality 는 BE 코드의 레이어/DI/DTO/에러 전파/테스트 품질 감사
```

## FULLSTACK

```yaml
trigger: 신규 PRD / 제품 설명
agents:
  - planner (full)
  - generator-backend
  - generator-frontend
  - evaluator-code-quality
  - evaluator-functional
  - evaluator-visual
evaluator_chain:
  - evaluator-code-quality
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
