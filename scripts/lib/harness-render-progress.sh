#!/bin/bash
# harness-render-progress.sh — Feature-level 프로그래스 렌더링 (공통 함수)
# source로 포함하여 사용: source "$(dirname "$0")/lib/harness-render-progress.sh"

# ─────────────────────────────────────────
# Dependencies: jq
# ─────────────────────────────────────────
check_jq() {
  if ! command -v jq &>/dev/null; then
    echo "[harness] ERROR: jq is required. Install with: brew install jq" >&2
    return 1
  fi
}

# ─────────────────────────────────────────
# resolve_harness_root — .harness/ 디렉토리 찾기
# ─────────────────────────────────────────
resolve_harness_root() {
  local dir="${1:-.}"
  dir="$(cd "$dir" && pwd)"
  while [ "$dir" != "/" ]; do
    if [ -d "$dir/.harness" ]; then
      echo "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  return 1
}

# ─────────────────────────────────────────
# render_progress — Feature-level 프로그래스 출력
#
# Args:
#   $1 — project root (optional, defaults to auto-detect)
#
# Reads:
#   .harness/progress.json
#   .harness/config.json
#   .harness/actions/feature-list.json (if exists)
# ─────────────────────────────────────────
render_progress() {
  check_jq || return 1

  local PROJECT_ROOT
  PROJECT_ROOT="$(resolve_harness_root "${1:-.}")" || {
    echo "[harness] .harness/ directory not found" >&2
    return 1
  }

  local PROGRESS="$PROJECT_ROOT/.harness/progress.json"
  local CONFIG="$PROJECT_ROOT/.harness/config.json"
  local FEATURES="$PROJECT_ROOT/.harness/actions/feature-list.json"

  if [ ! -f "$PROGRESS" ]; then
    return 1
  fi

  # Read progress.json
  local pipeline sprint_num sprint_status retry_count
  local current_agent agent_status next_agent
  local failure_agent failure_location failure_message

  pipeline=$(jq -r '.pipeline // "unknown"' "$PROGRESS")
  sprint_num=$(jq -r '.sprint.number // 0' "$PROGRESS")
  sprint_status=$(jq -r '.sprint.status // "init"' "$PROGRESS")
  retry_count=$(jq -r '.sprint.retry_count // 0' "$PROGRESS")
  current_agent=$(jq -r '.current_agent // "none"' "$PROGRESS")
  agent_status=$(jq -r '.agent_status // "pending"' "$PROGRESS")
  next_agent=$(jq -r '.next_agent // "none"' "$PROGRESS")
  failure_agent=$(jq -r '.failure.agent // empty' "$PROGRESS")
  failure_location=$(jq -r '.failure.location // empty' "$PROGRESS")
  failure_message=$(jq -r '.failure.message // empty' "$PROGRESS")

  # Read max retries from config
  local max_retries=10
  if [ -f "$CONFIG" ]; then
    max_retries=$(jq -r '.flow.max_retries_per_sprint // 10' "$CONFIG")
  fi

  # Pipeline agents for progress bar
  local -a pipeline_agents
  if [ -f "$CONFIG" ] && [ "$pipeline" != "null" ] && [ "$pipeline" != "unknown" ]; then
    mapfile -t pipeline_agents < <(jq -r ".flow.pipeline_selection.pipelines[\"${pipeline}\"][]" "$CONFIG" 2>/dev/null | sed 's/:.*//')
  fi

  # ── Header ──
  local header="Sprint ${sprint_num} / ${pipeline}"
  local pad_len=$(( 40 - ${#header} ))
  local padding=""
  for ((i=0; i<pad_len; i++)); do padding+="═"; done
  echo ""
  echo "  ═══ ${header} ${padding}"
  echo ""

  # ── Feature Progress ──
  if [ -f "$FEATURES" ]; then
    local total_features completed_features=0 in_progress_features=0
    total_features=$(jq '.features | length' "$FEATURES" 2>/dev/null || echo 0)

    if [ "$total_features" -gt 0 ]; then
      # Determine columns based on pipeline
      local show_be=true show_fe=true
      case "$pipeline" in
        BE-ONLY)  show_fe=false ;;
        FE-ONLY)  show_be=false ;;
      esac

      # Build feature lines
      local i=0
      while [ $i -lt "$total_features" ]; do
        local fid fname passes be_pass fe_pass eval_func_pass eval_visual_pass
        fid=$(jq -r ".features[$i].id // \"F-$((i+1))\"" "$FEATURES")
        fname=$(jq -r ".features[$i].name // .features[$i].description // \"Feature $((i+1))\"" "$FEATURES")
        passes=$(jq -r ".features[$i].passes // [] | .[]" "$FEATURES" 2>/dev/null)

        # Truncate name to 20 chars
        if [ ${#fname} -gt 20 ]; then
          fname="${fname:0:18}.."
        fi

        # Check passes
        be_pass="○"; fe_pass="○"; eval_func_pass="○"; eval_visual_pass="○"
        local eval_done=false

        while IFS= read -r p; do
          case "$p" in
            generator-backend)    be_pass="✓" ;;
            generator-frontend)   fe_pass="✓" ;;
            evaluator-functional) eval_func_pass="✓" ;;
            evaluator-visual)     eval_visual_pass="✓" ;;
          esac
        done <<< "$passes"

        # Eval column: both must pass
        local eval_pass="○"
        if [ "$eval_func_pass" = "✓" ] && [ "$eval_visual_pass" = "✓" ]; then
          eval_pass="✓"
        elif [ "$eval_func_pass" = "✓" ] || [ "$eval_visual_pass" = "✓" ]; then
          eval_pass="◐"
        fi

        # Feature status icon
        local icon="○"
        local is_complete=false
        if [ "$show_be" = true ] && [ "$show_fe" = true ]; then
          # FULLSTACK: all must pass
          if [ "$be_pass" = "✓" ] && [ "$fe_pass" = "✓" ] && [ "$eval_pass" = "✓" ]; then
            icon="✓"; is_complete=true
          elif [ "$be_pass" = "✓" ] || [ "$fe_pass" = "✓" ]; then
            icon="◐"
          fi
        elif [ "$show_be" = true ]; then
          # BE-ONLY
          if [ "$be_pass" = "✓" ] && [ "$eval_pass" = "✓" ]; then
            icon="✓"; is_complete=true
          elif [ "$be_pass" = "✓" ]; then
            icon="◐"
          fi
        else
          # FE-ONLY
          if [ "$fe_pass" = "✓" ] && [ "$eval_pass" = "✓" ]; then
            icon="✓"; is_complete=true
          elif [ "$fe_pass" = "✓" ]; then
            icon="◐"
          fi
        fi

        if [ "$is_complete" = true ]; then
          completed_features=$((completed_features + 1))
        fi

        # Build columns
        local cols=""
        if [ "$show_be" = true ]; then cols+="BE${be_pass}  "; fi
        if [ "$show_fe" = true ]; then cols+="FE${fe_pass}  "; fi
        cols+="Eval${eval_pass}"

        printf "  %s %-5s %-22s %s\n" "$icon" "$fid" "$fname" "$cols"

        i=$((i + 1))
      done

      echo ""

      # ── Progress Bar ──
      local steps_per_feature=0
      if [ "$show_be" = true ]; then steps_per_feature=$((steps_per_feature + 1)); fi
      if [ "$show_fe" = true ]; then steps_per_feature=$((steps_per_feature + 1)); fi
      steps_per_feature=$((steps_per_feature + 1))  # eval

      local total_steps=$((total_features * steps_per_feature))
      local done_steps=0

      # Count individual passes across all features
      i=0
      while [ $i -lt "$total_features" ]; do
        passes=$(jq -r ".features[$i].passes // [] | .[]" "$FEATURES" 2>/dev/null)
        while IFS= read -r p; do
          case "$p" in
            generator-backend)
              if [ "$show_be" = true ]; then done_steps=$((done_steps + 1)); fi
              ;;
            generator-frontend)
              if [ "$show_fe" = true ]; then done_steps=$((done_steps + 1)); fi
              ;;
            evaluator-functional|evaluator-visual)
              # Each eval counts as 0.5 of the eval step
              # We'll handle this by checking both at the end
              ;;
          esac
        done <<< "$passes"

        # Check eval completion
        local ef ev
        ef=$(jq -r ".features[$i].passes // [] | map(select(. == \"evaluator-functional\")) | length" "$FEATURES" 2>/dev/null)
        ev=$(jq -r ".features[$i].passes // [] | map(select(. == \"evaluator-visual\")) | length" "$FEATURES" 2>/dev/null)
        if [ "${ef:-0}" -gt 0 ] && [ "${ev:-0}" -gt 0 ]; then
          done_steps=$((done_steps + 1))
        elif [ "${ef:-0}" -gt 0 ] || [ "${ev:-0}" -gt 0 ]; then
          # partial eval — don't count
          :
        fi

        i=$((i + 1))
      done

      local pct=0
      if [ "$total_steps" -gt 0 ]; then
        pct=$(( done_steps * 100 / total_steps ))
      fi

      local bar_width=16
      local filled=$(( pct * bar_width / 100 ))
      local empty=$(( bar_width - filled ))
      local bar=""
      for ((j=0; j<filled; j++)); do bar+="█"; done
      for ((j=0; j<empty; j++)); do bar+="░"; done

      echo "  Features: ${completed_features}/${total_features} completed"
      echo "  Pipeline: ${bar}  ${pct}%"
    fi
  else
    echo "  (feature-list.json not yet created — run Planner first)"
  fi

  echo ""

  # ── Current Agent Status ──
  if [ "$current_agent" != "none" ] && [ "$current_agent" != "null" ]; then
    echo "  Current:  ${current_agent} [${agent_status}] (retry ${retry_count}/${max_retries})"
  fi

  # ── Failure Info ──
  if [ -n "$failure_agent" ] && [ "$failure_agent" != "null" ]; then
    echo ""
    echo "  ⚠ FAIL: ${failure_agent} → ${failure_location}"
    if [ -n "$failure_message" ] && [ "$failure_message" != "null" ]; then
      echo "    ${failure_message}"
    fi
  fi

  # ── Blocked ──
  if [ "$agent_status" = "blocked" ]; then
    echo ""
    echo "  ✖ BLOCKED: retry limit (${max_retries}) reached — user intervention required"
  fi

  # ── Next Action ──
  if [ "$next_agent" != "none" ] && [ "$next_agent" != "null" ] && [ "$agent_status" != "blocked" ]; then
    echo ""
    echo "  Next → /harness-${next_agent}"
    echo "  Auto → claude --prompt \"\$(cat .harness/next-prompt.txt)\""
  fi

  echo ""
}

# ─────────────────────────────────────────
# render_agent_bar — 에이전트 시퀀스 바 (compact)
# ─────────────────────────────────────────
render_agent_bar() {
  local PROGRESS="${1:-.}/.harness/progress.json"
  local CONFIG="${1:-.}/.harness/config.json"
  local PIPELINE_JSON="${1:-.}/.harness/actions/pipeline.json"

  if [ ! -f "$PROGRESS" ] || [ ! -f "$CONFIG" ]; then return 1; fi

  local pipeline current_agent fe_stack
  pipeline=$(jq -r '.pipeline // "unknown"' "$PROGRESS")
  current_agent=$(jq -r '.current_agent // "none"' "$PROGRESS")
  fe_stack="react"
  if [ -f "$PIPELINE_JSON" ]; then
    fe_stack=$(jq -r '.fe_stack // "react"' "$PIPELINE_JSON" 2>/dev/null || echo "react")
  fi

  local completed_agents
  completed_agents=$(jq -r '.completed_agents // [] | .[]' "$PROGRESS")

  if [ "$pipeline" = "null" ] || [ "$pipeline" = "unknown" ]; then return 1; fi

  local agents_line="  Agents: "
  local first=true

  while IFS= read -r agent; do
    agent=$(echo "$agent" | sed 's/:.*//')  # strip mode suffix like :light, :api-only

    # fe_stack 치환 적용
    if [ "$fe_stack" = "flutter" ]; then
      local sub
      sub=$(jq -r ".flow.pipeline_selection.fe_stack_substitution.flutter[\"${agent}\"] // \"${agent}\"" "$CONFIG" 2>/dev/null)
      if [ "$sub" = "__skip__" ]; then continue; fi
      agent="$sub"
    fi

    if [ "$first" = true ]; then
      first=false
    else
      agents_line+=" → "
    fi

    if echo "$completed_agents" | grep -q "^${agent}$"; then
      agents_line+="${agent}✓"
    elif [ "$agent" = "$current_agent" ]; then
      agents_line+="[${agent}]"
    else
      agents_line+="${agent}"
    fi
  done < <(jq -r ".flow.pipeline_selection.pipelines[\"${pipeline}\"][]" "$CONFIG" 2>/dev/null)

  echo "$agents_line"
}
