#!/usr/bin/env bash
# walwal-harness — Brick Office dashboard launcher (shared single-install)
#
# 대시보드 코드는 모든 프로젝트에서 byte 단위로 동일하다 (패키지가 버전 고정으로
# 배포). 프로젝트마다 다른 것은 HARNESS_ROOT(어느 .harness/ 를 볼지)와 PORT 뿐이고,
# HARNESS_ROOT 는 lib/harness-root.ts 가 *런타임*에 읽는다. 따라서 설치본은 하나면
# 충분하다.
#
# 이 런처는 버전별 단일 설치본을 ~/.walwal-harness/dashboard/<version>/ 에 두고
# (npm install + next build 를 버전당 딱 한 번), 각 프로젝트는 HARNESS_ROOT+PORT 만
# 바꿔 `next start` 로 띄운다. next start 는 .next 를 읽기전용으로 쓰므로 같은 폴더에서
# 여러 프로젝트를 동시에 서빙해도 안전하다. 프로젝트가 100개여도 node_modules/.next 는
# 단 1벌(~640MB).
#
# 구버전 호환: 패키지에 dashboard 가 없으면 git sparse-checkout 으로 fallback 한다.
#
# Usage:
#   bash scripts/harness-dashboard-up.sh                 # build(최초 1회) + serve (port 3001)
#   bash scripts/harness-dashboard-up.sh --port 3050     # override port
#   bash scripts/harness-dashboard-up.sh --reinstall     # 공유 설치본 폐기 후 재빌드
#   HARNESS_ROOT=/path/to/project bash ...               # explicit harness root
set -euo pipefail

REPO_URL="${WALWAL_HARNESS_REPO:-https://github.com/30eggis/walwal-harness.git}"
DASHBOARD_PATH="apps/harness-dashboard"
PORT="${PORT:-3001}"
REINSTALL=false
PACKAGE_VERSION="unknown"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --port) PORT="$2"; shift 2 ;;
    --reinstall) REINSTALL=true; shift ;;
    --help|-h)
      sed -n '2,28p' "$0"
      exit 0 ;;
    *) echo "[brick-office] unknown arg: $1" >&2; exit 2 ;;
  esac
done

# --- target project (the one whose .harness/ we visualize) ---
if [[ -z "${HARNESS_ROOT:-}" ]]; then
  HARNESS_ROOT="$(pwd)"
fi
if [[ ! -d "${HARNESS_ROOT}/.harness" ]]; then
  echo "[brick-office] FAIL: ${HARNESS_ROOT} 에 .harness/ 가 없습니다."
  echo "                먼저 'npx walwal-harness' 로 초기화하세요."
  exit 3
fi

# --- locate the packaged dashboard source + its version ---
PACKAGE_ROOT="${HARNESS_ROOT}/node_modules/@walwal-harness/cli"
PACKAGED_DASHBOARD="${PACKAGE_ROOT}/${DASHBOARD_PATH}"
if [[ -f "${PACKAGE_ROOT}/package.json" ]]; then
  PACKAGE_VERSION="$(node -p "require('${PACKAGE_ROOT}/package.json').version" 2>/dev/null || echo unknown)"
fi

# --- shared, version-keyed install (the whole point: one copy for ALL projects) ---
SHARED_BASE="${WALWAL_HARNESS_HOME:-$HOME/.walwal-harness}/dashboard"
VERSION_KEY="${PACKAGE_VERSION}"
[[ "$VERSION_KEY" == "unknown" || -z "$VERSION_KEY" ]] && VERSION_KEY="edge"
SHARED_DIR="${SHARED_BASE}/${VERSION_KEY}"           # node_modules + .next + source live here
READY_MARKER="${SHARED_DIR}/.walwal-dashboard-ready" # written only after a successful build
LOCK_DIR="${SHARED_BASE}/.build-lock-${VERSION_KEY}" # mkdir-based build mutex (atomic)

if [[ "$REINSTALL" == "true" ]]; then
  rm -rf "$SHARED_DIR"
fi

echo "[brick-office] HARNESS_ROOT   = ${HARNESS_ROOT}"
echo "[brick-office] shared install = ${SHARED_DIR}  (version ${VERSION_KEY})"

# Copy the dashboard source into the shared dir. Leaves any existing node_modules
# in place (the package tarball ships no node_modules), so a re-entry after a failed
# build keeps the installed deps.
populate_source() {
  mkdir -p "$SHARED_DIR"
  if [[ -d "${PACKAGED_DASHBOARD}" ]]; then
    cp -R "${PACKAGED_DASHBOARD}/." "${SHARED_DIR}/"
  else
    echo "[brick-office] 패키지에 dashboard 없음 — git sparse-checkout fallback (~5MB)."
    local dl="${SHARED_BASE}/.download-${VERSION_KEY}"
    rm -rf "$dl"; mkdir -p "$dl"
    (
      cd "$dl"
      git init -q
      git remote add origin "${REPO_URL}" 2>/dev/null || true
      git config core.sparseCheckout true
      echo "${DASHBOARD_PATH}/" > .git/info/sparse-checkout
      git fetch --depth=1 origin main -q
      git checkout main -q
    )
    cp -R "${dl}/${DASHBOARD_PATH}/." "${SHARED_DIR}/"
    rm -rf "$dl"
  fi
}

# build = install deps + production build, guarded by a single-writer lock so two
# projects launching at once don't race on the same shared dir. The EXIT trap is a
# safety net: under `set -e` a failed npm install / next build aborts the script, and
# the trap then frees the lock (and leaves no READY_MARKER → next launch rebuilds).
build_shared() {
  local waited=0
  mkdir -p "$SHARED_BASE"   # lock dir is created with plain mkdir, so its parent must exist
  while ! mkdir "$LOCK_DIR" 2>/dev/null; do
    # someone else finished the build while we were waiting → done, nothing to own.
    [[ -f "$READY_MARKER" ]] && return 0
    sleep 1; waited=$((waited + 1))
    if (( waited > 600 )); then
      echo "[brick-office] stale build lock (>10m) — 강제 해제." >&2
      rm -rf "$LOCK_DIR"
    fi
  done
  trap 'rm -rf "$LOCK_DIR"' EXIT

  # double-checked: another waiter may have built it just before we got the lock.
  if [[ -f "$READY_MARKER" && "$(cat "$READY_MARKER" 2>/dev/null || true)" == "$VERSION_KEY" ]]; then
    rm -rf "$LOCK_DIR"; trap - EXIT; return 0
  fi

  [[ -f "${SHARED_DIR}/package.json" ]] || populate_source

  echo "[brick-office] npm install (버전당 1회, ~30s)..."
  ( cd "$SHARED_DIR" && npm install --no-audit --no-fund --loglevel=error )

  echo "[brick-office] next build (버전당 1회)..."
  ( cd "$SHARED_DIR" && ./node_modules/.bin/next build )

  printf '%s\n' "$VERSION_KEY" > "$READY_MARKER"
  echo "[brick-office] 빌드 완료 — 이후 모든 프로젝트가 이 설치본을 공유합니다."
  rm -rf "$LOCK_DIR"; trap - EXIT
}

if [[ ! -f "$READY_MARKER" || "$(cat "$READY_MARKER" 2>/dev/null || true)" != "$VERSION_KEY" ]]; then
  build_shared
fi

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  Brick Office — http://localhost:${PORT}"
echo "║                                                          ║"
echo "║  HARNESS_ROOT 이 가리키는 프로젝트의 .harness/ 상태를     ║"
echo "║  실시간 (SSE) 시각화합니다. Ctrl+C 로 종료.              ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

cd "$SHARED_DIR"
HARNESS_ROOT="${HARNESS_ROOT}" exec ./node_modules/.bin/next start -H 127.0.0.1 -p "${PORT}"
