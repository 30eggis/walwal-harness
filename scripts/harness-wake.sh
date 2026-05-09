#!/bin/bash
# harness-wake.sh — hourly safety wake (v6.2)
#
# launchd 가 1시간 주기로 호출. 등록된 모든 walwal-harness 프로젝트에 대해:
#   1) idle 한 시간이 임계치 이상이면 (.harness/progress.json mtime 기준, review 실행 전 캡처)
#   2) deterministic hourly review 를 디스크에 남김
#   3) 기본값으로 기존 tmux 세션에 긴 prompt 를 주입하지 않고 headless 1-tick Claude 를 실행
#
# 등록 방식: ~/.walwal-harness/projects.list 에 한 줄에 하나씩 절대경로 기재.
# 또는 환경변수 WALWAL_HARNESS_PROJECTS 에 콜론(:)으로 구분된 절대경로 목록.

set -uo pipefail

LOG_DIR="${HOME}/.walwal-harness/logs"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/wake.log"

ts() { date "+%Y-%m-%d %H:%M:%S"; }
say() { echo "[$(ts)] $*" >> "$LOG"; }

stat_mtime() {
  local path="$1"
  stat -f "%m" "$path" 2>/dev/null || stat -c "%Y" "$path" 2>/dev/null
}

in_force_wake_window() {
  local hhmm start end
  hhmm="$(date "+%H%M")"
  start="${HARNESS_WAKE_FORCE_START_HHMM:-0555}"
  end="${HARNESS_WAKE_FORCE_END_HHMM:-0615}"

  # 기본값은 Anthropic 5-hour reset 이 자주 걸리는 06:00 KST 주변.
  # StartInterval=3600 이 몇 분 밀려 실행돼도 복구되도록 20분 창을 둔다.
  [ "$((10#$hhmm))" -ge "$((10#$start))" ] && [ "$((10#$hhmm))" -le "$((10#$end))" ]
}

find_tmux_session() {
  local project_root="$1"
  local base sanitized upper var cand

  base=$(basename "$project_root")
  sanitized=$(echo "$base" | tr -- '-. ' '___')
  for cand in "claude_${sanitized}_" "claude_${base}_"; do
    if tmux has-session -t "$cand" 2>/dev/null; then
      echo "$cand"
      return 0
    fi
  done

  upper=$(echo "$sanitized" | tr 'a-z' 'A-Z')
  var="WALWAL_HARNESS_TMUX_${upper}"
  if [ -n "${!var:-}" ] && tmux has-session -t "${!var}" 2>/dev/null; then
    echo "${!var}"
    return 0
  fi

  return 1
}

start_headless_tick() {
  local project_root="$1"
  local idle="$2"
  local force="$3"
  local review_path="$4"
  local mode stamp wake_dir ops_dir prompt_rel log_rel prompt_path log_path pid_file old_pid pid status tmux_session

  mode="${HARNESS_WAKE_MODE:-headless}"
  stamp="$(date -u "+%Y%m%dT%H%M%SZ")"
  wake_dir="$project_root/.harness/actions/wake"
  ops_dir="$project_root/.harness/ops/wake"
  mkdir -p "$wake_dir" "$ops_dir"

  prompt_rel=".harness/actions/wake/wake-${stamp}.prompt.md"
  log_rel=".harness/ops/wake/wake-${stamp}.log"
  prompt_path="$project_root/$prompt_rel"
  log_path="$project_root/$log_rel"
  pid_file="$ops_dir/wake.pid"

  if [ -f "$pid_file" ]; then
    old_pid="$(cat "$pid_file" 2>/dev/null || true)"
    if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
      say "skip-headless: $project_root (previous wake pid=$old_pid still running)"
      return 0
    fi
  fi

  cat > "$prompt_path" <<EOF
You are the walwal-harness autonomous hourly wake tick.

Project root: $project_root
Wake reason: idle=${idle}s force=${force}
Hourly review: ${review_path:-"(not available)"}

Policy:
- Owner input after the initial GOAL is an interrupt or additional request, never a reason to wait.
- Never set conductor.state to waiting_owner. Normalize any waiting_owner state to waiting_meeting and continue.
- meeting-manager is the default synchronization loop. Incidents, service warnings, goal drift, and escalations go to meeting-manager first.
- Keep this to one bounded autonomous tick. Do not run an endless loop.
- Do not write future timestamps to .harness/progress.log or artifacts.
- Keep terminal output concise; write evidence to project files.

Tasks:
1. Read CONVENTIONS.md if present, .harness/conventions/shared.md, relevant .harness/conventions/<role>.md, .harness/gotchas/<role>.md, .harness/memory.md, .harness/progress.json, and the hourly review above.
2. If service_ops.requested_mode is monitor, run or trigger one service-ops monitor pass and record last_check. stream_active may be true only during the pass and must be false when finished.
3. Treat the hourly review as Executive Meeting Minutes. Verify it contains CEO/COO/CTO/CQO/Service-Ops role positions, discussion, decision JSON, and action items.
4. Check conductor state against the current GOAL and route the next department without waiting for Owner.
5. If there is an active incident or operational warning, make sure meeting-manager has shared context and an action decision that names CTO/CQO/Service-Ops responsibilities.
6. Append a short factual summary to .harness/progress.log and any normal harness artifacts used by this project.
EOF

  case "$mode" in
    record)
      status="recorded"
      ;;
    headless|"")
      if command -v claude >/dev/null 2>&1; then
        (
          cd "$project_root" || exit 1
          claude -p "$(cat "$prompt_path")" > "$log_path" 2>&1
        ) &
        pid=$!
        echo "$pid" > "$pid_file"
        status="spawned pid=$pid"
      else
        status="recorded claude-not-found"
      fi
      ;;
    *)
      status="recorded unsupported-mode=$mode"
      ;;
  esac

  echo "$(date -u "+%Y-%m-%dT%H:%M:%SZ") | wake | headless | $status | idle=${idle}s | force=${force} | prompt=$prompt_rel | log=$log_rel" >> "$project_root/.harness/progress.log"
  say "wake-headless: $project_root (idle ${idle}s, force=${force}, mode=${mode}) → $status $log_rel"

  if tmux_session="$(find_tmux_session "$project_root" 2>/dev/null)"; then
    tmux display-message -t "$tmux_session" "walwal wake headless tick: $status ($log_rel)" 2>/dev/null || true
  fi
}

PROJECTS_LIST="${HOME}/.walwal-harness/projects.list"
PROJECTS=()

if [ -n "${WALWAL_HARNESS_PROJECTS:-}" ]; then
  IFS=':' read -r -a PROJECTS <<< "$WALWAL_HARNESS_PROJECTS"
elif [ -f "$PROJECTS_LIST" ]; then
  while IFS= read -r line; do
    line="${line%%#*}"
    line="$(echo "$line" | xargs)"
    [ -z "$line" ] && continue
    PROJECTS+=("$line")
  done < "$PROJECTS_LIST"
fi

if [ "${#PROJECTS[@]}" -eq 0 ]; then
  say "no registered projects (set ~/.walwal-harness/projects.list or WALWAL_HARNESS_PROJECTS)"
  exit 0
fi

# 임계치: idle 60분 이상이면 깨운다 (Stop 훅이 정상 동작하면 거의 연속 활동이므로
# 1시간 이상 정지 = 어디선가 멈춘 상태로 판단)
IDLE_THRESHOLD_SECONDS="${HARNESS_WAKE_IDLE_SECONDS:-3300}"   # 55분 (안전 마진)
NOW_EPOCH=$(date "+%s")
FORCE_WAKE=0
if in_force_wake_window; then
  FORCE_WAKE=1
fi

for PROJECT_ROOT in "${PROJECTS[@]}"; do
  if [ ! -d "$PROJECT_ROOT" ]; then
    say "skip: $PROJECT_ROOT (not a directory)"
    continue
  fi
  PROGRESS="$PROJECT_ROOT/.harness/progress.json"
  if [ ! -f "$PROGRESS" ]; then
    say "skip: $PROJECT_ROOT (no .harness/progress.json)"
    continue
  fi
  PROJECT_FORCE_WAKE="$FORCE_WAKE"

  if command -v jq >/dev/null 2>&1 && [ "$(jq -r '.conductor.state // "idle"' "$PROGRESS" 2>/dev/null || echo idle)" = "waiting_owner" ]; then
    if [ -x "$PROJECT_ROOT/scripts/harness-progress-set.sh" ]; then
      bash "$PROJECT_ROOT/scripts/harness-progress-set.sh" "$PROJECT_ROOT" \
        '.conductor.state = "waiting_meeting" |
         .conductor.current_action = "autonomous-normalize-waiting-owner" |
         .next_agent = "meeting-manager" |
         .agent_status = "pending" |
         .meetings.active = ((.meetings.active // []) + ["meeting-manager"] | unique) |
         .meetings.requested_type = (.meetings.requested_type // "followup-review") |
         .meetings.requested_reason = (.meetings.requested_reason // "autonomous-normalize-waiting-owner") |
         .workflow.stage = "ops-monitoring" |
         .workflow.last_transition = (now | todate) |
         .workflow.last_reason = "autonomous-normalize-waiting-owner"' \
        >/dev/null 2>&1 || true
      say "normalize: $PROJECT_ROOT (conductor=waiting_owner → waiting_meeting)"
      PROJECT_FORCE_WAKE=1
    fi
  fi

  # idle 시간은 hourly-review 실행 전에 캡처한다. review 는 progress.json 과
  # progress.log 를 갱신하므로, 이후 mtime 을 보면 wake 가 자기 활동을
  # "프로젝트 활동 중"으로 오판한다.
  if MTIME=$(stat_mtime "$PROGRESS"); then :;
  else
    say "skip: $PROJECT_ROOT (cannot stat progress.json)"
    continue
  fi
  IDLE=$((NOW_EPOCH - MTIME))

  # Every hourly batch must leave disk-backed evidence, even if Claude/tmux is
  # stopped or busy. This deterministic review runs after the idle snapshot.
  if [ -x "$PROJECT_ROOT/scripts/harness-hourly-review.sh" ]; then
    review_output=$(bash "$PROJECT_ROOT/scripts/harness-hourly-review.sh" "$PROJECT_ROOT" 2>/dev/null || true)
    review_path=$(printf "%s\n" "$review_output" | grep -Eo '(/[^[:space:]]+|[.][^[:space:]]+)\.md' | tail -1)
    if [ -z "$review_path" ]; then
      review_path=$(printf "%s\n" "$review_output" | tail -1)
    fi
    if [ -n "$review_path" ]; then
      say "review: $PROJECT_ROOT → $review_path"
    else
      say "review-fail: $PROJECT_ROOT"
    fi
  fi

  if [ "$IDLE" -lt "$IDLE_THRESHOLD_SECONDS" ] && [ "$PROJECT_FORCE_WAKE" -ne 1 ]; then
    say "skip: $PROJECT_ROOT (idle ${IDLE}s < threshold ${IDLE_THRESHOLD_SECONDS}s — 활동 중)"
    continue
  fi

  # 회사 루프가 멈춘 상태인지 확인
  if command -v jq >/dev/null 2>&1; then
    CSTATE=$(jq -r '.conductor.state // "idle"' "$PROGRESS" 2>/dev/null || echo "idle")
    SSTATUS=$(jq -r '.sprint.status // "init"' "$PROGRESS" 2>/dev/null || echo "init")
    if [ "$SSTATUS" = "completed" ] || [ "$SSTATUS" = "aborted" ]; then
      say "continue: $PROJECT_ROOT (sprint=$SSTATUS — autonomous review still required)"
    fi
    if [ "$CSTATE" = "paused" ] || [ "$CSTATE" = "completed" ] || [ "$CSTATE" = "escalated" ]; then
      say "continue: $PROJECT_ROOT (conductor=$CSTATE — route through meeting-manager/service-ops)"
    fi
  fi

  # 발화 직전 service-ops monitor 트리거 partial update.
  # requested_mode 만 set — conductor-tick 이 이걸 보고 service-ops 를 spawn 한다.
  # stream_active 는 service-ops 본인이 spawn 시 §3.1.1 에 따라 직접 set (정직성 룰).
  # auto-retro / incident / null / monitor 가 아닌 모드가 진행 중이면 덮어쓰지 않음.
  if [ -x "$PROJECT_ROOT/scripts/harness-progress-set.sh" ]; then
    bash "$PROJECT_ROOT/scripts/harness-progress-set.sh" "$PROJECT_ROOT" \
      'if (.service_ops.requested_mode // "") == "" or (.service_ops.requested_mode // "") == "monitor" or (.service_ops.requested_mode // "") == "auto-retro"
       then .service_ops.requested_mode = "monitor" |
            .service_ops.monitor.wake_trigger_at = (now | todate)
       else . end' \
      >/dev/null 2>&1 || true
  fi

  start_headless_tick "$PROJECT_ROOT" "$IDLE" "$PROJECT_FORCE_WAKE" "$review_path"
done

exit 0
