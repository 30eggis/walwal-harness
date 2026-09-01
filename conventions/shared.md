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

## Declared Audience

Every convention and gotcha declares which roles must be able to **find** it, and is linked from each of those roles' index files.

- Topic file: `<!-- roles: cto, cqo -->` near the top.
- Entry inside an index file: `- **Roles**: cto, cqo`.
- Registration is complete only when `bash scripts/harness-corpus-reachability.sh . text` passes. `--fix` adds the missing links.

Lazy loading tells a reader to consult `{shared, own-role}` and nothing else. That is a **promise about reachability**: where the promise is not kept, the rule stops narrowing the search and starts hiding the entry. An agent following the reading rule exactly will never see an item filed only under someone else's index.

## Section-Scoped Reading

Any reader that scans a role document, worker report, or mission record for sections — a script, a hook, an agent following a protocol — matches:

```
^>?\s*#{1,6}
```

and returns **every** hit. Blockquoted or plain, at any depth, with **no content filter of any kind**.

- **Do not filter headings by what they appear to say.** A filter encodes the reader's guess about which headings matter, and a document is free to put anything in a heading: verdicts, in-place retractions, standing rules, continuation lines.
- A verdict-token filter and a retraction-marker filter, measured against real CXX documents, caught 3/11 and 4/11 blockquoted headings; their union still missed 4 — including the second line of a verdict, whose first line was caught. **A filter that catches half a verdict is worse than one that catches none, because it reports success.**
- A reader anchored on `^#` reads a claim and never reaches the in-place retraction posted below it as `> ## …`. That is worse than missing a section: it returns superseded content as current.
- **The reader that decides what is important before reading is the failure.**

## DDD

- Keep domain, application, interface, and infrastructure decisions distinct.
- CXX agents define responsibility boundaries before assigning workers.
