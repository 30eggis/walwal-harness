---
docmeta:
  id: AGENTS
  title: Project Context for AI Agents (walwal-harness)
  type: input
  createdAt: 2026-04-09T00:00:00Z
  updatedAt: 2026-05-12T00:00:00Z
  source:
    producer: user
  tags: [project-context, v7.1, harness, npm-package, claude, codex]
---

# AGENTS.md — walwal-harness v7.1 (Package Repository)

This repository **installs the harness**. It is not a project that runs the harness.

Do not create `.harness/` here. Do not treat this as a runtime project.

---

## 1. Package Identity

- **Package**: `@walwal-harness/cli`
- **Version**: v7.1
- **Purpose**: Install company-mode AI agent harness into external projects
- **Runtime target**: Projects where the user runs `walwal-harness init`

---

## 2. Before You Modify

Don't assume. State what you are changing and why.

- Minimum change that achieves the install contract. No speculative additions.
- Match existing code style. Don't clean up adjacent code.
- After any change to `bin/init.js` or scripts: verify before considering done.

**Verify:**
```bash
node --check bin/init.js
node --check scripts/import-agency-agents.js
npm pack --dry-run --cache /private/tmp/walwal-npm-cache
```

**Init test:**
```bash
mkdir -p /private/tmp/walwal-v7-init-test
node ./bin/init.js init --force --project-root /private/tmp/walwal-v7-init-test
```

**Expected after init:**
- `.claude/commands/goal.md` and `hot-fix.md` — no other commands
- `.claude/skills/harness-{ceo,coo,cdo,cto,cqo,ops}/SKILL.md`
- `.harness/shared/HR-Resource/`
- `CLAUDE.md` is a symlink → `AGENTS.md`

---

## 3. Install Contract

`bin/init.js` performs exactly these steps in the target project:

1. Create `.harness/` runtime directories
2. Copy `HR-Resource/` → `.harness/shared/HR-Resource/`
3. Install `/goal` and `/hot-fix` in `.claude/commands/` and `.codex/commands/` only
4. Install CXX skills in `.claude/skills/` and `.codex/skills/`
5. Remove invalid CXX slash commands (`/ceo`, `/cto`, `/cqo`, etc.) if present
6. Install runtime scripts and hooks
7. Write `AGENTS.md` from `assets/templates/AGENTS.md.template` and create `CLAUDE.md → AGENTS.md` symlink

`postinstall` does **not** auto-initialize. Only explicit `walwal-harness init` runs init.

---

## 4. IA-MAP

```
/
├── bin/init.js                        # CLI entry — walwal-harness init
├── commands/
│   ├── goal.md                        # Owner command (installed to target)
│   └── hot-fix.md                     # Owner command (installed to target)
├── HR-Resource/{skill-name}/SKILL.md  # Hireable worker pool
├── scripts/
│   ├── import-agency-agents.js        # agency-agents → HR-Resource converter
│   └── *.sh                           # Runtime scripts installed by init
├── assets/templates/
│   └── AGENTS.md.template             # Target project CLAUDE.md/AGENTS.md source
├── conventions/                       # Bundled convention templates
├── gotchas/                           # Bundled gotcha templates
└── package.json
```

---

## 5. Company Structure (v7.1)

Target projects run in company mode after init:

```
Owner
  └─ /goal or /hot-fix
      └─ harness-ceo
          ├─ harness-coo
          ├─ harness-cdo
          ├─ harness-cto
          ├─ harness-cqo
          └─ harness-ops
```

Support skills: `harness-hiring`, `harness-resource-manager`, `harness-brick-office`

---

## 6. Command Rule

Exactly two Owner-facing commands. This rule does not flex:

| Command | Role |
|---|---|
| `/goal` | Mission intake |
| `/hot-fix` | Emergency fix |

Never add `/ceo`, `/cto`, `/cqo`, `/ops`, `/hiring`, or any CXX as a command.

---

## 7. HR-Resource

Hireable worker pool for CXX agents.

- Source: `HR-Resource/{skill-name}/SKILL.md`
- Installed to: `.harness/shared/HR-Resource/` in target project
- Conversion: `scripts/import-agency-agents.js` (agency-agents format → HR-Resource format)

---

## 8. Editing Rules

- Do not modify `AGENTS.md` without Owner request or explicit approval.
- Do not create `.harness/` or commit runtime state to this repository.
- HR-Resource conversion uses `scripts/import-agency-agents.js` only.
- Do not revert user-made changes unless explicitly instructed.
- The 2-command rule does not change without Owner approval.
