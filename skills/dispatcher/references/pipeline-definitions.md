# Pipeline Definitions

## FE-ONLY

```yaml
trigger: 외부 API 존재 + FE 작업 요청
agents:
  - planner (light):
      skip: MSA 서비스 설계, BE 기능 목록
      do: OpenAPI → api-contract.json 변환, FE 컴포넌트 설계, feature-list (layer: frontend만)
  - generator-frontend
  - evaluator-functional
  - evaluator-visual
skip:
  - generator-backend
notes:
  - api-contract.json은 OpenAPI에서 파생 (Planner가 변환)
  - Eval-Func의 API Health Check는 외부 서버 대상
  - AGENTS.md IA-MAP에 BE 경로 없음 (외부 서버)
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
