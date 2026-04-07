# 6-Agent Production Harness — 사용 가이드

> Anthropic 블로그 "Harness Design for Long-Running Application Development" 기반
> Solo: 20min/$9 (broken) → Harness: 6hr/$200 (fully functional)
> Stack: NestJS MSA + React/Next.js + Playwright MCP

## 디렉토리 구조

```
.harness/
├── HARNESS.md                  # 이 파일
├── config.json                 # 하네스 설정
├── progress.json               # 기계 판독 상태 (세션 오케스트레이션)
├── progress.log                # 사람 판독 히스토리 (append-only)
├── next-prompt.txt             # 다음 세션용 프롬프트 (claude CLI 파이프용)
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

## 세션 오케스트레이션

### 핵심: 한 세션에 1 에이전트 단계

각 에이전트는 독립 Claude Code 세션에서 실행됩니다. 컨텍스트 소진을 방지하고 품질을 유지합니다.

### 상태 관리

| 파일 | 역할 |
|------|------|
| `.harness/progress.json` | 기계 판독 상태 (현재 에이전트, 파이프라인, 실패 정보) |
| `.harness/progress.log` | 사람 판독 히스토리 (append-only) |
| `.harness/next-prompt.txt` | 다음 세션용 프롬프트 (claude CLI 파이프용) |

### 실행 방법

#### 1. 첫 세션: Dispatcher
```
"하네스 엔지니어링 시작" 또는 /harness-dispatcher
```

#### 2. 이후 세션: harness-next.sh로 안내받기
```bash
bash scripts/harness-next.sh
```
Feature-level 프로그래스를 출력하고 다음 에이전트를 안내합니다.

#### 3. 다음 세션 시작
```bash
# 방법 A: 새 세션에서 스킬 직접 호출
/harness-generator-backend

# 방법 B: claude CLI 자동 실행
claude --prompt "$(cat .harness/next-prompt.txt)"
```

#### 4. SessionStart 훅 (자동)
세션 시작 시 `.claude/settings.json` 훅이 자동으로 현재 프로그래스를 출력합니다.

### Session Boundary Protocol

모든 에이전트 스킬에 내장된 프로토콜:

- **On Start**: `progress.json` 읽기 → `agent_status: "running"` 설정
- **On Complete**: `progress.json` 업데이트 → `next_agent` 계산 → **STOP**
- **On Fail** (Evaluator): `failure` 정보 기록 → `retry_target` 설정 → **STOP**

에이전트는 절대 다음 에이전트를 직접 호출하지 않습니다.

## 핵심 원칙

1. **Backend First** — API가 안정된 후 Frontend 연동 (없는 API 호출 방지)
2. **api-contract.json이 진실의 원천** — FE↔Gateway↔Services 간 유일한 계약
3. **한 세션에 1 에이전트 단계** — 컨텍스트 소진 방지, Session Boundary Protocol 준수
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
