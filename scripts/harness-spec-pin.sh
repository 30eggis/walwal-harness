#!/bin/bash
# harness-spec-pin.sh — AGENTS.md Hard Rule 4 (spec-pin clause).
#
# A category is complete AGAINST A SPEC VERSION, never in the abstract. Measured:
# a spec moved v0.7 -> v0.9, changing a response contract, while the category
# built against v0.7 sat marked complete — two later revisions had landed
# silently, and nothing in the harness recorded which version the work was for.
# The symptom was a lookup key that no longer matched: no error, no log, three
# overlays dropped as null.
#
# Usage:
#   harness-spec-pin.sh <project-root> <mission-rel> add <name> <path> [version]
#   harness-spec-pin.sh <project-root> <mission-rel> verify [text|json]
#   harness-spec-pin.sh <project-root> <mission-rel> list
set -uo pipefail

PROJECT_ROOT="${1:-.}"
MISSION_REL="${2:-}"
CMD="${3:-verify}"
DOCS="$PROJECT_ROOT/.harness/documents"
PINS="$DOCS/$MISSION_REL/spec-pins.json"

command -v jq >/dev/null 2>&1 || { echo "[spec-pin] jq required" >&2; exit 2; }
[ -n "$MISSION_REL" ] || { echo "[spec-pin] mission path required" >&2; exit 2; }

hash_of() {
  local f="$1"
  [ -f "$f" ] || { printf 'MISSING'; return; }
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$f" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then sha256sum "$f" | awk '{print $1}'
  else printf 'NOHASHER'; fi
}

case "$CMD" in
  add)
    name="${4:-}"; specpath="${5:-}"; version="${6:-unversioned}"
    [ -n "$name" ] && [ -n "$specpath" ] || { echo "[spec-pin] usage: add <name> <path> [version]" >&2; exit 2; }
    mkdir -p "$(dirname "$PINS")"
    [ -f "$PINS" ] || echo '{"pins":[]}' > "$PINS"
    abs="$specpath"; case "$specpath" in /*) ;; *) abs="$PROJECT_ROOT/$specpath" ;; esac
    h="$(hash_of "$abs")"
    tmp="$(mktemp)"
    jq --arg n "$name" --arg p "$specpath" --arg v "$version" --arg h "$h" \
       '.pins = ((.pins // []) | map(select(.name != $n)) + [{name:$n, path:$p, version:$v, sha256:$h, pinned_at:(now|todate)}])' \
       "$PINS" > "$tmp" && mv "$tmp" "$PINS"
    echo "[spec-pin] pinned $name @ $version ($h)"
    ;;
  list)
    [ -f "$PINS" ] && jq -r '.pins[] | "- \(.name) @ \(.version) — \(.path) [\(.sha256[0:12])]"' "$PINS" || echo "(no pins)"
    ;;
  verify)
    mode="${4:-text}"
    # No pins file is not a failure: not every mission builds against an external spec.
    if [ ! -f "$PINS" ]; then
      [ "$mode" = "json" ] && jq -nc '{ok:true, drifted:[], pinned:0}'
      exit 0
    fi
    drifted=()
    while IFS=$'\t' read -r name specpath version want; do
      [ -n "$name" ] || continue
      abs="$specpath"; case "$specpath" in /*) ;; *) abs="$PROJECT_ROOT/$specpath" ;; esac
      got="$(hash_of "$abs")"
      [ "$got" = "NOHASHER" ] && continue
      if [ "$got" != "$want" ]; then
        if [ "$got" = "MISSING" ]; then drifted+=("$name|$version|spec file is gone: $specpath")
        else drifted+=("$name|$version|content changed since it was pinned: $specpath"); fi
      fi
    done < <(jq -r '.pins[]? | [.name, .path, .version, .sha256] | @tsv' "$PINS" 2>/dev/null)
    total="$(jq '[.pins[]?] | length' "$PINS" 2>/dev/null || echo 0)"
    if [ "${#drifted[@]}" -eq 0 ]; then
      [ "$mode" = "json" ] && jq -nc --argjson n "$total" '{ok:true, drifted:[], pinned:$n}'
      [ "$mode" = "text" ] && echo "[spec-pin] $total pin(s) still match the current documents"
      exit 0
    fi
    if [ "$mode" = "json" ]; then
      printf '%s\n' "${drifted[@]}" | jq -Rcs 'split("\n")[:-1] | map(split("|") | {name:.[0], pinned_version:.[1], detail:.[2]}) | {ok:false, drifted:.}'
    else
      echo "Spec pin drift (AGENTS.md Hard Rule 4):"
      for d in "${drifted[@]}"; do
        rest="${d#*|}"
        echo "- ${d%%|*} (built against ${rest%%|*})"
        echo "    ${d##*|}"
      done
      echo "  This mission was built against a spec that has since moved. Re-check the"
      echo "  affected work before marking anything complete, then re-pin:"
      echo "    scripts/harness-spec-pin.sh . $MISSION_REL add <name> <path> <new-version>"
    fi
    exit 1
    ;;
  *) echo "[spec-pin] unknown command: $CMD" >&2; exit 2 ;;
esac
