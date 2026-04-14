#!/bin/bash
# harness-control-v4.sh — v4 Control Center
#
# Commands:
#   init              Initialize feature queue
#   start             Launch all idle team workers
#   pause <team>      Pause team worker
#   resume <team>     Resume team worker
#   assign <fid> <t>  Force-assign feature to team
#   requeue <fid>     Move failed feature back to ready
#   concurrency <N>   Change parallel team count
#   status / s        Show queue status
#   log <message>     Add manual note
#   help / h          Show help
#   quit / q          Exit

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

PROJECT_ROOT="${1:-}"
if [ -z "$PROJECT_ROOT" ]; then
  source "$SCRIPT_DIR/lib/harness-render-progress.sh"
  PROJECT_ROOT="$(resolve_harness_root ".")" || { echo "[control] .harness/ not found."; exit 1; }
fi

QUEUE="$PROJECT_ROOT/.harness/actions/feature-queue.json"
PROGRESS_LOG="$PROJECT_ROOT/.harness/progress.log"
QUEUE_MGR="$SCRIPT_DIR/harness-queue-manager.sh"

BOLD="\033[1m"
DIM="\033[2m"
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
CYAN="\033[36m"
RESET="\033[0m"

cmd_init() {
  bash "$QUEUE_MGR" init "$PROJECT_ROOT"
}

cmd_status() {
  bash "$QUEUE_MGR" status "$PROJECT_ROOT"
}

cmd_requeue() {
  local fid="${1:-}"
  if [ -z "$fid" ]; then echo -e "  ${RED}Usage: requeue <feature_id>${RESET}"; return; fi
  bash "$QUEUE_MGR" requeue "$fid" "$PROJECT_ROOT"
}

cmd_log() {
  local msg="$1"
  if [ -z "$msg" ]; then echo -e "  ${RED}Usage: log <message>${RESET}"; return; fi
  local ts
  ts=$(date +"%Y-%m-%d")
  echo "${ts} | manual | note | ${msg}" >> "$PROGRESS_LOG"
  echo -e "  ${GREEN}Logged:${RESET} ${msg}"
}

show_help() {
  echo ""
  echo -e "  ${BOLD}Harness v4 Control${RESET}"
  echo -e "  ${CYAN}init${RESET}                Initialize feature queue from feature-list.json"
  echo -e "  ${CYAN}status${RESET}  / ${CYAN}s${RESET}         Show queue + team status"
  echo -e "  ${CYAN}requeue${RESET} <fid>       Move failed feature back to ready"
  echo -e "  ${CYAN}log${RESET} <message>       Add manual note to progress.log"
  echo -e "  ${CYAN}help${RESET}   / ${CYAN}h${RESET}         Show this help"
  echo -e "  ${CYAN}quit${RESET}   / ${CYAN}q${RESET}         Exit control"
  echo ""
  echo -e "  ${DIM}Teams auto-start when studio launches.${RESET}"
  echo -e "  ${DIM}Workers auto-dequeue from the ready queue.${RESET}"
  echo ""
}

# ── Main ──
echo ""
echo -e "  ${BOLD}Harness v4 Control${RESET}  ${DIM}(type 'help' for commands)${RESET}"
echo ""

while true; do
  echo -ne "  ${BOLD}v4>${RESET} "
  read -r input || exit 0
  input=$(echo "$input" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

  case "$input" in
    init)           cmd_init ;;
    status|s)       cmd_status ;;
    requeue\ *)     cmd_requeue "${input#requeue }" ;;
    log\ *)         cmd_log "${input#log }" ;;
    help|h)         show_help ;;
    quit|q)         echo -e "  ${DIM}Goodbye.${RESET}"; exit 0 ;;
    "")             ;; # empty
    *)              echo -e "  ${DIM}Unknown command. Type 'help'.${RESET}" ;;
  esac
done
