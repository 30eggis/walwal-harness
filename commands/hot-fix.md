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
2. If another child mission under the goal is active, update its `mission-state.json` to `closed`, `cancelled`, or `superseded` with `active:false` before starting the hot-fix.
3. Create `.harness/documents/{goal_name}/hotfix-{hotfix_index}-{hotfix_name}/ceo.md`.
4. Write `.harness/documents/{goal_name}/hotfix-{hotfix_index}-{hotfix_name}/mission-state.json` with `{"lifecycle":"active","active":true}`.
5. CEO summons CTO and CQO first; summon COO/CDO only when planning or UX decisions are involved. CEO must not ask the Owner whether to start the fix or which internal path to choose.
6. CTO applies the smallest correct patch path through hired implementation skills.
7. CXX roles must start in a fresh session context. Do not let the default model impersonate a missing CXX or worker.
8. CXX roles must not directly execute specialist deliverables. They must use hired workers for implementation, QA, ops checks, and documentation even when the fix is small.
9. If a required worker is missing, CEO or the responsible CXX must invoke the installed `harness-hiring` skill before assigning the work.
10. CEO must require a Worker Evidence Manifest and worker report paths under `.harness/documents/{goal_name}/hotfix-{hotfix_index}-{hotfix_name}/{owning-cxx}/workers/` before accepting CXX completion.
11. CQO must register durable lessons in `.harness/gotchas/`, `.harness/conventions/`, or `.harness/memories/`. This step is mandatory, not optional, even for small fixes.
12. Archive only after CQO has accepted the fix, then update `mission-state.json` to `complete` with `active:false`.
13. Do not invoke internal roles through slash commands; commands are Owner entrypoints only.
14. Do not ask the Owner whether to continue, hire workers, choose internal options, or start the next step. If CEO cannot decide alone, convene the relevant CXX agents and decide from their written recommendations. Stop only for external authority such as credentials/secrets, payment approval, legal/business acceptance, unavailable production access, destructive data action, or direct conflict with stated Owner direction.

Note: `/hot-fix` is a problem-fix flow while pursuing the active goal. It belongs under that goal in history.

Harness documents (ceo.md, cto.md, cqo.md, worker reports) are mission records, not derived output documents. A docmeta skip decision on these files does not authorize skipping any harness protocol step.

Hot-fix request:

```
$ARGUMENTS
```
