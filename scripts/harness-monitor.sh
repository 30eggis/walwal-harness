#!/bin/bash
# harness-monitor.sh — Panel 2: Task & Agent Lifecycle 모니터링
# audit.log 스트리밍 + progress.json 변경 감지
# Usage: bash scripts/harness-monitor.sh [project-root]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

PROJECT_ROOT="${1:-}"
if [ -z "$PROJECT_ROOT" ]; then
  source "$SCRIPT_DIR/lib/harness-render-progress.sh"
  PROJECT_ROOT="$(resolve_harness_root ".")" || {
    echo "[monitor] .harness/ not found. Pass project root as argument."
    exit 1
  }
fi

PROGRESS="$PROJECT_ROOT/.harness/progress.json"
AUDIT_LOG="$PROJECT_ROOT/.harness/actions/audit.log"
HANDOFF="$PROJECT_ROOT/.harness/handoff.json"

# ── ANSI helpers ──
BOLD="\033[1m"
DIM="\033[2m"
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
CYAN="\033[36m"
MAGENTA="\033[35m"
RESET="\033[0m"

LAST_AGENT=""
LAST_STATUS=""
LAST_SPRINT=""
EVENT_COUNT=0

print_event() {
  local ts="$1" icon="$2" color="$3" msg="$4"
  EVENT_COUNT=$((EVENT_COUNT + 1))
  echo -e "  ${DIM}${ts}${RESET}  ${color}${icon}${RESET}  ${msg}"
}

# ── Header ──
print_header() {
  echo -e "${BOLD}╔══════════════════════════════════════╗${RESET}"
  echo -e "${BOLD}║  AGENT LIFECYCLE MONITOR             ║${RESET}"
  echo -e "${BOLD}╚══════════════════════════════════════╝${RESET}"
  echo ""
}

# ── Detect agent transitions from progress.json ──
check_transitions() {
  if [ ! -f "$PROGRESS" ]; then return; fi

  local agent status sprint
  agent=$(jq -r '.current_agent // "none"' "$PROGRESS" 2>/dev/null)
  status=$(jq -r '.agent_status // "pending"' "$PROGRESS" 2>/dev/null)
  sprint=$(jq -r '.sprint.number // 0' "$PROGRESS" 2>/dev/null)

  local now
  now=$(date +"%H:%M:%S")

  # Sprint change
  if [ "$sprint" != "$LAST_SPRINT" ] && [ -n "$LAST_SPRINT" ]; then
    print_event "$now" ">>>" "$MAGENTA" "${BOLD}Sprint ${sprint} started${RESET}"
    echo ""
  fi

  # Agent change
  if [ "$agent" != "$LAST_AGENT" ] && [ -n "$LAST_AGENT" ]; then
    if [ "$LAST_AGENT" != "none" ] && [ "$LAST_AGENT" != "null" ]; then
      print_event "$now" " ✓ " "$GREEN" "${LAST_AGENT} → ${BOLD}done${RESET}"
    fi
    if [ "$agent" != "none" ] && [ "$agent" != "null" ]; then
      print_event "$now" " ▶ " "$CYAN" "${BOLD}${agent}${RESET} started"

      # Show handoff context if available
      if [ -f "$HANDOFF" ]; then
        local from focus
        from=$(jq -r '.from // empty' "$HANDOFF" 2>/dev/null)
        focus=$(jq -r '.focus_features // [] | join(", ")' "$HANDOFF" 2>/dev/null)
        if [ -n "$from" ] && [ "$from" != "null" ]; then
          echo -e "         ${DIM}handoff from: ${from}${RESET}"
        fi
        if [ -n "$focus" ] && [ "$focus" != "null" ]; then
          echo -e "         ${DIM}focus: ${focus}${RESET}"
        fi
      fi
    fi
  fi

  # Status change (same agent)
  if [ "$agent" = "$LAST_AGENT" ] && [ "$status" != "$LAST_STATUS" ] && [ -n "$LAST_STATUS" ]; then
    local status_color="$RESET"
    local status_icon="•"
    case "$status" in
      running)   status_color="$GREEN";  status_icon=" ▶ " ;;
      completed) status_color="$CYAN";   status_icon=" ✓ " ;;
      failed)    status_color="$RED";    status_icon=" ✗ " ;;
      blocked)   status_color="$RED";    status_icon=" ! " ;;
      pending)   status_color="$YELLOW"; status_icon=" … " ;;
    esac
    print_event "$now" "$status_icon" "$status_color" "${agent} → ${BOLD}${status}${RESET}"

    # Show failure detail
    if [ "$status" = "failed" ]; then
      local fail_msg
      fail_msg=$(jq -r '.failure.message // empty' "$PROGRESS" 2>/dev/null)
      if [ -n "$fail_msg" ] && [ "$fail_msg" != "null" ]; then
        echo -e "         ${RED}${fail_msg}${RESET}"
      fi
    fi
  fi

  LAST_AGENT="$agent"
  LAST_STATUS="$status"
  LAST_SPRINT="$sprint"
}

# ── Stream audit.log new lines ──
stream_audit() {
  if [ ! -f "$AUDIT_LOG" ]; then return; fi

  # Use tail -f in background, parse each new line
  tail -n 0 -f "$AUDIT_LOG" 2>/dev/null | while IFS= read -r line; do
    # Skip comments/headers
    if [[ "$line" == "#"* ]] || [[ -z "$line" ]]; then continue; fi

    # Parse: TIMESTAMP | AGENT | ACTION | STATUS | TARGET | DETAIL
    local ts agent action status target detail
    ts=$(echo "$line" | awk -F'|' '{gsub(/^ +| +$/,"",$1); print $1}')
    agent=$(echo "$line" | awk -F'|' '{gsub(/^ +| +$/,"",$2); print $2}')
    action=$(echo "$line" | awk -F'|' '{gsub(/^ +| +$/,"",$3); print $3}')
    status=$(echo "$line" | awk -F'|' '{gsub(/^ +| +$/,"",$4); print $4}')
    target=$(echo "$line" | awk -F'|' '{gsub(/^ +| +$/,"",$5); print $5}')
    detail=$(echo "$line" | awk -F'|' '{gsub(/^ +| +$/,"",$6); print $6}')

    # Color by status
    local color="$RESET" icon="•"
    case "$status" in
      start)    color="$CYAN";   icon="▶" ;;
      complete) color="$GREEN";  icon="✓" ;;
      fail)     color="$RED";    icon="✗" ;;
      pass)     color="$GREEN";  icon="✓" ;;
      skip)     color="$DIM";    icon="–" ;;
    esac

    # Short timestamp (HH:MM:SS from ISO)
    local short_ts
    short_ts=$(echo "$ts" | grep -oE '[0-9]{2}:[0-9]{2}:[0-9]{2}' || echo "$ts")

    echo -e "  ${DIM}${short_ts}${RESET}  ${color}${icon}${RESET}  ${BOLD}${agent}${RESET} ${action} ${target} ${DIM}${detail}${RESET}"
  done &
  AUDIT_TAIL_PID=$!
}

# ── Cleanup ──
cleanup() {
  if [ -n "${AUDIT_TAIL_PID:-}" ]; then
    kill "$AUDIT_TAIL_PID" 2>/dev/null || true
  fi
  exit 0
}
trap cleanup EXIT INT TERM

# ── Main ──
print_header

# Initialize state
if [ -f "$PROGRESS" ]; then
  LAST_AGENT=$(jq -r '.current_agent // "none"' "$PROGRESS" 2>/dev/null)
  LAST_STATUS=$(jq -r '.agent_status // "pending"' "$PROGRESS" 2>/dev/null)
  LAST_SPRINT=$(jq -r '.sprint.number // 0' "$PROGRESS" 2>/dev/null)
fi

# Show existing history
if [ -f "$PROGRESS" ]; then
  echo -e "  ${BOLD}History${RESET}"
  jq -r '.history // [] | .[] | "  \(.timestamp)  \(.agent) — \(.action): \(.detail)"' "$PROGRESS" 2>/dev/null
  echo ""
  echo -e "  ${DIM}── Live events below ──${RESET}"
  echo ""
fi

# Start audit log streaming
stream_audit

# Poll progress.json for transitions
while true; do
  check_transitions
  sleep 2
done
