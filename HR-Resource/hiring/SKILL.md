---
name: harness-hiring
description: "HR hiring. Searches .harness/shared/HR-Resource candidates, installs selected worker skills into .claude and .codex, and records roster wiring."
model: sonnet
disable-model-invocation: false
---

# Hiring

Hire workers from `.harness/shared/HR-Resource/`.

## Required Inputs

- requester
- needed capability
- mission name
- blocking status
- owning CXX (`cto`, `cqo`, `coo`, `cdo`, or `ops`)

## Workflow

1. Reject any request from CEO to hire or brief a specialist worker directly. Tell CEO to route through the owning CXX.
2. Search `.harness/shared/HR-Resource/*/SKILL.md`.
3. Select the smallest fitting worker.
4. Install it to `.claude/skills/{owning-cxx}/{name}/SKILL.md` and `.codex/skills/{owning-cxx}/{name}/SKILL.md`.
5. Update `.harness/shared/hr-roster.json` without deleting existing hired entries. Record `owner` as the owning CXX, `skillPath` as `.harness/shared/HR-Resource/{name}/SKILL.md`, and `skillPaths.claude` / `skillPaths.codex` as tool-specific hierarchical installed paths.
6. The owning CXX must write worker reports under `.harness/documents/{mission}/{owning-cxx}/workers/{name}.md`. Do not write flat `.harness/documents/{mission}/workers/{name}.md` except when migrating legacy missions.
7. Ask the `harness-resource-manager` skill to update trigger wording.
8. Return worker name, owner, source skill path, installed paths, mission report path, invocation wording, related convention/gotcha links supplied by the owning CXX, and the mandatory report appendix below.

## Worker Rule Links

Every hired worker receives the owning CXX's relevant convention/gotcha links in the worker brief. Workers read those linked topic files only when they match the assigned task.

## Mandatory Worker Report Appendix

Every hired worker must append this English section to the bottom of its existing report:

```
## Implementation Notes

### Design Decisions
- ...

### Deviations
- ...

### Tradeoffs
- ...

### Open Questions
- ...
```

The appendix must summarize risks, self-corrections, and chosen direction. Use `None` when a subsection has no entries.

Never mark a missing worker as available.
