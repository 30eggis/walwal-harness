# 6-Agent Production Harness — 사용 가이드

> Anthropic 블로그 "Harness Design for Long-Running Application Development" 기반
> Solo: 20min/$9 (broken) → Harness: 6hr/$200 (fully functional)
> Stack: NestJS MSA + React/Next.js + Playwright MCP

## 디렉토리 구조

```
.harness/
├── HARNESS.md                  # 이 파일
├── config.json                 # 하네스 설정
├── progress.txt                # 세션 간 상태 전달 로그
├── prompts/                    # 에이전트 프롬프트 (6개)
│   ├── dispatcher.md           # Dispatcher — 파이프라인 선택
│   ├── planner.md              # Planner — 제품 사양 + MSA 설계
│   ├── generator-backend.md    # Generator-BE — NestJS MSA 구현
│   ├── generator-frontend.md   # Generator-FE — React/Next.js 구현
│   ├── evaluator-functional.md # Evaluator-기능 — Playwright E2E
│   └── evaluator-visual.md     # Evaluator-비주얼 — 디자인/접근성
├── actions/                    # 현재 활성 문서
│   ├── pipeline.json           # Dispatcher 결정 (어떤 파이프라인인지)
│   ├── plan.md                 # 제품 사양
│   ├── feature-list.json       # 기능 추적 (layer + service 필드)
│   ├── api-contract.json       # API 계약서
│   ├── sprint-contract.md      # 현재 스프린트 계약
│   ├── evaluation-functional.md
│   └── evaluation-visual.md
└── archive/                    # 완료 스프린트 보관 (불변)
    └── sprint-NNN/
```

## 실행 흐름

```
사용자: 프로젝트 요청 (자유 형식)
         │
         ▼
┌──────────────────┐
│  0. DISPATCHER    │  요청 분석 → pipeline.json 생성
│  (파이프라인 선택) │  사용자 확인
└────────┬─────────┘
         │
    ┌────┴────┬──────────┐
    ▼         ▼          ▼
 FULLSTACK  FE-ONLY   BE-ONLY
```

### FULLSTACK — 신규 PRD 기반 풀스택

```
Planner → Gen-BE → Gen-FE → Eval-Func → Eval-Visual → Archive
```

### FE-ONLY — 기존 API + 프론트엔드 연동

```
Planner(light) → Gen-FE → Eval-Func → Eval-Visual → Archive
    │
    └─ OpenAPI spec → api-contract.json 변환
       Gen-BE SKIP (외부 서버 사용)
```

### BE-ONLY — 기존 서버 + 백엔드 기능 추가

```
Planner → Gen-BE → Eval-Func(API-only) → Archive
    │
    └─ 기존 코드 분석 후 확장 설계
       Gen-FE SKIP, Eval-Visual SKIP
       Eval-Func: Playwright 대신 curl/httpie API 테스트
```

### 공통 — 실패 시 루프

```
Eval-Func FAIL → failure_location에 따라 Gen-BE 또는 Gen-FE 재작업 (max 10회)
Eval-Visual FAIL → Gen-FE 재작업 (max 10회)
10회 초과 → 사용자 개입 요청
```

## 수동 프롬프트 실행 방법

### Step 0: Dispatcher (항상 최초 실행)
```
".harness/prompts/dispatcher.md를 읽고 Dispatcher로 동작하세요.
[사용자의 자유 형식 요청]"
```

### Step 1: Planner
```
".harness/prompts/planner.md를 읽고 Planner 에이전트로 동작하세요.
pipeline.json을 참조하여 [light/full] 모드로 실행합니다."
```

### Step 2: Generator-Backend (FULLSTACK, BE-ONLY)
```
".harness/prompts/generator-backend.md를 읽고 Generator-Backend으로 동작하세요.
Sprint [N]을 시작합니다."
```

### Step 3: Generator-Frontend (FULLSTACK, FE-ONLY)
```
".harness/prompts/generator-frontend.md를 읽고 Generator-Frontend으로 동작하세요.
Sprint [N]의 프론트엔드를 구현합니다."
```

### Step 4: Evaluator-Functional
```
".harness/prompts/evaluator-functional.md를 읽고 Evaluator-Functional로 동작하세요.
Sprint [N]을 평가합니다. Playwright MCP를 사용하세요."
```

### Step 5: Evaluator-Visual
```
".harness/prompts/evaluator-visual.md를 읽고 Evaluator-Visual로 동작하세요.
Sprint [N]의 비주얼을 평가합니다."
```

### Archive (Eval-Visual PASS 후)
```
"Sprint [N] 문서를 아카이브 하세요.
.harness/actions/의 스프린트 문서를 .harness/archive/sprint-NNN/으로 이동합니다."
```

## 핵심 원칙

1. **Backend First** — API가 안정된 후 Frontend 연동 (없는 API 호출 방지)
2. **api-contract.json이 진실의 원천** — FE↔Gateway↔Services 간 유일한 계약
3. **한 세션에 1 스프린트** — 컨텍스트 소진 방지
4. **feature-list.json의 passes만 수정** — 기능 정의는 Planner만 변경
5. **테스트 삭제/약화 금지** — 테스트는 계약이다
6. **Evaluator는 회의적** — 자기 설득 금지, 기준 미달 = FAIL
7. **아카이브 불변** — 완료 문서 수정 금지
8. **MSA 경계 존수** — 서비스 간 직접 DB 접근 금지, 반드시 메시지 패턴

## Tech Stack

| 영역 | 기술 |
|------|------|
| Backend Framework | NestJS (TypeScript) |
| Architecture | MSA (Microservice Architecture) |
| Monorepo | NestJS 내장 monorepo (nest-cli.json) |
| Runner | 통합 러너 (`npm run dev` = concurrently) |
| Transport | TCP (dev) / RabbitMQ·NATS (prod) |
| Frontend | React 또는 Next.js (TypeScript) |
| Styling | Tailwind CSS |
| State | TanStack Query + Zustand |
| E2E Testing | Playwright MCP |
| Unit Testing | Jest (backend) + Vitest (frontend) |
| Database | PostgreSQL (dev: SQLite 가능) |

## MCP 도구

Playwright MCP (`@playwright/mcp`) — headless + vision 모드:
- `browser_navigate`, `browser_click`, `browser_fill`
- `browser_take_screenshot`, `browser_snapshot`
- `browser_console_messages`, `browser_network_requests`
- `browser_resize`, `browser_press_key`, `browser_wait`
