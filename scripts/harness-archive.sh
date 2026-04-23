#!/bin/bash
# harness-archive.sh — 스프린트 종료 시 자동 아카이빙
#
# 동작:
#   1. .harness/actions/ 의 스프린트 산출물을 .harness/archive/D-NNN/S-NNN/ 로 이동
#   2. progress.json 의 sprint 상태를 초기화 (신규 dispatch 준비)
#   3. dispatch.id 가 없으면 counter++ 로 새 dispatch 시작
#
# 유지되는 파일 (이동하지 않음):
#   - .harness/gotchas/**, .harness/conventions/**, .harness/ref/**
#   - .harness/config.json, .harness/memory.md
#   - .harness/progress.json (초기화만)
#
# 호출 주체: harness-next.sh (next_agent="archive" 도달 시 자동)

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/harness-render-progress.sh" 2>/dev/null || true

PROJECT_ROOT="${1:-.}"
PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd)"

PROGRESS="$PROJECT_ROOT/.harness/progress.json"
ACTIONS_DIR="$PROJECT_ROOT/.harness/actions"
ARCHIVE_ROOT="$PROJECT_ROOT/.harness/archive"

if [ ! -f "$PROGRESS" ]; then
  echo "[archive] ERROR: progress.json not found" >&2
  exit 1
fi

command -v jq >/dev/null 2>&1 || { echo "[archive] ERROR: jq required" >&2; exit 1; }

# ── Read current dispatch/sprint numbers ──
dispatch_counter=$(jq -r '.dispatch.counter // 0' "$PROGRESS")
dispatch_id=$(jq -r '.dispatch.id // empty' "$PROGRESS")
sprint_num=$(jq -r '.sprint.number // 0' "$PROGRESS")

# Ensure dispatch id exists (fallback for legacy progress.json without dispatch)
if [ -z "$dispatch_id" ] || [ "$dispatch_id" = "null" ]; then
  if [ "$dispatch_counter" -lt 1 ]; then
    dispatch_counter=1
  fi
  dispatch_id=$(printf 'D-%03d' "$dispatch_counter")
fi

sprint_id=$(printf 'S-%03d' "$sprint_num")
target_dir="$ARCHIVE_ROOT/$dispatch_id/$sprint_id"

echo ""
echo "  ── Archive ────────────────────────────"
echo "  Dispatch : $dispatch_id"
echo "  Sprint   : $sprint_id"
echo "  Target   : ${target_dir#$PROJECT_ROOT/}"

# ── Move actions/ contents into archive ──
if [ -d "$ACTIONS_DIR" ] && [ "$(ls -A "$ACTIONS_DIR" 2>/dev/null)" ]; then
  mkdir -p "$target_dir"
  moved=0
  for f in "$ACTIONS_DIR"/*; do
    [ -e "$f" ] || continue
    name="$(basename "$f")"
    if [ -e "$target_dir/$name" ]; then
      # Collision — suffix with timestamp to avoid overwrite
      ts=$(date +%Y%m%d-%H%M%S)
      mv "$f" "$target_dir/${name%.}.${ts}"
    else
      mv "$f" "$target_dir/"
    fi
    moved=$((moved + 1))
  done
  echo "  Moved    : $moved file(s)"
else
  echo "  Moved    : 0 file(s) (actions/ empty)"
fi

# ── Reset progress.json for next dispatch ──
# - sprint → init
# - agents → cleared
# - artifacts → pending
# - dispatch.id cleared (next dispatcher run will allocate new D-NNN)
# - failure → cleared
jq --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
  .pipeline = null
  | .dispatch.id = null
  | .sprint = { number: 0, status: "init", retry_count: 0 }
  | .current_agent = null
  | .agent_status = "pending"
  | .completed_agents = []
  | .next_agent = "dispatcher"
  | .failure = { agent: null, location: null, message: null, retry_target: null }
  | (.artifacts // {}) as $a
  | .artifacts = ($a | with_entries(
      if (.value | type) == "object"
      then .value = { status: "pending", updated_by: null, updated_at: null }
      else .
      end))
  | .updated_at = $now
' "$PROGRESS" > "${PROGRESS}.tmp" && mv "${PROGRESS}.tmp" "$PROGRESS"

# ── Clear handoff so next session starts fresh ──
HANDOFF="$PROJECT_ROOT/.harness/handoff.json"
echo '{}' > "$HANDOFF"

echo "  Status   : archived, progress reset"
echo ""
echo "  ✓ 다음 요청은 새로운 dispatch 로 시작합니다."
echo ""
