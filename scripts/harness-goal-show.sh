#!/usr/bin/env bash
# harness-goal-show.sh — 현재 active GOAL + 적합도 요약 출력
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROGRESS="$ROOT/.harness/progress.json"
GOAL_FILE="$ROOT/.harness/actions/goals.md"

if [ ! -f "$PROGRESS" ]; then
  echo "progress.json 없음. bash init.sh 먼저 실행." >&2; exit 1
fi

ACTIVE_ID=$(jq -r '.goals.active_id // ""' "$PROGRESS")
ADHERENCE=$(jq -r '.goals.current_adherence // "n/a"' "$PROGRESS")

if [ -z "$ACTIVE_ID" ]; then
  echo "Active GOAL 없음. CEO(Dispatcher)가 첫 발화에서 발급."
  echo "  bash scripts/harness-goal-init.sh \"<title>\""
  exit 0
fi

echo "Active GOAL: $ACTIVE_ID"
echo "Adherence:   $ADHERENCE"
echo ""

# progress.json 의 GOAL 메타 출력
jq -r --arg id "$ACTIVE_ID" '
  .goals.list[] | select(.id == $id) |
  "title:           \(.title)",
  "status:          \(.status)",
  "owner_confirmed: \(.owner_confirmed)",
  "cto_feasibility: \(.cto_feasibility // "pending")",
  "created_at:      \(.created_at // "?")"
' "$PROGRESS"

echo ""
echo "본문: $GOAL_FILE 에서 ## $ACTIVE_ID 섹션 참조"
