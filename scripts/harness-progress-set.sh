#!/bin/bash
# harness-progress-set.sh — Safe partial update to .harness/progress.json
#
# Usage:
#   bash scripts/harness-progress-set.sh <project-root> <jq_filter>
#
# The jq filter is a partial assignment expression. All other fields are
# preserved. NEVER rewrite progress.json as a full JSON blob — mode,
# team_state, and similar top-level fields will be lost.
#
# Example:
#   bash scripts/harness-progress-set.sh . '.current_agent = "planner" | .agent_status = "running"'

set -uo pipefail

PROJECT_ROOT="${1:-.}"
FILTER="${2:-}"

if [ -z "$FILTER" ]; then
  echo "[progress-set] usage: $0 <project-root> <jq_filter>" >&2
  exit 2
fi

PROGRESS="$PROJECT_ROOT/.harness/progress.json"

if [ ! -f "$PROGRESS" ]; then
  echo "[progress-set] not found: $PROGRESS" >&2
  exit 1
fi

# Always add .updated_at = now so callers don't forget
FINAL_FILTER="$FILTER | .updated_at = (now | todate)"

TMP="${PROGRESS}.tmp.$$"
if jq "$FINAL_FILTER" "$PROGRESS" > "$TMP" 2>/dev/null; then
  mv "$TMP" "$PROGRESS"
else
  rm -f "$TMP"
  echo "[progress-set] jq filter failed: $FILTER" >&2
  exit 1
fi
