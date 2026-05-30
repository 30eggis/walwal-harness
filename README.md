# @walwal-harness/cli

**v7.1** — Company-mode AI agent harness for Claude Code and Codex.

One project = one company. The Owner speaks only to the CEO. The CEO speaks only to CXX agents. CXX agents hire specialist workers. No one skips a level.

---

## Company Structure

```
Owner
  └─ /goal · /submission · /hot-fix
      └─ harness-ceo          orchestrator — Owner's only contact
          ├─ harness-coo      research, hypothesis, service direction
          ├─ harness-cdo      branding, UI/UX, design review
          ├─ harness-cto      architecture, API, platform, implementation
          ├─ harness-cqo      quality gates, regression, archive, gotcha/convention
          └─ harness-ops      build monitoring, log analysis, service events
```

### Hierarchy Rules (non-negotiable)

- **CEO → CXX only.** CEO never dispatches or hires workers directly. All worker contact goes through the responsible CXX.
- **CTO → dev workers.** CTO hires and briefs implementation workers. `cto.md` must exist before any worker is dispatched.
- **CQO → evaluator/tester workers.** CQO hires evaluation workers and bases its verdict entirely on their evidence. Self-inspection by CQO is not valid evidence.
- **No CXX self-execution.** CXX agents coordinate and manage only. A CXX that produces specialist deliverables without matching worker records has violated its scope.
- **No verdict without worker evidence.** CQO cannot issue ACCEPTED/REJECTED without a Worker Evidence Manifest referencing at least one evaluator worker.

---

## Install

```bash
npm i @walwal-harness/cli
```

Restart Claude Code after install.

To initialize a project:

```bash
npx walwal-harness init
```

What `init` installs:

| Path | Contents |
|---|---|
| `.claude/commands/goal.md` | `/goal` Owner command |
| `.claude/commands/submission.md` | `/submission` Owner command |
| `.claude/commands/hot-fix.md` | `/hot-fix` Owner command |
| `.claude/skills/harness-{ceo,coo,cdo,cto,cqo,ops}/` | CXX agent skills |
| `.harness/shared/HR-Resource/` | Hireable worker skill pool |
| `.harness/events.jsonl` | Structured append-only runtime event stream |
| `.harness/todos/state.json` | Machine-readable CXX todo queues |
| `.harness/todos/events.jsonl` | Structured todo transition history |
| `AGENTS.md` + `CLAUDE.md` symlink | Project AI operating rules |

---

## Project Docs Merge

`AGENTS.md` is the source of truth for project AI operating rules. `CLAUDE.md` is normalized to a symlink that points at `AGENTS.md`.

Install and migrate preserve existing project instructions:

- Existing `AGENTS.md` is not replaced. The harness adds or updates a marked section between `<!-- walwal-harness:agents:start -->` and `<!-- walwal-harness:agents:end -->`.
- The top of `AGENTS.md` gets a small walwal-harness enabled marker so agents know the harness section applies.
- Existing `CLAUDE.md` file content is appended into `AGENTS.md` under a `preserved-claude` marked section, then `CLAUDE.md` is replaced with a symlink to `AGENTS.md`.
- Re-running `init`, `init --force`, or `migrate` is idempotent: marked sections are replaced, not duplicated.
- Existing docs and symlink targets are backed up under `.harness/archive/pre-harness-backup/` or the migration backup directory before modification.

---

## Mission Flow

### Goal

```
Owner /goal → CEO → [COO] → [CDO] → CTO → [dev workers] → CQO → [evaluator workers]
```

1. CEO reads Owner request, writes `ceo.md`, routes to relevant CXX.
2. Each CXX writes its own `{cxx}.md`, hires workers, collects evidence.
3. CEO aggregates CXX outputs and reports to Owner.
4. Every goal/submission/hot-fix mission has `mission-state.json` with `lifecycle` and `active`.

### Hot Fix

```
Owner /hot-fix → CEO → CTO → [dev workers] → CQO → [evaluator workers]
```

1. CEO summons CTO and CQO immediately.
2. CTO designs minimum patch, hires implementation workers, writes `cto.md`.
3. CQO runs regression gate with evaluator workers, registers gotcha/convention, writes `cqo.md`.

**Complete when:** `cto.md` + `cqo.md` + at least one `.harness/gotchas/` or `.harness/conventions/` entry exist.

### Submission

```
Owner /submission → CEO → [relevant CXX] → [workers] → [convention updates]
```

1. CEO locates the active `.harness/documents/goal-{index}-{name}/`.
2. CEO creates `.harness/documents/goal-{index}-{name}/submission-{index}-{name}/`.
3. Relevant CXX update `.harness/conventions/` when the new requirement changes durable project rules.

---

## Hard Rules

| # | Rule |
|---|---|
| 1 | No source edit without `{mission}/cto.md` — CTO scope sign-off required |
| 2 | No CXX impersonation — use installed harness skills in fresh sessions |
| 3 | No unnamed workers — all work routes through `harness-hiring` → `harness-resource-manager` |
| 4 | No archive without CQO verdict — `{mission}/cqo.md` with explicit PASS must exist |
| 5 | No gotcha skip — every hot-fix produces at least one gotcha or convention entry |
| 6 | CEO routes only to CXX — never directly to workers |
| 7 | No CXX self-execution — deliverables without matching worker records are rejected |
| 8 | No verdict without worker evidence — CQO self-inspection is not valid |
| 9 | Hierarchical worker ownership — worker reports live under `.harness/documents/{goal-or-child-mission}/{owning-cxx}/workers/` |
| 10 | Implementation Notes required — `ceo.md`, every `{cxx}.md`, and every worker report must end with one English `## Implementation Notes` section in the same file |
| 11 | Structured runtime state — queues, heartbeats, preemption/resume state, and harness-parsed evidence belong in JSON/JSONL, not free-form Markdown |

### Implementation Notes Format

Every `ceo.md`, `{cxx}.md`, and worker report must end with:

```markdown
## Implementation Notes

### Design Decisions
- How the role interpreted the Owner request

### Deviations
- Where the role intentionally diverged from the request

### Tradeoffs
- Alternatives considered and why they were rejected

### Open Questions
- What still needs Owner or CXX confirmation
```

Use `None` when a subsection has no entries. This section is mandatory even for small or emergency work. Do not create a separate sidecar notes file; the notes belong at the bottom of the same role or worker report that produced the decision/evidence. CEO must reject any CXX report that omits it. CTO and CQO must not accept worker output that omits it.

---

## Harness Dashboard

The harness ships with a real-time dashboard that reads `.harness/` runtime state directly. The current dashboard is process-oriented: it highlights CXX todo readiness, active workers, incidents, mission flow, and structured runtime events alongside the organization view.

```bash
bash scripts/harness-dashboard-up.sh
```

Run on a different port:

```bash
bash scripts/harness-dashboard-up.sh --port 3002
```

Force-refresh the isolated dashboard cache when an older dashboard is still shown:

```bash
bash scripts/harness-dashboard-up.sh --port 3002 --reinstall
```

Dashboard options:

| Option | Role |
|---|---|
| `--port <port>` | Run Brick Office on a custom port, e.g. `3002` |
| `--reinstall` | Delete and rebuild the isolated dashboard cache under `~/.walwal-harness/dashboard/` |

### Company Auto-Chain State

`/goal`, `/submission`, and `/hot-fix` mark the v7 company loop as running in `.harness/progress.json`:

- `company_state.state = "running"`
- `conductor.state = "running"`
- `current_agent = "ceo"`
- `next_agent = "ceo"`

Claude's Stop hook uses this state to prevent an unfinished CEO/CXX/worker loop from ending after a partial routing step such as hiring. Hookless executors such as Codex should drive the same state through an external runner or dashboard auto-mode process.

When the mission is genuinely complete, the common completion transition is:

```bash
bash scripts/harness-company-complete.sh . mission-complete
```

This sets `company_state.state = "idle"`, `conductor.state = "completed"`, `next_agent = "none"`, and `owner_prompt.status = "completed"` so dashboards, runners, and hooks agree that auto-mode can stop.

It also closes structured work state:

- active/pending/paused todos in `.harness/todos/state.json` become `done`
- active `mission-state.json` files become `{"lifecycle":"complete","active":false}`
- the dashboard stops treating recent worker report mtimes as live activity after runtime completion
- heatmap activity is persisted in `.harness/activity/YYYY-MM-DD.jsonl` and pruned after 7 days

Existing users should update and migrate from the target project:

```bash
npm i @walwal-harness/cli@latest
npx walwal-harness migrate
```

If command discovery or installed harness files look stale, refresh the install contract:

```bash
npx walwal-harness init --force
```

For an explicit project root:

```bash
npx walwal-harness migrate --project-root /path/to/project
npx walwal-harness init --force --project-root /path/to/project
```

Features:

- **Company Harness Observatory** — glass/aurora process monitor showing active CXX todos, workers, incidents, missions, and current loop state
- **Layer Activity by CXX/Worker** — Layer Activity rows match the heatmap hierarchy, grouping each CXX with its workers and sorting groups by remaining work first, completed groups next, empty CXX groups last
- **Explicit Mission Lifecycle** — goal/submission/hot-fix directories use `mission-state.json`; `init`, `init --force`, and `migrate` backfill missing lifecycle files for existing projects
- **Structured Runtime State** — `/goal`, `/submission`, and `/hot-fix` append to `.harness/events.jsonl` and update `.harness/todos/state.json`; `migrate` backfills these files for existing projects
- **Split Workspace** — full-viewport left/right panes keep Org Tree + Mission Timeline beside the selected mission detail; both panes scroll independently with hidden scrollbars, and the detail pane resets to top on selection changes
- **Org Tree** — live status of Owner → CEO → CXX → Workers hierarchy, with worker cards created only from hired `hr-roster.json` entries backed by `.harness/shared/HR-Resource/{worker}/SKILL.md`; running hired workers are highlighted under their owning CXX
- **Mission Timeline** — clickable history of goal/submission/hot-fix missions showing the full dispatch chain
- **Mission Flow tab** — per-mission flow: Owner prompt → CEO routing → CXX → owner-specific worker evidence → CQO verdict
- **CDO Preview** — clicking `harness-cdo` opens a dashboard iframe preview from `.harness/documents/{mission}/cdo/preview.html`; CDO completion requires this visual summary artifact
- **History tab** — mission-specific Owner request (from CEO summary + closest progress.log match)
- **Gotchas tab** — searchable `.harness/gotchas/*.md` knowledge base, click to read full markdown
- **Document tab** — per-CXX markdown doc viewer
- **Owner Acceptance Gate** — Owner is final acceptance only; CEO/CXX must complete worker-backed verification before asking for Owner review

Hourly autonomous wake:

- `HARNESS_WAKE_EXECUTOR=claude|codex` selects `claude -p` or `codex exec`.
- `HARNESS_WAKE_MODEL=<model>` optionally pins the Claude model for wake ticks.
- Each wake tick prompts CEO to convene CXX + OPS, collect progress and decisions, dispatch the next action without asking Owner, and require CQO/OPS verification until the active goal works.
- `npx @walwal-harness/cli migrate` refreshes package-owned runtime scripts, so existing projects receive wake prompt updates without a full re-init.
- In Codex, `.codex/skills/**/SKILL.md` files are the runtime protocol. `.codex/agents/` is not required; Codex should manually read the relevant skill if it is not auto-listed.
- Convention/gotcha topic files lazy-load through CXX index links: `migrate` preserves files such as `.harness/gotchas/i18n-locale-hotfix.md` and links them from relevant CXX files like `cto.md` and `cqo.md`.
- COO can use `support-support-mcp-registry-steward` to inventory Claude/Codex MCP capabilities, registration risk, credentials, and maintenance notes before recommending MCP use.

---

## Harness Runtime Paths

| Path | Role |
|---|---|
| `.harness/documents/goal-{index}-{name}/` | Goal-level CXX decisions and worker reports |
| `.harness/documents/goal-{index}-{name}/submission-{index}-{name}/` | Additional requirement under the active goal |
| `.harness/documents/goal-{index}-{name}/hotfix-{index}-{name}/` | Emergency fix under the active goal |
| `.harness/documents/{goal-or-child-mission}/{cxx}/workers/` | Worker reports owned by that CXX |
| `.harness/conventions/` | Durable rules and CXX lazy-loading indexes |
| `.harness/gotchas/` | Recurrence-prevention records and CXX lazy-loading indexes |
| `.harness/shared/HR-Resource/` | Hireable worker skill pool |
| `.harness/archive/` | CQO-approved completed missions (immutable) |
| `.harness/logs/YYYY-MM-DD/` | OPS exception logs |

---

## Hiring

Any CXX uses `harness-hiring` before assigning work to a specialist not yet on roster.

```
harness-resource-manager → find available worker
harness-hiring           → register and onboard worker
{cxx} → hired worker     → deliverable → {cxx} evidence manifest
```

---

## Version History

| Version | Summary |
|---|---|
| 7.1.37 | Adds CEO autonomous decision charter, prevents routine Owner progress questions, and limits Owner waits to true external-authority blocks |
| 7.1.36 | Stop hook only validates worker evidence while chaining the active loop, scopes validation to the newest active mission, and makes the 24h heatmap visible at 10-minute resolution |
| 7.1.35 | Fix dashboard heatmap mission scoping, choose the newest active mission for activity recording, and normalize duplicate active child mission states during init/migrate |
| 7.1.34 | Fix dashboard 500 when `company_state.workers` is recorded as a keyed worker map instead of an array |
| 7.1.33 | Dashboard keeps recently written worker reports active even when docmeta is present, and CXX skills now record worker activity telemetry for live dashboard state |
| 7.1.31 | Persist dashboard heatmap activity to 7-day JSONL logs, load persisted samples in the dashboard, and backfill activity during migrate from existing mission docs/progress logs |
| 7.1.29 | Idempotent AGENTS/CLAUDE doc merge with marked harness sections, mission lifecycle backfill for init/migrate, completion closes todos and mission-state, and Layer Activity now lists CXX/worker rows sorted by remaining work |
| 7.1.28 | Dashboard APM rewrite: top header consolidation, Knowledge Base panel (gotchas/conventions), Layer Activity (CEO/CXX/Worker TODO·DONE·Remain via goal-scope inference), Recent Report list (worker mtime desc), Cadence strip with click-to-prompt tooltip in local timezone, heatmap click-tooltip with empty-cell guard, Document Viewer expand-to-50vw with docmeta hidden, Command Log bubble popover |
| 7.1.19 | `migrate` now carries OPS verification rules into existing installs: runtime.verification merge, HARNESS refresh, and AGENTS migration block |
| 7.1.18 | OPS watches CQO runnable verification and production incidents; Implementation Notes stay in the same role/worker report |
| 7.1.17 | Dashboard: fix /submission and /hot-fix missions displaying as /goal; runtime strip shows live owner command in mission flow tab |
| 7.1.16 | `migrate` now always fully replaces /goal, /submission, /hot-fix commands regardless of current state |
| 7.1.15 | Dashboard: reset embedded View Doc state when the selected mission or document target changes |
| 7.1.14 | Owner acceptance gate: Owner is final reviewer, not tester; dashboard org-node clicks initialize the detail pane |
| 7.1.13 | Dashboard: full-viewport split workspace, hidden pane scrollbars, and detail scroll reset on selection |
| 7.1.12 | Dashboard: split workspace panes now scroll independently |
| 7.1.11 | Dashboard: persistent 50/50 split workspace and CXX-owned worker grouping in the org tree |
| 7.1.10 | Adds `/submission` and nested goal/submission/hot-fix mission history |
| 7.1.9 | Dashboard is packaged with npm and auto-syncs isolated cache by package version; README documents dashboard port/reinstall and update/migrate commands |
| 7.1.8 | HR-Resource: replace China-platform-specific workers with global equivalents; refine cross-border/video/livestream skills |
| 7.1.7 | Implementation Notes mandatory in all CXX docs and worker reports; harness-worker-evidence-validate.sh |
| 7.1.6 | CXX hierarchy enforcement: CEO→CXX-only gate, CTO prerequisite gate, CQO worker-evidence mandate; dashboard gotchas tab, mission-specific history tab, worker file list in flow |
| 7.1.5 | Dashboard: mission flow timeline, markdown viewer, 50vw drawer |
| 7.1.4 | Dashboard: org-tree redesign with real `.harness/documents/` data |
| 7.1.3 | Karpathy-style AGENTS.md rewrite, ko templates, hot-fix harness gate rules |
| 7.1.2 | v7 CEO routing migration, legacy command removal |
| 7.1.1 | CEO no-git hiring fix, gotcha/convention migration |
| 7.1.0 | v7.1 merge: OPS monitoring, CXX hiring enforcement |

---

## License

MIT
