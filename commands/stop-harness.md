---
description: Stop any harness play or release process/session.
argument-hint: "[optional stop reason]"
---

# /stop-harness

Stop any active harness play or release runtime.

Required flow:
1. Confirm `.harness/` exists in the current project.
2. Run `bash scripts/harness-runtime-stop.sh $ARGUMENTS`.
3. Verify both play and release runtime state files are cleared or marked stopped.
4. Notify the installed `harness-ops` skill/agent that monitoring should stop for the terminated runtime mode.
5. Record the stop result in `.harness/documents/{mission_name}/ops.md` when a mission is active.

Stop reason:

```
$ARGUMENTS
```
