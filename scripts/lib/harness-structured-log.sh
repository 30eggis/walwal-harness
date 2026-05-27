#!/bin/bash
# Structured runtime helpers for events.jsonl and todos/state.json.

harness_json_escape() {
  jq -Rs . 2>/dev/null
}

harness_ensure_structured_runtime() {
  local project_root="${1:-.}"
  local harness_dir="$project_root/.harness"
  [ -d "$harness_dir" ] || return 0
  mkdir -p "$harness_dir/todos"
  [ -f "$harness_dir/events.jsonl" ] || : > "$harness_dir/events.jsonl"
  [ -f "$harness_dir/todos/events.jsonl" ] || : > "$harness_dir/todos/events.jsonl"
  if [ ! -f "$harness_dir/todos/state.json" ]; then
    jq -n --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{
      version: 1,
      updated_at: $now,
      owners: {ceo: [], coo: [], cdo: [], cto: [], cqo: [], ops: []}
    }' > "$harness_dir/todos/state.json"
  fi
}

harness_emit_event() {
  local project_root="$1"
  local event_json="$2"
  harness_ensure_structured_runtime "$project_root"
  local path="$project_root/.harness/events.jsonl"
  jq -c --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
    . + {ts: (.ts // $now)}
  ' <<<"$event_json" >> "$path" 2>/dev/null || true
}

harness_todo_upsert() {
  local project_root="$1"
  local todo_json="$2"
  harness_ensure_structured_runtime "$project_root"
  local state="$project_root/.harness/todos/state.json"
  local events="$project_root/.harness/todos/events.jsonl"
  local tmp="$state.tmp.$$"
  local now
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  jq -c --arg now "$now" '. + {ts: (.ts // $now), type: (.type // "todo_upsert")}' <<<"$todo_json" >> "$events" 2>/dev/null || true
  if jq --argjson todo "$todo_json" --arg now "$now" '
    .version = (.version // 1) |
    .updated_at = $now |
    .owners = (.owners // {ceo: [], coo: [], cdo: [], cto: [], cqo: [], ops: []}) |
    ($todo.owner // "ceo") as $owner |
    .owners[$owner] = (.owners[$owner] // []) |
    .owners[$owner] = ((.owners[$owner] | map(select(.id != $todo.id))) + [
      ($todo + {updated_at: ($todo.updated_at // $now), created_at: ($todo.created_at // $now)})
    ] | sort_by(-(.priority // 0), .created_at))
  ' "$state" > "$tmp" 2>/dev/null; then
    mv "$tmp" "$state"
  else
    rm -f "$tmp"
  fi
}
