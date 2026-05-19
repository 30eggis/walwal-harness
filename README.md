# @walwal-harness/cli

**v7.1** — Company-mode AI agent harness for Claude Code and Codex.

One project = one company. The Owner speaks only to the CEO. The CEO speaks only to CXX agents. CXX agents hire specialist workers. No one skips a level.

---

## Company Structure

```
Owner
  └─ /goal · /hot-fix
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
| `.claude/commands/hot-fix.md` | `/hot-fix` Owner command |
| `.claude/skills/harness-{ceo,coo,cdo,cto,cqo,ops}/` | CXX agent skills |
| `.harness/shared/HR-Resource/` | Hireable worker skill pool |
| `AGENTS.md` ← `CLAUDE.md` symlink | Project harness config |

---

## Mission Flow

### Goal

```
Owner /goal → CEO → [COO] → [CDO] → CTO → [dev workers] → CQO → [evaluator workers]
```

1. CEO reads Owner request, writes `ceo.md`, routes to relevant CXX.
2. Each CXX writes its own `{cxx}.md`, hires workers, collects evidence.
3. CEO aggregates CXX outputs and reports to Owner.

### Hot Fix

```
Owner /hot-fix → CEO → CTO → [dev workers] → CQO → [evaluator workers]
```

1. CEO summons CTO and CQO immediately.
2. CTO designs minimum patch, hires implementation workers, writes `cto.md`.
3. CQO runs regression gate with evaluator workers, registers gotcha/convention, writes `cqo.md`.

**Complete when:** `cto.md` + `cqo.md` + at least one `.harness/gotchas/` or `.harness/conventions/` entry exist.

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
| 9 | Hierarchical worker ownership — worker reports live under `.harness/documents/{mission}/{owning-cxx}/workers/` |
| 10 | Implementation Notes required — `ceo.md`, every `{cxx}.md`, and every worker report must end with an English `## Implementation Notes` section |

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

Use `None` when a subsection has no entries. This section is mandatory even for small or emergency work. CEO must reject any CXX report that omits it. CTO and CQO must not accept worker output that omits it.

---

## Harness Dashboard

The harness ships with a real-time dashboard that reads `.harness/documents/` directly.

```bash
bash scripts/harness-dashboard-up.sh
```

Features:

- **Org Tree** — live status of Owner → CEO → CXX → Workers hierarchy
- **Mission Timeline** — clickable history of goal/hot-fix missions showing the full dispatch chain
- **Mission Flow tab** — per-mission flow: Owner prompt → CEO routing → CXX → worker files changed → CQO verdict
- **History tab** — mission-specific Owner request (from CEO summary + closest progress.log match)
- **Gotchas tab** — searchable `.harness/gotchas/*.md` knowledge base, click to read full markdown
- **Document tab** — per-CXX markdown doc viewer

---

## Harness Runtime Paths

| Path | Role |
|---|---|
| `.harness/documents/{mission}/` | CXX decisions and worker reports per mission |
| `.harness/documents/{mission}/{cxx}/workers/` | Worker reports owned by that CXX |
| `.harness/conventions/` | Durable rules (CQO writes, survives missions) |
| `.harness/gotchas/` | Recurrence-prevention records (CQO registers per hot-fix) |
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
