#!/bin/bash
# harness-worker-evidence-validate.sh — block CXX direct execution without worker reports
set -euo pipefail

PROJECT_ROOT="${1:-.}"
DOC_ROOT="$PROJECT_ROOT/.harness/documents"

[ -d "$DOC_ROOT" ] || exit 0

mode="${2:-text}"
violations=()

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

for mission_dir in "$DOC_ROOT"/*; do
  [ -d "$mission_dir" ] || continue
  mission_name="$(basename "$mission_dir")"

  if has_legacy_flat_worker_report "$mission_dir"; then
    violations+=("$mission_name:legacy-flat-workers")
  fi

  for cxx in coo cdo cto cqo ops; do
    cxx_path="$mission_dir/$cxx.md"
    [ -s "$cxx_path" ] || continue
    if ! has_worker_report "$mission_dir" "$cxx"; then
      violations+=("$mission_name:$cxx.md")
    fi
  done

  cqo_path="$mission_dir/cqo.md"
  if [ -s "$cqo_path" ] && grep -Eq '\b(ACCEPTED|REJECTED|PASS|FAIL)\b' "$cqo_path" && ! has_worker_report "$mission_dir" "cqo"; then
    violations+=("$mission_name:cqo-verdict-without-evaluator")
  fi
done

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
