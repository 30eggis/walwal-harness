#!/bin/bash
# conductor-tick.sh — document-driven company-loop router
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/harness-render-progress.sh"

PROJECT_ROOT="$(resolve_harness_root "${1:-.}")" || exit 0
PROGRESS="$PROJECT_ROOT/.harness/progress.json"
CONFIG="$PROJECT_ROOT/.harness/config.json"
FEATURES="$PROJECT_ROOT/.harness/actions/feature-list.json"
QUEUE="$PROJECT_ROOT/.harness/actions/feature-queue.json"

[ -f "$PROGRESS" ] || exit 0
[ -f "$CONFIG" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

candidate="${HARNESS_CONDUCTOR_CANDIDATE:-}"
if [ -z "$candidate" ]; then
  candidate=$(jq -r '.next_agent // "null"' "$PROGRESS" 2>/dev/null || echo "null")
fi

current_agent=$(jq -r '.current_agent // "null"' "$PROGRESS")
agent_status=$(jq -r '.agent_status // "pending"' "$PROGRESS")
pipeline=$(jq -r '.pipeline // "null"' "$PROGRESS")
mode=$(jq -r '.mode // "company"' "$PROGRESS")

# v7 company mode: the CEO/CXX skills own the current_agent / next_agent /
# conductor.state transitions through the document-driven flow. conductor-tick
# has no current_agent="ceo" routing branch (its vocabulary is the legacy v6
# pipeline: dispatcher/planner/cto/cqo/service-ops/meeting-manager/...), so on a
# CEO state it would fall through and re-assert conductor.state="running" /
# next_agent="ceo" at the end, cementing the stuck runtime and clobbering any
# clean completion. Hand the turn back without touching state.
if [ "$current_agent" = "ceo" ]; then
  echo "ceo"
  exit 0
fi
# v6.2 — parallel tracks (fork-join) state
parallel_tracks=$(jq -c '.conductor.tracks // []' "$PROGRESS")
parallel_rendezvous=$(jq -c '.conductor.rendezvous // null' "$PROGRESS")
parallel_pending_count=$(jq -r '[ .conductor.tracks // [] | .[] | select(.status == "pending" or .status == "running") ] | length' "$PROGRESS")
requested_mode=$(jq -r '.service_ops.requested_mode // "null"' "$PROGRESS")
planner_requested_mode=$(jq -r '.planner.requested_mode // "null"' "$PROGRESS")
planner_last_brief=$(jq -r '.planner.last_brief // "null"' "$PROGRESS")
goal_adherence=$(jq -r '.goals.current_adherence // "null"' "$PROGRESS")
meetings_active_count=$(jq -r '(.meetings.active | length) // 0' "$PROGRESS")
pending_required_execution=$(jq -r 'if (.meetings.decision.required_execution // null) != null then "true" else "false" end' "$PROGRESS")
cqo_verdict=$(jq -r '.cqo.sprint_verdict // "pending"' "$PROGRESS")
ops_report=$(jq -r '.service_ops.auto_retro.last_report // "null"' "$PROGRESS")
cto_hotfixes=$(jq -r '.cto.open_hotfixes // 0' "$PROGRESS")
ops_recommendations=$(jq -r '.service_ops.auto_retro.open_recommendations // 0' "$PROGRESS")
ops_alerts=$(jq -r '.service_ops.monitor.alerts_this_sprint // 0' "$PROGRESS")
open_incidents=$(jq -r '(.service_ops.incident.open | length) // 0' "$PROGRESS")
workflow_stage=$(jq -r '.workflow.stage // "goal-intake"' "$PROGRESS")
meeting_type=$(jq -r '.meetings.requested_type // "null"' "$PROGRESS")
meeting_reason=$(jq -r '.meetings.requested_reason // "null"' "$PROGRESS")
cqo_regressions=$(jq -r '.cqo.open_regressions // 0' "$PROGRESS")
cqo_axes_below=$(jq -r '(.cqo.axes_below_threshold | length) // 0' "$PROGRESS")
plan_status=$(jq -r '.artifacts["plan.md"].status // "pending"' "$PROGRESS")
feature_status=$(jq -r '.artifacts["feature-list.json"].status // "pending"' "$PROGRESS")
api_status=$(jq -r '.artifacts["api-contract.json"].status // "pending"' "$PROGRESS")
service_ops_drift=$(jq -r '.service_ops.drift_classification // "null"' "$PROGRESS")

set_progress() {
  bash "$SCRIPT_DIR/harness-progress-set.sh" "$PROJECT_ROOT" "$1" >/dev/null
}

escape_json_string() {
  jq -Rn --arg v "$1" '$v'
}

normalize_company_mode() {
  if [ "$mode" != "company" ]; then
    set_progress '.mode = "company" |
      .mode_decision.owner = "conductor" |
      .mode_decision.policy = "always_company_parallel" |
      .mode_decision.user_override = null |
      .mode_decision.decided_at = (now | todate) |
      .mode_decision.rationale = "legacy mode normalized to always-on company mode"'
  fi
  echo "company"
}

infer_drift_classification() {
  if [ "$service_ops_drift" != "null" ] && [ -n "$service_ops_drift" ]; then
    echo "$service_ops_drift"
    return
  fi
  if [ "$cqo_verdict" = "FAIL" ] || [ "${cqo_regressions:-0}" -gt 0 ] || [ "${cqo_axes_below:-0}" -gt 0 ]; then
    echo "implementation_drift"
    return
  fi
  if [ "$requested_mode" = "incident" ] || [ "${open_incidents:-0}" -gt 0 ] || [ "${ops_alerts:-0}" -gt 0 ]; then
    echo "ops_drift"
    return
  fi
  if [ "$goal_adherence" != "null" ] && awk "BEGIN {exit !($goal_adherence < 0.7)}"; then
    if [ "$cqo_verdict" = "PASS" ] && [ "${open_incidents:-0}" -eq 0 ] && [ "${ops_alerts:-0}" -eq 0 ]; then
      echo "planning_drift"
    elif [ "$(jq -r '.goals.active_id // "null"' "$PROGRESS")" = "null" ]; then
      echo "goal_drift"
    else
      echo "goal_drift"
    fi
    return
  fi
  echo "unknown"
}

meeting_stage_for_owner() {
  case "$1" in
    planner) echo "coo-planning" ;;
    cto) echo "cto-review" ;;
    cqo) echo "quality-review" ;;
    service-ops) echo "ops-review" ;;
    dispatcher) echo "goal-intake" ;;
    *) echo "goal-intake" ;;
  esac
}

ensure_team_queue() {
  [ "$effective_mode" = "company" ] || return 0
  [ -f "$FEATURES" ] || return 0
  [ -x "$SCRIPT_DIR/harness-queue-manager.sh" ] || return 0

  if [ ! -f "$QUEUE" ]; then
    bash "$SCRIPT_DIR/harness-queue-manager.sh" init all "$PROJECT_ROOT" >/dev/null 2>&1 || true
  else
    bash "$SCRIPT_DIR/harness-queue-manager.sh" recover "$PROJECT_ROOT" >/dev/null 2>&1 || true
  fi
}

load_meeting_decision() {
  local decision
  if jq -e '(.meetings.decision.required_execution // null) != null' "$PROGRESS" >/dev/null 2>&1; then
    jq -c '.meetings.decision' "$PROGRESS"
    return 0
  fi
  decision=$(bash "$SCRIPT_DIR/harness-meeting-doc.sh" "$PROJECT_ROOT" read-decision 2>/dev/null || true)
  if [ -n "$decision" ]; then
    echo "$decision"
  else
    jq -c '.meetings.decision // {}' "$PROGRESS"
  fi
}

dispatch_company_workers() {
  [ "$effective_mode" = "company" ] || { echo "[]"; return 0; }
  [ -f "$FEATURES" ] || { echo "[]"; return 0; }
  [ -x "$SCRIPT_DIR/harness-worker-dispatch.sh" ] || { echo "[]"; return 0; }
  bash "$SCRIPT_DIR/harness-worker-dispatch.sh" "$PROJECT_ROOT" 2>/dev/null || echo "[]"
}

ensure_strategy_work_package() {
  local required_json="$1"
  local deliverable_path="$2"
  local target_path="$PROJECT_ROOT/$deliverable_path"
  local stamp
  stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  [ -n "$deliverable_path" ] && [ "$deliverable_path" != "null" ] || return 0
  mkdir -p "$(dirname "$target_path")"
  if [ ! -f "$target_path" ]; then
    {
      echo "# Strategy Cadence Recovery Work Package"
      echo ""
      echo "- created_at: $stamp"
      echo "- owner: Planner/COO"
      echo "- source_decision: $(jq -r '.source_path // "unknown"' <<<"$required_json")"
      echo "- required_execution_id: $(jq -r '.id // "unknown"' <<<"$required_json")"
      echo "- status: opened"
      echo ""
      echo "## Candidate Idea"
      echo ""
      echo "Planner/COO must define one concrete strategy candidate for this hour. A restatement of the goal is not sufficient."
      echo ""
      echo "## Data Source"
      echo ""
      echo "Name the market data source, lookback window, and any filters used by the candidate."
      echo ""
      echo "## Backtest Command"
      echo ""
      echo '```bash'
      echo "# Fill with the exact command that produces a backtest result artifact."
      echo '```'
      echo ""
      echo "## CQO Acceptance"
      echo ""
      echo "- PASS requires a generated candidate artifact and a backtest/evaluation artifact."
      echo "- If no candidate is generated before the next hourly review, classify the cycle as paperwork_only_failure."
    } > "$target_path"
  fi
}

effective_mode="$(normalize_company_mode)"
ensure_team_queue
drift_classification="$(infer_drift_classification)"

next="$candidate"
action="pass-through"
new_conductor_state="running"
new_workflow_stage="$workflow_stage"
meeting_filter=""
planner_filter=""
ops_filter=""
meeting_prepare=false

plan_artifacts_ready=false
if [ "$plan_status" != "pending" ] || [ "$feature_status" != "pending" ] || [ "$api_status" != "pending" ]; then
  plan_artifacts_ready=true
fi

first_generator="generator-backend"
if [ "$pipeline" = "FE-ONLY" ]; then
  first_generator="generator-frontend"
fi

if [ "$current_agent" = "dispatcher" ] && [ "$agent_status" = "completed" ]; then
  next="meeting-manager"
  action="convene:all-hands:goal-intake"
  new_conductor_state="waiting_meeting"
  new_workflow_stage="ceo-meeting"
  meeting_prepare=true
  meeting_filter="
    .meetings.active = [\"meeting-manager\"] |
    .meetings.requested_type = \"all-hands\" |
    .meetings.requested_reason = \"goal-intake\" |
    .meetings.decision = {
      \"owner\": \"planner\",
      \"action_type\": \"goal-alignment\",
      \"rationale\": \"CEO intake always starts with COO alignment.\",
      \"evidence\": [],
      \"drift_classification\": null,
      \"source_path\": null
    }"

elif [ "$meetings_active_count" -gt 0 ] && [ "$current_agent" != "meeting-manager" ]; then
  next="meeting-manager"
  action="spawn:meeting-manager:${meeting_type}"
  new_conductor_state="waiting_meeting"
  if [ "$meeting_type" = "followup-review" ]; then
    new_workflow_stage="followup-review"
    if [ "$current_agent" = "planner" ] && [ "$planner_requested_mode" = "hypothesis-verdict" ]; then
      planner_filter='.planner.requested_mode = null'
    fi
  fi

# v6.2 — Parallel tracks advance: if a track owner just completed, mark its track done
# and dispatch the next pending track. When all tracks completed, convene followup-review.
#
# Exclusion: for planner running a hypothesis chain (action_type=hypothesis-*), the track is
# only terminal when the chain ends with planner.last_brief="hypothesis:done". Intermediate
# planner ticks (research, verdict-prep, etc.) must defer to the dedicated planner-completed
# branch which routes the chain.
elif [ "$parallel_pending_count" -gt 0 ] && [ "$agent_status" = "completed" ] && \
     [ "$(jq --arg a "$current_agent" '[.[] | select(.owner == $a and (.status == "running" or .status == "pending"))] | length' <<<"$parallel_tracks")" -gt 0 ] && \
     ! { [ "$current_agent" = "planner" ] && \
         [ "$(jq --arg a "$current_agent" '[.[] | select(.owner == $a and (.status == "running" or .status == "pending")) | .action_type // ""] | first | startswith("hypothesis")' <<<"$parallel_tracks")" = "true" ] && \
         [ "$planner_last_brief" != "hypothesis:done" ]; }; then
  # mark the matching running/pending track as completed
  updated_tracks=$(jq -c --arg a "$current_agent" '
    [ .[] |
      if .owner == $a and (.status == "running" or .status == "pending") then
        . + { status: "completed", completed_at: (now | todate) }
      else . end
    ]
  ' <<<"$parallel_tracks")
  remaining=$(jq -r '[ .[] | select(.status == "pending" or .status == "running") ] | length' <<<"$updated_tracks")
  if [ "$remaining" -gt 0 ]; then
    # dispatch the next pending track
    next_owner=$(jq -r '[ .[] | select(.status == "pending") ] | .[0].owner // empty' <<<"$updated_tracks")
    next_action=$(jq -r '[ .[] | select(.status == "pending") ] | .[0].action_type // "triage"' <<<"$updated_tracks")
    next_track_id=$(jq -r '[ .[] | select(.status == "pending") ] | .[0].id // "track-?"' <<<"$updated_tracks")
    if [ -n "$next_owner" ]; then
      updated_tracks=$(jq -c --arg id "$next_track_id" '
        [ .[] |
          if .id == $id then . + { status: "running", started_at: (now | todate) } else . end
        ]
      ' <<<"$updated_tracks")
      next="$next_owner"
      action="dispatch:parallel:${next_track_id}:${next_owner}/${next_action}"
      new_workflow_stage="$(meeting_stage_for_owner "$next_owner")"
      if [ "$next_owner" = "planner" ]; then
        planner_filter=".planner.requested_mode = \"$next_action\""
      fi
      meeting_filter=".conductor.tracks = $updated_tracks | .meetings.decision.tracks = $updated_tracks"
    else
      next="$candidate"
      action="parallel:await-rendezvous"
      meeting_filter=".conductor.tracks = $updated_tracks | .meetings.decision.tracks = $updated_tracks"
    fi
  else
    # All tracks completed → rendezvous (followup-review)
    rdv_type=$(jq -r '.type // "followup-review"' <<<"$parallel_rendezvous")
    fork_meeting_id=$(jq -r '.conductor.fork_meeting_id // ""' "$PROGRESS")
    next="meeting-manager"
    action="convene:${rdv_type}:rendezvous"
    new_conductor_state="waiting_meeting"
    new_workflow_stage="followup-review"
    meeting_prepare=true
    # Save prior_tracks + fork_meeting_id to a stable namespace (.meetings.fork_context)
    # because meeting-doc.sh prepare overwrites .meetings.decision with a new skeleton.
    meeting_filter="
      .meetings.active = [\"meeting-manager\"] |
      .meetings.requested_type = \"$rdv_type\" |
      .meetings.requested_reason = \"rendezvous\" |
      .meetings.requested_tracks = [] |
      .meetings.requested_rendezvous = null |
      .meetings.fork_meeting_id = $(escape_json_string "$fork_meeting_id") |
      .meetings.fork_context = {
        \"fork_meeting_id\": $(escape_json_string "$fork_meeting_id"),
        \"prior_tracks\": $updated_tracks,
        \"sealed_at\": (now | todate)
      } |
      .planner.requested_mode = null |
      .conductor.tracks = $updated_tracks |
      .conductor.rendezvous = null"
  fi

elif [ "$pending_required_execution" != "true" ] && [ "$requested_mode" != "null" ] && [ -n "$requested_mode" ] && [ "$current_agent" != "service-ops" ]; then
  next="service-ops"
  action="spawn:service-ops:${requested_mode}"

elif [ "$goal_adherence" != "null" ] && awk "BEGIN {exit !($goal_adherence < 0.7)}"; then
  next="meeting-manager"
  action="convene:spec-review:${drift_classification}"
  new_conductor_state="waiting_meeting"
  new_workflow_stage="goal-drift-review"
  meeting_prepare=true
  meeting_filter="
    .meetings.active = [\"meeting-manager\"] |
    .meetings.requested_type = \"spec-review\" |
    .meetings.requested_reason = \"goal-drift\" |
    .service_ops.drift_classification = \"$drift_classification\" |
    .meetings.decision = {
      \"owner\": null,
      \"action_type\": null,
      \"rationale\": null,
      \"evidence\": [],
      \"drift_classification\": \"$drift_classification\",
      \"source_path\": null
    }"

elif [ "$current_agent" = "meeting-manager" ] && [ "$agent_status" = "completed" ]; then
  meeting_decision="$(load_meeting_decision)"
  owner=$(jq -r '.owner // "null"' <<<"$meeting_decision")
  action_type=$(jq -r '.action_type // "triage"' <<<"$meeting_decision")
  rationale=$(jq -r '.rationale // ""' <<<"$meeting_decision")
  evidence=$(jq -c '.evidence // []' <<<"$meeting_decision")
  decision_drift=$(jq -r '.drift_classification // "unknown"' <<<"$meeting_decision")
  source_path=$(jq -r '.source_path // "null"' <<<"$meeting_decision")
  required_execution=$(jq -c '.required_execution // null' <<<"$meeting_decision")
  required_deliverable=$(jq -r '.required_execution.deliverable_path // "null"' <<<"$meeting_decision")
  # v6.2 — tracks length >= 2 → fork-join, else single. mode 필드 없음.
  decision_tracks=$(jq -c '.tracks // []' <<<"$meeting_decision")
  decision_rendezvous=$(jq -c '.rendezvous // null' <<<"$meeting_decision")

  if [ "$owner" = "null" ] || [ -z "$owner" ]; then
    case "$decision_drift" in
      implementation_drift) owner="cto" ;;
      planning_drift) owner="planner" ;;
      ops_drift) owner="service-ops" ;;
      goal_drift) owner="planner" ;;
      *)
        if [ "$plan_artifacts_ready" = false ]; then owner="planner"; else owner="cto"; fi
        ;;
    esac
  fi

  if [ "$required_execution" = "null" ]; then
    case "$owner:$action_type" in
      planner:continue-current-handoff|planner:execution-plan|cto:continue-current-handoff|cqo:continue-current-handoff|generator-*:continue-current-handoff|evaluator-*:continue-current-handoff)
        next="meeting-manager"
        action="convene:followup-review:execution-contract-missing"
        new_conductor_state="waiting_meeting"
        new_workflow_stage="followup-review"
        meeting_prepare=true
        meeting_filter="
          .meetings.active = [\"meeting-manager\"] |
          .meetings.requested_type = \"followup-review\" |
          .meetings.requested_reason = \"execution-contract-missing\" |
          .meetings.contract_missing = {
            \"owner\": \"$owner\",
            \"action_type\": \"$action_type\",
            \"source_path\": $(escape_json_string "$source_path"),
            \"detected_at\": (now | todate)
          }"
        ;;
    esac
  fi

  # v6.2 — Parallel fork: if 2+ tracks, materialize all tracks as running.
  # `next_agent` keeps the first owner only for backward-compatible handoff display;
  # the fork state itself must expose every track as active in the same tick.
  if [ "$action" = "convene:followup-review:execution-contract-missing" ]; then
    :
  elif [ "$(jq 'length' <<<"$decision_tracks")" -gt 1 ]; then
    first_track_owner=$(jq -r '.[0].owner' <<<"$decision_tracks")
    first_track_action=$(jq -r '.[0].action_type // "triage"' <<<"$decision_tracks")
    first_track_id=$(jq -r '.[0].id // "track-1"' <<<"$decision_tracks")
    active_track_owners=$(jq -c '[.[] | .owner] | unique' <<<"$decision_tracks")
    # mark every independent track as running; rendezvous waits for completion.
    materialized_tracks=$(jq -c '
      [ .[] | . + {
          status: "running",
          started_at: (now | todate),
          deliverable_path: (.deliverable_path // null)
        }
      ]
    ' <<<"$decision_tracks")
    next="$first_track_owner"
    action="dispatch:parallel:${first_track_id}:${first_track_owner}/${first_track_action}"
    new_workflow_stage="$(meeting_stage_for_owner "$first_track_owner")"
    if [ "$first_track_owner" = "planner" ]; then
      planner_filter=".planner.requested_mode = \"$first_track_action\""
    fi
    meeting_filter="
      .meetings.active = [] |
      .meetings.last_type = .meetings.requested_type |
      .meetings.last_reason = .meetings.requested_reason |
      .meetings.last_decision = \"fork:${first_track_owner}:${first_track_action}\" |
      .meetings.requested_type = null |
      .meetings.requested_reason = null |
      .meetings.requested_tracks = [] |
      .meetings.requested_rendezvous = null |
      .meetings.active = $active_track_owners |
      .meetings.decision = {
        \"owner\": \"$owner\",
        \"action_type\": \"$action_type\",
        \"rationale\": $(escape_json_string "$rationale"),
        \"evidence\": $evidence,
        \"drift_classification\": $(escape_json_string "$decision_drift"),
        \"source_path\": $(escape_json_string "$source_path"),
        \"tracks\": $materialized_tracks,
        \"rendezvous\": $decision_rendezvous
      } |
      .conductor.tracks = $materialized_tracks |
      .conductor.rendezvous = $decision_rendezvous |
      .conductor.fork_meeting_id = (.meetings.current_id // null)"
  else
    if [ "$action_type" = "strategy-cadence-recovery" ]; then
      ensure_strategy_work_package "$required_execution" "$required_deliverable"
      owner="planner"
    fi
    next="$owner"
    action="dispatch:${owner}:${action_type}"
    new_workflow_stage="$(meeting_stage_for_owner "$owner")"
    if [ "$owner" = "planner" ]; then
      planner_filter=".planner.requested_mode = \"$action_type\""
    fi
    meeting_filter="
      .meetings.active = [] |
      .meetings.last_type = .meetings.requested_type |
      .meetings.last_reason = .meetings.requested_reason |
      .meetings.last_decision = \"$owner:$action_type\" |
      .meetings.requested_type = null |
      .meetings.requested_reason = null |
      .meetings.requested_tracks = [] |
      .meetings.requested_rendezvous = null |
      .meetings.decision = {
        \"owner\": \"$owner\",
        \"action_type\": \"$action_type\",
        \"rationale\": $(escape_json_string "$rationale"),
        \"evidence\": $evidence,
        \"drift_classification\": $(escape_json_string "$decision_drift"),
        \"source_path\": $(escape_json_string "$source_path"),
        \"required_execution\": $required_execution,
        \"tracks\": [],
        \"rendezvous\": null
      } |
      .conductor.tracks = [] |
      .conductor.rendezvous = null |
      .conductor.fork_meeting_id = null"
  fi

elif [ "$current_agent" = "planner" ] && [ "$agent_status" = "completed" ]; then
  # v6.2 — hypothesis-verdict is terminal for the cell; return to meeting-manager.
  if [ "$planner_requested_mode" = "hypothesis-verdict" ]; then
    next="meeting-manager"
    action="convene:followup-review:hypothesis-verdict"
    new_workflow_stage="followup-review"
    meeting_prepare=true
    planner_filter='.planner.requested_mode = null'
    meeting_filter="
      .meetings.active = [\"meeting-manager\"] |
      .meetings.requested_type = \"followup-review\" |
      .meetings.requested_reason = \"rendezvous\" |
      .meetings.requested_tracks = [] |
      .meetings.requested_rendezvous = null"
  # v6.2 — Accept hypothesis* (e.g. "hypothesis", "hypothesis-validation") as Hypothesis Cell trigger
  elif [[ "$planner_requested_mode" == hypothesis* ]]; then
    next="documentationer"
    action="dispatch:hypothesis:documentationer"
    new_workflow_stage="coo-hypothesis-research"
    planner_filter='
      .planner.last_brief = "hypothesis:research" |
      .planner.requested_mode = null'
  else
    next="cto"
    action="handoff:cto:plan-ready"
    new_workflow_stage="cto-review"
    planner_filter='
      .planner.last_brief = (.planner.requested_mode // "goal-alignment") |
      .planner.requested_mode = null'
  fi

elif [ "$current_agent" = "documentationer" ] && [ "$agent_status" = "completed" ]; then
  if [ "$planner_last_brief" = "hypothesis:research" ]; then
    next="coo-developer"
    action="dispatch:hypothesis:experiment"
    new_workflow_stage="coo-hypothesis-experiment"
    planner_filter='.planner.last_brief = "hypothesis:experiment"'
  elif [ "$planner_last_brief" = "hypothesis:report" ]; then
    next="planner"
    action="dispatch:planner:hypothesis-verdict"
    new_workflow_stage="coo-hypothesis-verdict"
    planner_filter='
      .planner.last_brief = "hypothesis:done" |
      .planner.requested_mode = "hypothesis-verdict"'
  fi

elif [ "$current_agent" = "coo-developer" ] && [ "$agent_status" = "completed" ]; then
  if [ "$planner_last_brief" = "hypothesis:experiment" ]; then
    next="documentationer"
    action="dispatch:hypothesis:report"
    new_workflow_stage="coo-hypothesis-report"
    planner_filter='.planner.last_brief = "hypothesis:report"'
  fi

elif [ "$current_agent" = "cto" ]; then
  cto_step_b_status=$(jq -r '.cto.step_b_status // ""' "$PROGRESS")
  if [ "$agent_status" = "step-B-code-edited" ] || [[ "$cto_step_b_status" == *deferred* ]]; then
    next="cqo"
    action="spawn:cqo:gateway-typecheck-verify"
    new_workflow_stage="quality-review"
    meeting_filter='
      .cqo.requested_mode = "gateway-typecheck-verify" |
      .meetings.active = ["cqo"] |
      .meetings.requested_type = null |
      .meetings.requested_reason = null'
  elif [ "${cto_hotfixes:-0}" -gt 0 ] || [ "${ops_recommendations:-0}" -gt 0 ]; then
    next="planner"
    action="dispatch:planner:execution-plan"
    new_workflow_stage="coo-replan"
    planner_filter='.planner.requested_mode = "execution-plan"'
  elif [ "$candidate" = "archive" ] && [ "$workflow_stage" = "ops-review" ]; then
    next="archive"
    action="archive"
    new_conductor_state="completed"
    new_workflow_stage="ops-monitoring"
  else
    next="$first_generator"
    action="dispatch:workers:${first_generator}"
    new_workflow_stage="implementation"
  fi

elif [ "$candidate" = "archive" ]; then
  if [[ "$current_agent" == evaluator-* ]] && [ "$cqo_verdict" = "pending" ]; then
    next="cqo"
    action="spawn:cqo"
    new_workflow_stage="quality-review"
  elif [ "$current_agent" = "cqo" ]; then
    if [ "$cqo_verdict" = "FAIL" ] || [ "${cqo_regressions:-0}" -gt 0 ] || [ "${cqo_axes_below:-0}" -gt 0 ]; then
      next="meeting-manager"
      action="convene:spec-review:implementation_drift"
      new_conductor_state="waiting_meeting"
      new_workflow_stage="quality-review"
      meeting_prepare=true
      meeting_filter='
        .meetings.active = ["meeting-manager"] |
        .meetings.requested_type = "spec-review" |
        .meetings.requested_reason = "quality-fail" |
        .service_ops.drift_classification = "implementation_drift" |
        .meetings.decision = {
          "owner": null,
          "action_type": null,
          "rationale": null,
          "evidence": [],
          "drift_classification": "implementation_drift",
          "source_path": null
        }'
    else
      next="service-ops"
      action="spawn:service-ops:auto-retro"
      new_workflow_stage="ops-review"
      ops_filter='.service_ops.requested_mode = "auto-retro"'
    fi
  elif [ "$cqo_verdict" != "pending" ] && [ "$ops_report" = "null" ]; then
    next="service-ops"
    action="spawn:service-ops:auto-retro"
    new_workflow_stage="ops-review"
    ops_filter='.service_ops.requested_mode = "auto-retro"'
  elif [ "$current_agent" = "service-ops" ]; then
    local_drift="$drift_classification"
    if [ "$requested_mode" = "auto-retro" ] || [ "${open_incidents:-0}" -gt 0 ] || [ "${ops_alerts:-0}" -gt 0 ] || { [ "$goal_adherence" != "null" ] && awk "BEGIN {exit !($goal_adherence < 0.7)}"; }; then
      next="meeting-manager"
      action="convene:operating-review:${local_drift}"
      new_conductor_state="waiting_meeting"
      new_workflow_stage="ops-review"
      meeting_prepare=true
      meeting_filter="
        .meetings.active = [\"meeting-manager\"] |
        .meetings.requested_type = \"followup-review\" |
        .meetings.requested_reason = \"ops-batch\" |
        .service_ops.drift_classification = \"$local_drift\" |
        .meetings.decision = {
          \"owner\": null,
          \"action_type\": null,
          \"rationale\": null,
          \"evidence\": [],
          \"drift_classification\": \"$local_drift\",
          \"source_path\": null
        }"
    else
      next="archive"
      action="archive"
      new_conductor_state="completed"
      new_workflow_stage="ops-monitoring"
      ops_filter='.service_ops.requested_mode = null'
    fi
  fi
fi

filter=".conductor.state = \"$new_conductor_state\" |
  .conductor.current_action = \"$action\" |
  .conductor.last_tick = (now | todate) |
  .conductor.tick_count = ((.conductor.tick_count // 0) + 1) |
  .next_agent = \"$next\" |
  .workflow.stage = \"$new_workflow_stage\" |
  .workflow.last_transition = (now | todate) |
  .workflow.last_reason = \"$action\""

if [ -n "$meeting_filter" ]; then
  filter="$filter | $meeting_filter"
fi
if [ -n "$planner_filter" ]; then
  filter="$filter | $planner_filter"
fi
if [ -n "$ops_filter" ]; then
  filter="$filter | $ops_filter"
elif [ "$current_agent" = "service-ops" ] && [ "$next" != "service-ops" ]; then
  filter="$filter | .service_ops.requested_mode = null"
fi
if [ "$next" = "meeting-manager" ] && [ "$workflow_stage" = "ops-review" ]; then
  filter="$filter | .workflow.loop_count = ((.workflow.loop_count // 0) + 1)"
fi

worker_dispatches="[]"
if [ "$new_conductor_state" = "running" ] &&
  [ "$next" != "meeting-manager" ] &&
  [ "$next" != "service-ops" ] &&
  [ "$next" != "planner" ] &&
  [ "$next" != "cto" ] &&
  [ "$next" != "cqo" ] &&
  [ "$next" != "archive" ]; then
  worker_dispatches="$(dispatch_company_workers)"
  if jq -e 'type == "array" and length > 0' >/dev/null 2>&1 <<<"$worker_dispatches"; then
    dispatch_count="$(jq 'length' <<<"$worker_dispatches")"
    filter="$filter |
      .conductor.current_action = \"dispatch:workers:${dispatch_count}\" |
      .next_agent = \"conductor\" |
      .workflow.stage = \"implementation\" |
      .workflow.last_reason = \"dispatch:workers:${dispatch_count}\""
    next="conductor"
  fi
fi

set_progress "$filter"

if command -v node >/dev/null 2>&1 && [ -f "$SCRIPT_DIR/harness-activity-record.js" ]; then
  node "$SCRIPT_DIR/harness-activity-record.js" "$PROJECT_ROOT" >/dev/null 2>&1 || true
fi

if [ "$meeting_prepare" = true ] && [ "$next" = "meeting-manager" ]; then
  bash "$SCRIPT_DIR/harness-meeting-doc.sh" "$PROJECT_ROOT" prepare >/dev/null 2>&1 || true
fi

echo "$next"
