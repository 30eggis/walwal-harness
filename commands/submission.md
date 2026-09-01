---
description: Add a requirement under the active goal.
argument-hint: "<additional requirement>"
---

# /submission

Route the Owner request to the installed `harness-ceo` agent/skill as an additional requirement under the active goal.

Codex adapter:
- If Codex does not auto-load `harness-ceo`, manually read `.codex/skills/harness-ceo/SKILL.md` and follow it.
- Absence of `.codex/agents/` is not a failure. `.codex/skills/**/SKILL.md` is the Codex runtime protocol.
- For CXX "fresh session context", use role-scoped context: read the CXX skill, active mission files, and required conventions/gotchas before writing that role's `{cxx}.md`.

Required flow:
1. Locate the active goal document root under `.harness/documents/{goal_name}/`. If no active goal exists, CEO must create/select the best matching goal record from available mission context or mark the submission blocked with the recommended default; do not ask the Owner an open-ended setup question.
2. If another child mission under the goal is active, update its `mission-state.json` to `closed`, `cancelled`, or `superseded` with `active:false` before starting this submission.
3. Create a submission record under `.harness/documents/{goal_name}/submission-{submission_index}-{submission_name}/`.
4. Write `.harness/documents/{goal_name}/submission-{submission_index}-{submission_name}/mission-state.json` with `{"lifecycle":"active","active":true}`.
5. Record CEO decisions in `.harness/documents/{goal_name}/submission-{submission_index}-{submission_name}/ceo.md`.
6. CEO routes only to the CXX agents needed for this additional requirement. CEO must not ask the Owner which CXX or worker path to choose.
7. CXX roles must start in a fresh session context. Do not let the default model impersonate a missing CXX or worker.
8. CXX roles must not directly execute specialist deliverables. They must use hired workers for research, planning, design, implementation, QA, ops checks, and documentation.
9. If a required worker is missing, the responsible CXX must invoke the installed `harness-hiring` skill before assigning the work.
10. CXX must manage conventions for new requirements. Durable changes in behavior, architecture, UI, process, or policy must be reflected in `.harness/conventions/` when accepted.
11. CEO must require a Worker Evidence Manifest and worker report paths under `.harness/documents/{goal_name}/submission-{submission_index}-{submission_name}/{owning-cxx}/workers/` before accepting CXX completion.
12. When the submission is accepted, cancelled, superseded, blocked, or closed, update `mission-state.json` to `complete`, `cancelled`, `superseded`, `blocked`, or `closed` and set `active:false`. Then fire the matching runtime transition as the literal final action of the turn so the terminal document state matches the `progress.json` flag the harness reads: finished/closed → `bash scripts/harness-company-complete.sh . submission-complete`; external-authority block → `bash scripts/harness-company-block.sh . "<exact missing authority>"`. This clears `progress.json` out of `running` so the autonomous loop stops cleanly and the dashboard shows idle/done.
13. Do not invoke internal roles through slash commands; commands are Owner entrypoints only.
14. Do not ask the Owner whether to continue, hire workers, choose internal options, or start the next step. If CEO cannot decide alone, convene the relevant CXX agents and decide from their written recommendations. CEO may approve reversible routine operations such as local cron/launchd/wake automation, dashboard refresh, monitoring cadence, Telegram briefing format using existing credentials, and mission consolidation/supersede cleanup. Stop only for external authority such as new credentials/secrets, payment approval, legal/business acceptance, unavailable production access, destructive data action, or direct conflict with stated Owner direction.

Lessons before plan (AGENTS.md Hard Rule 20): CEO and every CXX read `.harness/conventions/{shared,role}.md` and `.harness/gotchas/{shared,role}.md`, follow only the topic links those files name, and write `## Lessons Preflight` **before** the first edit, the first measurement, and the first worker brief. Every role document and worker report closes with a one-line `## Lessons Tally` immediately above `## Implementation Notes` — `0 fired` is a valid tally and must be stated, not omitted. Requirements a CXX must satisfy that its workers must also satisfy go into the worker brief **verbatim**. The Stop hook enforces this; it is not advisory.

Note: `/submission` is not a new company goal and not an emergency fix. It is an additional requirement while pursuing the active goal. It belongs under that goal in history.

Submission request:

```
$ARGUMENTS
```
