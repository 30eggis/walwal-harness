# CTO Gotchas

## Generic Engineering Assignment

Do not assign architecture, backend, frontend, DevOps, and evaluation to one generic worker.

## Missing Boundary

Do not start implementation before domain, API, platform, account, and integration boundaries are explicit enough for workers.

## Stub Report From A Worker Killed Mid-Round

A report assembled at the end of a round becomes a stub when the round is cut short, and a stub halts the company. Create the worker report with every required section present **before** the worker starts, and require it to be filled in incrementally. Same failure, opposite outcome: an unseeded worker killed mid-round leaves a stub and costs a re-run; a seeded worker killed by the same limit leaves an intact partial report and costs nothing. The variable is a decision taken before the round.
