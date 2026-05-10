#!/bin/bash
# harness-wake-install.sh — launchd hourly wake 설치/관리
#
# 사용법:
#   bash scripts/harness-wake-install.sh install [project-root...]
#   bash scripts/harness-wake-install.sh add <project-root>
#   bash scripts/harness-wake-install.sh remove <project-root>
#   bash scripts/harness-wake-install.sh list
#   bash scripts/harness-wake-install.sh status
#   bash scripts/harness-wake-install.sh uninstall
#
# install: 등록된 프로젝트를 합치고 launchd job 을 (재)로드. 추가 인자가 있으면 그 경로들을 새로 추가.
# add/remove: ~/.walwal-harness/projects.list 만 수정.
# list: 현재 등록 목록 출력.
# status: launchd 상태 확인.
# uninstall: plist 언로드 + 제거.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WAKE_SH="$SCRIPT_DIR/harness-wake.sh"
HARNESS_DIR="$HOME/.walwal-harness"
PROJECTS_LIST="$HARNESS_DIR/projects.list"
LOG_DIR="$HARNESS_DIR/logs"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
PLIST_NAME="com.walwal.harness-wake"
PLIST_PATH="$LAUNCH_AGENTS_DIR/$PLIST_NAME.plist"

# 템플릿 위치 후보 — walwal-harness 패키지 안일 수도, 프로젝트 안일 수도.
detect_template() {
  local candidates=(
    "$SCRIPT_DIR/../assets/launchd/com.walwal.harness-wake.plist.template"
    "$HOME/project/walwal-harness/assets/launchd/com.walwal.harness-wake.plist.template"
  )
  for c in "${candidates[@]}"; do
    [ -f "$c" ] && { echo "$c"; return 0; }
  done
  return 1
}

ensure_dirs() {
  mkdir -p "$HARNESS_DIR" "$LOG_DIR" "$LAUNCH_AGENTS_DIR"
  touch "$PROJECTS_LIST"
}

abs_path() {
  local p="$1"
  if [ -d "$p" ]; then
    (cd "$p" && pwd)
  else
    echo "$p"
  fi
}

cmd_add() {
  ensure_dirs
  local project
  project=$(abs_path "$1")
  if grep -Fxq "$project" "$PROJECTS_LIST" 2>/dev/null; then
    echo "[wake] already registered: $project"
    return 0
  fi
  echo "$project" >> "$PROJECTS_LIST"
  echo "[wake] added: $project"
}

cmd_remove() {
  ensure_dirs
  local project
  project=$(abs_path "$1")
  if ! grep -Fxq "$project" "$PROJECTS_LIST" 2>/dev/null; then
    echo "[wake] not registered: $project"
    return 0
  fi
  local tmp
  tmp=$(mktemp)
  grep -Fxv "$project" "$PROJECTS_LIST" > "$tmp" || true
  mv "$tmp" "$PROJECTS_LIST"
  echo "[wake] removed: $project"
}

cmd_list() {
  ensure_dirs
  if [ ! -s "$PROJECTS_LIST" ]; then
    echo "(empty)"
    return 0
  fi
  cat "$PROJECTS_LIST"
}

cmd_status() {
  if [ -f "$PLIST_PATH" ]; then
    echo "[wake] plist: $PLIST_PATH (exists)"
  else
    echo "[wake] plist: $PLIST_PATH (NOT installed)"
  fi
  if launchctl list 2>/dev/null | grep -q "$PLIST_NAME"; then
    echo "[wake] launchd: loaded"
    launchctl list | awk -v n="$PLIST_NAME" '$3==n {print "        pid="$1" exit="$2" label="$3}'
  else
    echo "[wake] launchd: NOT loaded"
  fi
  echo "[wake] projects:"
  cmd_list | sed 's/^/        /'
}

cmd_install() {
  ensure_dirs

  # 추가 인자가 있으면 add
  shift_count=0
  for p in "$@"; do
    cmd_add "$p"
  done

  local template
  template=$(detect_template) || {
    echo "[wake] ERROR: plist template not found" >&2
    return 1
  }

  # plist 생성
  sed \
    -e "s|{{WAKE_SCRIPT}}|$WAKE_SH|g" \
    -e "s|{{LOG_DIR}}|$LOG_DIR|g" \
    -e "s|{{HOME}}|$HOME|g" \
    "$template" > "$PLIST_PATH"

  # 기존 jobs 언로드 (idempotent)
  launchctl unload "$PLIST_PATH" 2>/dev/null || true

  # 로드
  if launchctl load "$PLIST_PATH" 2>/dev/null; then
    echo "[wake] launchd loaded: $PLIST_PATH"
  else
    echo "[wake] WARN: launchctl load 실패. 다음 명령으로 직접 시도해 보세요:" >&2
    echo "         launchctl load $PLIST_PATH" >&2
  fi

  cmd_status
}

cmd_uninstall() {
  if [ -f "$PLIST_PATH" ]; then
    launchctl unload "$PLIST_PATH" 2>/dev/null || true
    rm -f "$PLIST_PATH"
    echo "[wake] uninstalled: $PLIST_PATH"
  else
    echo "[wake] not installed"
  fi
}

cmd_run_now() {
  bash "$WAKE_SH"
  echo "[wake] run-now done. log:"
  tail -20 "$LOG_DIR/wake.log" 2>/dev/null || true
}

case "${1:-}" in
  install)   shift; cmd_install "$@" ;;
  add)       shift; cmd_add "${1:-$PWD}" ;;
  remove)    shift; cmd_remove "${1:-$PWD}" ;;
  list)      cmd_list ;;
  status)    cmd_status ;;
  uninstall) cmd_uninstall ;;
  run-now)   cmd_run_now ;;
  *)
    cat <<USAGE
harness-wake-install.sh — launchd hourly wake 관리

  install [project-root...]   plist 생성 + 로드 (+ 프로젝트 등록)
  add <project-root>          프로젝트 등록만
  remove <project-root>       프로젝트 등록 해제
  list                        등록된 프로젝트 출력
  status                      launchd / plist / 등록 상태
  run-now                     지금 즉시 wake 실행 (테스트)
  uninstall                   plist 언로드 + 제거
USAGE
    ;;
esac
