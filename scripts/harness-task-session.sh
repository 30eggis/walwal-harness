#!/bin/bash
# harness-task-session.sh — create per-agent task session document
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/harness-render-progress.sh"

PROJECT_ROOT="$(resolve_harness_root "${1:-.}")" || exit 1
AGENT="${2:-}"
SOURCE="${3:-}"

[ -n "$AGENT" ] || exit 2
command -v jq >/dev/null 2>&1 || exit 1

PROGRESS="$PROJECT_ROOT/.harness/progress.json"
TASK_ROOT="$PROJECT_ROOT/.harness/actions/task-sessions/$AGENT"
mkdir -p "$TASK_ROOT"

dispatch_id=$(jq -r '.dispatch.id // "D-000"' "$PROGRESS")
sprint_num=$(jq -r '.sprint.number // 0' "$PROGRESS")
ts=$(date -u +%Y%m%dT%H%M%SZ)
session_id="${AGENT}-S$(printf '%03d' "$sprint_num")-${ts}"
session_path="$TASK_ROOT/${session_id}.md"

cat > "$session_path" <<EOF
# Task Session — $session_id

- agent: $AGENT
- dispatch: $dispatch_id
- sprint: $sprint_num
- source: ${SOURCE:-none}
- created_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)

## Allowed Inputs
- .harness/handoff.json
- .harness/progress.json
- assigned evidence documents only

## Rule
- 이전 대화 기억이 아니라 문서와 evidence만 근거로 판단할 것
- 사실과 추론을 분리해서 기록할 것
EOF

bash "$SCRIPT_DIR/harness-progress-set.sh" "$PROJECT_ROOT" \
  ".task_sessions.current = {\"agent\":\"$AGENT\",\"id\":\"$session_id\",\"path\":\"${session_path#$PROJECT_ROOT/}\",\"source\":$(jq -Rn --arg v "${SOURCE:-}" '$v')} |
   .task_sessions.history = ((.task_sessions.history // []) + [{\"agent\":\"$AGENT\",\"id\":\"$session_id\",\"path\":\"${session_path#$PROJECT_ROOT/}\",\"source\":$(jq -Rn --arg v "${SOURCE:-}" '$v')}])" >/dev/null

echo "${session_path#$PROJECT_ROOT/}"
