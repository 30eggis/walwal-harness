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

# ── Lock file for git operations (prevent race conditions between teams) ──
GIT_LOCK="$PROJECT_ROOT/.harness/.git-lock"

MAX_ATTEMPTS="${MAX_ATTEMPTS:-3}"
GEN_MODEL="${GEN_MODEL:-sonnet}"
EVAL_MODEL="${EVAL_MODEL:-opus}"

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
  echo "$(date +"%Y-%m-%d") | team-${TEAM_ID} | ${1} | ${2}" >> "$PROGRESS_LOG"
}

# ── Git lock — serialize git checkout/merge across teams ──
acquire_git_lock() {
  local max_wait=60 waited=0
  while [ -f "$GIT_LOCK" ]; do
    sleep 1
    waited=$((waited + 1))
    if [ "$waited" -ge "$max_wait" ]; then
      log "${RED}Git lock timeout (${max_wait}s). Removing stale lock.${RESET}"
      rm -f "$GIT_LOCK"
      break
    fi
  done
  echo "T${TEAM_ID}" > "$GIT_LOCK"
}

release_git_lock() {
  rm -f "$GIT_LOCK"
}

# ── Pre-eval gate ──
run_pre_eval_gate() {
  local cwd="$PROJECT_ROOT"

  if [ -f "$CONFIG" ]; then
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

  local all_pass=true fail_cmds=""
  for cmd in "${checks[@]}"; do
    if (cd "$cwd" && timeout 120s bash -c "$cmd" >/dev/null 2>&1); then
      log "  ${GREEN}✓${RESET} $cmd"
    else
      log "  ${RED}✗${RESET} $cmd"
      all_pass=false
      fail_cmds+="$cmd; "
    fi
  done

  [ "$all_pass" = true ]
}

# ── Build generator prompt ──
build_gen_prompt() {
  local fid="$1" attempt="$2" feedback="${3:-}"

  local fobj
  fobj=$(jq --arg fid "$fid" '.features[] | select(.id == $fid)' "$FEATURES" 2>/dev/null)
  local fname fdesc ac_json deps_json
  fname=$(echo "$fobj" | jq -r '.name // .description // ""')
  fdesc=$(echo "$fobj" | jq -r '.description // ""')
  ac_json=$(echo "$fobj" | jq -c '.ac // []')
  deps_json=$(echo "$fobj" | jq -c '.depends_on // []')

  local project_name
  project_name=$(jq -r '.project_name // ""' "$PROJECT_ROOT/.harness/progress.json" 2>/dev/null)

  cat <<PROMPT
You are Generator-Frontend for a harness engineering project.

PROJECT: ${project_name}
CONVENTIONS: Read CONVENTIONS.md if it exists.

YOUR TASK: Implement ONLY feature ${fid}: ${fname}
Description: ${fdesc}
Dependencies (already implemented): ${deps_json}
Acceptance Criteria: ${ac_json}

Read these files for context:
- .harness/actions/feature-list.json (filter to ${fid})
- .harness/actions/api-contract.json (relevant endpoints)
- .harness/actions/plan.md (overall design)

RULES:
- Implement ONLY this single feature
- Do NOT modify code belonging to other features
- Follow existing code patterns and CONVENTIONS.md
- When done, stage and commit with: git add -A && git commit -m 'feat(${fid}): ${fname}'
PROMPT

  if [ "$attempt" -gt 1 ] && [ -n "$feedback" ]; then
    cat <<RETRY

PREVIOUS EVAL FEEDBACK (attempt ${attempt}):
${feedback}

Fix the issues above. Focus specifically on the failed criteria.
RETRY
  fi
}

# ── Build evaluator prompt ──
build_eval_prompt() {
  local fid="$1"

  local fobj
  fobj=$(jq --arg fid "$fid" '.features[] | select(.id == $fid)' "$FEATURES" 2>/dev/null)
  local fname ac_json
  fname=$(echo "$fobj" | jq -r '.name // .description // ""')
  ac_json=$(echo "$fobj" | jq -c '.ac // []')

  local passed_list
  passed_list=$(jq -r '.queue.passed // [] | join(", ")' "$QUEUE" 2>/dev/null)

  cat <<PROMPT
You are Evaluator-Functional for a harness engineering project.

TASK: Evaluate feature ${fid}: ${fname}

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

You MUST output this exact block (parseable by automation):
---EVAL-RESULT---
FEATURE: ${fid}
VERDICT: PASS or FAIL
SCORE: X.XX
FEEDBACK: one paragraph summary
---END-EVAL-RESULT---
PROMPT
}

# ── Parse eval result (macOS-compatible, no grep -P) ──
parse_eval_result() {
  local output="$1"

  local verdict score feedback
  verdict=$(echo "$output" | grep -E '^VERDICT:' | sed 's/VERDICT:[[:space:]]*//' | head -1)
  score=$(echo "$output" | grep -E '^SCORE:' | sed 's/SCORE:[[:space:]]*//' | head -1)
  feedback=$(echo "$output" | grep -E '^FEEDBACK:' | sed 's/FEEDBACK:[[:space:]]*//' | head -1)

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

  if [ -z "$feature_id" ] || [[ "$feature_id" == "["* ]]; then
    log "${DIM}No features ready. Waiting 10s...${RESET}"
    sleep 10

    # Check if completely done
    remaining=$(jq '(.queue.ready | length) + (.queue.blocked | length) + (.queue.in_progress | length)' "$QUEUE" 2>/dev/null || echo "1")
    if [ "${remaining}" -eq 0 ] 2>/dev/null; then
      log "${GREEN}${BOLD}ALL FEATURES COMPLETE. Team ${TEAM_ID} exiting.${RESET}"
      log_progress "complete" "All features done"
      exit 0
    fi
    continue
  fi

  log "${CYAN}▶ Dequeued ${feature_id}${RESET}"
  log_progress "dequeue" "${feature_id}"

  # ── Create feature branch (with lock) ──
  branch="feature/${feature_id}"
  acquire_git_lock
  (cd "$PROJECT_ROOT" && git checkout main 2>/dev/null && git checkout -b "$branch" 2>/dev/null) || \
  (cd "$PROJECT_ROOT" && git checkout "$branch" 2>/dev/null) || true
  release_git_lock
  log "Branch: ${branch}"

  # ── Gen→Eval Loop ──
  attempt=1
  eval_feedback=""
  passed=false

  while [ "$attempt" -le "$MAX_ATTEMPTS" ]; do
    log "${BOLD}── Attempt ${attempt}/${MAX_ATTEMPTS} ──${RESET}"

    # ── Generate ──
    log "Gen ${feature_id} (${GEN_MODEL})..."
    bash "$QUEUE_MGR" update_phase "$feature_id" "gen" "$attempt" "$PROJECT_ROOT" 2>/dev/null

    gen_prompt=$(build_gen_prompt "$feature_id" "$attempt" "$eval_feedback")

    gen_start=$(date +%s)
    gen_output=$(cd "$PROJECT_ROOT" && claude -p "$gen_prompt" --model "$GEN_MODEL" --output-format text 2>&1) || true
    gen_elapsed=$(( $(date +%s) - gen_start ))

    files_changed=$(cd "$PROJECT_ROOT" && git diff --name-only 2>/dev/null | wc -l | tr -d ' ')
    log "Gen done (${gen_elapsed}s) — ${files_changed} files"
    log_progress "gen" "${feature_id} attempt ${attempt}: ${files_changed} files, ${gen_elapsed}s"

    # Auto-commit
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

    eval_prompt=$(build_eval_prompt "$feature_id")

    eval_start=$(date +%s)
    eval_output=$(cd "$PROJECT_ROOT" && claude -p "$eval_prompt" --model "$EVAL_MODEL" --output-format text 2>&1) || true
    eval_elapsed=$(( $(date +%s) - eval_start ))

    # Parse result
    result_line=$(parse_eval_result "$eval_output")
    verdict=$(echo "$result_line" | cut -d'|' -f1)
    score=$(echo "$result_line" | cut -d'|' -f2)
    feedback=$(echo "$result_line" | cut -d'|' -f3-)

    log_progress "eval" "${feature_id} attempt ${attempt}: ${verdict} (${score}) ${eval_elapsed}s"

    if [ "$verdict" = "PASS" ]; then
      log "${GREEN}${BOLD}✓ PASS${RESET} ${feature_id} — ${score}/3.00 (${eval_elapsed}s)"
      passed=true
      break
    else
      log "${RED}✗ FAIL${RESET} ${feature_id} — ${score}/3.00 (${eval_elapsed}s)"
      log "${DIM}  ${feedback}${RESET}"
      eval_feedback="$feedback"
      attempt=$((attempt + 1))
    fi
  done

  # ══════════════════════════════════════════
  # Phase 3: Branch merge with conflict handling
  # ══════════════════════════════════════════
  if [ "$passed" = true ]; then
    log "Merging ${branch} → main..."
    acquire_git_lock

    merge_ok=false

    # Attempt 1: straight merge
    if (cd "$PROJECT_ROOT" && git checkout main 2>/dev/null && git merge --no-ff "$branch" -m "merge: ${feature_id} PASS" 2>/dev/null); then
      merge_ok=true
    else
      # Attempt 2: abort failed merge, rebase, re-eval gate, then merge
      log "${YELLOW}Conflict detected — rebasing ${branch} onto main...${RESET}"
      (cd "$PROJECT_ROOT" && git merge --abort 2>/dev/null) || true
      (cd "$PROJECT_ROOT" && git checkout "$branch" 2>/dev/null) || true

      if (cd "$PROJECT_ROOT" && git rebase main 2>/dev/null); then
        log "Rebase OK. Re-running gate..."

        if run_pre_eval_gate "$feature_id"; then
          log "Gate still PASS after rebase."
          if (cd "$PROJECT_ROOT" && git checkout main 2>/dev/null && git merge --no-ff "$branch" -m "merge: ${feature_id} PASS (rebased)" 2>/dev/null); then
            merge_ok=true
          fi
        else
          log "${RED}Gate FAIL after rebase — needs re-gen${RESET}"
        fi
      else
        log "${RED}Rebase failed — conflicts too complex${RESET}"
        (cd "$PROJECT_ROOT" && git rebase --abort 2>/dev/null) || true
      fi
    fi

    release_git_lock

    if [ "$merge_ok" = true ]; then
      # Clean up feature branch
      (cd "$PROJECT_ROOT" && git branch -d "$branch" 2>/dev/null) || true

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

      log "${GREEN}${BOLD}✓ ${feature_id} DONE${RESET}"
    else
      log "${RED}${BOLD}Merge failed — ${feature_id} marked as failed${RESET}"
      (cd "$PROJECT_ROOT" && git checkout main 2>/dev/null) || true
      bash "$QUEUE_MGR" fail "$feature_id" "$PROJECT_ROOT" 2>/dev/null
      log_progress "merge-fail" "${feature_id}"
    fi

  else
    log "${RED}${BOLD}✗ ${feature_id} FAILED after ${MAX_ATTEMPTS} attempts${RESET}"
    acquire_git_lock
    (cd "$PROJECT_ROOT" && git checkout main 2>/dev/null) || true
    release_git_lock
    bash "$QUEUE_MGR" fail "$feature_id" "$PROJECT_ROOT" 2>/dev/null
    log_progress "fail" "${feature_id} after ${MAX_ATTEMPTS} attempts"
  fi

  sleep 2
done
