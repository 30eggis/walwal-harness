#!/bin/bash
# harness-next.sh — 세션 오케스트레이터
# 현재 progress.json 상태를 읽고 다음 에이전트를 결정한다.
# Feature-level 프로그래스를 출력하고 handoff.json을 생성한다.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/harness-render-progress.sh"
source "$SCRIPT_DIR/lib/harness-guardrail.sh"
source "$SCRIPT_DIR/lib/harness-audit.sh"

# ─────────────────────────────────────────
# Resolve project root
# ─────────────────────────────────────────
PROJECT_ROOT="$(resolve_harness_root "${1:-.}")" || {
  echo "[harness] ERROR: .harness/ directory not found" >&2
  echo "  Run 'npx walwal-harness' to initialize." >&2
  exit 1
}

PROGRESS="$PROJECT_ROOT/.harness/progress.json"
CONFIG="$PROJECT_ROOT/.harness/config.json"
PIPELINE_JSON="$PROJECT_ROOT/.harness/actions/pipeline.json"
HANDOFF="$PROJECT_ROOT/.harness/handoff.json"

check_jq || exit 1

# Initialize audit log
init_audit "$PROJECT_ROOT"

if [ ! -f "$PROGRESS" ]; then
  echo "[harness] ERROR: progress.json not found" >&2
  echo "  Run 'npx walwal-harness --force' to reinitialize." >&2
  exit 1
fi

# ─────────────────────────────────────────
# Read current state
# ─────────────────────────────────────────
pipeline=$(jq -r '.pipeline // "null"' "$PROGRESS")
sprint_num=$(jq -r '.sprint.number // 0' "$PROGRESS")
sprint_status=$(jq -r '.sprint.status // "init"' "$PROGRESS")
current_agent=$(jq -r '.current_agent // "null"' "$PROGRESS")
agent_status=$(jq -r '.agent_status // "pending"' "$PROGRESS")
next_agent=$(jq -r '.next_agent // "null"' "$PROGRESS")
retry_count=$(jq -r '.sprint.retry_count // 0' "$PROGRESS")
max_retries=$(jq -r '.flow.max_retries_per_sprint // 10' "$CONFIG" 2>/dev/null || echo 10)

# fe_stack + fe_target 치환 (Flutter Web/Mobile/Desktop 지원) — pipeline.json 에서 읽음
fe_stack="react"
fe_target="web"
if [ -f "$PIPELINE_JSON" ]; then
  fe_stack=$(jq -r '.fe_stack // "react"' "$PIPELINE_JSON" 2>/dev/null || echo "react")
  fe_target=$(jq -r '.fe_target // empty' "$PIPELINE_JSON" 2>/dev/null || true)
  if [ -z "$fe_target" ]; then
    # pipeline.json 에 fe_target 미지정 시 config.json 의 _default_target 사용
    fe_target=$(jq -r ".flow.pipeline_selection.fe_stack_substitution.${fe_stack}._default_target // \"web\"" "$CONFIG" 2>/dev/null || echo "web")
  fi
fi

# ─────────────────────────────────────────
# fe_stack 치환 (no-op — Flutter 지원 제거됨, 하위 호환용 stub)
# ─────────────────────────────────────────
substitute_fe_stack() {
  echo "$1"
}

# ─────────────────────────────────────────
# Pre-Eval Gate — deterministic checks before Evaluator
#   Generator가 완료되고 다음이 Evaluator일 때, lint/type/test를 먼저 실행.
#   실패 시 Evaluator를 건너뛰고 Generator로 리라우팅.
# ─────────────────────────────────────────
run_pre_eval_gate() {
  local next="$1"
  local gate_enabled
  gate_enabled=$(jq -r '.flow.pre_eval_gate.enabled // false' "$CONFIG" 2>/dev/null)
  if [ "$gate_enabled" != "true" ]; then return 0; fi

  # Evaluator 에이전트인지 확인
  case "$next" in
    evaluator-*) ;;
    *) return 0 ;;
  esac

  local timeout
  timeout=$(jq -r '.flow.pre_eval_gate.timeout_seconds // 120' "$CONFIG" 2>/dev/null)

  # 실패 위치 결정 (backend or frontend)
  # current_agent가 실패로 변경된 경우, completed_agents에서 직전 Generator를 찾는다
  local location="backend"
  local checks_key="backend_checks"
  local source_agent="$current_agent"

  # current_agent가 generator가 아닌 경우 (예: dispatcher로 리라우팅된 상태),
  # completed_agents에서 마지막 generator를 찾는다
  case "$source_agent" in
    generator-frontend)
      location="frontend"
      checks_key="frontend_checks"
      ;;
    generator-backend)
      location="backend"
      checks_key="backend_checks"
      ;;
    *)
      # completed_agents에서 마지막 generator를 역순으로 찾기
      local last_gen
      last_gen=$(jq -r '.completed_agents // [] | map(select(startswith("generator-"))) | last // empty' "$PROGRESS" 2>/dev/null)
      case "$last_gen" in
        generator-frontend)
          location="frontend"
          checks_key="frontend_checks"
          ;;
        generator-backend)
          location="backend"
          checks_key="backend_checks"
          ;;
      esac
      ;;
  esac

  local -a checks
  mapfile -t checks < <(jq -r ".flow.pre_eval_gate.${checks_key}[]" "$CONFIG" 2>/dev/null)

  if [ ${#checks[@]} -eq 0 ]; then return 0; fi

  # Resolve cwd for checks: config.pre_eval_gate.frontend_cwd / backend_cwd
  local cwd_key="${location}_cwd"
  local check_cwd
  check_cwd=$(jq -r ".flow.pre_eval_gate.${cwd_key} // empty" "$CONFIG" 2>/dev/null)
  if [ -n "$check_cwd" ] && [ "$check_cwd" != "null" ]; then
    # Relative path from PROJECT_ROOT
    check_cwd="$PROJECT_ROOT/$check_cwd"
  else
    check_cwd="$PROJECT_ROOT"
  fi

  echo ""
  echo "  ── Pre-Eval Gate ──────────────────────"
  if [ "$check_cwd" != "$PROJECT_ROOT" ]; then
    echo "  cwd: ${check_cwd#$PROJECT_ROOT/}"
  fi
  local all_pass=true
  local fail_log=""

  for cmd in "${checks[@]}"; do
    printf "  %-40s " "$cmd"
    local output
    if output=$(cd "$check_cwd" && timeout "${timeout}s" bash -c "$cmd" 2>&1); then
      echo "✓"
    else
      echo "✗"
      all_pass=false
      fail_log+="[FAIL] $cmd"$'\n'"$output"$'\n\n'
    fi
  done

  if [ "$all_pass" = true ]; then
    echo "  Gate: PASS — proceeding to $next"
    echo ""
    return 0
  else
    echo ""
    echo "  Gate: FAIL — rerouting to $current_agent"
    echo ""

    # progress.json 업데이트: 실패 기록 + Generator로 리라우팅
    local new_retry=$((retry_count + 1))
    local fail_summary
    fail_summary=$(echo "$fail_log" | head -20)

    jq --arg agent "$current_agent" \
       --arg loc "$location" \
       --arg msg "Pre-eval gate failed: $fail_summary" \
       --arg target "$current_agent" \
       --argjson retry "$new_retry" \
       '.sprint.status = "failed" |
        .sprint.retry_count = $retry |
        .agent_status = "failed" |
        .next_agent = $target |
        .failure.agent = $agent |
        .failure.location = $loc |
        .failure.message = $msg |
        .failure.retry_target = $target' "$PROGRESS" > "${PROGRESS}.tmp" && mv "${PROGRESS}.tmp" "$PROGRESS"

    # next_agent를 Generator로 덮어쓰기
    next_agent="$current_agent"
    return 1
  fi
}

# ─────────────────────────────────────────
# Determine next agent
# ─────────────────────────────────────────
compute_next_agent() {
  local current="$1"
  local status="$2"

  # If blocked, no next
  if [ "$status" = "blocked" ]; then
    echo "null"
    return
  fi

  # If failure with retry target, use that
  local retry_target
  retry_target=$(jq -r '.failure.retry_target // "null"' "$PROGRESS")
  if [ "$retry_target" != "null" ] && [ "$status" = "failed" ]; then
    echo "$retry_target"
    return
  fi

  # If next_agent is already set in progress.json, use it
  if [ "$next_agent" != "null" ]; then
    echo "$next_agent"
    return
  fi

  # Compute from pipeline sequence
  if [ "$pipeline" = "null" ] || [ ! -f "$CONFIG" ]; then
    echo "dispatcher"
    return
  fi

  local -a raw_agents
  mapfile -t raw_agents < <(jq -r ".flow.pipeline_selection.pipelines[\"${pipeline}\"][]" "$CONFIG" 2>/dev/null | sed 's/:.*//')

  # fe_stack 치환 + __skip__ 필터링
  local -a agents
  for a in "${raw_agents[@]}"; do
    local sub
    sub=$(substitute_fe_stack "$a")
    if [ "$sub" != "__skip__" ]; then
      agents+=("$sub")
    fi
  done

  local found=false
  for agent in "${agents[@]}"; do
    if [ "$found" = true ]; then
      echo "$agent"
      return
    fi
    # current 비교 시에도 치환된 이름으로 (Flutter 변형 에이전트가 실행되는 경우)
    if [ "$agent" = "$current" ]; then
      found=true
    fi
  done

  # Current is last agent → sprint complete
  echo "archive"
}

# If current agent completed, compute next
if [ "$agent_status" = "completed" ] && [ "$next_agent" = "null" ]; then
  next_agent=$(compute_next_agent "$current_agent" "$agent_status")
fi

# ─────────────────────────────────────────
# Artifact Prerequisites — 선행 아티팩트 상태 검증
# ─────────────────────────────────────────
verify_artifact_prerequisites() {
  local target_agent="$1"
  local states_order='["pending","draft","reviewed","approved"]'

  # 에이전트의 prerequisites 가져오기
  local prereqs
  prereqs=$(jq -r ".artifacts.prerequisites[\"${target_agent}\"] // empty" "$CONFIG" 2>/dev/null)
  if [ -z "$prereqs" ] || [ "$prereqs" = "null" ]; then return 0; fi

  local all_met=true
  echo ""
  echo "  ── Artifact Prerequisites ─────────────"

  # prereqs의 각 키(artifact명)를 순회
  while IFS='=' read -r artifact required_status; do
    artifact=$(echo "$artifact" | tr -d '"' | tr -d ' ')
    required_status=$(echo "$required_status" | tr -d '"' | tr -d ' ')
    if [ -z "$artifact" ]; then continue; fi

    local current_status
    current_status=$(jq -r ".artifacts[\"${artifact}\"].status // \"pending\"" "$PROGRESS" 2>/dev/null)

    # 상태 순서 비교
    local required_idx current_idx
    required_idx=$(echo "$states_order" | jq "index(\"$required_status\") // 0")
    current_idx=$(echo "$states_order" | jq "index(\"$current_status\") // 0")

    if [ "$current_idx" -ge "$required_idx" ]; then
      printf "  ✓ %-25s %s (required: %s)\n" "$artifact" "$current_status" "$required_status"
    else
      printf "  ✗ %-25s %s (required: %s)\n" "$artifact" "$current_status" "$required_status"
      all_met=false
    fi
  done < <(jq -r ".artifacts.prerequisites[\"${target_agent}\"] | to_entries[] | \"\(.key)=\(.value)\"" "$CONFIG" 2>/dev/null)

  echo ""

  if [ "$all_met" = true ]; then
    echo "  Prerequisites: PASS"
  else
    echo "  Prerequisites: FAIL — preceding agent must complete artifacts first"
  fi
  echo ""

  [ "$all_met" = true ] && return 0 || return 1
}

# ─────────────────────────────────────────
# Runtime Guardrail — 파일 소유권 검증
# ─────────────────────────────────────────
if [ "$agent_status" = "completed" ]; then
  audit_log "$current_agent" "develop" "complete" "" "agent completed"
  verify_file_ownership "$PROJECT_ROOT" || audit_gate "file-ownership" "warn" "boundary violation detected"
fi

# ─────────────────────────────────────────
# Run Pre-Eval Gate (if applicable)
# ─────────────────────────────────────────
if [ "$agent_status" = "completed" ]; then
  audit_gate "pre-eval" "start" "$next_agent"
  if run_pre_eval_gate "$next_agent"; then
    audit_gate "pre-eval" "pass" "$next_agent"
  else
    audit_gate "pre-eval" "fail" "rerouted to $current_agent"
  fi
  if verify_artifact_prerequisites "$next_agent"; then
    audit_gate "artifact-prereq" "pass" "$next_agent"
  else
    audit_gate "artifact-prereq" "fail" "$next_agent"
  fi
fi

# ─────────────────────────────────────────
# Render progress
# ─────────────────────────────────────────
render_progress "$PROJECT_ROOT"
render_agent_bar "$PROJECT_ROOT"
echo ""

# ─────────────────────────────────────────
# Generate handoff.json (unified session transition document)
# ─────────────────────────────────────────
if [ "$next_agent" != "null" ] && [ "$next_agent" != "archive" ] && [ "$agent_status" != "blocked" ]; then
  # ── Escalation check: 3회 실패 시 Planner에게 scope 축소 요청 ──
  escalate_after=$(jq -r '.flow.escalate_to_planner_after // 3' "$CONFIG" 2>/dev/null || echo 3)
  if [ "$retry_count" -ge "$escalate_after" ] && [ "$sprint_status" = "failed" ] && [ "$next_agent" != "planner" ]; then
    echo "  ⚠ Escalation: ${retry_count}회 실패 — Planner에게 scope 축소/접근 변경 요청"
    audit_log "system" "escalate" "start" "→planner" "retry ${retry_count}회 초과"
    next_agent="planner"
    jq --arg msg "Escalated after ${retry_count} failures. Planner must review scope or approach." \
       '.next_agent = "planner" |
        .failure.message = $msg |
        .failure.retry_target = "planner"' "$PROGRESS" > "${PROGRESS}.tmp" && mv "${PROGRESS}.tmp" "$PROGRESS"
  fi

  # ── Read model & thinking mode for next agent ──
  agent_model=$(jq -r ".agents[\"${next_agent}\"].model // \"opus\"" "$CONFIG" 2>/dev/null || echo "opus")
  agent_thinking=$(jq -r ".agents[\"${next_agent}\"].thinking_mode // \"null\"" "$CONFIG" 2>/dev/null || echo "null")

  # ── Build prompt text (embedded in handoff.json) ──
  prompt="/harness-${next_agent} 를 실행하세요."

  if [ "$sprint_num" -gt 0 ]; then
    prompt+=$'\n'"Sprint ${sprint_num}"
    if [ "$sprint_status" = "failed" ]; then
      prompt+=" (retry ${retry_count}/${max_retries})"
    fi
    prompt+="을 진행합니다."
  fi

  prompt+=$'\n'".harness/handoff.json을 읽고 컨텍스트를 확인하세요."

  # Inject thinking mode instruction
  if [ "$agent_thinking" != "null" ]; then
    case "$agent_thinking" in
      ultraplan)
        prompt+=$'\n\n'"[Thinking Mode: ultraplan] /${agent_thinking} 모드를 사용하세요. 깊은 사고로 아키텍처와 설계를 수행합니다."
        ;;
      ultrathink)
        prompt+=$'\n\n'"[Thinking Mode: ultrathink] /${agent_thinking} 모드를 사용하세요. 최대 추론 깊이로 비판적 검증을 수행합니다."
        ;;
      plan)
        prompt+=$'\n\n'"[Thinking Mode: plan] /${agent_thinking} 모드를 사용하세요. 구조화된 계획을 수립한 후 실행합니다."
        ;;
    esac
  fi

  # Add failure context if retrying
  failure_msg=$(jq -r '.failure.message // empty' "$PROGRESS")
  if [ -n "$failure_msg" ] && [ "$failure_msg" != "null" ]; then
    prompt+=$'\n\n'"이전 실패 사유: ${failure_msg}"
    prompt+=$'\n'"같은 접근을 반복하지 말고, 실패 원인을 분석한 후 다른 전략으로 시도하세요."
  fi

  # ── Collect artifacts ──
  FEATURE_LIST="$PROJECT_ROOT/.harness/actions/feature-list.json"

  local -a artifacts_ready=()
  for f in plan.md feature-list.json api-contract.json sprint-contract.md evaluation-functional.md evaluation-visual.md; do
    if [ -f "$PROJECT_ROOT/.harness/actions/$f" ]; then
      artifacts_ready+=("$f")
    fi
  done
  local artifacts_json
  artifacts_json=$(printf '%s\n' "${artifacts_ready[@]}" | jq -R . | jq -s .)

  # Collect focus features (incomplete ones)
  local focus_features="[]"
  if [ -f "$FEATURE_LIST" ]; then
    focus_features=$(jq '[.features[]? | select(.passes == null or (.passes | length) == 0 or ((.passes // []) | map(select(. == "evaluator-functional")) | length == 0)) | .id] | .[0:5]' "$FEATURE_LIST" 2>/dev/null || echo "[]")
  fi

  # ── Regression data ──
  local regression_source="null"
  local prev_sprint=$((sprint_num - 1))
  local prev_archive="$PROJECT_ROOT/.harness/archive/sprint-$(printf '%03d' $prev_sprint)"
  if [ "$prev_sprint" -ge 1 ] && [ -d "$prev_archive" ]; then
    if [ -f "$prev_archive/feature-list.json" ]; then
      regression_source=$(jq '{
        sprint: '"$prev_sprint"',
        passed_features: [.features[]? | select((.passes // []) | map(select(. == "evaluator-functional")) | length > 0) | {id, name, acceptance_criteria}],
        archive_path: "'"$prev_archive"'"
      }' "$prev_archive/feature-list.json" 2>/dev/null || echo "null")
    fi
  fi

  # ── Eval-specific config ──
  local eval_config="null"
  local cross_validation_data="null"
  case "$next_agent" in
    evaluator-*)
      eval_config=$(jq '{
        pass_threshold: .evaluation.scoring.pass_threshold,
        scale: .evaluation.scoring.scale,
        verdict_rules: .evaluation.scoring.verdict_rules,
        regression_enabled: .evaluation.regression.enabled,
        cross_validation_enabled: .evaluation.cross_validation.enabled,
        adversarial_rules: .agents["'"$next_agent"'"].adversarial_rules.rules,
        forbidden: .agents["'"$next_agent"'"].adversarial_rules.forbidden
      }' "$CONFIG" 2>/dev/null || echo "null")
      ;;
  esac

  # ── Cross-Validation ──
  if [ "$next_agent" = "evaluator-visual" ]; then
    local func_eval="$PROJECT_ROOT/.harness/actions/evaluation-functional.md"
    if [ -f "$func_eval" ]; then
      cross_validation_data=$(sed -n '/```json/,/```/p' "$func_eval" | tail -n +2 | head -n -1 | jq 'select(.evaluator == "functional")' 2>/dev/null || echo "null")
    fi
  fi

  # ── Build handoff.json (single source of truth for session transition) ──
  jq -n \
    --arg from "${current_agent:-dispatcher}" \
    --arg to "$next_agent" \
    --arg prompt "$prompt" \
    --argjson sprint "$sprint_num" \
    --argjson retry "$retry_count" \
    --arg status "$sprint_status" \
    --arg agent_model "$agent_model" \
    --arg agent_thinking "$agent_thinking" \
    --arg failure_msg "${failure_msg:-}" \
    --argjson artifacts "$artifacts_json" \
    --argjson focus "$focus_features" \
    --argjson regression "$regression_source" \
    --argjson eval_config "$eval_config" \
    --argjson cross_val "$cross_validation_data" \
    --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{
      from: $from,
      to: $to,
      prompt: $prompt,
      sprint: $sprint,
      retry_count: $retry,
      sprint_status: $status,
      model: $agent_model,
      thinking_mode: (if $agent_thinking == "null" then null else $agent_thinking end),
      failure_context: (if $failure_msg != "" then $failure_msg else null end),
      artifacts_ready: $artifacts,
      focus_features: $focus,
      regression: $regression,
      eval_config: $eval_config,
      cross_validation_from_functional: $cross_val,
      warnings: [],
      timestamp: $timestamp
    }' > "$HANDOFF"

  audit_handoff "${current_agent:-dispatcher}" "$next_agent" "complete"

elif [ "$next_agent" = "archive" ]; then
  audit_log "system" "archive" "start" "sprint-${sprint_num}" "sprint cycle complete"
  jq -n \
    --arg from "${current_agent:-evaluator}" \
    --argjson sprint "$sprint_num" \
    --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{
      from: $from,
      to: "archive",
      prompt: "Sprint 문서를 아카이브하세요.\n.harness/actions/의 스프린트 문서를 .harness/archive/sprint-NNN/으로 이동합니다.\n.harness/handoff.json을 읽고 sprint 번호를 확인하세요.",
      sprint: $sprint,
      model: "opus",
      thinking_mode: null,
      timestamp: $timestamp
    }' > "$HANDOFF"

else
  echo '{}' > "$HANDOFF"
fi
