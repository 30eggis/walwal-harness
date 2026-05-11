---
description: Set, revise, or extend a company mission goal.
argument-hint: "<goal request>"
---

# /goal

Route the Owner request to the installed `harness-ceo` agent/skill.

Required flow:
1. Create or update a mission under `.harness/documents/{mission_name}/`.
2. Record CEO decisions in `.harness/documents/{mission_name}/ceo.md`.
3. CEO decides whether brainstorming is needed or whether CXX questions can be issued immediately.
4. CEO asks COO, CDO, CTO, and CQO only the questions needed for this goal.
5. CXX roles must start in a fresh session context. Do not let the default model impersonate a missing worker.
6. If a required CXX or worker skill is missing, CEO must invoke the installed `harness-hiring` skill before assigning the work.
7. Do not invoke internal roles through slash commands; commands are Owner entrypoints only.

Owner request:

```
$ARGUMENTS
```
