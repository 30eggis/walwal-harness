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
  ready=$(jq '.queue.ready | length' "$QUEUE" 2>/dev/null || echo 0)
  blocked=$(jq '.queue.blocked | length' "$QUEUE" 2>/dev/null || echo 0)
  in_prog=$(jq '.queue.in_progress | length' "$QUEUE" 2>/dev/null || echo 0)
  passed=$(jq '.queue.passed | length' "$QUEUE" 2>/dev/null || echo 0)
  failed=$(jq '.queue.failed | length' "$QUEUE" 2>/dev/null || echo 0)
  concurrency=$(jq '.concurrency // 3' "$QUEUE" 2>/dev/null || echo 3)
  ready=${ready:-0}; blocked=${blocked:-0}; in_prog=${in_prog:-0}; passed=${passed:-0}; failed=${failed:-0}
  total=$((ready + blocked + in_prog + passed + failed))

  # Progress bar
  local pct=0
  if [ "$total" -gt 0 ]; then pct=$(( passed * 100 / total )); fi
  local bar_w=20
  local filled=$(( pct * bar_w / 100 ))
  local empty=$(( bar_w - filled ))
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

  echo -e "  ${BOLD}Features${RESET}"

  # Single jq call: merge feature-list + queue state → pre-formatted lines
  jq -r --slurpfile q "$QUEUE" '
    ($q[0].queue.passed // []) as $passed |
    ($q[0].queue.failed // []) as $failed |
    ($q[0].queue.ready // []) as $ready |
    ($q[0].queue.in_progress // {}) as $prog |
    .features[] |
    .id as $fid |
    (.name // .description // "?" | if length > 22 then .[0:20] + ".." else . end) as $fname |
    (if ($fid | IN($passed[])) then "P"
     elif $prog[$fid] then "I|\($prog[$fid].team)|\($prog[$fid].phase)"
     elif ($fid | IN($failed[])) then "F"
     elif ($fid | IN($ready[])) then "R"
     else "B" end) as $st |
    "\($st)\t\($fid)\t\($fname)"
  ' "$FEATURES" 2>/dev/null | while IFS=$'\t' read -r st fid fname; do
    case "$st" in
      P)    printf "  ${GREEN}●${RESET} %-6s %s\n" "$fid" "$fname" ;;
      F)    printf "  ${RED}✗${RESET} %-6s %s\n" "$fid" "$fname" ;;
      R)    printf "  ${YELLOW}○${RESET} %-6s %s\n" "$fid" "$fname" ;;
      B)    printf "  ${DIM}◌${RESET} %-6s %s\n" "$fid" "$fname" ;;
      I\|*) # in_progress: extract team and phase
            team=$(echo "$st" | cut -d'|' -f2)
            phase=$(echo "$st" | cut -d'|' -f3)
            printf "  ${CYAN}◐${RESET} %-6s %-18s T%s:%s\n" "$fid" "$fname" "$team" "$phase" ;;
      *)    printf "  ? %-6s %s\n" "$fid" "$fname" ;;
    esac
  done

  echo ""
}

render_prompt_history() {
  local log_file="$PROJECT_ROOT/.harness/progress.log"
  if [ ! -f "$log_file" ]; then return; fi

  # Get terminal height to limit display
  local term_h
  term_h=$(tput lines 2>/dev/null || echo 50)
  local max_lines=10  # show latest 10 entries

  echo -e "  ${BOLD}Prompt History${RESET} ${DIM}(newest first)${RESET}"

  # Read non-comment lines, reverse (newest first), take max_lines
  grep -v '^#' "$log_file" 2>/dev/null | grep -v '^$' | tail -r 2>/dev/null | head -"$max_lines" | \
  while IFS= read -r line; do
    # Parse: date | agent | action | detail
    local ts agent action detail
    ts=$(echo "$line" | awk -F'|' '{gsub(/^ +| +$/,"",$1); print $1}')
    agent=$(echo "$line" | awk -F'|' '{gsub(/^ +| +$/,"",$2); print $2}')
    action=$(echo "$line" | awk -F'|' '{gsub(/^ +| +$/,"",$3); print $3}')
    detail=$(echo "$line" | awk -F'|' '{gsub(/^ +| +$/,"",$4); print $4}')

    local short_ts icon color
    short_ts=$(echo "$ts" | sed 's/^[0-9]*-//')

    case "$agent" in
      dispatcher*|dispatch) icon="▸"; color="$MAGENTA" ;;
      team-*)               icon="⚡"; color="$CYAN" ;;
      manual|user)          icon="★"; color="$BOLD" ;;
      planner*)             icon="□"; color="$YELLOW" ;;
      generator*|gen*)      icon="▶"; color="$GREEN" ;;
      eval*)                icon="✦"; color="$RED" ;;
      system)               icon="⚙"; color="$DIM" ;;
      *)                    icon="·"; color="$DIM" ;;
    esac

    if [ ${#detail} -gt 45 ]; then detail="${detail:0:43}.."; fi

    echo -e "  ${color}${icon}${RESET} ${DIM}${short_ts}${RESET} ${agent} ${DIM}${action}${RESET} ${detail}"
  done

  echo ""
}

render_all() {
  render_header
  render_queue_summary
  render_teams
  render_prompt_history
  render_feature_list
  echo -e "  ${DIM}Refreshing every 3s${RESET}"
}

# ── Main loop ──
tput civis 2>/dev/null
trap 'tput cnorm 2>/dev/null; exit 0' EXIT INT TERM

clear

while true; do
  buf=$(render_all 2>&1)
  tput cup 0 0 2>/dev/null
  echo "$buf"
  tput ed 2>/dev/null
  sleep 3
done
