# Gotchas

Bundled v7 gotcha templates copied into target projects during `walwal-harness init`.

Only company-level roles are provided by default:

- `shared.md`
- `ceo.md`
- `coo.md`
- `cdo.md`
- `cto.md`
- `cqo.md`
- `ops.md`
- `hiring.md`
- `resource-manager.md`
- `brick-office.md`

Topic-specific gotcha files may use descriptive names such as `i18n-locale-hotfix.md`.

CXX files such as `cto.md` and `cqo.md` act as lazy-loading indexes. Add links there when a topic file applies to that CXX.

**Declare the audience.** Every gotcha names each role that must be able to *find* it — `<!-- roles: cto, cqo -->` at the top of a topic file, or `- **Roles**: cto, cqo` inside an index entry — and is linked from each of those roles' index files, not only its author's. Lazy loading is a promise about reachability: an entry filed only under its author is indexed but invisible to the readers it names. Verify with `bash scripts/harness-corpus-reachability.sh . text` (`--fix` adds the missing links). Entries in `shared.md` need no cross-linking; every role reads it.
