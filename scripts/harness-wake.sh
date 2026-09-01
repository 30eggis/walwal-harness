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

export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

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

resolve_agent_bin() {
  local executor="$1"
  local env_name cand

  case "$executor" in
    codex)
      env_name="${HARNESS_CODEX_BIN:-${CODEX_BIN:-}}"
      ;;
    claude|*)
      env_name="${HARNESS_CLAUDE_BIN:-${CLAUDE_BIN:-}}"
      executor="claude"
      ;;
  esac

  for cand in "$env_name" "$HOME/.local/bin/$executor" "/opt/homebrew/bin/$executor" "/usr/local/bin/$executor"; do
    [ -n "$cand" ] && [ -x "$cand" ] && { echo "$cand"; return 0; }
  done

  command -v "$executor" 2>/dev/null && return 0
  return 1
}

run_conductor_fallback() {
  local project_root="$1"
  local reason="$2"
  local tick="$project_root/scripts/conductor-tick.sh"
  local progress="$project_root/.harness/progress.json"
  local progress_set="$project_root/scripts/harness-progress-set.sh"
  local before after status

  [ "${HARNESS_WAKE_CONDUCTOR_FALLBACK:-1}" = "1" ] || return 0
  [ -x "$tick" ] || return 0
  [ -f "$progress" ] || return 0
  command -v jq >/dev/null 2>&1 || return 0

  before="$(jq -c '{current_agent,next_agent,agent_status,conductor:(.conductor.state // null),decision:(.meetings.decision // {})}' "$progress" 2>/dev/null || echo '{}')"

  if [ -x "$progress_set" ] &&
    jq -e '
      (.meetings.decision.owner // "") != "" and
      ((((.meetings.active // []) | length) > 0) or ((.meetings.decision.required_execution // null) != null))
    ' "$progress" >/dev/null 2>&1 && {
      [ "$(jq -r '.current_agent // ""' "$progress")" != "meeting-manager" ] ||
      [ "$(jq -r '.agent_status // ""' "$progress")" != "completed" ];
    }; then
    bash "$progress_set" "$project_root" '
      .current_agent = "meeting-manager" |
      .agent_status = "completed" |
      .conductor.state = "running" |
      .conductor.current_action = "wake-meeting-decision-ready" |
      .workflow.last_transition = (now | todate) |
      .workflow.last_reason = "wake-meeting-decision-ready"
    ' >/dev/null 2>&1 || true
  fi

  if bash "$tick" "$project_root" >/dev/null 2>&1; then
    status="ok"
  else
    status="failed"
  fi

  after="$(jq -c '{current_agent,next_agent,agent_status,conductor:(.conductor.state // null),last_action:(.conductor.current_action // null)}' "$progress" 2>/dev/null || echo '{}')"
  echo "$(date -u "+%Y-%m-%dT%H:%M:%SZ") | wake | conductor-fallback | $status | reason=$reason | before=$before | after=$after" >> "$project_root/.harness/progress.log"
  say "conductor-fallback: $project_root ($status, reason=$reason)"
}

start_headless_tick() {
  local project_root="$1"
  local idle="$2"
  local force="$3"
  local review_path="$4"
  local mode executor wake_model agent_bin auto_approve_flag stamp ops_dir activity_dir prompt_scratch log_rel log_path pid_file old_pid pid status tmux_session session_name session_safe wake_prompt log_note

  if command -v jq >/dev/null 2>&1 && [ -f "$project_root/.harness/config.json" ]; then
    mode="${HARNESS_WAKE_MODE:-$(jq -r '.company_mode.hourly_wake_mode // "headless"' "$project_root/.harness/config.json" 2>/dev/null || echo headless)}"
    executor="${HARNESS_WAKE_EXECUTOR:-$(jq -r '.company_mode.hourly_wake_executor // "claude"' "$project_root/.harness/config.json" 2>/dev/null || echo claude)}"
    wake_model="${HARNESS_WAKE_MODEL:-$(jq -r '.company_mode.hourly_wake_model // ""' "$project_root/.harness/config.json" 2>/dev/null || true)}"
  else
    mode="${HARNESS_WAKE_MODE:-headless}"
    executor="${HARNESS_WAKE_EXECUTOR:-claude}"
    wake_model="${HARNESS_WAKE_MODEL:-}"
  fi
  # Autonomous wake agents run unattended: accept all tool/MCP usage so the tick
  # never blocks on a permission prompt nobody is there to answer (default = accept all).
  if [ "$executor" = "codex" ]; then
    auto_approve_flag="--dangerously-bypass-approvals-and-sandbox"
  else
    auto_approve_flag="--dangerously-skip-permissions"
  fi
  stamp="$(date -u "+%Y%m%dT%H%M%SZ")"
  ops_dir="$project_root/.harness/ops/wake"
  activity_dir="$project_root/.harness/activity"
  mkdir -p "$ops_dir" "$activity_dir"

  # The wake prompt is a static template parameterized only by project/idle/force/
  # review-path. Per the write-on-signal agreement we assemble it in memory rather
  # than persisting a fresh wake-<ts>.prompt.md every tick (those 100+ identical
  # templates were pure noise). tmux mode, which feeds the prompt over stdin, reuses
  # one overwritten scratch file instead of N timestamped ones.
  prompt_scratch="$ops_dir/current.prompt.md"
  log_rel=".harness/ops/wake/wake-${stamp}.log"
  log_path="$project_root/$log_rel"
  pid_file="$ops_dir/wake.pid"

  if [ -f "$pid_file" ]; then
    old_pid="$(cat "$pid_file" 2>/dev/null || true)"
    if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
      say "skip-headless: $project_root (previous wake pid=$old_pid still running)"
      return 0
    fi
  fi

  wake_prompt="$(cat <<EOF
You are harness-ceo waking for the walwal-harness hourly executive loop.

Project root: $project_root
Wake reason: idle=${idle}s force=${force}
Hourly review: ${review_path:-"(not available)"}

Operating (perpetual) goal mode:
- If the active goal's mission-state.json lifecycle is "operating", this is a never-completing standing company. Do NOT run harness-company-complete.sh for it.
- Read the shared agenda .harness/documents/<goal>/agenda.json (scripts/harness-agenda.sh . <goal> list). If it has active items, adjudicate every open item (scripts/harness-agenda.sh . <goal> decide <id> "<decision>" <cxx>) and route the owning CXX to execute+verify, then close it. If the agenda is empty, run a status-briefing round: require each CXX (COO/CDO/CTO/CQO/OPS) to confirm its live deliverables still operate toward the goal and to raise any loss/drift/incident/opportunity/risk via scripts/harness-agenda.sh . <goal> raise <cxx> <kind> "<title>".
- If a full briefing round genuinely surfaces nothing this tick, run scripts/harness-company-cycle.sh . <goal> to record the operating heartbeat and end the tick; the next hourly wake resumes the cycle. A loss/drawdown is an agenda item that triggers the next research→apply→operate cycle, never a reason to stop or to wait on the Owner.

One-line command:
Convene CXX + OPS, collect current progress and decisions, decide the next action as CEO with the active goal in mind, drive all teams without asking Owner, and use CQO verification until the goal demonstrably works.

Policy:
- Owner already provided the GOAL. Owner input after the initial GOAL is an interrupt or additional request, never a reason to wait.
- Do not ask Owner what to do next. Convert uncertainty into CXX/OPS tasks, CQO checks, or a bounded assumption written to artifacts.
- Never set conductor.state to waiting_owner. Normalize any waiting_owner state to waiting_meeting and continue.
- meeting-manager is the synchronization loop, not the stopping point. Incidents, service warnings, goal drift, and escalations go to meeting-manager first, then route execution.
- Keep this to one bounded autonomous tick. Do not run an endless loop.
- Do not write future timestamps to .harness/progress.log or artifacts.
- Keep terminal output concise; write evidence to project files.
- Treat paperwork-only output as insufficient. A meeting that does not create or advance executable next actions is incomplete.

ADHD/autonomy support pattern:
- Act as an external executive-function scaffold: break blocked work into tiny executable next steps, name the first action, and start it.
- Use body-doubling behavior: check the active work state, ask each role for a concise status through artifacts, and keep the loop moving.
- Use context-transition support: summarize what just finished, what starts next, and the handoff artifact path.
- Use time-guardian behavior: identify hidden sub-tasks that make the work longer than expected, set a realistic next checkpoint, and avoid vague "later" states.
- Use open-loop triage: classify discovered work as NOW / NEXT / PARKED. Execute or dispatch NOW items only.

Tasks:
1. Read CONVENTIONS.md if present, .harness/conventions/shared.md, relevant .harness/conventions/<role>.md, .harness/gotchas/<role>.md, .harness/memory.md, .harness/progress.json, and the hourly review above.
2. Determine the active GOAL/submission/hot-fix from progress.json and .harness/documents. Restate it in one sentence for yourself.
3. Convene the executive loop through artifacts: CEO + COO + CDO + CTO + CQO + OPS. Collect only concise status, blocker, decision-needed, and evidence-path information.
4. If service_ops.requested_mode is monitor, run or trigger one service-ops monitor pass and record last_check. stream_active may be true only during the pass and must be false when finished.
5. Treat the hourly review as Executive Meeting Minutes. Verify it contains role positions, discussion, decision JSON, action items, and CQO/OPS evidence requirements.
6. As CEO, decide exactly one NOW action package:
   - owner CXX/role,
   - action_type,
   - deliverable_path,
   - success_condition,
   - verifier, preferably CQO when goal behavior must be proven.
7. Route all teams needed for that NOW action. Do not stop after hiring, planning, status reporting, or meeting note creation.
8. Use CQO to verify whether the goal is actually satisfied. If verification fails or is missing, route implementation/fix work again.
9. If there is an active incident or operational warning, make sure meeting-manager has shared context and an action decision that names CTO/CQO/OPS responsibilities.
10. Split meaningful progress from paperwork-only artifacts in your summary.
11. Append a short factual summary to .harness/progress.log and update normal harness artifacts used by this project.

Required final shape for this tick:
- GOAL:
- CXX/OPS status collected:
- CEO decision:
- NOW action dispatched:
- CQO/OPS verification required:
- NEXT checkpoint:
- Evidence paths:
EOF
)"

  # log_note tracks the on-disk artifact for this tick. record mode and
  # BLOCKED_RUNTIME never spawn an agent, so they leave no (previously empty) log.
  log_note="(none)"
  case "$mode" in
    record)
      status="recorded"
      ;;
    headless|"")
      if agent_bin="$(resolve_agent_bin "$executor")"; then
        (
          cd "$project_root" || exit 1
          if [ "$executor" = "codex" ]; then
            "$agent_bin" exec $auto_approve_flag -C "$project_root" "$wake_prompt" > "$log_path" 2>&1
          else
            if [ -n "$wake_model" ]; then
              "$agent_bin" $auto_approve_flag -p "$wake_prompt" --model "$wake_model" > "$log_path" 2>&1
            else
              "$agent_bin" $auto_approve_flag -p "$wake_prompt" > "$log_path" 2>&1
            fi
          fi
        ) &
        pid=$!
        echo "$pid" > "$pid_file"
        status="spawned executor=$executor pid=$pid"
        log_note="$log_rel"
      else
        status="BLOCKED_RUNTIME ${executor}-not-found"
      fi
      ;;
    tmux)
      if ! command -v tmux >/dev/null 2>&1; then
        status="BLOCKED_RUNTIME tmux-not-found"
      elif agent_bin="$(resolve_agent_bin "$executor")"; then
        printf '%s\n' "$wake_prompt" > "$prompt_scratch"
        session_safe="$(basename "$project_root" | tr -c '[:alnum:]_' '_')"
        session_name="walwal_${session_safe}_${stamp}"
        if [ "$executor" = "codex" ]; then
          tmux new-session -d -s "$session_name" "cd '$project_root' && '$agent_bin' exec $auto_approve_flag -C '$project_root' - < '$prompt_scratch' 2>&1 | tee '$log_path'"
        else
          if [ -n "$wake_model" ]; then
            tmux new-session -d -s "$session_name" "cd '$project_root' && '$agent_bin' $auto_approve_flag -p \"\$(cat '$prompt_scratch')\" --model '$wake_model' 2>&1 | tee '$log_path'"
          else
            tmux new-session -d -s "$session_name" "cd '$project_root' && '$agent_bin' $auto_approve_flag -p \"\$(cat '$prompt_scratch')\" 2>&1 | tee '$log_path'"
          fi
        fi
        status="spawned-tmux executor=$executor session=$session_name"
        log_note="$log_rel"
      else
        status="BLOCKED_RUNTIME ${executor}-not-found"
      fi
      ;;
    *)
      status="recorded unsupported-mode=$mode"
      ;;
  esac

  # Per-tick wake telemetry = one params-only line, not a full prompt copy. This
  # is the "if you must keep something, keep one line in activity.jsonl" path from
  # the wake-template agreement, with rotation so it never grows unbounded.
  if command -v jq >/dev/null 2>&1; then
    jq -nc \
      --arg ts "$(date -u "+%Y-%m-%dT%H:%M:%SZ")" \
      --arg stamp "$stamp" \
      --argjson idle "${idle:-0}" \
      --arg force "$force" \
      --arg mode "$mode" \
      --arg executor "$executor" \
      --arg status "$status" \
      --arg review "${review_path:-}" \
      --arg log "$log_note" \
      '{ts:$ts,stamp:$stamp,idle:$idle,force:$force,mode:$mode,executor:$executor,status:$status,review:$review,log:$log}' \
      >> "$activity_dir/wake.jsonl" 2>/dev/null || true
    if [ -f "$activity_dir/wake.jsonl" ] && tail -n 2000 "$activity_dir/wake.jsonl" > "$activity_dir/wake.jsonl.tmp" 2>/dev/null; then
      mv "$activity_dir/wake.jsonl.tmp" "$activity_dir/wake.jsonl"
    else
      rm -f "$activity_dir/wake.jsonl.tmp" 2>/dev/null || true
    fi
  fi

  # Rotate per-tick agent logs: keep only the most recent 48 (~2 days hourly).
  ls -1t "$ops_dir"/wake-*.log 2>/dev/null | tail -n +49 | while IFS= read -r old_log; do
    rm -f "$old_log"
  done

  echo "$(date -u "+%Y-%m-%dT%H:%M:%SZ") | wake | agent-tick | $status | idle=${idle}s | force=${force} | mode=${mode} | log=$log_note" >> "$project_root/.harness/progress.log"
  say "wake-agent: $project_root (idle ${idle}s, force=${force}, mode=${mode}, executor=${executor}) → $status $log_note"

  run_conductor_fallback "$project_root" "$status"

  if tmux_session="$(find_tmux_session "$project_root" 2>/dev/null)"; then
    tmux display-message -t "$tmux_session" "walwal wake headless tick: $status ($log_note)" 2>/dev/null || true
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
