#!/bin/bash
# harness-worker-dispatch.sh — connect feature queue to actual worker launches
#
# Deterministic responsibilities:
#   1. auto-dispatch ready features to idle worker slots
#   2. create per-worker prompt + log paths
#   3. optionally launch `claude -p` workers in background
#   4. write progress.json.company_state so dashboards/CLI show real activity

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/harness-render-progress.sh"
source "$SCRIPT_DIR/lib/harness-agent-resolver.sh"

PROJECT_ROOT="$(resolve_harness_root "${1:-.}")" || exit 0
PROGRESS="$PROJECT_ROOT/.harness/progress.json"
CONFIG="$PROJECT_ROOT/.harness/config.json"
FEATURES="$PROJECT_ROOT/.harness/actions/feature-list.json"
QUEUE="$PROJECT_ROOT/.harness/actions/feature-queue.json"
WORKER_DIR="$PROJECT_ROOT/.harness/actions/workers"
LOG_DIR="$PROJECT_ROOT/.harness/ops/workers"
DISPATCH_LOCK="$PROJECT_ROOT/.harness/.worker-dispatch-lock"
DISPATCH_LOCK_STALE_SEC="${DISPATCH_LOCK_STALE_SEC:-900}"

[ -f "$PROGRESS" ] || exit 0
[ -f "$CONFIG" ] || exit 0
[ -f "$FEATURES" ] || exit 0
[ -x "$SCRIPT_DIR/harness-queue-manager.sh" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

mkdir -p "$WORKER_DIR" "$LOG_DIR"

acquire_dispatch_lock() {
  if mkdir "$DISPATCH_LOCK" 2>/dev/null; then
    printf '%s\n' "$$" > "$DISPATCH_LOCK/pid"
    printf '%s\n' "$(date +%s)" > "$DISPATCH_LOCK/created_at"
    trap 'rm -rf "$DISPATCH_LOCK" 2>/dev/null || true' EXIT INT TERM
    return 0
  fi

  local now created age holder
  now="$(date +%s)"
  created="$(cat "$DISPATCH_LOCK/created_at" 2>/dev/null || echo "$now")"
  holder="$(cat "$DISPATCH_LOCK/pid" 2>/dev/null || echo unknown)"
  age=$((now - created))
  if [ "$age" -ge "$DISPATCH_LOCK_STALE_SEC" ]; then
    rm -rf "$DISPATCH_LOCK" 2>/dev/null || true
    if mkdir "$DISPATCH_LOCK" 2>/dev/null; then
      printf '%s\n' "$$" > "$DISPATCH_LOCK/pid"
      printf '%s\n' "$now" > "$DISPATCH_LOCK/created_at"
      trap 'rm -rf "$DISPATCH_LOCK" 2>/dev/null || true' EXIT INT TERM
      return 0
    fi
  fi

  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | conductor | worker-dispatch | skipped-locked | holder=${holder} age=${age}s" >> "$PROJECT_ROOT/.harness/progress.log"
  echo "[]"
  exit 0
}

acquire_dispatch_lock

spawn_mode="$(jq -r '.company_mode.worker_spawn // "claude"' "$CONFIG" 2>/dev/null || echo claude)"

# AGENTS.md Hard Rule 21 — every worker spawn declares its model explicitly.
# Never inherit the CLI default: a worker terminated by a usage limit looks
# exactly like a worker that finished, and without a declared model there is
# nothing to check the limit against. Falls back to the phase model from
# flow.team, then to opus.
resolve_worker_model() {
  local phase="$1" model
  model="$(jq -r --arg p "$phase" '
    .company_mode.worker_model
    // (if $p == "eval" then .flow.team.eval_model else .flow.team.gen_model end)
    // empty' "$CONFIG" 2>/dev/null || true)"
  [ -n "$model" ] && [ "$model" != "null" ] || model="opus"
  printf '%s' "$model"
}

pipeline="$(jq -r '.pipeline // "FULLSTACK"' "$PROGRESS" 2>/dev/null || echo FULLSTACK)"
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
stamp="$(date -u +%Y%m%dT%H%M%SZ)"

build_prompt() {
  local team="$1" fid="$2" agent="$3" prompt_path="$4" log_path="$5" model="${6:-}"
  cat > "$prompt_path" <<EOF
You are running as walwal-harness company worker.

Agent: harness-${agent}
Worker slot: ${team}
Feature ID: ${fid}
Project root: ${PROJECT_ROOT}
Declared model: ${model:-unspecified}

Follow these rules exactly:
1. Lessons before plan. FIRST — before any source edit and before any measurement — read AGENTS.md, CONVENTIONS.md if present, .harness/conventions/shared.md, .harness/conventions/${agent}.md if present, .harness/gotchas/shared.md, .harness/gotchas/${agent}.md if present, .harness/memory.md, .harness/progress.json, .harness/actions/feature-list.json, .harness/actions/api-contract.json, and the relevant harness skill for ${agent}. Then write down which convention/gotcha items apply to FEATURE_ID=${fid} and why, and only then start work.
2. Work only on FEATURE_ID=${fid}. Do not broaden scope.
3. Respect IA ownership and do not edit files outside your department.
4. Write a report to .harness/actions/gen-report-${fid}.md if you are a generator, or .harness/actions/evaluation-${fid}.md if you are an evaluator.
5. On success, update feature-list passes and run: bash scripts/harness-queue-manager.sh pass ${fid}
6. On failure, write the reason and run: bash scripts/harness-queue-manager.sh fail ${fid} "<short reason>"
7. Use partial progress updates only via scripts/harness-progress-set.sh.
8. Append real timestamped progress to .harness/progress.log. Never write future timestamps.
9. End the report with a one-line tally naming which of the convention/gotcha items from step 1 actually fired. \`0 fired\` is a valid tally and must be stated, not omitted.
10. Write the report incrementally as the work happens — create the file with its sections present up front and fill them in. If this session is killed mid-round, the report must still be a valid partial report, never a stub.

This worker log is: ${log_path#$PROJECT_ROOT/}
EOF
}

if [ ! -f "$QUEUE" ]; then
  bash "$SCRIPT_DIR/harness-queue-manager.sh" init all "$PROJECT_ROOT" >/dev/null 2>&1 || exit 0
else
  bash "$SCRIPT_DIR/harness-queue-manager.sh" recover "$PROJECT_ROOT" >/dev/null 2>&1 || true
fi

pairs="$(bash "$SCRIPT_DIR/harness-queue-manager.sh" auto-dispatch "$PROJECT_ROOT" 2>/dev/null || echo "[]")"
if ! jq -e 'type == "array"' >/dev/null 2>&1 <<<"$pairs"; then
  pairs="[]"
fi

count="$(jq 'length' <<<"$pairs")"
if [ "$count" -eq 0 ]; then
  active_workers="$(jq '[.teams | to_entries[] | select(.value.status == "busy") | {team:(.key|tonumber), feature:.value.feature, pid:.value.pid, tmux_session:.value.tmux_session, phase:(.value.phase // "gen")}]' "$QUEUE" 2>/dev/null || echo "[]")"
  jq --arg ts "$ts" --argjson workers "$active_workers" '
    .company_state.active_workers = ($workers | length) |
    .company_state.workers = $workers |
    .company_state.last_dispatch_at = (.company_state.last_dispatch_at // null)
  ' "$PROGRESS" > "${PROGRESS}.tmp" && mv "${PROGRESS}.tmp" "$PROGRESS"
  echo "[]"
  exit 0
fi

dispatches_file="$(mktemp)"
: > "$dispatches_file"

i=0
while [ "$i" -lt "$count" ]; do
  team="$(jq -r ".[$i].team" <<<"$pairs")"
  fid="$(jq -r ".[$i].feature" <<<"$pairs")"
  phase="$(jq -r --arg fid "$fid" '.queue.in_progress[$fid].phase // "gen"' "$QUEUE" 2>/dev/null || echo gen)"
  agent="$(resolve_feature_agent "$PROJECT_ROOT" "$fid" "$phase" "$pipeline" 2>/dev/null || true)"
  prompt_rel=".harness/actions/workers/T${team}-${fid}-${stamp}.prompt.md"
  log_rel=".harness/ops/workers/T${team}-${fid}-${stamp}.log"
  prompt_path="$PROJECT_ROOT/$prompt_rel"
  log_path="$PROJECT_ROOT/$log_rel"

  if [ -z "$agent" ]; then
    reason="agent_resolution_failed phase=${phase}"
    bash "$SCRIPT_DIR/harness-queue-manager.sh" fail "$fid" "$PROJECT_ROOT" >/dev/null 2>&1 || true
    printf '%s\n' "$reason" > "$log_path"
    jq -n --argjson team "$team" --arg feature "$fid" --arg phase "$phase" --arg status "blocked" --arg reason "$reason" \
      '{team:$team, feature:$feature, phase:$phase, agent:null, prompt:null, log:null, status:$status, reason:$reason, pid:null}' >> "$dispatches_file"
    echo "$ts | conductor | worker-dispatch | blocked | T${team}/${fid} | ${reason}" >> "$PROJECT_ROOT/.harness/progress.log"
    i=$((i + 1))
    continue
  fi

  worker_model="$(resolve_worker_model "$phase")"
  build_prompt "$team" "$fid" "$agent" "$prompt_path" "$log_path" "$worker_model"

  pid="null"
  tmux_session="null"
  status="recorded"
  if [ "$spawn_mode" = "tmux" ] && command -v tmux >/dev/null 2>&1 && command -v claude >/dev/null 2>&1; then
    session_safe="$(basename "$PROJECT_ROOT" | tr -c '[:alnum:]_' '_')"
    session_name="walwal_${session_safe}_w${team}_${stamp}"
    if tmux new-session -d -s "$session_name" "cd '$PROJECT_ROOT' && claude --dangerously-skip-permissions --model '$worker_model' -p \"\$(cat '$prompt_path')\" > '$log_path' 2>&1"; then
      pane_pid="$(tmux list-panes -t "$session_name" -F '#{pane_pid}' 2>/dev/null | head -n1)"
      if [ -n "$pane_pid" ]; then
        pid="$pane_pid"
      fi
      tmux_session="\"$session_name\""
      status="spawned-tmux"
    else
      status="recorded tmux-spawn-failed"
    fi
  elif [ "$spawn_mode" = "tmux" ] && command -v claude >/dev/null 2>&1; then
    # tmux requested but unavailable: fall back to background claude spawn
    (
      cd "$PROJECT_ROOT" || exit 1
      claude --dangerously-skip-permissions --model "$worker_model" -p "$(cat "$prompt_path")" > "$log_path" 2>&1
    ) &
    pid="$!"
    status="spawned tmux-fallback-claude"
  elif [ "$spawn_mode" = "claude" ] && command -v claude >/dev/null 2>&1; then
    (
      cd "$PROJECT_ROOT" || exit 1
      claude --dangerously-skip-permissions --model "$worker_model" -p "$(cat "$prompt_path")" > "$log_path" 2>&1
    ) &
    pid="$!"
    status="spawned"
  fi

  tmpq="${QUEUE}.tmp.$$.$i"
  jq --arg tid "$team" --arg agent "$agent" --arg phase "$phase" --arg prompt "$prompt_rel" --arg log "$log_rel" --arg status "$status" --argjson pid "$pid" --argjson tmux_session "$tmux_session" --arg ts "$ts" --arg model "$worker_model" '
    .teams[$tid].pid = $pid |
    .teams[$tid].model = $model |
    .teams[$tid].tmux_session = $tmux_session |
    .teams[$tid].agent = $agent |
    .teams[$tid].phase = $phase |
    .teams[$tid].prompt = $prompt |
    .teams[$tid].log = $log |
    .teams[$tid].spawn_status = $status |
    .teams[$tid].started_at = $ts |
    .queue.in_progress[.teams[$tid].feature].agent = $agent |
    .queue.in_progress[.teams[$tid].feature].model = $model |
    .queue.in_progress[.teams[$tid].feature].phase = $phase |
    .queue.in_progress[.teams[$tid].feature].prompt = $prompt |
    .queue.in_progress[.teams[$tid].feature].log = $log |
    .queue.in_progress[.teams[$tid].feature].pid = $pid |
    .queue.in_progress[.teams[$tid].feature].tmux_session = $tmux_session
  ' "$QUEUE" > "$tmpq" && mv "$tmpq" "$QUEUE"

  jq -n --argjson team "$team" --arg feature "$fid" --arg agent "$agent" --arg phase "$phase" --arg prompt "$prompt_rel" --arg log "$log_rel" --arg status "$status" --argjson pid "$pid" --argjson tmux_session "$tmux_session" --arg model "$worker_model" \
    '{team:$team, feature:$feature, agent:$agent, phase:$phase, model:$model, prompt:$prompt, log:$log, status:$status, pid:$pid, tmux_session:$tmux_session}' >> "$dispatches_file"
  echo "$ts | conductor | worker-dispatch | $status | T${team}/${fid} | $agent phase=$phase model=$worker_model pid=$pid" >> "$PROJECT_ROOT/.harness/progress.log"
  i=$((i + 1))
done

dispatches="$(jq -s '.' "$dispatches_file")"
rm -f "$dispatches_file"
active_workers="$(jq '[.teams | to_entries[] | select(.value.status == "busy") | {team:(.key|tonumber), feature:.value.feature, agent:.value.agent, model:.value.model, pid:.value.pid, tmux_session:.value.tmux_session, phase:(.value.phase // "gen"), prompt:.value.prompt, log:.value.log, spawn_status:.value.spawn_status}]' "$QUEUE")"

jq --arg ts "$ts" --argjson dispatches "$dispatches" --argjson workers "$active_workers" '
  .company_state.active_workers = ($workers | length) |
  .company_state.workers = $workers |
  .company_state.last_dispatch_at = $ts |
  .company_state.last_dispatch = $dispatches |
  .conductor.worker_dispatches = ((.conductor.worker_dispatches // []) + $dispatches)
' "$PROGRESS" > "${PROGRESS}.tmp" && mv "${PROGRESS}.tmp" "$PROGRESS"

echo "$dispatches"
