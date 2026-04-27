#!/bin/bash
# harness-gotcha-register.sh — Evaluator → Gotcha 자동 등록 파이프라인
#
# 사용법:
#   1) 단일 항목 등록 (수동/스크립트):
#      bash harness-gotcha-register.sh <project-root> \
#        --target <agent> \
#        --rule-id <rule-id> \
#        --title "제목" \
#        --wrong "잘못된 행동" \
#        --right "올바른 행동" \
#        --why "근거" \
#        --scope "적용 범위" \
#        --source "evaluator-functional:F-003"
#
#   2) 일괄 등록 (JSON stdin/파일):
#      bash harness-gotcha-register.sh <project-root> --from-json <path>
#      bash harness-gotcha-register.sh <project-root> --scan-evaluations
#        └ .harness/actions/evaluation-*.md 의 ```gotcha_candidates``` 블록 전부 스캔
#
# 동작:
#   - 대상 파일: .harness/gotchas/<target>.md (없으면 생성)
#   - 중복 감지: 동일 rule_id 가 있으면 Occurrences +1, last_seen 갱신 (본문 수정 없음)
#   - 신규: 다음 G-NNN 할당, Status: unverified 로 기록
#   - 등록 성공 로그: .harness/progress.log 에 한 줄 append
#
# 등록 형식:
#   ### [G-NNN] <title>  <!-- rule_id: <rule-id> -->
#   - **Status**: unverified
#   - **Date**: YYYY-MM-DD
#   - **Source**: <source>   (예: "evaluator-functional:F-003")
#   - **Trigger**: Eval 자동 감지
#   - **Wrong**: <wrong>
#   - **Right**: <right>
#   - **Why**: <why>
#   - **Scope**: <scope>
#   - **Occurrences**: 1
#   - **Last-Seen**: YYYY-MM-DD

set -euo pipefail

if [ $# -lt 1 ]; then
  echo "usage: harness-gotcha-register.sh <project-root> [options]" >&2
  exit 1
fi

PROJECT_ROOT="$1"
shift
PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd)"

command -v jq >/dev/null 2>&1 || { echo "[gotcha-register] ERROR: jq required" >&2; exit 1; }

GOTCHAS_DIR="$PROJECT_ROOT/.harness/gotchas"
ACTIONS_DIR="$PROJECT_ROOT/.harness/actions"
mkdir -p "$GOTCHAS_DIR"

TODAY="$(date +%Y-%m-%d)"

# ─────────────────────────────────────────
# 단일 항목을 .harness/gotchas/<target>.md 에 append
#   $1: target agent (generator-backend, generator-frontend, evaluator-functional, ...)
#   $2: rule_id (dedup key)
#   $3: title
#   $4: wrong
#   $5: right
#   $6: why
#   $7: scope
#   $8: source
# ─────────────────────────────────────────
register_one() {
  local target="$1" rule_id="$2" title="$3" wrong="$4" right="$5" why="$6" scope="$7" source="$8"
  local file="$GOTCHAS_DIR/${target}.md"

  # Ensure file exists with header
  if [ ! -f "$file" ]; then
    cat > "$file" <<EOF
# Gotchas — $target

> Dispatcher + Evaluator 가 관리. $target 은 세션 시작 시 이 파일을 읽고 같은 실수를 반복하지 않습니다.
> 신규 항목은 \`Status: unverified\` 로 기록되고, Planner 리뷰 후 \`verified\` 로 승격됩니다.

EOF
  fi

  # Dedup by rule_id marker comment
  if grep -qE "<!-- rule_id: ${rule_id} -->" "$file" 2>/dev/null; then
    # Bump Occurrences + Last-Seen for matching block
    awk -v rid="$rule_id" -v today="$TODAY" '
      BEGIN { in_block = 0 }
      /^### \[G-[0-9]+\].*<!-- rule_id: / {
        in_block = (index($0, "rule_id: " rid " ") > 0 || index($0, "rule_id: " rid "\n") > 0 || $0 ~ ("rule_id: " rid " -->"))
      }
      in_block && /^- \*\*Occurrences\*\*:/ {
        n = $NF + 0
        print "- **Occurrences**: " (n + 1)
        next
      }
      in_block && /^- \*\*Last-Seen\*\*:/ {
        print "- **Last-Seen**: " today
        next
      }
      /^### / && !/<!-- rule_id: / { in_block = 0 }
      { print }
    ' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
    echo "[gotcha-register] $target: dedup $rule_id (occurrence bumped)"
    return 0
  fi

  # Allocate next G-NNN (|| true — pipefail-safe when no existing entries)
  local next_num=""
  next_num=$(grep -oE '^### \[G-[0-9]+\]' "$file" 2>/dev/null | grep -oE '[0-9]+' | sort -n | tail -1 || true)
  next_num=$((${next_num:-0} + 1))
  local g_id
  g_id=$(printf 'G-%03d' "$next_num")

  # Append new block
  {
    echo ""
    echo "### [$g_id] $title  <!-- rule_id: $rule_id -->"
    echo "- **Status**: unverified"
    echo "- **Date**: $TODAY"
    echo "- **Source**: $source"
    echo "- **Trigger**: Eval 자동 감지"
    echo "- **Wrong**: $wrong"
    echo "- **Right**: $right"
    echo "- **Why**: $why"
    echo "- **Scope**: $scope"
    echo "- **Occurrences**: 1"
    echo "- **Last-Seen**: $TODAY"
  } >> "$file"

  echo "[gotcha-register] $target: registered $g_id ($rule_id) — unverified"

  # Log to progress.log if present
  local progress_log="$PROJECT_ROOT/.harness/progress.log"
  if [ -f "$progress_log" ]; then
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [gotcha] $target $g_id unverified — $title (source: $source)" >> "$progress_log"
  fi
}

# ─────────────────────────────────────────
# JSON 배열에서 일괄 등록
#   schema: [{ target, rule_id, title, wrong, right, why, scope, source }]
# ─────────────────────────────────────────
register_from_json() {
  local json="$1"
  local count
  count=$(echo "$json" | jq 'length' 2>/dev/null || echo 0)
  if [ "$count" -eq 0 ]; then
    return 0
  fi

  local i
  for ((i=0; i<count; i++)); do
    local t r ti w ri wh sc so
    t=$(echo "$json"  | jq -r ".[$i].target // empty")
    r=$(echo "$json"  | jq -r ".[$i].rule_id // empty")
    ti=$(echo "$json" | jq -r ".[$i].title // empty")
    w=$(echo "$json"  | jq -r ".[$i].wrong // empty")
    ri=$(echo "$json" | jq -r ".[$i].right // empty")
    wh=$(echo "$json" | jq -r ".[$i].why // empty")
    sc=$(echo "$json" | jq -r ".[$i].scope // \"항상\"")
    so=$(echo "$json" | jq -r ".[$i].source // \"evaluator:auto\"")

    if [ -z "$t" ] || [ -z "$r" ] || [ -z "$ti" ]; then
      echo "[gotcha-register] skip: missing target/rule_id/title at index $i" >&2
      continue
    fi
    register_one "$t" "$r" "$ti" "$w" "$ri" "$wh" "$sc" "$so"
  done
}

# ─────────────────────────────────────────
# Convention 등록 — .harness/conventions/<scope>.md 에 [C-NNN] entry append
#   $1: scope (shared, generator-backend, generator-frontend, ... — 파일명 base)
#   $2: rule_id (dedup key)
#   $3: title
#   $4: rule (긍정 가이드 본문 — "X 는 항상 Y 로")
#   $5: why
#   $6: source
# ─────────────────────────────────────────
CONVENTIONS_DIR="$PROJECT_ROOT/.harness/conventions"
register_convention_one() {
  local scope="$1" rule_id="$2" title="$3" rule="$4" why="$5" source="$6"
  mkdir -p "$CONVENTIONS_DIR"
  local file="$CONVENTIONS_DIR/${scope}.md"

  if [ ! -f "$file" ]; then
    cat > "$file" <<EOF
# Conventions — ${scope}

> Dispatcher가 관리. 긍정 가이드("~를 사용해", "항상 ~") 자동 등록.

EOF
  fi

  # dedup: 같은 rule_id 가 있으면 해당 [C-NNN] 블록의 Occurrences +1, Last-Seen 갱신
  if grep -qE "<!-- rule_id: ${rule_id} -->" "$file" 2>/dev/null; then
    awk -v rid="$rule_id" -v today="$TODAY" '
      BEGIN { in_block = 0 }
      /^### \[C-[0-9]+\].*<!-- rule_id: / {
        in_block = ($0 ~ ("rule_id: " rid " -->"))
      }
      in_block && /^- \*\*Occurrences\*\*:/ {
        n = $NF + 0
        print "- **Occurrences**: " (n + 1)
        next
      }
      in_block && /^- \*\*Last-Seen\*\*:/ {
        print "- **Last-Seen**: " today
        next
      }
      /^### / && !/<!-- rule_id: / { in_block = 0 }
      { print }
    ' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
    echo "[gotcha-register] convention/${scope}: dedup ${rule_id} (occurrence bumped)"
    return 0
  fi

  # 신규 — 다음 [C-NNN] 번호 할당 (set -e 회피: || true)
  local last_n
  last_n=$(grep -oE '\[C-[0-9]+\]' "$file" 2>/dev/null | grep -oE '[0-9]+' | sort -n | tail -1 || true)
  last_n=${last_n:-0}
  local next_n=$(printf "%03d" $((last_n + 1)))

  cat >> "$file" <<EOF

### [C-${next_n}] ${title}  <!-- rule_id: ${rule_id} -->
- **Status**: unverified
- **Date**: ${TODAY}
- **Source**: ${source}
- **Rule**: ${rule}
- **Why**: ${why}
- **Occurrences**: 1
- **Last-Seen**: ${TODAY}
EOF

  echo "[gotcha-register] convention/${scope}: registered C-${next_n} (${rule_id}) — unverified"
}

register_conventions_from_json() {
  local json="$1"
  local count
  count=$(echo "$json" | jq 'length' 2>/dev/null || echo 0)
  [ "$count" -eq 0 ] && return 0
  local i
  for ((i=0; i<count; i++)); do
    local sc r ti ru wh so
    sc=$(echo "$json" | jq -r ".[$i].scope // \"shared\"")
    r=$(echo "$json"  | jq -r ".[$i].rule_id // empty")
    ti=$(echo "$json" | jq -r ".[$i].title // empty")
    ru=$(echo "$json" | jq -r ".[$i].rule // empty")
    wh=$(echo "$json" | jq -r ".[$i].why // empty")
    so=$(echo "$json" | jq -r ".[$i].source // \"agent:auto\"")
    if [ -z "$r" ] || [ -z "$ti" ] || [ -z "$ru" ]; then
      echo "[gotcha-register] convention skip: missing rule_id/title/rule at index $i" >&2
      continue
    fi
    register_convention_one "$sc" "$r" "$ti" "$ru" "$wh" "$so"
  done
}

# ─────────────────────────────────────────
# 단일 파일에서 fenced block 추출 (block_tag 인자로 종류 지정)
#   $1: file path · $2: block tag (gotcha_candidates 또는 convention_candidates)
# stdout 으로 각 block JSON 을 한 줄씩 출력 (\0 구분자)
# ─────────────────────────────────────────
extract_blocks() {
  local file="$1" tag="$2"
  local blocks_prefix
  blocks_prefix=$(mktemp -d)
  awk -v dir="$blocks_prefix" -v tag="$tag" '
    BEGIN { idx=0; flag=0; buf="" }
    $0 ~ ("^```" tag "[[:space:]]*$") { flag=1; buf=""; next }
    /^```[[:space:]]*$/ && flag {
      flag=0
      idx++
      outfile = sprintf("%s/block-%03d.json", dir, idx)
      print buf > outfile
      close(outfile)
      buf=""
      next
    }
    flag { buf = buf $0 "\n" }
  ' "$file"
  echo "$blocks_prefix"
}

process_blocks_in_file() {
  local file="$1"
  # gotcha_candidates
  local g_dir
  g_dir=$(extract_blocks "$file" "gotcha_candidates")
  local b
  for b in "$g_dir"/block-*.json; do
    [ -f "$b" ] || continue
    if jq empty "$b" 2>/dev/null; then
      register_from_json "$(cat "$b")"
    else
      echo "[gotcha-register] skip: invalid gotcha_candidates JSON in $(basename "$file")" >&2
    fi
  done
  rm -rf "$g_dir"

  # convention_candidates
  local c_dir
  c_dir=$(extract_blocks "$file" "convention_candidates")
  for b in "$c_dir"/block-*.json; do
    [ -f "$b" ] || continue
    if jq empty "$b" 2>/dev/null; then
      register_conventions_from_json "$(cat "$b")"
    else
      echo "[gotcha-register] skip: invalid convention_candidates JSON in $(basename "$file")" >&2
    fi
  done
  rm -rf "$c_dir"
}

# ─────────────────────────────────────────
# evaluation-*.md 스캔 — ```gotcha_candidates``` + ```convention_candidates``` 둘 다
# ─────────────────────────────────────────
scan_evaluations() {
  [ -d "$ACTIONS_DIR" ] || return 0
  local f
  for f in "$ACTIONS_DIR"/evaluation-*.md; do
    [ -f "$f" ] || continue
    process_blocks_in_file "$f"
  done
}

# ─────────────────────────────────────────
# 모든 worker report 스캔 — evaluation-*.md + gen-report-*.md + lead-report-*.md
# Generator 는 gen-report-{F-ID}.md 작성, Lead 는 lead-report-{date}.md 작성 가능
# ─────────────────────────────────────────
scan_all() {
  [ -d "$ACTIONS_DIR" ] || return 0
  local f
  for f in "$ACTIONS_DIR"/evaluation-*.md "$ACTIONS_DIR"/gen-report-*.md "$ACTIONS_DIR"/lead-report-*.md; do
    [ -f "$f" ] || continue
    process_blocks_in_file "$f"
  done
}

# ─────────────────────────────────────────
# Parse CLI
# ─────────────────────────────────────────
TARGET=""
RULE_ID=""
TITLE=""
WRONG=""
RIGHT=""
WHY=""
SCOPE="항상"
SOURCE="evaluator:auto"
MODE="single"
FROM_JSON=""

while [ $# -gt 0 ]; do
  case "$1" in
    --target)   TARGET="$2"; shift 2 ;;
    --rule-id)  RULE_ID="$2"; shift 2 ;;
    --title)    TITLE="$2"; shift 2 ;;
    --wrong)    WRONG="$2"; shift 2 ;;
    --right)    RIGHT="$2"; shift 2 ;;
    --why)      WHY="$2"; shift 2 ;;
    --scope)    SCOPE="$2"; shift 2 ;;
    --source)   SOURCE="$2"; shift 2 ;;
    --from-json) MODE="json"; FROM_JSON="$2"; shift 2 ;;
    --scan-evaluations) MODE="scan"; shift ;;
    --scan-all) MODE="scan-all"; shift ;;
    *) echo "[gotcha-register] unknown arg: $1" >&2; exit 1 ;;
  esac
done

case "$MODE" in
  single)
    if [ -z "$TARGET" ] || [ -z "$RULE_ID" ] || [ -z "$TITLE" ]; then
      echo "[gotcha-register] usage: --target X --rule-id Y --title Z [...]" >&2
      exit 1
    fi
    register_one "$TARGET" "$RULE_ID" "$TITLE" "$WRONG" "$RIGHT" "$WHY" "$SCOPE" "$SOURCE"
    ;;
  json)
    if [ ! -f "$FROM_JSON" ]; then echo "[gotcha-register] file not found: $FROM_JSON" >&2; exit 1; fi
    register_from_json "$(cat "$FROM_JSON")"
    ;;
  scan)
    scan_evaluations
    ;;
  scan-all)
    scan_all
    ;;
esac
