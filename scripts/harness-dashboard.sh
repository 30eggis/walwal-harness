#!/bin/bash
# harness-dashboard.sh — Panel 1: 실시간 대시보드
# progress.json + feature-list.json + progress.log 를 2초 간격으로 시각화
#
# Layout:
#   ┌─────────────────────┬──────────────────────┐
#   │  Sprint Map         │  Prompt History       │
#   ├─────────────────────┴──────────────────────┤
#   │  Processing Status (features, agent bar)    │
#   └────────────────────────────────────────────┘
#
# Usage: bash scripts/harness-dashboard.sh [project-root]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/harness-render-progress.sh"

PROJECT_ROOT="${1:-}"
if [ -z "$PROJECT_ROOT" ]; then
  PROJECT_ROOT="$(resolve_harness_root ".")" || {
    echo "[dashboard] .harness/ not found. Pass project root as argument."
    exit 1
  }
fi

PROGRESS="$PROJECT_ROOT/.harness/progress.json"
FEATURES="$PROJECT_ROOT/.harness/actions/feature-list.json"
PROGRESS_LOG="$PROJECT_ROOT/.harness/progress.log"

# ── ANSI helpers ──
BOLD="\033[1m"
DIM="\033[2m"
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
CYAN="\033[36m"
MAGENTA="\033[35m"
RESET="\033[0m"

# ── Get terminal width for column layout ──
get_term_width() {
  tput cols 2>/dev/null || echo 80
}

render_header() {
  local now
  now=$(date +"%H:%M:%S")
  local project_name
  project_name=$(jq -r '.project_name // "Unknown"' "$PROGRESS" 2>/dev/null)

  echo -e "${BOLD}╔══════════════════════════════════════╗${RESET}"
  echo -e "${BOLD}║  HARNESS DASHBOARD                   ║${RESET}"
  echo -e "${BOLD}╚══════════════════════════════════════╝${RESET}"
  echo -e "  ${DIM}${project_name}  |  Updated: ${now}${RESET}"
  echo ""
}

render_sprint_overview() {
  if [ ! -f "$PROGRESS" ]; then
    echo -e "  ${DIM}(waiting for harness init...)${RESET}"
    return
  fi

  local pipeline sprint_num sprint_status current_agent agent_status retry_count
  pipeline=$(jq -r '.pipeline // "?"' "$PROGRESS")
  sprint_num=$(jq -r '.sprint.number // 0' "$PROGRESS")
  sprint_status=$(jq -r '.sprint.status // "init"' "$PROGRESS")
  current_agent=$(jq -r '.current_agent // "none"' "$PROGRESS")
  agent_status=$(jq -r '.agent_status // "pending"' "$PROGRESS")
  retry_count=$(jq -r '.sprint.retry_count // 0' "$PROGRESS")

  local status_color="$RESET"
  case "$agent_status" in
    running)   status_color="$GREEN" ;;
    completed) status_color="$CYAN" ;;
    failed)    status_color="$RED" ;;
    blocked)   status_color="$RED" ;;
    *)         status_color="$YELLOW" ;;
  esac

  echo -e "  ${BOLD}Pipeline${RESET}  ${pipeline}  |  ${BOLD}Sprint${RESET}  ${sprint_num} (${sprint_status})  |  ${BOLD}Agent${RESET}  ${status_color}${current_agent} [${agent_status}]${RESET}$([ "$retry_count" -gt 0 ] && echo -e "  |  ${RED}R${retry_count}${RESET}")"
  echo ""
}

# ── Sprint Map column (left) ──
render_sprint_map_lines() {
  if [ ! -f "$PROGRESS" ]; then return; fi

  local sprint_keys
  sprint_keys=$(jq -r '.sprint_progress // {} | keys[]' "$PROGRESS" 2>/dev/null | sort -n)
  if [ -z "$sprint_keys" ]; then return; fi

  echo -e "${BOLD}Sprint Map${RESET}"

  while IFS= read -r s; do
    local status feat_count notes icon
    status=$(jq -r ".sprint_progress[\"${s}\"].status // \"pending\"" "$PROGRESS")
    feat_count=$(jq ".sprint_progress[\"${s}\"].features // [] | length" "$PROGRESS")
    notes=$(jq -r ".sprint_progress[\"${s}\"].notes // \"\"" "$PROGRESS")

    case "$status" in
      completed)   icon="●" ;;
      in_progress) icon="◐" ;;
      scaffolded)  icon="◑" ;;
      *)           icon="○" ;;
    esac

    if [ ${#notes} -gt 28 ]; then
      notes="${notes:0:26}.."
    fi

    printf "%s S%-2s %2df %-11s %s\n" "$icon" "$s" "$feat_count" "$status" "$notes"
  done <<< "$sprint_keys"
}

# ── Prompt History column (right) ──
render_prompt_history_lines() {
  echo -e "${BOLD}Prompt History${RESET}"

  # Source 1: progress.log (user/dispatcher interventions)
  if [ -f "$PROGRESS_LOG" ]; then
    grep -v '^#' "$PROGRESS_LOG" | grep -v '^$' | tail -15 | while IFS= read -r line; do
      # Format: 2026-04-13 | agent | action | detail
      local ts agent action detail
      ts=$(echo "$line" | awk -F'|' '{gsub(/^ +| +$/,"",$1); print $1}')
      agent=$(echo "$line" | awk -F'|' '{gsub(/^ +| +$/,"",$2); print $2}')
      action=$(echo "$line" | awk -F'|' '{gsub(/^ +| +$/,"",$3); print $3}')
      detail=$(echo "$line" | awk -F'|' '{gsub(/^ +| +$/,"",$4); print $4}')

      # Short date (MM-DD)
      local short_ts
      short_ts=$(echo "$ts" | sed 's/^[0-9]*-//')

      # Icon by agent/action
      local icon color
      case "$agent" in
        dispatcher*)  icon="▸" ; color="$MAGENTA" ;;
        brainstormer) icon="◇" ; color="$CYAN" ;;
        planner*)     icon="□" ; color="$YELLOW" ;;
        generator*)   icon="▶" ; color="$GREEN" ;;
        eval*)        icon="✦" ; color="$RED" ;;
        *)            icon="·" ; color="$DIM" ;;
      esac

      # Truncate detail
      if [ ${#detail} -gt 35 ]; then
        detail="${detail:0:33}.."
      fi

      echo -e "${color}${icon}${RESET} ${DIM}${short_ts}${RESET} ${agent} ${DIM}${action}${RESET}"
      if [ -n "$detail" ]; then
        echo -e "  ${DIM}${detail}${RESET}"
      fi
    done
  else
    echo -e "${DIM}(no progress.log yet)${RESET}"
  fi
}

# ── Side-by-side rendering ──
render_two_columns() {
  local term_width
  term_width=$(get_term_width)
  local col_width=$(( (term_width - 7) / 2 ))  # 7 = indent(4) + separator(3)
  if [ "$col_width" -lt 30 ]; then col_width=30; fi
  if [ "$col_width" -gt 60 ]; then col_width=60; fi

  # Capture each column into temp arrays
  local left_lines=()
  local right_lines=()

  while IFS= read -r line; do
    left_lines+=("$line")
  done < <(render_sprint_map_lines 2>/dev/null)

  while IFS= read -r line; do
    right_lines+=("$line")
  done < <(render_prompt_history_lines 2>/dev/null)

  # Determine max rows
  local left_count=${#left_lines[@]}
  local right_count=${#right_lines[@]}
  local max_rows=$left_count
  if [ "$right_count" -gt "$max_rows" ]; then max_rows=$right_count; fi

  # Print separator
  local sep=""
  for ((i=0; i<term_width-4; i++)); do sep+="─"; done
  echo -e "  ${DIM}${sep}${RESET}"

  # Print rows side by side
  for ((i=0; i<max_rows; i++)); do
    local left_text="${left_lines[$i]:-}"
    local right_text="${right_lines[$i]:-}"

    # Strip ANSI for length calculation
    local left_plain
    left_plain=$(echo -e "$left_text" | sed 's/\x1b\[[0-9;]*m//g')
    local left_len=${#left_plain}

    # Pad left column
    local pad_needed=$(( col_width - left_len ))
    if [ "$pad_needed" -lt 0 ]; then pad_needed=0; fi
    local padding=""
    for ((p=0; p<pad_needed; p++)); do padding+=" "; done

    echo -e "  ${left_text}${padding} ${DIM}│${RESET} ${right_text}"
  done

  echo -e "  ${DIM}${sep}${RESET}"
  echo ""
}

render_build_status() {
  if [ ! -f "$PROGRESS" ]; then return; fi

  local build_status tsc_status routes_total
  build_status=$(jq -r '.build.build_status // "unknown"' "$PROGRESS" 2>/dev/null)
  tsc_status=$(jq -r '.build.tsc_status // "unknown"' "$PROGRESS" 2>/dev/null)
  routes_total=$(jq -r '.build.routes_total // 0' "$PROGRESS" 2>/dev/null)

  if [ "$build_status" = "null" ] || [ "$build_status" = "unknown" ]; then return; fi

  local build_color="$GREEN"
  if [ "$build_status" != "passing" ]; then build_color="$RED"; fi
  local tsc_color="$GREEN"
  if [ "$tsc_status" != "clean" ]; then tsc_color="$RED"; fi

  echo -e "  ${BOLD}Build${RESET}  ${build_color}${build_status}${RESET}  |  TSC: ${tsc_color}${tsc_status}${RESET}  |  Routes: ${routes_total}"
  echo ""
}

# Strip all ANSI escape sequences from a string
strip_ansi() {
  sed 's/\x1b\[[0-9;]*m//g; s/\x1b\[[0-9;]*[a-zA-Z]//g'
}

render_failure_info() {
  if [ ! -f "$PROGRESS" ]; then return; fi

  local failure_agent
  failure_agent=$(jq -r '.failure.agent // empty' "$PROGRESS" 2>/dev/null)

  if [ -n "$failure_agent" ] && [ "$failure_agent" != "null" ]; then
    local failure_loc failure_msg
    failure_loc=$(jq -r '.failure.location // ""' "$PROGRESS")
    # Get raw message, strip ANSI codes, take first meaningful line
    failure_msg=$(jq -r '.failure.message // ""' "$PROGRESS" | strip_ansi | tr '\n' ' ' | sed 's/  */ /g')

    # Truncate to 80 chars
    if [ ${#failure_msg} -gt 80 ]; then
      failure_msg="${failure_msg:0:78}.."
    fi

    echo -e "  ${RED}${BOLD}FAIL${RESET} ${RED}${failure_agent} → ${failure_loc}${RESET}"
    if [ -n "$failure_msg" ]; then
      echo -e "  ${DIM}${failure_msg}${RESET}"
    fi
    echo ""
  fi
}

# ── Render all sections ──
render_all() {
  render_header
  render_sprint_overview
  render_build_status
  render_failure_info

  # Two-column: Sprint Map | Prompt History
  render_two_columns

  # Feature progress (reuse existing lib)
  if [ -f "$FEATURES" ]; then
    render_progress "$PROJECT_ROOT" 2>/dev/null
  fi

  # Agent sequence bar
  render_agent_bar "$PROJECT_ROOT" 2>/dev/null
  echo ""

  echo -e "  ${DIM}Refreshing every 2s  |  Ctrl+C to exit${RESET}"
}

# ── Main Loop ──
tput civis 2>/dev/null
trap 'tput cnorm 2>/dev/null; exit 0' EXIT INT TERM

clear

while true; do
  buf=$(render_all 2>/dev/null)
  tput cup 0 0 2>/dev/null
  echo "$buf"
  tput ed 2>/dev/null
  sleep 2
done
