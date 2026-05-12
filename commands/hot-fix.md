---
description: Start an urgent fix outside the active goal.
argument-hint: "<incident or fix request>"
---

# /hot-fix

Route the Owner request to the installed `harness-ceo` agent/skill as an emergency mission.

Required flow:
1. Create `.harness/documents/{hotfix_name}/ceo.md`.
2. CEO summons CTO and CQO first; summon COO/CDO only when planning or UX decisions are involved.
3. CTO applies the smallest correct patch path through hired implementation skills.
4. CXX roles must start in a fresh session context. Do not let the default model impersonate a missing CXX or worker.
5. CXX roles must not directly execute specialist deliverables. They must use hired workers for implementation, QA, ops checks, and documentation even when the fix is small.
6. If a required worker is missing, CEO or the responsible CXX must invoke the installed `harness-hiring` skill before assigning the work.
7. CEO must require worker report paths under `.harness/documents/{hotfix_name}/workers/` before accepting CXX completion.
8. CQO must register durable lessons in `.harness/gotchas/`, `.harness/conventions/`, or `.harness/memories/`. This step is mandatory, not optional, even for small fixes.
9. Archive only after CQO has accepted the fix.
10. Do not invoke internal roles through slash commands; commands are Owner entrypoints only.

Note: Harness documents (ceo.md, cto.md, cqo.md, worker reports) are mission records, not derived output documents. A docmeta skip decision on these files does not authorize skipping any harness protocol step.

Hot-fix request:

```
$ARGUMENTS
```
