# @walwal-harness/cli

**AI 에이전트를 위한 프로덕션 하네스 엔지니어링 프레임워크**

> Solo: 20min/$9 (broken) → Harness: 6hr/$200 (fully functional)
> — [Anthropic Engineering Blog](https://www.anthropic.com/engineering/harness-design-long-running-apps)

같은 AI 모델이라도 **하네스 설계에 따라 결과물 품질이 극적으로 달라집니다.** walwal-harness는 Anthropic이 제안한 하네스 엔지니어링 패턴을 설치 한 번으로 즉시 사용할 수 있게 패키징한 프레임워크입니다.

---

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
2. `.claude/skills/` 에 에이전트 스킬 설치 (7개)
3. `.claude/commands/` 에 모드 제어 커맨드 설치 (3개)
4. `scripts/` 에 오케스트레이션 스크립트 설치
5. SessionStart / UserPromptSubmit 훅 등록
6. `AGENTS.md` + `CLAUDE.md` 심볼릭 링크 생성

> **중요:** 설치 후 Claude Code 세션을 **재시작**해야 skills/commands가 인식됩니다.

### 업데이트

```bash
npm update @walwal-harness/cli
```

npm update 시 모든 시스템 파일(scripts, skills, commands)이 **자동으로 교체**됩니다.
사용자 데이터(progress.json, progress.log, gotchas 커스텀 항목, archive)는 보존됩니다.

### CLI 명령어

```bash
npx walwal-harness              # 초기화 / 스크립트 업데이트
npx walwal-harness --force      # 강제 재초기화
npx walwal-harness team         # Team Mode tmux 레이아웃 실행
npx walwal-harness team --kill  # Team Mode tmux 세션 종료
npx walwal-harness --help       # 도움말
```

---

## Quick Start — Solo Mode

```bash
# 1. 설치
npm install @walwal-harness/cli

# 2. Claude Code 재시작
claude   # (또는 codex)

# 3. 하네스 시작
> 하네스 엔지니어링 시작

# 4. Dispatcher → Planner 순서로 자동 진행
# 5. Generator, Evaluator를 프롬프트로 순차 호출
```

### Solo 파이프라인

```
사용자 요청 → Dispatcher → (Brainstormer) → Planner
→ Generator-Backend → Generator-Frontend
→ Evaluator-Functional → Evaluator-Visual
→ PASS: 다음 Sprint | FAIL: Generator로 재시도 (최대 5회)
```

---

## Quick Start — Team Mode

```bash
# Planner 완료 후:
> /harness-team

# 자동으로:
# 1. feature-queue.json 초기화 (의존성 topological sort)
# 2. tmux Studio 레이아웃 구축
# 3. 3개 팀이 병렬로 Gen→Eval 루프 자동 실행
# 4. 팀 완료 시 자동으로 다음 feature dequeue
# 5. 5회 초과 실패 시 사용자 개입 요청
```

### Team 모드 레이아웃

```
┌──────────────┬──────────────┬──────────────┐
│  Prompt      │  Dashboard   │   TEAM 1     │
│  History     │  (queue +    │  Gen | Eval   │
│              │   status)    ├──────────────┤
├──────────────┤              │   TEAM 2     │
│  Controller  │              │  Gen | Eval   │
│  (Claude /   │              ├──────────────┤
│   Codex)     │              │   TEAM 3     │
└──────────────┴──────────────┴──────────────┘
```

---

## 모드 전환

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

## 에이전트 구성

| 에이전트 | 역할 | 모델 |
|----------|------|------|
| **Dispatcher** | 요청 분석 → 파이프라인 결정 | opus |
| **Brainstormer** | 러프한 요구사항 → 구조화된 spec | opus |
| **Planner** | 제품 사양 + API 계약서 + 서비스 분할 | opus |
| **Generator-Backend** | NestJS MSA 서비스 구현 | sonnet |
| **Generator-Frontend** | React/Next.js UI 구현 | sonnet |
| **Evaluator-Functional** | Playwright E2E 기능 검증 | opus |
| **Evaluator-Visual** | 디자인/접근성/AI슬롭 검증 | opus |

### Evaluation 기준
- PASS: Weighted Score ≥ 2.80/3.00
- AC 100% 충족 필수 (부분 통과 = FAIL)
- Regression 실패 1건+ = FAIL
- Evidence 없는 Score = 0점
- Team Mode: 최대 5회 재시도 후 사용자 개입 요청

---

## 디렉토리 구조

```
your-project/
├── .harness/
│   ├── config.json                    # 하네스 설정
│   ├── progress.json                  # 런타임 상태 (mode, sprint, agent)
│   ├── progress.log                   # 실시간 이벤트 로그
│   ├── HARNESS.md                     # 하네스 상세 가이드
│   ├── actions/                       # 활성 스프린트 문서
│   │   ├── feature-list.json          # Feature 목록 + AC
│   │   ├── api-contract.json          # API 계약서
│   │   ├── feature-queue.json         # Feature Queue 상태 (Team Mode)
│   │   └── ...
│   ├── archive/                       # 완료 스프린트 보관 (불변)
│   └── gotchas/                       # 에이전트 실수 기록
├── .claude/
│   ├── skills/harness-*/              # 에이전트 스킬 (7개)
│   ├── commands/harness-*.md          # 모드 제어 커맨드 (3개)
│   └── settings.json                  # 훅, statusline
├── scripts/
│   ├── harness-tmux.sh                # 통합 tmux 레이아웃 (Solo/Team)
│   ├── harness-dashboard.sh           # 통합 대시보드
│   ├── harness-monitor.sh             # 에이전트 모니터
│   ├── harness-queue-manager.sh       # Feature Queue 관리
│   ├── harness-next.sh                # 에이전트 전환 라우터
│   ├── harness-session-start.sh       # SessionStart 훅
│   ├── harness-user-prompt-submit.sh  # UserPromptSubmit 훅
│   ├── harness-statusline.sh          # 상태바
│   ├── harness-prompt-history.sh      # 프롬프트 히스토리
│   └── lib/                           # 공유 라이브러리
├── AGENTS.md                          # 프로젝트 컨텍스트 (IA-MAP)
└── CLAUDE.md → AGENTS.md             # 심볼릭 링크
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

---

## License

MIT
