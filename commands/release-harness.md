---
description: Run the harness release build, start service operation, and notify OPS monitoring.
argument-hint: "[additional release args]"
---

# /release-harness

Run the target project's harness release mode and begin service operation.

Required flow:
1. Confirm `.harness/` exists in the current project.
2. Run `bash scripts/release.sh release $ARGUMENTS`.
3. Treat play mode and release mode as mutually exclusive. If play mode is active, stop it first with `/stop-harness` or report the conflict to the Owner.
4. After the script returns, read the emitted OPS report path and notify the installed `harness-ops` skill/agent that release monitoring has started.
5. Record the release result in `.harness/documents/{mission_name}/ops.md` when a mission is active.
6. Do not route this through `/goal`; this command is an Owner-facing runtime control entrypoint.

Release arguments:

```
$ARGUMENTS
```
