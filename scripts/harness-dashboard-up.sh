#!/usr/bin/env bash
# walwal-harness — Brick Office dashboard launcher
#
# 처음 쓰는 사용자도 한 줄로 대시보드를 띄워볼 수 있게 만든 helper.
# npm 패키지에 포함된 apps/harness-dashboard 를 사용자 프로젝트 외부
# (~/.walwal-harness/dashboard/<project-key>) 에 격리 복사 후 dev 실행한다.
# 구버전 호환을 위해 패키지에 dashboard 가 없으면 git sparse-checkout 으로 fallback 한다.
#
# Usage:
#   bash scripts/harness-dashboard-up.sh                 # install + dev (port 3001)
#   bash scripts/harness-dashboard-up.sh --port 3050     # override port
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
      sed -n '2,16p' "$0"
      exit 0 ;;
    *) echo "[brick-office] unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "${HARNESS_ROOT:-}" ]]; then
  HARNESS_ROOT="$(pwd)"
fi
if [[ ! -d "${HARNESS_ROOT}/.harness" ]]; then
  echo "[brick-office] FAIL: ${HARNESS_ROOT} 에 .harness/ 가 없습니다."
  echo "                먼저 'npx walwal-harness' 로 초기화하세요."
  exit 3
fi

PROJECT_KEY="$(printf '%s' "${HARNESS_ROOT}" | shasum -a 1 | awk '{print substr($1,1,12)}')"
PROJECT_NAME="$(basename "${HARNESS_ROOT}")"
LOCAL_DIR="${HOME}/.walwal-harness/dashboard/${PROJECT_NAME}-${PROJECT_KEY}"
VERSION_FILE="${LOCAL_DIR}/.walwal-dashboard-version"

PACKAGE_ROOT="${HARNESS_ROOT}/node_modules/@walwal-harness/cli"
PACKAGED_DASHBOARD="${PACKAGE_ROOT}/${DASHBOARD_PATH}"
if [[ -f "${PACKAGE_ROOT}/package.json" ]]; then
  PACKAGE_VERSION="$(node -p "require('${PACKAGE_ROOT}/package.json').version" 2>/dev/null || echo unknown)"
fi

if [[ "$REINSTALL" == "true" ]]; then
  rm -rf "$LOCAL_DIR"
fi

echo "[brick-office] HARNESS_ROOT = ${HARNESS_ROOT}"
echo "[brick-office] dashboard 격리 경로 = ${LOCAL_DIR}"

if [[ -d "${PACKAGED_DASHBOARD}" ]]; then
  INSTALLED_VERSION=""
  if [[ -f "${VERSION_FILE}" ]]; then
    INSTALLED_VERSION="$(cat "${VERSION_FILE}" 2>/dev/null || true)"
  fi
  if [[ ! -d "${LOCAL_DIR}/${DASHBOARD_PATH}" || "${INSTALLED_VERSION}" != "${PACKAGE_VERSION}" ]]; then
    echo "[brick-office] dashboard sync from npm package @walwal-harness/cli@${PACKAGE_VERSION}"
    rm -rf "${LOCAL_DIR:?}/${DASHBOARD_PATH}"
    mkdir -p "${LOCAL_DIR}/apps"
    cp -R "${PACKAGED_DASHBOARD}" "${LOCAL_DIR}/apps/"
    printf '%s\n' "${PACKAGE_VERSION}" > "${VERSION_FILE}"
  fi
elif [[ ! -d "${LOCAL_DIR}/${DASHBOARD_PATH}" ]]; then
  echo "[brick-office] 첫 실행 — git sparse-checkout 으로 dashboard 만 가져옵니다 (~5MB)."
  mkdir -p "${LOCAL_DIR}"
  cd "${LOCAL_DIR}"
  git init -q
  git remote add origin "${REPO_URL}" 2>/dev/null || true
  git config core.sparseCheckout true
  echo "${DASHBOARD_PATH}/" > .git/info/sparse-checkout
  git fetch --depth=1 origin main -q
  git checkout main -q
  echo "[brick-office] 다운로드 완료."
fi

cd "${LOCAL_DIR}/${DASHBOARD_PATH}"

if [[ ! -d node_modules ]]; then
  echo "[brick-office] npm install (한 번만 실행, ~30s)..."
  npm install --no-audit --no-fund --loglevel=error
fi

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  Brick Office — http://localhost:${PORT}"
echo "║                                                          ║"
echo "║  HARNESS_ROOT 이 가리키는 프로젝트의 .harness/ 상태를     ║"
echo "║  실시간 (SSE) 시각화합니다. Ctrl+C 로 종료.              ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

HARNESS_ROOT="${HARNESS_ROOT}" npm run dev:dashboard -- -p "${PORT}"
