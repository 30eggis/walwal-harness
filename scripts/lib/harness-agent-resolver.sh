#!/bin/bash
# harness-agent-resolver.sh — canonical feature/phase → harness agent resolver
#
# Worker dispatch must not guess the department when Planner already wrote
# owner_agents/applicable_eval_axes. This resolver is intentionally strict:
# declared metadata wins; keyword fallback is only allowed when metadata is
# absent.

set -uo pipefail

resolve_feature_agent() {
  local project_root="$1" fid="$2" phase="${3:-gen}" pipeline="${4:-FULLSTACK}"
  local features="$project_root/.harness/actions/feature-list.json"

  [ -f "$features" ] || return 2
  command -v jq >/dev/null 2>&1 || return 2

  local feature_json
  feature_json="$(jq -c --arg id "$fid" '.features[]? | select(.id == $id)' "$features" 2>/dev/null | head -1)"
  [ -n "$feature_json" ] && [ "$feature_json" != "null" ] || return 3

  case "$phase" in
    eval|eval:*|evaluation|evaluator-*)
      _resolve_eval_agent "$feature_json" "$phase"
      return $?
      ;;
    *)
      _resolve_generation_agent "$feature_json" "$pipeline"
      return $?
      ;;
  esac
}

_resolve_generation_agent() {
  local feature_json="$1" pipeline="$2"
  local owner_count agent

  owner_count="$(jq '(.owner_agents // []) | length' <<<"$feature_json")"
  if [ "${owner_count:-0}" -gt 0 ]; then
    agent="$(jq -r '
      (.owner_agents // [])
      | map(select(
          . == "generator-backend" or
          . == "generator-frontend" or
          . == "generator-designer" or
          . == "generator-devops"
        ))
      | .[0] // empty
    ' <<<"$feature_json")"
    [ -n "$agent" ] || return 4
    echo "$agent"
    return 0
  fi

  local layer service title text
  layer="$(jq -r '(.layer // .type // "")' <<<"$feature_json")"
  service="$(jq -r '(.service // "")' <<<"$feature_json")"
  title="$(jq -r '(.title // .name // .description // "")' <<<"$feature_json")"
  text="$(printf '%s %s %s' "$layer" "$service" "$title" | tr '[:upper:]' '[:lower:]')"

  case "$text" in
    *frontend*|*ui*|*web*|*react*|*next*) echo "generator-frontend" ;;
    *design*|*token*|*component-spec*) echo "generator-designer" ;;
    *devops*|*infra*|*deploy*|*ci*) echo "generator-devops" ;;
    *)
      if [ "$pipeline" = "FE-ONLY" ]; then echo "generator-frontend"; else echo "generator-backend"; fi
      ;;
  esac
}

_resolve_eval_agent() {
  local feature_json="$1" phase="$2"
  local requested_axis axes_count agent

  requested_axis="${phase#eval:}"
  requested_axis="${requested_axis#evaluator-}"
  [ "$requested_axis" = "$phase" ] && requested_axis=""
  [ "$requested_axis" = "eval" ] && requested_axis=""
  [ "$requested_axis" = "evaluation" ] && requested_axis=""

  axes_count="$(jq '(.applicable_eval_axes // []) | length' <<<"$feature_json")"
  [ "${axes_count:-0}" -gt 0 ] || return 5

  if [ -n "$requested_axis" ]; then
    agent="$(_axis_to_evaluator "$requested_axis")" || return 6
    jq -e --arg agent "$agent" '
      def map_axis:
        if . == "code-quality" or . == "code_quality" or . == "evaluator-code-quality" then "evaluator-code-quality"
        elif . == "functional" or . == "evaluator-functional" then "evaluator-functional"
        elif . == "visual" or . == "evaluator-visual" then "evaluator-visual"
        elif . == "architecture" or . == "evaluator-architecture" then "evaluator-architecture"
        elif . == "security" or . == "evaluator-security" then "evaluator-security"
        else empty end;
      (.applicable_eval_axes // []) | map(map_axis) | index($agent)
    ' <<<"$feature_json" >/dev/null || return 7
    echo "$agent"
    return 0
  fi

  agent="$(jq -r '
    def map_axis:
      if . == "code-quality" or . == "code_quality" or . == "evaluator-code-quality" then "evaluator-code-quality"
      elif . == "functional" or . == "evaluator-functional" then "evaluator-functional"
      elif . == "visual" or . == "evaluator-visual" then "evaluator-visual"
      elif . == "architecture" or . == "evaluator-architecture" then "evaluator-architecture"
      elif . == "security" or . == "evaluator-security" then "evaluator-security"
      else empty end;
    (.applicable_eval_axes // []) | map(map_axis) | .[0] // empty
  ' <<<"$feature_json")"
  [ -n "$agent" ] || return 6
  echo "$agent"
}

_axis_to_evaluator() {
  case "$1" in
    code-quality|code_quality|evaluator-code-quality) echo "evaluator-code-quality" ;;
    functional|evaluator-functional) echo "evaluator-functional" ;;
    visual|evaluator-visual) echo "evaluator-visual" ;;
    architecture|evaluator-architecture) echo "evaluator-architecture" ;;
    security|evaluator-security) echo "evaluator-security" ;;
    *) return 1 ;;
  esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  resolve_feature_agent "${1:-.}" "${2:-}" "${3:-gen}" "${4:-FULLSTACK}"
fi
