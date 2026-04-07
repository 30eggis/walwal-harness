# walwal-harness

**AI 에이전트를 위한 프로덕션 하네스 엔지니어링 프레임워크**

> Solo: 20min/$9 (broken) → Harness: 6hr/$200 (fully functional)
> — [Anthropic Engineering Blog](https://www.anthropic.com/engineering/harness-design-long-running-apps)

같은 AI 모델이라도 **하네스 설계에 따라 결과물 품질이 극적으로 달라집니다.** walwal-harness는 Anthropic이 제안한 하네스 엔지니어링 패턴을 설치 한 번으로 즉시 사용할 수 있게 패키징한 프레임워크입니다.

## 무엇을 하는가

6개의 전문화된 AI 에이전트가 **역할 분리 + 피드백 루프**로 소프트웨어를 만듭니다:

```
"하네스 엔지니어링 시작"
         │
         ▼
    DISPATCHER ─── 요청 분석 ─── 파이프라인 자동 선택
         │
    ┌────┴────┬──────────┐
    ▼         ▼          ▼
 FULLSTACK  FE-ONLY   BE-ONLY
```

### FULLSTACK (신규 프로젝트)
```
Planner → Generator-BE → Generator-FE → Evaluator-Func → Evaluator-Visual
                                              │ FAIL
                                              └──→ 재작업 (max 10회)
```

### FE-ONLY (기존 API에 프론트엔드 연동)
```
Planner(light) → Generator-FE → Evaluator-Func → Evaluator-Visual
     └─ OpenAPI → api-contract.json 자동 변환
```

### BE-ONLY (기존 서버에 백엔드 기능 추가)
```
Planner → Generator-BE → Evaluator-Func(API-only)
```

## 설치

```bash
npm install @walwal-harness/cli
```

`postinstall`이 자동으로 프로젝트 루트에 설치합니다:
- `.harness/` 디렉토리 스캐폴딩 (actions, archive, gotchas)
- `.claude/skills/` 에 6개 에이전트 스킬 설치
- `AGENTS.md` 생성 + `CLAUDE.md` 심볼릭 링크
- 기존 프로젝트면 구조 스캔 → IA-MAP 자동 생성

> **Note:** `npm install` 후 Claude Code 세션을 **재시작**해야 skills가 인식됩니다.
> Claude Code는 세션 시작 시 `.claude/skills/`를 스캔하므로, 설치 후 `/exit` → 재진입이 필요합니다.

### CLI 명령

```bash
npx walwal-harness           # 초기화 (postinstall과 동일)
npx walwal-harness --force   # 강제 재초기화 (기존 파일 덮어쓰기)
npx walwal-harness --help    # 도움말
```

## 사용법

Claude Code를 **재시작**한 뒤:

```
> 하네스 엔지니어링 시작
```

이 한 마디로 Dispatcher가 실행되어:
1. 프로젝트 초기화 상태 확인 (빈 프로젝트 / 기존 프로젝트 자동 감지)
2. 사용자 요청 분석 → 파이프라인 선택
3. 순차적으로 에이전트 실행

## 6개 에이전트

| 에이전트 | 역할 | SKILL |
|----------|------|-------|
| **Dispatcher** | 파이프라인 선택 + Gotcha 관리 | `harness-dispatcher` |
| **Planner** | 제품 사양 + API 계약서 + IA-MAP 설계 | `harness-planner` |
| **Generator-Backend** | NestJS MSA 구현 (Gateway + Microservices) | `harness-generator-backend` |
| **Generator-Frontend** | React/Next.js UI + API 연동 | `harness-generator-frontend` |
| **Evaluator-Functional** | Playwright E2E 기능 검증 + IA 구조 검증 | `harness-evaluator-functional` |
| **Evaluator-Visual** | 디자인 일관성, 반응형, 접근성, AI슬롭 감지 | `harness-evaluator-visual` |

## 핵심 기능

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

## 디렉토리 구조

설치 후 프로젝트에 생성되는 구조:

```
your-project/
├── AGENTS.md                       # 에이전트 공통 컨텍스트 (Planner 관리)
├── CLAUDE.md → AGENTS.md           # 심볼릭 링크
├── .harness/
│   ├── config.json                 # 하네스 설정
│   ├── progress.json               # 세션 간 상태 (기계 판독)
│   ├── gotchas/                    # 에이전트별 실수 기록
│   │   ├── planner.md
│   │   ├── generator-backend.md
│   │   ├── generator-frontend.md
│   │   ├── evaluator-functional.md
│   │   └── evaluator-visual.md
│   ├── actions/                    # 활성 스프린트 문서
│   │   ├── pipeline.json
│   │   ├── plan.md
│   │   ├── feature-list.json
│   │   ├── api-contract.json
│   │   └── sprint-contract.md
│   └── archive/                    # 완료 스프린트 보관 (불변)
│       └── sprint-NNN/
└── .claude/skills/                 # Claude Code 스킬
    ├── harness-dispatcher/
    ├── harness-planner/
    ├── harness-generator-backend/
    ├── harness-generator-frontend/
    ├── harness-evaluator-functional/
    └── harness-evaluator-visual/
```

## Tech Stack

| 영역 | 기술 |
|------|------|
| Backend | NestJS (TypeScript) + MSA |
| Frontend | React 또는 Next.js (TypeScript) |
| Styling | Tailwind CSS |
| E2E Testing | Playwright MCP |
| Unit Testing | Jest (BE) + Vitest (FE) |
| Database | PostgreSQL / SQLite |

## 권장 외부 스킬

하네스는 자체 reference 파일로 기본 가이드를 제공하지만, 아래 외부 스킬을 설치하면 품질이 향상됩니다. 초기화 시 자동으로 설치 여부를 체크하고 안내합니다.

| 스킬 | 설명 | 사용 에이전트 |
|------|------|-------------|
| **vercel** | Vercel/Next.js 배포, 성능 최적화, AI SDK | Generator-FE |
| **web-design-guidelines** | UI/UX 접근성, Web Interface Guidelines | Evaluator-Visual, Generator-FE |
| **taste-skill** | AI 생성 UI 디자인 품질, AI슬롭 감지 | Evaluator-Visual, Generator-FE |
| **supanova-design-skill** | 디자인 시스템 규칙, 시각적 일관성 | Evaluator-Visual, Generator-FE |

## Playwright MCP 설정

Evaluator가 브라우저 테스트를 수행하려면 Playwright MCP가 필요합니다. `~/.mcp.json`에 추가:

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

## 참고

- [Anthropic: Effective Harnesses for Long-Running Agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents)
- [Anthropic: Harness Design for Long-Running Application Development](https://www.anthropic.com/engineering/harness-design-long-running-apps)
- [Claude Code Skills Documentation](https://code.claude.com/docs/en/skills)
- [Skill Authoring Best Practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices)

## License

MIT
