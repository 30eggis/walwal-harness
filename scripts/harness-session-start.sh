#!/bin/bash
# harness-session-start.sh — SessionStart 훅
# 새 세션 시작 시 자동으로:
#   1) 이전 에이전트가 completed이면 harness-next.sh 실행 (게이트 + handoff)
#   2) Planner/Dispatcher 사이클이면 audit 리셋
#   3) 모드별 안내 출력

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB="$SCRIPT_DIR/lib/harness-render-progress.sh"
AUDIT_LIB="$SCRIPT_DIR/lib/harness-audit.sh"

if [ ! -f "$LIB" ]; then exit 0; fi
source "$LIB"
[ -f "$AUDIT_LIB" ] && source "$AUDIT_LIB"
command -v jq &>/dev/null || exit 0

PROJECT_ROOT="$(resolve_harness_root "." 2>/dev/null)" || exit 0
PROGRESS="$PROJECT_ROOT/.harness/progress.json"
CONFIG="$PROJECT_ROOT/.harness/config.json"
HANDOFF="$PROJECT_ROOT/.harness/handoff.json"
[ -f "$PROGRESS" ] || exit 0

sprint_status=$(jq -r '.sprint.status // "init"' "$PROGRESS" 2>/dev/null)
sprint_num=$(jq -r '.sprint.number // 0' "$PROGRESS" 2>/dev/null)
current_agent=$(jq -r '.current_agent // "none"' "$PROGRESS" 2>/dev/null)
next_agent=$(jq -r '.next_agent // "none"' "$PROGRESS" 2>/dev/null)
agent_status=$(jq -r '.agent_status // "pending"' "$PROGRESS" 2>/dev/null)
mode=$(jq -r '.mode // "solo"' "$PROGRESS" 2>/dev/null)

# ─────────────────────────────────────────
# Auto-heal mode drift — Team 상태 유실 복구
#   feature-queue.json 에 활성 작업(in_progress)이 있는데 mode 가 solo/paused 면
#   누군가 progress.json 을 통째로 덮어써서 team_state 를 날린 것. mode=team 으로
#   자동 복원하고 경고 로그 남김.
# ─────────────────────────────────────────
FEATURE_QUEUE_HEAL="$PROJECT_ROOT/.harness/actions/feature-queue.json"
if [ -f "$FEATURE_QUEUE_HEAL" ] && [ "$mode" != "team" ]; then
  active_count=$(jq -r '(.queue.in_progress | length) // 0' "$FEATURE_QUEUE_HEAL" 2>/dev/null || echo 0)
  if [ "${active_count:-0}" -gt 0 ]; then
    heal_teams=$active_count
    [ "$heal_teams" -gt 3 ] && heal_teams=3
    bash "$SCRIPT_DIR/harness-progress-set.sh" "$PROJECT_ROOT" \
      ".mode = \"team\" | .team_state.active_teams = ${heal_teams} | .team_state.paused_at = null" \
      2>/dev/null
    mode="team"
    echo "# Harness: mode auto-healed to 'team' (feature-queue has ${active_count} active, but mode was drifted)" >&2
    if [ -f "$PROJECT_ROOT/.harness/progress.log" ]; then
      echo "$(date +'%Y-%m-%d %H:%M') | system | heal | mode | reset solo→team (queue had ${active_count} in_progress)" >> "$PROJECT_ROOT/.harness/progress.log"
    fi
  fi
fi

# ─────────────────────────────────────────
# Team Mode — 팀이 자율 실행 중이면 오케스트레이터 안내
# ─────────────────────────────────────────
if [ "$mode" = "team" ]; then
  FEATURE_QUEUE="$PROJECT_ROOT/.harness/actions/feature-queue.json"
  passed=0; total=0; in_prog=0; failed=0
  if [ -f "$FEATURE_QUEUE" ]; then
    passed=$(jq '.queue.passed | length' "$FEATURE_QUEUE" 2>/dev/null || echo 0)
    total=$(jq '[.queue.ready, (.queue.blocked | keys), (.queue.in_progress | keys), .queue.passed, .queue.failed] | flatten | length' "$FEATURE_QUEUE" 2>/dev/null || echo 0)
    in_prog=$(jq '.queue.in_progress | length' "$FEATURE_QUEUE" 2>/dev/null || echo 0)
    failed=$(jq '.queue.failed | length' "$FEATURE_QUEUE" 2>/dev/null || echo 0)
  fi

  echo "# Harness Team Mode active"
  echo "# Queue: ${passed}/${total} passed, ${in_prog} in progress, ${failed} failed"
  echo "# Teams run autonomously (Gen-Eval loop, max 5 retries)."
  echo "# Stop: /harness-stop | Switch to solo: /harness-solo"
  exit 0
fi

# ─────────────────────────────────────────
# Paused Mode — 중단 상태 안내
# ─────────────────────────────────────────
if [ "$mode" = "paused" ]; then
  echo "# Harness paused — resume with /harness-team or /harness-solo"
  exit 0
fi

# ─────────────────────────────────────────
# init 상태: 첫 안내
# ─────────────────────────────────────────
if [ "$sprint_status" = "init" ]; then
  echo "# Harness ready — say \"하네스 엔지니어링 시작\" or /harness-dispatcher"
  echo "# 기본은 Solo 모드. 병렬 3팀 실행을 원하면 Planner 완료 후 /harness-team."
  exit 0
fi

# ─────────────────────────────────────────
# Audit lifecycle: Planner/Dispatcher 시작 시 리셋
# ─────────────────────────────────────────
init_audit "$PROJECT_ROOT"
if [ "$next_agent" = "planner" ] || [ "$next_agent" = "dispatcher" ]; then
  # 새 사이클 — 이전 audit을 archive로 이동하고 새로 시작
  reset_audit "$PROJECT_ROOT" "$sprint_num"
  audit_log "system" "cycle" "start" "sprint-${sprint_num}" "new plan/dispatch cycle"
fi

# ─────────────────────────────────────────
# 이전 에이전트가 completed/failed → 자동 전환
# ─────────────────────────────────────────
if [ "$agent_status" = "completed" ] || [ "$agent_status" = "failed" ]; then
  bash "$SCRIPT_DIR/harness-next.sh" "$PROJECT_ROOT" 2>/dev/null

  next_agent=$(jq -r '.next_agent // "none"' "$PROGRESS" 2>/dev/null)
  agent_status=$(jq -r '.agent_status // "pending"' "$PROGRESS" 2>/dev/null)
fi

# ─────────────────────────────────────────
# 상태별 안내 출력
# ─────────────────────────────────────────
if [ "$agent_status" = "blocked" ]; then
  echo "# Harness BLOCKED — retry limit reached, user intervention required"

elif [ -f "$HANDOFF" ] && [ "$next_agent" != "none" ] && [ "$next_agent" != "null" ]; then
  handoff_model=$(jq -r '.model // "opus"' "$HANDOFF" 2>/dev/null)
  handoff_thinking=$(jq -r '.thinking_mode // empty' "$HANDOFF" 2>/dev/null)

  mode_str=""
  if [ -n "$handoff_thinking" ] && [ "$handoff_thinking" != "null" ]; then
    mode_str=" /${handoff_thinking}"
  fi

  echo "# Harness: next → /harness-${next_agent}  (${handoff_model}${mode_str})"

elif [ "$current_agent" != "none" ] && [ "$current_agent" != "null" ]; then
  echo "# Harness: ${current_agent} [${agent_status}]"
fi
