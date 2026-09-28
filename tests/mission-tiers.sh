#!/bin/bash
# Run: bash tests/mission-tiers.sh — real gates, isolated /private/tmp fixtures.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
ROOT=$(mktemp -d /private/tmp/walwal-tiers.XXXXXX)
trap 'rm -rf "$ROOT"' EXIT
count=0
fresh() {
  local role
  rm -rf "$ROOT/.harness"
  M="$ROOT/.harness/documents/goal-test"
  mkdir -p "$M" "$ROOT/.harness/todos"
  echo '{"conductor":{"state":"running"},"company_state":{"state":"running"}}' > "$ROOT/.harness/progress.json"
  echo '{"owners":{"cto":[{"status":"active"}]}}' > "$ROOT/.harness/todos/state.json"
  echo '{"behavior":{"mission_tiers":true}}' > "$ROOT/.harness/config.json"
  echo '{"tier":"S","active":true,"lifecycle":"active"}' > "$M/mission-state.json"
  for role in ceo cto cqo; do
    printf '## Lessons\nPreflight: none\nFired: 0 fired\n## Implementation Notes\n- None\n' > "$M/$role.md"
  done
  printf '## Direct Work\nFixed one function.  \n' >> "$M/cto.md"
  printf '## Verification Commands\nnode --check sample.js / exit 0 / no syntax errors\nVerification Session: separate\n## CQO Verdict\nVerdict: PASS\n' >> "$M/cqo.md"
}
state() { jq "$1" "$M/mission-state.json" > "$ROOT/state.tmp"; mv "$ROOT/state.tmp" "$M/mission-state.json"; }
worker() { mkdir -p "$M/$1/workers"; cp "$REPO/assets/templates/worker-report.md.template" "$M/$1/workers/check.md"; }
full_roles() {
  local role
  for role in ceo cto cqo; do
    printf '\n## Lessons Preflight\nnone\n## Lessons Tally\n0 fired\n### Design Decisions\nNone\n### Deviations\nNone\n### Tradeoffs\nNone\n### Open Questions\nNone\n' >> "$M/$role.md"
  done
}
complete() { bash "$REPO/scripts/harness-company-complete.sh" "$ROOT" test "${1:-goal-test}"; }
check() {
  local expected="$1" reason="${2:-}" path="${3:-goal-test}" code=0
  cp "$ROOT/.harness/progress.json" "$ROOT/progress.before"
  cp "$ROOT/.harness/todos/state.json" "$ROOT/todos.before"
  cp "$M/mission-state.json" "$ROOT/mission.before"
  complete "$path" > "$ROOT/output" 2>&1 || code=$?
  if { [ "$expected" = pass ] && [ "$code" -ne 0 ]; } || { [ "$expected" = fail ] && [ "$code" -eq 0 ]; }; then
    cat "$ROOT/output"; echo "FAIL case $count: expected $expected ($reason)"; exit 1
  fi
  if [ "$expected" = fail ]; then
    cmp "$ROOT/progress.before" "$ROOT/.harness/progress.json"
    cmp "$ROOT/todos.before" "$ROOT/.harness/todos/state.json"
    cmp "$ROOT/mission.before" "$M/mission-state.json"
    grep -q -- "$reason" "$ROOT/output"
  else
    jq -e '.conductor.state == "completed"' "$ROOT/.harness/progress.json" >/dev/null
  fi
  count=$((count+1))
}
verdict() { fresh; sed '/Verdict: PASS/d' "$M/cqo.md" > "$ROOT/cqo.tmp"; mv "$ROOT/cqo.tmp" "$M/cqo.md"; printf '%s\n' "$1" >> "$M/cqo.md"; check "$2" "${3:-}"; }
verdict $'Verdict: FAIL\nPASS later' fail verdict-not-pass
verdict $'Verdict: PASS\nPrevious FAIL resolved' pass
verdict $'~~Verdict: FAIL~~\nVerdict: PASS' pass
verdict $'Verdict: PASS\nVerdict: FAIL' fail verdict-not-pass
verdict 'The result might PASS' fail missing-verdict
for invalid in 'Verdict: PASSED' 'Verdict: pass' 'Verdict: PASS (conditional)' 'Verdict: FAIL (regression)' 'Verdict:' '**Verdict: FAIL**' '- verdict: fail' '_Verdict: FAIL_' '**Verdict**: FAIL' '__Verdict__: FAIL' 'Verdict : FAIL'; do
  verdict "$invalid" fail invalid-final-verdict
  verdict "$(printf 'Verdict: PASS\n%s' "$invalid")" fail invalid-final-verdict
done
verdict $'Verdict: FAIL\n## Other\nVerdict: FAIL\n## CQO Verdict\nVerdict: PASS' pass
verdict $'Verdict: PASS\n## CQO Verdict\nVerdict: FAIL — reproduced' fail invalid-final-verdict
verdict $'Verdict: FAIL\n> Verdict: PASS' pass
verdict 'Verdict: ACCEPTED' pass
verdict $'Verdict: PASS\n### Re-evaluation\nVerdict: FAIL' fail verdict-not-pass
verdict $'Verdict: PASS\n## CQO Verdict (Re-test)\nVerdict: FAIL' fail verdict-not-pass
verdict $'Verdict: PASS\n> ### Re-evaluation\n**Verdict**: FAIL' fail invalid-final-verdict
verdict $'Verdict: FAIL\n## CQO Verdict (Re-test)\nVerdict: PASS' pass
verdict $'Verdict: PASS\n## Other\nVerdict: FAIL' pass
verdict $'Verdict: PASS\n# Other\nVerdict: FAIL' pass
fresh; rm "$M/cqo.md"; check fail missing-verdict
fresh; check fail invalid-mission-path ../x
fresh; check fail invalid-mission-path missing
fresh; check fail invalid-mission-path /tmp
fresh; ln -s /private/tmp "$ROOT/.harness/documents/outside"; check fail invalid-mission-path outside
for tier in S M L; do
  for end in cancelled superseded closed; do
    fresh; rm "$M/cqo.md"
    state ".tier=\"$tier\" | .lifecycle=\"$end\" | .active=false"
    # Even a corrupt mission spec pin must not block non-acceptance termination.
    echo broken > "$M/spec-pins.json"
    check pass
    cmp "$ROOT/mission.before" "$M/mission-state.json"
    grep -q "ended-without-acceptance | $end" "$ROOT/.harness/progress.log"
  done
done
fresh; check pass
fresh; sed -i.bak 's/Session: separate/Session: same-session/' "$M/cqo.md"; check pass
grep -q 'WARNING: same-session' "$ROOT/output"
grep -q 'warn | same-session-verification' "$ROOT/.harness/progress.log"
for role in cdo coo; do
  fresh; cp "$M/ceo.md" "$M/$role.md"; check fail "$role.md"
  worker "$role"; check pass
done
# S/M OPS observes directly; L OPS stays worker-backed.
for tier in S M; do fresh; state ".tier=\"$tier\""; [ "$tier" = S ] || { worker cto; worker cqo; }; cp "$M/ceo.md" "$M/ops.md"; check pass; done
fresh; state '.tier="L"'; full_roles; worker cto; worker cqo; cp "$M/ceo.md" "$M/ops.md"; check fail ops.md
# A summoned role with nothing to do completes with a one-reason N/A report, at any tier.
for role in ops cdo coo; do
  for tier in S L; do
    fresh; state ".tier=\"$tier\""; [ "$tier" = S ] || { full_roles; worker cto; worker cqo; }
    printf '## Not Applicable
No long-lived runtime in this mission.
' > "$M/$role.md"; check pass
  done
done
# N/A is not an escape hatch for CTO/CQO.
fresh; state '.tier="L"'; full_roles; worker cqo; printf '## Not Applicable
x
' >> "$M/cto.md"; check fail cto.md
for change in '.tier_history=[{from:"L",to:"S"}]' '.tier_history=[{from:"M",to:"S"}]' '.tier_history=[{from:"S",to:"L"},{from:"L",to:"S"}]' '.tier_history=[{from:"X",to:"S"}]' '.tier="X"' '.tier=null'; do
  fresh; state "$change"; check fail
 done
fresh; echo '{"behavior":{"mission_tiers":false}}' > "$ROOT/.harness/config.json"; check fail
upgrade() {
  fresh
  sha=$(bash "$REPO/scripts/harness-worker-evidence-validate.sh" "$ROOT" direct-work-sha mission:goal-test)
  [ "$sha" = "$(bash "$REPO/scripts/harness-worker-evidence-validate.sh" "$ROOT" direct-work-sha mission:goal-test)" ]
  state ".tier=\"M\" | .tier_history=[{from:\"S\",to:\"M\",direct_work_sha256:\"$sha\"}]"
  printf '## Post-Upgrade Work\nnone — verification only\n' >> "$M/cto.md"
  worker cqo
}
upgrade; check pass
upgrade; sed -i.bak 's/Fixed one function./Fixed two functions./' "$M/cto.md"; check fail cto-direct-work-modified-after-upgrade
upgrade; sed -i.bak 's/none — verification only/Added implementation/' "$M/cto.md"; check fail cto-post-upgrade-work-without-worker
worker cto; check pass
upgrade; state 'del(.tier_history[0].direct_work_sha256)'; check fail cto.md
upgrade; rm -rf "$M/cqo/workers"; check fail cqo-verdict-without-evaluator
upgrade; state '.tier="L" | .tier_history[0].to="L"'; check fail lessons-gate
full_roles; check pass
fresh; state '.tier="M"'; worker cto; worker cqo; check pass
state '.tier="L" | .active=true | .lifecycle="active" | .tier_history=[{from:"M",to:"L"}]'; check fail lessons-gate
full_roles; check pass
fresh; state 'del(.tier)'; full_roles; rm "$M/cqo.md"; check pass
# Explicit legacy targets use their own lessons, never a different active mission.
fresh; state 'del(.tier) | .active=false | .lifecycle="complete"'; full_roles
mkdir "$ROOT/.harness/documents/other"
echo '{"active":true,"lifecycle":"active"}' > "$ROOT/.harness/documents/other/mission-state.json"
echo 'missing lessons' > "$ROOT/.harness/documents/other/ceo.md"
check pass
fresh; state 'del(.tier) | .active=false | .lifecycle="complete"'
mkdir "$ROOT/.harness/documents/other"
echo '{"active":true,"lifecycle":"active"}' > "$ROOT/.harness/documents/other/mission-state.json"
printf '## Lessons Preflight\nnone\n## Lessons Tally\n0 fired\n' > "$ROOT/.harness/documents/other/ceo.md"
check fail lessons-gate
fresh; state 'del(.tier) | .active=false | .lifecycle="complete"'; rm "$M/cqo.md"
bash "$REPO/scripts/harness-company-complete.sh" "$ROOT" backstop > "$ROOT/output"
for tier in S M L; do
  fresh; state ".tier=\"$tier\""
  if bash "$REPO/scripts/harness-lessons-gate.sh" "$ROOT" text mission:goal-test > "$ROOT/output"; then
    [ "$tier" != L ]
  else
    [ "$tier" = L ]
  fi
  count=$((count+1))
done
fresh
# An active mission still chains normally; the Stop hook must not demand S workers.
echo '{"conductor":{"state":"running"},"next_agent":"cqo"}' > "$ROOT/.harness/progress.json"
jq -nc --arg cwd "$ROOT" '{cwd:$cwd}' | bash "$REPO/scripts/harness-stop.sh" > "$ROOT/output"
! grep -Eq 'worker/문서 증거 차단|교훈 선행 게이트' "$ROOT/output"
rm "$M/cto.md"
if bash "$REPO/scripts/harness-worker-evidence-validate.sh" "$ROOT" direct-work-sha mission:goal-test > "$ROOT/output" 2>&1; then exit 1; fi
fresh; sed -i.bak '/## Direct Work/d' "$M/cto.md"
if bash "$REPO/scripts/harness-worker-evidence-validate.sh" "$ROOT" direct-work-sha mission:goal-test > "$ROOT/output" 2>&1; then exit 1; fi
# Target the inactive mission even when a different active mission exists.
fresh; state '.active=false | .lifecycle="complete"'
mkdir "$ROOT/.harness/documents/other"
echo '{"tier":"S","active":true,"lifecycle":"active"}' > "$ROOT/.harness/documents/other/mission-state.json"
printf 'Verdict: FAIL\n' >> "$M/cqo.md"; check fail verdict-not-pass
# Worker notes stay strict even at S; unrelated missions do not poison explicit scope.
fresh; worker cto; printf '## Implementation Notes\n- compact\n' > "$M/cto/workers/check.md"; check fail missing-implementation-notes
fresh; mkdir -p "$ROOT/.harness/documents/other/cqo/workers"
printf '## Status\nCOMPLETE\n' > "$ROOT/.harness/documents/other/cqo/workers/check.md"
bash "$REPO/scripts/harness-progress-set.sh" "$ROOT" '.company_state.workers=[{name:"other",status:"running",report:".harness/documents/other/cqo/workers/check.md"}]' >/dev/null
check pass
# Spec drift remains a gate on the explicitly selected mission.
fresh; echo v1 > "$ROOT/spec.txt"
bash "$REPO/scripts/harness-spec-pin.sh" "$ROOT" goal-test add sample spec.txt v1 >/dev/null
echo v2 > "$ROOT/spec.txt"; check fail spec-pin
# Required S sections cannot be silently omitted.
fresh; sed -i.bak '/## Direct Work/d' "$M/cto.md"; check fail missing-direct-work
fresh; sed -i.bak '/## Verification Commands/d' "$M/cqo.md"; check fail missing-verification-commands
fresh; sed -i.bak '/Verification Session:/d' "$M/cqo.md"; check fail missing-verification-session
# A frozen section must have post-upgrade declaration even when a worker exists.
upgrade; sed -i.bak '/## Post-Upgrade Work/,$d' "$M/cto.md"; worker cto; check fail cto-post-upgrade-work-without-worker
# SHA covers trailing spaces and an absent final newline exactly.
fresh; printf '## Direct Work\nexact  ' > "$M/cto.md"
actual=$(bash "$REPO/scripts/harness-worker-evidence-validate.sh" "$ROOT" direct-work-sha mission:goal-test)
expected=$(printf 'exact  ' | shasum -a 256 | awk '{print $1}')
[ "$actual" = "$expected" ]
printf 'PASS: %s transition/lessons cases plus SHA, Stop, and legacy backstop checks\n' "$count"
