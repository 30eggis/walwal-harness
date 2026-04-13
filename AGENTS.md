# AGENTS.md — Project Context for AI Agents

> 이 파일은 모든 AI 에이전트(Claude, Cursor, Copilot, Windsurf 등)의 공통 진입점입니다.
> CLAUDE.md는 이 파일의 심볼릭 링크입니다.

## Project

- **Name**: (Planner가 설정)
- **Description**: (Planner가 설정)
- **Phase**: INIT
- **Harness**: `.harness/HARNESS.md` 참조

## Tech Stack

- Backend: NestJS (TypeScript) — MSA, 모노레포
- Frontend: React 또는 Next.js (TypeScript)
- Database: PostgreSQL / SQLite (dev)
- Testing: Playwright MCP (E2E), Jest (BE), Vitest (FE)
- Styling: Tailwind CSS

## IA-MAP (Information Architecture)

> 1차원 폴더 맵. 각 경로의 책임과 소유 에이전트를 명시합니다.
> Planner만 이 맵을 수정할 수 있습니다.

```
/
├── apps/
│   ├── gateway/          # [BE] API Gateway — 라우팅, 인증, CORS       → Generator-Backend
│   ├── service-*/        # [BE] Microservice — 도메인 비즈니스 로직     → Generator-Backend
│   └── web/              # [FE] Frontend — UI, 상태관리, API 연동       → Generator-Frontend
├── libs/
│   ├── shared-dto/       # [BE] 공유 DTO — api-contract.json에서 파생   → Generator-Backend
│   ├── database/         # [BE] DB 모듈 — TypeORM/Prisma 설정          → Generator-Backend
│   └── common/           # [BE] 공통 유틸 — 필터, 인터셉터, 가드        → Generator-Backend
├── .harness/
│   ├── prompts/          # [HARNESS] 에이전트 프롬프트 정의             → Planner
│   ├── actions/          # [HARNESS] 활성 스프린트 문서                 → 각 에이전트
│   └── archive/          # [HARNESS] 완료 스프린트 보관 (불변)          → Evaluator
├── AGENTS.md             # [META] 이 파일 — 프로젝트 컨텍스트           → Planner
├── CLAUDE.md             # [META] → AGENTS.md 심볼릭 링크
├── init.sh               # [HARNESS] 환경 초기화 + 통합 러너
├── nest-cli.json         # [BE] NestJS 모노레포 설정                    → Generator-Backend
├── package.json          # [ROOT] 워크스페이스 + 통합 스크립트           → Generator-Backend
└── docker-compose.yml    # [INFRA] 개발용 서비스 오케스트레이션          → Generator-Backend
```

### IA-MAP 범례

| 태그 | 의미 | 소유 에이전트 |
|------|------|--------------|
| `[BE]` | Backend 영역 | Generator-Backend |
| `[FE]` | Frontend 영역 | Generator-Frontend |
| `[HARNESS]` | 하네스 시스템 | Planner / Evaluator |
| `[META]` | 프로젝트 메타 문서 | Planner |
| `[INFRA]` | 인프라/배포 설정 | Planner |
| `[ROOT]` | 루트 설정 | Generator-Backend (초기), Planner (구조 변경) |

## Rules (모든 에이전트 공통)

### 읽기/쓰기 권한

| 파일 | 읽기 | 쓰기 |
|------|------|------|
| CONVENTIONS.md | 전체 | 사용자만 (에이전트 수정 금지) |
| AGENTS.md | 전체 | Planner만 |
| .harness/actions/api-contract.json | 전체 | Planner만 |
| .harness/actions/feature-list.json | 전체 | passes 필드: Generator, 나머지: Planner만 |
| .harness/actions/sprint-contract.md | 전체 | Generator-BE(BE섹션), Generator-FE(FE섹션) |
| .harness/actions/evaluation-*.md | 전체 | 해당 Evaluator만 |
| .harness/progress.json | 전체 | 전체 (Session Boundary Protocol에 따라 업데이트) |
| apps/gateway/, apps/service-*/ | 전체 | Generator-Backend만 |
| apps/web/ | 전체 | Generator-Frontend만 |
| libs/ | 전체 | Generator-Backend만 |
| .harness/archive/ | 전체 | 쓰기 금지 (불변) |

### 변경 요청 프로토콜

Generator/Evaluator가 AGENTS.md 또는 api-contract.json 변경이 필요하다고 판단할 때:

1. `.harness/actions/sprint-contract.md` 또는 evaluation에 `## Change Request` 섹션 추가
2. 변경 사유, 영향 범위, 제안 내용 기술
3. Planner가 다음 스프린트 전환 시 반영 여부 결정

### 금지 사항 (전체)

- AGENTS.md를 Planner 외 에이전트가 수정
- api-contract.json에 없는 엔드포인트 구현/호출
- 서비스 간 직접 DB 접근 (반드시 메시지 패턴)
- 테스트 삭제/약화
- archive/ 내 파일 수정
- 프로젝트를 조기 "완료" 선언
- 아티팩트 상태가 `draft` 미만인 선행 아티팩트에 의존하여 작업 시작

### 품질 게이트 (v3.1 신설)

| 게이트 | 시점 | 내용 |
|--------|------|------|
| **Pre-Eval Gate** | Generator → Evaluator 전환 | tsc, eslint, jest/vitest 자동 실행. 실패 시 Generator 리라우팅 |
| **파일 소유권 검증** | 에이전트 전환 시 | git diff로 권한 밖 파일 수정 감지 |
| **아티팩트 선행조건** | 에이전트 시작 전 | progress.json.artifacts 상태 확인 |
| **에스컬레이션** | 3회 연속 실패 | Planner에게 scope 축소/접근 변경 요청 |

### Evaluation System (v3.2)

| 설정 | 값 |
|------|------|
| PASS 기준 | **2.80 / 3.00 이상** |
| FAIL 기준 | 2.79 이하 (예외 없음) |
| Evidence 없는 Score | 0점 강제 |
| AC 부분 통과 | FAIL (100% 필수) |
| Regression 실패 1건+ | FAIL (신규 점수 무관) |

- Planner는 feature-list.json에 **Executable AC** (type: api/visual/e2e + verify 조건) 필수 작성
- Evaluator는 Adversarial Rules에 따라 적대적으로 검증 (rubber-stamping 금지)
- 이전 Sprint PASS 기능은 Regression Checkpoint로 재검증
- Eval-Functional ↔ Eval-Visual 간 Cross-Validation으로 불일치 감지

### 메모리 오염 방어

- gotcha/memory 항목은 `unverified` 상태로 시작, Planner 리뷰 후 `verified` 승격
- TTL 만료 항목은 Planner 스프린트 전환 시 리뷰 (갱신 또는 삭제)
- 코드/git으로 검증 불가한 항목은 즉시 삭제

## Harness Quick Reference

| 명령 | 설명 |
|------|------|
| `npm run dev` | 통합 러너 (Gateway + 전체 서비스 + Frontend) |
| `bash init.sh` | 환경 확인 + 서비스 기동 |
| `.harness/progress.json` | 현재 진행 상태 (기계 판독) |
| `.harness/actions/` | 활성 스프린트 문서 |
| `.harness/HARNESS.md` | 하네스 상세 가이드 |
