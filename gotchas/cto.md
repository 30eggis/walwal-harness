# CTO Gotchas

## Generic Engineering Assignment

Do not assign architecture, backend, frontend, DevOps, and evaluation to one generic worker.

## Missing Boundary

Do not start implementation before domain, API, platform, account, and integration boundaries are explicit enough for workers.

## Stub Report From A Worker Killed Mid-Round

A report assembled at the end of a round becomes a stub when the round is cut short, and a stub halts the company. Create the worker report with every required section present **before** the worker starts, and require it to be filled in incrementally. Same failure, opposite outcome: an unseeded worker killed mid-round leaves a stub and costs a re-run; a seeded worker killed by the same limit leaves an intact partial report and costs nothing. The variable is a decision taken before the round.

## Complete Against A Spec Version, Never In The Abstract
<!-- roles: cto, cqo -->

A category marked complete records *what it was complete against*. A spec moved `v0.7 → v0.9`, changing a response contract, while the category built against `v0.7` sat marked done — two later revisions landed silently and nothing in the harness recorded which version the work had been for.

The symptom was not an error. A lookup key stopped matching, and three map overlays were dropped as `null`: no exception, no log, just an absence. Pin version **and content hash** with `scripts/harness-spec-pin.sh` before implementation, and re-verify before completion and archive.
