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
1. Locate the active goal document root under `.harness/documents/{goal_name}/`. If no active goal exists, CEO must ask the Owner to create or select one with `/goal` before proceeding.
2. If another child mission under the goal is active, update its `mission-state.json` to `closed`, `cancelled`, or `superseded` with `active:false` before starting this submission.
3. Create a submission record under `.harness/documents/{goal_name}/submission-{submission_index}-{submission_name}/`.
4. Write `.harness/documents/{goal_name}/submission-{submission_index}-{submission_name}/mission-state.json` with `{"lifecycle":"active","active":true}`.
5. Record CEO decisions in `.harness/documents/{goal_name}/submission-{submission_index}-{submission_name}/ceo.md`.
6. CEO routes only to the CXX agents needed for this additional requirement.
7. CXX roles must start in a fresh session context. Do not let the default model impersonate a missing CXX or worker.
8. CXX roles must not directly execute specialist deliverables. They must use hired workers for research, planning, design, implementation, QA, ops checks, and documentation.
9. If a required worker is missing, the responsible CXX must invoke the installed `harness-hiring` skill before assigning the work.
10. CXX must manage conventions for new requirements. Durable changes in behavior, architecture, UI, process, or policy must be reflected in `.harness/conventions/` when accepted.
11. CEO must require a Worker Evidence Manifest and worker report paths under `.harness/documents/{goal_name}/submission-{submission_index}-{submission_name}/{owning-cxx}/workers/` before accepting CXX completion.
12. When the submission is accepted, cancelled, superseded, blocked, or closed, update `mission-state.json` to `complete`, `cancelled`, `superseded`, `blocked`, or `closed` and set `active:false`.
13. Do not invoke internal roles through slash commands; commands are Owner entrypoints only.

Note: `/submission` is not a new company goal and not an emergency fix. It is an additional requirement while pursuing the active goal. It belongs under that goal in history.

Submission request:

```
$ARGUMENTS
```
