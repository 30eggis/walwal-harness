---
description: Add a requirement under the active goal.
argument-hint: "<additional requirement>"
---

# /submission

Route the Owner request to the installed `harness-ceo` agent/skill as an additional requirement under the active goal.

Codex adapter:
- If Codex does not auto-load `harness-ceo`, manually read `.codex/skills/harness-ceo/SKILL.md` and follow it.
- Absence of `.codex/agents/` is not a failure. `.codex/skills/**/SKILL.md` is the Codex runtime protocol.
- Prefer a genuinely separate CQO session (Claude Agent, Codex sub-agent, or `codex exec`) from implementation. Reading another role skill in the same session is only a role switch, not independent verification. If separate execution is unavailable, record `Verification Session: same-session` and disclose the limitation to Owner; the completion gate warns but permits it.

At intake, classify and record `tier` (S/M/L) using the CEO Mission Tier criteria; record the rationale in `ceo.md`. Preserve the highest historical tier when requirements change.

Required flow:
1. Locate the active goal document root under `.harness/documents/{goal_name}/`. If no active goal exists, CEO must create/select the best matching goal record from available mission context or mark the submission blocked with the recommended default; do not ask the Owner an open-ended setup question.
2. If another child mission under the goal is active, update its `mission-state.json` to `closed`, `cancelled`, or `superseded` with `active:false` before starting this submission.
3. Create a submission record under `.harness/documents/{goal_name}/submission-{submission_index}-{submission_name}/`.
4. Write `.harness/documents/{goal_name}/submission-{submission_index}-{submission_name}/mission-state.json` with `{"lifecycle":"active","active":true,"tier":"S"}` (replace S with the classified tier).
5. Record CEO decisions in `.harness/documents/{goal_name}/submission-{submission_index}-{submission_name}/ceo.md`.
6. CEO routes only to the CXX agents needed for this additional requirement. CEO must not ask the Owner which CXX or worker path to choose.
7. CXX roles must start in a fresh session context. Do not let the default model impersonate a missing CXX or worker.
8. At effective tier M/L, and for COO/CDO/OPS at every tier, delegate specialist execution to hired workers. At S, CTO implements directly and CQO directly runs verification in a separate session; no CTO/CQO hiring is needed.
9. If a required worker is missing, the responsible CXX must invoke the installed `harness-hiring` skill before assigning the work.
10. CXX must manage conventions for new requirements. Durable changes in behavior, architecture, UI, process, or policy must be reflected in `.harness/conventions/` when accepted.
11. For roles requiring workers, CEO must require a Worker Evidence Manifest and worker report paths under `.harness/documents/{goal_name}/submission-{submission_index}-{submission_name}/{owning-cxx}/workers/` before accepting CXX completion.
12. For acceptance, leave the mission active and run `bash scripts/harness-company-complete.sh . <reason> <mission-rel>` as the final action; the script checks evidence before writing `complete` and `active:false`. On refusal, keep working. For termination without acceptance, first write lifecycle `cancelled`, `superseded`, or `closed` and `active:false`, then call the same explicit transition. `closed` means ended without acceptance; disclose “미수락 종료” in the Owner report and never archive without PASS. For an external-authority block, record `blocked`/`active:false` and run `bash scripts/harness-company-block.sh . "<exact missing authority>"`. `<mission-rel>` is the path relative to `.harness/documents/`.
13. Do not invoke internal roles through slash commands; commands are Owner entrypoints only.
14. Do not ask the Owner whether to continue, hire workers, choose internal options, or start the next step. If CEO cannot decide alone, convene the relevant CXX agents and decide from their written recommendations. CEO may approve reversible routine operations such as local cron/launchd/wake automation, dashboard refresh, monitoring cadence, Telegram briefing format using existing credentials, and mission consolidation/supersede cleanup. Stop only for external authority such as new credentials/secrets, payment approval, legal/business acceptance, unavailable production access, destructive data action, or direct conflict with stated Owner direction.

Lessons before plan: read relevant shared/role conventions and gotchas before edits, measurements, or briefs. At effective tier S/M, role documents may replace Lessons Preflight + Lessons Tally with `## Lessons` containing `Preflight: <applicable items and why>` (before work) and `Fired: <items or 0 fired>` (at completion). `## Implementation Notes` may contain concise bullets. At L, retain Lessons Preflight, Lessons Tally, and all four Implementation Notes subsections. All worker reports retain the full seeded format at every tier. **Worker brief:** name the seeded report path and instruct the worker to fill its existing sections incrementally. Do not copy the report skeleton, Tally, or Notes block into the brief. Continue to pass relevant corpus links and copy behavioral requirements absent from the seed (including the browser-automation clause) verbatim.

Note: `/submission` is not a new company goal and not an emergency fix. It is an additional requirement while pursuing the active goal. It belongs under that goal in history.

Submission request:

```
$ARGUMENTS
```
