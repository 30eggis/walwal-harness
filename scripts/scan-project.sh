#!/bin/bash
# scan-project.sh — 기존 프로젝트 구조를 분석하여 하네스 초기화 정보를 생성
# 출력: .harness/actions/scan-result.json
set -e

PROJECT_ROOT="${1:-.}"
OUTPUT="${PROJECT_ROOT}/.harness/actions/scan-result.json"

mkdir -p "$(dirname "$OUTPUT")"

echo "=== Scanning project: ${PROJECT_ROOT} ==="

# ─────────────────────────────────────────
# 1. 기존 AGENTS.md / CLAUDE.md 감지
# ─────────────────────────────────────────
AGENTS_MD="none"
CLAUDE_MD="none"
CLAUDE_MD_IS_SYMLINK=false
EXISTING_RULES=""

if [ -f "${PROJECT_ROOT}/AGENTS.md" ]; then
  AGENTS_MD="exists"
fi

if [ -L "${PROJECT_ROOT}/CLAUDE.md" ]; then
  CLAUDE_MD="symlink"
  CLAUDE_MD_IS_SYMLINK=true
elif [ -f "${PROJECT_ROOT}/CLAUDE.md" ]; then
  CLAUDE_MD="exists"
  # 기존 CLAUDE.md 내용 보존용 추출
  EXISTING_RULES=$(cat "${PROJECT_ROOT}/CLAUDE.md")
fi

# ─────────────────────────────────────────
# 2. Tech Stack 감지
# ─────────────────────────────────────────
TECH_BACKEND="unknown"
TECH_FRONTEND="unknown"
TECH_DB="unknown"
TECH_MONOREPO="none"
TECH_LANG="unknown"

# Backend
if [ -f "${PROJECT_ROOT}/nest-cli.json" ]; then
  TECH_BACKEND="nestjs"
  TECH_LANG="typescript"
elif [ -f "${PROJECT_ROOT}/requirements.txt" ] || [ -f "${PROJECT_ROOT}/pyproject.toml" ]; then
  TECH_BACKEND="python"
  TECH_LANG="python"
  if grep -q "fastapi" "${PROJECT_ROOT}/requirements.txt" 2>/dev/null || grep -q "fastapi" "${PROJECT_ROOT}/pyproject.toml" 2>/dev/null; then
    TECH_BACKEND="fastapi"
  elif grep -q "django" "${PROJECT_ROOT}/requirements.txt" 2>/dev/null || grep -q "django" "${PROJECT_ROOT}/pyproject.toml" 2>/dev/null; then
    TECH_BACKEND="django"
  fi
elif [ -f "${PROJECT_ROOT}/go.mod" ]; then
  TECH_BACKEND="go"
  TECH_LANG="go"
elif [ -f "${PROJECT_ROOT}/pom.xml" ] || [ -f "${PROJECT_ROOT}/build.gradle" ]; then
  TECH_BACKEND="java"
  TECH_LANG="java"
fi

# Frontend
if [ -f "${PROJECT_ROOT}/next.config.js" ] || [ -f "${PROJECT_ROOT}/next.config.ts" ] || [ -f "${PROJECT_ROOT}/next.config.mjs" ]; then
  TECH_FRONTEND="nextjs"
elif [ -f "${PROJECT_ROOT}/vite.config.ts" ] || [ -f "${PROJECT_ROOT}/vite.config.js" ]; then
  TECH_FRONTEND="vite-react"
elif [ -f "${PROJECT_ROOT}/angular.json" ]; then
  TECH_FRONTEND="angular"
elif [ -f "${PROJECT_ROOT}/nuxt.config.ts" ]; then
  TECH_FRONTEND="nuxt"
fi

# Monorepo 내 Frontend 감지
if [ -d "${PROJECT_ROOT}/apps/web" ]; then
  if [ -f "${PROJECT_ROOT}/apps/web/next.config.js" ] || [ -f "${PROJECT_ROOT}/apps/web/next.config.ts" ]; then
    TECH_FRONTEND="nextjs"
  elif [ -f "${PROJECT_ROOT}/apps/web/vite.config.ts" ]; then
    TECH_FRONTEND="vite-react"
  fi
fi

# Database
if grep -rq "typeorm\|prisma\|sequelize\|knex" "${PROJECT_ROOT}/package.json" 2>/dev/null; then
  if grep -q "pg\|postgres" "${PROJECT_ROOT}/package.json" 2>/dev/null; then
    TECH_DB="postgresql"
  elif grep -q "mysql" "${PROJECT_ROOT}/package.json" 2>/dev/null; then
    TECH_DB="mysql"
  elif grep -q "sqlite" "${PROJECT_ROOT}/package.json" 2>/dev/null; then
    TECH_DB="sqlite"
  else
    TECH_DB="orm-detected"
  fi
elif grep -rq "mongoose\|mongodb" "${PROJECT_ROOT}/package.json" 2>/dev/null; then
  TECH_DB="mongodb"
fi

# Monorepo
if [ -f "${PROJECT_ROOT}/turbo.json" ]; then
  TECH_MONOREPO="turborepo"
elif [ -f "${PROJECT_ROOT}/nx.json" ]; then
  TECH_MONOREPO="nx"
elif [ -f "${PROJECT_ROOT}/lerna.json" ]; then
  TECH_MONOREPO="lerna"
elif [ -f "${PROJECT_ROOT}/pnpm-workspace.yaml" ]; then
  TECH_MONOREPO="pnpm-workspace"
elif [ -f "${PROJECT_ROOT}/nest-cli.json" ] && grep -q '"monorepo": true' "${PROJECT_ROOT}/nest-cli.json" 2>/dev/null; then
  TECH_MONOREPO="nestjs-monorepo"
fi

# ─────────────────────────────────────────
# 3. 디렉토리 트리 스캔 (2 depth)
# ─────────────────────────────────────────
TREE=$(find "${PROJECT_ROOT}" -maxdepth 3 -type d \
  ! -path "*/node_modules/*" \
  ! -path "*/.git/*" \
  ! -path "*/.next/*" \
  ! -path "*/dist/*" \
  ! -path "*/__pycache__/*" \
  ! -path "*/.harness/archive/*" \
  ! -name "node_modules" \
  ! -name ".git" \
  ! -name ".next" \
  ! -name "dist" \
  2>/dev/null | sort | sed "s|${PROJECT_ROOT}/||g" | sed '/^$/d')

# ─────────────────────────────────────────
# 4. 주요 설정 파일 목록
# ─────────────────────────────────────────
CONFIG_FILES=""
for f in package.json tsconfig.json nest-cli.json next.config.js next.config.ts \
         vite.config.ts docker-compose.yml docker-compose.yaml Dockerfile \
         .env .env.example turbo.json nx.json pyproject.toml requirements.txt \
         go.mod pom.xml build.gradle Makefile; do
  if [ -f "${PROJECT_ROOT}/${f}" ]; then
    CONFIG_FILES="${CONFIG_FILES}\"${f}\","
  fi
done
CONFIG_FILES="[${CONFIG_FILES%,}]"

# ─────────────────────────────────────────
# 5. OpenAPI / Swagger 감지
# ─────────────────────────────────────────
OPENAPI="none"
for f in openapi.json openapi.yaml swagger.json swagger.yaml api-spec.json api-spec.yaml; do
  if [ -f "${PROJECT_ROOT}/${f}" ] || [ -f "${PROJECT_ROOT}/docs/${f}" ]; then
    OPENAPI="${f}"
    break
  fi
done

# NestJS Swagger 모듈 감지
if grep -rq "@nestjs/swagger" "${PROJECT_ROOT}/package.json" 2>/dev/null; then
  if [ "$OPENAPI" = "none" ]; then
    OPENAPI="nestjs-swagger-module (runtime-generated)"
  fi
fi

# ─────────────────────────────────────────
# 6. Git 정보
# ─────────────────────────────────────────
GIT_INIT=false
GIT_COMMITS=0
GIT_BRANCH="none"
if [ -d "${PROJECT_ROOT}/.git" ]; then
  GIT_INIT=true
  GIT_COMMITS=$(git -C "${PROJECT_ROOT}" rev-list --count HEAD 2>/dev/null || echo 0)
  GIT_BRANCH=$(git -C "${PROJECT_ROOT}" branch --show-current 2>/dev/null || echo "unknown")
fi

# ─────────────────────────────────────────
# 7. 하네스 기존 상태
# ─────────────────────────────────────────
HARNESS_EXISTS=false
HARNESS_VERSION="none"
if [ -f "${PROJECT_ROOT}/.harness/config.json" ]; then
  HARNESS_EXISTS=true
  HARNESS_VERSION=$(grep '"version"' "${PROJECT_ROOT}/.harness/config.json" 2>/dev/null | head -1 | sed 's/.*: *"\(.*\)".*/\1/')
fi

# ─────────────────────────────────────────
# 8. JSON 출력
# ─────────────────────────────────────────

# 디렉토리 트리를 JSON 배열로 변환
TREE_JSON=$(echo "$TREE" | awk 'BEGIN{printf "["} NR>1{printf ","} {printf "\"%s\"", $0} END{printf "]"}')

# 기존 CLAUDE.md 내용 (JSON escape)
EXISTING_RULES_JSON=$(echo "$EXISTING_RULES" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')

cat > "$OUTPUT" << JSONEOF
{
  "scanned_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "project_root": "${PROJECT_ROOT}",

  "existing_docs": {
    "agents_md": "${AGENTS_MD}",
    "claude_md": "${CLAUDE_MD}",
    "claude_md_is_symlink": ${CLAUDE_MD_IS_SYMLINK},
    "existing_claude_md_content": ${EXISTING_RULES_JSON}
  },

  "tech_stack": {
    "backend": "${TECH_BACKEND}",
    "frontend": "${TECH_FRONTEND}",
    "database": "${TECH_DB}",
    "monorepo": "${TECH_MONOREPO}",
    "language": "${TECH_LANG}"
  },

  "structure": {
    "directories": ${TREE_JSON},
    "config_files": ${CONFIG_FILES}
  },

  "api": {
    "openapi_spec": "${OPENAPI}"
  },

  "git": {
    "initialized": ${GIT_INIT},
    "commits": ${GIT_COMMITS},
    "branch": "${GIT_BRANCH}"
  },

  "harness": {
    "exists": ${HARNESS_EXISTS},
    "version": "${HARNESS_VERSION}"
  },

  "recommendation": {
    "project_type": "$(
      if [ "$TECH_BACKEND" != "unknown" ] && [ "$TECH_FRONTEND" != "unknown" ]; then
        echo "fullstack"
      elif [ "$TECH_BACKEND" != "unknown" ]; then
        echo "backend-only"
      elif [ "$TECH_FRONTEND" != "unknown" ]; then
        echo "frontend-only"
      else
        echo "empty"
      fi
    )",
    "agents_md_action": "$(
      if [ "$AGENTS_MD" = "none" ] && [ "$CLAUDE_MD" = "none" ]; then
        echo "create-new"
      elif [ "$AGENTS_MD" = "none" ] && [ "$CLAUDE_MD" = "exists" ]; then
        echo "migrate-claude-to-agents"
      elif [ "$AGENTS_MD" = "exists" ]; then
        echo "rebuild-with-harness"
      else
        echo "create-new"
      fi
    )"
  }
}
JSONEOF

echo ""
echo "=== Scan Complete ==="
echo "Output: ${OUTPUT}"
echo ""
echo "--- Summary ---"
echo "Tech Stack: ${TECH_BACKEND} / ${TECH_FRONTEND} / ${TECH_DB}"
echo "Monorepo: ${TECH_MONOREPO}"
echo "OpenAPI: ${OPENAPI}"
echo "Git: ${GIT_INIT} (${GIT_COMMITS} commits, branch: ${GIT_BRANCH})"
echo "Existing Docs: AGENTS.md=${AGENTS_MD}, CLAUDE.md=${CLAUDE_MD}"
echo "Harness: ${HARNESS_EXISTS} (v${HARNESS_VERSION})"
echo "Recommendation: $(cat "$OUTPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(f\"type={d['recommendation']['project_type']}, agents_md={d['recommendation']['agents_md_action']}\")" 2>/dev/null)"
