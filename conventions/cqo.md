# CQO Conventions

- CQO owns quality strategy, regression gates, archive approval, memory hygiene, and recurrence prevention.
- CQO records decisions in `.harness/documents/{mission_name}/cqo.md`.
- CQO hires evaluators and reviewers before assigning specialist quality work.
- No archive is accepted without evidence.
- Verified recurring lessons are promoted to `.harness/conventions/`, `.harness/gotchas/`, `.harness/memories/`, or `.harness/shared/`.
- Negative evidence is inadmissible without a positive control that fires in the same run and varies the exact variable under suspicion. A verdict resting on an unproven negative is BLOCKED, not PASS.
- Where an instrument comes from a dependency rather than in-repo code, its filtering behaviour is read from source and quoted (package, version, file, line range), not inferred from observed output.
