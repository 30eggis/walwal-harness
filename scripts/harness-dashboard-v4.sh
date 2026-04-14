#!/bin/bash
# harness-dashboard-v4.sh — v4 Dashboard: Feature Queue + Team Status
# Auto-refresh 3초 간격. feature-queue.json + feature-list.json 시각화.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/harness-render-progress.sh"

PROJECT_ROOT="${1:-}"
if [ -z "$PROJECT_ROOT" ]; then
  PROJECT_ROOT="$(resolve_harness_root ".")" || { echo "[dash] .harness/ not found."; exit 1; }
fi

QUEUE="$PROJECT_ROOT/.harness/actions/feature-queue.json"
FEATURES="$PROJECT_ROOT/.harness/actions/feature-list.json"
PROGRESS="$PROJECT_ROOT/.harness/progress.json"

BOLD="\033[1m"
DIM="\033[2m"
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
CYAN="\033[36m"
MAGENTA="\033[35m"
RESET="\033[0m"

render_header() {
  local now project_name
  now=$(date +"%H:%M:%S")
  project_name=$(jq -r '.project_name // "Unknown"' "$PROGRESS" 2>/dev/null)

  echo -e "${BOLD}╔════════════════════════════════════════════════╗${RESET}"
  echo -e "${BOLD}║  HARNESS v4 — Parallel Agent Teams             ║${RESET}"
  echo -e "${BOLD}╚════════════════════════════════════════════════╝${RESET}"
  echo -e "  ${DIM}${project_name}  |  ${now}${RESET}"
  echo ""
}

render_queue_summary() {
  if [ ! -f "$QUEUE" ]; then
    echo -e "  ${DIM}(queue not initialized — run 'init' in Control)${RESET}"
    return
  fi

  local ready blocked in_prog passed failed total concurrency
  ready=$(jq '.queue.ready | length' "$QUEUE" 2>/dev/null)
  blocked=$(jq '.queue.blocked | length' "$QUEUE" 2>/dev/null)
  in_prog=$(jq '.queue.in_progress | length' "$QUEUE" 2>/dev/null)
  passed=$(jq '.queue.passed | length' "$QUEUE" 2>/dev/null)
  failed=$(jq '.queue.failed | length' "$QUEUE" 2>/dev/null)
  concurrency=$(jq '.concurrency // 3' "$QUEUE" 2>/dev/null)
  total=$((ready + blocked + in_prog + passed + failed))

  # Progress bar
  local pct=0
  if [ "$total" -gt 0 ]; then pct=$(( passed * 100 / total )); fi
  local bar_w=20 filled=$(( pct * bar_w / 100 )) empty=$(( bar_w - filled ))
  local bar=""
  for ((i=0; i<filled; i++)); do bar+="█"; done
  for ((i=0; i<empty; i++)); do bar+="░"; done

  echo -e "  ${BOLD}Queue${RESET}  ${bar}  ${passed}/${total} (${pct}%)  ${DIM}concurrency=${concurrency}${RESET}"
  echo -e "  Ready:${GREEN}${ready}${RESET}  Blocked:${YELLOW}${blocked}${RESET}  Progress:${CYAN}${in_prog}${RESET}  Pass:${GREEN}${passed}${RESET}  Fail:${RED}${failed}${RESET}"
  echo ""
}

render_teams() {
  if [ ! -f "$QUEUE" ]; then return; fi

  local team_count
  team_count=$(jq '.teams | length' "$QUEUE" 2>/dev/null)
  if [ "${team_count:-0}" -eq 0 ]; then return; fi

  echo -e "  ${BOLD}Teams${RESET}"

  for i in $(seq 1 "$team_count"); do
    local t_status t_feature t_phase t_attempt
    t_status=$(jq -r ".teams[\"$i\"].status // \"idle\"" "$QUEUE" 2>/dev/null)
    t_feature=$(jq -r ".teams[\"$i\"].feature // \"—\"" "$QUEUE" 2>/dev/null)

    # Get phase from in_progress
    if [ "$t_feature" != "—" ] && [ "$t_feature" != "null" ]; then
      t_phase=$(jq -r --arg f "$t_feature" '.queue.in_progress[$f].phase // "?"' "$QUEUE" 2>/dev/null)
      t_attempt=$(jq -r --arg f "$t_feature" '.queue.in_progress[$f].attempt // 1' "$QUEUE" 2>/dev/null)
    else
      t_phase="—"
      t_attempt="—"
    fi

    local icon color
    case "$t_status" in
      busy)   icon="▶" ; color="$GREEN" ;;
      idle)   icon="○" ; color="$DIM" ;;
      paused) icon="⏸" ; color="$YELLOW" ;;
      *)      icon="?" ; color="$RESET" ;;
    esac

    local phase_display=""
    case "$t_phase" in
      gen)  phase_display="${CYAN}GEN${RESET}" ;;
      gate) phase_display="${YELLOW}GATE${RESET}" ;;
      eval) phase_display="${MAGENTA}EVAL${RESET}" ;;
      *)    phase_display="${DIM}${t_phase}${RESET}" ;;
    esac

    printf "  %b %b Team %d  %-8s %b  attempt %s\n" "$color" "$icon" "$i" "$t_feature" "$phase_display" "$t_attempt"
  done
  echo ""
}

render_feature_list() {
  if [ ! -f "$QUEUE" ] || [ ! -f "$FEATURES" ]; then return; fi

  local total
  total=$(jq '.features | length' "$FEATURES" 2>/dev/null)
  if [ "${total:-0}" -eq 0 ]; then return; fi

  echo -e "  ${BOLD}Features${RESET}"

  local i=0
  while [ "$i" -lt "$total" ]; do
    local fid fname status_icon
    fid=$(jq -r ".features[$i].id" "$FEATURES" 2>/dev/null)
    fname=$(jq -r ".features[$i].name // .features[$i].description // \"\"" "$FEATURES" 2>/dev/null)
    if [ ${#fname} -gt 22 ]; then fname="${fname:0:20}.."; fi

    # Determine status from queue
    local in_passed in_failed in_progress in_ready in_blocked
    in_passed=$(jq -r --arg f "$fid" '.queue.passed // [] | map(select(. == $f)) | length' "$QUEUE" 2>/dev/null)
    in_failed=$(jq -r --arg f "$fid" '.queue.failed // [] | map(select(. == $f)) | length' "$QUEUE" 2>/dev/null)
    in_progress=$(jq -r --arg f "$fid" '.queue.in_progress[$f] // empty' "$QUEUE" 2>/dev/null)
    in_ready=$(jq -r --arg f "$fid" '.queue.ready // [] | map(select(. == $f)) | length' "$QUEUE" 2>/dev/null)

    if [ "${in_passed:-0}" -gt 0 ]; then
      status_icon="${GREEN}●${RESET}"
    elif [ -n "$in_progress" ] && [ "$in_progress" != "" ]; then
      local team phase
      team=$(echo "$in_progress" | jq -r '.team // "?"' 2>/dev/null)
      phase=$(echo "$in_progress" | jq -r '.phase // "?"' 2>/dev/null)
      status_icon="${CYAN}◐${RESET} T${team}:${phase}"
    elif [ "${in_failed:-0}" -gt 0 ]; then
      status_icon="${RED}✗${RESET}"
    elif [ "${in_ready:-0}" -gt 0 ]; then
      status_icon="${YELLOW}○${RESET}"
    else
      status_icon="${DIM}◌${RESET}"  # blocked
    fi

    printf "  %b %-6s %-24s\n" "$status_icon" "$fid" "$fname"

    i=$((i + 1))
  done
  echo ""
}

render_all() {
  render_header
  render_queue_summary
  render_teams
  render_feature_list
  echo -e "  ${DIM}Refreshing every 3s${RESET}"
}

# ── Main loop ──
tput civis 2>/dev/null
trap 'tput cnorm 2>/dev/null; exit 0' EXIT INT TERM

clear

while true; do
  local buf
  buf=$(render_all 2>/dev/null)
  tput cup 0 0 2>/dev/null
  echo "$buf"
  tput ed 2>/dev/null
  sleep 3
done
