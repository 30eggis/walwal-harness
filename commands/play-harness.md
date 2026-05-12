---
description: Run the harness play build and notify OPS monitoring.
argument-hint: "[additional play args]"
---

# /play-harness

Run the target project's harness play mode.

Required flow:
1. Confirm `.harness/` exists in the current project.
2. Run `bash scripts/play.sh $ARGUMENTS`.
3. Treat play mode and release mode as mutually exclusive. If release mode is active, stop it first with `/stop-harness` or report the conflict to the Owner.
4. After the script returns, read the emitted OPS report path and notify the installed `harness-ops` skill/agent that play monitoring has started.
5. Record the build result in `.harness/documents/{mission_name}/ops.md` when a mission is active.
6. Do not route this through `/goal`; this command is an Owner-facing runtime control entrypoint.

Play arguments:

```
$ARGUMENTS
```
