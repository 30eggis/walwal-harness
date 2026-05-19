# Shared Conventions

## V7 Runtime Boundary

- This package repository must not contain project runtime `.harness/` state.
- `walwal-harness init` creates `.harness/` in the target project.
- `.claude/commands` and `.codex/commands` contain only `/goal`, `/submission`, and `/hot-fix`.
- CXX and worker execution uses installed agents/skills, not slash commands.

## Hiring Boundary

- A missing specialist must not be replaced by a generic default AI engine.
- Use `harness-resource-manager` to find already hired workers.
- Use `harness-hiring` to hire from `.harness/shared/HR-Resource/`.
- Record hired workers in `.harness/shared/hr-roster.json`.
- CXX agents do not complete specialist work directly, even for small tasks.
- Research, planning, design, implementation, QA, ops checks, and documentation deliverables must be assigned to hired workers.
- CXX mission reports must cite worker names and report paths for accepted deliverables.

## Mission Documents

- Goal records live under `.harness/documents/goal-{index}-{name}/`.
- Submission and hot-fix records live below the active goal directory.
- CXX decisions use `{cxx}.md`.
- Worker reports use `{owning-cxx}/workers/{worker-name}.md`.

## DDD

- Keep domain, application, interface, and infrastructure decisions distinct.
- CXX agents define responsibility boundaries before assigning workers.
