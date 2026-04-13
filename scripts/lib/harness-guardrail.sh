#!/bin/bash
# harness-guardrail.sh — 런타임 파일 소유권 검증
# 에이전트 전환 시 이전 에이전트가 권한 밖 파일을 수정했는지 git diff로 검증.
#
# 사용법: source lib/harness-guardrail.sh && verify_file_ownership "$PROJECT_ROOT"
# 반환값: 0=통과, 1=위반 발견 (위반 목록을 stdout에 출력)

# ─────────────────────────────────────────
# Agent → 허용 경로 매핑
# ─────────────────────────────────────────
get_allowed_paths() {
  local agent="$1"
  case "$agent" in
    planner)
      echo "AGENTS.md"
      echo ".harness/actions/"
      echo ".harness/progress.json"
      echo ".harness/progress.log"
      ;;
    generator-backend)
      echo "apps/gateway/"
      echo "apps/service-"
      echo "libs/"
      echo ".harness/actions/sprint-contract.md"
      echo ".harness/actions/feature-list.json"
      echo ".harness/progress.json"
      echo "package.json"
      echo "nest-cli.json"
      echo "tsconfig"
      echo "docker-compose"
      ;;
    generator-frontend|generator-frontend-flutter)
      echo "apps/web/"
      echo "apps/flutter/"
      echo ".harness/actions/sprint-contract.md"
      echo ".harness/actions/feature-list.json"
      echo ".harness/progress.json"
      echo "package.json"
      echo "tsconfig"
      echo "pubspec"
      ;;
    evaluator-functional|evaluator-functional-flutter)
      echo ".harness/actions/evaluation-functional.md"
      echo ".harness/progress.json"
      echo "tests/"
      echo "test/"
      echo "e2e/"
      echo "playwright"
      ;;
    evaluator-visual)
      echo ".harness/actions/evaluation-visual.md"
      echo ".harness/progress.json"
      ;;
    dispatcher)
      echo ".harness/"
      ;;
    *)
      echo "**"  # unknown agent — allow all (safe fallback)
      ;;
  esac
}

# ─────────────────────────────────────────
# verify_file_ownership — git diff 기반 검증
#
# Args:
#   $1 — project root
#
# Reads:
#   .harness/progress.json (current_agent)
#
# Returns: 0=pass, 1=violation found
# ─────────────────────────────────────────
verify_file_ownership() {
  local PROJECT_ROOT="$1"
  local PROGRESS="$PROJECT_ROOT/.harness/progress.json"

  if [ ! -f "$PROGRESS" ]; then return 0; fi

  local agent
  agent=$(jq -r '.current_agent // "null"' "$PROGRESS" 2>/dev/null)
  if [ "$agent" = "null" ] || [ -z "$agent" ]; then return 0; fi

  # git이 없으면 skip
  if ! command -v git &>/dev/null; then return 0; fi

  # 마지막 커밋 이후 변경된 파일 목록
  local -a changed_files
  mapfile -t changed_files < <(cd "$PROJECT_ROOT" && git diff --name-only HEAD 2>/dev/null)

  # staged 파일도 포함
  local -a staged_files
  mapfile -t staged_files < <(cd "$PROJECT_ROOT" && git diff --name-only --cached 2>/dev/null)

  # 합치기 (중복 제거)
  local -a all_files
  mapfile -t all_files < <(printf '%s\n' "${changed_files[@]}" "${staged_files[@]}" | sort -u | grep -v '^$')

  if [ ${#all_files[@]} -eq 0 ]; then return 0; fi

  # 허용 경로 목록
  local -a allowed
  mapfile -t allowed < <(get_allowed_paths "$agent")

  # 위반 검사
  local -a violations=()
  for file in "${all_files[@]}"; do
    local is_allowed=false
    for pattern in "${allowed[@]}"; do
      if [[ "$file" == $pattern* ]]; then
        is_allowed=true
        break
      fi
    done
    if [ "$is_allowed" = false ]; then
      violations+=("$file")
    fi
  done

  if [ ${#violations[@]} -eq 0 ]; then
    return 0
  fi

  # 위반 보고
  echo ""
  echo "  ── Guardrail Violation ────────────────"
  echo "  Agent '$agent' modified files outside its allowed paths:"
  echo ""
  for v in "${violations[@]}"; do
    echo "    ✗ $v"
  done
  echo ""
  echo "  Allowed paths for $agent:"
  for p in "${allowed[@]}"; do
    echo "    ✓ $p*"
  done
  echo ""
  echo "  Action: Review these changes before proceeding."
  echo "  ─────────────────────────────────────────"
  echo ""

  return 1
}
