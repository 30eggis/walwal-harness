#!/bin/bash
# harness-dashboard-v4.sh — v4 Dashboard 상단: Planner Progress
# Queue + Teams + Features 를 auto-refresh. 고정 영역, 스크롤 없음.

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

  echo -e "${BOLD}HARNESS v4${RESET} ${DIM}${project_name} | ${now}${RESET}"
}

render_queue_summary() {
  if [ ! -f "$QUEUE" ]; then
    echo -e "  ${DIM}(queue not initialized)${RESET}"
    return
  fi

  local ready blocked in_prog passed failed total
  ready=$(jq '.queue.ready | length' "$QUEUE" 2>/dev/null || echo 0)
  blocked=$(jq '.queue.blocked | length' "$QUEUE" 2>/dev/null || echo 0)
  in_prog=$(jq '.queue.in_progress | length' "$QUEUE" 2>/dev/null || echo 0)
  passed=$(jq '.queue.passed | length' "$QUEUE" 2>/dev/null || echo 0)
  failed=$(jq '.queue.failed | length' "$QUEUE" 2>/dev/null || echo 0)
  ready=${ready:-0}; blocked=${blocked:-0}; in_prog=${in_prog:-0}; passed=${passed:-0}; failed=${failed:-0}
  total=$((ready + blocked + in_prog + passed + failed))

  local pct=0
  if [ "$total" -gt 0 ]; then pct=$(( passed * 100 / total )); fi
  local bar_w=16
  local filled=$(( pct * bar_w / 100 ))
  local empty=$(( bar_w - filled ))
  local bar=""
  for ((i=0; i<filled; i++)); do bar+="█"; done
  for ((i=0; i<empty; i++)); do bar+="░"; done

  echo -e "  ${bar} ${passed}/${total} (${pct}%)  R:${GREEN}${ready}${RESET} B:${YELLOW}${blocked}${RESET} P:${CYAN}${in_prog}${RESET} ${GREEN}✓${passed}${RESET} ${RED}✗${failed}${RESET}"
}

render_teams() {
  if [ ! -f "$QUEUE" ]; then return; fi

  local team_count
  team_count=$(jq '.teams | length' "$QUEUE" 2>/dev/null)
  if [ "${team_count:-0}" -eq 0 ]; then return; fi

  for i in $(seq 1 "$team_count"); do
    local t_status t_feature t_phase t_attempt
    t_status=$(jq -r ".teams[\"$i\"].status // \"idle\"" "$QUEUE" 2>/dev/null)
    t_feature=$(jq -r ".teams[\"$i\"].feature // \"—\"" "$QUEUE" 2>/dev/null)

    if [ "$t_feature" != "—" ] && [ "$t_feature" != "null" ]; then
      t_phase=$(jq -r --arg f "$t_feature" '.queue.in_progress[$f].phase // "?"' "$QUEUE" 2>/dev/null)
      t_attempt=$(jq -r --arg f "$t_feature" '.queue.in_progress[$f].attempt // 1' "$QUEUE" 2>/dev/null)
    else
      t_phase="—"; t_attempt=""
    fi

    local icon color
    case "$t_status" in
      busy)   icon="▶"; color="$GREEN" ;;
      idle)   icon="○"; color="$DIM" ;;
      *)      icon="?"; color="$RESET" ;;
    esac

    local phase_short=""
    case "$t_phase" in
      gen)  phase_short="${CYAN}G${RESET}" ;;
      gate) phase_short="${YELLOW}K${RESET}" ;;
      eval) phase_short="${MAGENTA}E${RESET}" ;;
      *)    phase_short="${DIM}-${RESET}" ;;
    esac

    printf "  %b%b T%d %-7s %b" "$color" "$icon" "$i" "$t_feature" "$phase_short"
    if [ -n "$t_attempt" ] && [ "$t_attempt" != "—" ]; then
      printf " #%s" "$t_attempt"
    fi
    echo ""
  done
}

render_features() {
  if [ ! -f "$QUEUE" ] || [ ! -f "$FEATURES" ]; then return; fi

  jq -r --slurpfile q "$QUEUE" '
    ($q[0].queue.passed // []) as $passed |
    ($q[0].queue.failed // []) as $failed |
    ($q[0].queue.ready // []) as $ready |
    ($q[0].queue.in_progress // {}) as $prog |
    .features[] |
    .id as $fid |
    (.name // .description // "?" | if length > 18 then .[0:16] + ".." else . end) as $fname |
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
      I\|*) team=$(echo "$st" | cut -d'|' -f2)
            phase=$(echo "$st" | cut -d'|' -f3)
            printf "  ${CYAN}◐${RESET} %-6s %-14s T%s:%s\n" "$fid" "$fname" "$team" "$phase" ;;
      *)    printf "  ? %-6s %s\n" "$fid" "$fname" ;;
    esac
  done
}

render_all() {
  render_header
  render_queue_summary
  render_teams
  echo ""
  render_features
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
