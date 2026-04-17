#!/bin/bash
# Harness Init Script — 적응형(adaptive) 하네스 진입점 허브
#
# 서브커맨드:
#   help                               — 사용법 출력
#   check         (default · 무인자)   — 환경 확인 + scan + ref 상태 출력 (기존 동작)
#   init          [project_root]       — 신규 프로젝트 초기화 (scan → ref placeholder → AGENTS.md)
#   refresh-ref   <role> <stack>       — 기존 ref 파일 archive 백업 후 재생성 유도
#
# 스택별 서버 기동은 scan-result.json.tech_stack 과 .harness/ref/<role>-<stack>.md.runner 에서
# 가져온다. NestJS/React 하드코딩은 제거되었다.

set -e

SUBCOMMAND="${1:-check}"
shift || true

usage() {
  cat <<'USAGE'
Harness Init — 적응형 하네스 진입점

Usage:
  bash init.sh help                                 — 이 메시지
  bash init.sh check         [project_root]         — 환경 확인 + scan + ref 상태 (기본)
  bash init.sh init          [project_root]         — scan + ref placeholder 생성 + AGENTS.md
  bash init.sh refresh-ref   <role> <stack> [path]  — 기존 ref 파일 백업 후 재생성 안내

스택 독립: 개발 서버 기동 명령은 .harness/ref/<role>-<stack>.md 의 runner.dev_command 에서 조회한다.
USAGE
}

run_check() {
  local project_root="${1:-.}"
  echo "=== Harness Environment Check ==="
  echo "Working Directory: $(pwd)"
  echo "Date: $(date)"
  echo ""

  # Git 상태
  echo "--- Git Status ---"
  if [ -d "${project_root}/.git" ]; then
    git -C "$project_root" log --oneline -5 2>/dev/null || echo "No commits yet"
    echo ""
    git -C "$project_root" status --short
  else
    echo "Not a git repository — run: git init"
  fi
  echo ""

  # Harness 상태
  echo "--- Harness Status ---"
  if [ -f "${project_root}/.harness/progress.json" ]; then
    if [ -f "${project_root}/scripts/lib/harness-render-progress.sh" ]; then
      (cd "$project_root" && source scripts/lib/harness-render-progress.sh && render_progress "." 2>/dev/null) || cat "${project_root}/.harness/progress.json"
    else
      cat "${project_root}/.harness/progress.json"
    fi
  else
    echo "progress.json not found — run: bash init.sh init"
  fi
  echo ""

  # scan 상태
  echo "--- Scan Result ---"
  if [ -f "${project_root}/.harness/actions/scan-result.json" ]; then
    jq '{tech_stack, tech_stack_confidence, recommendation}' "${project_root}/.harness/actions/scan-result.json"
  else
    echo "scan-result.json not found — run: bash scripts/scan-project.sh ${project_root}"
  fi
  echo ""

  # ref 상태
  echo "--- Ref Docs ---"
  if [ -d "${project_root}/.harness/ref" ]; then
    ls -1 "${project_root}/.harness/ref/" 2>/dev/null | grep -v '^\.generated' | sed 's/^/  /' || echo "  (none)"
  else
    echo "  .harness/ref/ not present — run: bash init.sh init"
  fi
  echo ""

  echo "=== Harness Ready ==="
}

run_init() {
  local project_root="${1:-.}"
  echo "=== Harness Init: ${project_root} ==="

  # 1. scan
  echo "[1/3] scan-project.sh"
  bash "$(dirname "$0")/scripts/scan-project.sh" "$project_root"
  echo ""

  # 2. ref placeholder 생성 (감지된 스택 전체)
  echo "[2/3] init-ref-docs.sh (placeholder)"
  bash "$(dirname "$0")/scripts/init-ref-docs.sh" --yes --placeholder "$project_root"
  echo ""

  # 3. AGENTS.md 동적 생성
  if [ -f "$(dirname "$0")/scripts/init-agents-md.sh" ]; then
    echo "[3/3] init-agents-md.sh"
    bash "$(dirname "$0")/scripts/init-agents-md.sh" "$project_root"
  else
    echo "[3/3] init-agents-md.sh — skip (not found)"
  fi
  echo ""

  echo "=== Init Complete ==="
  echo "다음 단계:"
  echo "  1. 각 .harness/ref/<role>-<stack>.md 를 실제 컨텐츠로 채우려면:"
  echo "     bash init.sh refresh-ref <role> <stack> $project_root"
  echo "  2. 그 결과 프롬프트를 Claude 세션에 붙여 WebSearch + WebFetch 로 ref 작성"
}

run_refresh_ref() {
  local role="$1" stack="$2" project_root="${3:-.}"
  if [ -z "$role" ] || [ -z "$stack" ]; then
    echo "ERROR: bash init.sh refresh-ref <role> <stack> [project_root]" >&2
    exit 1
  fi

  local ref_path="${project_root}/.harness/ref/${role}-${stack}.md"
  local archive_dir="${project_root}/.harness/archive"
  mkdir -p "$archive_dir"

  if [ -f "$ref_path" ]; then
    local backup="${archive_dir}/ref-${role}-${stack}-$(date +%Y%m%d%H%M%S).md"
    mv "$ref_path" "$backup"
    echo "archive: $backup"
  fi

  echo ""
  bash "$(dirname "$0")/scripts/init-ref-docs.sh" --claude-prompt --stack "$stack" --role "$role" "$project_root"
}

case "$SUBCOMMAND" in
  help|-h|--help)      usage ;;
  check)               run_check "$@" ;;
  init)                run_init "$@" ;;
  refresh-ref)         run_refresh_ref "$@" ;;
  *)
    echo "ERROR: unknown subcommand '$SUBCOMMAND'" >&2
    usage
    exit 1
    ;;
esac
