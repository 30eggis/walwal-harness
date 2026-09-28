---
description: Set, revise, or extend a company mission goal.
argument-hint: "<goal request>"
---

# /goal

Route the Owner request to the installed `harness-ceo` agent/skill.

Codex adapter:
- If Codex does not auto-load `harness-ceo`, manually read `.codex/skills/harness-ceo/SKILL.md` and follow it.
- Absence of `.codex/agents/` is not a failure. `.codex/skills/**/SKILL.md` is the Codex runtime protocol.
- Prefer a genuinely separate CQO session (Claude Agent, Codex sub-agent, or `codex exec`) from implementation. Reading another role skill in the same session is only a role switch, not independent verification. If separate execution is unavailable, record `Verification Session: same-session` and disclose the limitation to Owner; the completion gate warns but permits it.

At intake, classify and record `tier` (S/M/L) using the CEO Mission Tier criteria; record the rationale in `ceo.md`. Preserve the highest historical tier when requirements change.

Required flow:
1. Create or update a goal under `.harness/documents/goal-{goal_index}-{goal_name}/`.
2. Classify the goal, then write `.harness/documents/goal-{goal_index}-{goal_name}/mission-state.json` before routing CXX:
   - **Finite** goal (build/add/fix something with a definite done state) → `{"lifecycle":"active","active":true,"tier":"S"}` (replace S with the classified tier).
   - **Operating/perpetual** goal (operate/monitor/keep growing/지속·영구 운영, e.g. "run a trading bot and keep it profitable forever") → `{"lifecycle":"operating","active":true,"tier":"L"}`. An operating goal NEVER completes: drive it as the agenda-driven standing loop in the CEO skill ("Operating (Perpetual) Goals"), and never run `harness-company-complete.sh` for it. It ends only on explicit Owner stop or a true external-authority block.
3. Record CEO decisions in `.harness/documents/goal-{goal_index}-{goal_name}/ceo.md`.
4. CEO decides whether brainstorming is needed or whether CXX questions can be issued immediately. CEO must not ask the Owner which path to take.
5. CEO routes only to the CXX needed for this goal and its effective tier.
6. CXX roles must start in a fresh session context. Do not let the default model impersonate a missing worker.
7. At effective tier M/L, and for COO/CDO/OPS at every tier, delegate specialist execution to hired workers. At S, CTO implements directly and CQO directly runs verification in a separate session; no CTO/CQO hiring is needed.
8. If a required CXX or worker skill is missing, CEO must invoke the installed `harness-hiring` skill before assigning the work.
9. For roles requiring workers, CEO must require a Worker Evidence Manifest and worker report paths under `.harness/documents/goal-{goal_index}-{goal_name}/{owning-cxx}/workers/` before accepting CXX completion.
10. For acceptance, leave the mission active and run `bash scripts/harness-company-complete.sh . <reason> <mission-rel>` as the final action; the script checks evidence before writing `complete` and `active:false`. On refusal, keep working. For termination without acceptance, first write lifecycle `cancelled`, `superseded`, or `closed` and `active:false`, then call the same explicit transition. `closed` means ended without acceptance; disclose “미수락 종료” in the Owner report and never archive without PASS. For an external-authority block, record `blocked`/`active:false` and run `bash scripts/harness-company-block.sh . "<exact missing authority>"`. `<mission-rel>` is the path relative to `.harness/documents/`.
11. Do not invoke internal roles through slash commands; commands are Owner entrypoints only.
12. Do not ask the Owner whether to continue, hire workers, choose internal options, or start the next step. If CEO cannot decide alone, convene the relevant CXX agents and decide from their written recommendations. CEO may approve reversible routine operations such as local cron/launchd/wake automation, dashboard refresh, monitoring cadence, Telegram briefing format using existing credentials, and mission consolidation/supersede cleanup. Stop only for external authority such as new credentials/secrets, payment approval, legal/business acceptance, unavailable production access, destructive data action, or direct conflict with stated Owner direction.

Lessons before plan: read relevant shared/role conventions and gotchas before edits, measurements, or briefs. At effective tier S/M, role documents may replace Lessons Preflight + Lessons Tally with `## Lessons` containing `Preflight: <applicable items and why>` (before work) and `Fired: <items or 0 fired>` (at completion). `## Implementation Notes` may contain concise bullets. At L, retain Lessons Preflight, Lessons Tally, and all four Implementation Notes subsections. All worker reports retain the full seeded format at every tier. **Worker brief:** name the seeded report path and instruct the worker to fill its existing sections incrementally. Do not copy the report skeleton, Tally, or Notes block into the brief. Continue to pass relevant corpus links and copy behavioral requirements absent from the seed (including the browser-automation clause) verbatim.

Note: A goal is the company's objective. Submissions and hot-fixes that happen while pursuing it should be recorded under that goal directory.

Harness documents (ceo.md, cto.md, cqo.md, worker reports) are mission records, not derived output documents. A docmeta skip decision on these files does not authorize skipping any harness protocol step.

Owner request:

```
$ARGUMENTS
```
