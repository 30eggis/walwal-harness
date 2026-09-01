# Shared Gotchas

## Default Engine Impersonation

Do not let a missing CXX or specialist silently run as the default AI engine. Hire first.

## Command Misuse

Do not add internal slash commands for CXX or workers. Commands are Owner entrypoints only.

## Runtime State In Package Repo

Do not create or commit project runtime `.harness/` state in this package repository.

## Written, Indexed, And Still Too Late

A lesson that is written, indexed, and reachable still costs a mission if it is read *after* the mistake. The corpus is rarely the problem; the ordering is. Read `conventions/` and `gotchas/` **before** the first edit, the first measurement, and the first brief — then write the plan.

Do not answer this with a distilled checklist file. A derived corpus must be re-synced whenever any source file changes, goes stale silently, and becomes a second thing nobody reads before planning.

## Silent Worker Is A Rate Limit

A worker terminated by a usage limit is indistinguishable, from the outside, from a worker that finished. A silent or truncated round is a rate limit until proven otherwise — check the limit and its reset time before re-briefing, re-hiring, or rewriting the task. This is why every spawn must declare its model: without a declared model there is nothing to check the limit against.

## Heading Readers That Filter By Content

A reader anchored on `^#` misses the same heading written as `> ## …`, which is exactly how in-place retractions, verdict continuations, and standing rules get posted. Match `^>?\s*#{1,6}` and return every hit with no content filter. A filter that catches half a verdict is worse than one that catches none, because it reports success.

## Rules Stated One Layer Above The Executing Layer

A requirement placed on a CXX that its workers must also satisfy does not reach the workers unless it is inserted **verbatim** into the worker brief. A rule stated one layer above the layer that executes it does not apply, and the layer below cannot infer a rule it was never given.

## The Author Files Under Itself
<!-- roles: ceo, coo, cdo, cto, cqo, ops -->

The recurring way an indexed entry becomes unreachable: whoever wrote it filed it under their own role index and nowhere else. Registration *feels* complete — the entry exists, it is indexed, it is linked. It is just not where its declared readers are told to look.

Measured on a live corpus: 69 items, **10 unreachable role-routings, 7 of them invisible to a role the entry itself named**. The clearest case was an entry whose own text called two others "the same family" — both siblings were already reachable from the index it was missing from. An inconsistency, not a decision.

Declare the audience at registration and let `scripts/harness-corpus-reachability.sh` link it. Reading is not reaching.

## A Conclusion Not Written Is Not Held
<!-- roles: ceo, coo, cdo, cto, cqo, ops -->

A conclusion a session holds but has not written into its role document and the runtime state file is not held by the company. Reconcile before reporting; strike and correct in place, never delete.

The cheap version: a deliverable table that contradicts three messages already sent, and a line still requesting work a peer has already delivered. The expensive version was measured — a required step completed, reported, and accepted, that never reached the state file, so the orchestration loop went on trying to spawn the finished step **70 times**. "Write your conclusions down" reads as tidiness until it reads as seventy.
