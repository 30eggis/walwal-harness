#!/bin/bash
# Pass variable names, never secret values, on the command line. Do not use bash -x.
set -o pipefail
fail() { echo "[secret-scan] $*" >&2; exit 2; }
VALS=()
while [ "$#" -gt 0 ] && [ "$1" != -- ]; do
  [[ "$1" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || fail "invalid variable name"
  [ -n "${!1}" ] || fail "unset or empty variable: $1"
  VALS+=("${!1}")
  shift
done
[ "${#VALS[@]}" -gt 0 ] && [ "${1:-}" = -- ] || fail "expected VAR_NAME... -- PATH..."
shift
[ "$#" -gt 0 ] || fail "no paths"
for path in "$@"; do [ -e "$path" ] || fail "missing path"; done
OUT=$(grep -rlF -f <(printf '%s\n' "${VALS[@]}") -- "$@")
RC=$?
COUNT=0
if [ -n "$OUT" ]; then
  while IFS= read -r path; do
    printf 'leak: %s\n' "$path"
    COUNT=$((COUNT+1))
  done <<< "$OUT"
fi
case "$RC" in
  0) printf 'leaks=%s\n' "$COUNT"; exit 1 ;;
  1) echo 'leaks=0'; exit 0 ;;
  *) echo "scan incomplete (grep rc=$RC)" >&2; exit 2 ;;
esac
