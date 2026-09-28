#!/bin/bash
# harness-worker-evidence-validate.sh — enforce tier-scoped role and worker evidence
# Usage: <root> [text|json|direct-work-sha] [all|latest-active|mission:<rel>]
set -euo pipefail

PROJECT_ROOT="${1:-.}"
DOC_ROOT="$PROJECT_ROOT/.harness/documents"

mode="${2:-text}"
scope="${3:-all}"
if [ ! -d "$DOC_ROOT" ]; then
  [[ "$scope" != mission:* && "$mode" != direct-work-sha ]] || exit 1
  exit 0
fi
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

has_role_notes() {
  if [ "$tier" -lt 2 ]; then
    grep -Eq "${HEADING2}Implementation Notes[[:space:]]*$" "$1"
  else
    has_implementation_notes "$1"
  fi
}

# Preserve the exact body bytes, including trailing spaces and final newline.
direct_work_sha() {
  node - "$1" <<'JS'
const fs = require('fs'), crypto = require('crypto');
const text = fs.readFileSync(process.argv[2], 'utf8');
const heading = /^[ \t]*>?[ \t]*##[ \t]+Direct Work[ \t]*\r?$/m.exec(text);
if (!heading) process.exit(1);
let start = heading.index + heading[0].length;
if (text[start] === '\n') start++;
const rest = text.slice(start);
const next = /^[ \t]*>?[ \t]*#/m.exec(rest);
process.stdout.write(crypto.createHash('sha256').update(rest.slice(0, next ? next.index : rest.length)).digest('hex') + '\n');
JS
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

mission_dirs=""
if [[ "$scope" != mission:* ]]; then
  mission_dirs=$(find "$DOC_ROOT" -type f \( -name 'ceo.md' -o -name 'coo.md' -o -name 'cdo.md' -o -name 'cto.md' -o -name 'cqo.md' -o -name 'ops.md' \) -exec dirname {} \; 2>/dev/null | sort -u)
fi

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

if [[ "$scope" == mission:* ]]; then
  mission_rel="${scope#mission:}"
  case "$mission_rel" in ""|/*|*..*) echo "invalid mission path" >&2; exit 1 ;; esac
  mission_dirs="$(cd "$DOC_ROOT/$mission_rel" 2>/dev/null && pwd -P)" || exit 1
  case "$mission_dirs/" in "$(cd "$DOC_ROOT" && pwd -P)/"*) ;; *) exit 1 ;; esac
  [ -f "$mission_dirs/mission-state.json" ] || exit 1
fi

if [ "$mode" = direct-work-sha ]; then
  [[ "$scope" == mission:* ]] || exit 1
  direct_work_sha "$mission_dirs/cto.md"
  exit $?
fi

while IFS= read -r mission_dir; do
  [ -n "$mission_dir" ] || continue
  [ -d "$mission_dir" ] || continue
  mission_name="${mission_dir#$DOC_ROOT/}"
  tier=2
  if [ -f "$mission_dir/mission-state.json" ]; then
    tier=$(jq -r 'def r: if . == "S" then 0 elif . == "M" then 1 else 2 end;
      [.tier, (.tier_history[]? | .from, .to)] | map(r) | max' "$mission_dir/mission-state.json")
  fi
  if [ -f "$PROJECT_ROOT/.harness/config.json" ]; then
    enabled=$(jq -r 'if .behavior.mission_tiers == null then true else .behavior.mission_tiers end' "$PROJECT_ROOT/.harness/config.json")
    [ "$enabled" != false ] || tier=2
  fi

  ceo_path="$mission_dir/ceo.md"
  if [ -s "$ceo_path" ] && ! has_role_notes "$ceo_path"; then
    violations+=("$mission_name:ceo.md-missing-implementation-notes")
  fi

  if has_legacy_flat_worker_report "$mission_dir"; then
    violations+=("$mission_name:legacy-flat-workers")
  fi

  for cxx in coo cdo cto cqo ops; do
    cxx_path="$mission_dir/$cxx.md"
    [ -s "$cxx_path" ] || continue
    if ! has_role_notes "$cxx_path"; then
      violations+=("$mission_name:$cxx.md-missing-implementation-notes")
    fi
    exempt=false
    if [ "$tier" -eq 0 ] && [[ "$cxx" == cto || "$cxx" == cqo ]]; then
      exempt=true
    elif [ "$cxx" = cto ] && [ -f "$mission_dir/mission-state.json" ] && jq -e 'any(.tier_history[]?; .from == "S" and (.to == "M" or .to == "L"))' "$mission_dir/mission-state.json" >/dev/null; then
      frozen=$(jq -r '[.tier_history[]? | select(.from == "S" and (.to == "M" or .to == "L"))][0].direct_work_sha256 // empty' "$mission_dir/mission-state.json")
      if [ -n "$frozen" ]; then
        current=$(direct_work_sha "$cxx_path") || current=""
        if [ "$current" != "$frozen" ]; then
          violations+=("$mission_name:cto-direct-work-modified-after-upgrade")
        else
          post=$(awk '
            /^[[:space:]]*>?[[:space:]]*##[[:space:]]+Post-Upgrade Work[[:space:]]*$/ { inb=1; next }
            inb && /^[[:space:]]*>?[[:space:]]*#/ { exit }
            inb && /[^[:space:]]/ { sub(/^[[:space:]]*/, ""); print; exit }
          ' "$cxx_path")
          # ponytail: trust the declaration; add git-diff enforcement if abuse is observed.
          if [[ "$post" == none* ]] || { [ -n "$post" ] && has_worker_report "$mission_dir" cto; }; then
            exempt=true
          else
            violations+=("$mission_name:cto-post-upgrade-work-without-worker")
          fi
        fi
      fi
    fi
    if [ "$exempt" != true ] && ! has_worker_report "$mission_dir" "$cxx"; then
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
  if [ "$tier" -ne 0 ] && [ -s "$cqo_path" ] && grep -Eq '\b(ACCEPTED|REJECTED|PASS|FAIL)\b' "$cqo_path" && ! has_worker_report "$mission_dir" "cqo"; then
    violations+=("$mission_name:cqo-verdict-without-evaluator")
  fi
done <<EOF
$mission_dirs
EOF

# Record drift (AGENTS.md Hard Rule 12): a conclusion the session holds but has
# not written into the state file is not held by the company. Measured cost of
# the unreconciled case: a finished step the orchestration loop went on trying
# to spawn 70 times, because only the report knew it was done.
PROGRESS_FILE="$PROJECT_ROOT/.harness/progress.json"
if [ -f "$PROGRESS_FILE" ]; then
  while IFS=$'\t' read -r wname wreport; do
    [ -n "$wname" ] && [ -n "$wreport" ] || continue
    report_abs="$wreport"
    case "$wreport" in /*) ;; *) report_abs="$PROJECT_ROOT/$wreport" ;; esac
    [ -f "$report_abs" ] || continue
    if [[ "$scope" == mission:* ]]; then
      report_abs="$(cd "$(dirname "$report_abs")" && pwd -P)/$(basename "$report_abs")"
      case "$report_abs" in "$mission_dirs/"*) ;; *) continue ;; esac
    fi
    # Section-scoped reading: the Status body may be quoted or indented.
    if awk '
      /^[[:space:]]*>?[[:space:]]*##[[:space:]]+Status[[:space:]]*$/ { inb=1; next }
      inb && /^[[:space:]]*>?[[:space:]]*#/ { inb=0 }
      inb && /COMPLETE/ { found=1 }
      END { exit(found ? 0 : 1) }
    ' "$report_abs" 2>/dev/null; then
      violations+=("state-file:worker-$wname-reported-COMPLETE-but-progress.json-still-running")
    fi
  done < <(jq -r '
    [.company_state.workers[]? | select((.status // "") | test("running|busy"))
     | [(.name // .worker // .feature // "unknown"), (.report // .report_path // .path // "")]]
    | .[] | @tsv' "$PROGRESS_FILE" 2>/dev/null)
fi

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
  echo "CXX worker evidence violation (unknown tier → L):"
  for violation in "${violations[@]}"; do
    mission="${violation%%:*}"
    docs="${violation#*:}"
    echo "- mission: $mission"
    echo "  issue: $docs"
    echo "  required: worker reports under .harness/documents/$mission/{cxx}/workers/{worker-name}.md"
  done
fi

exit 1
