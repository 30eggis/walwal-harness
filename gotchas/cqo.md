# CQO Gotchas

## Archive Without Evidence

Do not approve archive based on narrative confidence. Require concrete quality evidence.

## Unpromoted Recurrence

Do not leave repeated failures only in chat or mission notes. Promote verified recurrence prevention to conventions, gotchas, memories, or shared state.

## Negative Evidence Without A Positive Control

"No error was logged", "no stubbed 2xx was served", "no leak was detected" are claims about the instrument, not about the system, until a positive control fires in the same run and varies the exact variable under suspicion. Do not accept a clean negative result whose instrument was never shown to be able to see the failure.

## Null Instrument Supplied By A Dependency

An instrument's filtering behaviour is read from source and quoted — package, version, file, line range — never inferred from observed output. A log filter that lives in a dependency is invisible to every in-repo search, so its absence from the project's own code proves nothing. When an instrument turns out to have been structurally null, re-open the affected claims **by their shape** — every claim of that form, not only the one that happened to be noticed.

## Audit Questions That Offer Alternatives

An audit question that offers alternatives asserts that the alternatives are exhaustive. "Is it a skip rule **or** a status-conditional format?" cannot return "neither, it is upstream" — both branches locate the rule inside our own code, so the true answer is unreachable from the question's grammar. When an audit stalls, re-ask the question without the menu.

## A Range Is The Two Least Representative Points
<!-- roles: cqo, ops -->

Publish a summary statistic **with its `n`**, and characterise a spiky series by **percentiles, never min–max**. A range reports the two most extreme observations in the set and reads as a finding; on a spiky series it is almost always noise wearing the shape of a result.

## Cross-role Links

Entries written under another role that name CQO as an audience.

- [Complete Against A Spec Version, Never In The Abstract](./cto.md) — verify `spec-pins.json` before PASS and before archive.
