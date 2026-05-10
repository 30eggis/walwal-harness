#!/bin/bash
# harness-parity-audit.sh — compare installed project company-loop surface to walwal-harness

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HARNESS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MANIFEST="$HARNESS_ROOT/assets/templates/company-pipeline-manifest.json"

usage() {
  echo "usage: bash scripts/harness-parity-audit.sh <project-root> [<project-root> ...]" >&2
}

[ "$#" -gt 0 ] || { usage; exit 2; }
[ -f "$MANIFEST" ] || { echo "MISSING manifest: $MANIFEST" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "MISSING jq" >&2; exit 2; }

sha() {
  LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 shasum -a 256 "$1" | awk '{print $1}'
}

project_path_for() {
  local rel="$1"
  case "$rel" in
    conventions/*) echo ".harness/$rel" ;;
    gotchas/*) echo ".harness/$rel" ;;
    skills/*) echo ".harness/$rel" ;;
    *) echo "$rel" ;;
  esac
}

config_core_filter() {
  jq -S '
    del(.project, .name, .description, .paths, .production, .telegram, .services, .owners, .runtime, .tech_stack, .integrations)
  ' "$1"
}

status=0
for project in "$@"; do
  project="$(cd "$project" && pwd)"
  echo "== $project =="

  if [ ! -d "$project/.harness" ]; then
    echo "DRIFT missing .harness"
    status=1
    continue
  fi

  while IFS= read -r rel; do
    src="$HARNESS_ROOT/$rel"
    dst="$project/$(project_path_for "$rel")"
    if [ ! -f "$src" ]; then
      echo "UPSTREAM_REQUIRED missing-source $rel"
      status=1
    elif [ ! -f "$dst" ]; then
      echo "DRIFT missing $rel -> $(project_path_for "$rel")"
      status=1
    elif [ "$(sha "$src")" != "$(sha "$dst")" ]; then
      echo "DRIFT hash $rel -> $(project_path_for "$rel")"
      status=1
    else
      echo "PASS $rel"
    fi
  done < <(jq -r '.identical_files[]' "$MANIFEST")

  while IFS=$'\t' read -r src_rel dst_rel mode; do
    src="$HARNESS_ROOT/$src_rel"
    dst="$project/$dst_rel"
    if [ ! -f "$dst" ]; then
      echo "DRIFT missing $dst_rel"
      status=1
    elif [ "$mode" = "identical" ] && [ "$(sha "$src")" != "$(sha "$dst")" ]; then
      echo "DRIFT hash $src_rel -> $dst_rel"
      status=1
    else
      echo "PASS $src_rel -> $dst_rel"
    fi
  done < <(jq -r '.template_mappings[] | [.source, .target, .mode] | @tsv' "$MANIFEST")

  if [ -f "$project/.harness/config.json" ]; then
    tmp_src="$(mktemp)"
    tmp_dst="$(mktemp)"
    config_core_filter "$HARNESS_ROOT/assets/templates/config.json" > "$tmp_src"
    config_core_filter "$project/.harness/config.json" > "$tmp_dst"
    if jq -e -s '.[0] == .[1]' "$tmp_src" "$tmp_dst" >/dev/null; then
      echo "PASS config-core"
    else
      echo "DRIFT config-core"
      diff -u "$tmp_src" "$tmp_dst" | sed 's/^/  /'
      status=1
    fi
    rm -f "$tmp_src" "$tmp_dst"
  else
    echo "DRIFT missing .harness/config.json"
    status=1
  fi

  echo
done

exit "$status"
