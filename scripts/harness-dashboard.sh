#!/bin/bash
# harness-dashboard.sh — Panel 1: 실시간 대시보드
# progress.json + feature-list.json 을 2초 간격으로 시각화
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

# ── ANSI helpers ──
BOLD="\033[1m"
DIM="\033[2m"
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
CYAN="\033[36m"
RESET="\033[0m"

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

  # Status color
  local status_color="$RESET"
  case "$agent_status" in
    running)   status_color="$GREEN" ;;
    completed) status_color="$CYAN" ;;
    failed)    status_color="$RED" ;;
    blocked)   status_color="$RED" ;;
    *)         status_color="$YELLOW" ;;
  esac

  echo -e "  ${BOLD}Pipeline${RESET}  ${pipeline}"
  echo -e "  ${BOLD}Sprint${RESET}    ${sprint_num} (${sprint_status})"
  echo -e "  ${BOLD}Agent${RESET}     ${status_color}${current_agent} [${agent_status}]${RESET}"
  if [ "$retry_count" -gt 0 ]; then
    echo -e "  ${BOLD}Retries${RESET}   ${RED}${retry_count}${RESET}"
  fi
  echo ""
}

render_sprint_map() {
  if [ ! -f "$PROGRESS" ]; then return; fi

  local sprint_keys
  sprint_keys=$(jq -r '.sprint_progress // {} | keys[]' "$PROGRESS" 2>/dev/null | sort -n)
  if [ -z "$sprint_keys" ]; then return; fi

  echo -e "  ${BOLD}Sprint Map${RESET}"

  while IFS= read -r s; do
    local status features_csv notes
    status=$(jq -r ".sprint_progress[\"${s}\"].status // \"pending\"" "$PROGRESS")
    features_csv=$(jq -r ".sprint_progress[\"${s}\"].features // [] | join(\",\")" "$PROGRESS")
    notes=$(jq -r ".sprint_progress[\"${s}\"].notes // \"\"" "$PROGRESS")

    # Status icon
    local icon="○"
    case "$status" in
      completed)   icon="●" ;;
      in_progress) icon="◐" ;;
      scaffolded)  icon="◑" ;;
      pending)     icon="○" ;;
    esac

    # Count features
    local feat_count
    feat_count=$(jq ".sprint_progress[\"${s}\"].features // [] | length" "$PROGRESS")

    # Truncate notes
    if [ ${#notes} -gt 40 ]; then
      notes="${notes:0:38}.."
    fi

    printf "  %s S%-2s  %2d feat  %-12s %s\n" "$icon" "$s" "$feat_count" "$status" "$notes"
  done <<< "$sprint_keys"

  echo ""
}

render_build_status() {
  if [ ! -f "$PROGRESS" ]; then return; fi

  local build_status tsc_status routes_total last_build
  build_status=$(jq -r '.build.build_status // "unknown"' "$PROGRESS" 2>/dev/null)
  tsc_status=$(jq -r '.build.tsc_status // "unknown"' "$PROGRESS" 2>/dev/null)
  routes_total=$(jq -r '.build.routes_total // 0' "$PROGRESS" 2>/dev/null)
  last_build=$(jq -r '.build.last_build // "n/a"' "$PROGRESS" 2>/dev/null)

  if [ "$build_status" = "null" ] || [ "$build_status" = "unknown" ]; then return; fi

  local build_color="$GREEN"
  if [ "$build_status" != "passing" ]; then build_color="$RED"; fi
  local tsc_color="$GREEN"
  if [ "$tsc_status" != "clean" ]; then tsc_color="$RED"; fi

  echo -e "  ${BOLD}Build${RESET}"
  echo -e "  Build: ${build_color}${build_status}${RESET}  |  TSC: ${tsc_color}${tsc_status}${RESET}  |  Routes: ${routes_total}"
  echo ""
}

render_failure_info() {
  if [ ! -f "$PROGRESS" ]; then return; fi

  local failure_agent
  failure_agent=$(jq -r '.failure.agent // empty' "$PROGRESS" 2>/dev/null)

  if [ -n "$failure_agent" ] && [ "$failure_agent" != "null" ]; then
    local failure_loc failure_msg
    failure_loc=$(jq -r '.failure.location // ""' "$PROGRESS")
    failure_msg=$(jq -r '.failure.message // ""' "$PROGRESS")

    echo -e "  ${RED}${BOLD}╔═ FAILURE ═══════════════════════════╗${RESET}"
    echo -e "  ${RED}  Agent: ${failure_agent}${RESET}"
    echo -e "  ${RED}  Where: ${failure_loc}${RESET}"
    if [ -n "$failure_msg" ] && [ "$failure_msg" != "null" ]; then
      echo -e "  ${RED}  ${failure_msg}${RESET}"
    fi
    echo -e "  ${RED}${BOLD}╚════════════════════════════════════╝${RESET}"
    echo ""
  fi
}

# ── Main Loop ──
while true; do
  clear
  render_header
  render_sprint_overview
  render_build_status
  render_failure_info
  render_sprint_map

  # Feature progress (reuse existing lib)
  if [ -f "$FEATURES" ]; then
    render_progress "$PROJECT_ROOT" 2>/dev/null
  fi

  # Agent sequence bar
  render_agent_bar "$PROJECT_ROOT" 2>/dev/null
  echo ""

  echo -e "  ${DIM}Refreshing every 2s  |  Ctrl+C to exit${RESET}"
  sleep 2
done
