# @walwal-harness/cli

**AI 에이전트를 위한 프로덕션 하네스 엔지니어링 프레임워크**

> Solo: 20min/$9 (broken) → Harness: 6hr/$200 (fully functional)
> — [Anthropic Engineering Blog](https://www.anthropic.com/engineering/harness-design-long-running-apps)

같은 AI 모델이라도 **하네스 설계에 따라 결과물 품질이 극적으로 달라집니다.** walwal-harness는 Anthropic이 제안한 하네스 엔지니어링 패턴을 설치 한 번으로 즉시 사용할 수 있게 패키징한 프레임워크입니다.

---

## Run Book — 0 → 첫 스프린트 완주

> 프로젝트 루트에서 `npm i @walwal-harness/cli` 를 마치고 Claude Code 를 재시작한 뒤 아래 순서 그대로 진행합니다.

### Step 1. Dispatcher — 들어오자마자

Claude Code 세션을 연 뒤 첫 메시지로:

```
하네스 엔지니어링 시작
```

Dispatcher 가:
- 요청을 분류 (기능 요청 / 실수 지적 / 메타 질문)
- `FULLSTACK` / `FE-ONLY` / `BE-ONLY` 파이프라인 결정 → `actions/pipeline.json`
- 신규/재플래닝이면 "Brainstormer 를 거칠지" 한 번 묻고 `next_agent` 설정 후 STOP

완료되면 **새 세션을 열기만 하면** SessionStart 훅이 다음 에이전트(`planner` 또는 `brainstorming`)를 안내합니다.

### Step 2. Planner

새 세션에서:

```
/harness-planner
```

Planner 가 `plan.md` + `feature-list.json` + `api-contract.json` 을 생성합니다. AC(Acceptance Criteria)는 반드시 **Executable** 포맷으로 기술됩니다.

### Step 3. Solo / Team 모드 선택

Planner 완료 후 두 갈래 중 하나.

| 선택 | 명령 | 언제 |
|------|------|------|
| **Solo** | 프롬프트로 `/harness-generator-backend` → `/harness-generator-frontend` → `/harness-evaluator-*` 순차 호출 | 학습 목적 · feature 3개 이하 · 레이아웃이 좁음 |
| **Team** | `/harness-team` | feature 4개 이상 · 병렬로 확 밀고 싶을 때 |

### Step 4. Team 모드 — Dashboard 띄우기

Team 모드는 tmux 통합 Studio 레이아웃을 제공합니다:

```bash
# Claude Code 내에서
> /harness-team

# 또는 외부 터미널에서
npx walwal-harness team
```

첫 실행 시 자동으로:
1. `feature-queue.json` 초기화 (의존성 topological sort)
2. tmux (또는 iTerm2 native split) 레이아웃 구축
3. 3개 팀 worker 가 Gen → Eval 루프를 병렬 실행
4. 팀이 feature 완료 시 자동 dequeue
5. 5회 초과 실패하면 사용자 개입 요청

#### 대시보드 구성

```
┌────────────────────┬──────────────────────────┬───────────┐
│ Dashboard          │ Gotcha & Memory          │ TEAM 1    │
│  - pipeline/sprint │  - 활성 에이전트 gotcha   │  Gen|Eval │
│  - feature 진행도  │  - 나머지 에이전트 요약    ├───────────┤
│  - queue 상태      │  - SHARED MEMORY          │ TEAM 2    │
│                    │   (memory.md 최근 N)      │  Gen|Eval │
├────────────────────┤                          ├───────────┤
│ Archive Prompt     │                          │ TEAM 3    │
│  (완료 feature 요약)│                          │  Gen|Eval │
└────────────────────┴──────────────────────────┴───────────┘
```

| 패널 | 내용 | 소스 |
|------|------|------|
| **Dashboard** | Pipeline · Sprint · Feature passes (●/◐/○/◌/✗) · Queue R:B:P · Retry | `harness-dashboard.sh` |
| **Gotcha & Memory** | 활성 에이전트의 누적 실수 + 나머지 요약 + 공유 메모리 | `harness-gotcha-memory.sh` |
| **TEAM 1–3** | 각 워커의 현재 feature · phase(Gen/Eval) · 실시간 stdout | `harness-queue-manager.sh` worker loop |
| **Archive Prompt** | 직전 완료 feature 요약 (다음 팀 컨텍스트 주입용) | archive 디렉토리 |

- 새로고침 주기: `HARNESS_REFRESH=5` (초). 환경변수로 조정.
- 단축키: `tmux prefix + 방향키` 로 패널 이동, `prefix + z` 로 확대/축소.
- 종료: `npx walwal-harness team --kill`.

### Step 5. Feedback 등록 — 학습 누적

대화 중 사용자 피드백은 **성격에 따라 3개 저장소** 중 하나로 자동 분류됩니다.

| 유형 | 성격 | 시그널 | 저장 위치 | ID |
|------|------|--------|----------|-----|
| **Gotcha** | 에이전트 실수(부정) | "~하지 마", "잘못됐어" | `.harness/gotchas/<agent>.md` | `G-NNN` |
| **Convention** | 하우스 스타일(긍정) | "~해야 해", "이렇게 해줘" | `.harness/conventions/<scope>.md` | `C-NNN` |
| **Memory** | 전체 공통 교훈 | "모든 에이전트가~" | `.harness/memory.md` | `M-NNN` |

#### 5a. Gotcha — "이러면 안 돼"

사용자가 에이전트의 실수를 지적하면 Dispatcher 가 해당 에이전트의 `.harness/gotchas/<agent>.md` 에 자동 append. 다음 세션부터 그 에이전트는 세션 시작 시 자기 gotcha 파일을 읽고 같은 실수를 피합니다.

#### 예제 — 실수 지적

```
아니 그렇게 하면 안 되지. Generator-Backend 가 MockServer 를 무시하고
실제 DB 에 붙으려고 하는데, npm run dev 에서 MockServer 가 concurrent 로
기동되어 있으니 그걸 먼저 확인하고 써.
```

Dispatcher 는 자동으로 분류:
- **대상 에이전트**: `generator-backend`
- **저장 위치**: `.harness/gotchas/generator-backend.md`
- **ID 할당**: `[G-002]` (기존 항목 다음 번호)

#### 기록 포맷 (Dispatcher 가 자동 작성)

```markdown
### [G-002] MockServer + npm run dev 자동 기동 + OpenAPI 동기화
- **Date**: 2026-04-22
- **Severity**: HIGH
- **Occurrences**: 1
- **Symptom**: 실제 DB 연결 시도 → 연결 실패로 스프린트 중단
- **Rule**: `npm run dev` 는 MockServer 를 concurrent 로 기동한다.
  API 호출 전 `http://localhost:3001/health` 를 확인할 것.
- **Applies to**: generator-backend
```

#### 5b. Convention — "이렇게 해줘"

긍정 가이드는 하우스 스타일로 등록됩니다:

```
API 응답 필드는 전부 snake_case 로 해야 해. FE TS 모델이
snake_case 로 정의돼 있어서 변환 레이어를 두기 싫어.
```

Dispatcher 자동 분류:
- **스코프**: `generator-backend` (API 응답 → BE 스코프)
- **저장 위치**: `.harness/conventions/generator-backend.md`
- **ID 할당**: `[C-001]` (해당 파일의 기존 최댓값 + 1)

기록 포맷 (자동 작성):

```markdown
### [C-001] API 응답 필드는 snake_case
- **Date**: 2026-04-22
- **Scope**: generator-backend
- **Rule**: 모든 API 응답 JSON 필드는 snake_case (created_at, user_id 등).
- **Rationale**: FE TS 모델이 snake_case 로 정의돼 있어 변환 레이어 불필요.
- **Applies to**: generator-backend, libs/shared-dto
- **Added from**: user prompt (2026-04-22 16:12)
```

#### 스코프 판별 (Convention)

| 키워드 | 스코프 (파일) |
|--------|-------------|
| backend, API, controller, service, DTO, NestJS | `generator-backend.md` |
| frontend, React, Next.js, UI, component, hook | `generator-frontend.md` |
| plan, sprint, feature-list | `planner.md` |
| Playwright, E2E, browser | `evaluator-functional.md` |
| layout, screenshot, a11y, responsive | `evaluator-visual.md` |
| code quality, lint, architecture | `evaluator-code-quality.md` |
| 매칭 실패 + 에이전트 국한 | `shared.md` |
| 프로젝트 철학 (예: "우리는 TDD") | 루트 `CONVENTIONS.md` 권고 |

#### 에이전트 와이어링

각 에이전트는 세션 시작 시 다음 순서로 읽고 적용:

```
1. CONVENTIONS.md              (루트, 최상위 원칙)
2. .harness/conventions/shared.md      (공통)
3. .harness/conventions/<self>.md      (자기 스코프)
4. .harness/gotchas/<self>.md          (과거 실수)
5. .harness/memory.md                  (공유 교훈)
```

충돌 시 우선순위: `<self>` > `shared` > 루트.

#### 5c. Memory — 프로젝트 전체 규칙

한 에이전트 실수가 아니라 **모든 에이전트에 적용할 구조적 교훈** 이면 `.harness/memory.md` 로 승격:

```
이건 특정 Generator 실수가 아니라 이 프로젝트 공통 규칙이야 —
모든 테스트는 MockServer seed data 기반이어야 한다는 걸
메모리에 올려줘.
```

→ Dispatcher 가 `memory.md` 에 `### [M-NNN] ...` 로 기록. Planner 리뷰 후 `unverified → verified` 로 승격.

#### 주의 — 데이터 보존

`npm install` postinstall 은 **누적 엔트리(`[G-NNN]` 또는 `[C-NNN]`)가 있는 파일을 절대 덮어쓰지 않습니다**. 스캐폴드 템플릿인 경우에만 갱신됩니다. v5.5.2 이전 버전은 gotchas 에 이 버그가 있었으므로 `5.6.0+` 사용을 권장합니다.

#### 기존 프로젝트 마이그레이션 (첫 설치 시 자동)

기존 `CLAUDE.md` / `AGENTS.md` 에 Convention/Gotcha 성격의 섹션(`Conventions`, `Coding Standards`, `Best Practices`, `Gotchas`, `Don't`, `주의사항`, `금지사항` 등)이 있다면 첫 설치 시 자동으로 추출되어:

- **Convention 성격** → `.harness/conventions/<scope>.md` 에 `[C-NNN]` 으로 이관
- **Gotcha 성격** → `.harness/gotchas/<agent>.md` 에 `[G-NNN]` 으로 이관
- **원본** → `.harness/archive/pre-harness-*.md.bak` 에 백업
- **리포트** → `.harness/MIGRATION_REPORT.md` 에 이관 내역 + 수동 확인 요청 사항 기록

마이그레이션은 heuristic(키워드 기반)이므로 리포트를 확인해 스코프 재배정이 필요한지 검토하세요. 이미 하네스 서명(`[BE]`/`[FE]`/`[HARNESS]`)이 있는 문서는 skip 됩니다.

---

## Detail Architecture

여기부터는 어떻게 구성되어 있는지, 왜 그렇게 설계했는지에 대한 상세 문서입니다.

## 두 가지 모드

| 모드 | 설명 | 실행 방법 |
|------|------|----------|
| **Solo** | 순차 실행 — 프롬프트 기반으로 Planner → Generator → Evaluator 순서대로 진행 | `/harness-solo` 또는 프롬프트로 진행 |
| **Team** | 병렬 실행 — 3 Team이 Feature 단위 Gen→Eval 루프를 자동 핸즈오프로 동시 실행 | `/harness-team` 또는 `npx walwal-harness team` |

두 모드는 언제든 전환 가능합니다. Team 모드 중단 후 Solo로 이어가거나, Solo에서 Team으로 전환해도 진행 상태가 보존됩니다.

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
3. `.claude/commands/` 에 모드 제어 커맨드 설치 (3개)
4. `scripts/` 에 오케스트레이션 스크립트 설치
5. SessionStart / UserPromptSubmit 훅 등록
6. `AGENTS.md` + `CLAUDE.md` 심볼릭 링크 생성

> **중요:** 설치 후 Claude Code 세션을 **재시작**해야 skills/commands가 인식됩니다.

### 업데이트

```bash
npm update @walwal-harness/cli
```

npm update 시 모든 시스템 파일(scripts, skills, commands, config 템플릿)이 **자동으로 교체**됩니다. 사용자 데이터(progress.json, progress.log, **gotchas 누적 엔트리**, memory.md, archive)는 보존됩니다.

### CLI 명령어

```bash
npx walwal-harness              # 초기화 / 스크립트 업데이트
npx walwal-harness --force      # 강제 재초기화
npx walwal-harness team         # Team Mode tmux 레이아웃 실행
npx walwal-harness team --kill  # Team Mode tmux 세션 종료
npx walwal-harness --help       # 도움말
```

---

## 에이전트 구성

| 에이전트 | 역할 | 모델 |
|----------|------|------|
| **Dispatcher** | 요청 분석 → 파이프라인 결정 · gotcha 관리 | opus |
| **Brainstormer** | 러프한 요구사항 → 구조화된 spec | opus |
| **Planner** | 제품 사양 + API 계약서 + 서비스 분할 | opus |
| **Generator-Backend** | NestJS MSA 서비스 구현 | sonnet |
| **Generator-Frontend** | React/Next.js UI 구현 | sonnet |
| **Evaluator-Code-Quality** | 코드 유지보수성/아키텍처/Best Practice (BE/FE/libs 공통, 브라우저 없음) | opus |
| **Evaluator-Functional** | Playwright E2E 기능 검증 · API 계약 준수 | opus |
| **Evaluator-Visual** | 레이아웃/접근성/AI슬롭 검증 | opus |

### Evaluator Chain (v5.5+)

Generator 이후는 **3-Evaluator 직렬 체인 + 조기 종료** 로 동작:

```
Generator
  → Evaluator-Code-Quality  (정적 · 저비용 · 브라우저 없음)
  → Evaluator-Functional    (동작 · 중비용 · Playwright/curl)
  → Evaluator-Visual        (렌더 · 고비용 · 스크린샷)
  → Archive
```

앞단 FAIL 시 뒤 평가자는 실행하지 않고 바로 Generator 재작업으로 리라우팅. BE-ONLY 파이프라인에서는 Visual 이 체인에서 제외됩니다.

| 단계 | 채점 축 | Weight | 도구 |
|------|---------|--------|------|
| Code-Quality | C1 Layer · C2 Readability · C3 DRY · C4 Type/Error · C5 Test | 25/15/20/25/15 | Read/Grep + tsc/eslint |
| Functional   | R1 Contract · R2 AC · R3 Negative · R4 E2E · R5 Error | 25/25/20/15/15 | Playwright 또는 curl |
| Visual       | V1 Layout · V2 Responsive · V3 A11y · V4 Consistency · V5 Interaction | 20×5 | Playwright 스크린샷 |

### Evaluation 기준
- PASS: Weighted Score ≥ 2.80 / 3.00
- AC 100% 충족 필수 (부분 통과 = FAIL)
- Regression 실패 1건+ = FAIL (이전 Sprint PASS 기능 재검증)
- Evidence 없는 Score = 0점 강제 재계산
- Cross-Validation 불일치 1건+ = CONDITIONAL FAIL
- Team Mode: 최대 5회 재시도 후 사용자 개입 요청

---

## 솔로 파이프라인 상세

```
사용자 요청 → Dispatcher → (Brainstormer) → Planner
→ Generator-Backend → Generator-Frontend
→ Evaluator-Code-Quality → Evaluator-Functional → Evaluator-Visual
→ PASS: 다음 Sprint | FAIL: Generator로 재시도 (최대 5회)
```

각 에이전트는 **독립 Claude Code 세션** 에서 실행됩니다. Session Boundary Protocol 이 On Start / On Complete / On Fail 훅으로 progress.json 을 갱신하고 STOP. 다음 세션을 열면 SessionStart 훅이 자동으로 다음 에이전트를 안내합니다.

## 팀 파이프라인 상세

```bash
# Planner 완료 후
> /harness-team

# 자동 실행 흐름:
# 1. feature-queue.json 초기화 (의존성 topological sort)
# 2. tmux Studio 레이아웃 구축
# 3. 3개 팀이 병렬로 Gen→Eval 루프 자동 실행
# 4. 팀 완료 시 자동으로 다음 feature dequeue
# 5. 5회 초과 실패 시 사용자 개입 요청
```

### 모드 전환

| 명령 | 설명 |
|------|------|
| `/harness-team` | Team 모드 시작/재개 |
| `/harness-solo` | Solo 모드로 전환 (진행 상태 보존) |
| `/harness-stop` | Team 모드 중단 (queue 보존, 나중에 재개 가능) |

```
Team 실행 중 → /harness-stop → /harness-solo → 프롬프트로 계속
                                    ↓
                              /harness-team → 나머지 feature 팀 재개
```

---

## 디렉토리 구조

```
your-project/
├── .harness/
│   ├── config.json                    # 하네스 설정
│   ├── progress.json                  # 런타임 상태 (mode, sprint, agent)
│   ├── progress.log                   # 실시간 이벤트 로그
│   ├── memory.md                      # 공유 학습 기록 (모든 에이전트 공통)
│   ├── HARNESS.md                     # 하네스 상세 가이드
│   ├── actions/                       # 활성 스프린트 문서
│   │   ├── pipeline.json              # Dispatcher 결정 (evaluator_chain 포함)
│   │   ├── plan.md
│   │   ├── feature-list.json          # Feature 목록 + Executable AC
│   │   ├── api-contract.json
│   │   ├── feature-queue.json         # Feature Queue 상태 (Team Mode)
│   │   ├── sprint-contract.md
│   │   ├── evaluation-code-quality.md
│   │   ├── evaluation-functional.md
│   │   └── evaluation-visual.md
│   ├── archive/                       # 완료 스프린트 보관 (불변, 마이그레이션 백업도 여기)
│   ├── gotchas/                       # 에이전트 실수 기록 [G-NNN] (누적 보존)
│   │   ├── planner.md
│   │   ├── generator-backend.md
│   │   ├── generator-frontend.md
│   │   ├── evaluator-code-quality.md
│   │   ├── evaluator-functional.md
│   │   └── evaluator-visual.md
│   ├── conventions/                   # 하우스 스타일 [C-NNN] (v5.6+, 누적 보존)
│   │   ├── shared.md
│   │   ├── planner.md
│   │   ├── generator-backend.md
│   │   ├── generator-frontend.md
│   │   ├── evaluator-code-quality.md
│   │   ├── evaluator-functional.md
│   │   └── evaluator-visual.md
│   └── MIGRATION_REPORT.md            # 첫 설치 시 기존 문서 이관 내역 (있을 때만)
├── .claude/
│   ├── skills/harness-*/              # 에이전트 스킬 (8개)
│   ├── commands/harness-*.md          # 모드 제어 커맨드 (3개)
│   └── settings.json                  # 훅, statusline
├── scripts/
│   ├── harness-tmux.sh                # 통합 tmux 레이아웃 (Solo/Team)
│   ├── harness-dashboard.sh           # 통합 대시보드
│   ├── harness-gotcha-memory.sh       # Gotcha & Memory 패널
│   ├── harness-monitor.sh             # 에이전트 모니터
│   ├── harness-queue-manager.sh       # Feature Queue 관리
│   ├── harness-next.sh                # 에이전트 전환 라우터
│   ├── harness-session-start.sh       # SessionStart 훅
│   ├── harness-user-prompt-submit.sh  # UserPromptSubmit 훅
│   ├── harness-statusline.sh          # 상태바
│   ├── harness-prompt-history.sh      # 프롬프트 히스토리
│   └── lib/                           # 공유 라이브러리
├── AGENTS.md                          # 프로젝트 컨텍스트 (IA-MAP)
├── CLAUDE.md → AGENTS.md              # 심볼릭 링크
└── CONVENTIONS.md                     # 최상위 원칙 (사용자 자유 기술, 하위는 .harness/conventions/)
```

---

## Troubleshooting

### Skills/Commands가 인식되지 않음
```bash
# Claude Code 세션 재시작
/exit
claude
```

### Team 모드에서 "No features ready"
```bash
# Queue 상태 확인
bash scripts/harness-queue-manager.sh status .

# 실패한 feature requeue
bash scripts/harness-queue-manager.sh requeue F-001 .
```

### 모드 전환 후 상태 꼬임
```bash
# progress.json 직접 확인
cat .harness/progress.json | jq '{mode, sprint, current_agent, next_agent}'

# 강제 Solo 복귀
jq '.mode = "solo"' .harness/progress.json > /tmp/p.json && mv /tmp/p.json .harness/progress.json
```

### 대시보드에 feature title 이 "?" 로 표시
- v5.5.1 에서 해결 (feature 의 `name`/`title`/`description` 순으로 fallback).
- 그 이전 버전이면 `npm i @walwal-harness/cli@latest` 로 업데이트.

### Gotcha 가 누적되지 않고 사라짐
- v5.5.2 에서 해결 (postinstall 이 누적 엔트리를 절대 덮어쓰지 않도록 수정).
- 반드시 `5.5.2+` 사용.

---

## License

MIT
