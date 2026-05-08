#!/bin/bash
# harness-progress-migrate.sh — Idempotent progress.json normalizer.
#
# 목적: 새 스키마 필드를 누락하지 않도록 SessionStart 마다 안전하게 채운다.
# 항상 jq 의 alternative operator(`//`) 또는 `if has` 패턴으로 작성하여
# 기존 값을 절대 덮어쓰지 않는다.
#
# Usage (sourced):
#   source "$SCRIPT_DIR/lib/harness-progress-migrate.sh"
#   migrate_progress_schema "$PROGRESS"
#
# Usage (standalone):
#   bash scripts/lib/harness-progress-migrate.sh /path/to/.harness/progress.json

migrate_progress_schema() {
  local progress="$1"
  [ -f "$progress" ] || return 0
  command -v jq >/dev/null 2>&1 || return 0

  # v6.2 — Parallel tracks (fork-join) fields. tracks.length >= 2 → fork.
  # Note: there is intentionally NO `meetings.decision.mode` field — single/parallel is derived
  # from tracks.length. Runtime progress.mode is preserved because it still governs solo/team/paused.
  local filter='
    .conductor.tracks           = (.conductor.tracks // [])
    | .conductor.rendezvous       = (.conductor.rendezvous // null)
    | .conductor.fork_meeting_id  = (.conductor.fork_meeting_id // null)

    | .meetings                   = (.meetings // {})
    | .meetings.requested_tracks  = (.meetings.requested_tracks // [])
    | .meetings.requested_rendezvous = (.meetings.requested_rendezvous // null)
    | .meetings.fork_meeting_id   = (.meetings.fork_meeting_id // null)

    | .meetings.decision          = (.meetings.decision // {})
    | .meetings.decision.tracks   = (.meetings.decision.tracks // [])
    | .meetings.decision.rendezvous = (.meetings.decision.rendezvous // null)
    | del(.meetings.decision.mode)
    | del(.meetings.requested_mode)
  '

  local tmp
  tmp="$(mktemp)" || return 1
  if jq "$filter" "$progress" > "$tmp" 2>/dev/null; then
    mv "$tmp" "$progress"
  else
    rm -f "$tmp"
    return 1
  fi
}

# Standalone invocation
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  target="${1:-}"
  if [ -z "$target" ]; then
    echo "usage: $0 <path/to/.harness/progress.json>" >&2
    exit 2
  fi
  migrate_progress_schema "$target"
fi
