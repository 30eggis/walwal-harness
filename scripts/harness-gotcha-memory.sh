#!/bin/bash
# harness-gotcha-memory.sh — Gotcha & Memory pane (index view)
# 활성 에이전트의 gotcha를 최상단으로, 나머지는 요약(최근 3항목+총개수)으로 표시
# Usage: bash scripts/harness-gotcha-memory.sh [project-root]

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/harness-render-progress.sh"

PROJECT_ROOT="${1:-}"
if [ -z "$PROJECT_ROOT" ]; then
  PROJECT_ROOT="$(resolve_harness_root ".")" || { echo "[gotcha] .harness/ not found."; exit 1; }
fi

MEMORY_FILE="$PROJECT_ROOT/.harness/memory.md"
GOTCHAS_DIR="$PROJECT_ROOT/.harness/gotchas"
PROGRESS="$PROJECT_ROOT/.harness/progress.json"

BOLD="\033[1m"
DIM="\033[2m"
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
CYAN="\033[36m"
MAGENTA="\033[35m"
RESET="\033[0m"
BG_YELLOW="\033[43m"

REFRESH_SEC="${HARNESS_REFRESH:-5}"
RECENT_N="${HARNESS_GOTCHA_RECENT:-3}"

# 활성 에이전트 결정: current_agent > next_agent
get_active_agent() {
  [ -f "$PROGRESS" ] || { echo ""; return; }
  command -v jq &>/dev/null || { echo ""; return; }
  local cur nxt
  cur=$(jq -r '.current_agent // ""' "$PROGRESS" 2>/dev/null)
  nxt=$(jq -r '.next_agent // ""' "$PROGRESS" 2>/dev/null)
  if [ -n "$cur" ] && [ "$cur" != "null" ] && [ "$cur" != "none" ]; then
    echo "$cur"
  elif [ -n "$nxt" ] && [ "$nxt" != "null" ] && [ "$nxt" != "none" ]; then
    echo "$nxt"
  else
    echo ""
  fi
}

# gotcha 파일에서 '### ' 헤딩 개수 = 항목 총수
count_items() {
  local f="$1"
  local n
  n=$(grep -c '^### ' "$f" 2>/dev/null)
  echo "${n:-0}"
}

# 최근 N개 항목 제목 추출 (### 헤딩 — 파일 하단부가 최신이라 tail)
recent_titles() {
  local f="$1" n="$2"
  grep '^### ' "$f" 2>/dev/null | tail -n "$n" | sed 's/^### //'
}

# agent 이름 → 파일 basename 매핑 (정확/접두 일치)
file_for_agent() {
  local agent="$1"
  local f="$GOTCHAS_DIR/${agent}.md"
  [ -f "$f" ] && { echo "$f"; return; }
  # 접두 일치 (예: current_agent=generator → generator-backend/frontend 중 하나)
  for cand in "$GOTCHAS_DIR"/*.md; do
    [ -e "$cand" ] || continue
    local base
    base=$(basename "$cand" .md)
    [ "$base" = "README" ] && continue
    case "$base" in
      "$agent"*|*"$agent"*) echo "$cand"; return ;;
    esac
  done
  echo ""
}

render_gotcha_entry() {
  local f="$1" active="$2"
  local name count
  name=$(basename "$f" .md)
  count=$(count_items "$f")
  if [ "$active" = "true" ]; then
    echo -e "${BOLD}${BG_YELLOW} ▸ ${name} ${RESET} ${DIM}(${count} items · ACTIVE)${RESET}"
  else
    echo -e "${BOLD}${GREEN}▸ ${name}${RESET} ${DIM}(${count} items)${RESET}"
  fi
  if [ "$count" -eq 0 ]; then
    echo -e "  ${DIM}(항목 없음)${RESET}"
  else
    recent_titles "$f" "$RECENT_N" | while IFS= read -r t; do
      echo -e "  ${DIM}·${RESET} $t"
    done
  fi
}

render_memory_summary() {
  if [ ! -f "$MEMORY_FILE" ]; then
    echo -e "${DIM}(memory.md 없음)${RESET}"
    return
  fi
  local count
  count=$(grep -c '^### ' "$MEMORY_FILE" 2>/dev/null)
  count="${count:-0}"
  echo -e "${BOLD}${CYAN}▣ SHARED MEMORY${RESET} ${DIM}(${count} items · memory.md)${RESET}"
  if [ "$count" -eq 0 ]; then
    echo -e "  ${DIM}(항목 없음)${RESET}"
  else
    grep '^### ' "$MEMORY_FILE" | tail -n "$RECENT_N" | sed 's/^### //' | while IFS= read -r t; do
      echo -e "  ${DIM}·${RESET} $t"
    done
  fi
}

render() {
  clear
  local cols hr
  cols=$(tput cols 2>/dev/null || echo 80)
  hr=$(printf '─%.0s' $(seq 1 "$cols"))

  local active active_file
  active=$(get_active_agent)
  active_file=""
  [ -n "$active" ] && active_file=$(file_for_agent "$active")

  echo -e "${BOLD}${MAGENTA}GOTCHA INDEX${RESET}  ${DIM}$(date +%H:%M:%S) · recent=${RECENT_N} · refresh ${REFRESH_SEC}s${RESET}"
  if [ -n "$active" ]; then
    echo -e "${DIM}active agent:${RESET} ${BOLD}${YELLOW}${active}${RESET}"
  else
    echo -e "${DIM}active agent: (none)${RESET}"
  fi
  echo -e "${DIM}${hr}${RESET}"

  # 활성 에이전트 gotcha 최상단
  if [ -n "$active_file" ]; then
    render_gotcha_entry "$active_file" "true"
    echo ""
  fi

  # 나머지 gotcha
  if [ -d "$GOTCHAS_DIR" ]; then
    for f in "$GOTCHAS_DIR"/*.md; do
      [ -e "$f" ] || continue
      [ "$f" = "$active_file" ] && continue
      local base
      base=$(basename "$f" .md)
      [ "$base" = "README" ] && continue
      render_gotcha_entry "$f" "false"
    done
  fi

  echo ""
  echo -e "${DIM}${hr}${RESET}"
  render_memory_summary
}

trap 'exit 0' INT TERM

while true; do
  render
  sleep "$REFRESH_SEC"
done
