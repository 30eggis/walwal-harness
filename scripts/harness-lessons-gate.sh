#!/bin/bash
# harness-lessons-gate.sh — enforce "lessons precede planning" where the Stop
# hook already stops the turn (AGENTS.md Hard Rule 20).
#
# A role document that was written without reading the corpus is invisible; a
# role document that names which corpus items it applied, and then tallies which
# of them actually fired, is not. Rules that live only in prose are followed
# when convenient — this one gets the mechanism that already works.
#
# Checks every role document of the in-scope mission for:
#   ## Lessons Preflight   — which convention/gotcha items apply, and why
#   ## Lessons Tally       — one line: which of them actually fired ("0 fired" is valid)
#
# Usage: harness-lessons-gate.sh <project-root> [text|json] [all|latest-active|mission:<rel>]
set -euo pipefail

PROJECT_ROOT="${1:-.}"
DOC_ROOT="$PROJECT_ROOT/.harness/documents"
CONFIG="$PROJECT_ROOT/.harness/config.json"

mode="${2:-text}"
scope="${3:-all}"
if [ ! -d "$DOC_ROOT" ]; then
  [[ "$scope" != mission:* && "$mode" != direct-work-sha ]] || exit 1
  exit 0
fi

# Opt-out for projects that have not adopted the sections yet.
if command -v jq >/dev/null 2>&1 && [ -f "$CONFIG" ]; then
  # jq's `//` treats `false` as empty, so `.x // true` can never return false.
  # Test for null explicitly or the opt-out silently does nothing.
  enabled=$(jq -r 'if .behavior.lessons_gate == null then true else .behavior.lessons_gate end' "$CONFIG" 2>/dev/null || echo true)
  if [ "$enabled" != "true" ]; then
    [ "$mode" = "json" ] && jq -nc '{ok:true, violations:[], skipped:"lessons_gate disabled"}'
    exit 0
  fi
fi

violations=()

# Section-scoped reading (conventions/shared.md): match `^>?\s*#{1,6}` and take
# every hit — blockquoted or plain, at any depth, with no content filter.
HEADING2='^[[:space:]]*>?[[:space:]]*##[[:space:]]+'

has_section() {
  local file="$1" title="$2"
  [ -s "$file" ] || return 1
  grep -Eq "${HEADING2}${title}[[:space:]]*$" "$file"
}

is_terminal_lifecycle() {
  case "$1" in
    closed|cancelled|superseded|complete|completed|blocked) return 0 ;;
    *) return 1 ;;
  esac
}

mission_mtime() {
  stat -f '%m' "$1" 2>/dev/null || stat -c '%Y' "$1" 2>/dev/null || echo 0
}

mission_dirs=""
if [[ "$scope" != mission:* ]]; then
  mission_dirs=$(find "$DOC_ROOT" -type f \( -name 'ceo.md' -o -name 'coo.md' -o -name 'cdo.md' -o -name 'cto.md' -o -name 'cqo.md' -o -name 'ops.md' \) -exec dirname {} \; 2>/dev/null | sort -u)
fi

if [ "$scope" = "latest-active" ]; then
  latest_active_mission=""
  latest_active_mtime=0
  while IFS= read -r mission_dir; do
    [ -n "$mission_dir" ] || continue
    state_path="$mission_dir/mission-state.json"
    [ -f "$state_path" ] || continue
    command -v jq >/dev/null 2>&1 || continue
    active=$(jq -r '.active // false' "$state_path" 2>/dev/null || echo false)
    lifecycle=$(jq -r '.lifecycle // .status // "unknown"' "$state_path" 2>/dev/null || echo unknown)
    if [ "$active" != "true" ] || is_terminal_lifecycle "$lifecycle"; then
      continue
    fi
    mtime=$(mission_mtime "$mission_dir")
    if [ "${mtime:-0}" -ge "${latest_active_mtime:-0}" ]; then
      latest_active_mtime="$mtime"
      latest_active_mission="$mission_dir"
    fi
  done <<EOF
$mission_dirs
EOF
  mission_dirs="$latest_active_mission"
fi

if [[ "$scope" == mission:* ]]; then
  mission_rel="${scope#mission:}"
  case "$mission_rel" in ""|/*|*..*) echo "invalid mission path" >&2; exit 1 ;; esac
  mission_dirs="$(cd "$DOC_ROOT/$mission_rel" 2>/dev/null && pwd -P)" || exit 1
  case "$mission_dirs/" in "$(cd "$DOC_ROOT" && pwd -P)/"*) ;; *) exit 1 ;; esac
  [ -f "$mission_dirs/mission-state.json" ] || exit 1
fi

while IFS= read -r mission_dir; do
  [ -n "$mission_dir" ] || continue
  [ -d "$mission_dir" ] || continue
  mission_name="${mission_dir#"$DOC_ROOT"/}"
  tier=2
  if [ -f "$mission_dir/mission-state.json" ]; then
    tier=$(jq -r 'def r: if . == "S" then 0 elif . == "M" then 1 else 2 end;
      [.tier, (.tier_history[]? | .from, .to)] | map(r) | max' "$mission_dir/mission-state.json")
  fi
  if [ -f "$PROJECT_ROOT/.harness/config.json" ]; then
    enabled=$(jq -r 'if .behavior.mission_tiers == null then true else .behavior.mission_tiers end' "$PROJECT_ROOT/.harness/config.json")
    [ "$enabled" != false ] || tier=2
  fi

  for role in ceo coo cdo cto cqo ops; do
    role_path="$mission_dir/$role.md"
    [ -s "$role_path" ] || continue
    if [[ "$role" == coo || "$role" == cdo || "$role" == ops ]] && has_section "$role_path" "Not Applicable"; then
      continue
    fi
    if [ "$tier" -lt 2 ] && has_section "$role_path" "Lessons"; then
      continue
    fi
    if ! has_section "$role_path" "Lessons Preflight"; then
      violations+=("$mission_name:$role.md-missing-lessons-preflight")
    fi
    if ! has_section "$role_path" "Lessons Tally"; then
      violations+=("$mission_name:$role.md-missing-lessons-tally")
    fi
  done
done <<EOF
$mission_dirs
EOF

if [ "${#violations[@]}" -eq 0 ]; then
  if [ "$mode" = "json" ]; then
    jq -nc '{ok:true, violations:[]}' 2>/dev/null || echo '{"ok":true,"violations":[]}'
  fi
  exit 0
fi

if [ "$mode" = "json" ]; then
  printf '%s\n' "${violations[@]}" | jq -Rcs '
    split("\n")[:-1]
    | map(capture("(?<mission>[^:]+):(?<docs>.*)") | .docs = (.docs | split(" ")))
    | {ok:false, violations:.}
  '
else
  echo "Lessons-before-plan violation (AGENTS.md Hard Rule 20; unknown tier → L):"
  for violation in "${violations[@]}"; do
    mission="${violation%%:*}"
    docs="${violation#*:}"
    echo "- mission: $mission"
    echo "  issue: $docs"
    echo "  S/M role documents may instead use ## Lessons (Preflight/Fired)."
    echo "  required: '## Lessons Preflight' (which convention/gotcha items apply, and why)"
    echo "            '## Lessons Tally' (one line: which fired; '0 fired' is valid and must be stated)"
  done
fi

exit 1
