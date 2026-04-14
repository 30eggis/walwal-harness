#!/bin/bash
# harness-team-worker.sh — Team Worker: Feature-level Gen→Eval loop (v4.0)
#
# 1 Team = 1 프로세스. Feature Queue에서 feature를 꺼내
# Gen→Gate→Eval 루프를 claude -p 헤드리스로 자율 실행한다.
#
# Usage:
#   bash scripts/harness-team-worker.sh <team_id> [project-root]
#
# Environment:
#   MAX_ATTEMPTS=3  Feature당 최대 Gen→Eval 시도 횟수
#   GEN_MODEL=sonnet  Generator 모델
#   EVAL_MODEL=opus   Evaluator 모델

set -uo pipefail

TEAM_ID="${1:?Usage: harness-team-worker.sh <team_id> [project-root]}"
shift || true

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Resolve project root ──
PROJECT_ROOT="${1:-}"
if [ -z "$PROJECT_ROOT" ]; then
  dir="$(pwd)"
  while [ "$dir" != "/" ]; do
    if [ -d "$dir/.harness" ]; then PROJECT_ROOT="$dir"; break; fi
    dir="$(dirname "$dir")"
  done
fi

if [ -z "$PROJECT_ROOT" ] || [ ! -d "$PROJECT_ROOT/.harness" ]; then
  echo "[T${TEAM_ID}] .harness/ not found."
  exit 1
fi

QUEUE="$PROJECT_ROOT/.harness/actions/feature-queue.json"
FEATURES="$PROJECT_ROOT/.harness/actions/feature-list.json"
CONFIG="$PROJECT_ROOT/.harness/config.json"
PROGRESS_LOG="$PROJECT_ROOT/.harness/progress.log"
QUEUE_MGR="$SCRIPT_DIR/harness-queue-manager.sh"

MAX_ATTEMPTS="${MAX_ATTEMPTS:-3}"
GEN_MODEL="${GEN_MODEL:-sonnet}"
EVAL_MODEL="${EVAL_MODEL:-opus}"

# Read models from config if available
if [ -f "$CONFIG" ]; then
  _gm=$(jq -r '.agents["generator-frontend"].model // empty' "$CONFIG" 2>/dev/null)
  _em=$(jq -r '.agents["evaluator-functional"].model // empty' "$CONFIG" 2>/dev/null)
  if [ -n "$_gm" ]; then GEN_MODEL="$_gm"; fi
  if [ -n "$_em" ]; then EVAL_MODEL="$_em"; fi
fi

# ── ANSI helpers ──
BOLD="\033[1m"
DIM="\033[2m"
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
CYAN="\033[36m"
RESET="\033[0m"

ts() { date +"%H:%M:%S"; }

log() {
  echo -e "[$(ts)] ${BOLD}T${TEAM_ID}${RESET} $*"
}

log_progress() {
  local action="$1" detail="$2"
  local now
  now=$(date +"%Y-%m-%d")
  echo "${now} | team-${TEAM_ID} | ${action} | ${detail}" >> "$PROGRESS_LOG"
}

# ── Pre-eval gate ──
run_pre_eval_gate() {
  local feature_id="$1"
  local cwd="$PROJECT_ROOT"

  # Read frontend_cwd from config
  if [ -f "$CONFIG" ]; then
    local _cwd
    _cwd=$(jq -r '.flow.pre_eval_gate.frontend_cwd // empty' "$CONFIG" 2>/dev/null)
    if [ -n "$_cwd" ] && [ "$_cwd" != "null" ]; then
      cwd="$PROJECT_ROOT/$_cwd"
    fi
  fi

  local checks=()
  if [ -f "$CONFIG" ]; then
    mapfile -t checks < <(jq -r '.flow.pre_eval_gate.frontend_checks[]' "$CONFIG" 2>/dev/null)
  fi

  if [ ${#checks[@]} -eq 0 ]; then
    checks=("npx tsc --noEmit" "npx eslint src/")
  fi

  local all_pass=true
  for cmd in "${checks[@]}"; do
    if ! (cd "$cwd" && timeout 120s bash -c "$cmd" >/dev/null 2>&1); then
      log "${RED}Gate FAIL:${RESET} $cmd"
      all_pass=false
    fi
  done

  if [ "$all_pass" = true ]; then
    log "${GREEN}Gate: tsc ✓ eslint ✓${RESET}"
    return 0
  else
    return 1
  fi
}

# ── Build generator prompt ──
build_gen_prompt() {
  local feature_id="$1"
  local attempt="$2"
  local eval_feedback="${3:-}"

  local feature_json
  feature_json=$(jq --arg fid "$feature_id" '.features[] | select(.id == $fid)' "$FEATURES" 2>/dev/null)

  local feature_name feature_desc ac_json
  feature_name=$(echo "$feature_json" | jq -r '.name // .description // ""')
  feature_desc=$(echo "$feature_json" | jq -r '.description // ""')
  ac_json=$(echo "$feature_json" | jq -c '.ac // []')

  local prompt="You are Generator-Frontend for a harness engineering project.

PROJECT: $(jq -r '.project_name // ""' "$PROJECT_ROOT/.harness/progress.json" 2>/dev/null)
CONVENTIONS: Read CONVENTIONS.md if it exists.

YOUR TASK: Implement ONLY feature ${feature_id}: ${feature_name}
Description: ${feature_desc}
Acceptance Criteria: ${ac_json}

Read these files for context:
- .harness/actions/feature-list.json (filter to ${feature_id})
- .harness/actions/api-contract.json (relevant endpoints)
- .harness/actions/plan.md (overall design)

RULES:
- Implement ONLY this feature, do not touch other features' code
- Follow existing code patterns and CONVENTIONS.md
- Commit your changes with message: 'feat(${feature_id}): ${feature_name}'
- Do NOT create tests (evaluator will handle that)"

  if [ "$attempt" -gt 1 ] && [ -n "$eval_feedback" ]; then
    prompt="$prompt

PREVIOUS EVAL FEEDBACK (attempt ${attempt}):
${eval_feedback}

Fix the issues from the feedback above. Focus specifically on the failed criteria."
  fi

  echo "$prompt"
}

# ── Build evaluator prompt ──
build_eval_prompt() {
  local feature_id="$1"

  local feature_json
  feature_json=$(jq --arg fid "$feature_id" '.features[] | select(.id == $fid)' "$FEATURES" 2>/dev/null)

  local feature_name ac_json
  feature_name=$(echo "$feature_json" | jq -r '.name // .description // ""')
  ac_json=$(echo "$feature_json" | jq -c '.ac // []')

  local passed_list
  passed_list=$(jq -r '.queue.passed // [] | join(", ")' "$QUEUE" 2>/dev/null)

  echo "You are Evaluator-Functional for a harness engineering project.

TASK: Evaluate feature ${feature_id}: ${feature_name}

Acceptance Criteria to verify:
${ac_json}

Previously passed features (regression check): [${passed_list}]

SCORING RUBRIC (R1-R5):
R1: API Contract compliance (25%)
R2: Acceptance Criteria full pass (25%)
R3: Negative tests (20%)
R4: E2E scenario (15%)
R5: Error handling & edge cases (15%)

PASS threshold: 2.80 / 3.00
FAIL: any AC not met, any regression failure

OUTPUT FORMAT (must be parseable):
---EVAL-RESULT---
FEATURE: ${feature_id}
VERDICT: PASS or FAIL
SCORE: X.XX
FEEDBACK: <one paragraph summary of issues or confirmation>
---END-EVAL-RESULT---"
}

# ── Parse eval result ──
parse_eval_result() {
  local output="$1"

  local verdict score feedback
  verdict=$(echo "$output" | grep -oP 'VERDICT:\s*\K\w+' | head -1)
  score=$(echo "$output" | grep -oP 'SCORE:\s*\K[0-9.]+' | head -1)
  feedback=$(echo "$output" | sed -n 's/^FEEDBACK:\s*//p' | head -1)

  echo "${verdict:-UNKNOWN}|${score:-0.00}|${feedback:-no feedback}"
}

# ══════════════════════════════════════════
# Main Worker Loop
# ══════════════════════════════════════════
log "${CYAN}Team ${TEAM_ID} started${RESET} (gen=${GEN_MODEL}, eval=${EVAL_MODEL}, max=${MAX_ATTEMPTS})"
log_progress "start" "Team ${TEAM_ID} worker started"

while true; do
  # ── Dequeue next feature ──
  feature_id=$(bash "$QUEUE_MGR" dequeue "$TEAM_ID" "$PROJECT_ROOT" 2>/dev/null)

  if [ -z "$feature_id" ] || [[ "$feature_id" == "[queue]"* ]]; then
    log "${DIM}No features in queue. Waiting 10s...${RESET}"
    sleep 10

    # Check if completely done
    local remaining
    remaining=$(jq '(.queue.ready | length) + (.queue.blocked | length) + (.queue.in_progress | length)' "$QUEUE" 2>/dev/null)
    if [ "${remaining:-1}" -eq 0 ]; then
      log "${GREEN}${BOLD}ALL FEATURES COMPLETE. Team ${TEAM_ID} exiting.${RESET}"
      log_progress "complete" "All features done"
      exit 0
    fi
    continue
  fi

  log "${CYAN}▶ Dequeued ${feature_id}${RESET}"
  log_progress "dequeue" "${feature_id}"

  # ── Create feature branch ──
  local branch="feature/${feature_id}"
  (cd "$PROJECT_ROOT" && git checkout -b "$branch" main 2>/dev/null) || \
  (cd "$PROJECT_ROOT" && git checkout "$branch" 2>/dev/null) || true
  log "Branch: ${branch}"

  # ── Gen→Eval Loop ──
  local attempt=1
  local eval_feedback=""
  local passed=false

  while [ "$attempt" -le "$MAX_ATTEMPTS" ]; do
    log "${BOLD}── Attempt ${attempt}/${MAX_ATTEMPTS} ──${RESET}"

    # ── Generate ──
    log "Gen ${feature_id} (${GEN_MODEL})..."
    bash "$QUEUE_MGR" update_phase "$feature_id" "gen" "$attempt" "$PROJECT_ROOT" 2>/dev/null

    local gen_prompt
    gen_prompt=$(build_gen_prompt "$feature_id" "$attempt" "$eval_feedback")

    local gen_output
    gen_output=$(cd "$PROJECT_ROOT" && claude -p "$gen_prompt" --model "$GEN_MODEL" --output-format text 2>&1) || true

    local files_changed
    files_changed=$(cd "$PROJECT_ROOT" && git diff --name-only | wc -l | tr -d ' ')
    log "Gen complete — ${files_changed} files changed"
    log_progress "gen" "${feature_id} attempt ${attempt}: ${files_changed} files"

    # Auto-commit gen output
    (cd "$PROJECT_ROOT" && git add -A && git commit -m "feat(${feature_id}): gen attempt ${attempt}" --no-verify 2>/dev/null) || true

    # ── Pre-eval gate ──
    log "Pre-eval gate..."
    bash "$QUEUE_MGR" update_phase "$feature_id" "gate" "$attempt" "$PROJECT_ROOT" 2>/dev/null

    if ! run_pre_eval_gate "$feature_id"; then
      log "${RED}Gate FAIL — retrying gen${RESET}"
      eval_feedback="Pre-eval gate failed: type check or lint errors. Fix compilation and lint issues."
      attempt=$((attempt + 1))
      continue
    fi

    # ── Evaluate ──
    log "Eval ${feature_id} (${EVAL_MODEL})..."
    bash "$QUEUE_MGR" update_phase "$feature_id" "eval" "$attempt" "$PROJECT_ROOT" 2>/dev/null

    local eval_prompt
    eval_prompt=$(build_eval_prompt "$feature_id")

    local eval_output
    eval_output=$(cd "$PROJECT_ROOT" && claude -p "$eval_prompt" --model "$EVAL_MODEL" --output-format text 2>&1) || true

    # Parse result
    local result_line verdict score feedback
    result_line=$(parse_eval_result "$eval_output")
    verdict=$(echo "$result_line" | cut -d'|' -f1)
    score=$(echo "$result_line" | cut -d'|' -f2)
    feedback=$(echo "$result_line" | cut -d'|' -f3-)

    log_progress "eval" "${feature_id} attempt ${attempt}: ${verdict} (${score})"

    if [ "$verdict" = "PASS" ]; then
      log "${GREEN}${BOLD}✓ PASS${RESET} ${feature_id} — ${score}/3.00"
      passed=true
      break
    else
      log "${RED}✗ FAIL${RESET} ${feature_id} — ${score}/3.00"
      log "${DIM}  ${feedback}${RESET}"
      eval_feedback="$feedback"
      attempt=$((attempt + 1))
    fi
  done

  # ── Result processing ──
  if [ "$passed" = true ]; then
    # Merge to main
    log "Merging ${branch} → main..."
    (cd "$PROJECT_ROOT" && git checkout main 2>/dev/null && git merge --no-ff "$branch" -m "merge: ${feature_id} PASS" 2>/dev/null) || {
      log "${YELLOW}Merge conflict — rebasing...${RESET}"
      (cd "$PROJECT_ROOT" && git checkout "$branch" && git rebase main 2>/dev/null && \
       git checkout main && git merge --no-ff "$branch" -m "merge: ${feature_id} PASS (rebased)" 2>/dev/null) || {
        log "${RED}Merge failed after rebase. Manual intervention needed.${RESET}"
        bash "$QUEUE_MGR" fail "$feature_id" "$PROJECT_ROOT" 2>/dev/null
        log_progress "merge-fail" "${feature_id}"
        continue
      }
    }

    # Mark passed in queue
    bash "$QUEUE_MGR" pass "$feature_id" "$PROJECT_ROOT" 2>/dev/null
    log_progress "pass" "${feature_id} merged to main"

    # Update feature-list.json passes
    if [ -f "$FEATURES" ]; then
      jq --arg fid "$feature_id" '
        .features |= map(
          if .id == $fid then
            .passes = ((.passes // []) + ["generator-frontend", "evaluator-functional"] | unique)
          else . end
        )
      ' "$FEATURES" > "${FEATURES}.tmp" && mv "${FEATURES}.tmp" "$FEATURES"
    fi

  else
    log "${RED}${BOLD}✗ ${feature_id} FAILED after ${MAX_ATTEMPTS} attempts${RESET}"
    bash "$QUEUE_MGR" fail "$feature_id" "$PROJECT_ROOT" 2>/dev/null
    log_progress "fail" "${feature_id} after ${MAX_ATTEMPTS} attempts"

    # Return to main
    (cd "$PROJECT_ROOT" && git checkout main 2>/dev/null) || true
  fi

  # Brief pause before next feature
  sleep 2
done
