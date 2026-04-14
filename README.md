# @walwal-harness/cli

**AI 에이전트를 위한 프로덕션 하네스 엔지니어링 프레임워크**

> Solo: 20min/$9 (broken) → Harness: 6hr/$200 (fully functional)
> — [Anthropic Engineering Blog](https://www.anthropic.com/engineering/harness-design-long-running-apps)

같은 AI 모델이라도 **하네스 설계에 따라 결과물 품질이 극적으로 달라집니다.** walwal-harness는 Anthropic이 제안한 하네스 엔지니어링 패턴을 설치 한 번으로 즉시 사용할 수 있게 패키징한 프레임워크입니다.

---

## 두 가지 모드

| 모드 | 설명 | 실행 방법 |
|------|------|----------|
| **Classic (v3)** | 순차 실행 — Planner → Generator → Evaluator 1세션씩 | `하네스 엔지니어링 시작` |
| **Agent Teams (v4)** | 병렬 실행 — 3 Team이 Feature 단위 Gen→Eval 루프 동시 실행 | `/harness-team` 또는 `npx walwal-harness v4` |

---

## 설치

### 첫 설치

```bash
cd your-project
npm install @walwal-harness/cli
```

`postinstall`이 자동으로:
1. `.harness/` 디렉토리 스캐폴딩
2. `.claude/skills/` 에 에이전트 스킬 설치 (8개)
3. `scripts/` 에 오케스트레이션 스크립트 설치
4. SessionStart / UserPromptSubmit 훅 등록
5. `AGENTS.md` + `CLAUDE.md` 심볼릭 링크 생성

> **중요:** 설치 후 Claude Code 세션을 **재시작**해야 skills가 인식됩니다.

### 기존 설치자 업데이트

```bash
# latest (v3 안정판)
npm update @walwal-harness/cli

# v4 alpha (Agent Teams)
npm install @walwal-harness/cli@next

# 스크립트 동기화 (코어 스크립트 자동 덮어쓰기)
npx walwal-harness
```

### CLI 명령어

```bash
npx walwal-harness            # 초기화 / 스크립트 업데이트
npx walwal-harness --force    # 강제 재초기화
npx walwal-harness studio     # Harness Studio v3 (tmux 5-pane)
npx walwal-harness v4         # Harness Studio v4 (Agent Teams, tmux 6-pane)
npx walwal-harness --help     # 도움말
```

---

## Quick Start — Classic Mode (v3)

### 1. 설치 + 재시작

```bash
cd your-project
npm install @walwal-harness/cli
# Claude Code 재시작 (/exit → 재진입)
```

### 2. 하네스 시작

```
❯ 하네스 엔지니어링 시작
```

또는 Claude Code에서 아무 요청 → UserPromptSubmit 훅이 자동으로 Dispatcher를 호출합니다.

### 3. 파이프라인 자동 선택

Dispatcher가 요청을 분석하여 파이프라인을 결정합니다:

```
FULLSTACK  : Planner → Gen-BE → Gen-FE → Eval-Func → Eval-Visual
FE-ONLY    : Planner(light) → Gen-FE → Eval-Func → Eval-Visual
BE-ONLY    : Planner → Gen-BE → Eval-Func(API-only)
```

### 4. 순차 실행

각 에이전트가 독립 Claude Code 세션에서 실행됩니다:

```
❯ /harness-planner           # Plan 작성
❯ /harness-generator-frontend  # 코드 생성
❯ /harness-evaluator-functional  # E2E 테스트
```

에이전트가 완료되면 **새 세션**을 시작하면 자동으로 다음 에이전트를 안내합니다.

### 5. Eval FAIL → 자동 재작업

Evaluator FAIL 시 → 실패 원인 + 피드백과 함께 Generator로 자동 리라우팅 (최대 10회).

---

## Quick Start — Agent Teams (v4)

> **v4는 alpha 단계입니다.** `npm install @walwal-harness/cli@next`로 설치하세요.

### 개요

3개 Agent Team이 **Feature 단위**로 Gen→Eval 루프를 **병렬 실행**합니다.

```
기존 (v3): Planner → Gen(F-001~028 전부) → Eval(전부)
v4:        Planner → 3 Teams 병렬, 각 Team이 Feature 1개씩 Gen→Eval
```

### 1. 설치

```bash
npm install @walwal-harness/cli@next
npx walwal-harness    # 스크립트 동기화
```

### 2. Planner 실행 (Classic으로)

v4에서도 Planner는 먼저 실행해야 합니다:

```
❯ 하네스 엔지니어링 시작
# Dispatcher → Planner → feature-list.json 생성
```

### 3. Studio 실행

**터미널에서** (Claude 세션 밖에서):

```bash
npx walwal-harness v4
```

### 4. Teams 가동/중지

Studio가 열리면 Main pane의 Claude에서:

```
❯ /harness-team-action    # Queue 초기화 + 3 Teams 백그라운드 실행
❯ /harness-team-stop      # 모든 Teams 중지
```

**흐름 요약:**
```
npx walwal-harness v4     ← 터미널에서 Studio 실행
  Main에서:
    ❯ 하네스 엔지니어링 시작  ← Planner가 feature-list.json 생성
    ❯ /harness-team-action   ← Queue 생성 + Teams 가동 → 자율 실행 시작
    (모니터링, 개입, gotcha 등록...)
    ❯ /harness-team-stop     ← 필요 시 중지
```

### 5. Team 관리 명령어

| 명령 | 동작 |
|------|------|
| `/harness-team-action` | Queue 초기화 + 3 Teams 가동 |
| `/harness-team-stop` | 모든 Teams 중지 |
| `bash scripts/harness-queue-manager.sh status .` | Queue 상태 확인 |
| `bash scripts/harness-queue-manager.sh requeue F-XXX .` | 실패한 Feature 재큐 |
| `tail -f /tmp/harness-team-1.log` | Team 1 로그 실시간 확인 |

### 6. tmux 레이아웃

```
┌──────────────┬──────────────┬──────────────┐
│              │  Progress    │  Team 1      │
│              │  (Queue,     │  Gen→Eval    │
│  Main        │   Teams,     ├──────────────┤
│  (Claude)    │   Features)  │  Team 2      │
│              ├──────────────┤  Gen→Eval    │
│              │  Prompts     ├──────────────┤
│              │  (History)   │  Team 3      │
│              │              │  Gen→Eval    │
└──────────────┴──────────────┴──────────────┘
```

| 패널 | 역할 |
|------|------|
| **Main** | 사용자 대화형 Claude — 오케스트레이터 역할 |
| **Progress** | Feature Queue + Team 상태 + Feature 목록 (자동 갱신) |
| **Prompts** | 사용자 매뉴얼 프롬프트 + Team 활동 로그 (newest first) |
| **Team 1~3** | `claude -p --dangerously-skip-permissions` headless worker |

### 5. 작동 원리

```
Feature Queue (dependency-aware topological sort)
  Ready:   [F-002, F-003, F-007]  ← depends_on 충족된 것만
  Blocked: [F-004, F-005, ...]    ← 선행 Feature 미완료

Team 1: dequeue F-002 → worktree 생성 → Gen → Gate → Eval
  PASS → merge to main → worktree 정리 → unblock dependents → dequeue next
  FAIL → retry (max 3) → 3회 실패 시 failed 처리
```

- 각 Team은 **git worktree**로 격리 실행 (파일 충돌 없음)
- Feature PASS 시 main으로 **auto-merge** + worktree 즉시 삭제
- Merge conflict 시 auto-rebase 시도

### 9. Main에서 할 수 있는 것

Main Claude는 **오케스트레이터**입니다:

| 할 수 있는 것 | 예시 |
|--------------|------|
| Teams 가동/중지 | `/harness-team-action`, `/harness-team-stop` |
| 상태 확인 | `bash scripts/harness-queue-manager.sh status .` |
| 실패 Feature 분석 | "F-003이 왜 실패했는지 로그 확인해줘" |
| Feature 재큐 | `bash scripts/harness-queue-manager.sh requeue F-003 .` |
| 코드 리뷰 | "F-002의 Sidebar 컴포넌트 리뷰해줘" |
| Gotcha 등록 | "API 응답에 created_at은 ISO 8601이어야 해" |

**하지 말 것:** `/harness-generator-*`, `/harness-evaluator-*` 직접 호출 — Team이 처리합니다.

---

## 에이전트

| 에이전트 | 역할 | 모델 |
|----------|------|------|
| **Dispatcher** | 파이프라인 선택 + Gotcha 관리 | opus |
| **Brainstormer** | 러프한 요구사항 대화형 구체화 | opus |
| **Planner** | 제품 사양 + API 계약 + Feature 설계 | opus/ultraplan |
| **Generator-Backend** | NestJS MSA 구현 | sonnet |
| **Generator-Frontend** | React/Next.js UI 구현 | sonnet |
| **Evaluator-Functional** | Playwright E2E 기능 검증 | opus/ultrathink |
| **Evaluator-Visual** | 디자인, 반응형, 접근성 검증 | opus/ultrathink |

### Brainstormer (조건부)

[obra/superpowers](https://github.com/obra/superpowers) (MIT License) 기반. 바이브코딩 수준의 러프한 요구사항을 대화형 Q&A로 구체화합니다.

---

## 핵심 메커니즘

### Auto-Routing

모든 사용자 프롬프트가 Dispatcher를 자동 경유합니다.

```
# per-message opt-out
❯ harness skip 그냥 답해줘

# 전역 비활성
.harness/config.json → behavior.auto_route_dispatcher = false
```

### API Contract — 진실의 원천

`api-contract.json`이 FE ↔ Gateway ↔ Services 간 유일한 계약서입니다.

### Gotcha 시스템

사용자가 실수를 지적하면 Dispatcher가 자동 기록 → 이후 세션에서 반복 방지.

### Pre-Eval Gate

Generator → Evaluator 전환 전 결정론적 검증 (tsc, eslint, test). 실패 시 Evaluator 세션을 열지 않고 Generator로 자동 리라우팅.

```json
// .harness/config.json
"pre_eval_gate": {
  "frontend_checks": ["npx tsc --noEmit", "npx eslint src/", "npx vitest run --bail 1"],
  "frontend_cwd": "path/to/frontend"  // 프로젝트 루트와 다른 경우
}
```

### Evaluation System

| 설정 | 값 |
|------|------|
| PASS 기준 | 2.80 / 3.00 이상 |
| FAIL 기준 | 2.79 이하 (예외 없음) |
| Evidence 없는 Score | 0점 강제 |
| Regression 실패 | 1건이라도 → 전체 FAIL |

---

## Harness Studio (tmux)

### Studio v3 (Classic)

```bash
npx walwal-harness studio
```

```
┌──────────────┬──────────────┐
│  Dashboard    │ Monitor      │
│  (Progress)   ├──────────────┤
├──────────────┤ Agent Session │
│  Control      ├──────────────┤
│  (harness>)   │ Eval Review  │
└──────────────┴──────────────┘
```

### Studio v4 (Agent Teams)

```bash
npx walwal-harness v4
```

```
┌──────────────┬──────────────┬──────────────┐
│              │  Progress    │  Team 1      │
│  Main        ├──────────────┤  Team 2      │
│  (Claude)    │  Prompts     │  Team 3      │
└──────────────┴──────────────┴──────────────┘
```

---

## 프로젝트 구조

```
your-project/
├── AGENTS.md                           # 에이전트 공통 컨텍스트
├── CLAUDE.md → AGENTS.md               # 심볼릭 링크
├── scripts/
│   ├── harness-next.sh                 # 세션 오케스트레이터
│   ├── harness-session-start.sh        # SessionStart 훅
│   ├── harness-user-prompt-submit.sh   # UserPromptSubmit 훅
│   ├── harness-queue-manager.sh        # v4: Feature Queue 관리
│   ├── harness-team-worker.sh          # v4: Team Worker (Gen→Eval 루프)
│   ├── harness-studio-v4.sh            # v4: tmux 레이아웃
│   ├── harness-dashboard-v4.sh         # v4: Progress 패널
│   ├── harness-prompts-v4.sh           # v4: Prompts 패널
│   └── lib/
├── .harness/
│   ├── config.json                     # 하네스 설정
│   ├── HARNESS.md                      # 상세 가이드
│   ├── progress.json                   # 세션 간 상태
│   ├── progress.log                    # append-only 히스토리
│   ├── gotchas/                        # 에이전트별 실수 기록
│   ├── actions/
│   │   ├── feature-list.json           # 기능 목록 + AC
│   │   ├── feature-queue.json          # v4: Feature Queue 상태
│   │   ├── api-contract.json           # API 계약서
│   │   └── plan.md                     # 제품 사양
│   └── archive/                        # 완료 스프린트 보관
└── .claude/
    ├── settings.json                   # 훅 등록
    └── skills/                         # Claude Code 스킬 (8개)
```

---

## Playwright MCP 설정

Evaluator가 브라우저 테스트를 수행하려면 Playwright MCP가 필요합니다:

```json
// ~/.mcp.json
{
  "mcpServers": {
    "playwright": {
      "command": "npx",
      "args": ["-y", "@playwright/mcp@latest", "--headless", "--caps", "vision"]
    }
  }
}
```

---

## 트러블슈팅

### Skills가 로드되지 않아요

```bash
/exit  # Claude Code 세션 종료
# 프로젝트 디렉토리에서 재진입
```

### 스크립트가 구버전이에요

```bash
npx walwal-harness  # 코어 스크립트 자동 덮어쓰기
```

### v4 Team이 "No features ready" 반복

```bash
# Studio를 재시작하면 자동으로 stale in_progress 복구
npx walwal-harness v4
```

### Auto-routing 끄기

```
❯ harness skip 답만 해줘
```

또는 `.harness/config.json`에서 `behavior.auto_route_dispatcher = false`

---

## 참고

- [Anthropic: Effective Harnesses for Long-Running Agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents)
- [Anthropic: Harness Design for Long-Running Application Development](https://www.anthropic.com/engineering/harness-design-long-running-apps)
- [Claude Code Skills Documentation](https://code.claude.com/docs/en/skills)
- [obra/superpowers](https://github.com/obra/superpowers) — Brainstorming skill (MIT License)

## License

MIT
