#!/bin/bash
# harness-queue-manager.sh — Feature Queue Manager (v4.0)
#
# feature-list.json에서 depends_on 그래프를 읽어 topological sort 후
# feature-queue.json을 생성/관리한다.
#
# Commands:
#   init          feature-list.json → feature-queue.json 초기 생성
#   dequeue <team> ready 큐에서 feature를 꺼내 team에 배정
#   pass <fid>    feature를 passed로 이동, blocked→ready 전이
#   fail <fid>    feature를 failed로 이동
#   requeue <fid> failed feature를 ready로 복귀
#   status        현재 큐 상태 출력
#
# Usage: bash scripts/harness-queue-manager.sh <command> [args...] [project-root]

set -uo pipefail

# ── Resolve project root ──
resolve_root() {
  local dir="${1:-.}"
  dir="$(cd "$dir" 2>/dev/null && pwd || echo "$dir")"
  while [ "$dir" != "/" ]; do
    if [ -d "$dir/.harness" ]; then echo "$dir"; return 0; fi
    dir="$(dirname "$dir")"
  done
  return 1
}

CMD="${1:-status}"
shift || true

# Last arg might be project root
PROJECT_ROOT=""
for arg in "$@"; do
  if [ -d "$arg/.harness" ]; then PROJECT_ROOT="$arg"; fi
done
if [ -z "$PROJECT_ROOT" ]; then
  PROJECT_ROOT="$(resolve_root ".")" || { echo "[queue] .harness/ not found."; exit 1; }
fi

FEATURES="$PROJECT_ROOT/.harness/actions/feature-list.json"
QUEUE="$PROJECT_ROOT/.harness/actions/feature-queue.json"
CONFIG="$PROJECT_ROOT/.harness/config.json"

# ── Concurrency from config ──
CONCURRENCY=3
if [ -f "$CONFIG" ]; then
  _c=$(jq -r '.flow.parallel.concurrency // 3' "$CONFIG" 2>/dev/null)
  if [ "$_c" -gt 0 ] 2>/dev/null; then CONCURRENCY=$_c; fi
fi

# ══════════════════════════════════════════
# init — Build queue from feature-list.json
# ══════════════════════════════════════════
cmd_init() {
  if [ ! -f "$FEATURES" ]; then
    echo "[queue] feature-list.json not found."
    exit 1
  fi

  # Build dependency graph and topological sort
  # Output: feature-queue.json with ready (no deps) and blocked (has deps)
  jq --argjson concurrency "$CONCURRENCY" '
    # Build passed set (features already passed by evaluator)
    def passed_set:
      [.features[] | select(
        ((.passes // []) | length > 0) and
        ((.passes // []) | any(. == "evaluator-functional"))
      ) | .id] ;

    # Separate ready vs blocked
    def classify(passed):
      reduce .features[] as $f (
        { ready: [], blocked: {} };
        ($f.depends_on // []) as $deps |
        if ($f.id | IN(passed[])) then .  # already passed, skip
        elif ($deps | length == 0) then
          .ready += [$f.id]
        elif (passed | length > 0) and ($deps | all(. as $d | $d | IN(passed[]))) then
          .ready += [$f.id]  # all deps satisfied
        else
          .blocked[$f.id] = ($deps - passed)
        end
      ) ;

    passed_set as $passed |
    classify($passed) as $classified |
    {
      version: "4.0",
      concurrency: $concurrency,
      queue: {
        ready: $classified.ready,
        blocked: $classified.blocked,
        in_progress: {},
        passed: $passed,
        failed: []
      },
      teams: (
        [range(1; $concurrency + 1)] | map({
          key: (. | tostring),
          value: { status: "idle", feature: null, branch: null, pid: null }
        }) | from_entries
      )
    }
  ' "$FEATURES" > "$QUEUE"

  local ready_count blocked_count passed_count
  ready_count=$(jq '.queue.ready | length' "$QUEUE")
  blocked_count=$(jq '.queue.blocked | length' "$QUEUE")
  passed_count=$(jq '.queue.passed | length' "$QUEUE")

  echo "[queue] Initialized: $ready_count ready, $blocked_count blocked, $passed_count already passed"
  echo "[queue] Concurrency: $CONCURRENCY teams"
}

# ══════════════════════════════════════════
# dequeue — Assign next ready feature to team
# ══════════════════════════════════════════
cmd_dequeue() {
  local team_id="${1:-}"
  if [ -z "$team_id" ]; then echo "[queue] Usage: dequeue <team_id>"; exit 1; fi
  if [ ! -f "$QUEUE" ]; then echo "[queue] Run 'init' first."; exit 1; fi

  local feature
  feature=$(jq -r '.queue.ready[0] // empty' "$QUEUE")

  if [ -z "$feature" ]; then
    echo "[queue] No features in ready queue."
    # Check if all done
    local in_prog blocked
    in_prog=$(jq '.queue.in_progress | length' "$QUEUE")
    blocked=$(jq '.queue.blocked | length' "$QUEUE")
    if [ "$in_prog" -eq 0 ] && [ "$blocked" -eq 0 ]; then
      echo "[queue] ALL FEATURES COMPLETE."
    fi
    return 1
  fi

  # Move feature from ready → in_progress, assign to team
  jq --arg fid "$feature" --arg tid "$team_id" '
    .queue.ready -= [$fid] |
    .queue.in_progress[$fid] = { team: ($tid | tonumber), phase: "gen", attempt: 1 } |
    .teams[$tid] = { status: "busy", feature: $fid, branch: ("feature/" + $fid), pid: null }
  ' "$QUEUE" > "${QUEUE}.tmp" && mv "${QUEUE}.tmp" "$QUEUE"

  echo "$feature"
}

# ══════════════════════════════════════════
# pass — Mark feature as passed, unblock dependents
# ══════════════════════════════════════════
cmd_pass() {
  local fid="${1:-}"
  if [ -z "$fid" ]; then echo "[queue] Usage: pass <feature_id>"; exit 1; fi
  if [ ! -f "$QUEUE" ]; then echo "[queue] Run 'init' first."; exit 1; fi

  # Get team that was working on this feature
  local team_id
  team_id=$(jq -r --arg fid "$fid" '.queue.in_progress[$fid].team // empty' "$QUEUE")

  # Move from in_progress → passed, free team, unblock dependents
  jq --arg fid "$fid" --arg tid "${team_id:-0}" '
    # Remove from in_progress
    del(.queue.in_progress[$fid]) |

    # Add to passed
    .queue.passed += [$fid] |
    .queue.passed |= unique |

    # Free team
    (if $tid != "0" then
      .teams[$tid] = { status: "idle", feature: null, branch: null, pid: null }
    else . end) |

    # Unblock dependents: for each blocked feature, remove $fid from its deps
    # If deps become empty, move to ready
    .queue.blocked as $blocked |
    reduce ($blocked | keys[]) as $blocked_fid (
      .;
      .queue.blocked[$blocked_fid] -= [$fid] |
      if (.queue.blocked[$blocked_fid] | length) == 0 then
        del(.queue.blocked[$blocked_fid]) |
        .queue.ready += [$blocked_fid]
      else . end
    )
  ' "$QUEUE" > "${QUEUE}.tmp" && mv "${QUEUE}.tmp" "$QUEUE"

  local newly_ready
  newly_ready=$(jq -r '.queue.ready | join(", ")' "$QUEUE")
  echo "[queue] $fid PASSED. Ready: [$newly_ready]"
}

# ══════════════════════════════════════════
# fail — Mark feature as failed
# ══════════════════════════════════════════
cmd_fail() {
  local fid="${1:-}"
  if [ -z "$fid" ]; then echo "[queue] Usage: fail <feature_id>"; exit 1; fi
  if [ ! -f "$QUEUE" ]; then exit 1; fi

  local team_id
  team_id=$(jq -r --arg fid "$fid" '.queue.in_progress[$fid].team // empty' "$QUEUE")

  jq --arg fid "$fid" --arg tid "${team_id:-0}" '
    del(.queue.in_progress[$fid]) |
    .queue.failed += [$fid] |
    .queue.failed |= unique |
    (if $tid != "0" then
      .teams[$tid] = { status: "idle", feature: null, branch: null, pid: null }
    else . end)
  ' "$QUEUE" > "${QUEUE}.tmp" && mv "${QUEUE}.tmp" "$QUEUE"

  echo "[queue] $fid FAILED."
}

# ══════════════════════════════════════════
# requeue — Move failed feature back to ready
# ══════════════════════════════════════════
cmd_requeue() {
  local fid="${1:-}"
  if [ -z "$fid" ]; then echo "[queue] Usage: requeue <feature_id>"; exit 1; fi

  jq --arg fid "$fid" '
    .queue.failed -= [$fid] |
    .queue.ready += [$fid]
  ' "$QUEUE" > "${QUEUE}.tmp" && mv "${QUEUE}.tmp" "$QUEUE"

  echo "[queue] $fid requeued to ready."
}

# ══════════════════════════════════════════
# update_phase — Update in_progress feature phase/attempt
# ══════════════════════════════════════════
cmd_update_phase() {
  local fid="${1:-}" phase="${2:-}" attempt="${3:-}"
  if [ -z "$fid" ] || [ -z "$phase" ]; then
    echo "[queue] Usage: update_phase <feature_id> <phase> [attempt]"
    exit 1
  fi

  local jq_expr
  jq_expr=".queue.in_progress[\"$fid\"].phase = \"$phase\""
  if [ -n "$attempt" ]; then
    jq_expr="$jq_expr | .queue.in_progress[\"$fid\"].attempt = ($attempt | tonumber)"
  fi

  jq "$jq_expr" "$QUEUE" > "${QUEUE}.tmp" && mv "${QUEUE}.tmp" "$QUEUE"
}

# ══════════════════════════════════════════
# status — Print queue state
# ══════════════════════════════════════════
cmd_status() {
  if [ ! -f "$QUEUE" ]; then
    echo "[queue] Not initialized. Run: bash scripts/harness-queue-manager.sh init"
    return
  fi

  local ready blocked in_prog passed failed
  ready=$(jq -r '.queue.ready | length' "$QUEUE")
  blocked=$(jq -r '.queue.blocked | length' "$QUEUE")
  in_prog=$(jq -r '.queue.in_progress | length' "$QUEUE")
  passed=$(jq -r '.queue.passed | length' "$QUEUE")
  failed=$(jq -r '.queue.failed | length' "$QUEUE")
  local total=$((ready + blocked + in_prog + passed + failed))

  echo ""
  echo "  Feature Queue ($passed/$total done)"
  echo "  ─────────────────────────────"
  echo "  Ready:       $ready"
  echo "  Blocked:     $blocked"
  echo "  In Progress: $in_prog"
  echo "  Passed:      $passed"
  echo "  Failed:      $failed"
  echo ""

  # Team status
  local team_count
  team_count=$(jq '.teams | length' "$QUEUE")
  echo "  Teams"
  echo "  ─────────────────────────────"
  for i in $(seq 1 "$team_count"); do
    local t_status t_feature
    t_status=$(jq -r ".teams[\"$i\"].status // \"idle\"" "$QUEUE")
    t_feature=$(jq -r ".teams[\"$i\"].feature // \"—\"" "$QUEUE")
    printf "  Team %d: %-6s %s\n" "$i" "$t_status" "$t_feature"
  done
  echo ""

  # In-progress details
  if [ "$in_prog" -gt 0 ]; then
    echo "  In Progress"
    echo "  ─────────────────────────────"
    jq -r '.queue.in_progress | to_entries[] | "  \(.key): team \(.value.team) — \(.value.phase) (attempt \(.value.attempt))"' "$QUEUE"
    echo ""
  fi
}

# ── Dispatch ──
case "$CMD" in
  init)         cmd_init ;;
  dequeue)      cmd_dequeue "$@" ;;
  pass)         cmd_pass "$@" ;;
  fail)         cmd_fail "$@" ;;
  requeue)      cmd_requeue "$@" ;;
  update_phase) cmd_update_phase "$@" ;;
  status)       cmd_status ;;
  *)
    echo "Usage: harness-queue-manager.sh <init|dequeue|pass|fail|requeue|update_phase|status> [args]"
    exit 1
    ;;
esac
