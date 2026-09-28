---
description: Start an urgent fix under the active goal.
argument-hint: "<incident or fix request>"
---

# /hot-fix

Route the Owner request to the installed `harness-ceo` agent/skill as an emergency mission under the active goal.

Codex adapter:
- If Codex does not auto-load `harness-ceo`, manually read `.codex/skills/harness-ceo/SKILL.md` and follow it.
- Absence of `.codex/agents/` is not a failure. `.codex/skills/**/SKILL.md` is the Codex runtime protocol.
- Prefer a genuinely separate CQO session (Claude Agent, Codex sub-agent, or `codex exec`) from implementation. Reading another role skill in the same session is only a role switch, not independent verification. If separate execution is unavailable, record `Verification Session: same-session` and disclose the limitation to Owner; the completion gate warns but permits it.

At intake, classify and record `tier` (S/M/L) using the CEO Mission Tier criteria; record the rationale in `ceo.md`. Preserve the highest historical tier when requirements change.

Required flow:
1. Locate the active goal document root under `.harness/documents/{goal_name}/`. If no active goal exists, CEO must create/select one before proceeding.
2. If another child mission under the goal is active, update its `mission-state.json` to `closed`, `cancelled`, or `superseded` with `active:false` before starting the hot-fix.
3. Create `.harness/documents/{goal_name}/hotfix-{hotfix_index}-{hotfix_name}/ceo.md`.
4. Write `.harness/documents/{goal_name}/hotfix-{hotfix_index}-{hotfix_name}/mission-state.json` with `{"lifecycle":"active","active":true,"tier":"S"}` (replace S with the classified tier).
5. CEO summons CTO and CQO first; summon COO/CDO only when planning or UX decisions are involved. CEO must not ask the Owner whether to start the fix or which internal path to choose.
6. CTO applies the smallest correct patch directly at S, or through hired implementation skills at M/L.
7. CXX roles must start in a fresh session context. Do not let the default model impersonate a missing CXX or worker.
8. At effective tier M/L, and for COO/CDO deliverables at every tier, delegate specialist execution to hired workers. At S, CTO implements directly and CQO directly runs verification in a separate session; no CTO/CQO hiring is needed. At S/M, OPS observes directly. CQO starts only after CTO's CQO Handoff — never in parallel. A CXX writes a document only when summoned; a summoned COO/CDO/OPS with no work writes only `## Not Applicable` and one reason.
9. If a required worker is missing, CEO or the responsible CXX must invoke the installed `harness-hiring` skill before assigning the work.
10. For roles requiring workers, CEO must require a Worker Evidence Manifest and worker report paths under `.harness/documents/{goal_name}/hotfix-{hotfix_index}-{hotfix_name}/{owning-cxx}/workers/` before accepting CXX completion.
11. At S/M, CQO registers a lesson when recurrence is plausible or the cause is non-obvious; otherwise write `none — <reason>` in cqo.md Recurrence Notes. L retains mandatory lesson registration.
12. For acceptance, leave the mission active and run `bash scripts/harness-company-complete.sh . <reason> <mission-rel>` as the final action; the script checks evidence before writing `complete` and `active:false`. On refusal, keep working. For termination without acceptance, first write lifecycle `cancelled`, `superseded`, or `closed` and `active:false`, then call the same explicit transition. `closed` means ended without acceptance; disclose “미수락 종료” in the Owner report and never archive without PASS. For an external-authority block, record `blocked`/`active:false` and run `bash scripts/harness-company-block.sh . "<exact missing authority>"`. `<mission-rel>` is the path relative to `.harness/documents/`.
13. Do not invoke internal roles through slash commands; commands are Owner entrypoints only.
14. Do not ask the Owner whether to continue, hire workers, choose internal options, or start the next step. If CEO cannot decide alone, convene the relevant CXX agents and decide from their written recommendations. CEO may approve reversible routine operations such as local cron/launchd/wake automation, dashboard refresh, monitoring cadence, Telegram briefing format using existing credentials, and mission consolidation/supersede cleanup. Stop only for external authority such as new credentials/secrets, payment approval, legal/business acceptance, unavailable production access, destructive data action, or direct conflict with stated Owner direction.

Lessons before plan: read relevant shared/role conventions and gotchas before edits, measurements, or briefs. At effective tier S/M, role documents may replace Lessons Preflight + Lessons Tally with `## Lessons` containing `Preflight: <applicable items and why>` (before work) and `Fired: <items or 0 fired>` (at completion). `## Implementation Notes` may contain concise bullets. At L, retain Lessons Preflight, Lessons Tally, and all four Implementation Notes subsections. All worker reports retain the full seeded format at every tier. **Worker brief:** name the seeded report path and instruct the worker to fill its existing sections incrementally. Do not copy the report skeleton, Tally, or Notes block into the brief. Continue to pass relevant corpus links and copy behavioral requirements absent from the seed (including the browser-automation clause) verbatim.

Scale the read to the fix. A four-line patch pays the index files plus only the topic links that match the fix — not the whole corpus. The ordering constraint holds at every size; the depth does not.

Note: `/hot-fix` is a problem-fix flow while pursuing the active goal. It belongs under that goal in history.

Harness documents (ceo.md, cto.md, cqo.md, worker reports) are mission records, not derived output documents. A docmeta skip decision on these files does not authorize skipping any harness protocol step.

Hot-fix request:

```
$ARGUMENTS
```
