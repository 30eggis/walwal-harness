#!/bin/bash
# init-agents-md.sh — scan-result.json을 기반으로 AGENTS.md를 생성/리빌드
# 기존 CLAUDE.md의 사용자 규칙을 보존하면서 하네스 포맷으로 변환
set -e

PROJECT_ROOT="${1:-.}"
SCAN_RESULT="${PROJECT_ROOT}/.harness/actions/scan-result.json"
export SCAN_RESULT PROJECT_ROOT
AGENTS_FILE="${PROJECT_ROOT}/AGENTS.md"
CLAUDE_FILE="${PROJECT_ROOT}/CLAUDE.md"
BACKUP_DIR="${PROJECT_ROOT}/.harness/archive/pre-harness-backup"

if [ ! -f "$SCAN_RESULT" ]; then
  echo "ERROR: scan-result.json not found. Run scan-project.sh first."
  exit 1
fi

# ─────────────────────────────────────────
# 1. Python으로 scan-result.json 파싱
# ─────────────────────────────────────────
eval "$(python3 << 'PYEOF'
import json, sys, os

with open(os.environ.get("SCAN_RESULT", ".harness/actions/scan-result.json")) as f:
    scan = json.load(f)

docs = scan["existing_docs"]
tech = scan["tech_stack"]
rec = scan["recommendation"]
dirs = scan["structure"]["directories"]
configs = scan["structure"]["config_files"]

print(f'ACTION="{rec["agents_md_action"]}"')
print(f'PROJECT_TYPE="{rec["project_type"]}"')
print(f'TECH_BE="{tech["backend"]}"')
print(f'TECH_FE="{tech["frontend"]}"')
print(f'TECH_DB="{tech["database"]}"')
print(f'TECH_MONO="{tech["monorepo"]}"')
print(f'OPENAPI="{scan["api"]["openapi_spec"]}"')
print(f'HAS_EXISTING_CLAUDE="{docs["claude_md"]}"')
print(f'EXISTING_CONTENT={json.dumps(docs["existing_claude_md_content"])}')
PYEOF
)"

echo "=== AGENTS.md Initialization ==="
echo "Action: ${ACTION}"
echo "Project Type: ${PROJECT_TYPE}"
echo ""

# ─────────────────────────────────────────
# 2. 기존 문서 백업
# ─────────────────────────────────────────
if [ "$ACTION" = "migrate-claude-to-agents" ] || [ "$ACTION" = "rebuild-with-harness" ]; then
  mkdir -p "$BACKUP_DIR"
  TIMESTAMP=$(date +%Y%m%d_%H%M%S)

  if [ -f "$AGENTS_FILE" ] && [ ! -L "$AGENTS_FILE" ]; then
    cp "$AGENTS_FILE" "${BACKUP_DIR}/AGENTS.md.${TIMESTAMP}.bak"
    echo "Backed up: AGENTS.md → ${BACKUP_DIR}/AGENTS.md.${TIMESTAMP}.bak"
  fi

  if [ -f "$CLAUDE_FILE" ] && [ ! -L "$CLAUDE_FILE" ]; then
    cp "$CLAUDE_FILE" "${BACKUP_DIR}/CLAUDE.md.${TIMESTAMP}.bak"
    echo "Backed up: CLAUDE.md → ${BACKUP_DIR}/CLAUDE.md.${TIMESTAMP}.bak"
  fi
fi

# ─────────────────────────────────────────
# 3. IA-MAP 자동 생성
# ─────────────────────────────────────────
generate_ia_map() {
  python3 << 'PYEOF'
import json, os

with open(os.environ.get("SCAN_RESULT", ".harness/actions/scan-result.json")) as f:
    scan = json.load(f)

dirs = scan["structure"]["directories"]
tech = scan["tech_stack"]

# 경로별 태그/설명 추론 규칙
tag_rules = {
    # Backend patterns
    "apps/gateway": ("[BE]", "API Gateway", "Generator-Backend"),
    "apps/service": ("[BE]", "Microservice", "Generator-Backend"),
    "src/controllers": ("[BE]", "API Controllers", "Generator-Backend"),
    "src/services": ("[BE]", "Business Logic", "Generator-Backend"),
    "src/models": ("[BE]", "Data Models", "Generator-Backend"),
    "src/entities": ("[BE]", "DB Entities", "Generator-Backend"),
    "src/modules": ("[BE]", "NestJS Modules", "Generator-Backend"),
    "src/guards": ("[BE]", "Auth Guards", "Generator-Backend"),
    "src/pipes": ("[BE]", "Validation Pipes", "Generator-Backend"),
    "src/interceptors": ("[BE]", "Interceptors", "Generator-Backend"),
    "src/filters": ("[BE]", "Exception Filters", "Generator-Backend"),
    "routers": ("[BE]", "API Routers", "Generator-Backend"),
    "routes": ("[BE]", "API Routes", "Generator-Backend"),
    "middleware": ("[BE]", "Middleware", "Generator-Backend"),
    "migrations": ("[BE]", "DB Migrations", "Generator-Backend"),

    # Frontend patterns
    "apps/web": ("[FE]", "Frontend App", "Generator-Frontend"),
    "src/components": ("[FE]", "UI Components", "Generator-Frontend"),
    "src/pages": ("[FE]", "Page Routes", "Generator-Frontend"),
    "src/app": ("[FE]", "App Router", "Generator-Frontend"),
    "src/hooks": ("[FE]", "Custom Hooks", "Generator-Frontend"),
    "src/stores": ("[FE]", "State Management", "Generator-Frontend"),
    "src/styles": ("[FE]", "Stylesheets", "Generator-Frontend"),
    "src/api": ("[FE]", "API Client Layer", "Generator-Frontend"),
    "src/lib": ("[FE]", "Utility Library", "Generator-Frontend"),
    "public": ("[FE]", "Static Assets", "Generator-Frontend"),

    # Shared / Libs
    "libs/shared": ("[BE]", "Shared Libraries", "Generator-Backend"),
    "libs/database": ("[BE]", "Database Module", "Generator-Backend"),
    "libs/common": ("[BE]", "Common Utilities", "Generator-Backend"),

    # Infra
    "docker": ("[INFRA]", "Docker Configuration", "Planner"),
    ".github": ("[INFRA]", "CI/CD Workflows", "Planner"),
    "deploy": ("[INFRA]", "Deployment Scripts", "Planner"),
    "terraform": ("[INFRA]", "Infrastructure as Code", "Planner"),
    "k8s": ("[INFRA]", "Kubernetes Manifests", "Planner"),

    # Harness
    ".harness": ("[HARNESS]", "Harness System", "Planner"),

    # Tests
    "test": ("[TEST]", "Test Suite", "Evaluator"),
    "tests": ("[TEST]", "Test Suite", "Evaluator"),
    "e2e": ("[TEST]", "E2E Tests", "Evaluator"),
    "__tests__": ("[TEST]", "Unit Tests", "Evaluator"),

    # Native app patterns (Swift / Kotlin / Rust 등)
    "Sources": ("[FE]", "Native Source Root", "Generator-Frontend"),
    "Tests": ("[TEST]", "Native Test Suite", "Evaluator"),
    "Resources": ("[FE]", "Native Resources", "Generator-Frontend"),
    "android": ("[FE]", "Android Host", "Generator-Frontend"),
    "ios": ("[FE]", "iOS Host", "Generator-Frontend"),
    "macos": ("[FE]", "macOS Host", "Generator-Frontend"),
    "Shared": ("[FE]", "Cross-platform Shared", "Generator-Frontend"),
}

# 디렉토리를 분석
ia_lines = []
for d in sorted(dirs):
    if d == "." or not d:
        continue

    matched = False
    for pattern, (tag, desc, owner) in tag_rules.items():
        if pattern in d:
            depth = d.count("/")
            indent = "│   " * depth
            name = d.split("/")[-1] + "/"
            ia_lines.append(f"{indent}├── {name:<25} # {tag} {desc:<30} → {owner}")
            matched = True
            break

    if not matched:
        depth = d.count("/")
        if depth <= 1:  # 1depth만 미분류 표시
            indent = "│   " * depth
            name = d.split("/")[-1] + "/"
            ia_lines.append(f"{indent}├── {name:<25} # [?] (Planner가 분류 필요)       → TBD")

for line in ia_lines:
    print(line)
PYEOF
}

IA_MAP=$(generate_ia_map)

# ─────────────────────────────────────────
# 4. 기존 사용자 규칙 추출 (CLAUDE.md에서)
# ─────────────────────────────────────────
extract_user_rules() {
  if [ "$HAS_EXISTING_CLAUDE" = "exists" ]; then
    python3 << 'PYEOF'
import json, os

with open(os.environ.get("SCAN_RESULT", ".harness/actions/scan-result.json")) as f:
    scan = json.load(f)

content = scan["existing_docs"]["existing_claude_md_content"]

if not content or content.strip() == "":
    print("(기존 규칙 없음)")
else:
    # 사용자 정의 규칙 영역만 추출 (harness 관련 제외)
    lines = content.split("\n")
    user_section = []
    skip = False
    for line in lines:
        # harness가 생성한 섹션은 제외
        if any(kw in line.lower() for kw in ["ia-map", "ia map", "harness", "## tech stack"]):
            skip = True
        elif line.startswith("## ") and skip:
            skip = False

        if not skip:
            user_section.append(line)

    result = "\n".join(user_section).strip()
    if result:
        print(result)
    else:
        print("(기존 규칙 없음)")
PYEOF
  else
    echo "(기존 규칙 없음)"
  fi
}

USER_RULES=$(extract_user_rules)

# ─────────────────────────────────────────
# 5. AGENTS.md 생성
# ─────────────────────────────────────────
cat > "$AGENTS_FILE" << AGENTSEOF
# AGENTS.md — Project Context for AI Agents

> 이 파일은 모든 AI 에이전트(Claude, Cursor, Copilot, Windsurf 등)의 공통 진입점입니다.
> CLAUDE.md는 이 파일의 심볼릭 링크입니다.
> Generated by walwal-harness ($(date +%Y-%m-%d))

## Project

- **Name**: (Planner가 설정)
- **Description**: (Planner가 설정)
- **Phase**: INIT
- **Type**: ${PROJECT_TYPE}
- **Harness**: \`.harness/HARNESS.md\` 참조

## Tech Stack (Auto-detected)

- Backend: ${TECH_BE}
- Frontend: ${TECH_FE}
- Database: ${TECH_DB}
- Monorepo: ${TECH_MONO}
- OpenAPI: ${OPENAPI}

## IA-MAP (Information Architecture)

> 자동 스캔으로 생성됨. Planner가 검토 후 확정해야 합니다.
> \`[?]\` 태그는 Planner가 분류해야 하는 미확인 경로입니다.

\`\`\`
/
${IA_MAP}
├── AGENTS.md                 # [META] 프로젝트 컨텍스트           → Planner
├── CLAUDE.md                 # [META] → AGENTS.md 심볼릭 링크
└── .harness/                 # [HARNESS] 하네스 시스템             → Planner
\`\`\`

### IA-MAP 범례

| 태그 | 의미 | 소유 에이전트 |
|------|------|--------------|
| \`[BE]\` | Backend 영역 | Generator-Backend |
| \`[FE]\` | Frontend 영역 | Generator-Frontend |
| \`[HARNESS]\` | 하네스 시스템 | Planner / Evaluator |
| \`[META]\` | 프로젝트 메타 문서 | Planner |
| \`[INFRA]\` | 인프라/배포 설정 | Planner |
| \`[TEST]\` | 테스트 코드 | Evaluator / Generator |
| \`[?]\` | 미분류 (Planner 확인 필요) | TBD |

## Preserved Rules (기존 프로젝트에서 이관)

${USER_RULES}

## Rules (모든 에이전트 공통)

### 읽기/쓰기 권한

| 파일 | 읽기 | 쓰기 |
|------|------|------|
| AGENTS.md | 전체 | Planner만 |
| .harness/actions/api-contract.json | 전체 | Planner만 |
| .harness/actions/feature-list.json | 전체 | passes: Generator, 나머지: Planner |
| .harness/progress.json | 전체 | 전체 (Session Boundary Protocol에 따라 업데이트) |
| \`[BE]\` 소유 경로 | 전체 | Generator-Backend만 |
| \`[FE]\` 소유 경로 | 전체 | Generator-Frontend만 |
| .harness/archive/ | 전체 | 쓰기 금지 (불변) |

### 변경 요청 프로토콜

AGENTS.md 또는 api-contract.json 변경이 필요할 때:
1. sprint-contract.md에 \`## Change Request\` 섹션 추가
2. Planner가 다음 스프린트 전환 시 반영 여부 결정

### 금지 사항

- AGENTS.md를 Planner 외 에이전트가 수정
- 서비스 간 직접 DB 접근
- 테스트 삭제/약화
- archive/ 내 파일 수정
- 프로젝트를 조기 "완료" 선언

## Harness Quick Reference

| 명령 | 설명 |
|------|------|
| \`bash scripts/scan-project.sh\` | 프로젝트 구조 재스캔 |
| \`.harness/progress.json\` | 현재 진행 상태 (기계 판독) |
| \`.harness/actions/\` | 활성 스프린트 문서 |
| \`.harness/HARNESS.md\` | 하네스 상세 가이드 |
AGENTSEOF

echo ""
echo "=== AGENTS.md Generated ==="
echo "Path: ${AGENTS_FILE}"

# ─────────────────────────────────────────
# 6. CLAUDE.md 심볼릭 링크
# ─────────────────────────────────────────
if [ -f "$CLAUDE_FILE" ] && [ ! -L "$CLAUDE_FILE" ]; then
  echo ""
  echo "WARNING: CLAUDE.md가 일반 파일로 존재합니다."
  echo "기존 내용은 AGENTS.md의 'Preserved Rules' 섹션에 이관되었습니다."
  echo "백업: ${BACKUP_DIR}/"
  rm "$CLAUDE_FILE"
fi

if [ ! -L "$CLAUDE_FILE" ]; then
  ln -sf AGENTS.md "$CLAUDE_FILE"
  echo "Created symlink: CLAUDE.md → AGENTS.md"
else
  echo "Symlink already exists: CLAUDE.md → AGENTS.md"
fi

echo ""
echo "=== Initialization Complete ==="
echo ""
echo "Next steps:"
echo "  1. AGENTS.md의 [?] 태그를 확인하고 Planner에게 분류를 요청하세요"
echo "  2. 'Preserved Rules' 섹션에서 불필요한 규칙을 정리하세요"
echo "  3. '하네스 엔지니어링 시작'으로 Dispatcher를 실행하세요"
