# walwal-harness

**AI 에이전트를 위한 프로덕션 하네스 엔지니어링 프레임워크**

> Solo: 20min/$9 (broken) → Harness: 6hr/$200 (fully functional)
> — [Anthropic Engineering Blog](https://www.anthropic.com/engineering/harness-design-long-running-apps)

같은 AI 모델이라도 **하네스 설계에 따라 결과물 품질이 극적으로 달라집니다.** walwal-harness는 Anthropic이 제안한 하네스 엔지니어링 패턴을 설치 한 번으로 즉시 사용할 수 있게 패키징한 프레임워크입니다.

---

## 설치

```bash
npm install @walwal-harness/cli
```

`postinstall`이 자동으로 프로젝트 루트에 설치합니다:

1. `.harness/` 디렉토리 스캐폴딩 (actions, archive, gotchas, config)
2. `.claude/skills/` 에 에이전트 스킬 설치 (9개)
3. `scripts/` 에 오케스트레이션 헬퍼 스크립트 설치
4. `SessionStart` 훅 등록 (세션 시작 시 진행 상태 표시)
5. `UserPromptSubmit` 훅 등록 (모든 프롬프트를 Dispatcher 경유 자동 라우팅)
6. `AGENTS.md` 생성 + `CLAUDE.md` 심볼릭 링크
7. 기존 프로젝트면 구조 스캔 → IA-MAP 자동 생성

> **중요:** 설치 후 Claude Code 세션을 **재시작**해야 skills가 인식됩니다.
> `/exit` → 디렉터리 재진입이 필요합니다.

### CLI 명령

```bash
npx walwal-harness           # 초기화 (postinstall과 동일)
npx walwal-harness --force   # 강제 재초기화 (기존 파일 덮어쓰기)
npx walwal-harness --help    # 도움말
```

### 초기화에서 일어나는 일

```
your-project/
├── AGENTS.md                       # 에이전트 공통 컨텍스트 (Planner 관리)
├── CLAUDE.md → AGENTS.md           # 심볼릭 링크
├── scripts/
│   ├── harness-next.sh             # 세션 오케스트레이터
│   ├── harness-session-start.sh    # SessionStart 훅
│   ├── harness-user-prompt-submit.sh  # UserPromptSubmit 훅 (auto-routing)
│   ├── scan-project.sh             # 프로젝트 구조 스캔
│   ├── init-agents-md.sh           # AGENTS.md 생성/리빌드
│   └── lib/
│       └── harness-render-progress.sh  # 프로그레스 바 렌더러
├── .harness/
│   ├── config.json                 # 하네스 설정
│   ├── HARNESS.md                  # 하네스 상세 가이드
│   ├── progress.json               # 세션 간 상태 (기계 판독)
│   ├── gotchas/                    # 에이전트별 실수 기록
│   ├── actions/                    # 활성 스프린트 문서
│   └── archive/                    # 완료 스프린트 보관 (불변)
└── .claude/
    ├── settings.json               # 훅 등록 (SessionStart + UserPromptSubmit)
    └── skills/                     # Claude Code 스킬 (9개)
        ├── harness-dispatcher/
        ├── harness-brainstorming/
        ├── harness-planner/
        ├── harness-generator-backend/
        ├── harness-generator-frontend/
        ├── harness-generator-frontend-flutter/
        ├── harness-evaluator-functional/
        ├── harness-evaluator-functional-flutter/
        └── harness-evaluator-visual/
```

---

## Quick Start

### 1. 설치 + 재시작

```bash
cd your-project
npm install @walwal-harness/cli
# Claude Code 세션 재시작 (/exit → 재진입)
```

### 2. 하네스 시작

Claude Code에서 아무 요청이나 입력하면 **UserPromptSubmit 훅이 자동으로 Dispatcher를 호출**합니다. 또는 명시적으로:

```
> 하네스 엔지니어링 시작
```

### 3. Dispatcher가 분류

```
사용자 입력
    │
    ├─ 신규 기능/제품 요청 → 파이프라인 선택 (FULLSTACK / FE-ONLY / BE-ONLY)
    │   └─ "브레인스토밍 필요합니까?" → Y: Brainstormer → Planner
    │                                  → N: Planner 직행
    ├─ 실수 지적 → Gotcha 기록 → 해당 에이전트 재작업
    ├─ 특정 에이전트 명령 → 해당 에이전트 직접 라우팅
    └─ 메타/인사 → 일반 응답
```

### 4. 에이전트 순차 실행

각 에이전트가 완료되면 다음 프롬프트를 제안합니다:

```
✓ Dispatcher 완료. bash scripts/harness-next.sh 실행하여 다음 단계 확인.
```

`bash scripts/harness-next.sh` 를 실행하면 프로그레스 바 + 다음 에이전트 안내:

```
═══ Sprint 1 / FULLSTACK ═══════════════════

Agents: planner✓ → generator-backend✓ → [generator-frontend] → evaluator-functional → evaluator-visual

/harness-generator-frontend 를 실행하세요.
```

### 5. 반복

FAIL이 발생하면 Evaluator가 원인을 분석하고 해당 Generator로 자동 재작업 라우팅 (최대 10회). PASS하면 다음 Evaluator로 진행. 모든 Evaluator를 통과하면 스프린트 완료 → 아카이브.

---

## 파이프라인

Dispatcher가 사용자 요청을 분석하여 3가지 파이프라인 중 하나를 자동 선택합니다:

### FULLSTACK (신규 프로젝트)

```
Brainstormer? → Planner → Generator-BE → Generator-FE → Evaluator-Func → Evaluator-Visual
                                                              │ FAIL
                                                              └──→ 재작업 (max 10회)
```

### FE-ONLY (기존 API에 프론트엔드 연동)

```
Brainstormer? → Planner(light) → Generator-FE → Evaluator-Func → Evaluator-Visual
                    └─ OpenAPI → api-contract.json 자동 변환
```

### BE-ONLY (기존 서버에 백엔드 기능 추가)

```
Brainstormer? → Planner → Generator-BE → Evaluator-Func(API-only)
```

> `Brainstormer?` = Dispatcher가 사용자에게 확인 후 조건부 실행. 명확한 PRD/OpenAPI가 있으면 생략 가능.

### Flutter 프로젝트 자동 감지

`pubspec.yaml` + `flutter:` 키가 감지되면 FE 에이전트가 **자동 치환**됩니다:

| React (기본) | Flutter |
|-------------|---------|
| `generator-frontend` | `generator-frontend-flutter` |
| `evaluator-functional` (Playwright) | `evaluator-functional-flutter` (flutter analyze/test) |
| `evaluator-visual` | **SKIP** (브라우저 없음) |

치환은 `pipeline.json.fe_stack` 값에 의해 `harness-next.sh`가 자동 처리합니다. Planner가 프로젝트 스캔 결과를 보고 `fe_stack`을 확정합니다.

---

## 에이전트

### 9개 에이전트 (조건부 포함)

| 에이전트 | 역할 | 호출 조건 |
|----------|------|----------|
| **Dispatcher** | 파이프라인 선택 + Gotcha 관리 + 라우팅 | 항상 (auto-routing 훅) |
| **Brainstormer** | 러프한 요구사항을 대화형으로 구체화 | Dispatcher가 사용자에게 확인 후 |
| **Planner** | 제품 사양 + API 계약서 + 서비스 분할 | 파이프라인 시작 시 |
| **Generator-Backend** | NestJS MSA 구현 (Gateway + Microservices) | FULLSTACK, BE-ONLY |
| **Generator-Frontend** | React/Next.js UI + API 연동 | FULLSTACK, FE-ONLY (React) |
| **Generator-Frontend-Flutter** | Flutter (Riverpod + Retrofit + ARB i18n) | FULLSTACK, FE-ONLY (Flutter) |
| **Evaluator-Functional** | Playwright E2E 기능 검증 | FULLSTACK, FE-ONLY (React) |
| **Evaluator-Functional-Flutter** | flutter analyze/test + 정적 anti-pattern 검증 | FULLSTACK, FE-ONLY (Flutter) |
| **Evaluator-Visual** | 디자인 일관성, 반응형, 접근성, AI슬롭 감지 | FULLSTACK, FE-ONLY (React만) |

### Brainstormer (조건부)

[obra/superpowers](https://github.com/obra/superpowers) (MIT License)의 brainstorming 방법론을 이식.
바이브코딩 수준의 러프한 요구사항을 **대화형 Q&A로 구체화**하여 Planner가 바로 소비할 수 있는 `brainstorm-spec.md`로 만듭니다.

**핵심 원칙:**
- HARD-GATE: 사용자 승인 없이 구현 단계로 넘어갈 수 없음
- 한 번에 한 질문, 객관식 우선
- 2-3개 접근법 제시 후 사용자가 선택
- Spec self-review + User Review Gate

**실행 조건:** Dispatcher가 "브레인스토밍 과정이 필요합니까? (Y/N)" 라고 묻고 사용자가 Y 응답한 경우에만. 피드백/이터레이션/직접 명령에서는 자동 스킵.

---

## 핵심 메커니즘

### Auto-Routing (UserPromptSubmit Hook)

설치 시 `.claude/settings.json`에 `UserPromptSubmit` 훅이 자동 등록됩니다. 모든 사용자 프롬프트가 Dispatcher를 경유하도록 컨텍스트를 주입합니다.

**per-message opt-out:**
```
> harness skip 그냥 이것만 답해줘
> harness 없이 질문 하나만
> without harness ...
```

**전역 비활성:**
```json
// .harness/config.json
{ "behavior": { "auto_route_dispatcher": false } }
```

### API Contract — 진실의 원천

`api-contract.json`이 Frontend ↔ Gateway ↔ Microservices 간 유일한 계약서입니다. Planner만 수정 가능하며, Generator-BE는 이를 구현하고, Generator-FE는 이를 소비합니다.

### AGENTS.md — 에이전트 불문 범용 컨텍스트

모든 AI 에이전트(Claude, Cursor, Copilot, Windsurf)가 읽을 수 있는 공통 진입점입니다. 1차원 IA-MAP으로 폴더별 책임과 소유 에이전트를 명시합니다.

```
├── apps/gateway/     # [BE] API Gateway       → Generator-Backend
├── apps/service-a/   # [BE] Microservice      → Generator-Backend
├── apps/web/         # [FE] Frontend App      → Generator-Frontend
└── .harness/         # [HARNESS] 하네스 시스템  → Planner
```

### Gotcha 시스템 — 실수를 반복하지 않는 에이전트

사용자가 에이전트의 실수를 지적하면 Dispatcher가 자동으로 감지하여 해당 에이전트의 gotchas 파일에 기록합니다. 이후 세션에서 에이전트는 시작 시 자신의 gotchas를 읽고 같은 실수를 반복하지 않습니다.

```
사용자: "API 응답에 created_at은 ISO 8601로 반환해야 해"
  → Dispatcher: generator-backend.md에 [G-001] 기록
  → Generator-BE 다음 세션: gotchas 읽기 → 같은 실수 방지
```

### IA Structure Compliance — Step 0 Gate

Evaluator는 기능 테스트 전에 AGENTS.md의 IA-MAP과 실제 폴더 구조를 대조합니다. 경로 누락이나 소유권 침범이 발견되면 **기능 테스트 없이 즉시 FAIL**합니다.

### 브라운필드 지원

기존 프로젝트에 설치하면:
- `scan-project.sh`가 Tech Stack, 폴더 구조, 기존 CLAUDE.md를 자동 스캔
- 기존 CLAUDE.md 규칙을 "Preserved Rules" 섹션으로 이관
- 원본은 `.harness/archive/pre-harness-backup/`에 백업
- Flutter 프로젝트 자동 감지 (`pubspec.yaml` + `flutter:`)

---

## FE 스택별 지원

### React / Next.js (기본)

| 항목 | 상세 |
|------|------|
| Generator | `harness-generator-frontend` — RSC, App Router, Tailwind CSS, Cache Components |
| Evaluator-Func | `harness-evaluator-functional` — Playwright MCP (`browser_*`) E2E 테스트 |
| Evaluator-Visual | `harness-evaluator-visual` — 스크린샷 기반 디자인/접근성/반응형 검증 |
| 레퍼런스 | Vercel Best Practices, Design System Rules, AI Forbidden Patterns, Component Patterns |

### Flutter (Dart)

| 항목 | 상세 |
|------|------|
| Generator | `harness-generator-frontend-flutter` — Riverpod + integrated_data_layer(Retrofit) + ARB i18n |
| Evaluator-Func | `harness-evaluator-functional-flutter` — `flutter analyze` + `flutter test` + build_runner drift + anti-pattern grep (FL-01~FL-08) |
| Evaluator-Visual | **SKIP** (Flutter 앱은 브라우저 기반 시각 검증 불가) |
| 레퍼런스 | API Layer Pattern, Riverpod Pattern, i18n Pattern, Anti-Patterns (9개 금지 패턴 + 셀프 체크 스크립트) |

### FE 스택 감지

1. `scan-project.sh`가 `pubspec.yaml` + `flutter:` 키를 탐지
2. Planner가 `pipeline.json.fe_stack = "flutter"` 확정
3. `harness-next.sh`가 FE 에이전트를 자동 치환 (Agent Bar에도 반영)

---

## 스크립트 레퍼런스

| 스크립트 | 설명 | 실행 방법 |
|----------|------|----------|
| `harness-next.sh` | 세션 오케스트레이터 — progress.json 읽고 다음 에이전트 결정, 프로그레스 바 출력 | `bash scripts/harness-next.sh` |
| `scan-project.sh` | 프로젝트 구조 스캔 → `.harness/actions/scan-result.json` 출력 | `bash scripts/scan-project.sh .` |
| `init-agents-md.sh` | scan-result.json 기반 AGENTS.md 생성/리빌드 | `bash scripts/init-agents-md.sh .` |
| `harness-session-start.sh` | SessionStart 훅 — 세션 시작 시 progress 요약 출력 | (자동 — .claude/settings.json 훅) |
| `harness-user-prompt-submit.sh` | UserPromptSubmit 훅 — 모든 프롬프트를 Dispatcher 경유 라우팅 | (자동 — .claude/settings.json 훅) |

---

## Tech Stack

| 영역 | 기술 |
|------|------|
| Backend | NestJS (TypeScript) + MSA |
| Frontend (React) | React 또는 Next.js (TypeScript) + Tailwind CSS |
| Frontend (Flutter) | Flutter (Dart) + Riverpod + Retrofit + ARB i18n |
| E2E Testing (React) | Playwright MCP |
| E2E Testing (Flutter) | flutter analyze + flutter test + 정적 검증 |
| Unit Testing | Jest (BE) + Vitest (FE-React) + flutter test (FE-Flutter) |
| Database | PostgreSQL / SQLite |

---

## 권장 외부 스킬

하네스는 자체 reference 파일로 기본 가이드를 제공하지만, 아래 외부 스킬을 설치하면 품질이 향상됩니다. 초기화 시 자동으로 설치 여부를 체크하고 안내합니다.

| 스킬 | 설명 | 사용 에이전트 |
|------|------|-------------|
| **vercel** | Vercel/Next.js 배포, 성능 최적화, AI SDK | Generator-FE |
| **web-design-guidelines** | UI/UX 접근성, Web Interface Guidelines | Evaluator-Visual, Generator-FE |
| **taste-skill** | AI 생성 UI 디자인 품질, AI슬롭 감지 | Evaluator-Visual, Generator-FE |
| **supanova-design-skill** | 디자인 시스템 규칙, 시각적 일관성 | Evaluator-Visual, Generator-FE |

---

## Playwright MCP 설정 (React 프로젝트)

Evaluator-Functional / Evaluator-Visual이 브라우저 테스트를 수행하려면 Playwright MCP가 필요합니다. `~/.mcp.json`에 추가:

```json
{
  "mcpServers": {
    "playwright": {
      "command": "npx",
      "args": ["-y", "@playwright/mcp@latest", "--headless", "--caps", "vision"]
    }
  }
}
```

> Flutter 프로젝트에서는 Playwright가 필요 없습니다 — `evaluator-functional-flutter`는 `flutter analyze` + `flutter test` 기반입니다.

---

## 트러블슈팅

### Skills가 로드되지 않아요

```bash
# Claude Code 세션을 완전히 종료하고 다시 시작
/exit
# 프로젝트 디렉토리에서 재진입 후 확인
```

Claude Code는 세션 시작 시 `.claude/skills/`를 스캔합니다. `npm install` 이후 반드시 세션 재시작이 필요합니다.

### Dispatcher가 자동 호출되지 않아요

`UserPromptSubmit` 훅이 정상적으로 등록되었는지 확인:

```bash
cat .claude/settings.json
# hooks.UserPromptSubmit 배열에 harness-user-prompt-submit.sh가 있어야 함
```

등록이 안 되었다면:

```bash
npx walwal-harness --force
# 재시작
```

### 브레인스토밍이 매번 실행돼서 피로해요

Brainstormer는 Dispatcher가 "브레인스토밍 필요합니까?" 물을 때만 실행됩니다. **N**으로 답하면 Planner로 직행합니다. 피드백/이터레이션/특정 에이전트 명령에서는 질문 자체가 나오지 않습니다.

### Flutter 프로젝트인데 React 에이전트가 실행돼요

```bash
# 프로젝트 루트에 pubspec.yaml이 있고 flutter: 키가 존재하는지 확인
grep "flutter:" pubspec.yaml

# 재스캔
bash scripts/scan-project.sh .
# pipeline.json의 fe_stack 값 확인
cat .harness/actions/pipeline.json | jq '.fe_stack'
```

### Auto-routing을 끄고 싶어요

```json
// .harness/config.json
{ "behavior": { "auto_route_dispatcher": false } }
```

또는 개별 메시지에서:

```
> harness skip 그냥 이것만 답해줘
```

---

## 참고

- [Anthropic: Effective Harnesses for Long-Running Agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents)
- [Anthropic: Harness Design for Long-Running Application Development](https://www.anthropic.com/engineering/harness-design-long-running-apps)
- [Claude Code Skills Documentation](https://code.claude.com/docs/en/skills)
- [obra/superpowers](https://github.com/obra/superpowers) — Brainstorming skill 원본 (MIT License)

## License

MIT
