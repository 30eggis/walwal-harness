---
docmeta:
  id: CHANGELOG
  title: walwal-harness CHANGELOG
  type: output
  createdAt: 2026-05-07T00:00:00Z
  updatedAt: 2026-05-07T00:00:00Z
  source:
    producer: agent
    skillId: harness-release
  inputs:
    - documentId: agency-mapping
      uri: .harness/agency-mapping.md
      relation: output-from
      sections:
        - sourceRange: { startLine: 41, endLine: 53 }
          targetRange: { startLine: 28, endLine: 40 }
    - documentId: doctrine-nexus
      uri: .harness/doctrine/nexus.md
      relation: output-from
      sections:
        - sourceRange: { startLine: 32, endLine: 60 }
          targetRange: { startLine: 41, endLine: 50 }
    - documentId: package
      uri: package.json
      relation: output-from
  tags: [changelog, release-notes, v6.0.0, nexus]
---

# Changelog

## Unreleased

## 7.1.37 — Project-local dashboard runtime + wake reliability (2026-05-31)

- Dashboard runtime now lives under each project’s `.harness/dashboard/` instead of the shared `~/.walwal-harness/dashboard/` cache, with generated dependencies/build output ignored via `.gitignore`.
- Dashboard heatmap is no longer filtered by the selected goal/submission/hot-fix; it shows all recorded activity while still preserving mission IDs on active cells.
- Dashboard worker parsing now accepts `name`, `progress`, `eta`, and `report_path` telemetry and no longer treats docmeta-only report drafts as proof of live worker activity.
- Init/migrate now best-effort registers the project with the hourly wake scheduler, and wake status now uses the macOS `launchctl print gui/$UID/...` state to avoid false `NOT loaded` reports.

## 7.1.36 — Stop hook active-loop guard + visible heatmap (2026-05-29)

- Stop hook no longer runs worker evidence validation before deciding whether the company loop should chain.
- Worker evidence validation can be scoped to the newest active mission so legacy/archive mission records cannot keep Stop blocked forever.
- Dashboard heatmap now uses 10-minute buckets across 24 hours, making activity visible without horizontal scrolling through 1440 minute cells.

## 7.1.35 — Dashboard heatmap mission scoping (2026-05-29)

- Dashboard heatmap samples are now scoped to the selected mission, so worker rows no longer inherit activity from unrelated stale-active missions.
- Activity recording now chooses the newest active mission when legacy runtime state contains multiple `active:true` mission-state files.
- Init/migrate now deactivates duplicate active submission/hot-fix children under the same goal instead of only creating missing mission-state files.

## 7.1.26 — Lazy rule links + MCP steward (2026-05-27)

### Added
- COO planning can hire `support-support-mcp-registry-steward` to inventory Claude/Codex MCP capabilities, registration risk, credentials, and maintenance notes.
- CXX convention/gotcha files now act as lazy-loading indexes that link to topic files such as `i18n-locale-hotfix.md`.

### Changed
- `migrate` preserves topic-specific convention/gotcha files and adds related links to matching CXX index files instead of merging or deleting them.
- CXX and worker guidance now passes only relevant convention/gotcha links to workers, avoiding full-registry scans.

## 7.1.25 — Absolute Claude hook paths + Codex adapter docs (2026-05-26)

### Fixed
- Claude hooks and statusline now install with project-root absolute script paths, preventing `UserPromptSubmit hook error: scripts/harness-user-prompt-submit.sh: No such file or directory` when Claude runs hooks outside the project root.
- Existing relative-path harness hooks are migrated to absolute paths on re-init.

### Changed
- Codex command and AGENTS templates now explain that `.codex/skills/**/SKILL.md` is the Codex runtime protocol and `.codex/agents/` is not required.
- `migrate` appends a Codex Runtime Adapter block to existing AGENTS.md files when missing.

## 7.1.24 — Hourly CEO wake loop + migrate script refresh (2026-05-22)

### Changed
- Hourly wake prompting now explicitly wakes CEO to convene CXX + OPS, collect current progress and decisions, dispatch one NOW action, and continue through CQO/OPS verification without asking Owner for next steps.
- Hourly wake prompts now include external executive-function scaffolding: body-doubling status checks, context-transition summaries, time-guardian hidden-task detection, and NOW/NEXT/PARKED open-loop triage.
- Hourly wake now supports `HARNESS_WAKE_MODEL` / `company_mode.hourly_wake_model` for Claude model pinning.
- `migrate` now refreshes package-owned runtime scripts, including `scripts/harness-wake.sh`, while archiving the previous target scripts directory.
- Dashboard Org Tree now uses a left-to-right depth layout while keeping zoom, ctrl/meta-wheel zoom, and drag panning.

## 7.1.23 — Dashboard CDO preview + radial org tree (2026-05-21)

### Added
- Dashboard CDO Preview tab: clicking `harness-cdo` opens an iframe preview from `.harness/documents/{mission}/cdo/preview.html`.
- CDO skill and harness reference now require the preview artifact before CDO completion, with CEO/Owner handoff guidance to view it in the dashboard.
- Dashboard mission state now reads `cdo/preview.html` alongside CXX markdown docs.

### Changed
- Dashboard Org Tree now uses a compact radial/sunflower layout with Owner/CEO centered and CXX roles arranged around them.
- Org Tree now has independent zoom controls, ctrl/meta-wheel zoom, and drag panning inside a reduced-height scroll surface.

### Fixed
- CDO dashboard navigation now opens the visual Preview tab instead of only the markdown document flow.

### Fixed
- v7 `/goal`, `/submission`, and `/hot-fix` now mark both `company_state.state` and `conductor.state` as `running`, so Claude Stop hook auto-chain does not stop after CEO routing or hiring-only summaries.
- Stop hook now treats v7 CEO routing state (`current_agent=ceo`, `agent_status=running`, `owner_prompt.status=routing`) as an unfinished company loop, including migrated projects that do not yet have running conductor/company state.
- CEO skill now explicitly forbids ending a mission turn with only hiring/resource-manager output while the Owner goal remains unfinished.

### Added
- `scripts/harness-company-complete.sh` provides the shared running → idle/completed transition for dashboard auto-mode, external runners, hooks, and final CEO handoff paths.
- New progress templates include `company_state.state` and default `conductor` fields for consistent runner/dashboard state.

### Changed
- Dashboard Org Tree now positions only hired HR-Resource workers from `hr-roster.json`, requiring a backing `.harness/shared/HR-Resource/{worker}/SKILL.md`.
- Running hired workers are highlighted under their owning CXX instead of showing queue jobs as worker seats.
- Dashboard SSE now watches mission documents, hired-worker roster, and HR-Resource changes so worker updates appear without browser refresh.
- Dashboard worker cards now prefer mission/report task labels and mark recently updated unfinished worker reports as active when runtime active-worker state is absent.

### Added
- Hourly wake can now run either `claude -p` or `codex exec` via `HARNESS_WAKE_EXECUTOR=claude|codex`.
- Hourly wake supports `HARNESS_WAKE_MODE=headless|tmux|record`; `tmux` creates a separate time-boxed session per hourly company tick for easier inspection.
- Deterministic conductor fallback runs after each hourly review so meeting decisions can advance even when the LLM runtime is unavailable.
- Hourly meeting minutes now split meaningful progress from paperwork-only artifacts and track strategy cadence drift.

### Runtime Changed
- launchd wake PATH now includes `$HOME/.local/bin` so local Claude/Codex installs are found from non-interactive jobs.
- Service-Ops records repeated incident signatures and marks repeated incidents as `recovery_required`, causing hourly meetings to route to CTO runtime recovery instead of repeating discussion.

## 6.2.0 — Always-on company runtime + legacy purge (2026-05-08)

### Why
회사모드 only 정렬. 솔로/팀 모드의 잔재 스크립트와 분기 로직이 SKILL/문서 곳곳에 남아 있어 Owner 가 "지금 어떤 모드인지" 혼동하고, 한 시간이 지나도 자율 활동이 일어나지 않는 (스케줄러 부재) 문제 발생. 추가로 Claude 가 미래 시각으로 progress.log 라인을 미리 적어 가짜 진행을 보고하는 환각이 관찰됨.

### Added
- **Stop 훅** (`scripts/harness-stop.sh`) — Claude turn 종료 시 conductor 가 running 이면 자동으로 다음 tick 으로 연쇄. `behavior.auto_chain_on_stop=false` 로 비활성, `behavior.auto_chain_max_per_sprint` 로 상한 (기본 200).
- **launchd hourly wake** (`scripts/harness-wake.sh`, `scripts/harness-wake-install.sh`, `assets/launchd/com.walwal.harness-wake.plist.template`) — 1시간마다 idle ≥ 55분 프로젝트의 tmux 에 wake prompt 송출.
- **Truthful Logging Heal** — `harness-session-start.sh` 가 `progress.log` 의 미래 시각 라인을 자동으로 `progress.log.future-quarantine.<ts>` 로 격리 + 메인 로그에서 제거.
- **conductor / dispatcher SKILL 의 정직성 룰** — "미래 시각 progress.log 항목 금지" Inviolable 섹션 추가, Owner "최근 1시간 뭐 했냐" 질문 시 디스크 mtime 으로 정직 답변하도록 명시.
- **meeting-manager SKILL 의 라이브 가시화 계약** — `meetings.active` 가 평탄한 agent ID 배열이라는 데이터 계약을 명시. convene 시 active=[참석자], dispatch 시 active=[] 로 갱신해야 미니피규어가 회의실로 텔레포트.

### Removed (legacy purge)
- `scripts/harness-dashboard.sh` — tmux ASCII 대시보드 pane (3D Brick Office 가 대체).
- `scripts/harness-monitor.sh` — 3-team worker pane (회사모드는 동적 worker pool).
- `scripts/harness-prompt-history.sh` — tmux Studio 전용 pane.
- `scripts/harness-gotcha-memory.sh` — tmux Studio 전용 pane.
- `scripts/harness-tmux.sh` — tmux Studio launcher (회사모드는 단일 Claude CLI + 브라우저 대시보드).
- `scripts/harness-goal-init.sh`, `scripts/harness-goal-show.sh` — 외부 호출 0 건의 고아.
- `commands/harness-company.md` — Studio launch 명령 (런타임 자동화로 불필요).
- `bin/init.js`: `runTeamStudio()` + `company` / `studio` / `studio-v4` / `v4` subcommand 제거.

### Migration
기존 프로젝트는 `npx walwal-harness --force` 또는 다음만 수동 적용:
1. `.claude/settings.json` 에 Stop 훅 추가 (matcher: "", command: `bash scripts/harness-stop.sh`).
2. `bash scripts/harness-wake-install.sh install <project-root>` 로 1시간 안전망 등록 (선택).
3. `~/<project>/scripts/` 에서 위 7개 legacy 스크립트 제거.

## 6.1.4 — Template + package files alignment with v6 NEXUS (2026-05-08)

### Why
6.1.3 까지 `assets/templates/HARNESS.md` 와 `assets/templates/config.json` 의 메타 헤더가 v3 시절 "7-Agent Production Harness / 5.6.0" 으로 정지해 있어, `--force` 가 stale 템플릿을 그대로 덮어쓰는 회귀 발생. 또 신규 `conventions/` 디렉토리가 `package.json` "files" 에 누락되어 게시 패키지에 포함되지 않았다.

### Changed
- `assets/templates/HARNESS.md`: v6 NEXUS 도큐트린 기준으로 전면 재작성 (단일 대화 창구·조직도·디렉토리·실행 흐름·6종 회의·parallel-tracks·Solo/Team/Hypothesis 모드·품질 게이트·자주 쓰는 명령).
- `assets/templates/config.json`: `harness.name` / `version` / `description` 메타 헤더를 v6.1.4 NEXUS 기준으로 갱신.
- `package.json` "files": `conventions/` 추가 (이제 게시 tarball 에 포함됨).

## 6.1.3 — Parallel-tracks fork-join + role gotchas/conventions backfill (2026-05-08)

### Added
- **Meeting parallel-tracks (fork-join)**: 회의 결정의 `tracks[]` 길이 ≥ 2 를 단일 진실로 사용 (별도 mode 플래그 없음). Conductor 가 트랙 dispatch · rendezvous join 을 자동 처리.
- **followup-review** 회의 타입(6번째) 정식화 — fork 결과를 결정자(CTO 기본, goal-* fork 면 CEO) 가 `apply-now/backlog/more-validation` 중 하나로 마무리.
- `scripts/lib/harness-progress-migrate.sh` — `progress.json` 스키마 idempotent migrator. SessionStart 마다 `conductor.tracks/rendezvous/fork_meeting_id`, `meetings.requested_tracks/requested_rendezvous`, `meetings.decision.tracks/rendezvous` 필드를 안전하게 채움 (기존 값 보존, 폐기 필드 정리).
- **신규 역할 gotchas**: `cto`, `cqo`, `generator-designer`, `generator-devops`, `evaluator-architecture`, `evaluator-security`, `meeting-manager`.
- **신규 역할 conventions**: `conductor`, `coo-developer`, `cqo`, `cto`, `dispatcher`, `documentationer`, `evaluator-architecture`, `evaluator-security`, `generator-designer`, `generator-devops`, `meeting-manager`, `service-ops`.
- `apps/harness-dashboard/lib/__tests__/company-flow.test.ts` — company-loop 검증.

### Changed
- `scripts/conductor-tick.sh`: parallel-tracks 분기·rendezvous 라우팅, hypothesis chain 단계별 라우팅 가드 (`hypothesis:research → experiment → report → done`) 보강.
- `scripts/harness-meeting-doc.sh`: `requested_tracks` 가 length≥2 면 fork-join decision JSON 합성, length≤1 이면 1-element tracks[] 로 backward compat.
- `skills/meeting-manager/SKILL.md`: §7.05 parallel-tracks 합성 규칙 + followup-review prep 절차 추가.
- `skills/planner/SKILL.md`: hypothesis-validation fork 트랙 운영 흐름 + Hypothesis Cell 산출물 경로(`actions/hypothesis/<id>/`) 명문화.
- `AGENTS.md`: IA-MAP 에 `actions/hypothesis/`, followup-review 추가, 권한 매트릭스에 hypothesis/followup 경로 추가.

### Validation
- `bash -n scripts/conductor-tick.sh scripts/harness-meeting-doc.sh scripts/lib/harness-progress-migrate.sh`
- 회사 플로우 테스트 통과 (`apps/harness-dashboard/lib/__tests__/company-flow.test.ts`)

## 6.1.2 — TokenLimit hold/resume checker (2026-05-08)

### Added
- `TaskStopReason: TokenLimit` 기반의 저비용 작업 재개 플로우 추가
- `scripts/harness-token-limit.sh mark|resume-probe` 도입
- SessionStart / UserPromptSubmit 가 TokenLimit hold 를 감지해 전체 작업 중지 및 재개 타이밍을 안내
- `progress.json.task_stop` 과 `config.token_limit` 필드 추가

## 6.1.1 — COO hypothesis routing activation (2026-05-08)

### Why
v6.1.0 에서 COO 직속 `coo-developer` / `documentationer` 역할과 hypothesis cell 문서는 추가됐지만, 실제 Conductor 라우팅은 여전히 `planner -> cto` 직행이었다. 그래서 "COO가 가설을 세우면 빠르게 리서치·실험·판정한다" 는 운용 모델이 문서상으로만 존재했다.

### Changes
- **runtime routing for hypothesis mode**
  - `planner.requested_mode = "hypothesis"` 이면 `documentationer` 로 우선 라우팅
  - 이후 `documentationer -> coo-developer -> documentationer -> planner` 순서로 가설 검증 루프 진행
  - 단계 추적용 상태를 `planner.last_brief` 에 `hypothesis:research`, `hypothesis:experiment`, `hypothesis:report`, `hypothesis:done` 으로 기록
- **agent registry update**
  - `.harness/config.json` 의 `agents` 카탈로그에 `coo-developer`, `documentationer` 등록
  - handoff/statusline/session-start 가 두 agent 를 정상 인식하도록 연결

### Validation
- `bash -n scripts/conductor-tick.sh`
- `jq empty .harness/config.json`
- `/private/tmp` 샌드박스에서 hypothesis flow 시뮬레이션:
  - `planner(completed, requested_mode=hypothesis) -> documentationer`
  - `documentationer -> coo-developer`
  - `coo-developer -> documentationer`
  - `documentationer -> planner(requested_mode=hypothesis-verdict)`

## 6.1.0 — document-driven company loop + task-session isolation (2026-05-08)

### Why
v6.0.x 는 회사형 조직 비유와 Cxx 라우팅을 문서로는 설명했지만, 실제 런타임은 여전히 얕았다. 특히 다음 두 결함이 컸다.

- 회의 결과가 `누가 다음 owner 인가` 를 구조적으로 기록하지 않음
- `goal_adherence` 하락 시 원인 분류 없이 Planner로 보내는 경향이 있음

또한 agent 간 자기강화 편향을 줄이기 위한 문서 중심 task session 분리도 충분히 강제되지 않았다.

### Changes
- **document-driven meeting decision**
  - `meeting-manager` 가 `notice.md`, `prep-*.md`, `meeting-<id>.md` skeleton 을 자동 생성
  - 회의 기록에 `decision.owner`, `action_type`, `rationale`, `evidence`, `drift_classification` JSON 블록 추가
  - `conductor-tick` 은 더 이상 `meeting_reason` 문자열만 보지 않고 회의 decision 문서를 우선 읽어 다음 owner 를 결정
- **goal drift classification**
  - `implementation_drift | planning_drift | ops_drift | goal_drift` 분류 추가
  - 분류별 기본 라우팅:
    - `implementation_drift -> cto`
    - `planning_drift -> planner`
    - `ops_drift -> service-ops`
    - `goal_drift -> dispatcher`
- **task-session isolation**
  - `harness-next` 가 다음 agent 마다 `.harness/actions/task-sessions/<agent>/<id>.md` 생성
  - `handoff.json` 에 `task_session_path` 추가
  - `UserPromptSubmit` 가 running agent 와 다른 `/harness-*` 호출을 경고가 아니라 **hard block**
- **direct invocation policy**
  - 모든 harness skill 의 `disable-model-invocation` 을 `false` 로 통일
  - orchestration/control-plane 과 worker/evaluator 모두 직접 호출 가능 상태로 정리
- **archive reset hardening**
  - archive 시 `workflow`, `meetings.decision`, `service_ops.drift_classification`, `task_sessions.current` 초기화

### Validation
- `bash -n` 으로 주요 스크립트 문법 검증
- `jq empty` 로 `config.json`, `progress.json` 검증
- `/private/tmp` 샌드박스에서:
  - `dispatcher -> meeting-manager` 시 회의 문서 자동 생성 확인
  - 회의 decision 편집 후 `dispatcher / planner / cto` 로 문서 기반 재라우팅 확인
  - `goal_adherence` 하락 시 drift classification 반영 확인
  - context isolation hard block 확인
  - `task_session_path` 생성 확인

## 6.0.5 — migrate 가 gotcha entry / bundle version 까지 sync (2026-05-07)

### Why
Owner 보고 — `npm install @walwal-harness/cli@latest && npx walwal-harness migrate` 가 "이미 최신 버전입니다" 로 종료. 그러나 v6.0.4 에서 새로 추가된 `gotchas/conductor.md` 의 [G-005], [G-006], `gotchas/service-ops.md`, `gotchas/generator-frontend.md [G-001]` 가 사용자 프로젝트에 merge 되지 않음. **존재 여부 (3 항목 — progress v4 / config.mode_selection / M-NEXUS-P3) 만 확인하고 콘텐츠는 비교 안 함** → 본질적 버그.

### Changes
- **bin/init.js `detectMigrationNeeded`** — 두 신규 시그널 추가:
  - `gotchaMissingEntries`: `gotchas/*.md` 별로 패키지 → 사용자 [G-NNN] entry 차이 산출 (memory.md 패턴과 동일)
  - `bundleVersionStale`: `.harness/.bundle-version` 스탬프와 패키지 버전 비교
- **bin/init.js `runMigrate`** — gotcha entry append + bundle stamp 갱신 단계 추가. 사용자가 직접 추가한 [G-NNN] entry 는 절대 건드리지 않으며, 패키지의 신규 시스템 entry 만 끝에 추가.
- **bin/init.js `extractGotchaEntryBlock` / `extractEntryBlock`** — JS 정규식 `\Z` 미지원 fix. 마지막 entry 가 추출 누락되던 버그 동시 해결 (v6.0.2 부터 잠재).
- **bin/init.js main flow** — 콘텐츠 드리프트 없이 stamp 만 누락된 경우 init 종료 시 자동 갱신. stamp 만으로 매번 migrate 권유 알림이 뜨는 것 방지.

### Migration
```bash
npm install @walwal-harness/cli@latest
npx walwal-harness migrate     # gotchas/conductor.md G-005/G-006, gotchas/service-ops.md, gotchas/generator-frontend.md G-001 자동 append + stamp 갱신
npx walwal-harness verify
```
사용자 [G-NNN] entry 는 보존되고 시스템 entry 만 끝에 append. 변경 전 `.harness/archive/migration-<ts>/gotchas-<file>` 백업.

## 6.0.4 — Sub-skill 협업 + Service-Ops 상시 + Team 병렬 spawn (2026-05-07)

### Why
moon_web 사용자 보고 — v6.0.3 이후에도 (a) CTO-Frontend 가 흡수된 agency-agents sub-skill (UX/UI/A11y/Perf) 을 호출하지 않고 단독 작업, (b) build/test 중 Service-Ops 자리 비움 → stderr 의 컴파일/테스트 에러 무감시, (c) `mode=team` 인데도 Conductor 가 직렬로 1개씩 spawn 하여 Team 자동 결정 룰 (ready≥3, features≥6, depth≤2) 만족이 무의미해짐. 세 가지는 형식상 v6 였지만 실효는 6.0 이전 수준.

### Changes
- **gotchas/generator-frontend.md [G-001]** — Sprint Workflow Step 2 에 5개 sub-skill 순차 호출 의무 (engineering-{react,flutter}-developer / design/ux-strategy / design/ui-component-spec / engineering-accessibility-reviewer / engineering-performance-engineer). 결과는 sprint-contract.md FE 섹션 `## Sub-skill Findings` 에 인용. 빈 블록 = Evaluator-Code-Quality FAIL.
- **gotchas/service-ops.md [G-001]** (신규) — build/test/deploy spawn 직전 동일 tick 에서 monitor stream-mode 동반 활성. 정규식 `(error|exception|TestFailure|Cannot find|Failed to compile)` 매칭 시 즉시 red-alert.
- **gotchas/conductor.md [G-005]** — Team mode 직렬 회귀 금지. 매 tick 시작 시 ready 목록 계산 → `min(ready, 3)` 동시 spawn + `team_state.team_<n>.assigned_feature/assigned_agent` 갱신 + `meetings.active=["t1-lead","t2-lead","t3-lead"]` standup 시각화.
- **gotchas/conductor.md [G-006]** — Service-Ops monitor 동반 spawn 룰을 Conductor SKILL §5 spawn 결정 트리에 명시.
- **skills/generator-frontend/SKILL.md** — Sprint Workflow §2.1 sub-skill 호출 시퀀스 표 + visibility partial update 패턴.
- **skills/conductor/SKILL.md** — §5 spawn 결정 트리에 두 라인 추가 + §5.1 Team mode 병렬 알고리즘 + §5.2 Service-Ops 동반 spawn 의사코드.

### Migration
기존 사용자:
```bash
npm install @walwal-harness/cli@latest
npx walwal-harness migrate     # gotchas/service-ops.md 자동 추가
npx walwal-harness verify
```
sub-skill 호출은 generator-frontend SKILL.md 가 갱신되면 다음 sprint 부터 자동 적용. 진행 중 sprint 의 FE 섹션은 Eval-Code-Quality 가 빈 `## Sub-skill Findings` 를 잡아내며 retry 유도.

## 6.0.3 — Visibility + Spawn 검증 + 사용자 슬래시 노출 제거 (2026-05-07)

Owner 의 두 지적을 동시 해결:
1. "Dispatcher 와 대화 중인데 CEO 가 자리에 없다 / 회의실에 모이지도 않는다" — visibility 의무 부재
2. "회사인데 왜 자꾸 나에게 명령을 요구하는가" — 사용자 facing 슬래시 잔재

### Added
- `gotchas/dispatcher.md` [G-005] [G-006] — 사용자 슬래시 명령 요구 금지 + Owner 대화 중 dashboard 가시화 의무
- `gotchas/conductor.md` (신규) — [G-001] inline fallback 금지 (M-001 의 Conductor 적용) / [G-002] spawn 핸드오프 시 회의실 활용 / [G-003] Visibility Checklist 4 시점 / [G-004] Owner 진행 동의 묻지 말 것
- `skills/conductor/SKILL.md` §0.5 "Visibility Checklist (Inviolable)" 신설 — 매 tick 의 4 시점 progress.json partial update 의무 + spawn 사전 검증 (SKILL 존재 검사 → 없으면 escalate, inline fallback 금지)
- 신규 명령 `walwal-harness verify` — 17 SKILL invariants + progress schema + config mode_selection + memory 시스템 entry + deprecated commands 검사. 한 줄로 통합 점검.
- `apps/harness-dashboard` 의 `ActivityIndicator` 컴포넌트 — `last_activity` age 표시. 30 초 이상 정적 → "stale — 회사가 멈춰 보입니다" 빨간 표시.

### Changed
- `commands/harness-next.md` **삭제** — 사용자 슬래시 노출 제거. v6 자율 회사에서 Owner 가 입력할 일 없음. `scripts/harness-next.sh` 는 회사 내부 도구로 유지 (Conductor 자율 호출).
- 9 개 SKILL 본문의 "/harness-next 자동 진행" 안내 → "자동 핸드오프 (Conductor 자율 시동)" 로 일괄 치환.
- `bin/init.js` install 의 commands cleanup 로직이 자동으로 deprecated `harness-next.md` 를 사용자 환경에서 제거 (기존 동작이 모든 `harness-*` 를 갱신하므로).

### Removed
- `commands/harness-next.md` — 사용자 facing 슬래시 (자율 위반)

### Migration (one-liner)
```bash
npm install @walwal-harness/cli@latest
npx walwal-harness migrate    # 이전 버전 사용자
npx walwal-harness verify     # 설치 무결성 점검
```

`verify` 가 점검하는 것:
- 17 개 SKILL 의 frontmatter (name, description) + 파일 존재
- progress.json schema (version ≥ 4, mode_decision, dispatch)
- config.json mode_selection 존재
- memory.md 시스템 entry (M-NEXUS-P3)
- deprecated 사용자 슬래시 (`.claude/commands/harness-next.md`) 잔존 여부

## 6.0.2 — `migrate` 가 memory 시스템 entry 까지 자동 처리 (2026-05-07)

v6.0.1 patch 적용을 위해 사용자가 memory.md 의 [M-NEXUS-P3] 를 수동 추가해야 했던 불편을 제거. `npx walwal-harness migrate` 한 줄로 모두 처리됩니다.

### Changed
- `bin/init.js` 의 `detectMigrationNeeded()` 가 memory.md 의 시스템 entry (M-NEXUS-*, M-SYS-*) 누락도 감지.
- `runMigrate()` 가 누락된 시스템 entry 를 template 에서 발췌해 사용자 memory.md 끝에 append. **사용자 [M-NNN] entry 는 무손상**.
- postinstall 안내 banner 가 누락된 memory entry 목록도 함께 표시.

### Migration (one-liner)
```bash
npm install @walwal-harness/cli@latest
npx walwal-harness migrate          # progress + config + memory 한 번에
```

`migrate` 가 처리하는 것:
- progress.json v3 → v4 (mode → "auto" + mode_decision)
- config.json mode_selection 자동 주입
- **(신규)** memory.md 시스템 entry append (M-NEXUS-P3 등)
- 변경 전 .harness/archive/migration-<ts>/ 에 progress / config / memory 자동 백업.

## 6.0.1 — Owner ↔ CEO 정체성 + 자율 실행 룰 강화 (2026-05-07)

v6.0.0 publish 직후 Owner 의 명시적 교정으로 발견된 두 가지 inviolable 룰 위반 패턴을 패키지에 정식 등재한 patch.

### 발견된 위반 패턴
- Dispatcher 응답이 사용자를 "CEO 직접 리뷰…" 로 호명 — 정체성 혼선
- "/harness-next 자동 진행하시겠습니까?" 식의 사용자 펌프 — NEXUS P3 자율 실행 위반

### Added
- `gotchas/dispatcher.md` — 신규 4개 entry ([G-001]~[G-004]) 정식 등재. install 시 사용자 `.harness/gotchas/dispatcher.md` 로 자동 복사.
  - [G-001] 사용자를 CEO 로 다루지 말 것 (Owner ↔ CEO 정체성)
  - [G-002] 사용자에게 진행 여부 묻지 말 것 (NEXUS P3 자율 실행)
  - [G-003] GOAL 모호성 명료화는 짧게 한 번만
  - [G-004] Owner ↔ Conductor/Planner/Generator/Evaluator 직접 라우팅 금지
- `assets/templates/memory.md` — 신규 [M-NEXUS-P3] 항목. 모든 신규 install 의 시작 memory 에 포함.

### Changed
- `skills/dispatcher/SKILL.md` 상단에 두 inviolable 섹션 신설:
  - "정체성 — Owner ↔ CEO (NEXUS, Inviolable)"
  - "자율 실행 원칙 (NEXUS P3, Inviolable)"
- `skills/conductor/SKILL.md` §0 "자율 시동 트리거" 신설 — Dispatcher GOAL 확정 / Planner feature-list 확정 / Eval PASS / Eval FAIL 4 시점에 자동 시동 명시.

### Why a patch (not a feature)
이 룰들은 v6.0.0 의 NEXUS 도큐트린에 이미 존재했지만 SKILL 본문에서 충분히 강제되지 않아 대화에서 위반이 발생. 룰 자체는 변경 없음, **명시화/강제력 강화** 만.

### Migration
이전 사용자 (v6.0.0 install 자) 가 patch 적용:
```bash
npm install @walwal-harness/cli@latest    # 6.0.1 설치
# .claude/skills/ 와 .harness/gotchas/dispatcher.md 가 자동 갱신됨.
# .harness/memory.md 는 [G-NNN] entry 가 있으면 보존되므로
# [M-NEXUS-P3] 항목을 수동으로 메모에 추가하거나
# memory.md 백업 후 walwal-harness --force 로 template 재적용.
```

## 6.0.0 — NEXUS-Adapted Company Metaphor (2026-05-07)

회사 메타포로의 전면 전환. 기존 단일 dispatcher/planner/generator/evaluator 라인업을 NEXUS 도큐트린에 따라 7부서 + 14 에이전트 조직도로 재해석했습니다.

### Added
- **CEO (Dispatcher 격상)** — Owner ↔ 회사 단일 대화 창구. GOAL 협의·escalation 보고.
- **Conductor** — 자율 실행 엔진. Gen↔Eval 무인 루프.
- **Meeting-Manager** — 동기화 엔진. 5종 회의(standup/planning/review/all-hands/phase-gate) 적응형 cadence.
- **COO (Planner)** — Sprint·AC·HR·온보딩 통합.
- **CTO (Generator 총괄)** — Gen-BE/Gen-FE/Designer/DevOps 4팀 통솔.
- **CQO (Evaluator 총괄)** — Eval-Functional/Visual/CodeQuality + 신규 Architecture/Security.
- **Service-Ops** — 운용·모니터·인시던트·자율회고.
- 신규 14개 SKILL.md (`skills/{conductor,meeting-manager,cto,cqo,service-ops,evaluator-architecture,evaluator-security,generator-designer,generator-devops,...}/SKILL.md`).
- `.harness/doctrine/nexus.md` — Foundational Principles (P1~P5) + 7 Phase Lifecycle.
- `.harness/agency-mapping.md` — agency-agents → walwal-harness 매핑 (Phase A 결과).
- `.harness/memory.md` 기반 공유 학습 시스템 (gotcha 와 분리).
- Brainstormer 스킬 (obra/superpowers 파생, MIT, Visual Companion 포함).
- 적응형 ref-docs (`.harness/ref/<role>-<stack>.md`) — 단일 에이전트가 스택별 best-practice 동적 로드.

### Changed
- `agents` 섹션의 Flutter 변형 (`generator-frontend-flutter` / `evaluator-functional-flutter`) 제거. 단일 에이전트가 `.harness/ref/<role>-<stack>.md` 동적 로드.
- AGENTS.md IA-MAP — 부서 권한 매트릭스 25항 (이전 12항).
- progress.json 스키마 v3 — `org/goals/conductor/meetings/cto/cqo/service_ops` 슬롯 추가.
- Evaluator chain 명시화: `evaluator-code-quality → evaluator-functional → evaluator-visual` (FULLSTACK/FE-ONLY) / `code-quality → functional` (BE-ONLY).

### Removed
- Flutter "유령 스킬" 참조 ([M-001] resolved). config.json + dispatcher SKILL.md 의 fe_stack_substitution 폐기.
- 기존 PRE-NEXUS dispatcher 단일 라인업.
- **Dispatcher 의 Solo/Team 모드 질문**. 사용자 "harness-solo / harness-team 입력하세요" 안내 패턴 제거.

### Mode Decision — User → Conductor 이양 (Breaking)
- `progress.json.mode` 디폴트 `"solo"` → `"auto"`. version 3 → 4.
- 신규 필드 `progress.json.mode_decision = { owner, decided_at, rationale, user_override }`.
- `config.json.mode_selection` 신규 — `force_team_when`(ready≥3 + features≥6 + depth≤2) / `force_solo_when` / tie-breaker=solo.
- Conductor SKILL §7.5: Planner 의 feature-list 확정 직후 자동 결정. 결정은 progress.json + progress.log 에 rationale 명시.
- `/harness-solo`, `/harness-team` 은 사용자 override 명령으로 의미 변경. `mode_decision.user_override` 에 기록되어 현재 sprint 종료까지 유지. "auto 로 돌려" 발화로 자동결정 복귀.
- Dispatcher SKILL §"Mode 결정 위임" — 모드 질문/추천 출력 모두 폐기. 사용자 발화에서 명시적 모드 신호 감지 시만 user_override 로 기록.

### Migration (5.9.x → 6.0.0)

기존 walwal-harness 사용 프로젝트는 `npm install @walwal-harness/cli@latest` 후 다음 한 줄로 자동 마이그레이션 가능:

```bash
npx walwal-harness migrate --dry-run    # 변경 미리보기
npx walwal-harness migrate              # 실제 적용
```

**자동 처리되는 것**:
- `progress.json` v3 → v4 — 기존 `mode` 값 (`"solo"` 또는 `"team"`) 을 `mode_decision.user_override` 로 **그대로 보존**. 새 mode 는 `"auto"` 로 셋되지만 user_override 로 직전 sprint 의 사용자 의도 유지.
- `config.json` 의 `mode_selection` 누락 시 자동 주입 (rules: ready≥3 + features≥6 + depth≤2 → team / 그 외 → solo). 사용자 customization (`behavior`, `flow.pre_eval_gate.*`) 은 **모두 보존**.
- 변경 전 자동 백업: `.harness/archive/migration-<timestamp>/` (progress.json + config.json 원본).

**수동 처리 권장**:
1. AGENTS.md 의 IA-MAP 권한 매트릭스 신규 25항 검토.
2. 기존 sprint 진행 중이라면 `.harness/archive/` 로 수동 이관 후 새 dispatch 시작.
3. `.claude/skills/` 의 신규 14개 부서 SKILL.md 가 정상 설치되었는지 확인 (`ls .claude/skills/` 에 conductor / cto / cqo / meeting-manager / service-ops / evaluator-architecture / evaluator-security 포함).
4. Flutter 프로젝트 사용자: `pubspec.yaml` 자동 감지 + `.harness/ref/generator-frontend-flutter.md` (있을 시) 로 동작. 누락 시 Planner 가 ref 생성 권고.

**Postinstall 안내**: `npm install` 후 v3 detect 시 안내 banner 가 출력될 수 있으나 npm v9+ 의 quiet mode 에서는 누락될 수 있습니다. 의심 시 `npx walwal-harness migrate --dry-run` 으로 직접 확인하세요.

### Reference
Phase C "Brick Office 대시보드 MVP" 가 본 v6 organization 기반 첫 풀사이클 검증 (3 sprints, 25 features, 모든 평가 PASS).

## 5.9.6 — Queue Integrity & Lead Guard (이전)
- queue enqueue/integrity 명령 추가, dashboard orphan 경고, Lead 가드.

## 5.9.5 — Solo/Team Mode Drift Fix
- progress.json mode drift 시 dashboard/tmux 가 SOLO 로 잘못 표시되던 버그 수정.

## 5.9.4 — Graceful Crash Recovery
- progress.json 손상 시 dashboard crash → 안내 메시지로 graceful 처리.

## 5.9.3 — Compressed Output Fix
- 분할 패널에서 Conventions/Memory 가 3 줄만 보이던 압축 출력 수정.
