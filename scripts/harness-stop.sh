#!/bin/bash
# harness-stop.sh — Stop hook (v6.2)
#
# Claude 가 한 turn 을 끝내려 할 때 발화.
# conductor.state == "running" 이고 다음 작업이 남아 있으면
# stdout 으로 {"decision":"block", "reason":"..."} JSON 을 출력해
# Claude 가 멈추지 않고 다음 tick 으로 자동 연쇄하게 한다.
#
# 멈춰야 할 경우 (회사 루프 정지·task_stop 등) 는 그냥 exit 0
# → Claude 가 정상적으로 turn 을 종료.

set -uo pipefail

INPUT=$(cat 2>/dev/null || echo "{}")
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)
[ -z "$CWD" ] && CWD="$PWD"

# 하네스 초기화 안 된 곳: no-op
[ -f "$CWD/.harness/progress.json" ] || exit 0
[ -f "$CWD/.harness/config.json" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

PROGRESS="$CWD/.harness/progress.json"
CONFIG="$CWD/.harness/config.json"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Opt-out
# `.x // true` would collapse an explicit `false` back to `true` (jq treats
# false as empty), which silently disabled this documented opt-out.
AUTO_CHAIN=$(jq -r 'if .behavior.auto_chain_on_stop == null then true else .behavior.auto_chain_on_stop end' "$CONFIG" 2>/dev/null || echo "true")
if [ "$AUTO_CHAIN" != "true" ]; then exit 0; fi

# 무한루프 방지: 한 sprint 안에서 stop_chain_count 가 상한을 넘으면 중단
STOP_CHAIN_MAX=$(jq -r '.behavior.auto_chain_max_per_sprint // 200' "$CONFIG" 2>/dev/null || echo 200)
STOP_CHAIN_COUNT=$(jq -r '.conductor.stop_chain_count // 0' "$PROGRESS" 2>/dev/null || echo 0)
if [ "${STOP_CHAIN_COUNT:-0}" -ge "${STOP_CHAIN_MAX:-200}" ]; then exit 0; fi

# 회사 루프 상태 확인
CONDUCTOR_STATE=$(jq -r '.conductor.state // "idle"' "$PROGRESS" 2>/dev/null || echo "idle")
COMPANY_STATE=$(jq -r '.company_state.state // "idle"' "$PROGRESS" 2>/dev/null || echo "idle")
CURRENT_AGENT=$(jq -r '.current_agent // "none"' "$PROGRESS" 2>/dev/null || echo "none")
NEXT_AGENT=$(jq -r '.next_agent // "none"' "$PROGRESS" 2>/dev/null || echo "none")
AGENT_STATUS=$(jq -r '.agent_status // "pending"' "$PROGRESS" 2>/dev/null || echo "pending")
OWNER_PROMPT_STATUS=$(jq -r '.owner_prompt.status // "none"' "$PROGRESS" 2>/dev/null || echo "none")
TASK_STOP_ACTIVE=$(jq -r '.task_stop.active // false' "$PROGRESS" 2>/dev/null || echo "false")
ESCALATION=$(jq -r '.conductor.escalation // "null"' "$PROGRESS" 2>/dev/null || echo "null")
SPRINT_STATUS=$(jq -r '.sprint.status // "init"' "$PROGRESS" 2>/dev/null || echo "init")

# stop hook 이 자기 자신에 의해 재진입되지 않도록 hook event 필터링
HOOK_EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // empty' 2>/dev/null || true)
if [ "$HOOK_EVENT" = "Stop" ]; then
  STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null || echo "false")
  if [ "$STOP_HOOK_ACTIVE" = "true" ]; then exit 0; fi
fi

# ── v7 깨끗한 정지 short-circuit ──────────────────────────────
# 회사 루프의 정당한 정지 조건은 둘뿐이다: COMPLETE, 그리고 외부권한 BLOCKED.
# harness-company-complete.sh / harness-company-block.sh 가 이 terminal 런타임
# 상태를 기록한다. 그 상태를 여기서 존중해, 끝났는데도 "계속하라"고 채근하지 않고
# 턴을 깨끗이 종료한다. (/goal 직후 routing/running 상태에서는 발동하지 않는다.)
case "$CONDUCTOR_STATE" in
  completed|idle|blocked) exit 0 ;;
esac
if [ "$AGENT_STATUS" = "blocked" ] || [ "$OWNER_PROMPT_STATUS" = "completed" ] || [ "$OWNER_PROMPT_STATUS" = "awaiting-authority" ]; then
  exit 0
fi

# ── v7 영구 운영(operating) + 완료 backstop ──────────────────
# .harness/documents 의 mission-state 를 스캔해 루프 종류를 분류한다:
#   - operating mission 이 active  → 영구 모드: 안건을 강제 구동하거나 wake 로 양보
#   - 모든 mission 이 terminal      → 유한 루프 종료: 완료 처리 + 깨끗한 정지
# (mission 문서가 없으면 순수 v6 프로젝트 → 미발동)
DOCS_DIR="$CWD/.harness/documents"
if [ "$TASK_STOP_ACTIVE" != "true" ] && [ -d "$DOCS_DIR" ] && \
   { [ "$CONDUCTOR_STATE" = "running" ] || [ "$CONDUCTOR_STATE" = "operating" ]; }; then
  any_mission="false"; active_mission="false"; operating_active="false"; operating_rel=""
  while IFS= read -r state; do
    [ -n "$state" ] || continue
    any_mission="true"
    a=$(jq -r '.active // false' "$state" 2>/dev/null || echo false)
    lc=$(jq -r '.lifecycle // .status // "unknown"' "$state" 2>/dev/null || echo unknown)
    case "$lc" in
      closed|cancelled|superseded|complete|completed|blocked) ;;
      operating|monitoring)
        if [ "$a" = "true" ]; then
          active_mission="true"; operating_active="true"
          rel="${state#"$DOCS_DIR"/}"; operating_rel="${rel%/mission-state.json}"
        fi ;;
      *) [ "$a" = "true" ] && active_mission="true" ;;
    esac
  done < <(find "$DOCS_DIR" -name mission-state.json -type f 2>/dev/null)

  if [ "$operating_active" = "true" ]; then
    active_agenda=0
    if [ -x "$SCRIPT_DIR/harness-agenda.sh" ]; then
      active_agenda=$(bash "$SCRIPT_DIR/harness-agenda.sh" "$CWD" "$operating_rel" active-count 2>/dev/null || echo 0)
    fi
    # operating tick 도 활동 샘플 1회 + stop_chain_count 증가
    NEW_COUNT=$((STOP_CHAIN_COUNT + 1))
    jq --argjson n "$NEW_COUNT" '.conductor.stop_chain_count=$n | .conductor.last_stop_chain_at=(now|todate)' "$PROGRESS" > "$PROGRESS.tmp.$$" 2>/dev/null && mv "$PROGRESS.tmp.$$" "$PROGRESS" || rm -f "$PROGRESS.tmp.$$"
    if command -v node >/dev/null 2>&1 && [ -f "$SCRIPT_DIR/harness-activity-record.js" ]; then node "$SCRIPT_DIR/harness-activity-record.js" "$CWD" >/dev/null 2>&1 || true; fi
    if [ "${active_agenda:-0}" -gt 0 ] 2>/dev/null; then
      bash "$SCRIPT_DIR/harness-progress-set.sh" "$CWD" '.conductor.state="running"' >/dev/null 2>&1 || true
      jq -nc --arg n "$active_agenda" --arg g "$operating_rel" '{decision:"block", reason:("영구 운영 루프: 활성 안건 \($n)건. CEO는 .harness/documents/\($g)/agenda.json 의 모든 open 안건을 `scripts/harness-agenda.sh . \($g) decide` 로 판단·라우팅하고, decided 안건은 담당 CXX가 hired worker로 실행·검증한 뒤 `... close` 할 때까지 진행하라. 안건이 남았는데 턴을 끝내지 말 것.")}'
      exit 0
    elif [ "$CONDUCTOR_STATE" = "operating" ]; then
      exit 0   # 안건 0 + heartbeat 기록됨 → 다음 hourly wake 로 양보(깨끗한 정지)
    else
      jq -nc --arg g "$operating_rel" '{decision:"block", reason:("영구 운영 루프: 안건 없음. CEO는 각 CXX(COO/CDO/CTO/CQO/OPS)에게 현황 보고를 지시하라 — 각 CXX는 자기 산하 worker 산출물이 goal 기준으로 여전히 올바르게 동작하는지 브리핑하고, 손실·드리프트·기회·리스크가 보이면 `scripts/harness-agenda.sh . \($g) raise <cxx> <kind> \"<title>\"` 로 새 안건을 등록한다. 한 바퀴 브리핑이 정말 무안건이면 `scripts/harness-company-cycle.sh . \($g)` 로 operating heartbeat 를 남기고 다음 hourly wake 로 양보하라.")}'
      exit 0
    fi
  fi

  if [ "$any_mission" = "true" ] && [ "$active_mission" = "false" ] && [ "$CONDUCTOR_STATE" = "running" ]; then
    # Never silently complete: record why the backstop fired so an operator can
    # audit a misclassification, and only treat the loop as finished if the
    # transition actually applied (otherwise fall through and keep chaining).
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | stop-hook | auto-complete | backstop fired (conductor=running but no active mission under .harness/documents)" >> "$CWD/.harness/progress.log" 2>/dev/null || true
    if bash "$SCRIPT_DIR/harness-company-complete.sh" "$CWD" "loop-idle-no-active-mission" >/dev/null 2>&1; then
      exit 0
    fi
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | stop-hook | auto-complete | WARN: harness-company-complete.sh failed during backstop; continuing loop" >> "$CWD/.harness/progress.log" 2>/dev/null || true
  fi
fi

# 자동 연쇄 조건:
#   conductor/company loop 가 running
#   AND task_stop 비활성
#   AND (next_agent 가 명시되어 있거나, agent_status=completed 라서 다음 tick 결정 필요)
# v7 CEO 루프는 conductor-tick 없이 CEO/CXX 상태로 시작될 수 있다.
# current_agent=ceo running + owner_prompt.routing 은 기존 설치본이 conductor/company
# state를 아직 쓰지 않은 stuck 상태에서도 turn 종료 차단 대상으로 본다.
should_chain="false"
if { [ "$CONDUCTOR_STATE" = "running" ] || [ "$COMPANY_STATE" = "running" ]; } \
  && [ "$TASK_STOP_ACTIVE" != "true" ]; then
  if [ "$NEXT_AGENT" != "none" ] && [ "$NEXT_AGENT" != "null" ]; then
    should_chain="true"
  elif [ "$AGENT_STATUS" = "completed" ]; then
    should_chain="true"
  elif [ "$CURRENT_AGENT" = "ceo" ] && [ "$AGENT_STATUS" = "running" ] && [ "$OWNER_PROMPT_STATUS" = "routing" ]; then
    should_chain="true"
  fi
fi
if [ "$should_chain" != "true" ] \
  && [ "$TASK_STOP_ACTIVE" != "true" ] \
  && [ "$CURRENT_AGENT" = "ceo" ] \
  && [ "$AGENT_STATUS" = "running" ] \
  && [ "$OWNER_PROMPT_STATUS" = "routing" ]; then
  should_chain="true"
fi

if [ "$should_chain" != "true" ]; then exit 0; fi

# CXX direct-execution guard:
# Only run this while an active company loop is actually chaining. Scope it to
# the newest active mission so legacy/archive documents cannot keep Stop
# blocked forever.
if [ -x "$SCRIPT_DIR/harness-worker-evidence-validate.sh" ]; then
  WORKER_EVIDENCE_JSON=$("$SCRIPT_DIR/harness-worker-evidence-validate.sh" "$CWD" json latest-active 2>/dev/null || true)
  WORKER_EVIDENCE_OK=$(echo "$WORKER_EVIDENCE_JSON" | jq -r 'if has("ok") then .ok else true end' 2>/dev/null || echo true)
  if [ "$WORKER_EVIDENCE_OK" != "true" ]; then
    REASON=$(echo "$WORKER_EVIDENCE_JSON" | jq -r '
      "CXX 직접 실행 차단: " +
      ([.violations[] | "\(.mission) has CXX docs without worker reports: \(.docs | join(","))"] | join("; ")) +
      ". harness-hiring/resource-manager로 전문 worker를 고용 또는 배정하고 .harness/documents/{goal-or-child-mission}/{owning-cxx}/workers/{worker-name}.md 를 남긴 뒤 계속하라."
    ' 2>/dev/null || echo "CXX 직접 실행 차단: worker report가 없는 active mission이 있습니다. hired worker 보고서를 먼저 생성하세요.")
    jq -nc --arg reason "$REASON" '{decision:"block", reason:$reason}'
    exit 0
  fi
fi

# Lessons-before-plan gate (AGENTS.md Hard Rule 20):
# 코퍼스를 읽고 계획을 세운 흔적이 role 문서에 없으면 턴을 끝내지 못하게 막는다.
# 산문으로만 존재하는 규칙은 편할 때만 지켜진다 — 이미 동작하는 정지 메커니즘에
# 검사를 붙인다. 활성 미션 1개로 스코프를 좁혀 legacy/archive 문서가 영구히
# Stop 을 막지 않게 한다. .harness/config.json 의 behavior.lessons_gate=false 로
# 아직 채택하지 않은 프로젝트는 opt-out 할 수 있다.
if [ -x "$SCRIPT_DIR/harness-lessons-gate.sh" ]; then
  LESSONS_JSON=$("$SCRIPT_DIR/harness-lessons-gate.sh" "$CWD" json latest-active 2>/dev/null || true)
  LESSONS_OK=$(echo "$LESSONS_JSON" | jq -r 'if has("ok") then .ok else true end' 2>/dev/null || echo true)
  if [ "$LESSONS_OK" != "true" ]; then
    REASON=$(echo "$LESSONS_JSON" | jq -r '
      "교훈 선행 게이트(Hard Rule 20): " +
      ([.violations[] | "\(.mission) → \(.docs | join(","))"] | join("; ")) +
      ". 각 role 문서에 `## Lessons Preflight`(이 미션에 적용되는 conventions/gotchas 항목과 이유)와 " +
      "그 아래 `## Implementation Notes` 바로 앞에 한 줄짜리 `## Lessons Tally`(실제로 발동한 항목; `0 fired` 도 유효하며 생략은 불가)를 " +
      "추가한 뒤 계속하라. 코퍼스를 다시 요약한 별도 체크리스트 파일을 만들지 말 것 — 읽는 순서를 고치는 규칙이다."
    ' 2>/dev/null || echo "교훈 선행 게이트(Hard Rule 20): active mission 의 role 문서에 ## Lessons Preflight / ## Lessons Tally 가 없습니다. 먼저 추가하세요.")
    jq -nc --arg reason "$REASON" '{decision:"block", reason:$reason}'
    exit 0
  fi
fi

# stop_chain_count 증가 (느슨한 카운터 — race 허용)
NEW_COUNT=$((STOP_CHAIN_COUNT + 1))
TMP=$(mktemp)
jq --argjson n "$NEW_COUNT" '.conductor.stop_chain_count = $n |
  .conductor.last_stop_chain_at = (now | todate)' "$PROGRESS" > "$TMP" 2>/dev/null \
  && mv "$TMP" "$PROGRESS" || rm -f "$TMP"

# 자율 tick 마다 활동 샘플 1회 기록 → 대시보드 히트맵이 라이브 운영 중에도 채워진다.
# (recorder 의 runtimeIdle 게이트가 완료 후에는 count>0 샘플을 알아서 억제한다.)
if command -v node >/dev/null 2>&1 && [ -f "$SCRIPT_DIR/harness-activity-record.js" ]; then
  node "$SCRIPT_DIR/harness-activity-record.js" "$CWD" >/dev/null 2>&1 || true
fi

# Claude 에게 다음 행동 지시
if [ "$ESCALATION" != "null" ]; then
  REASON="자율 회사 루프 진행 중. escalation=${ESCALATION} 는 정지 사유가 아니라 meeting-manager/service-ops 공유 대상이다. current_agent=${CURRENT_AGENT}, next_agent=${NEXT_AGENT}, agent_status=${AGENT_STATUS}, conductor=${CONDUCTOR_STATE}, company=${COMPANY_STATE}. SKILL 에 따라 CEO/CXX/worker 흐름을 계속하거나 conductor-tick 을 굴려 meeting-manager 회의로 라우팅하라. progress.log 에는 절대 미래 시각을 쓰지 말 것. 진짜로 끝났을 때만 turn 을 종료하라."
else
  REASON="자율 회사 루프 진행 중. current_agent=${CURRENT_AGENT}, next_agent=${NEXT_AGENT}, agent_status=${AGENT_STATUS}, conductor=${CONDUCTOR_STATE}, company=${COMPANY_STATE}. SKILL 에 따라 CEO/CXX/worker 흐름을 계속하고, 필요한 CXX/worker fresh session 을 실행하라. progress.log 에는 절대 미래 시각을 쓰지 말 것. 진짜로 끝났을 때만 turn 을 종료하라."
fi

jq -nc \
  --arg reason "$REASON" \
  '{decision: "block", reason: $reason}'

exit 0
