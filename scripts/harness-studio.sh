#!/bin/bash
# harness-studio.sh — 하네스 통합 진입점
#
# 사용자가 기억할 명령: 이것 하나.
#
#   bash scripts/harness-studio.sh          # 자동 감지: v3 or v4
#   bash scripts/harness-studio.sh --kill   # 세션 종료
#   bash scripts/harness-studio.sh --v3     # v3 강제
#   bash scripts/harness-studio.sh --v4     # v4 강제
#
# 자동 감지 기준:
#   feature-queue.json 존재 → v4 (Agent Teams 병렬 모드)
#   없으면 → v3 (순차 파이프라인 모드)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FORCE_MODE=""

# ── Parse args (pass through to sub-script) ──
PASSTHROUGH_ARGS=()
for arg in "$@"; do
  case "$arg" in
    --v3)   FORCE_MODE="v3" ;;
    --v4)   FORCE_MODE="v4" ;;
    --kill)
      tmux kill-session -t "harness-studio" 2>/dev/null && echo "v3 killed." || true
      tmux kill-session -t "harness-v4" 2>/dev/null && echo "v4 killed." || true
      exit 0
      ;;
    *)
      PASSTHROUGH_ARGS+=("$arg")
      ;;
  esac
done

# ── Auto-detect mode ──
detect_mode() {
  local dir="${1:-.}"
  while [ "$dir" != "/" ]; do
    if [ -d "$dir/.harness" ]; then
      if [ -f "$dir/.harness/actions/feature-queue.json" ]; then
        echo "v4"
      else
        echo "v3"
      fi
      return
    fi
    dir="$(dirname "$dir")"
  done
  echo "v3"  # default
}

MODE="${FORCE_MODE:-$(detect_mode "$(pwd)")}"

echo "Harness Studio — mode: $MODE"
echo ""

case "$MODE" in
  v4)
    exec bash "$SCRIPT_DIR/harness-tmux-v4.sh" "${PASSTHROUGH_ARGS[@]}"
    ;;
  v3)
    exec bash "$SCRIPT_DIR/harness-tmux.sh" "${PASSTHROUGH_ARGS[@]}"
    ;;
esac
