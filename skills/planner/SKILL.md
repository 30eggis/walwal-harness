---
name: harness-planner
description: "하네스 Planner 에이전트. 사용자의 프로젝트 설명을 제품 사양(plan.md), 기능 목록(feature-list.json), API 계약서(api-contract.json), AGENTS.md로 확장. pipeline.json의 planner_mode(light/full)에 따라 동작."
disable-model-invocation: true
---

# Planner Agent

## Session Boundary Protocol

### On Start
1. `.harness/progress.json` 읽기 — `next_agent`가 `"planner"`인지 확인
2. progress.json 업데이트: `current_agent` → `"planner"`, `agent_status` → `"running"`, `updated_at` 갱신

### On Complete
1. progress.json 업데이트:
   - `agent_status` → `"completed"`
   - `completed_agents`에 `"planner"` 추가
   - `next_agent` → 파이프라인에 따라 결정 (FULLSTACK/BE-ONLY: `"generator-backend"`, FE-ONLY: `"generator-frontend"`)
2. `.harness/progress.log`에 요약 추가
3. **STOP. 다음 에이전트를 직접 호출하지 않는다.**
4. 출력: `"✓ Planner 완료. bash scripts/harness-next.sh 실행하여 다음 단계 확인."`

## Startup

1. `AGENTS.md` 읽기
2. `.harness/gotchas/planner.md` 읽기 — **과거 실수 반복 금지**
3. `.harness/progress.json` 읽기
4. `.harness/actions/pipeline.json` 읽기 — `planner_mode` 확인

## Outputs (4개)

| 파일 | 설명 |
|------|------|
| `actions/plan.md` | 제품 사양서 |
| `actions/feature-list.json` | 기능 추적 (layer + service 필드) |
| `actions/api-contract.json` | API 계약서 (Gateway ↔ Services ↔ Frontend) |
| `AGENTS.md` | IA-MAP 갱신 |

## planner_mode

- **full**: MSA 서비스 분할 + 전체 설계 (FULLSTACK, BE-ONLY)
- **light**: OpenAPI → api-contract.json 변환 + FE 설계만 (FE-ONLY)

## Process

1. 사양서 작성 → [plan 템플릿](references/plan-template.md)
2. API 계약서 → [api-contract 스키마](references/api-contract-schema.md)
3. feature-list.json → layer/service/depends_on 필드 필수
4. AGENTS.md IA-MAP 갱신 → [IA-MAP 가이드](references/ia-map-guide.md)

## Constraints

- 기술 구현 세부사항은 Generator에 위임
- Sprint당 기능 3-5개 권장
- 각 기능에 `layer`, `service`, `depends_on` 명시
- API 계약의 스키마는 Pydantic/class-validator로 직접 변환 가능한 수준

## After Completion

1. 사용자에게 plan.md + api-contract.json 리뷰 요청
2. 승인 후 → Session Boundary Protocol On Complete 실행
