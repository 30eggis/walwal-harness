#!/usr/bin/env bash
# harness-goal-init.sh — 새 GOAL 발급 (CEO=Dispatcher 전용)
# 사용법: bash scripts/harness-goal-init.sh "<title>"
#
# 동작:
#   1. .harness/actions/goals.md 가 없으면 template로 생성
#   2. 다음 GOAL ID(G-N) 발급 → progress.json.goals.list 에 등록
#   3. progress.json.goals.active_id 갱신
#   4. CTO 협의 미완료 상태(cto_feasibility=null, owner_confirmed=false)
#
# 후속:
#   - CTO는 cto_feasibility 의견을 협의 후 같은 항목에 채워줌
#   - Owner 최종 확인 시 dispatcher 가 owner_confirmed=true 로 갱신
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GOAL_FILE="$ROOT/.harness/actions/goals.md"
TEMPLATE="$ROOT/.harness/actions/goals.md.template"
PROGRESS="$ROOT/.harness/progress.json"

TITLE="${1:-}"
if [ -z "$TITLE" ]; then
  echo "usage: $0 \"<title>\"" >&2
  exit 1
fi

mkdir -p "$ROOT/.harness/actions"

# 1. 파일이 없으면 template 복사 후 ISO 시각 채움
if [ ! -f "$GOAL_FILE" ]; then
  if [ ! -f "$TEMPLATE" ]; then
    echo "template missing: $TEMPLATE" >&2; exit 1
  fi
  ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  sed "s|<ISO>|$ISO|g" "$TEMPLATE" > "$GOAL_FILE"
fi

# 2. 다음 GOAL ID 계산
LAST_N=$(jq -r '.goals.list | map(.id // "G-0") | map(sub("G-"; "")) | map(tonumber? // 0) | max // 0' "$PROGRESS" 2>/dev/null || echo 0)
NEXT_N=$((LAST_N + 1))
GOAL_ID="G-${NEXT_N}"
ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# 3. progress.json 에 등록 (partial update)
jq --arg id "$GOAL_ID" --arg title "$TITLE" --arg iso "$ISO" '
  .goals.list += [{
    "id": $id,
    "title": $title,
    "status": "draft",
    "owner_confirmed": false,
    "cto_feasibility": null,
    "created_at": $iso
  }] |
  .goals.active_id = $id |
  .updated_at = $iso
' "$PROGRESS" > "$PROGRESS.tmp" && mv "$PROGRESS.tmp" "$PROGRESS"

# 4. goals.md 에 GOAL 섹션 append (CEO가 이후 본문 채움)
cat >> "$GOAL_FILE" <<EOF

## $GOAL_ID — $TITLE
status: draft
owner_confirmed: false
cto_feasibility: null
created_at: $ISO

(CEO가 success_metrics·deadline·kpis·runbook 채움)
EOF

echo "$GOAL_ID 발급 완료: $TITLE"
echo "→ $GOAL_FILE 에서 본문 작성"
echo "→ CTO 협의 후 owner 확정 시 owner_confirmed=true"
