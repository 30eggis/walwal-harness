#!/bin/bash
# harness-eval-watcher.sh — Panel 3: Evaluation 결과 Summary 리뷰
# evaluation-*.md 파일 변경 감지 → 요약 출력 (또는 claude -p 호출)
# Usage: bash scripts/harness-eval-watcher.sh [project-root] [--ai]
#   --ai  evaluation 완료 시 claude -p 로 AI 요약 생성 (API 비용 발생)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

PROJECT_ROOT="${1:-}"
USE_AI=false
for arg in "$@"; do
  if [ "$arg" = "--ai" ]; then USE_AI=true; fi
done

if [ -z "$PROJECT_ROOT" ] || [ "$PROJECT_ROOT" = "--ai" ]; then
  source "$SCRIPT_DIR/lib/harness-render-progress.sh"
  PROJECT_ROOT="$(resolve_harness_root ".")" || {
    echo "[eval-watcher] .harness/ not found. Pass project root as argument."
    exit 1
  }
fi

PROGRESS="$PROJECT_ROOT/.harness/progress.json"
EVAL_FUNC="$PROJECT_ROOT/.harness/actions/evaluation-functional.md"
EVAL_VISUAL="$PROJECT_ROOT/.harness/actions/evaluation-visual.md"

# ── ANSI helpers ──
BOLD="\033[1m"
DIM="\033[2m"
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
CYAN="\033[36m"
RESET="\033[0m"

LAST_FUNC_HASH=""
LAST_VISUAL_HASH=""
EVAL_COUNT=0

print_header() {
  echo -e "${BOLD}╔══════════════════════════════════════╗${RESET}"
  echo -e "${BOLD}║  EVALUATION REVIEW                   ║${RESET}"
  echo -e "${BOLD}╚══════════════════════════════════════╝${RESET}"
  echo ""
}

file_hash() {
  if [ -f "$1" ]; then
    md5 -q "$1" 2>/dev/null || md5sum "$1" 2>/dev/null | awk '{print $1}' || echo ""
  else
    echo ""
  fi
}

# ── Extract eval summary from markdown ──
extract_eval_summary() {
  local file="$1" type="$2"

  if [ ! -f "$file" ]; then return; fi

  EVAL_COUNT=$((EVAL_COUNT + 1))
  local now
  now=$(date +"%H:%M:%S")

  echo -e "  ${BOLD}═══ ${type} Evaluation #${EVAL_COUNT} ═══${RESET}  ${DIM}(${now})${RESET}"
  echo ""

  # Extract Verdict (PASS/FAIL)
  local verdict
  verdict=$(grep -i "verdict\|result\|판정" "$file" | head -3)
  if [ -n "$verdict" ]; then
    if echo "$verdict" | grep -qi "PASS"; then
      echo -e "  ${GREEN}${BOLD}VERDICT: PASS${RESET}"
    elif echo "$verdict" | grep -qi "FAIL"; then
      echo -e "  ${RED}${BOLD}VERDICT: FAIL${RESET}"
    else
      echo -e "  ${YELLOW}VERDICT: ${verdict}${RESET}"
    fi
    echo ""
  fi

  # Extract Score
  local score_line
  score_line=$(grep -iE "score|점수|weighted|가중" "$file" | head -3)
  if [ -n "$score_line" ]; then
    echo -e "  ${BOLD}Score${RESET}"
    echo "$score_line" | while IFS= read -r line; do
      # Color by score value
      local num
      num=$(echo "$line" | grep -oE '[0-9]+\.[0-9]+' | head -1)
      if [ -n "$num" ]; then
        local int_part
        int_part=$(echo "$num" | cut -d. -f1)
        if [ "${int_part:-0}" -ge 3 ] || ([ "${int_part:-0}" -eq 2 ] && [ "$(echo "$num >= 2.80" | bc 2>/dev/null)" = "1" ]); then
          echo -e "    ${GREEN}${line}${RESET}"
        else
          echo -e "    ${RED}${line}${RESET}"
        fi
      else
        echo "    $line"
      fi
    done
    echo ""
  fi

  # Extract individual rubric items (R1-R5 or V1-V5)
  local rubric_lines
  rubric_lines=$(grep -E "^[|#].*[RV][1-5]" "$file" | head -10)
  if [ -n "$rubric_lines" ]; then
    echo -e "  ${BOLD}Rubric${RESET}"
    echo "$rubric_lines" | while IFS= read -r line; do
      echo "    $line"
    done
    echo ""
  fi

  # Extract FAIL reasons
  local fail_lines
  fail_lines=$(grep -iE "fail|실패|regression|불일치|위반" "$file" | head -5)
  if [ -n "$fail_lines" ]; then
    echo -e "  ${RED}${BOLD}Issues${RESET}"
    echo "$fail_lines" | while IFS= read -r line; do
      echo -e "    ${RED}• ${line}${RESET}"
    done
    echo ""
  fi

  # Extract action items / recommendations
  local action_lines
  action_lines=$(grep -iE "recommend|action|수정|개선|필요|re-generate" "$file" | head -5)
  if [ -n "$action_lines" ]; then
    echo -e "  ${YELLOW}${BOLD}Actions${RESET}"
    echo "$action_lines" | while IFS= read -r line; do
      echo -e "    ${YELLOW}→ ${line}${RESET}"
    done
    echo ""
  fi

  echo -e "  ${DIM}─────────────────────────────────────${RESET}"
  echo ""
}

# ── AI Summary (optional) ──
generate_ai_summary() {
  local file="$1" type="$2"

  if [ "$USE_AI" != true ]; then return; fi
  if ! command -v claude &>/dev/null; then
    echo -e "  ${DIM}(claude CLI not found — skipping AI summary)${RESET}"
    return
  fi

  echo -e "  ${CYAN}Generating AI summary...${RESET}"

  local summary
  summary=$(claude -p "다음 ${type} Evaluation 문서를 3줄 이내로 요약해줘. 핵심 결과(PASS/FAIL), 주요 문제점, 다음 액션을 포함:

$(cat "$file")" --output-format text 2>/dev/null || echo "(AI summary failed)")

  echo -e "  ${CYAN}${BOLD}AI Summary:${RESET}"
  echo "$summary" | while IFS= read -r line; do
    echo -e "    ${CYAN}${line}${RESET}"
  done
  echo ""
}

# ── Main ──
print_header

# Show existing evals on startup
if [ -f "$EVAL_FUNC" ]; then
  echo -e "  ${DIM}Found existing functional evaluation${RESET}"
  extract_eval_summary "$EVAL_FUNC" "Functional"
  LAST_FUNC_HASH=$(file_hash "$EVAL_FUNC")
fi

if [ -f "$EVAL_VISUAL" ]; then
  echo -e "  ${DIM}Found existing visual evaluation${RESET}"
  extract_eval_summary "$EVAL_VISUAL" "Visual"
  LAST_VISUAL_HASH=$(file_hash "$EVAL_VISUAL")
fi

if [ -z "$LAST_FUNC_HASH" ] && [ -z "$LAST_VISUAL_HASH" ]; then
  echo -e "  ${DIM}Waiting for evaluation files...${RESET}"
  echo -e "  ${DIM}  ${EVAL_FUNC}${RESET}"
  echo -e "  ${DIM}  ${EVAL_VISUAL}${RESET}"
  echo ""
fi

echo -e "  ${DIM}Watching for changes every 3s  |  Ctrl+C to exit${RESET}"
if [ "$USE_AI" = true ]; then
  echo -e "  ${CYAN}AI summary enabled (claude -p)${RESET}"
fi
echo ""

# ── Poll for changes ──
while true; do
  # Check functional eval
  local_func_hash=$(file_hash "$EVAL_FUNC")
  if [ "$local_func_hash" != "$LAST_FUNC_HASH" ] && [ -n "$local_func_hash" ]; then
    LAST_FUNC_HASH="$local_func_hash"
    extract_eval_summary "$EVAL_FUNC" "Functional"
    generate_ai_summary "$EVAL_FUNC" "Functional"
  fi

  # Check visual eval
  local_visual_hash=$(file_hash "$EVAL_VISUAL")
  if [ "$local_visual_hash" != "$LAST_VISUAL_HASH" ] && [ -n "$local_visual_hash" ]; then
    LAST_VISUAL_HASH="$local_visual_hash"
    extract_eval_summary "$EVAL_VISUAL" "Visual"
    generate_ai_summary "$EVAL_VISUAL" "Visual"
  fi

  # Check agent status for eval-related transitions
  if [ -f "$PROGRESS" ]; then
    local agent
    agent=$(jq -r '.current_agent // "none"' "$PROGRESS" 2>/dev/null)
    local status
    status=$(jq -r '.agent_status // "pending"' "$PROGRESS" 2>/dev/null)

    if [[ "$agent" == evaluator-* ]] && [ "$status" = "running" ]; then
      # Show that evaluator is active
      :
    fi
  fi

  sleep 3
done
