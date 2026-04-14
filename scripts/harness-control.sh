#!/bin/bash
# harness-control.sh — Control Center 프롬프트 (하단)
# 사용자 명령을 받아 Agent Session 관리 + progress.log 기록
#
# Commands:
#   next / n        다음 에이전트 세션 시작
#   retry / r       현재 에이전트 재실행
#   stop            에이전트 세션 중지
#   log <message>   progress.log에 수동 메모 추가
#   clear-fail      failure 상태 클리어
#   status / s      대시보드 즉시 갱신 (상단 pane)
#   help / h        도움말
#   quit / q        종료
#
# Usage: bash scripts/harness-control.sh [project-root]

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

PROJECT_ROOT="${1:-}"
if [ -z "$PROJECT_ROOT" ]; then
  source "$SCRIPT_DIR/lib/harness-render-progress.sh"
  PROJECT_ROOT="$(resolve_harness_root ".")" || {
    echo "[control] .harness/ not found."
    exit 1
  }
fi

PROGRESS="$PROJECT_ROOT/.harness/progress.json"
PROGRESS_LOG="$PROJECT_ROOT/.harness/progress.log"

BOLD="\033[1m"
DIM="\033[2m"
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
CYAN="\033[36m"
RESET="\033[0m"

# ── Agent Session pane target (find by title) ──
find_agent_pane() {
  tmux list-panes -t harness-studio -F '#{pane_id} #{pane_title}' 2>/dev/null \
    | grep "Agent Session" | awk '{print $1}' | head -1
}

CONFIG="$PROJECT_ROOT/.harness/config.json"

# Build claude command from config
build_claude_cmd() {
  local agent="$1"
  local model="opus"
  if [ -f "$CONFIG" ]; then
    model=$(jq -r ".agents[\"${agent}\"].model // \"opus\"" "$CONFIG" 2>/dev/null)
  fi
  echo "claude --dangerously-skip-permissions --model ${model}"
}

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
  local pane
  pane=$(find_agent_pane)
  if [ -z "$pane" ]; then
    echo -e "  ${RED}Agent Session pane not found.${RESET}"
    return
  fi

  local next_agent
  next_agent=$(jq -r '.next_agent // "none"' "$PROGRESS" 2>/dev/null)
  if [ "$next_agent" = "none" ] || [ "$next_agent" = "null" ]; then
    echo -e "  ${YELLOW}No next agent in queue.${RESET}"
    return
  fi

  local claude_cmd
  claude_cmd=$(build_claude_cmd "$next_agent")

  echo -e "  ${CYAN}Starting ${next_agent}...${RESET}"
  echo -e "  ${DIM}${claude_cmd}${RESET}"

  local ts
  ts=$(date +"%Y-%m-%d")
  echo "${ts} | manual | start-agent | ${next_agent}" >> "$PROGRESS_LOG"

  # Launch claude in Agent Session pane with the agent's prompt
  tmux send-keys -t "$pane" "${claude_cmd} -p '하네스 엔지니어링 시작'" Enter
}

cmd_retry() {
  local pane
  pane=$(find_agent_pane)
  if [ -z "$pane" ]; then
    echo -e "  ${RED}Agent Session pane not found.${RESET}"
    return
  fi

  local current_agent
  current_agent=$(jq -r '.current_agent // "none"' "$PROGRESS" 2>/dev/null)
  if [ "$current_agent" = "none" ] || [ "$current_agent" = "null" ]; then
    echo -e "  ${YELLOW}No current agent to retry.${RESET}"
    return
  fi

  local claude_cmd
  claude_cmd=$(build_claude_cmd "$current_agent")

  echo -e "  ${CYAN}Retrying ${current_agent}...${RESET}"
  local ts
  ts=$(date +"%Y-%m-%d")
  echo "${ts} | manual | retry | ${current_agent}" >> "$PROGRESS_LOG"
  tmux send-keys -t "$pane" "${claude_cmd} -p '하네스 엔지니어링 시작'" Enter
}

cmd_stop() {
  local pane
  pane=$(find_agent_pane)
  if [ -z "$pane" ]; then
    echo -e "  ${RED}Agent Session pane not found.${RESET}"
    return
  fi

  echo -e "  ${YELLOW}Sending Ctrl+C to Agent Session...${RESET}"
  tmux send-keys -t "$pane" C-c
  local ts
  ts=$(date +"%Y-%m-%d")
  echo "${ts} | manual | stop | user-initiated" >> "$PROGRESS_LOG"
}

show_help() {
  echo ""
  echo -e "  ${BOLD}Commands${RESET}"
  echo -e "  ${CYAN}next${RESET}   / ${CYAN}n${RESET}          Start next agent"
  echo -e "  ${CYAN}retry${RESET}  / ${CYAN}r${RESET}          Retry current agent"
  echo -e "  ${CYAN}stop${RESET}              Send Ctrl+C to agent"
  echo -e "  ${CYAN}log${RESET} <message>     Add note to progress.log"
  echo -e "  ${CYAN}clear-fail${RESET}        Clear failure state"
  echo -e "  ${CYAN}help${RESET}  / ${CYAN}h${RESET}          Show this help"
  echo -e "  ${CYAN}quit${RESET}  / ${CYAN}q${RESET}          Exit"
  echo ""
}

# ── Main ──
echo ""
echo -e "  ${BOLD}Harness Control${RESET}  ${DIM}(type 'help' for commands)${RESET}"
echo ""

while true; do
  echo -ne "  ${BOLD}harness>${RESET} "
  read -r input || exit 0
  input=$(echo "$input" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

  case "$input" in
    next|n)         cmd_next ;;
    retry|r)        cmd_retry ;;
    stop)           cmd_stop ;;
    log\ *)         cmd_log "${input#log }" ;;
    clear-fail)     cmd_clear_fail ;;
    help|h)         show_help ;;
    quit|q)         echo -e "  ${DIM}Goodbye.${RESET}"; exit 0 ;;
    "")             ;; # empty — just re-prompt
    *)              echo -e "  ${DIM}Logging as note.${RESET}"; cmd_log "$input" ;;
  esac
done
