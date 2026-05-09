#!/bin/bash
# harness-session-start.sh — SessionStart 훅
# 새 세션 시작 시 자동으로:
#   1) 이전 에이전트가 completed이면 harness-next.sh 실행 (게이트 + handoff)
#   2) Planner/Dispatcher 사이클이면 audit 리셋
#   3) 모드별 안내 출력

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB="$SCRIPT_DIR/lib/harness-render-progress.sh"
AUDIT_LIB="$SCRIPT_DIR/lib/harness-audit.sh"
MIGRATE_LIB="$SCRIPT_DIR/lib/harness-progress-migrate.sh"

if [ ! -f "$LIB" ]; then exit 0; fi
source "$LIB"
[ -f "$AUDIT_LIB" ] && source "$AUDIT_LIB"
[ -f "$MIGRATE_LIB" ] && source "$MIGRATE_LIB"
command -v jq &>/dev/null || exit 0

PROJECT_ROOT="$(resolve_harness_root "." 2>/dev/null)" || exit 0
PROGRESS="$PROJECT_ROOT/.harness/progress.json"
CONFIG="$PROJECT_ROOT/.harness/config.json"
HANDOFF="$PROJECT_ROOT/.harness/handoff.json"
[ -f "$PROGRESS" ] || exit 0

# v6.2 — idempotent schema migration (parallel tracks fields, etc.)
if declare -f migrate_progress_schema >/dev/null 2>&1; then
  migrate_progress_schema "$PROGRESS" || true
fi

sprint_status=$(jq -r '.sprint.status // "init"' "$PROGRESS" 2>/dev/null)
sprint_num=$(jq -r '.sprint.number // 0' "$PROGRESS" 2>/dev/null)
current_agent=$(jq -r '.current_agent // "none"' "$PROGRESS" 2>/dev/null)
next_agent=$(jq -r '.next_agent // "none"' "$PROGRESS" 2>/dev/null)
agent_status=$(jq -r '.agent_status // "pending"' "$PROGRESS" 2>/dev/null)
mode=$(jq -r '.mode // "company"' "$PROGRESS" 2>/dev/null)
conductor_state=$(jq -r '.conductor.state // "idle"' "$PROGRESS" 2>/dev/null)
task_stop_active=$(jq -r '.task_stop.active // false' "$PROGRESS" 2>/dev/null)
task_stop_reason=$(jq -r '.task_stop.reason // "null"' "$PROGRESS" 2>/dev/null)
task_stop_resume_after=$(jq -r '.task_stop.resume_after // "null"' "$PROGRESS" 2>/dev/null)
task_stop_notified_at=$(jq -r '.task_stop.resume_notified_at // "null"' "$PROGRESS" 2>/dev/null)
task_stop_wake_target=$(jq -r '.task_stop.wake_target // .next_agent // "none"' "$PROGRESS" 2>/dev/null)
task_stop_task_session=$(jq -r '.task_stop.task_session_path // "null"' "$PROGRESS" 2>/dev/null)

parse_iso_epoch() {
  local iso="${1:-}"
  [ -n "$iso" ] && [ "$iso" != "null" ] || return 1
  date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$iso" "+%s" 2>/dev/null \
    || date -u -d "$iso" "+%s" 2>/dev/null
}

now_epoch() {
  date -u "+%s"
}

# ─────────────────────────────────────────
# Normalize legacy mode drift — v6.3+ always runs company mode.
# ─────────────────────────────────────────
FEATURE_QUEUE_HEAL="$PROJECT_ROOT/.harness/actions/feature-queue.json"
if [ "$mode" != "company" ]; then
  bash "$SCRIPT_DIR/harness-progress-set.sh" "$PROJECT_ROOT" \
    '.mode = "company" |
     .mode_decision.owner = "conductor" |
     .mode_decision.policy = "always_company_parallel" |
     .mode_decision.user_override = null |
     .mode_decision.decided_at = (now | todate) |
     .mode_decision.rationale = "legacy mode normalized to always-on company mode"' \
    2>/dev/null || true
  mode="company"
  [ -f "$PROJECT_ROOT/.harness/progress.log" ] && echo "$(date +'%Y-%m-%d %H:%M') | system | heal | mode | normalized legacy mode to company" >> "$PROJECT_ROOT/.harness/progress.log"
fi

# ─────────────────────────────────────────
# Truthful Logging Heal — strip future-dated progress.log entries
# ─────────────────────────────────────────
PROGRESS_LOG="$PROJECT_ROOT/.harness/progress.log"
if [ -f "$PROGRESS_LOG" ]; then
  NOW_KST=$(date "+%Y-%m-%d %H:%M")
  NOW_UTC_MIN=$(date -u "+%Y-%m-%d %H:%M")
  QUARANTINE_FILE="$PROGRESS_LOG.future-quarantine.$(date +%s)"
  KEEP_FILE="$PROGRESS_LOG.tmp.$$"

  # 미래 시각으로 시작하는 라인 격리. KST(YYYY-MM-DD HH:MM) 와 ISO(YYYY-MM-DDTHH:MM:SSZ) 둘 다 처리.
  awk -v now_kst="$NOW_KST" -v now_utc="$NOW_UTC_MIN" -v qfile="$QUARANTINE_FILE" '
    function iso_to_minute(s) {
      gsub("\\[", "", s); gsub("T", " ", s); gsub("Z", "", s)
      return substr(s, 1, 16)
    }
    {
      future=0
      if (match($0, /^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}/)) {
        ts = substr($0, RSTART, RLENGTH)
        if (ts > now_kst) future=1
      } else if (match($0, /^\[?[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}/)) {
        ts_min = iso_to_minute(substr($0, RSTART, RLENGTH+5))
        if (ts_min > now_utc) future=1
      }
      if (future) print >> qfile
      else print
    }
  ' "$PROGRESS_LOG" > "$KEEP_FILE"

  if [ -f "$QUARANTINE_FILE" ] && [ -s "$QUARANTINE_FILE" ]; then
    QCOUNT=$(wc -l < "$QUARANTINE_FILE" | tr -d ' ')
    mv "$KEEP_FILE" "$PROGRESS_LOG"
    echo "$(date +'%Y-%m-%d %H:%M') | system | heal | log | quarantined ${QCOUNT} future-dated lines → $(basename "$QUARANTINE_FILE")" >> "$PROGRESS_LOG"
  else
    rm -f "$KEEP_FILE" "$QUARANTINE_FILE" 2>/dev/null
  fi
fi

# ─────────────────────────────────────────
# Company Mode — autonomous parallel company loop
# ─────────────────────────────────────────
if [ "$mode" = "company" ]; then
  FEATURE_QUEUE="$PROJECT_ROOT/.harness/actions/feature-queue.json"
  passed=0; total=0; in_prog=0; failed=0
  if [ -f "$FEATURE_QUEUE" ]; then
    passed=$(jq '.queue.passed | length' "$FEATURE_QUEUE" 2>/dev/null || echo 0)
    total=$(jq '[.queue.ready, (.queue.blocked | keys), (.queue.in_progress | keys), .queue.passed, .queue.failed] | flatten | length' "$FEATURE_QUEUE" 2>/dev/null || echo 0)
    in_prog=$(jq '.queue.in_progress | length' "$FEATURE_QUEUE" 2>/dev/null || echo 0)
    failed=$(jq '.queue.failed | length' "$FEATURE_QUEUE" 2>/dev/null || echo 0)
  fi

  echo "# Harness Company Mode active"
  echo "# Queue: ${passed}/${total} passed, ${in_prog} in progress, ${failed} failed"
  echo "# Company loop runs autonomously with parallel workers. Owner input is an interrupt only; do not wait for Owner after the initial GOAL."
  exit 0
fi

# ─────────────────────────────────────────
# TokenLimit hold — zero-token resume reminder
# ─────────────────────────────────────────
if [ "$task_stop_active" = "true" ] && [ "$task_stop_reason" = "TokenLimit" ]; then
  retry_interval=$(jq -r '.token_limit.re_notify_every_seconds // 3600' "$CONFIG" 2>/dev/null || echo 3600)
  resume_after_epoch=$(parse_iso_epoch "$task_stop_resume_after" || echo 0)
  now_ts=$(now_epoch)
  notified_epoch=$(parse_iso_epoch "$task_stop_notified_at" || echo 0)

  if [ "$now_ts" -lt "$resume_after_epoch" ]; then
    echo "# Harness paused — TokenLimit hold"
    echo "# Wake target: /harness-${task_stop_wake_target}"
    echo "# Retry after: ${task_stop_resume_after}"
    if [ "$task_stop_task_session" != "null" ] && [ -n "$task_stop_task_session" ]; then
      echo "# Task session: ${task_stop_task_session}"
    fi
    exit 0
  fi

  if [ "$notified_epoch" -eq 0 ] || [ $((now_ts - notified_epoch)) -ge "$retry_interval" ]; then
    bash "$SCRIPT_DIR/harness-progress-set.sh" "$PROJECT_ROOT" \
      ".agent_status = \"pending\" |
       .current_agent = null |
       .next_agent = \"${task_stop_wake_target}\" |
       .task_stop.active = false |
       .task_stop.resume_ready = true |
       .task_stop.resume_notified_at = (now | todate)" \
      >/dev/null 2>&1 || true
    echo "# Harness resume ready — TokenLimit hold expired"
    echo "# Resume target: /harness-${task_stop_wake_target}"
    if [ "$task_stop_task_session" != "null" ] && [ -n "$task_stop_task_session" ]; then
      echo "# Resume with task session: ${task_stop_task_session}"
    fi
    exit 0
  fi
fi

# ─────────────────────────────────────────
# init 상태: 첫 안내
# ─────────────────────────────────────────
if [ "$sprint_status" = "init" ]; then
  if [ "$next_agent" != "null" ] && [ "$next_agent" != "none" ] && [ "$next_agent" != "dispatcher" ]; then
    echo "# Harness Company Mode active"
    echo "# Sprint is init, but next_agent=${next_agent}; continue the autonomous loop instead of waiting for Owner."
  else
  echo "# Harness ready — say \"하네스 엔지니어링 시작\" or /harness-dispatcher"
  echo "# 기본 경로는 회사 루프입니다: dispatch -> CEO meeting -> COO/CTO 분배 -> gen/eval -> CQO -> service-ops -> batch meeting."
  exit 0
  fi
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
# Conductor running/queued → refresh routing once on session start
# ─────────────────────────────────────────
if [ "$conductor_state" = "running" ] || [ "$next_agent" = "conductor" ]; then
  if [ -x "$SCRIPT_DIR/conductor-tick.sh" ]; then
    bash "$SCRIPT_DIR/conductor-tick.sh" "$PROJECT_ROOT" >/dev/null 2>&1 || true
    next_agent=$(jq -r '.next_agent // "none"' "$PROGRESS" 2>/dev/null)
  fi
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
