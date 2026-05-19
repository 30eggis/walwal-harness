---
description: Set, revise, or extend a company mission goal.
argument-hint: "<goal request>"
---

# /goal

Route the Owner request to the installed `harness-ceo` agent/skill.

Required flow:
1. Create or update a goal under `.harness/documents/goal-{goal_index}-{goal_name}/`.
2. Record CEO decisions in `.harness/documents/goal-{goal_index}-{goal_name}/ceo.md`.
3. CEO decides whether brainstorming is needed or whether CXX questions can be issued immediately.
4. CEO asks COO, CDO, CTO, and CQO only the questions needed for this goal.
5. CXX roles must start in a fresh session context. Do not let the default model impersonate a missing worker.
6. CXX roles must not directly execute specialist deliverables. They must use hired workers for research, planning, design, implementation, QA, ops checks, and documentation.
7. If a required CXX or worker skill is missing, CEO must invoke the installed `harness-hiring` skill before assigning the work.
8. CEO must require worker report paths under `.harness/documents/goal-{goal_index}-{goal_name}/{owning-cxx}/workers/` before accepting CXX completion.
9. Do not invoke internal roles through slash commands; commands are Owner entrypoints only.

Note: A goal is the company's objective. Submissions and hot-fixes that happen while pursuing it should be recorded under that goal directory.

Harness documents (ceo.md, cto.md, cqo.md, worker reports) are mission records, not derived output documents. A docmeta skip decision on these files does not authorize skipping any harness protocol step.

Owner request:

```
$ARGUMENTS
```
