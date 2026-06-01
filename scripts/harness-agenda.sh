#!/bin/bash
# harness-agenda.sh — shared executive agenda (안건) for the perpetual operating loop.
#
# The agenda is the meetup file every CXX co-writes. The Stop hook forces the
# CEO to adjudicate it: while items are open/decided the loop keeps running; when
# it is empty the CEO must run a status-briefing round (each CXX confirms its
# live deliverables still operate toward the goal and raises new items) before
# the loop may yield to the next hourly wake.
#
# Store: .harness/documents/<goal-rel>/agenda.json
#   { items:[{id,raised_by,kind,title,evidence,status:open|decided|done,
#             decision,decided_by,created_at,updated_at}],
#     cycles:int, last_cycle_at, last_briefing_at }
#
# Usage:
#   harness-agenda.sh <project-root> <goal-rel> raise  <cxx> <kind> "<title>" ["<evidence>"]
#   harness-agenda.sh <project-root> <goal-rel> decide <id> "<decision>" [<owner-cxx>]
#   harness-agenda.sh <project-root> <goal-rel> close  <id>
#   harness-agenda.sh <project-root> <goal-rel> brief                 # stamp a briefing round
#   harness-agenda.sh <project-root> <goal-rel> active-count          # items not done
#   harness-agenda.sh <project-root> <goal-rel> open-count            # items needing CEO decision
#   harness-agenda.sh <project-root> <goal-rel> list

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="${1:-.}"
GOAL_REL="${2:-}"
CMD="${3:-}"
command -v jq >/dev/null 2>&1 || { echo "[agenda] jq required" >&2; exit 1; }
[ -n "$GOAL_REL" ] && [ -n "$CMD" ] || { echo "[agenda] usage: $0 <project-root> <goal-rel> <cmd> ..." >&2; exit 2; }

AGENDA_DIR="$PROJECT_ROOT/.harness/documents/$GOAL_REL"
AGENDA="$AGENDA_DIR/agenda.json"
mkdir -p "$AGENDA_DIR"
[ -f "$AGENDA" ] || echo '{"items":[],"cycles":0,"last_cycle_at":null,"last_briefing_at":null}' > "$AGENDA"

STRUCTURED_LIB="$SCRIPT_DIR/lib/harness-structured-log.sh"
[ -f "$STRUCTURED_LIB" ] && source "$STRUCTURED_LIB"

NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

apply() { # jq-program ; reads from extra --arg pairs already in "$@"
  local prog="$1"; shift
  local tmp="$AGENDA.tmp.$$"
  if jq "$@" "$prog" "$AGENDA" > "$tmp" 2>/dev/null; then
    mv "$tmp" "$AGENDA"
  else
    rm -f "$tmp"; echo "[agenda] write failed" >&2; exit 1
  fi
}

upsert_todo() { # owner kind title status id priority
  declare -f harness_todo_upsert >/dev/null 2>&1 || return 0
  local todo
  todo=$(jq -nc \
    --arg id "$5" --arg owner "$1" --arg kind "$2" --arg title "$3" \
    --arg status "$4" --arg now "$NOW" --argjson priority "${6:-60}" '
    {id:$id,owner:$owner,kind:$kind,title:$title,status:$status,priority:$priority,
     command:"agenda",mission_path:null,required_artifacts:[],
     created_at:$now,updated_at:$now,last_heartbeat_at:$now,blocked_reason:null}')
  harness_todo_upsert "$PROJECT_ROOT" "$todo"
}

case "$CMD" in
  raise)
    CXX="${4:-ceo}"; KIND="${5:-other}"; TITLE="${6:-untitled}"; EVID="${7:-}"
    N=$(jq '.items | length' "$AGENDA")
    ID="A-$(date -u +%Y%m%dT%H%M%SZ)-$N"
    apply '.items += [{id:$id,raised_by:$cxx,kind:$kind,title:$title,evidence:$evid,status:"open",decision:null,decided_by:null,created_at:$now,updated_at:$now}]' \
      --arg id "$ID" --arg cxx "$CXX" --arg kind "$KIND" --arg title "$TITLE" --arg evid "$EVID" --arg now "$NOW"
    upsert_todo "$CXX" "agenda" "[안건] $TITLE" "pending" "$ID" 70
    echo "$ID"
    ;;
  decide)
    ID="${4:-}"; DECISION="${5:-}"; OWNER="${6:-}"
    [ -n "$ID" ] || { echo "[agenda] decide needs <id>" >&2; exit 2; }
    apply '.items |= map(if .id==$id then .status="decided" | .decision=$decision | .decided_by="ceo" | .updated_at=$now else . end)' \
      --arg id "$ID" --arg decision "$DECISION" --arg now "$NOW"
    [ -n "$OWNER" ] && upsert_todo "$OWNER" "agenda" "[결정] $DECISION" "active" "$ID-do" 70
    echo "decided $ID"
    ;;
  close)
    ID="${4:-}"
    [ -n "$ID" ] || { echo "[agenda] close needs <id>" >&2; exit 2; }
    apply '.items |= map(if .id==$id then .status="done" | .updated_at=$now else . end)' \
      --arg id "$ID" --arg now "$NOW"
    echo "closed $ID"
    ;;
  brief)
    apply '.last_briefing_at=$now' --arg now "$NOW"
    echo "briefing stamped"
    ;;
  active-count)
    jq '[.items[] | select(.status != "done")] | length' "$AGENDA"
    ;;
  open-count)
    jq '[.items[] | select(.status == "open")] | length' "$AGENDA"
    ;;
  list)
    jq -c '[.items[] | select(.status != "done")]' "$AGENDA"
    ;;
  *)
    echo "[agenda] unknown command: $CMD" >&2; exit 2 ;;
esac
