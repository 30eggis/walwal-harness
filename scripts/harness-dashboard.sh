#!/bin/bash
# harness-dashboard.sh — Control Center: Dashboard + Manual Prompt
#
# 상단: 실시간 대시보드 (Sprint Map | Prompt History + Processing Status)
# 하단: 사용자 명령 입력 (오케스트레이션)
#
# Commands:
#   status / s      대시보드 즉시 갱신
#   next / n        다음 에이전트 세션 시작 (Agent Session pane으로 전달)
#   retry / r       현재 에이전트 재실행
#   stop            에이전트 세션 중지
#   log <message>   progress.log에 수동 메모 추가
#   clear-fail      failure 상태 클리어
#   quit / q        대시보드 종료
#
# Usage: bash scripts/harness-dashboard.sh [project-root]

set -uo pipefail

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

# ── Strip ANSI escape sequences ──
strip_ansi() {
  sed 's/\x1b\[[0-9;]*m//g; s/\x1b\[[0-9;]*[a-zA-Z]//g'
}

get_term_width() {
  tput cols 2>/dev/null || echo 80
}

# ══════════════════════════════════════════
# Render functions
# ══════════════════════════════════════════

render_header() {
  local now project_name
  now=$(date +"%H:%M:%S")
  project_name=$(jq -r '.project_name // "Unknown"' "$PROGRESS" 2>/dev/null)

  echo -e "${BOLD}╔══════════════════════════════════════════════════════╗${RESET}"
  echo -e "${BOLD}║  HARNESS CONTROL CENTER                              ║${RESET}"
  echo -e "${BOLD}╚══════════════════════════════════════════════════════╝${RESET}"
  echo -e "  ${DIM}${project_name}  |  ${now}${RESET}"
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

  echo -e "  ${BOLD}Pipeline${RESET} ${pipeline}  ${BOLD}Sprint${RESET} ${sprint_num} (${sprint_status})  ${BOLD}Agent${RESET} ${status_color}${current_agent} [${agent_status}]${RESET}$([ "$retry_count" -gt 0 ] && echo -e "  ${RED}R${retry_count}${RESET}")"
  echo ""
}

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

    if [ ${#notes} -gt 28 ]; then notes="${notes:0:26}.."; fi

    printf "%s S%-2s %2df %-11s %s\n" "$icon" "$s" "$feat_count" "$status" "$notes"
  done <<< "$sprint_keys"
}

render_prompt_history_lines() {
  echo -e "${BOLD}Prompt History${RESET}"

  if [ -f "$PROGRESS_LOG" ]; then
    grep -v '^#' "$PROGRESS_LOG" 2>/dev/null | grep -v '^$' | tail -12 | while IFS= read -r line; do
      local ts agent action detail
      ts=$(echo "$line" | awk -F'|' '{gsub(/^ +| +$/,"",$1); print $1}')
      agent=$(echo "$line" | awk -F'|' '{gsub(/^ +| +$/,"",$2); print $2}')
      action=$(echo "$line" | awk -F'|' '{gsub(/^ +| +$/,"",$3); print $3}')
      detail=$(echo "$line" | awk -F'|' '{gsub(/^ +| +$/,"",$4); print $4}')

      local short_ts icon color
      short_ts=$(echo "$ts" | sed 's/^[0-9]*-//')

      case "$agent" in
        dispatcher*)  icon="▸" ; color="$MAGENTA" ;;
        brainstormer) icon="◇" ; color="$CYAN" ;;
        planner*)     icon="□" ; color="$YELLOW" ;;
        generator*)   icon="▶" ; color="$GREEN" ;;
        eval*)        icon="✦" ; color="$RED" ;;
        user|manual)  icon="★" ; color="$BOLD" ;;
        *)            icon="·" ; color="$DIM" ;;
      esac

      if [ ${#detail} -gt 30 ]; then detail="${detail:0:28}.."; fi

      echo -e "${color}${icon}${RESET} ${DIM}${short_ts}${RESET} ${agent} ${DIM}${action}${RESET}"
      if [ -n "$detail" ]; then
        echo -e "  ${DIM}${detail}${RESET}"
      fi
    done
  else
    echo -e "${DIM}(no progress.log yet)${RESET}"
  fi
}

render_two_columns() {
  local term_width col_width
  term_width=$(get_term_width)
  col_width=$(( (term_width - 7) / 2 ))
  if [ "$col_width" -lt 30 ]; then col_width=30; fi
  if [ "$col_width" -gt 55 ]; then col_width=55; fi

  local left_lines=() right_lines=()

  while IFS= read -r line; do
    left_lines+=("$line")
  done < <(render_sprint_map_lines 2>/dev/null)

  while IFS= read -r line; do
    right_lines+=("$line")
  done < <(render_prompt_history_lines 2>/dev/null)

  local left_count=${#left_lines[@]}
  local right_count=${#right_lines[@]}
  local max_rows=$left_count
  if [ "$right_count" -gt "$max_rows" ]; then max_rows=$right_count; fi

  local sep=""
  for ((i=0; i<term_width-4; i++)); do sep+="─"; done
  echo -e "  ${DIM}${sep}${RESET}"

  for ((i=0; i<max_rows; i++)); do
    local left_text="${left_lines[$i]:-}"
    local right_text="${right_lines[$i]:-}"

    local left_plain
    left_plain=$(echo -e "$left_text" | strip_ansi)
    local left_len=${#left_plain}
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

render_failure_info() {
  if [ ! -f "$PROGRESS" ]; then return; fi

  local failure_agent
  failure_agent=$(jq -r '.failure.agent // empty' "$PROGRESS" 2>/dev/null)

  if [ -n "$failure_agent" ] && [ "$failure_agent" != "null" ]; then
    local failure_loc failure_msg
    failure_loc=$(jq -r '.failure.location // ""' "$PROGRESS")
    failure_msg=$(jq -r '.failure.message // ""' "$PROGRESS" | strip_ansi | tr '\n' ' ' | sed 's/  */ /g')
    if [ ${#failure_msg} -gt 80 ]; then failure_msg="${failure_msg:0:78}.."; fi

    echo -e "  ${RED}${BOLD}FAIL${RESET} ${RED}${failure_agent} → ${failure_loc}${RESET}"
    if [ -n "$failure_msg" ]; then
      echo -e "  ${DIM}${failure_msg}${RESET}"
    fi
    echo ""
  fi
}

render_agent_info() {
  # Next action hint
  if [ ! -f "$PROGRESS" ]; then return; fi

  local next_agent agent_status
  next_agent=$(jq -r '.next_agent // "none"' "$PROGRESS" 2>/dev/null)
  agent_status=$(jq -r '.agent_status // "pending"' "$PROGRESS" 2>/dev/null)

  if [ "$next_agent" != "none" ] && [ "$next_agent" != "null" ] && [ "$agent_status" != "blocked" ]; then
    echo -e "  ${CYAN}Next → ${next_agent}${RESET}  ${DIM}(type 'next' to start)${RESET}"
  fi

  # Agent bar
  render_agent_bar "$PROJECT_ROOT" 2>/dev/null
  echo ""
}

# ══════════════════════════════════════════
# Full dashboard render
# ══════════════════════════════════════════
render_dashboard() {
  tput cup 0 0 2>/dev/null
  tput civis 2>/dev/null

  local buf
  buf=$(
    render_header
    render_sprint_overview
    render_build_status
    render_failure_info
    render_two_columns

    if [ -f "$FEATURES" ]; then
      render_progress "$PROJECT_ROOT" 2>/dev/null
    fi

    render_agent_info
  )
  echo "$buf"
  tput ed 2>/dev/null
  tput cnorm 2>/dev/null
}

# ══════════════════════════════════════════
# Command handlers
# ══════════════════════════════════════════

cmd_log() {
  local msg="$1"
  if [ -z "$msg" ]; then
    echo -e "  ${RED}Usage: log <message>${RESET}"
    return
  fi

  local ts
  ts=$(date +"%Y-%m-%d")
  echo "${ts} | manual | note | ${msg}" >> "$PROGRESS_LOG"
  echo -e "  ${GREEN}Logged:${RESET} ${msg}"
}

cmd_clear_fail() {
  if [ ! -f "$PROGRESS" ]; then return; fi

  jq '.failure = {agent: null, location: null, message: null, retry_target: null} |
      .sprint.status = "in_progress" |
      .sprint.retry_count = 0 |
      .agent_status = "completed"' "$PROGRESS" > "${PROGRESS}.tmp" && mv "${PROGRESS}.tmp" "$PROGRESS"
  echo -e "  ${GREEN}Failure state cleared.${RESET}"
}

cmd_next() {
  # Find the Agent Session pane and send the next agent command
  local tmux_target="harness-studio.2"  # Agent Session pane

  if ! tmux list-panes -t harness-studio 2>/dev/null | grep -q .; then
    echo -e "  ${RED}tmux session not found. Run inside harness-studio.${RESET}"
    return
  fi

  local next_agent
  next_agent=$(jq -r '.next_agent // "none"' "$PROGRESS" 2>/dev/null)

  if [ "$next_agent" = "none" ] || [ "$next_agent" = "null" ]; then
    echo -e "  ${YELLOW}No next agent in queue.${RESET}"
    return
  fi

  echo -e "  ${CYAN}Starting ${next_agent} in Agent Session pane...${RESET}"

  # Log the manual intervention
  local ts
  ts=$(date +"%Y-%m-%d")
  echo "${ts} | manual | start-agent | ${next_agent}" >> "$PROGRESS_LOG"

  # Send command to Agent Session pane
  tmux send-keys -t "$tmux_target" "/harness-${next_agent}" Enter
}

cmd_retry() {
  local tmux_target="harness-studio.2"

  if ! tmux list-panes -t harness-studio 2>/dev/null | grep -q .; then
    echo -e "  ${RED}tmux session not found.${RESET}"
    return
  fi

  local current_agent
  current_agent=$(jq -r '.current_agent // "none"' "$PROGRESS" 2>/dev/null)

  if [ "$current_agent" = "none" ] || [ "$current_agent" = "null" ]; then
    echo -e "  ${YELLOW}No current agent to retry.${RESET}"
    return
  fi

  echo -e "  ${CYAN}Retrying ${current_agent} in Agent Session pane...${RESET}"

  local ts
  ts=$(date +"%Y-%m-%d")
  echo "${ts} | manual | retry | ${current_agent}" >> "$PROGRESS_LOG"

  tmux send-keys -t "$tmux_target" "/harness-${current_agent}" Enter
}

cmd_stop() {
  local tmux_target="harness-studio.2"

  if ! tmux list-panes -t harness-studio 2>/dev/null | grep -q .; then
    echo -e "  ${RED}tmux session not found.${RESET}"
    return
  fi

  echo -e "  ${YELLOW}Sending Ctrl+C to Agent Session...${RESET}"
  tmux send-keys -t "$tmux_target" C-c

  local ts
  ts=$(date +"%Y-%m-%d")
  echo "${ts} | manual | stop | user-initiated" >> "$PROGRESS_LOG"
}

show_help() {
  echo ""
  echo -e "  ${BOLD}Commands${RESET}"
  echo -e "  ${CYAN}status${RESET} / ${CYAN}s${RESET}          Refresh dashboard"
  echo -e "  ${CYAN}next${RESET}   / ${CYAN}n${RESET}          Start next agent in Agent Session"
  echo -e "  ${CYAN}retry${RESET}  / ${CYAN}r${RESET}          Retry current agent"
  echo -e "  ${CYAN}stop${RESET}              Send Ctrl+C to Agent Session"
  echo -e "  ${CYAN}log${RESET} <message>     Add note to progress.log"
  echo -e "  ${CYAN}clear-fail${RESET}        Clear failure state"
  echo -e "  ${CYAN}help${RESET}  / ${CYAN}h${RESET}          Show this help"
  echo -e "  ${CYAN}quit${RESET}  / ${CYAN}q${RESET}          Exit dashboard"
  echo ""
}

# ══════════════════════════════════════════
# Main — Interactive loop
# ══════════════════════════════════════════
clear
render_dashboard

echo ""
echo -e "  ${DIM}Type 'help' for commands. Dashboard auto-refreshes every 5s.${RESET}"
echo ""

# Background auto-refresh
(
  while true; do
    sleep 5
    # Signal main process to refresh
    kill -USR1 $$ 2>/dev/null || exit 0
  done
) &
REFRESH_PID=$!

# Trap USR1 to refresh dashboard
trap 'render_dashboard' USR1
trap 'kill $REFRESH_PID 2>/dev/null; exit 0' EXIT INT TERM

while true; do
  echo -ne "  ${BOLD}harness>${RESET} "
  # Read with timeout so USR1 can interrupt
  if read -t 5 -r input; then
    # Trim whitespace
    input=$(echo "$input" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    case "$input" in
      status|s)
        render_dashboard
        ;;
      next|n)
        cmd_next
        ;;
      retry|r)
        cmd_retry
        ;;
      stop)
        cmd_stop
        ;;
      log\ *)
        cmd_log "${input#log }"
        ;;
      clear-fail)
        cmd_clear_fail
        ;;
      help|h)
        show_help
        ;;
      quit|q)
        echo -e "  ${DIM}Goodbye.${RESET}"
        exit 0
        ;;
      "")
        # Empty input — just refresh
        render_dashboard
        ;;
      *)
        # Unknown command — treat as manual note
        echo -e "  ${DIM}Unknown command. Logging as note.${RESET}"
        cmd_log "$input"
        ;;
    esac
  else
    # Timeout — auto-refresh
    render_dashboard
  fi
done
