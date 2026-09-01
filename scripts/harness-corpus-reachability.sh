#!/bin/bash
# harness-corpus-reachability.sh — AGENTS.md Hard Rule 11 (reachability clause).
#
# Lazy loading tells a reader to consult only {shared, own-role}. That is a
# PROMISE ABOUT REACHABILITY. Where it is not kept, the rule does not narrow the
# search — it hides the entry: an item can name a role as its audience, be
# indexed, and still be invisible to that reader by the path the rule tells it
# to use. Measured on a live corpus: 69 items, 10 unreachable role-routings,
# 7 of them invisible to a role the item itself named.
#
# The mechanism is mundane and recurs on any install: THE AUTHOR FILES UNDER
# ITSELF. Registration feels complete because the entry is indexed — just not
# where its declared readers look.
#
# Declaring an audience (either form):
#   file-level  (topic files):  <!-- roles: cto, cqo -->
#   entry-level (index files):  - **Roles**: cto, cqo
#
# Usage:
#   harness-corpus-reachability.sh <project-root> [text|json] [--fix]
set -uo pipefail

PROJECT_ROOT="${1:-.}"
MODE="${2:-text}"
FIX="${3:-}"

ROLES="ceo coo cdo cto cqo ops hiring resource-manager brick-office shared"
violations=()
fixed=0

is_index_file() {
  local base="$1"
  case " $ROLES " in *" ${base%.md} "*) return 0 ;; esac
  return 1
}

# Roles this file/entry names as an audience, whitespace-separated, deduped.
#
# A declaration must OWN its line. Anchoring here is what keeps the audit from
# reading its own documentation as data: prose that shows the syntax inline
# (`<!-- roles: cto, cqo -->` inside backticks) is an example, not a routing,
# and counting it makes the audit report holes that do not exist.
declared_roles() {
  {
    grep -oiE '^[[:space:]]*<!--[[:space:]]*roles?:[^>]*-->' "$1" 2>/dev/null | sed -E 's/^[[:space:]]*<!--[[:space:]]*[Rr]oles?:[[:space:]]*//; s/[[:space:]]*-->//'
    grep -oiE '^[[:space:]]*[-*][[:space:]]*\*\*Roles?\*\*:.*' "$1" 2>/dev/null | sed -E 's/.*\*\*[Rr]oles?\*\*:[[:space:]]*//'
  } | tr ',' '\n' | tr -d ' \t' | grep -v '^$' | tr 'A-Z' 'a-z' | sort -u
}

# Does <index> reach <target basename>? Only a real markdown link target counts.
# A bare mention of the filename in prose is not a route a reader can follow,
# and counting it would make the audit report success on exactly the entries it
# exists to find. Matches `](./file.md`, `](file.md`, with or without an anchor.
reaches() {
  local index="$1" target="$2"
  [ -f "$index" ] || return 1
  grep -qF -- "](./$target" "$index" || grep -qF -- "]($target" "$index"
}

audit_dir() {
  local kind="$1" dir="$PROJECT_ROOT/.harness/$1"
  [ -d "$dir" ] || return 0
  local f base host_role roles role index
  for f in "$dir"/*.md; do
    [ -e "$f" ] || continue
    base="$(basename "$f")"
    [ "$base" = "README.md" ] && continue
    # shared.md is read by every role by construction (Hard Rule 11), so an entry
    # living there is already reachable to every audience it could name.
    [ "$base" = "shared.md" ] && continue
    host_role="${base%.md}"
    roles="$(declared_roles "$f")"
    [ -n "$roles" ] || continue
    while IFS= read -r role; do
      [ -n "$role" ] || continue
      # The host file is reachable to its own role by construction.
      if is_index_file "$base" && [ "$role" = "$host_role" ]; then continue; fi
      case " $ROLES " in *" $role "*) ;; *) continue ;; esac
      # Naming `shared` as an audience is satisfied by construction.
      [ "$role" = "shared" ] && continue
      index="$dir/${role}.md"
      if reaches "$index" "$base"; then continue; fi
      if [ "$FIX" = "--fix" ]; then
        [ -f "$index" ] || printf '# %s — %s\n' "${role}" "${kind}" > "$index"
        if ! grep -qF 'Cross-role Links' "$index"; then
          printf '\n## Cross-role Links\n\nItems written elsewhere that name this role as an audience.\n' >> "$index"
        fi
        printf -- '- [%s](./%s) — declares `%s`\n' "${base%.md}" "$base" "$role" >> "$index"
        fixed=$((fixed + 1))
      else
        violations+=("$kind/$base:$role")
      fi
    done <<EOF
$roles
EOF
  done
}

audit_dir conventions
audit_dir gotchas

if [ "$FIX" = "--fix" ]; then
  echo "[corpus-reachability] linked $fixed previously unreachable routing(s)"
  exit 0
fi

if [ "${#violations[@]}" -eq 0 ]; then
  [ "$MODE" = "json" ] && { jq -nc '{ok:true, unreachable:[]}' 2>/dev/null || echo '{"ok":true,"unreachable":[]}'; }
  [ "$MODE" = "text" ] && echo "[corpus-reachability] all declared audiences reachable"
  exit 0
fi

if [ "$MODE" = "json" ]; then
  printf '%s\n' "${violations[@]}" | jq -Rcs '
    split("\n")[:-1]
    | map(capture("(?<item>[^:]+):(?<role>.*)"))
    | {ok:false, unreachable:.}
  '
else
  echo "Corpus reachability violation (AGENTS.md Hard Rule 11):"
  for v in "${violations[@]}"; do
    echo "- item: ${v%%:*}"
    echo "  names role '${v#*:}' as an audience, but ${v#*:}'s index does not reach it"
  done
  echo "  An entry is registered only when every role it names can reach it by the"
  echo "  path that role is told to use. Fix: harness-corpus-reachability.sh <root> text --fix"
fi
exit 1
