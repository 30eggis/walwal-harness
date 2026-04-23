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
# evaluation-*.md 스캔 — ```gotcha_candidates ... ``` JSON fenced block 추출
# ─────────────────────────────────────────
scan_evaluations() {
  if [ ! -d "$ACTIONS_DIR" ]; then return 0; fi
  local f
  for f in "$ACTIONS_DIR"/evaluation-*.md; do
    [ -f "$f" ] || continue

    # Enumerate blocks — simple per-file awk that prints each block into a
    # uniquely-named temp file. Avoids macOS awk \0 quirks.
    local blocks_prefix
    blocks_prefix=$(mktemp -d)
    awk -v dir="$blocks_prefix" '
      BEGIN { idx=0 }
      /^```gotcha_candidates[[:space:]]*$/ { flag=1; buf=""; next }
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
    ' "$f"

    local blockfile
    for blockfile in "$blocks_prefix"/block-*.json; do
      [ -f "$blockfile" ] || continue
      if jq empty "$blockfile" 2>/dev/null; then
        register_from_json "$(cat "$blockfile")"
      else
        echo "[gotcha-register] skip: invalid JSON block in $(basename "$f")" >&2
      fi
    done
    rm -rf "$blocks_prefix"
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
esac
