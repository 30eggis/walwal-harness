#!/bin/bash
# harness-monitor.sh — Agent Lifecycle Monitor (v5 unified)
#
# Solo 모드: 단일 이벤트 스트림 (progress.json 변경 감지 + audit.log)
# Team 모드: 팀별 섹션 분리 (feature-queue.json + progress.log 기반)
#
# Usage: bash scripts/harness-monitor.sh [project-root]

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/harness-keywait.sh"

# ── Args ──
# Usage: harness-monitor.sh [project-root] [--team N]
#   --team N  → 단일 팀만 렌더 (tmux per-team pane 용도)
PROJECT_ROOT=""
TEAM_FILTER=""
while [ $# -gt 0 ]; do
  case "$1" in
    --team) TEAM_FILTER="$2"; shift 2 ;;
    --team=*) TEAM_FILTER="${1#--team=}"; shift ;;
    *) [ -z "$PROJECT_ROOT" ] && PROJECT_ROOT="$1"; shift ;;
  esac
done

if [ -z "$PROJECT_ROOT" ]; then
  source "$SCRIPT_DIR/lib/harness-render-progress.sh"
  PROJECT_ROOT="$(resolve_harness_root ".")" || {
    echo "[monitor] .harness/ not found. Pass project root as argument."
    exit 1
  }
fi

PROGRESS="$PROJECT_ROOT/.harness/progress.json"
PROGRESS_LOG="$PROJECT_ROOT/.harness/progress.log"
AUDIT_LOG="$PROJECT_ROOT/.harness/actions/audit.log"
QUEUE="$PROJECT_ROOT/.harness/actions/feature-queue.json"

# ── ANSI helpers ──
BOLD="\033[1m"
DIM="\033[2m"
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
CYAN="\033[36m"
MAGENTA="\033[35m"
BLUE="\033[34m"
RESET="\033[0m"

# ── Team colors ──
T1_COLOR="$CYAN"
T2_COLOR="$MAGENTA"
T3_COLOR="$YELLOW"

team_color() {
  case "$1" in
    1|team-1) echo "$T1_COLOR" ;;
    2|team-2) echo "$T2_COLOR" ;;
    3|team-3) echo "$T3_COLOR" ;;
    *)        echo "$DIM" ;;
  esac
}

# ══════════════════════════════════════════
# Team 모드: 팀별 섹션 렌더링
# ══════════════════════════════════════════

render_v4_header() {
  echo -e "${BOLD}TEAM MONITOR${RESET}  ${DIM}$(date +%H:%M:%S)${RESET}"
  echo ""
}

# 고정폭 배너 구분선 (터미널 너비에 맞춰 채움)
banner_line() {
  local cols
  cols=$(tput cols 2>/dev/null || echo 78)
  local line=""
  for ((i=0; i<cols; i++)); do line+="━"; done
  echo "$line"
}

render_team_section() {
  local team_num="$1"
  local log_lines="${2:-10}"
  local color
  color=$(team_color "$team_num")

  # 팀 상태 from queue
  local t_status="idle" t_feature="—" t_phase="—" t_attempt=""
  if [ -f "$QUEUE" ]; then
    t_status=$(jq -r ".teams[\"$team_num\"].status // \"idle\"" "$QUEUE" 2>/dev/null)
    t_feature=$(jq -r ".teams[\"$team_num\"].feature // \"—\"" "$QUEUE" 2>/dev/null)
    if [ "$t_feature" != "—" ] && [ "$t_feature" != "null" ]; then
      t_phase=$(jq -r --arg f "$t_feature" '.queue.in_progress[$f].phase // "?"' "$QUEUE" 2>/dev/null)
      t_attempt=$(jq -r --arg f "$t_feature" '.queue.in_progress[$f].attempt // 1' "$QUEUE" 2>/dev/null)
    fi
  fi

  # 상태 아이콘
  local icon="○"
  case "$t_status" in
    busy) icon="▶" ;;
    idle) icon="○" ;;
  esac

  # Phase 표시
  local phase_str=""
  case "$t_phase" in
    gen)  phase_str="Gen" ;;
    gate) phase_str="Gate" ;;
    eval) phase_str="Eval" ;;
    *)    phase_str="" ;;
  esac

  # ── 큰 배너 ──
  local bar
  bar=$(banner_line)
  printf "%b%s%b\n" "$color" "$bar" "$RESET"

  printf "%b%b TEAM %s%b" "$color$BOLD" "$icon" "$team_num" "$RESET"
  if [ "$t_feature" != "—" ] && [ "$t_feature" != "null" ]; then
    printf "  %b%s%b" "$BOLD" "$t_feature" "$RESET"
    if [ -n "$phase_str" ]; then
      printf "  %b[%s]%b" "$color" "$phase_str" "$RESET"
    fi
    if [ -n "$t_attempt" ] && [ "$t_attempt" != "—" ] && [ "$t_attempt" != "1" ]; then
      printf " %battempt #%s%b" "$YELLOW" "$t_attempt" "$RESET"
    fi
  else
    printf "  %bidle%b" "$DIM" "$RESET"
  fi
  echo ""
  printf "%b%s%b\n" "$color" "$bar" "$RESET"

  # ── 팀 로그 ──
  local have_logs=0
  if [ -f "$PROGRESS_LOG" ]; then
    local matched
    # Team panel 필터: agent 필드($2)가 해당 team 번호를 포함하는 모든 prefix 매칭.
    # 허용: team-N, team_N, eval-N, eval_N, gen-N, gen-fe-N, worker-N, lead-N 등
    # (워커가 evaluator 분리를 위해 eval-N 으로 로깅해도 누락되지 않게 한다)
    matched=$(awk -F'|' -v n="${team_num}" '
      {
        # $2 = agent (앞뒤 공백 trim)
        a=$2; gsub(/^ +| +$/,"",a)
        # agent 토큰이 [-_]N\b 로 끝나거나 -N- / _N_ 처럼 N이 토큰 경계에 포함되면 매치
        if (match(a, "(^|[-_])" n "([-_]|$)")) print
      }' "$PROGRESS_LOG" 2>/dev/null | tail -"$log_lines")
    if [ -n "$matched" ]; then
      have_logs=1
      local cols
      cols=$(tput cols 2>/dev/null || echo 78)
      # 포맷: [ts] [icon agent] detail (너무 길면 터미널 너비에서 줄바꿈)
      local prefix_w=18  # "  HH:MM  ✦ eval  "
      local detail_w=$(( cols - prefix_w ))
      [ "$detail_w" -lt 20 ] && detail_w=20

      echo "$matched" | while IFS= read -r line; do
        local ts action detail
        ts=$(echo "$line" | awk -F'|' '{gsub(/^ +| +$/,"",$1); print $1}')
        action=$(echo "$line" | awk -F'|' '{gsub(/^ +| +$/,"",$3); print $3}')
        detail=$(echo "$line" | awk -F'|' '{gsub(/^ +| +$/,"",$4); print $4}')

        local short_ts
        short_ts=$(echo "$ts" | grep -oE '[0-9]{2}:[0-9]{2}' | tail -1 || echo "$ts")

        local a_icon="·" a_color="$DIM" a_label="$action"
        case "$action" in
          gen|gen-start|gen-read|gen-write|gen-test|gen-done)
            a_icon="▶"; a_color="$GREEN"; a_label="Gen" ;;
          eval-start)
            a_icon="✦"; a_color="$MAGENTA"; a_label="Eval" ;;
          eval-check)
            a_icon="·"; a_color="$MAGENTA"; a_label="Eval" ;;
          eval-done)
            a_icon="✦"; a_color="${BOLD}${MAGENTA}"; a_label="Eval" ;;
          eval)
            a_icon="✦"; a_color="$MAGENTA"; a_label="Eval" ;;
          result|pass)
            a_icon="✓"; a_color="$GREEN"; a_label="Result" ;;
          fail)
            a_icon="✗"; a_color="$RED"; a_label="Result" ;;
          dequeue)  a_icon="→"; a_color="$CYAN"; a_label="Queue" ;;
          gate)     a_icon="◆"; a_color="$YELLOW"; a_label="Gate" ;;
          *)        a_icon="·"; a_color="$DIM"; a_label="$action" ;;
        esac

        # 첫 줄
        local first="${detail:0:$detail_w}"
        printf "  %b%s%b %b%s%b %-6s %s\n" \
          "$DIM" "$short_ts" "$RESET" \
          "$a_color" "$a_icon" "$RESET" \
          "$a_label" "$first"
        # 이어질 줄 (긴 detail 은 접지 않고 들여쓰기로 이어서 출력)
        local rest="${detail:$detail_w}"
        while [ -n "$rest" ]; do
          local chunk="${rest:0:$detail_w}"
          rest="${rest:$detail_w}"
          printf "  %*s%s\n" "$prefix_w" "" "$chunk"
        done
      done
    fi
  fi
  if [ "$have_logs" -eq 0 ]; then
    printf "  %b(no activity)%b\n" "$DIM" "$RESET"
  fi
}

render_v4() {
  # 단일 팀 모드 (tmux per-team pane)
  if [ -n "$TEAM_FILTER" ]; then
    local rows log_lines
    rows=$(tput lines 2>/dev/null || echo 20)
    log_lines=$(( rows - 5 ))
    [ "$log_lines" -lt 3 ] && log_lines=3
    render_team_section "$TEAM_FILTER" "$log_lines"
    return
  fi

  render_v4_header

  local team_count=3
  if [ -f "$QUEUE" ]; then
    team_count=$(jq '.teams | length' "$QUEUE" 2>/dev/null || echo 3)
  fi
  [ "$team_count" -lt 1 ] && team_count=3

  local rows per_team log_lines
  rows=$(tput lines 2>/dev/null || echo 40)
  per_team=$(( (rows - 2) / team_count ))
  log_lines=$(( per_team - 5 ))
  if [ "$log_lines" -lt 3 ]; then log_lines=3; fi
  if [ "$log_lines" -gt 15 ]; then log_lines=15; fi

  for i in $(seq 1 "$team_count"); do
    render_team_section "$i" "$log_lines"
    echo ""
  done
}

# ══════════════════════════════════════════
# Solo 모드: 단일 스트림 (기존 동작)
# ══════════════════════════════════════════

LAST_AGENT=""
LAST_STATUS=""
LAST_SPRINT=""

print_event() {
  local ts="$1" icon="$2" color="$3" msg="$4"
  echo -e "  ${DIM}${ts}${RESET}  ${color}${icon}${RESET}  ${msg}"
}

print_v3_header() {
  echo -e "${BOLD}╔══════════════════════════════════════╗${RESET}"
  echo -e "${BOLD}║  AGENT LIFECYCLE MONITOR             ║${RESET}"
  echo -e "${BOLD}╚══════════════════════════════════════╝${RESET}"
  echo ""
}

check_transitions() {
  if [ ! -f "$PROGRESS" ]; then return; fi

  local agent status sprint
  agent=$(jq -r '.current_agent // "none"' "$PROGRESS" 2>/dev/null)
  status=$(jq -r '.agent_status // "pending"' "$PROGRESS" 2>/dev/null)
  sprint=$(jq -r '.sprint.number // 0' "$PROGRESS" 2>/dev/null)

  local now
  now=$(date +"%H:%M:%S")

  if [ "$sprint" != "$LAST_SPRINT" ] && [ -n "$LAST_SPRINT" ]; then
    print_event "$now" ">>>" "$MAGENTA" "${BOLD}Sprint ${sprint} started${RESET}"
    echo ""
  fi

  if [ "$agent" != "$LAST_AGENT" ] && [ -n "$LAST_AGENT" ]; then
    if [ "$LAST_AGENT" != "none" ] && [ "$LAST_AGENT" != "null" ]; then
      print_event "$now" " ✓ " "$GREEN" "${LAST_AGENT} → ${BOLD}done${RESET}"
    fi
    if [ "$agent" != "none" ] && [ "$agent" != "null" ]; then
      print_event "$now" " ▶ " "$CYAN" "${BOLD}${agent}${RESET} started"
    fi
  fi

  if [ "$agent" = "$LAST_AGENT" ] && [ "$status" != "$LAST_STATUS" ] && [ -n "$LAST_STATUS" ]; then
    local status_color="$RESET" status_icon="•"
    case "$status" in
      running)   status_color="$GREEN";  status_icon=" ▶ " ;;
      completed) status_color="$CYAN";   status_icon=" ✓ " ;;
      failed)    status_color="$RED";    status_icon=" ✗ " ;;
      blocked)   status_color="$RED";    status_icon=" ! " ;;
      pending)   status_color="$YELLOW"; status_icon=" … " ;;
    esac
    print_event "$now" "$status_icon" "$status_color" "${agent} → ${BOLD}${status}${RESET}"

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

stream_audit() {
  if [ ! -f "$AUDIT_LOG" ]; then return; fi
  tail -n 0 -f "$AUDIT_LOG" 2>/dev/null | while IFS= read -r line; do
    if [[ "$line" == "#"* ]] || [[ -z "$line" ]]; then continue; fi
    local ts agent action status target
    ts=$(echo "$line" | awk -F'|' '{gsub(/^ +| +$/,"",$1); print $1}')
    agent=$(echo "$line" | awk -F'|' '{gsub(/^ +| +$/,"",$2); print $2}')
    action=$(echo "$line" | awk -F'|' '{gsub(/^ +| +$/,"",$3); print $3}')
    status=$(echo "$line" | awk -F'|' '{gsub(/^ +| +$/,"",$4); print $4}')
    target=$(echo "$line" | awk -F'|' '{gsub(/^ +| +$/,"",$5); print $5}')

    local color="$RESET" icon="•"
    case "$status" in
      start)    color="$CYAN";  icon="▶" ;;
      complete) color="$GREEN"; icon="✓" ;;
      fail)     color="$RED";   icon="✗" ;;
      pass)     color="$GREEN"; icon="✓" ;;
      skip)     color="$DIM";   icon="–" ;;
    esac

    local short_ts
    short_ts=$(echo "$ts" | grep -oE '[0-9]{2}:[0-9]{2}:[0-9]{2}' || echo "$ts")
    echo -e "  ${DIM}${short_ts}${RESET}  ${color}${icon}${RESET}  ${BOLD}${agent}${RESET} ${action} ${target}"
  done &
  AUDIT_TAIL_PID=$!
}

# ══════════════════════════════════════════
# Mode detection & main loop
# ══════════════════════════════════════════

cleanup() {
  if [ -n "${AUDIT_TAIL_PID:-}" ]; then
    kill "$AUDIT_TAIL_PID" 2>/dev/null || true
  fi
  tput cnorm 2>/dev/null
  exit 0
}
trap cleanup EXIT INT TERM

# 매 루프마다 mode 동적 감지 — 시작 후에도 모드 전환 가능
tput civis 2>/dev/null
clear

CURRENT_MODE=""

while true; do
  # 동적 모드 감지 (--team 지정 시 항상 team, 그 외 progress.json.mode 참조)
  if [ -n "$TEAM_FILTER" ] || [ -f "$QUEUE" ]; then
    NEW_MODE="team"
  else
    if [ -f "$PROGRESS" ] && command -v jq &>/dev/null; then
      NEW_MODE=$(jq -r '.mode // "solo"' "$PROGRESS" 2>/dev/null)
      [ "$NEW_MODE" = "team" ] || NEW_MODE="solo"
    else
      NEW_MODE="solo"
    fi
  fi

  # 모드 전환 시 화면 초기화
  if [ "$NEW_MODE" != "$CURRENT_MODE" ]; then
    clear
    CURRENT_MODE="$NEW_MODE"
    if [ "$CURRENT_MODE" = "solo" ]; then
      # solo 초기화
      if [ -f "$PROGRESS" ]; then
        LAST_AGENT=$(jq -r '.current_agent // "none"' "$PROGRESS" 2>/dev/null)
        LAST_STATUS=$(jq -r '.agent_status // "pending"' "$PROGRESS" 2>/dev/null)
        LAST_SPRINT=$(jq -r '.sprint.number // 0' "$PROGRESS" 2>/dev/null)
      fi
      stream_audit
    fi
  fi

  if [ "$CURRENT_MODE" = "team" ]; then
    buf=$(render_v4 2>&1)
    tput cup 0 0 2>/dev/null
    echo "$buf"
    tput ed 2>/dev/null
  else
    check_transitions
  fi

  printf "${DIM}  [r] refresh  [q] quit${RESET}\033[K\n"
  wait_or_refresh 3 || true
done

