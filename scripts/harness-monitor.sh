#!/bin/bash
# harness-monitor.sh — Agent Lifecycle Monitor
#
# v3 모드: 단일 이벤트 스트림 (progress.json 변경 감지 + audit.log)
# v4 모드: 팀별 섹션 분리 (feature-queue.json + progress.log 기반)
#
# Usage: bash scripts/harness-monitor.sh [project-root]

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

PROJECT_ROOT="${1:-}"
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
# v4 모드: 팀별 섹션 렌더링
# ══════════════════════════════════════════

render_v4_header() {
  echo -e "${BOLD}TEAM MONITOR${RESET}  ${DIM}$(date +%H:%M:%S)${RESET}"
  echo ""
}

render_team_section() {
  local team_num="$1"
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

  # 헤더 라인
  printf "%b%b T%s%b " "$color" "$icon" "$team_num" "$RESET"
  if [ "$t_feature" != "—" ] && [ "$t_feature" != "null" ]; then
    printf "%s " "$t_feature"
    if [ -n "$phase_str" ]; then
      printf "%b%s%b" "$color" "$phase_str" "$RESET"
    fi
    if [ -n "$t_attempt" ] && [ "$t_attempt" != "—" ] && [ "$t_attempt" != "1" ]; then
      printf " %b#%s%b" "$DIM" "$t_attempt" "$RESET"
    fi
  else
    printf "%bidle%b" "$DIM" "$RESET"
  fi
  echo ""

  # 팀 로그 (progress.log에서 team-N 엔트리만 추출)
  if [ -f "$PROGRESS_LOG" ]; then
    grep -i "team-${team_num}\|team_${team_num}" "$PROGRESS_LOG" 2>/dev/null | tail -5 | while IFS= read -r line; do
      local ts action detail
      ts=$(echo "$line" | awk -F'|' '{gsub(/^ +| +$/,"",$1); print $1}')
      action=$(echo "$line" | awk -F'|' '{gsub(/^ +| +$/,"",$3); print $3}')
      detail=$(echo "$line" | awk -F'|' '{gsub(/^ +| +$/,"",$4); print $4}')

      local short_ts
      short_ts=$(echo "$ts" | grep -oE '[0-9]{2}:[0-9]{2}' | tail -1 || echo "$ts")

      if [ ${#detail} -gt 35 ]; then detail="${detail:0:33}.."; fi

      # 액션별 아이콘
      local a_icon="·" a_color="$DIM"
      case "$action" in
        gen)      a_icon="▶"; a_color="$GREEN" ;;
        eval)     a_icon="✦"; a_color="$BLUE" ;;
        pass)     a_icon="✓"; a_color="$GREEN" ;;
        fail)     a_icon="✗"; a_color="$RED" ;;
        dequeue)  a_icon="→"; a_color="$CYAN" ;;
        gate)     a_icon="◆"; a_color="$YELLOW" ;;
        *)        a_icon="·"; a_color="$DIM" ;;
      esac

      printf "  %b%s%b %b%s%b %b%s%b\n" \
        "$DIM" "$short_ts" "$RESET" \
        "$a_color" "$a_icon" "$RESET" \
        "$DIM" "$detail" "$RESET"
    done
  fi
}

render_v4() {
  render_v4_header

  # 팀 수 확인
  local team_count=3
  if [ -f "$QUEUE" ]; then
    team_count=$(jq '.teams | length' "$QUEUE" 2>/dev/null || echo 3)
  fi

  for i in $(seq 1 "$team_count"); do
    render_team_section "$i"
    echo ""
  done

  # Lead/시스템 이벤트 (team이 아닌 엔트리)
  echo -e "${BOLD}SYSTEM${RESET}"
  if [ -f "$PROGRESS_LOG" ]; then
    grep -v 'team-[0-9]' "$PROGRESS_LOG" 2>/dev/null | grep -v '^#' | grep -v '^$' | tail -5 | while IFS= read -r line; do
      local ts agent action detail
      ts=$(echo "$line" | awk -F'|' '{gsub(/^ +| +$/,"",$1); print $1}')
      agent=$(echo "$line" | awk -F'|' '{gsub(/^ +| +$/,"",$2); print $2}')
      action=$(echo "$line" | awk -F'|' '{gsub(/^ +| +$/,"",$3); print $3}')
      detail=$(echo "$line" | awk -F'|' '{gsub(/^ +| +$/,"",$4); print $4}')

      local short_ts
      short_ts=$(echo "$ts" | grep -oE '[0-9]{2}:[0-9]{2}' | tail -1 || echo "$ts")

      if [ ${#detail} -gt 35 ]; then detail="${detail:0:33}.."; fi

      printf "  %b%s%b %s %b%s%b\n" \
        "$DIM" "$short_ts" "$RESET" \
        "$agent" \
        "$DIM" "$detail" "$RESET"
    done
  fi
}

# ══════════════════════════════════════════
# v3 모드: 단일 스트림 (기존 동작)
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

# v4 감지: feature-queue.json 존재 여부
IS_V4=false
if [ -f "$QUEUE" ]; then
  IS_V4=true
fi

if [ "$IS_V4" = true ]; then
  # ── v4: 팀별 섹션, auto-refresh ──
  tput civis 2>/dev/null
  clear

  while true; do
    buf=$(render_v4 2>&1)
    tput cup 0 0 2>/dev/null
    echo "$buf"
    tput ed 2>/dev/null
    sleep 3
  done
else
  # ── v3: 단일 스트림, audit tail ──
  print_v3_header

  if [ -f "$PROGRESS" ]; then
    LAST_AGENT=$(jq -r '.current_agent // "none"' "$PROGRESS" 2>/dev/null)
    LAST_STATUS=$(jq -r '.agent_status // "pending"' "$PROGRESS" 2>/dev/null)
    LAST_SPRINT=$(jq -r '.sprint.number // 0' "$PROGRESS" 2>/dev/null)

    echo -e "  ${BOLD}History${RESET}"
    jq -r '.history // [] | .[] | "  \(.timestamp)  \(.agent) — \(.action): \(.detail)"' "$PROGRESS" 2>/dev/null
    echo ""
    echo -e "  ${DIM}── Live events below ──${RESET}"
    echo ""
  fi

  stream_audit

  while true; do
    check_transitions
    sleep 2
  done
fi
