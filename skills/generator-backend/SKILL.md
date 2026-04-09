---
name: harness-generator-backend
description: "하네스 Backend Generator. NestJS MSA 모노레포로 API Gateway, Microservices, DB 스키마를 구현한다. api-contract.json이 스펙이며, Sprint Contract의 Backend 섹션을 작성 후 구현한다."
disable-model-invocation: true
---

# Generator-Backend — NestJS MSA

## Session Boundary Protocol

### On Start
1. `.harness/progress.json` 읽기 — `next_agent`가 `"generator-backend"`인지 확인
2. progress.json 업데이트: `current_agent` → `"generator-backend"`, `agent_status` → `"running"`, `updated_at` 갱신
3. `failure` 필드 확인 — retry인 경우 `evaluation-functional.md`의 실패 사유 우선 읽기

### On Complete
1. progress.json 업데이트:
   - `agent_status` → `"completed"`
   - `completed_agents`에 `"generator-backend"` 추가
   - `next_agent` → 파이프라인에 따라 결정 (FULLSTACK: `"generator-frontend"`, BE-ONLY: `"evaluator-functional"`)
   - `failure` 필드 초기화 (retry 성공 시)
2. `feature-list.json`의 해당 feature `passes`에 `"generator-backend"` 추가
3. `.harness/progress.log`에 요약 추가
4. **STOP. 다음 에이전트를 직접 호출하지 않는다.**
5. 출력: `"✓ Generator-Backend 완료. bash scripts/harness-next.sh 실행하여 다음 단계 확인."`

## Startup

1. `AGENTS.md` 읽기 — IA-MAP, 권한 확인
2. `.harness/gotchas/generator-backend.md` 읽기 — **과거 실수 반복 금지**
3. `.harness/memory.md` 읽기 — **프로젝트 공유 학습 규칙 적용**
4. `pwd` + `.harness/progress.json` + `git log --oneline -20`
5. `.harness/actions/api-contract.json` 읽기 — **이것이 스펙**
6. `.harness/actions/feature-list.json` — `layer: "backend"` 필터
7. 통합 러너: `npm run dev`
8. Gateway 헬스체크: `curl http://localhost:3000/health`

## AGENTS.md — 읽기 전용

`[BE]` + `→ Generator-Backend` 소유 경로만 쓰기 가능. 구조 변경 필요 시 sprint-contract.md에 `## Change Request`.

## Sprint Workflow

1. **Sprint Contract BE 섹션 작성** — 엔드포인트, DB 변경, message patterns, 성공 기준
2. **구현** — Gateway 컨트롤러 + Microservice 핸들러 + Shared DTO
3. **Self-Verification** — Jest + curl 테스트
4. **Handoff** → Generator-Frontend

NestJS MSA 패턴 → [NestJS MSA 참조](references/nestjs-msa-patterns.md)
Sprint Contract 형식 → [Sprint Contract BE 템플릿](references/sprint-contract-be.md)

## 금지 사항

- api-contract.json에 없는 엔드포인트 추가
- Frontend(apps/web/) 코드 수정
- feature-list.json에서 `passes` 외 필드 수정
- 서비스 간 직접 DB 접근 (반드시 메시지 패턴)
- AGENTS.md 수정

## On Evaluator Feedback

`evaluation-functional.md` → `failure_location: "backend"` 필터 → 수정 → Jest 재실행 → 핸드오프
