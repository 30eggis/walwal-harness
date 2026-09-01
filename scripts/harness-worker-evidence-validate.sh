#!/bin/bash
# harness-worker-evidence-validate.sh — block CXX direct execution without worker reports
set -euo pipefail

PROJECT_ROOT="${1:-.}"
DOC_ROOT="$PROJECT_ROOT/.harness/documents"

[ -d "$DOC_ROOT" ] || exit 0

mode="${2:-text}"
scope="${3:-all}"
violations=()

# Section-scoped reading (conventions/shared.md): match `^>?\s*#{1,6}` and take
# every hit — blockquoted or plain, at any depth, with no content filter. A
# heading anchored on `^#` alone misses the same heading quoted one level in,
# which is how in-place retractions and continuation lines get written.
HEADING2='^[[:space:]]*>?[[:space:]]*##[[:space:]]+'
HEADING3='^[[:space:]]*>?[[:space:]]*###[[:space:]]+'

has_implementation_notes() {
  local file="$1"
  [ -s "$file" ] || return 1
  grep -Eq "${HEADING2}Implementation Notes[[:space:]]*$" "$file" &&
    grep -Eq "${HEADING3}Design Decisions[[:space:]]*$" "$file" &&
    grep -Eq "${HEADING3}Deviations[[:space:]]*$" "$file" &&
    grep -Eq "${HEADING3}Tradeoffs[[:space:]]*$" "$file" &&
    grep -Eq "${HEADING3}Open Questions[[:space:]]*$" "$file"
}

has_worker_report() {
  local mission_dir="$1"
  local owner="${2:-}"
  if [ -n "$owner" ]; then
    find "$mission_dir/$owner/workers" -maxdepth 1 -type f -name '*.md' 2>/dev/null | grep -q .
  else
    find "$mission_dir"/{coo,cdo,cto,cqo,ops}/workers -maxdepth 1 -type f -name '*.md' 2>/dev/null | grep -q .
  fi
}

has_legacy_flat_worker_report() {
  local mission_dir="$1"
  find "$mission_dir/workers" -maxdepth 1 -type f -name '*.md' 2>/dev/null | grep -q .
}

mission_dirs=$(find "$DOC_ROOT" -type f \( -name 'ceo.md' -o -name 'coo.md' -o -name 'cdo.md' -o -name 'cto.md' -o -name 'cqo.md' -o -name 'ops.md' \) -exec dirname {} \; 2>/dev/null | sort -u)

mission_mtime() {
  stat -f '%m' "$1" 2>/dev/null || stat -c '%Y' "$1" 2>/dev/null || echo 0
}

is_terminal_lifecycle() {
  case "$1" in
    closed|cancelled|superseded|complete|completed|blocked) return 0 ;;
    *) return 1 ;;
  esac
}

latest_active_mission=""
if [ "$scope" = "latest-active" ]; then
  latest_active_mtime=0
  while IFS= read -r mission_dir; do
    [ -n "$mission_dir" ] || continue
    state_path="$mission_dir/mission-state.json"
    [ -f "$state_path" ] || continue
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

while IFS= read -r mission_dir; do
  [ -n "$mission_dir" ] || continue
  [ -d "$mission_dir" ] || continue
  mission_name="${mission_dir#$DOC_ROOT/}"

  ceo_path="$mission_dir/ceo.md"
  if [ -s "$ceo_path" ] && ! has_implementation_notes "$ceo_path"; then
    violations+=("$mission_name:ceo.md-missing-implementation-notes")
  fi

  if has_legacy_flat_worker_report "$mission_dir"; then
    violations+=("$mission_name:legacy-flat-workers")
  fi

  for cxx in coo cdo cto cqo ops; do
    cxx_path="$mission_dir/$cxx.md"
    [ -s "$cxx_path" ] || continue
    if ! has_implementation_notes "$cxx_path"; then
      violations+=("$mission_name:$cxx.md-missing-implementation-notes")
    fi
    if ! has_worker_report "$mission_dir" "$cxx"; then
      violations+=("$mission_name:$cxx.md")
    fi
    workers_dir="$mission_dir/$cxx/workers"
    [ -d "$workers_dir" ] || continue
    for worker_report in "$workers_dir"/*.md; do
      [ -e "$worker_report" ] || continue
      if ! has_implementation_notes "$worker_report"; then
        violations+=("$mission_name:$cxx/workers/$(basename "$worker_report")-missing-implementation-notes")
      fi
    done
  done

  cqo_path="$mission_dir/cqo.md"
  if [ -s "$cqo_path" ] && grep -Eq '\b(ACCEPTED|REJECTED|PASS|FAIL)\b' "$cqo_path" && ! has_worker_report "$mission_dir" "cqo"; then
    violations+=("$mission_name:cqo-verdict-without-evaluator")
  fi
done <<EOF
$mission_dirs
EOF

if [ "${#violations[@]}" -eq 0 ]; then
  if [ "$mode" = "json" ]; then
    jq -nc '{ok:true, violations:[]}'
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
  echo "CXX worker evidence violation:"
  for violation in "${violations[@]}"; do
    mission="${violation%%:*}"
    docs="${violation#*:}"
    echo "- mission: $mission"
    echo "  issue: $docs"
    echo "  required: worker reports under .harness/documents/$mission/{cxx}/workers/{worker-name}.md"
  done
fi

exit 1
