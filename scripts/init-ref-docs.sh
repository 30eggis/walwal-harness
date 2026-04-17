#!/bin/bash
# init-ref-docs.sh — 감지된 스택에 따라 .harness/ref/<role>-<stack>.md 를 준비한다.
#
# bash 혼자서는 Claude 의 WebSearch/WebFetch 를 호출할 수 없으므로 이 스크립트는:
#   1. scan-result.json 에서 감지된 스택 목록을 계산
#   2. --placeholder 모드: 최소 frontmatter + TODO 본문을 저장 (AC 검증용 · 파이프라인 unblock 용)
#   3. --claude-prompt 모드: Claude 세션이 실제 WebSearch + WebFetch + synthesis 로 채울 수 있도록 프롬프트 템플릿을 stdout 출력
#   4. --register 모드: Claude 가 실제 본문을 작성한 뒤 호출해 .generated.json 에 sources / generated_at 을 등록
#
# 사용 예:
#   bash scripts/init-ref-docs.sh --dry-run .
#   bash scripts/init-ref-docs.sh --yes --placeholder --stack swift --role fe .
#   bash scripts/init-ref-docs.sh --claude-prompt --stack swift --role fe .
#   bash scripts/init-ref-docs.sh --register --stack swift --role fe --sources "https://a,https://b" .
set -e

# ───── 옵션 파싱 ─────
MODE="interactive"    # interactive | dry-run | placeholder | claude-prompt | register
YES=false
REFRESH=false
STACK=""
ROLE=""
SOURCES=""
PROJECT_ROOT="."

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)        MODE="dry-run"; shift ;;
    --placeholder)    MODE="placeholder"; shift ;;
    --claude-prompt)  MODE="claude-prompt"; shift ;;
    --register)       MODE="register"; shift ;;
    --yes)            YES=true; shift ;;
    --refresh)        REFRESH=true; shift ;;
    --stack)          STACK="$2"; shift 2 ;;
    --role)           ROLE="$2"; shift 2 ;;
    --sources)        SOURCES="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,16p' "$0" | sed 's/^# //; s/^#//'
      exit 0 ;;
    *)                PROJECT_ROOT="$1"; shift ;;
  esac
done

SCAN="${PROJECT_ROOT}/.harness/actions/scan-result.json"
REF_DIR="${PROJECT_ROOT}/.harness/ref"
META="${REF_DIR}/.generated.json"
ARCHIVE_DIR="${PROJECT_ROOT}/.harness/archive"
mkdir -p "$REF_DIR" "$ARCHIVE_DIR"
[ -f "$META" ] || echo "{}" > "$META"

# ───── 감지된 스택 목록 ─────
detect_stacks() {
  if [ ! -f "$SCAN" ]; then
    echo "ERROR: scan-result.json 이 없습니다. 먼저 bash scripts/scan-project.sh ${PROJECT_ROOT} 실행하세요." >&2
    exit 1
  fi
  local fe be native
  fe=$(jq -r '.tech_stack.frontend' "$SCAN")
  be=$(jq -r '.tech_stack.backend' "$SCAN")
  native=$(jq -r '.tech_stack.is_native_app // false' "$SCAN")

  # 네이티브 앱은 fe 만 기록 (be 는 null)
  if [ "$fe" != "unknown" ] && [ "$fe" != "null" ]; then
    echo "fe:$fe"
  fi
  if [ "$native" != "true" ] && [ "$be" != "unknown" ] && [ "$be" != "null" ]; then
    echo "be:$be"
  fi
}

# ───── placeholder 본문 ─────
write_placeholder() {
  local role="$1" stack="$2" path="$3"
  local ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  cat > "$path" <<REF
---
docmeta:
  id: ref-${role}-${stack}
  stack: ${stack}
  role: ${role}
  language: ${stack}
  generated_at: ${ts}
  generator: init-ref-docs.sh (placeholder)
  sources: []
  version: 0
runner:
  dev_command: null
  start_command: null
  install_command: null
paths:
  source_roots: []
  test_roots: []
  config_files: []
api:
  base_url: null
  gateway: null
validation:
  pre_eval_gate: []
  functional_tests: []
  visual:
    enabled: false
    reason: "placeholder — not yet filled by Claude"
    manual_check: "bash init.sh refresh-ref ${role} ${stack} 실행 후 Claude 세션에서 WebSearch + WebFetch 로 채우기"
  anti_pattern_rules: []
---

# Ref — ${stack} (${role})

> **Status**: PLACEHOLDER — Claude 가 WebSearch + WebFetch 로 채워야 함.
> 실행: bash scripts/init-ref-docs.sh --claude-prompt --stack ${stack} --role ${role}

## 1. Runner
TODO

## 2. Paths / Source Layout
TODO

## 3. Best Practices
TODO

## 4. Anti-Patterns (→ gotchas 시드 후보)
TODO
REF
}

# ───── Claude 용 프롬프트 ─────
# React 계열 스택 (react / nextjs / vite-react) 일 때는
# skills/generator-frontend/references/_web-react-legacy/ 의 4개 문서를
# 로컬 seed 로 프롬프트에 포함시킨다. 이 seed 는 새 ref-docs 작성 시
# "기존 웹 React 가이드" 참조용이며 WebSearch 결과와 병합된다.
LEGACY_SEED_DIR="$(dirname "$0")/../skills/generator-frontend/references/_web-react-legacy"
emit_claude_prompt() {
  local role="$1" stack="$2" path="$3"
  local legacy_hint=""
  if [ "$role" = "fe" ] && [ -d "$LEGACY_SEED_DIR" ]; then
    case "$stack" in
      react|nextjs|vite-react|nuxt|vue|svelte|angular|*web*)
        legacy_hint="
Local seed (병합 대상 · 이미 검증된 웹/React best practice):
$(ls "$LEGACY_SEED_DIR" 2>/dev/null | sed 's|^|  - '"$LEGACY_SEED_DIR"'/|')
"
        ;;
    esac
  fi
  cat <<PROMPT
───────────────────────────────────────────────
Claude 세션에 아래 프롬프트를 전달하세요
(또는 현재 세션이라면 그대로 실행):
───────────────────────────────────────────────

목표: ${path} 를 생성한다.

1. WebSearch 로 다음 쿼리 실행: "${stack} best practices 2025 site:docs.*"
2. 상위 3개 공식 문서 URL 을 WebFetch 로 가져온다.
3. 결과를 종합해 다음 스키마로 YAML frontmatter + 본문을 작성한다:
   - docmeta: { id, stack, role, language, generated_at, generator, sources, version }
   - runner: { dev_command, start_command, install_command }
   - paths: { source_roots, test_roots, config_files }
   - api: { base_url, gateway }
   - validation:
       pre_eval_gate: [...]
       functional_tests: [...]
       visual: { enabled, reason, manual_check }
       anti_pattern_rules: [{ id, pattern_type: "grep"|"lint_tool", pattern|tool+args, paths, severity }]
4. 본문에는 Runner / Paths / Best Practices / Anti-Patterns 섹션 작성.
5. 완료 후: bash scripts/init-ref-docs.sh --register --stack ${stack} --role ${role} --sources "<url1>,<url2>,<url3>" ${PROJECT_ROOT}
${legacy_hint}
───────────────────────────────────────────────
PROMPT
}

# ───── register: 메타 기록 ─────
register_meta() {
  local role="$1" stack="$2" sources_csv="$3"
  local ts key sources_json
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  key="${role}-${stack}"
  sources_json=$(echo "$sources_csv" | awk -F',' 'BEGIN{printf "["} {for(i=1;i<=NF;i++){printf (i>1?",":"") "\"" $i "\""}} END{printf "]"}')
  [ -z "$sources_csv" ] && sources_json="[]"
  jq --arg k "$key" --arg ts "$ts" --argjson s "$sources_json" '.[$k] = {"generated_at": $ts, "sources": $s, "status": "filled"}' "$META" > "${META}.tmp" && mv "${META}.tmp" "$META"
  echo "registered: $key (sources=$(echo "$sources_json" | jq 'length'))"
}

# ───── 한 스택 처리 ─────
process_one() {
  local role="$1" stack="$2"
  local path="${REF_DIR}/${role}-${stack}.md"

  if [ -f "$path" ] && ! $REFRESH; then
    echo "skip: $path 이미 존재 (--refresh 로 강제 재생성)"
    return 0
  fi
  if [ -f "$path" ] && $REFRESH; then
    local backup="${ARCHIVE_DIR}/ref-${role}-${stack}-$(date +%Y%m%d%H%M%S).md"
    cp "$path" "$backup"
    echo "archived: $backup"
  fi

  local answer="y"
  if ! $YES; then
    printf "Generate ref-docs for %s-%s? [y/N] " "$role" "$stack"
    read -r answer </dev/tty || answer="n"
  fi
  case "$answer" in
    y|Y|yes|YES) ;;
    *) echo "skipped: $role-$stack"; return 3 ;;
  esac

  case "$MODE" in
    placeholder)
      write_placeholder "$role" "$stack" "$path"
      local ts; ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
      jq --arg k "${role}-${stack}" --arg ts "$ts" '.[$k] = {"generated_at": $ts, "sources": [], "status": "placeholder"}' "$META" > "${META}.tmp" && mv "${META}.tmp" "$META"
      echo "wrote: $path (placeholder)"
      ;;
    claude-prompt)
      emit_claude_prompt "$role" "$stack" "$path"
      ;;
    *)
      echo "ERROR: interactive 모드는 --placeholder 또는 --claude-prompt 중 하나를 지정하세요." >&2
      return 1
      ;;
  esac
}

# ───── main ─────
case "$MODE" in
  dry-run)
    echo "detected stacks:"
    detect_stacks | sed 's/^/  - /'
    echo ""
    echo "ref files 예상 경로 (미존재 시 생성 대상):"
    while IFS=':' read -r role stack; do
      path="${REF_DIR}/${role}-${stack}.md"
      if [ -f "$path" ]; then
        echo "  [exists] $path"
      else
        echo "  [create] $path"
      fi
    done < <(detect_stacks)
    ;;
  register)
    [ -z "$STACK" ] || [ -z "$ROLE" ] && { echo "ERROR: --register 는 --stack --role --sources 필요" >&2; exit 1; }
    register_meta "$ROLE" "$STACK" "$SOURCES"
    ;;
  placeholder|claude-prompt)
    if [ -n "$STACK" ] && [ -n "$ROLE" ]; then
      process_one "$ROLE" "$STACK"
    else
      # 감지된 전체 스택을 순회
      while IFS=':' read -r role stack; do
        process_one "$role" "$stack"
      done < <(detect_stacks)
    fi
    ;;
  interactive)
    echo "ERROR: 모드 지정 필요 — --dry-run | --placeholder | --claude-prompt | --register" >&2
    echo "자세한 사용법: bash $0 --help" >&2
    exit 1
    ;;
esac
