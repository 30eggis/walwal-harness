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
├── handoff.json                # 세션 전환 문서 (prompt, model, artifacts, regression 등)
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
Eval-Func FAIL → failure_location에 따라 Gen-BE 또는 Gen-FE 재작업 (max 5회)
Eval-Visual FAIL → Gen-FE 재작업 (max 5회)
3회 실패 → Planner 에스컬레이션 (scope 축소/접근 변경)
5회 초과 → 사용자 개입 요청
```

### Pre-Eval Gate (Deterministic Checks)

Generator → Evaluator 전환 전, 결정론적 검증을 자동 실행합니다:

```
Generator 완료 → [tsc --noEmit] → [eslint] → [jest/vitest --bail] → Evaluator
                  ↓ FAIL                                              
                  Generator로 리라우팅 (Evaluator 세션 미개설)
```

- Backend: `tsc --noEmit`, `eslint . --max-warnings=0`, `jest --bail`
- Frontend: `tsc --noEmit`, `eslint . --max-warnings=0`, `vitest run --bail 1`
- `config.json`의 `flow.pre_eval_gate`에서 커스터마이징 가능

### Runtime Guardrail (파일 소유권 검증)

에이전트 전환 시 `git diff`로 이전 에이전트가 권한 밖 파일을 수정했는지 검증합니다.
위반 발견 시 경고를 출력하고 리뷰를 요청합니다.

### Context Isolation Guard (컨텍스트 분리 가드레일)

한 세션에서 여러 에이전트를 실행하면 컨텍스트가 오염됩니다.
`UserPromptSubmit` 훅이 다음 위반을 실시간 감지합니다:

- `current_agent`가 running인데 다른 `/harness-*` 스킬 호출 시 경고 주입
- `agent_status`를 completed로 변경하지 않고 다음 에이전트 호출 시 경고

### Statusline (상시 상태 표시)

터미널 하단에 항상 고정되는 1줄 compact 상태:

```
[S1] FULL | >backend | 2/5 feat | ctx 45% | $1.23
```

- `scripts/harness-statusline.sh`가 3초 간격으로 `progress.json`을 읽어 갱신
- `.claude/settings.json`의 `statusLine` 설정으로 활성화
- 세션 시작 시 장황한 프로그래스 출력 대신 statusline으로 대체

### Artifact State Machine

주요 아티팩트는 상태를 추적합니다:

```
pending → draft → reviewed → approved
```

| 아티팩트 | 생성 에이전트 | 필수 상태 (다음 에이전트 진행 조건) |
|----------|-------------|----------------------------------|
| plan.md | Planner | draft 이상 → Generator |
| api-contract.json | Planner | draft 이상 → Generator |
| feature-list.json | Planner | draft 이상 → Generator |
| sprint-contract.md | Generator | draft 이상 → Evaluator |

상태는 `progress.json.artifacts`에서 추적됩니다.

## 세션 오케스트레이션

### 핵심: 한 세션에 1 에이전트 단계

각 에이전트는 독립 Claude Code 세션에서 실행됩니다. 컨텍스트 소진을 방지하고 품질을 유지합니다.

### 상태 관리

| 파일 | 역할 |
|------|------|
| `.harness/progress.json` | 기계 판독 상태 (현재 에이전트, 파이프라인, 실패 정보) |
| `.harness/progress.log` | 사람 판독 히스토리 (append-only) |
| `.harness/handoff.json` | 세션 전환 문서 (prompt, model, thinking_mode, artifacts, regression) |

### 실행 방법

#### 1. 첫 세션: Dispatcher
```
"하네스 엔지니어링 시작" 또는 /harness-dispatcher
```

#### 2. 이후 세션: 새 세션만 열면 자동 진행

에이전트가 완료 후 STOP하면, **새 세션을 시작하기만 하면 됩니다**.
SessionStart 훅이 자동으로:
1. 이전 에이전트의 완료 상태 감지
2. 게이트 체크 실행 (Pre-Eval Gate, 파일 소유권, 아티팩트 선행조건)
3. `handoff.json` 생성 (prompt, model, thinking_mode, regression 등)
4. 다음 에이전트 안내 출력

```
# 새 세션 시작 시 자동 출력 예시:
# Harness: next → /harness-generator-backend  (sonnet)
```

사용자는 안내에 따라 스킬을 호출하면 됩니다.

#### 자동 CLI 실행 (옵션)

완전 자동화를 원하면 아래 명령으로 다음 에이전트를 즉시 시작할 수 있습니다:

```bash
claude --model $(jq -r .model .harness/handoff.json) --prompt "$(jq -r .prompt .harness/handoff.json)"
```

#### 디버깅 (수동)

문제가 생겼을 때만 수동으로 상태를 확인합니다:

```bash
bash scripts/harness-next.sh        # 게이트 체크 + 프로그래스 출력
jq . .harness/handoff.json          # handoff 내용 확인
jq . .harness/progress.json         # 현재 상태 확인
```

### Session Boundary Protocol

모든 에이전트 스킬에 내장된 프로토콜:

- **On Start**: `progress.json` 읽기 → `agent_status: "running"` 설정 → `handoff.json` 참조
- **On Complete**: `progress.json` 업데이트 → 아티팩트 상태 갱신 → `next_agent` 계산 → **STOP**
- **On Fail** (Evaluator): `failure` 정보 기록 → `retry_target` 설정 → **STOP**
- **On Transition**: 파일 소유권 검증 → Pre-Eval Gate (해당 시) → 아티팩트 선행조건 검증

에이전트는 절대 다음 에이전트를 직접 호출하지 않습니다.

### Handoff Document

에이전트 전환 시 `.harness/handoff.json`이 자동 생성됩니다:

```json
{
  "from": "planner",
  "to": "generator-backend",
  "sprint": 1,
  "retry_count": 0,
  "sprint_status": "running",
  "failure_context": null,
  "artifacts_ready": ["plan.md", "api-contract.json", "feature-list.json"],
  "focus_features": ["F-001", "F-002"],
  "warnings": [],
  "timestamp": "2026-04-09T12:00:00Z"
}
```

각 에이전트는 세션 시작 시 이 파일을 읽어 컨텍스트를 확보합니다.

### Escalation Protocol

```
1-2회 실패: 동일 에이전트 재시도 (실패 원인 요약 포함)
3회 실패:   Planner 에스컬레이션 (scope 축소 또는 접근 변경)
5회 실패:   BLOCKED — 사용자 개입 요청
```

## 핵심 원칙

1. **Backend First** — API가 안정된 후 Frontend 연동 (없는 API 호출 방지)
2. **api-contract.json이 진실의 원천** — FE↔Gateway↔Services 간 유일한 계약
3. **한 세션에 1 에이전트 단계** — 컨텍스트 소진 방지, Session Boundary Protocol 준수
4. **feature-list.json의 passes만 수정** — 기능 정의는 Planner만 변경
5. **테스트 삭제/약화 금지** — 테스트는 계약이다
6. **Evaluator는 적대적** — Rubber-stamping 금지, 2.80/3.00 미만 = FAIL, Evidence 없는 Score = 0
7. **아카이브 불변** — 완료 문서 수정 금지
8. **MSA 경계 존수** — 서비스 간 직접 DB 접근 금지, 반드시 메시지 패턴

## Evaluation System (v3.2)

### 정량 채점 (Rubric Scoring)

모든 Evaluator는 구조화된 Rubric으로 채점합니다:

| 설정 | 값 |
|------|------|
| 척도 | 0-3 (항목별) |
| PASS 기준 | **2.80 / 3.00 이상** |
| FAIL 기준 | 2.79 이하 (예외 없음) |
| Evidence 없는 항목 | Score = 0으로 강제 재계산 |

### Evaluator-Functional 채점 항목 (R1-R5)

| # | Criterion | Weight |
|---|-----------|--------|
| R1 | API Contract 준수 | 25% |
| R2 | Acceptance Criteria 전수 통과 | 25% |
| R3 | 부정 테스트 (엔드포인트당 2개+) | 20% |
| R4 | E2E 시나리오 (Playwright) | 15% |
| R5 | 에러 핸들링 & 엣지케이스 | 15% |

### Evaluator-Visual 채점 항목 (V1-V5)

| # | Criterion | Weight |
|---|-----------|--------|
| V1 | 레이아웃 정확성 | 20% |
| V2 | 반응형 (375/768/1280px) | 20% |
| V3 | 접근성 WCAG 2.1 AA | 20% |
| V4 | 시각적 일관성 + AI슬롭 감지 | 20% |
| V5 | 인터랙션 상태 (로딩/에러/빈/호버/포커스) | 20% |

### 자동 FAIL 조건 (Verdict Rules)

어떤 상황에서도 아래 조건 충족 시 FAIL:

1. Weighted Score < 2.80
2. AC 100% 미통과 (부분 통과 불인정)
3. Regression 실패 1건 이상 (신규 점수 무관)
4. Evidence 누락 항목 존재 → 해당 Score = 0 재계산
5. Cross-Validation 불일치 1건 이상 → CONDITIONAL FAIL
6. (Visual) a11y Critical/Serious 위반 1건 이상 → V3 = 0
7. (Visual) AI Slop 2건 이상 → V4 최대 1점

### Executable Acceptance Criteria

Planner는 feature-list.json에 기능을 정의할 때 **실행 가능한 검증 조건(AC)**을 반드시 작성합니다:

```json
{
  "id": "AC-001",
  "description": "유효한 이메일로 가입 시 201 응답",
  "type": "api",
  "verify": {
    "method": "POST",
    "path": "/api/auth/register",
    "body": { "email": "test@test.com", "password": "Test1234!" },
    "expect": { "status": 201 }
  }
}
```

AC 타입: `api` (HTTP 요청), `visual` (UI 요소 존재), `e2e` (사용자 플로우)

### Regression Checkpoint

Sprint N의 Evaluator는 이전 Sprint에서 PASS된 AC를 재검증합니다:
- archive에서 이전 feature-list.json의 passed AC를 로드
- handoff.json의 `regression` 필드로 전달
- **1건이라도 회귀 실패하면 전체 FAIL**

### Cross-Validation

Eval-Functional의 결과를 Eval-Visual이 교차 검증합니다:
- evaluation-functional.md 내 JSON 블록 → handoff.json의 `cross_validation_from_functional`
- API 성공인데 UI에 에러 표시 = 불일치 = FAIL 사유

### Adversarial Rules (적대적 행동 규칙)

Evaluator 에이전트에게 강제되는 행동 규칙:
- Generator의 '완료' 주장을 신뢰하지 않고 직접 검증
- 정상 1개당 비정상 2개 이상 테스트
- PASS 전 자문: "내가 이 코드로 PR을 올리겠는가?"
- '전반적으로 잘 되었습니다' 류의 모호한 긍정 평가 **금지**
- '시간 제약상 일부만 테스트' **금지** — 전수 불가 시 FAIL 처리

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
