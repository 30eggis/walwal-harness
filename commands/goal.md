---
description: Set, revise, or extend a company mission goal.
argument-hint: "<goal request>"
---

# /goal

Route the Owner request to the installed `harness-ceo` agent/skill.

Codex adapter:
- If Codex does not auto-load `harness-ceo`, manually read `.codex/skills/harness-ceo/SKILL.md` and follow it.
- Absence of `.codex/agents/` is not a failure. `.codex/skills/**/SKILL.md` is the Codex runtime protocol.
- For CXX "fresh session context", use role-scoped context: read the CXX skill, active mission files, and required conventions/gotchas before writing that role's `{cxx}.md`.

Required flow:
1. Create or update a goal under `.harness/documents/goal-{goal_index}-{goal_name}/`.
2. Write `.harness/documents/goal-{goal_index}-{goal_name}/mission-state.json` with `{"lifecycle":"active","active":true}` before routing CXX.
3. Record CEO decisions in `.harness/documents/goal-{goal_index}-{goal_name}/ceo.md`.
4. CEO decides whether brainstorming is needed or whether CXX questions can be issued immediately. CEO must not ask the Owner which path to take.
5. CEO asks COO, CDO, CTO, and CQO only the questions needed for this goal.
6. CXX roles must start in a fresh session context. Do not let the default model impersonate a missing worker.
7. CXX roles must not directly execute specialist deliverables. They must use hired workers for research, planning, design, implementation, QA, ops checks, and documentation.
8. If a required CXX or worker skill is missing, CEO must invoke the installed `harness-hiring` skill before assigning the work.
9. CEO must require a Worker Evidence Manifest and worker report paths under `.harness/documents/goal-{goal_index}-{goal_name}/{owning-cxx}/workers/` before accepting CXX completion.
10. When the goal is accepted, cancelled, superseded, blocked, or closed, update `mission-state.json` to `complete`, `cancelled`, `superseded`, `blocked`, or `closed` and set `active:false`.
11. Do not invoke internal roles through slash commands; commands are Owner entrypoints only.
12. Do not ask the Owner whether to continue, hire workers, choose internal options, or start the next step. If CEO cannot decide alone, convene the relevant CXX agents and decide from their written recommendations. CEO may approve reversible routine operations such as local cron/launchd/wake automation, dashboard refresh, monitoring cadence, Telegram briefing format using existing credentials, and mission consolidation/supersede cleanup. Stop only for external authority such as new credentials/secrets, payment approval, legal/business acceptance, unavailable production access, destructive data action, or direct conflict with stated Owner direction.

Note: A goal is the company's objective. Submissions and hot-fixes that happen while pursuing it should be recorded under that goal directory.

Harness documents (ceo.md, cto.md, cqo.md, worker reports) are mission records, not derived output documents. A docmeta skip decision on these files does not authorize skipping any harness protocol step.

Owner request:

```
$ARGUMENTS
```
