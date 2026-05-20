# walwal-harness Runtime Reference

This project runs in company mode.

Owner-facing commands are limited to:

| Command | Purpose | Document root |
|---|---|---|
| `/goal` | Set or change the company goal | `.harness/documents/goal-{index}-{name}/` |
| `/submission` | Add a requirement under the active goal | `.harness/documents/goal-{index}-{name}/submission-{index}-{name}/` |
| `/hot-fix` | Fix an urgent issue under the active goal | `.harness/documents/goal-{index}-{name}/hotfix-{index}-{name}/` |

No CXX role is a slash command. `/ceo`, `/coo`, `/cdo`, `/cto`, `/cqo`, `/ops`, `/hiring`, and `/resource-manager` are invalid Owner commands.

## Company Structure

```
Owner
  └─ /goal, /submission, or /hot-fix
      └─ harness-ceo
          ├─ harness-coo
          ├─ harness-cdo
          ├─ harness-cto
          ├─ harness-cqo
          └─ harness-ops
```

CEO is the Owner's only internal contact. CEO talks only to CXX agents. CXX agents coordinate, hire, review, and decide; they do not directly produce specialist deliverables.

## Owner Role

Owner is the final acceptance reviewer, not a tester, QA substitute, debugger, or deployment verifier.

- Do not give the Owner broken, unverified, or partially runnable software with "please check this" as the next action.
- CEO/CXX must use worker-backed verification before requesting Owner acceptance: unit tests, E2E tests, Playwright/browser checks, test accounts, seeded data, build/run checks, logs, CQO evidence, and OPS runtime evidence when relevant.
- Missing verification is a BLOCKED/FAIL condition, not an Owner task.
- Final Owner reports may ask for acceptance review, product judgment, or business approval; they must not ask the Owner to discover whether the software works.

## Runtime Paths

| Path | Role |
|---|---|
| `.harness/documents/goal-{index}-{name}/ceo.md` | Goal framing and CEO routing |
| `.harness/documents/goal-{index}-{name}/{cxx}.md` | Goal-level CXX decision record |
| `.harness/documents/goal-{index}-{name}/submission-{index}-{name}/` | Additional requirement under the active goal |
| `.harness/documents/goal-{index}-{name}/hotfix-{index}-{name}/` | Emergency fix under the active goal |
| `.harness/documents/{goal-or-child-mission}/{owning-cxx}/workers/{worker-name}.md` | Worker evidence owned by a CXX |
| `.harness/conventions/` | Durable rules, including requirement conventions from submissions |
| `.harness/gotchas/` | Recurrence-prevention records from hot-fixes |
| `.harness/memories/` | Long-term shared context |
| `.harness/shared/HR-Resource/` | Hireable worker skill pool |
| `.harness/shared/hr-roster.json` | Hired worker roster |
| `.harness/archive/` | CQO-approved completed mission records |
| `.harness/progress.log` | Append-only command and status history |
| `.harness/progress.json` | Machine-readable current runtime state |

Flat `.harness/documents/{mission}/workers/` reports are legacy. New worker evidence must be under `{owning-cxx}/workers/`.

## Required Flow

### Goal

1. CEO creates or updates `.harness/documents/goal-{index}-{name}/ceo.md`.
2. CEO routes only needed CXX agents.
3. Each CXX writes its own `{cxx}.md`.
4. CXX agents use `harness-resource-manager` and `harness-hiring` before assigning specialist work.
5. Workers write evidence under `{owning-cxx}/workers/`.
6. CEO reports only after CXX records and required worker evidence exist.

### Submission

1. CEO locates the active goal directory.
2. CEO creates `.harness/documents/goal-{index}-{name}/submission-{index}-{name}/ceo.md`.
3. CEO routes only the CXX needed for the additional requirement.
4. CXX agents update `.harness/conventions/` when the new requirement creates or changes durable project rules.
5. Worker reports and CXX notes stay inside the submission directory.

### Hot Fix

1. CEO locates the active goal directory.
2. CEO creates `.harness/documents/goal-{index}-{name}/hotfix-{index}-{name}/ceo.md`.
3. CEO routes CTO and CQO first.
4. CTO hires implementation workers and records the patch plan in `cto.md`.
5. CQO hires evaluator/tester workers and records the verdict in `cqo.md`.
6. CQO registers at least one durable lesson in `.harness/gotchas/`, `.harness/conventions/`, or `.harness/memories/`.

## Hard Gates

- CEO must not dispatch, hire, or brief workers directly.
- CXX agents must not directly execute specialist deliverables.
- CTO worker dispatch requires `cto.md` first.
- CQO verdicts require evaluator/tester worker evidence.
- Owner is final acceptance only. Do not report "done, please check" until worker-backed verification proves the goal is complete.
- Every `ceo.md`, `{cxx}.md`, and worker report must end with:

```markdown
## Implementation Notes

### Design Decisions
- None

### Deviations
- None

### Tradeoffs
- None

### Open Questions
- None
```

The notes must be written in English. Use `None` when a subsection has no entries. Do not create a separate sidecar notes file; keep the notes at the bottom of the same role or worker report that produced the decision/evidence.
