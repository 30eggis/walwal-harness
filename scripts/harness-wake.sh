#!/bin/bash
# harness-wake.sh — hourly safety wake (v6.2)
#
# launchd 가 1시간 주기로 호출. 등록된 모든 walwal-harness 프로젝트에 대해:
#   1) tmux 세션이 살아있는지 확인
#   2) idle 한 시간이 임계치 이상이면 (.harness/progress.json mtime 기준, review 실행 전 캡처)
#   3) tmux 세션에 안전한 continuation prompt 송출
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
    review_path=$(bash "$PROJECT_ROOT/scripts/harness-hourly-review.sh" "$PROJECT_ROOT" 2>/dev/null || true)
    if [ -n "$review_path" ]; then
      say "review: $PROJECT_ROOT → $review_path"
    else
      say "review-fail: $PROJECT_ROOT"
    fi
  fi

  # tmux 세션명 추론: claude_<basename>_  (dash/space → underscore)
  # 예: okx → claude_okx_, walwal-harness → claude_walwal_harness_
  base=$(basename "$PROJECT_ROOT")
  sanitized=$(echo "$base" | tr -- '-. ' '___')
  CANDIDATES=("claude_${sanitized}_" "claude_${base}_")
  TMUX_SESSION=""
  for cand in "${CANDIDATES[@]}"; do
    if tmux has-session -t "$cand" 2>/dev/null; then
      TMUX_SESSION="$cand"
      break
    fi
  done
  if [ -z "$TMUX_SESSION" ]; then
    # WALWAL_HARNESS_TMUX_<UPPER_SANITIZED> 환경변수로 직접 지정 가능
    upper=$(echo "$sanitized" | tr 'a-z' 'A-Z')
    var="WALWAL_HARNESS_TMUX_${upper}"
    if [ -n "${!var:-}" ] && tmux has-session -t "${!var}" 2>/dev/null; then
      TMUX_SESSION="${!var}"
    else
      say "skip: $PROJECT_ROOT (tmux session 추론 실패 — 시도: ${CANDIDATES[*]}; $var 환경변수로 직접 지정 가능)"
      continue
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

  # tmux 세션이 입력 대기 중일 때만 prompt 송출 (대시보드 첨부 모니터 paneltop 회피)
  if [ "$PROJECT_FORCE_WAKE" -eq 1 ]; then
    PROMPT="자율 회사 루프 깨우기 (limit-reset force wake): Anthropic limit reset 이후 정지 복구를 우선 점검하고, conductor 상태 확인 후 다음 부서를 spawn 하라. progress.log 에는 절대 미래 시각을 쓰지 마라."
  else
    PROMPT="자율 회사 루프 깨우기 (hourly wake): Owner 입력은 interrupt 로만 취급한다. conductor 가 waiting_owner 여도 대기하지 말고 meeting-manager 를 기본 루프로 삼아 goal 기준 운영 리뷰, service-ops 점검, 다음 부서 spawn 을 진행하라. progress.log 에는 절대 미래 시각을 쓰지 마라."
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

  # tmux send-keys: Claude CLI 의 입력창에 prompt 입력 + submit.
  # Claude CLI 는 multi-line 입력을 지원하므로 단일 Enter 는 줄바꿈으로 처리되는 경우가 많다.
  # 텍스트 → 짧은 대기 → Enter (submit) 의 두 단계로 분리해서 안정적으로 submit.
  WAKE_PROMPT="$PROMPT 그리고 service-ops 가 monitor 모드로 한 바퀴 돌게 해서 운영 상태를 갱신하라 (last_check, stream_active=true→완료 후 false)."
  if tmux send-keys -t "$TMUX_SESSION" -l "$WAKE_PROMPT" 2>/dev/null; then
    sleep 0.3
    tmux send-keys -t "$TMUX_SESSION" Enter 2>/dev/null
    if [ "$PROJECT_FORCE_WAKE" -eq 1 ]; then
      say "wake: $PROJECT_ROOT (idle ${IDLE}s, force=limit-reset) → tmux $TMUX_SESSION (+ service-ops monitor trigger)"
    else
      say "wake: $PROJECT_ROOT (idle ${IDLE}s) → tmux $TMUX_SESSION (+ service-ops monitor trigger)"
    fi
  else
    say "wake-fail: $PROJECT_ROOT (tmux send-keys failed)"
  fi
done

exit 0
