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

PROJECT_ROOT="$(resolve_harness_root "${1:-.}")" || exit 0
PROGRESS="$PROJECT_ROOT/.harness/progress.json"
CONFIG="$PROJECT_ROOT/.harness/config.json"
FEATURES="$PROJECT_ROOT/.harness/actions/feature-list.json"
QUEUE="$PROJECT_ROOT/.harness/actions/feature-queue.json"
WORKER_DIR="$PROJECT_ROOT/.harness/actions/workers"
LOG_DIR="$PROJECT_ROOT/.harness/ops/workers"

[ -f "$PROGRESS" ] || exit 0
[ -f "$CONFIG" ] || exit 0
[ -f "$FEATURES" ] || exit 0
[ -x "$SCRIPT_DIR/harness-queue-manager.sh" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

mkdir -p "$WORKER_DIR" "$LOG_DIR"

spawn_mode="$(jq -r '.company_mode.worker_spawn // "claude"' "$CONFIG" 2>/dev/null || echo claude)"
pipeline="$(jq -r '.pipeline // "FULLSTACK"' "$PROGRESS" 2>/dev/null || echo FULLSTACK)"
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
stamp="$(date -u +%Y%m%dT%H%M%SZ)"

agent_for_feature() {
  local fid="$1"
  local layer service title
  layer="$(jq -r --arg id "$fid" '.features[]? | select(.id == $id) | (.layer // .type // "")' "$FEATURES" 2>/dev/null | head -1)"
  service="$(jq -r --arg id "$fid" '.features[]? | select(.id == $id) | (.service // "")' "$FEATURES" 2>/dev/null | head -1)"
  title="$(jq -r --arg id "$fid" '.features[]? | select(.id == $id) | (.title // .name // .description // "")' "$FEATURES" 2>/dev/null | head -1)"
  case "$(printf '%s %s %s' "$layer" "$service" "$title" | tr '[:upper:]' '[:lower:]')" in
    *frontend*|*ui*|*web*|*react*|*next*) echo "generator-frontend" ;;
    *design*|*token*|*component-spec*) echo "generator-designer" ;;
    *devops*|*infra*|*deploy*|*ci*) echo "generator-devops" ;;
    *)
      if [ "$pipeline" = "FE-ONLY" ]; then echo "generator-frontend"; else echo "generator-backend"; fi
      ;;
  esac
}

build_prompt() {
  local team="$1" fid="$2" agent="$3" prompt_path="$4" log_path="$5"
  cat > "$prompt_path" <<EOF
You are running as walwal-harness company worker.

Agent: harness-${agent}
Worker slot: ${team}
Feature ID: ${fid}
Project root: ${PROJECT_ROOT}

Follow these rules exactly:
1. Read AGENTS.md, CONVENTIONS.md if present, .harness/conventions/shared.md, .harness/conventions/${agent}.md if present, .harness/gotchas/${agent}.md if present, .harness/memory.md, .harness/progress.json, .harness/actions/feature-list.json, .harness/actions/api-contract.json, and the relevant harness skill for ${agent}.
2. Work only on FEATURE_ID=${fid}. Do not broaden scope.
3. Respect IA ownership and do not edit files outside your department.
4. Write a report to .harness/actions/gen-report-${fid}.md if you are a generator, or .harness/actions/evaluation-${fid}.md if you are an evaluator.
5. On success, update feature-list passes and run: bash scripts/harness-queue-manager.sh pass ${fid}
6. On failure, write the reason and run: bash scripts/harness-queue-manager.sh fail ${fid} "<short reason>"
7. Use partial progress updates only via scripts/harness-progress-set.sh.
8. Append real timestamped progress to .harness/progress.log. Never write future timestamps.

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
  active_workers="$(jq '[.teams | to_entries[] | select(.value.status == "busy") | {team:(.key|tonumber), feature:.value.feature, pid:.value.pid, phase:(.value.phase // "gen")}]' "$QUEUE" 2>/dev/null || echo "[]")"
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
  agent="$(agent_for_feature "$fid")"
  prompt_rel=".harness/actions/workers/T${team}-${fid}-${stamp}.prompt.md"
  log_rel=".harness/ops/workers/T${team}-${fid}-${stamp}.log"
  prompt_path="$PROJECT_ROOT/$prompt_rel"
  log_path="$PROJECT_ROOT/$log_rel"

  build_prompt "$team" "$fid" "$agent" "$prompt_path" "$log_path"

  pid="null"
  status="recorded"
  if [ "$spawn_mode" = "claude" ] && command -v claude >/dev/null 2>&1; then
    (
      cd "$PROJECT_ROOT" || exit 1
      claude -p "$(cat "$prompt_path")" > "$log_path" 2>&1
    ) &
    pid="$!"
    status="spawned"
  fi

  tmpq="${QUEUE}.tmp.$$.$i"
  jq --arg tid "$team" --arg agent "$agent" --arg prompt "$prompt_rel" --arg log "$log_rel" --arg status "$status" --argjson pid "$pid" --arg ts "$ts" '
    .teams[$tid].pid = $pid |
    .teams[$tid].agent = $agent |
    .teams[$tid].prompt = $prompt |
    .teams[$tid].log = $log |
    .teams[$tid].spawn_status = $status |
    .teams[$tid].started_at = $ts |
    .queue.in_progress[.teams[$tid].feature].agent = $agent |
    .queue.in_progress[.teams[$tid].feature].prompt = $prompt |
    .queue.in_progress[.teams[$tid].feature].log = $log |
    .queue.in_progress[.teams[$tid].feature].pid = $pid
  ' "$QUEUE" > "$tmpq" && mv "$tmpq" "$QUEUE"

  jq -n --argjson team "$team" --arg feature "$fid" --arg agent "$agent" --arg prompt "$prompt_rel" --arg log "$log_rel" --arg status "$status" --argjson pid "$pid" \
    '{team:$team, feature:$feature, agent:$agent, prompt:$prompt, log:$log, status:$status, pid:$pid}' >> "$dispatches_file"
  echo "$ts | conductor | worker-dispatch | $status | T${team}/${fid} | $agent pid=$pid" >> "$PROJECT_ROOT/.harness/progress.log"
  i=$((i + 1))
done

dispatches="$(jq -s '.' "$dispatches_file")"
rm -f "$dispatches_file"
active_workers="$(jq '[.teams | to_entries[] | select(.value.status == "busy") | {team:(.key|tonumber), feature:.value.feature, agent:.value.agent, pid:.value.pid, phase:(.value.phase // "gen"), prompt:.value.prompt, log:.value.log, spawn_status:.value.spawn_status}]' "$QUEUE")"

jq --arg ts "$ts" --argjson dispatches "$dispatches" --argjson workers "$active_workers" '
  .company_state.active_workers = ($workers | length) |
  .company_state.workers = $workers |
  .company_state.last_dispatch_at = $ts |
  .company_state.last_dispatch = $dispatches |
  .conductor.worker_dispatches = ((.conductor.worker_dispatches // []) + $dispatches)
' "$PROGRESS" > "${PROGRESS}.tmp" && mv "${PROGRESS}.tmp" "$PROGRESS"

echo "$dispatches"
