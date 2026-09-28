#!/bin/bash
# Source identity is necessary, not sufficient: see CQO Evidence Reuse.
set -o pipefail
fail() { echo "[verify-fingerprint] $*" >&2; exit 2; }
CMD=fingerprint
ROOT=.
LOG=
INCLUDES=()
[ "${1:-}" != run ] || { CMD=run; shift; }
SEPARATOR=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    --root|--include|--log)
      [ "$#" -ge 2 ] && [ -n "$2" ] || fail "missing option value"
      case "$1" in
        --root) ROOT=$2 ;;
        --include) INCLUDES+=("$2") ;;
        --log) LOG=$2 ;;
      esac
      shift 2 ;;
    --) SEPARATOR=true; shift; break ;;
    *) fail "unknown option" ;;
  esac
done
if [ "$CMD" = run ]; then
  [ -n "$LOG" ] && [ "$SEPARATOR" = true ] && [ "$#" -gt 0 ] || fail "run requires --log PATH and -- CMD..."
else
  [ "$SEPARATOR" = false ] && [ -z "$LOG" ] || fail "unexpected run options"
fi
cd -- "$ROOT" 2>/dev/null || fail "invalid root"
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || fail "not a git repository"
cd -- "$ROOT" || fail "invalid repository root"
if command -v shasum >/dev/null 2>&1; then HASH=(shasum -a 256)
elif command -v sha256sum >/dev/null 2>&1; then HASH=(sha256sum)
else fail "SHA-256 tool required"; fi
hash() { "${HASH[@]}" | awk '{print $1}'; }
PATHS=(. ':(top,exclude).harness' ':(top,exclude).myterm')
file_input() {
  printf '%s\0' "$1"
  if [ -e "$1" ] || [ -L "$1" ]; then
    [ -f "$1" ] || return 2
    hash < "$1" || return 2
  else printf 'MISSING\n'; fi
}
fingerprint() {
  {
    git rev-parse --verify HEAD || return 2
    git diff HEAD --binary --no-ext-diff --no-textconv -- "${PATHS[@]}" || return 2
    git ls-files --others --exclude-standard -z -- "${PATHS[@]}" |
      while IFS= read -r -d '' file; do file_input "$file" || exit 2; done || return 2
    for file in "${INCLUDES[@]}"; do file_input "$file" || return 2; done
  } | hash
}
BEFORE=$(fingerprint) || fail "cannot fingerprint inputs"
case "$CMD" in
  fingerprint) printf '%s\n' "$BEFORE" ;;
  run)
    # ponytail: before/after misses ABA edits; wait for editors or use a fixed worktree.
    # Relative log/include paths and the command are resolved from the repository root.
    (umask 077; : > "$LOG") || fail "cannot open log"
    "$@" > "$LOG" 2>&1
    RC=$?
    AFTER=$(fingerprint) || fail "cannot fingerprint inputs after run"
    [ "$BEFORE" = "$AFTER" ] || { echo 'tree changed during run' >&2; exit 3; }
    printf 'Baseline: cmd='
    printf '%q ' "$@"
    printf 'exit=%s log=%q fingerprint=%s includes=' "$RC" "$LOG" "$BEFORE"
    printf '%q ' "${INCLUDES[@]}"
    printf '\n'
    exit "$RC" ;;
esac
