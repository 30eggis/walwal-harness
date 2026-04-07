#!/bin/bash
# Harness Init Script — NestJS MSA + React/Next.js
# Generator/Evaluator 에이전트가 세션 시작 시 실행

set -e

echo "=== Harness Environment Check ==="
echo "Working Directory: $(pwd)"
echo "Date: $(date)"
echo ""

# Runtime 확인
echo "--- Runtime Versions ---"
command -v node && echo "Node.js: $(node --version)" || echo "Node.js: NOT FOUND (required)"
command -v npm && echo "npm: $(npm --version)" || echo "npm: NOT FOUND (required)"
command -v npx && echo "npx: available" || echo "npx: NOT FOUND"
echo ""

# Git 상태
echo "--- Git Status ---"
if [ -d .git ]; then
  git log --oneline -5 2>/dev/null || echo "No commits yet"
  echo ""
  git status --short
else
  echo "Not a git repository — run: git init"
fi
echo ""

# Harness 상태
echo "--- Harness Status ---"
if [ -f .harness/progress.json ]; then
  # Feature-level 프로그래스 출력
  if [ -f scripts/lib/harness-render-progress.sh ]; then
    source scripts/lib/harness-render-progress.sh
    render_progress "." 2>/dev/null || cat .harness/progress.json
  else
    cat .harness/progress.json
  fi
else
  echo "progress.json not found"
fi
echo ""

# NestJS Monorepo 확인
echo "--- Project Structure ---"
if [ -f nest-cli.json ]; then
  echo "NestJS monorepo detected"
  echo "Apps:"
  ls -d apps/*/ 2>/dev/null || echo "  (no apps yet)"
  echo "Libs:"
  ls -d libs/*/ 2>/dev/null || echo "  (no libs yet)"
elif [ -f package.json ]; then
  echo "package.json found (project not yet scaffolded as NestJS monorepo)"
else
  echo "No project scaffolded yet"
fi
echo ""

# 의존성 확인
echo "--- Dependencies ---"
if [ -f package.json ]; then
  if [ -d node_modules ]; then
    echo "node_modules: installed"
  else
    echo "node_modules: NOT FOUND — run: npm install"
  fi
fi
echo ""

# 서버 기동 (프로젝트가 셋업된 경우)
if [ -f nest-cli.json ] && [ -d node_modules ]; then
  echo "=== Starting Services (Unified Runner) ==="
  npm run dev &
  RUNNER_PID=$!
  echo "Unified Runner PID: $RUNNER_PID"
  echo ""

  # Gateway 헬스체크 (최대 15초 대기)
  echo "--- Waiting for Gateway (localhost:3000) ---"
  for i in $(seq 1 15); do
    if curl -s http://localhost:3000/health > /dev/null 2>&1; then
      echo "Gateway: READY"
      break
    fi
    sleep 1
    if [ $i -eq 15 ]; then
      echo "Gateway: NOT RESPONDING (may need more time)"
    fi
  done

  # Frontend 확인
  if [ -d apps/web ]; then
    echo "--- Frontend ---"
    echo "Frontend dev server should be available at localhost:5173 or localhost:3001"
  fi
fi

echo ""
echo "=== Harness Ready ==="
