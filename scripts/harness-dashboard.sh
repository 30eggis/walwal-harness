#!/bin/bash
# harness-dashboard.sh — Unified Dashboard (Solo + Team mode)
#
# Reads progress.json.mode to decide rendering:
#   solo: Sequential pipeline progress (sprint map, agent bar, prompt history)
#   team: Queue summary, team status, feature list, bottleneck alerts
#
# Usage: bash scripts/harness-dashboard.sh [project-root]

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/harness-render-progress.sh"
source "$SCRIPT_DIR/lib/harness-keywait.sh"

PROJECT_ROOT="${1:-}"
if [ -z "$PROJECT_ROOT" ]; then
  PROJECT_ROOT="$(resolve_harness_root ".")" || {
    echo "[dashboard] .harness/ not found. Pass project root as argument."
    exit 1
  }
fi

PROGRESS="$PROJECT_ROOT/.harness/progress.json"
FEATURES="$PROJECT_ROOT/.harness/actions/feature-list.json"
QUEUE="$PROJECT_ROOT/.harness/actions/feature-queue.json"
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

strip_ansi() {
  sed 's/\x1b\[[0-9;]*m//g; s/\x1b\[[0-9;]*[a-zA-Z]//g'
}

get_term_width() {
  echo "${_COLS:-$(tput cols 2>/dev/null || echo 80)}"
}

get_mode() {
  if [ -f "$PROGRESS" ] && command -v jq &>/dev/null; then
    jq -r '.mode // "solo"' "$PROGRESS" 2>/dev/null
  else
    echo "solo"
  fi
}

# ══════════════════════════════════════════
# Common header
# ══════════════════════════════════════════
render_header() {
  local now project_name mode
  now=$(date +"%H:%M:%S")
  project_name=$(jq -r '.project_name // "Unknown"' "$PROGRESS" 2>/dev/null)
  mode=$(get_mode)

  local mode_label
  case "$mode" in
    team)   mode_label="${GREEN}TEAM${RESET}" ;;
    paused) mode_label="${YELLOW}PAUSED${RESET}" ;;
    *)      mode_label="${CYAN}SOLO${RESET}" ;;
  esac

  echo -e "${BOLD}HARNESS DASHBOARD${RESET}  ${mode_label}  ${DIM}${project_name} | ${now}${RESET}"
  echo ""
}

# ══════════════════════════════════════════
# Solo Mode rendering
# ══════════════════════════════════════════
render_solo_sprint_overview() {
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

render_solo_failure_info() {
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

render_solo_agent_info() {
  if [ ! -f "$PROGRESS" ]; then return; fi

  local next_agent agent_status
  next_agent=$(jq -r '.next_agent // "none"' "$PROGRESS" 2>/dev/null)
  agent_status=$(jq -r '.agent_status // "pending"' "$PROGRESS" 2>/dev/null)

  if [ "$next_agent" != "none" ] && [ "$next_agent" != "null" ] && [ "$agent_status" != "blocked" ]; then
    echo -e "  ${CYAN}Next → /harness-${next_agent}${RESET}"
  fi

  render_agent_bar "$PROJECT_ROOT" 2>/dev/null
  echo ""
}

render_solo_prompt_history() {
  echo -e "${BOLD}Recent Activity${RESET}"

  if [ -f "$PROGRESS_LOG" ]; then
    grep -v '^#' "$PROGRESS_LOG" 2>/dev/null | grep -v '^$' | tail -10 | while IFS= read -r line; do
      local ts agent action detail
      ts=$(echo "$line" | awk -F'|' '{gsub(/^ +| +$/,"",$1); print $1}')
      agent=$(echo "$line" | awk -F'|' '{gsub(/^ +| +$/,"",$2); print $2}')
      action=$(echo "$line" | awk -F'|' '{gsub(/^ +| +$/,"",$3); print $3}')
      detail=$(echo "$line" | awk -F'|' '{gsub(/^ +| +$/,"",$4); print $4}')

      local short_ts icon color
      short_ts=$(echo "$ts" | sed 's/^[0-9]*-//')

      # action 기반으로 먼저 분류 (team 모드에서 agent=team-N이므로)
      case "$action" in
        eval-start|eval-check|eval-done|eval)
          icon="✦" ; color="$MAGENTA" ;;
        gen-start|gen-read|gen-write|gen-test|gen-done|gen)
          icon="▶" ; color="$GREEN" ;;
        result|pass)
          icon="✓" ; color="$GREEN" ;;
        fail)
          icon="✗" ; color="$RED" ;;
        *)
          # fallback: agent 기반
          case "$agent" in
            dispatcher*)  icon="▸" ; color="$MAGENTA" ;;
            planner*)     icon="□" ; color="$YELLOW" ;;
            generator*)   icon="▶" ; color="$GREEN" ;;
            eval*)        icon="✦" ; color="$MAGENTA" ;;
            team-*)       icon="◆" ; color="$CYAN" ;;
            user*)        icon="★" ; color="$BOLD" ;;
            *)            icon="·" ; color="$DIM" ;;
          esac
          ;;
      esac

      if [ ${#detail} -gt 40 ]; then detail="${detail:0:38}.."; fi

      echo -e "${color}${icon}${RESET} ${DIM}${short_ts}${RESET} ${agent} ${DIM}${action}${RESET} ${detail}"
    done
  else
    echo -e "${DIM}(no progress.log yet)${RESET}"
  fi
}

# ══════════════════════════════════════════
# Team Mode rendering
# ══════════════════════════════════════════
render_team_queue_summary() {
  if [ ! -f "$QUEUE" ]; then
    echo -e "  ${DIM}(queue not initialized — run /harness-team)${RESET}"
    return
  fi

  local ready blocked in_prog passed failed total
  ready=$(jq '.queue.ready | length' "$QUEUE" 2>/dev/null || echo 0)
  blocked=$(jq '.queue.blocked | length' "$QUEUE" 2>/dev/null || echo 0)
  in_prog=$(jq '.queue.in_progress | length' "$QUEUE" 2>/dev/null || echo 0)
  failed=$(jq '.queue.failed | length' "$QUEUE" 2>/dev/null || echo 0)

  # passed 는 queue.passed ∪ feature-list.json 의 self-passed 를 dedup 합집합으로 계산
  # (과거 sprint 에서 PASS 되어 queue 에서 빠진 feature 도 카운트)
  if [ -f "$FEATURES" ]; then
    passed=$(jq -r --slurpfile q "$QUEUE" '
      ($q[0].queue.passed // []) as $qp |
      ([.features[] | select((.passes // []) | any(. == "evaluator-functional" or . == "evaluator-visual" or . == "evaluator-code-quality")) | .id]) as $sp |
      ($qp + $sp | unique | length)
    ' "$FEATURES" 2>/dev/null || echo 0)
    total=$(jq '.features | length' "$FEATURES" 2>/dev/null || echo 0)
  else
    passed=$(jq '.queue.passed | length' "$QUEUE" 2>/dev/null || echo 0)
    total=$((ready + blocked + in_prog + passed + failed))
  fi
  ready=${ready:-0}; blocked=${blocked:-0}; in_prog=${in_prog:-0}; passed=${passed:-0}; failed=${failed:-0}; total=${total:-0}

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

render_team_status() {
  if [ ! -f "$QUEUE" ]; then return; fi

  local team_count
  team_count=$(jq '.teams | length' "$QUEUE" 2>/dev/null)
  if [ "${team_count:-0}" -eq 0 ]; then return; fi

  echo ""
  echo -e "${BOLD}Teams${RESET}"

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
      gen)  phase_short="${CYAN}Gen${RESET}" ;;
      gate) phase_short="${YELLOW}Gate${RESET}" ;;
      eval) phase_short="${MAGENTA}Eval${RESET}" ;;
      *)    phase_short="${DIM}-${RESET}" ;;
    esac

    printf "  %b%b T%d %-7s %b" "$color" "$icon" "$i" "$t_feature" "$phase_short"
    if [ -n "$t_attempt" ] && [ "$t_attempt" != "—" ]; then
      printf " #%s/5" "$t_attempt"
    fi
    echo ""
  done
}

render_team_features() {
  if [ ! -f "$QUEUE" ] || [ ! -f "$FEATURES" ]; then return; fi

  echo ""
  echo -e "${BOLD}Features${RESET}"

  jq -r --slurpfile q "$QUEUE" '
    ($q[0].queue.passed // []) as $passed |
    ($q[0].queue.failed // []) as $failed |
    ($q[0].queue.ready // []) as $ready |
    ($q[0].queue.in_progress // {}) as $prog |
    ($q[0].queue.blocked // {}) as $blocked |
    .features[] |
    .id as $fid |
    (.name // .title // .description // "?" | if length > 18 then .[0:16] + ".." else . end) as $fname |
    # passed 판정: queue.passed 또는 feature.passes 에 evaluator-functional/visual/code-quality 가 있으면 PASS.
    # 과거 sprint 에서 PASS 된 feature 가 새 sprint queue 재생성 시 queue.passed 에서 누락되어도
    # feature-list.json 의 passes 배열은 이력으로 남아있으므로, 거기서도 검사한다.
    ((.passes // []) | any(. == "evaluator-functional" or . == "evaluator-visual" or . == "evaluator-code-quality")) as $self_passed |
    (if ($fid | IN($passed[])) or $self_passed then "P"
     elif $prog[$fid] then "I|\($prog[$fid].team)|\($prog[$fid].phase)"
     elif ($fid | IN($failed[])) then "F"
     elif ($fid | IN($ready[])) then "R"
     elif $blocked[$fid] then "BLK|\($blocked[$fid] | length)"
     else "U" end) as $st |
    "\($st)\t\($fid)\t\($fname)"
  ' "$FEATURES" 2>/dev/null | while IFS=$'\t' read -r st fid fname; do
    case "$st" in
      P)      printf "  ${GREEN}●${RESET} %-6s %s\n" "$fid" "$fname" ;;
      F)      printf "  ${RED}✗${RESET} %-6s %s\n" "$fid" "$fname" ;;
      R)      printf "  ${YELLOW}○${RESET} %-6s %s\n" "$fid" "$fname" ;;
      BLK\|*) deps=$(echo "$st" | cut -d'|' -f2)
              printf "  ${MAGENTA}◍${RESET} %-6s %-22s ${DIM}blocked (deps:%s)${RESET}\n" "$fid" "$fname" "$deps" ;;
      U)      printf "  ${DIM}◌${RESET} %-6s %s\n" "$fid" "$fname" ;;
      I\|*)   team=$(echo "$st" | cut -d'|' -f2)
              phase=$(echo "$st" | cut -d'|' -f3)
              printf "  ${CYAN}◐${RESET} %-6s %-22s T%s:%s\n" "$fid" "$fname" "$team" "$phase" ;;
      *)      printf "  ? %-6s %s\n" "$fid" "$fname" ;;
    esac
  done
}

render_team_bottleneck() {
  if [ ! -f "$QUEUE" ] || [ ! -f "$FEATURES" ]; then return; fi

  local failed_list
  failed_list=$(jq -r '.queue.failed[]' "$QUEUE" 2>/dev/null)
  if [ -z "$failed_list" ]; then return; fi

  local team_count idle_teams=0 blocked_count in_prog
  team_count=$(jq '.teams | length' "$QUEUE" 2>/dev/null || echo 0)
  blocked_count=$(jq '.queue.blocked | length' "$QUEUE" 2>/dev/null || echo 0)
  in_prog=$(jq '.queue.in_progress | length' "$QUEUE" 2>/dev/null || echo 0)

  for i in $(seq 1 "$team_count"); do
    local ts
    ts=$(jq -r ".teams[\"$i\"].status // \"idle\"" "$QUEUE" 2>/dev/null)
    if [ "$ts" = "idle" ]; then idle_teams=$((idle_teams + 1)); fi
  done

  while IFS= read -r fid; do
    [ -z "$fid" ] && continue
    local deps_on_this
    deps_on_this=$(jq --arg fid "$fid" '[.queue.blocked | to_entries[] | select(.value | index($fid))] | length' "$QUEUE" 2>/dev/null || echo 0)

    if [ "$deps_on_this" -gt 0 ]; then
      echo ""
      echo -e "  ${RED}${BOLD}⚠ BOTTLENECK${RESET} ${RED}${fid}${RESET} failed → ${YELLOW}${deps_on_this} features blocked${RESET}"
      if [ "$idle_teams" -gt 0 ]; then
        echo -e "  ${BOLD}→ requeue:${RESET} bash scripts/harness-queue-manager.sh requeue ${fid} ."
      fi
    fi
  done <<< "$failed_list"

  if [ "$idle_teams" -eq "$team_count" ] && [ "$in_prog" -eq 0 ] && [ "$blocked_count" -gt 0 ]; then
    echo ""
    echo -e "  ${RED}${BOLD}!! STALLED${RESET} — All teams idle, ${blocked_count} features blocked"
  fi
}

# ══════════════════════════════════════════
# Archive Prompt — 처리 완료된 프롬프트 목록
# ══════════════════════════════════════════
render_archive_prompts() {
  if [ ! -f "$PROGRESS_LOG" ]; then return; fi

  # user-prompt 엔트리 중 이후에 result/pass/completed 액션이 있는 것 = 처리 완료
  local all_prompts
  all_prompts=$(grep '| user-prompt |' "$PROGRESS_LOG" 2>/dev/null)
  if [ -z "$all_prompts" ]; then return; fi

  local total_prompts
  total_prompts=$(echo "$all_prompts" | wc -l | tr -d ' ')

  # 마지막 프롬프트를 제외한 모든 프롬프트 = archived (처리 완료)
  # newest first (tac), 전체 출력 (제한 없음)
  local archived
  if [ "$total_prompts" -le 1 ]; then return; fi
  archived=$(echo "$all_prompts" | head -n $((total_prompts - 1)) | tac)

  echo ""
  echo -e "${BOLD}Archive Prompt${RESET}  ${DIM}(처리 완료)${RESET}"

  echo "$archived" | while IFS= read -r line; do
    local ts detail
    ts=$(echo "$line" | awk -F'|' '{gsub(/^ +| +$/,"",$1); print $1}')
    detail=$(echo "$line" | awk -F'|' '{gsub(/^ +| +$/,"",$4); print $4}')

    local short_ts
    short_ts=$(echo "$ts" | grep -oE '[0-9]{2}:[0-9]{2}' | tail -1 || echo "$ts")

    if [ ${#detail} -gt 45 ]; then detail="${detail:0:43}.."; fi

    echo -e "  ${GREEN}✓${RESET} ${DIM}${short_ts}${RESET}  ${detail}"
  done
}

# ══════════════════════════════════════════
# Render dispatch
# ══════════════════════════════════════════
render_dashboard() {
  local mode
  mode=$(get_mode)

  render_header

  case "$mode" in
    team|paused)
      render_team_queue_summary
      render_team_status
      render_team_features
      render_team_bottleneck
      # Archive Prompt는 별도 패널(harness-prompt-history.sh)에서 렌더링 — Dashboard 모니터링 영역 보호
      ;;
    *)
      render_solo_sprint_overview
      render_solo_failure_info

      if [ -f "$FEATURES" ]; then
        render_progress "$PROJECT_ROOT" 2>/dev/null
      fi

      render_solo_agent_info
      # Archive Prompt는 별도 패널(harness-prompt-history.sh)에서 렌더링
      ;;
  esac
}

# ══════════════════════════════════════════
# Main — Auto-refresh loop
# ══════════════════════════════════════════
tput civis 2>/dev/null
trap 'tput cnorm 2>/dev/null; exit 0' EXIT INT TERM

clear

while true; do
  _ROWS=$(tput lines 2>/dev/null || echo 30)
  _COLS=$(tput cols 2>/dev/null || echo 80)
  export _ROWS _COLS
  buf=$(render_dashboard 2>&1)
  tput cup 0 0 2>/dev/null
  # Append ESC[K after every line so each row clears its right-side residue
  # from any previous frame (fixes wrapped shell-prompt bleed-through).
  printf '%s\n' "$buf" | awk '{printf "%s\033[K\n", $0}'
  tput ed 2>/dev/null
  printf "${DIM}  [r] refresh  [q] quit${RESET}\033[K\n"
  wait_or_refresh 3 || true
done
