---
description: Start an urgent fix outside the active goal.
argument-hint: "<incident or fix request>"
---

# /hot-fix

Route the Owner request to the installed `harness-ceo` agent/skill as an emergency mission.

Required flow:
1. Create `.harness/documents/{hotfix_name}/ceo.md`.
2. CEO summons CTO and CQO; summon COO/CDO only when planning or UX decisions are involved.
3. CTO applies the smallest correct patch path through hired implementation skills.
4. CXX roles must not directly execute specialist deliverables. They must use hired workers for implementation, QA, ops checks, and documentation even when the fix is small.
5. If a required worker is missing, CEO or the responsible CXX must invoke the installed `harness-hiring` skill before assigning the work.
6. CQO records regression coverage and recurrence prevention with worker report paths under `.harness/documents/{hotfix_name}/workers/`.
7. Register durable lessons in `.harness/gotchas/`, `.harness/conventions/`, or `.harness/memories/` as appropriate.
8. Archive only after CQO has accepted the fix.
9. Do not invoke internal roles through slash commands; commands are Owner entrypoints only.

Hot-fix request:

```
$ARGUMENTS
```
