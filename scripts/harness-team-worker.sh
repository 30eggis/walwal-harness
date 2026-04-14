#!/bin/bash
# harness-team-worker.sh — Team Worker v4: git worktree 격리 실행
#
# 각 Team이 독립 worktree에서 작업하여 git 충돌 없이 병렬 실행.
# Feature PASS → main merge → worktree 정리.
#
# Usage: bash scripts/harness-team-worker.sh <team_id> [project-root]

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
GIT_LOCK="$PROJECT_ROOT/.harness/.git-lock"

# Worktree base directory
WORKTREE_DIR="$PROJECT_ROOT/.worktrees/team-${TEAM_ID}"

MAX_ATTEMPTS="${MAX_ATTEMPTS:-3}"
GEN_MODEL="${GEN_MODEL:-sonnet}"
EVAL_MODEL="${EVAL_MODEL:-opus}"

if [ -f "$CONFIG" ]; then
  _gm=$(jq -r '.agents["generator-frontend"].model // empty' "$CONFIG" 2>/dev/null)
  _em=$(jq -r '.agents["evaluator-functional"].model // empty' "$CONFIG" 2>/dev/null)
  if [ -n "$_gm" ]; then GEN_MODEL="$_gm"; fi
  if [ -n "$_em" ]; then EVAL_MODEL="$_em"; fi
fi

BOLD="\033[1m"
DIM="\033[2m"
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
CYAN="\033[36m"
RESET="\033[0m"

ts() { date +"%H:%M:%S"; }
log() { echo -e "[$(ts)] ${BOLD}T${TEAM_ID}${RESET} $*"; }
log_progress() { echo "$(date +"%Y-%m-%d %H:%M") | team-${TEAM_ID} | ${1} | ${2}" >> "$PROGRESS_LOG"; }

# ── Git lock ──
acquire_git_lock() {
  local waited=0
  while ! mkdir "$GIT_LOCK" 2>/dev/null; do
    sleep 0.2
    waited=$((waited + 1))
    if [ "$waited" -ge 150 ]; then rm -rf "$GIT_LOCK"; mkdir "$GIT_LOCK" 2>/dev/null || true; break; fi
  done
}
release_git_lock() { rm -rf "$GIT_LOCK" 2>/dev/null || true; }

# ── Worktree management ──
setup_worktree() {
  local branch="$1"

  acquire_git_lock

  # Clean previous worktree if exists
  if [ -d "$WORKTREE_DIR" ]; then
    (cd "$PROJECT_ROOT" && git worktree remove "$WORKTREE_DIR" --force 2>/dev/null) || rm -rf "$WORKTREE_DIR"
  fi

  # Create fresh worktree from main
  (cd "$PROJECT_ROOT" && git worktree add "$WORKTREE_DIR" -b "$branch" main 2>/dev/null) || \
  (cd "$PROJECT_ROOT" && git worktree add "$WORKTREE_DIR" "$branch" 2>/dev/null) || {
    release_git_lock
    log "${RED}Failed to create worktree${RESET}"
    return 1
  }

  release_git_lock

  # Copy .harness to worktree (symlink for shared state)
  ln -sf "$PROJECT_ROOT/.harness" "$WORKTREE_DIR/.harness" 2>/dev/null || true

  log "Worktree: ${WORKTREE_DIR}"
  return 0
}

cleanup_worktree() {
  acquire_git_lock
  if [ -d "$WORKTREE_DIR" ]; then
    (cd "$PROJECT_ROOT" && git worktree remove "$WORKTREE_DIR" --force 2>/dev/null) || rm -rf "$WORKTREE_DIR"
  fi
  release_git_lock
}

merge_to_main() {
  local branch="$1"

  acquire_git_lock

  local merge_ok=false

  # Try merge
  if (cd "$PROJECT_ROOT" && git merge --no-ff "$branch" -m "merge: ${feature_id} PASS" 2>/dev/null); then
    merge_ok=true
  else
    # Conflict → abort, then try rebase in worktree
    (cd "$PROJECT_ROOT" && git merge --abort 2>/dev/null) || true

    log "${YELLOW}Merge conflict — rebasing in worktree...${RESET}"
    if (cd "$WORKTREE_DIR" && git rebase main 2>/dev/null); then
      # Retry merge after rebase
      if (cd "$PROJECT_ROOT" && git merge --no-ff "$branch" -m "merge: ${feature_id} PASS (rebased)" 2>/dev/null); then
        merge_ok=true
      fi
    else
      (cd "$WORKTREE_DIR" && git rebase --abort 2>/dev/null) || true
      log "${RED}Rebase failed${RESET}"
    fi
  fi

  # Clean up branch after merge
  if [ "$merge_ok" = true ]; then
    (cd "$PROJECT_ROOT" && git branch -d "$branch" 2>/dev/null) || true
  fi

  release_git_lock

  [ "$merge_ok" = true ]
}

# ── Pre-eval gate (runs in worktree) ──
run_pre_eval_gate() {
  local work_dir="$WORKTREE_DIR"

  # Resolve cwd within worktree
  if [ -f "$CONFIG" ]; then
    _cwd=$(jq -r '.flow.pre_eval_gate.frontend_cwd // empty' "$CONFIG" 2>/dev/null)
    if [ -n "$_cwd" ] && [ "$_cwd" != "null" ]; then
      work_dir="$WORKTREE_DIR/$_cwd"
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
    if (cd "$work_dir" && timeout 120s bash -c "$cmd" >/dev/null 2>&1); then
      log "  ${GREEN}✓${RESET} $cmd"
    else
      log "  ${RED}✗${RESET} $cmd"
      all_pass=false
    fi
  done

  [ "$all_pass" = true ]
}

# ── Build prompts ──
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
- When done, stage and commit: git add -A && git commit -m 'feat(${fid}): ${fname}'
PROMPT

  if [ "$attempt" -gt 1 ] && [ -n "$feedback" ]; then
    cat <<RETRY

PREVIOUS EVAL FEEDBACK (attempt ${attempt}):
${feedback}

Fix the issues above. Focus specifically on the failed criteria.
RETRY
  fi
}

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
  # ── Dequeue ──
  feature_id=$(bash "$QUEUE_MGR" dequeue "$TEAM_ID" "$PROJECT_ROOT" 2>/dev/null)

  if [ -z "$feature_id" ] || [[ "$feature_id" == "["* ]]; then
    log "${DIM}No features ready. Waiting 10s...${RESET}"
    sleep 10
    remaining=$(jq '(.queue.ready | length) + (.queue.blocked | length) + (.queue.in_progress | length)' "$QUEUE" 2>/dev/null || echo "1")
    if [ "${remaining}" -eq 0 ] 2>/dev/null; then
      log "${GREEN}${BOLD}ALL FEATURES COMPLETE. Team ${TEAM_ID} exiting.${RESET}"
      log_progress "complete" "All features done"
      exit 0
    fi
    continue
  fi

  log "${CYAN}▶ ${feature_id}${RESET}"
  log_progress "dequeue" "${feature_id}"

  # ── Setup worktree ──
  branch="feature/${feature_id}"
  if ! setup_worktree "$branch"; then
    bash "$QUEUE_MGR" fail "$feature_id" "$PROJECT_ROOT" 2>/dev/null
    log_progress "fail" "${feature_id} worktree setup failed"
    continue
  fi

  # ── Gen→Eval Loop ──
  attempt=1
  eval_feedback=""
  passed=false

  while [ "$attempt" -le "$MAX_ATTEMPTS" ]; do
    log "${BOLD}── ${feature_id} attempt ${attempt}/${MAX_ATTEMPTS} ──${RESET}"

    # ── Generate (in worktree) ──
    log "Gen (${GEN_MODEL})..."
    bash "$QUEUE_MGR" update_phase "$feature_id" "gen" "$attempt" "$PROJECT_ROOT" 2>/dev/null

    gen_prompt=$(build_gen_prompt "$feature_id" "$attempt" "$eval_feedback")

    gen_start=$(date +%s)
    gen_output=$(cd "$WORKTREE_DIR" && claude -p "$gen_prompt" \
      --dangerously-skip-permissions \
      --model "$GEN_MODEL" \
      --output-format text 2>&1 | tee /dev/stderr) 2>&1 || true
    gen_elapsed=$(( $(date +%s) - gen_start ))

    files_changed=$(cd "$WORKTREE_DIR" && git diff --name-only 2>/dev/null | wc -l | tr -d ' ')
    log "Gen done (${gen_elapsed}s) — ${files_changed} files"
    log_progress "gen" "${feature_id} #${attempt}: ${files_changed} files, ${gen_elapsed}s"

    # Auto-commit in worktree
    (cd "$WORKTREE_DIR" && git add -A && git commit -m "feat(${feature_id}): attempt ${attempt}" --no-verify 2>/dev/null) || true

    # ── Pre-eval gate (in worktree) ──
    log "Gate..."
    bash "$QUEUE_MGR" update_phase "$feature_id" "gate" "$attempt" "$PROJECT_ROOT" 2>/dev/null

    if ! run_pre_eval_gate; then
      log "${RED}Gate FAIL${RESET}"
      eval_feedback="Pre-eval gate failed: type check or lint errors."
      attempt=$((attempt + 1))
      continue
    fi

    # ── Evaluate (in worktree) ──
    log "Eval (${EVAL_MODEL})..."
    bash "$QUEUE_MGR" update_phase "$feature_id" "eval" "$attempt" "$PROJECT_ROOT" 2>/dev/null

    eval_prompt=$(build_eval_prompt "$feature_id")

    eval_start=$(date +%s)
    eval_output=$(cd "$WORKTREE_DIR" && claude -p "$eval_prompt" \
      --dangerously-skip-permissions \
      --model "$EVAL_MODEL" \
      --output-format text 2>&1 | tee /dev/stderr) 2>&1 || true
    eval_elapsed=$(( $(date +%s) - eval_start ))

    result_line=$(parse_eval_result "$eval_output")
    verdict=$(echo "$result_line" | cut -d'|' -f1)
    score=$(echo "$result_line" | cut -d'|' -f2)
    feedback=$(echo "$result_line" | cut -d'|' -f3-)

    log_progress "eval" "${feature_id} #${attempt}: ${verdict} (${score}) ${eval_elapsed}s"

    if [ "$verdict" = "PASS" ]; then
      log "${GREEN}${BOLD}✓ PASS ${score}/3.00${RESET} (${eval_elapsed}s)"
      passed=true
      break
    else
      log "${RED}✗ FAIL ${score}/3.00${RESET} (${eval_elapsed}s)"
      log "${DIM}  ${feedback}${RESET}"
      eval_feedback="$feedback"
      attempt=$((attempt + 1))
    fi
  done

  # ── Result ──
  if [ "$passed" = true ]; then
    log "Merging → main..."

    if merge_to_main "$branch"; then
      # Cleanup worktree after successful merge
      cleanup_worktree
      bash "$QUEUE_MGR" pass "$feature_id" "$PROJECT_ROOT" 2>/dev/null
      log_progress "pass" "${feature_id} merged & cleaned"

      # Update feature-list.json
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
      cleanup_worktree
      bash "$QUEUE_MGR" fail "$feature_id" "$PROJECT_ROOT" 2>/dev/null
      log "${RED}Merge failed → ${feature_id} FAILED${RESET}"
      log_progress "merge-fail" "${feature_id}"
    fi
  else
    cleanup_worktree
    bash "$QUEUE_MGR" fail "$feature_id" "$PROJECT_ROOT" 2>/dev/null
    log "${RED}${BOLD}✗ ${feature_id} FAILED (${MAX_ATTEMPTS} attempts)${RESET}"
    log_progress "fail" "${feature_id} after ${MAX_ATTEMPTS} attempts"
  fi

  sleep 2
done
