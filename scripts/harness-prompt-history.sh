#!/bin/bash
# harness-prompt-history.sh — User Prompt History pane
# 사용자가 입력한 프롬프트만 표시 + 현재 처리 단계(Planner/Team) 표시
# Usage: bash scripts/harness-prompt-history.sh [project-root]

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/harness-render-progress.sh"

PROJECT_ROOT="${1:-}"
if [ -z "$PROJECT_ROOT" ]; then
  PROJECT_ROOT="$(resolve_harness_root ".")" || { echo "[history] .harness/ not found."; exit 1; }
fi

PROGRESS_LOG="$PROJECT_ROOT/.harness/progress.log"
PROGRESS="$PROJECT_ROOT/.harness/progress.json"
QUEUE="$PROJECT_ROOT/.harness/actions/feature-queue.json"

BOLD="\033[1m"
DIM="\033[2m"
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
CYAN="\033[36m"
MAGENTA="\033[35m"
WHITE="\033[37m"
RESET="\033[0m"
BG_BLUE="\033[44m"
BG_GREEN="\033[42m"
BG_YELLOW="\033[43m"

render_header() {
  echo -e "${BOLD}USER PROMPTS${RESET}  ${DIM}$(date +%H:%M:%S)${RESET}"
  echo ""
}

# 현재 처리 상태 배지
render_processing_status() {
  local mode="solo" current_agent="none" agent_status="pending"

  if [ -f "$PROGRESS" ] && command -v jq &>/dev/null; then
    mode=$(jq -r '.mode // "solo"' "$PROGRESS" 2>/dev/null)
    current_agent=$(jq -r '.current_agent // "none"' "$PROGRESS" 2>/dev/null)
    agent_status=$(jq -r '.agent_status // "pending"' "$PROGRESS" 2>/dev/null)
  fi

  local badge=""
  case "$mode" in
    team)
      # Team 모드: 각 팀의 현재 상태 표시
      badge="${BG_BLUE}${WHITE}${BOLD} TEAM MODE ${RESET}"
      if [ -f "$QUEUE" ]; then
        local team_info=""
        for i in 1 2 3; do
          local t_status t_feature t_phase
          t_status=$(jq -r ".teams[\"$i\"].status // \"idle\"" "$QUEUE" 2>/dev/null)
          t_feature=$(jq -r ".teams[\"$i\"].feature // \"\"" "$QUEUE" 2>/dev/null)
          if [ "$t_status" = "busy" ] && [ -n "$t_feature" ] && [ "$t_feature" != "null" ]; then
            t_phase=$(jq -r --arg f "$t_feature" '.queue.in_progress[$f].phase // "?"' "$QUEUE" 2>/dev/null)
            team_info+="  ${CYAN}T${i}${RESET}:${t_feature}(${t_phase})"
          else
            team_info+="  ${DIM}T${i}:idle${RESET}"
          fi
        done
        echo -e "  ${badge}${team_info}"
      else
        echo -e "  ${badge}"
      fi
      ;;
    paused)
      echo -e "  ${BG_YELLOW}${WHITE}${BOLD} PAUSED ${RESET}  ${DIM}/harness-team 또는 /harness-solo${RESET}"
      ;;
    *)
      # Solo 모드: 현재 에이전트 표시
      if [ "$current_agent" != "none" ] && [ "$current_agent" != "null" ]; then
        local agent_color="$RESET"
        case "$current_agent" in
          planner*)     agent_color="$YELLOW" ;;
          generator*)   agent_color="$GREEN" ;;
          eval*)        agent_color="$RED" ;;
          dispatcher*)  agent_color="$MAGENTA" ;;
        esac
        local status_icon="·"
        case "$agent_status" in
          running)   status_icon="▶" ;;
          completed) status_icon="✓" ;;
          failed)    status_icon="✗" ;;
        esac
        echo -e "  ${BG_GREEN}${WHITE}${BOLD} SOLO ${RESET}  ${agent_color}${status_icon} ${current_agent}${RESET}"
      else
        echo -e "  ${BG_GREEN}${WHITE}${BOLD} SOLO ${RESET}  ${DIM}대기 중${RESET}"
      fi
      ;;
  esac
  echo ""
}

# 사용자 프롬프트만 필터하여 표시
render_user_prompts() {
  if [ ! -f "$PROGRESS_LOG" ]; then
    echo -e "  ${DIM}(프롬프트 기록 없음)${RESET}"
    return
  fi

  local term_height
  term_height=$(tput lines 2>/dev/null || echo 30)
  local max_lines=$((term_height - 10))
  if [ "$max_lines" -lt 5 ]; then max_lines=5; fi

  # user-prompt 행만 필터
  local prompts
  prompts=$(grep '| user-prompt |' "$PROGRESS_LOG" 2>/dev/null | tail -"$max_lines")

  if [ -z "$prompts" ]; then
    echo -e "  ${DIM}(사용자 프롬프트 없음)${RESET}"
    return
  fi

  local line_num=0
  local total_prompts
  total_prompts=$(grep -c '| user-prompt |' "$PROGRESS_LOG" 2>/dev/null || echo 0)

  echo "$prompts" | while IFS= read -r line; do
    line_num=$((line_num + 1))

    local ts detail
    ts=$(echo "$line" | awk -F'|' '{gsub(/^ +| +$/,"",$1); print $1}')
    detail=$(echo "$line" | awk -F'|' '{gsub(/^ +| +$/,"",$4); print $4}')

    local short_ts
    short_ts=$(echo "$ts" | grep -oE '[0-9]{2}:[0-9]{2}' | tail -1 || echo "$ts")

    # 프롬프트 내용 truncate
    local max_width
    max_width=$(( $(tput cols 2>/dev/null || echo 40) - 12 ))
    if [ "$max_width" -lt 20 ]; then max_width=20; fi
    if [ ${#detail} -gt "$max_width" ]; then
      detail="${detail:0:$((max_width - 2))}.."
    fi

    # 처리 상태 찾기: 이 프롬프트 이후의 첫 번째 에이전트 액션
    local processed_by=""
    local prompt_ts_epoch
    prompt_ts_epoch=$(echo "$ts" | sed 's/[^0-9:]//g')

    # 간단히: 마지막 프롬프트인지 확인 → 현재 처리 중 표시
    echo -e "  ${DIM}${short_ts}${RESET}  ${WHITE}${detail}${RESET}"
  done

  echo ""
  echo -e "  ${DIM}── ${total_prompts} prompts total ──${RESET}"
}

render_all() {
  render_header
  render_processing_status
  render_user_prompts
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
