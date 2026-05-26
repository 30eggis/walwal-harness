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
2. Create a submission record under `.harness/documents/{goal_name}/submission-{submission_index}-{submission_name}/`.
3. Record CEO decisions in `.harness/documents/{goal_name}/submission-{submission_index}-{submission_name}/ceo.md`.
4. CEO routes only to the CXX agents needed for this additional requirement.
5. CXX roles must start in a fresh session context. Do not let the default model impersonate a missing CXX or worker.
6. CXX roles must not directly execute specialist deliverables. They must use hired workers for research, planning, design, implementation, QA, ops checks, and documentation.
7. If a required worker is missing, the responsible CXX must invoke the installed `harness-hiring` skill before assigning the work.
8. CXX must manage conventions for new requirements. Durable changes in behavior, architecture, UI, process, or policy must be reflected in `.harness/conventions/` when accepted.
9. CEO must require worker report paths under `.harness/documents/{goal_name}/submission-{submission_index}-{submission_name}/{owning-cxx}/workers/` before accepting CXX completion.
10. Do not invoke internal roles through slash commands; commands are Owner entrypoints only.

Note: `/submission` is not a new company goal and not an emergency fix. It is an additional requirement while pursuing the active goal. It belongs under that goal in history.

Submission request:

```
$ARGUMENTS
```
