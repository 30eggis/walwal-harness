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
  find "$mission_dir/workers" -maxdepth 1 -type f -name '*.md' 2>/dev/null | grep -q .
}

for mission_dir in "$DOC_ROOT"/*; do
  [ -d "$mission_dir" ] || continue
  mission_name="$(basename "$mission_dir")"

  cxx_docs=()
  for cxx in coo cdo cto cqo ops; do
    cxx_path="$mission_dir/$cxx.md"
    [ -s "$cxx_path" ] || continue
    cxx_docs+=("$cxx.md")
  done

  [ "${#cxx_docs[@]}" -gt 0 ] || continue
  if ! has_worker_report "$mission_dir"; then
    violations+=("$mission_name:${cxx_docs[*]}")
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
    echo "  cxx_docs: $docs"
    echo "  required: at least one .harness/documents/$mission/workers/{worker-name}.md report"
  done
fi

exit 1
