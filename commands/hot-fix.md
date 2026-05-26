---
description: Start an urgent fix under the active goal.
argument-hint: "<incident or fix request>"
---

# /hot-fix

Route the Owner request to the installed `harness-ceo` agent/skill as an emergency mission under the active goal.

Codex adapter:
- If Codex does not auto-load `harness-ceo`, manually read `.codex/skills/harness-ceo/SKILL.md` and follow it.
- Absence of `.codex/agents/` is not a failure. `.codex/skills/**/SKILL.md` is the Codex runtime protocol.
- For CXX "fresh session context", use role-scoped context: read the CXX skill, active mission files, and required conventions/gotchas before writing that role's `{cxx}.md`.

Required flow:
1. Locate the active goal document root under `.harness/documents/{goal_name}/`. If no active goal exists, CEO must create/select one before proceeding.
2. Create `.harness/documents/{goal_name}/hotfix-{hotfix_index}-{hotfix_name}/ceo.md`.
3. CEO summons CTO and CQO first; summon COO/CDO only when planning or UX decisions are involved.
4. CTO applies the smallest correct patch path through hired implementation skills.
5. CXX roles must start in a fresh session context. Do not let the default model impersonate a missing CXX or worker.
6. CXX roles must not directly execute specialist deliverables. They must use hired workers for implementation, QA, ops checks, and documentation even when the fix is small.
7. If a required worker is missing, CEO or the responsible CXX must invoke the installed `harness-hiring` skill before assigning the work.
8. CEO must require worker report paths under `.harness/documents/{goal_name}/hotfix-{hotfix_index}-{hotfix_name}/{owning-cxx}/workers/` before accepting CXX completion.
9. CQO must register durable lessons in `.harness/gotchas/`, `.harness/conventions/`, or `.harness/memories/`. This step is mandatory, not optional, even for small fixes.
10. Archive only after CQO has accepted the fix.
11. Do not invoke internal roles through slash commands; commands are Owner entrypoints only.

Note: `/hot-fix` is a problem-fix flow while pursuing the active goal. It belongs under that goal in history.

Harness documents (ceo.md, cto.md, cqo.md, worker reports) are mission records, not derived output documents. A docmeta skip decision on these files does not authorize skipping any harness protocol step.

Hot-fix request:

```
$ARGUMENTS
```
