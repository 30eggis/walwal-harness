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
4. CQO records regression coverage and recurrence prevention.
5. Register durable lessons in `.harness/gotchas/`, `.harness/conventions/`, or `.harness/memories/` as appropriate.
6. Archive only after CQO has accepted the fix.
7. Do not invoke internal roles through slash commands; commands are Owner entrypoints only.

Hot-fix request:

```
$ARGUMENTS
```
