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
