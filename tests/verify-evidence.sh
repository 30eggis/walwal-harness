#!/bin/bash
# Run: bash tests/verify-evidence.sh — isolated repositories, dummy secrets only.
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d /private/tmp/walwal-evidence.XXXXXX)
trap 'chmod -R u+rwX "$TMP"; rm -rf "$TMP"' EXIT
FP="$REPO/scripts/harness-verify-fingerprint.sh"
SCAN="$REPO/scripts/harness-secret-scan.sh"
mkdir "$TMP/project" "$TMP/not-git"
cd "$TMP/project"
git init -q
git config user.name 'Evidence Test'
git config user.email 'evidence@example.invalid'
printf 'test-results/\n.env.test\n' > .gitignore
printf 'original\n' > tracked.txt
printf '{}\n' > package-lock.json
mkdir .harness .myterm
printf 'first\n' > .harness/report.md
printf 'first\n' > .myterm/report.md
git add .
git commit -qm fixture
count=0
check() { "$@" || { echo "FAIL: $*" >&2; exit 1; }; count=$((count+1)); }
run() {
  local expected=$1 rc=0
  shift
  "$@" > "$TMP/out" 2> "$TMP/err" || rc=$?
  check test "$rc" -eq "$expected"
}
fp() { bash "$FP" --root "$TMP/project" "$@"; }
base=$(fp)
check test "${#base}" -eq 64
check test "$base" = "$(fp)"
echo changed >> tracked.txt
check test "$base" != "$(fp)"
git checkout -- tracked.txt
rm tracked.txt
check test "$base" != "$(fp)"
git checkout -- tracked.txt
echo new > 'new file.txt'
check test "$base" != "$(fp)"
rm 'new file.txt'
echo changed >> package-lock.json
check test "$base" != "$(fp)"
git checkout -- package-lock.json
echo staged > added.txt
git add added.txt
check test "$base" != "$(fp)"
git reset -q HEAD -- added.txt
rm added.txt
printf 'second\n' >> .harness/report.md
printf 'second\n' >> .myterm/report.md
echo untracked > .harness/untracked.md
echo untracked > .myterm/untracked.md
check test "$base" = "$(fp)"
mkdir test-results
echo result > test-results/ignored.txt
check test "$base" = "$(fp)"
missing=$(fp --include .env.test)
echo dummy > .env.test
created=$(fp --include .env.test)
check test "$missing" != "$created"
check test "$base" = "$(fp)"
echo changed >> .env.test
check test "$created" != "$(fp --include .env.test)"
rm .env.test
check test "$missing" = "$(fp --include .env.test)"
echo external > "$TMP/external.mjs"
external=$(fp --include "$TMP/external.mjs")
echo changed >> "$TMP/external.mjs"
check test "$external" != "$(fp --include "$TMP/external.mjs")"
run 2 bash "$FP" --root "$TMP/not-git"
check test ! -s "$TMP/out"
run 2 bash "$FP" --root "$TMP/absent"
check test ! -s "$TMP/out"
run 2 bash "$FP" run -- true
run 2 bash "$FP" run --log test-results/run.log
run 2 bash "$FP" run --log test-results/run.log --
run 0 bash "$FP" run --log test-results/run.log --root "$TMP/project" -- sh -c 'echo stdout; echo stderr >&2'
check grep -q '^Baseline: .*exit=0 ' "$TMP/out"
check grep -q "fingerprint=$base " "$TMP/out"
check grep -q stdout test-results/run.log
check grep -q stderr test-results/run.log
run 1 bash "$FP" run --log test-results/run.log -- false
check grep -q '^Baseline: .*exit=1 ' "$TMP/out"
run 3 bash "$FP" run --log test-results/run.log -- sh -c 'exit 3'
check grep -q '^Baseline: .*exit=3 ' "$TMP/out"
run 3 bash "$FP" run --log test-results/run.log -- sh -c 'echo x >> tracked.txt'
check test ! -s "$TMP/out"
check grep -q 'tree changed during run' "$TMP/err"
git checkout -- tracked.txt
# An unignored log changes the source inputs and cannot create a baseline.
run 3 bash "$FP" run --log new.log -- true
check test ! -s "$TMP/out"
rm new.log

export DUMMY_SECRET=wh-dummy-7f3a
mkdir "$TMP/leaky" "$TMP/clean" "$TMP/errors"
printf '%s\n' "$DUMMY_SECRET" > "$TMP/leaky/match.txt"
echo clean > "$TMP/clean/file.txt"
scan() {
  run "$@"
  # Inspect both output streams without putting the dummy value in grep argv.
  if grep -qF -f <(printf '%s\n' "$DUMMY_SECRET") "$TMP/out" "$TMP/err"; then
    echo 'FAIL: secret appeared in output' >&2; exit 1
  fi
  count=$((count+1))
}
scan 1 bash "$SCAN" DUMMY_SECRET -- "$TMP/leaky"
check grep -q '^leaks=1$' "$TMP/out"
check grep -q '^leak: .*match.txt$' "$TMP/out"
scan 0 bash "$SCAN" DUMMY_SECRET -- "$TMP/clean"
check grep -q '^leaks=0$' "$TMP/out"
unset UNSET_SECRET || true
scan 2 bash "$SCAN" UNSET_SECRET -- "$TMP/clean"
export EMPTY_SECRET=
scan 2 bash "$SCAN" EMPTY_SECRET -- "$TMP/clean"
scan 2 bash "$SCAN" 'INVALID-NAME' -- "$TMP/clean"
scan 2 bash "$SCAN" -- "$TMP/clean"
scan 2 bash "$SCAN" DUMMY_SECRET --
scan 2 bash "$SCAN" DUMMY_SECRET -- "$TMP/absent"
echo clean > "$TMP/errors/clean.txt"
echo unreadable > "$TMP/errors/unreadable.txt"
chmod 000 "$TMP/errors/unreadable.txt"
if [ "$(id -u)" -eq 0 ]; then
  echo 'SKIP: root (read permission failures)'
else
  scan 2 bash "$SCAN" DUMMY_SECRET -- "$TMP/errors"
  check test ! -s "$TMP/out"
  check grep -q 'scan incomplete' "$TMP/err"
  cp "$TMP/leaky/match.txt" "$TMP/errors/match.txt"
  scan 2 bash "$SCAN" DUMMY_SECRET -- "$TMP/errors"
  check grep -q '^leak: .*match.txt$' "$TMP/out"
  check test "$(grep -c '^leaks=0$' "$TMP/out" || true)" -eq 0
fi
printf 'PASS: %s evidence checks\n' "$count"
