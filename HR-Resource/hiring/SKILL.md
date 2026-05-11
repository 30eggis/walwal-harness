---
name: harness-hiring
description: "HR hiring. Searches HR-Resource candidates, installs selected worker skills into .claude and .codex, and records roster wiring."
model: sonnet
disable-model-invocation: false
---

# Hiring

Hire workers from `HR-Resource/`.

## Required Inputs

- requester
- needed capability
- mission name
- blocking status

## Workflow

1. Search `HR-Resource/*/SKILL.md`.
2. Select the smallest fitting worker.
3. Install it to `.claude/skills/{name}/SKILL.md` and `.codex/skills/{name}/SKILL.md`.
4. Update `.harness/shared/hr-roster.json`.
5. Ask `/resource-manager` to update trigger wording.
6. Return worker name, skill path, and invocation wording.

Never mark a missing worker as available.
