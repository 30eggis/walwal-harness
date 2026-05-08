#!/bin/bash
# harness-service-ops-monitor.sh — deterministic Service-Ops production check
#
# Reads .harness/config.json runtime.production.services[] and writes:
#   - progress.json.service_ops.health[]
#   - progress.json.service_ops.monitor.last_check
#   - .harness/actions/ops-report-hourly-<timestamp>.md
#
# This script is intentionally deterministic and does not require an LLM. Claude
# can add analysis later, but the Owner must always have a disk-backed record.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/harness-render-progress.sh"

PROJECT_ROOT="$(resolve_harness_root "${1:-.}")" || exit 0
PROGRESS="$PROJECT_ROOT/.harness/progress.json"
CONFIG="$PROJECT_ROOT/.harness/config.json"
ACTIONS_DIR="$PROJECT_ROOT/.harness/actions"
OPS_DIR="$PROJECT_ROOT/.harness/ops"

[ -f "$PROGRESS" ] || exit 0
[ -f "$CONFIG" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

mkdir -p "$ACTIONS_DIR" "$OPS_DIR"

live=$(jq -r '.runtime.production.live // false' "$CONFIG" 2>/dev/null || echo false)
service_count=$(jq -r '(.runtime.production.services // []) | length' "$CONFIG" 2>/dev/null || echo 0)
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_rel=".harness/actions/ops-report-hourly-${stamp}.md"
report_path="$PROJECT_ROOT/$report_rel"

json_escape() {
  jq -Rn --arg v "$1" '$v'
}

tcp_check() {
  local host="$1"
  local port="$2"
  if command -v nc >/dev/null 2>&1; then
    nc -z -w 2 "$host" "$port" >/dev/null 2>&1
    return $?
  fi
  bash -c ":</dev/tcp/$host/$port" >/dev/null 2>&1
}

http_status() {
  local url="$1"
  if command -v curl >/dev/null 2>&1; then
    curl -s -o /dev/null -m 3 -w "%{http_code}" "$url" 2>/dev/null || echo "000"
  else
    echo "000"
  fi
}

log_summary_json() {
  local log_path="$1"
  if [ -z "$log_path" ] || [ "$log_path" = "null" ]; then
    jq -n '{configured:false, exists:false, recent_errors:0, last_line:null}'
    return
  fi
  if [ ! -f "$log_path" ]; then
    jq -n --arg path "$log_path" '{configured:true, exists:false, path:$path, recent_errors:0, last_line:null}'
    return
  fi
  local recent errors last_line
  recent="$(tail -200 "$log_path" 2>/dev/null || true)"
  errors="$(printf '%s\n' "$recent" | grep -Eic 'error|exception|fatal|panic|traceback|fail' || true)"
  last_line="$(tail -1 "$log_path" 2>/dev/null || true)"
  jq -n --arg path "$log_path" --arg last "$last_line" --argjson errors "${errors:-0}" \
    '{configured:true, exists:true, path:$path, recent_errors:$errors, last_line:$last}'
}

if [ "$live" != "true" ] || [ "${service_count:-0}" -eq 0 ]; then
  jq --arg ts "$ts" --arg report "$report_rel" '
    .service_ops.monitor.last_check = $ts |
    .service_ops.monitor.stream_active = false |
    .service_ops.monitor.last_report = $report |
    .service_ops.health = []
  ' "$PROGRESS" > "${PROGRESS}.tmp" && mv "${PROGRESS}.tmp" "$PROGRESS"

  {
    echo "# Service-Ops Hourly Report"
    echo ""
    echo "- ts: $ts"
    echo "- production.live: $live"
    echo "- services: $service_count"
    echo "- verdict: NO_PRODUCTION_SERVICES"
    echo ""
    echo "No production service endpoints are configured. Owner+CEO+CTO must define runtime.production.services[] before Service-Ops can monitor live servers."
  } > "$report_path"
  echo "$report_rel"
  exit 0
fi

results_file="$(mktemp)"
: > "$results_file"

i=0
while [ "$i" -lt "$service_count" ]; do
  svc="$(jq -c ".runtime.production.services[$i]" "$CONFIG")"
  name="$(jq -r '.name // ("service-" + (input_line_number|tostring))' <<<"$svc")"
  host="$(jq -r '.host // "127.0.0.1"' <<<"$svc")"
  port="$(jq -r '.port // empty' <<<"$svc")"
  health_path="$(jq -r '.health_path // empty' <<<"$svc")"
  expected_status="$(jq -r '.expected_status // 200' <<<"$svc")"
  log_path="$(jq -r '.log_path // empty' <<<"$svc")"

  port_state="unknown"
  if [ -n "$port" ] && tcp_check "$host" "$port"; then
    port_state="listening"
  else
    port_state="down"
  fi

  health_status="null"
  health_ok="null"
  health_url=""
  if [ -n "$health_path" ] && [ "$health_path" != "null" ] && [ -n "$port" ]; then
    health_url="http://${host}:${port}${health_path}"
    health_status="$(http_status "$health_url")"
    if [ "$health_status" = "$expected_status" ]; then health_ok="true"; else health_ok="false"; fi
  fi

  log_json="$(log_summary_json "$log_path")"

  status="ok"
  if [ "$port_state" != "listening" ]; then
    status="down"
  elif [ "$health_ok" = "false" ]; then
    status="degraded"
  elif [ "$(jq -r '.configured and (.exists|not)' <<<"$log_json")" = "true" ]; then
    status="log_missing"
  elif [ "$(jq -r '.recent_errors // 0' <<<"$log_json")" -gt 0 ]; then
    status="warn"
  fi

  jq -n \
    --arg ts "$ts" \
    --arg name "$name" \
    --arg host "$host" \
    --arg port "$port" \
    --arg port_state "$port_state" \
    --arg health_path "$health_path" \
    --arg health_url "$health_url" \
    --arg expected_status "$expected_status" \
    --arg health_status "$health_status" \
    --arg health_ok "$health_ok" \
    --arg status "$status" \
    --argjson log "$log_json" \
    '{
      ts:$ts,
      name:$name,
      host:$host,
      port:($port|tonumber?),
      port_state:$port_state,
      health_path:(if $health_path == "" or $health_path == "null" then null else $health_path end),
      health_url:(if $health_url == "" then null else $health_url end),
      expected_status:($expected_status|tonumber?),
      health_status:(if $health_status == "null" then null else ($health_status|tonumber?) end),
      health_ok:(if $health_ok == "true" then true elif $health_ok == "false" then false else null end),
      log:$log,
      status:$status
    }' >> "$results_file"
  i=$((i + 1))
done

results_json="$(jq -s '.' "$results_file")"
rm -f "$results_file"

down_count="$(jq '[.[] | select(.status == "down" or .status == "degraded")] | length' <<<"$results_json")"
warn_count="$(jq '[.[] | select(.status == "warn" or .status == "log_missing")] | length' <<<"$results_json")"
ok_count="$(jq '[.[] | select(.status == "ok")] | length' <<<"$results_json")"
verdict="OK"
if [ "$down_count" -gt 0 ]; then verdict="INCIDENT"; elif [ "$warn_count" -gt 0 ]; then verdict="WARN"; fi

incidents_json="$(jq '
  [ .[] | select(.status == "down" or .status == "degraded") |
    {
      id: ("OPS-" + (.name | ascii_upcase | gsub("[^A-Z0-9]+";"-"))),
      dept: "Operations",
      severity: (if .status == "down" then "critical" else "high" end),
      message: (.name + " " + .status + " (" + .host + ":" + (.port|tostring) + ")"),
      ts: .ts
    }
  ]' <<<"$results_json")"

jq --arg ts "$ts" --arg report "$report_rel" --argjson health "$results_json" --argjson incidents "$incidents_json" --argjson warn "$warn_count" --argjson alert "$down_count" '
  .service_ops.monitor.stream_active = false |
  .service_ops.monitor.last_check = $ts |
  .service_ops.monitor.last_report = $report |
  .service_ops.monitor.warns_this_sprint = ((.service_ops.monitor.warns_this_sprint // 0) + $warn) |
  .service_ops.monitor.alerts_this_sprint = ((.service_ops.monitor.alerts_this_sprint // 0) + $alert) |
  .service_ops.health = $health |
  .service_ops.incident.open = $incidents
' "$PROGRESS" > "${PROGRESS}.tmp" && mv "${PROGRESS}.tmp" "$PROGRESS"

{
  echo "# Service-Ops Hourly Report"
  echo ""
  echo "- ts: $ts"
  echo "- production.live: true"
  echo "- services: $service_count"
  echo "- verdict: $verdict"
  echo "- ok: $ok_count"
  echo "- warnings: $warn_count"
  echo "- alerts: $down_count"
  echo ""
  echo "| Service | Port | Health | Logs | Status |"
  echo "|---|---:|---|---|---|"
  jq -r '.[] |
    "| \(.name) | \(.host):\(.port) \(.port_state) | " +
    (if .health_path == null then "n/a" else ((.health_status // "000")|tostring) + " expected " + ((.expected_status // 200)|tostring) end) +
    " | " +
    (if (.log.configured|not) then "not configured" elif (.log.exists|not) then "missing" else ((.log.recent_errors|tostring) + " recent errors") end) +
    " | \(.status) |"' <<<"$results_json"
  echo ""
  echo "## Raw"
  echo ""
  echo '```json'
  jq '.' <<<"$results_json"
  echo '```'
} > "$report_path"

echo "$report_rel"
