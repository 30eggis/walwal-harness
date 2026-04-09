#!/bin/bash
# harness-next.sh — 세션 오케스트레이터
# 현재 progress.json 상태를 읽고 다음 에이전트를 결정한다.
# Feature-level 프로그래스를 출력하고 next-prompt.txt를 생성한다.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/harness-render-progress.sh"

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
NEXT_PROMPT="$PROJECT_ROOT/.harness/next-prompt.txt"

check_jq || exit 1

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
# fe_stack + fe_target 치환 헬퍼
#   pipeline_selection.pipelines 에서 읽은 에이전트명을 fe_stack/fe_target 에 따라 치환
#   - react: 그대로
#   - flutter+web: generator-frontend → generator-frontend-flutter 만 치환, eval 은 그대로 (Playwright 사용 가능)
#   - flutter+mobile/desktop: eval 도 정적 분석용으로 치환, evaluator-visual 은 __skip__
# ─────────────────────────────────────────
substitute_fe_stack() {
  local agent="$1"
  if [ "$fe_stack" != "flutter" ]; then
    echo "$agent"
    return
  fi
  local sub
  sub=$(jq -r ".flow.pipeline_selection.fe_stack_substitution.${fe_stack}.by_target[\"${fe_target}\"][\"${agent}\"] // \"${agent}\"" "$CONFIG" 2>/dev/null)
  echo "$sub"
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
# Render progress
# ─────────────────────────────────────────
render_progress "$PROJECT_ROOT"
render_agent_bar "$PROJECT_ROOT"
echo ""

# ─────────────────────────────────────────
# Generate next-prompt.txt
# ─────────────────────────────────────────
if [ "$next_agent" != "null" ] && [ "$next_agent" != "archive" ] && [ "$agent_status" != "blocked" ]; then
  # Build prompt
  prompt="/harness-${next_agent} 를 실행하세요."

  if [ "$sprint_num" -gt 0 ]; then
    prompt+=$'\n'"Sprint ${sprint_num}"
    if [ "$sprint_status" = "failed" ]; then
      prompt+=" (retry ${retry_count}/${max_retries})"
    fi
    prompt+="을 진행합니다."
  fi

  prompt+=$'\n'".harness/progress.json을 읽고 현재 상태를 확인하세요."

  # Add failure context if retrying
  failure_msg=$(jq -r '.failure.message // empty' "$PROGRESS")
  if [ -n "$failure_msg" ] && [ "$failure_msg" != "null" ]; then
    prompt+=$'\n\n'"이전 실패 사유: ${failure_msg}"
  fi

  echo "$prompt" > "$NEXT_PROMPT"

elif [ "$next_agent" = "archive" ]; then
  cat > "$NEXT_PROMPT" <<'PROMPT'
Sprint 문서를 아카이브 하세요.
.harness/actions/의 스프린트 문서를 .harness/archive/sprint-NNN/으로 이동합니다.
.harness/progress.json을 읽고 sprint 번호를 확인하세요.
PROMPT

else
  echo "" > "$NEXT_PROMPT"
fi
