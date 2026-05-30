#!/bin/bash
# harness-service-ops-monitor.sh — deterministic Service-Ops production check
#
# Reads .env plus .harness/config.json runtime.build.commands[] and
# runtime.production.services[] and writes:
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

ENV_FILE="$PROJECT_ROOT/.env"
env_base_port=""
if [ -f "$ENV_FILE" ]; then
  env_base_port="$(grep -E '^HARNESS_BASE_PORT=[0-9]' "$ENV_FILE" 2>/dev/null | tail -1 | cut -d= -f2- | tr -d '"' || true)"
fi
config_base_port="$(jq -r 'if .runtime.ports.base == null then "" else (.runtime.ports.base|tostring) end' "$CONFIG" 2>/dev/null || true)"
base_port="${env_base_port:-$config_base_port}"

if [ -z "$base_port" ]; then
  echo "ERROR: HARNESS_BASE_PORT is not set." >&2
  echo "" >&2
  echo "  CEO/CXX must choose an available {xx}000 base port and add it to .env:" >&2
  echo "    HARNESS_BASE_PORT=3000" >&2
  echo "" >&2
  echo "  OPS cannot monitor ports without a declared base. Set the value and re-run." >&2
  exit 1
fi

range_size="$(jq -r '.runtime.ports.range_size // 1000' "$CONFIG" 2>/dev/null || echo 1000)"
range_max=$((base_port + range_size - 1))

build_live=$(jq -r '.runtime.build.live // false' "$CONFIG" 2>/dev/null || echo false)
build_count=$(jq -r '(.runtime.build.commands // []) | length' "$CONFIG" 2>/dev/null || echo 0)
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

port_drift() {
  local port="$1"
  if [ -z "$port" ] || [ "$port" = "null" ]; then
    echo "missing"
  elif [ "$port" -lt "$base_port" ] || [ "$port" -gt "$range_max" ]; then
    echo "outside_base_range"
  else
    echo "ok"
  fi
}

build_results_file="$(mktemp)"
: > "$build_results_file"
if [ "$build_live" = "true" ] && [ "${build_count:-0}" -gt 0 ]; then
  b=0
  while [ "$b" -lt "$build_count" ]; do
    cmd_cfg="$(jq -c ".runtime.build.commands[$b]" "$CONFIG")"
    name="$(jq -r '.name // ("build-" + (input_line_number|tostring))' <<<"$cmd_cfg")"
    cwd="$(jq -r '.cwd // "."' <<<"$cmd_cfg")"
    command_text="$(jq -r '.command // empty' <<<"$cmd_cfg")"
    expected_port="$(jq -r '.expected_port // empty' <<<"$cmd_cfg")"
    log_path="$(jq -r '.log_path // empty' <<<"$cmd_cfg")"
    owner="$(jq -r '.owner // "cto"' <<<"$cmd_cfg")"
    drift="$(port_drift "$expected_port")"

    port_state="not_configured"
    if [ -n "$expected_port" ]; then
      if tcp_check "127.0.0.1" "$expected_port"; then port_state="listening"; else port_state="down"; fi
    fi

    log_json="$(log_summary_json "$log_path")"
    status="ok"
    if [ "$drift" != "ok" ]; then
      status="port_drift"
    elif [ -n "$expected_port" ] && [ "$port_state" != "listening" ]; then
      status="down"
    elif [ "$(jq -r '.configured and (.exists|not)' <<<"$log_json")" = "true" ]; then
      status="log_missing"
    elif [ "$(jq -r '.recent_errors // 0' <<<"$log_json")" -gt 0 ]; then
      status="warn"
    fi

    jq -n \
      --arg ts "$ts" \
      --arg name "$name" \
      --arg cwd "$cwd" \
      --arg command "$command_text" \
      --arg expected_port "$expected_port" \
      --arg owner "$owner" \
      --arg port_state "$port_state" \
      --arg port_drift "$drift" \
      --arg status "$status" \
      --argjson log "$log_json" \
      '{
        ts:$ts,
        name:$name,
        cwd:$cwd,
        command:$command,
        expected_port:(if $expected_port == "" or $expected_port == "null" then null else ($expected_port|tonumber?) end),
        owner:$owner,
        port_state:$port_state,
        port_drift:$port_drift,
        log:$log,
        status:$status
      }' >> "$build_results_file"
    b=$((b + 1))
  done
fi
build_results_json="$(jq -s '.' "$build_results_file")"
rm -f "$build_results_file"

if [ "$live" != "true" ] || [ "${service_count:-0}" -eq 0 ]; then
  jq --arg ts "$ts" --arg report "$report_rel" --argjson build "$build_results_json" '
    .service_ops.monitor.last_check = $ts |
    .service_ops.monitor.stream_active = false |
    .service_ops.monitor.last_report = $report |
    .service_ops.build = $build |
    .service_ops.health = [] |
    .service_ops.incident.open = [] |
    .service_ops.incident.signature = "" |
    .service_ops.incident.repeat_count = 0 |
    .service_ops.incident.recovery_required = false |
    .service_ops.incident.partial_recovery = false |
    .service_ops.incident.close_candidate = false |
    .service_ops.incident.closed = false |
    .service_ops.incident.last_seen_at = $ts
  ' "$PROGRESS" > "${PROGRESS}.tmp" && mv "${PROGRESS}.tmp" "$PROGRESS"

  {
    echo "# Service-Ops Hourly Report"
    echo ""
    echo "- ts: $ts"
    echo "- production.live: $live"
    echo "- build.live: $build_live"
    echo "- base_port: $base_port"
    echo "- services: $service_count"
    echo "- build_commands: $build_count"
    echo "- verdict: NO_PRODUCTION_SERVICES"
    echo ""
    echo "## Build Environments"
    echo ""
    echo "| Build | Command | Expected Port | Logs | Status |"
    echo "|---|---|---:|---|---|"
    jq -r '.[] |
      "| \(.name) | `\(.command)` | " +
      ((.expected_port // "n/a")|tostring) + " " + .port_state + " " + .port_drift +
      " | " +
      (if (.log.configured|not) then "not configured" elif (.log.exists|not) then "missing" else ((.log.recent_errors|tostring) + " recent errors") end) +
      " | \(.status) |"' <<<"$build_results_json"
    echo ""
    echo "No production service endpoints are configured. CEO+CTO+OPS must derive runtime.production.services[] from repo config, scripts, running processes, Docker, logs, or CXX reports before OPS can monitor live servers. Escalate to Owner only for external authority such as missing credentials or unavailable production access."
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
  environment="$(jq -r '.environment // "unknown"' <<<"$svc")"
  host="$(jq -r '.host // "127.0.0.1"' <<<"$svc")"
  port="$(jq -r '.port // empty' <<<"$svc")"
  health_path="$(jq -r '.health_path // empty' <<<"$svc")"
  expected_status="$(jq -r '.expected_status // 200' <<<"$svc")"
  log_path="$(jq -r '.log_path // empty' <<<"$svc")"
  owner="$(jq -r '.owner // "cto"' <<<"$svc")"
  source="$(jq -r '.source // "owner-provided"' <<<"$svc")"
  drift="$(port_drift "$port")"

  port_state="unknown"
  if [ -z "$port" ] || [ "$port" = "null" ]; then
    port_state="not_configured"
  elif tcp_check "$host" "$port"; then
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
  if [ "$drift" != "ok" ]; then
    status="port_drift"
  elif [ "$port_state" != "listening" ]; then
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
    --arg environment "$environment" \
    --arg host "$host" \
    --arg port "$port" \
    --arg port_state "$port_state" \
    --arg health_path "$health_path" \
    --arg health_url "$health_url" \
    --arg expected_status "$expected_status" \
    --arg health_status "$health_status" \
    --arg health_ok "$health_ok" \
    --arg status "$status" \
    --arg owner "$owner" \
    --arg source "$source" \
    --arg port_drift "$drift" \
    --argjson log "$log_json" \
    '{
      ts:$ts,
      name:$name,
      environment:$environment,
      host:$host,
      port:(if $port == "" or $port == "null" then null else ($port|tonumber?) end),
      port_state:$port_state,
      health_path:(if $health_path == "" or $health_path == "null" then null else $health_path end),
      health_url:(if $health_url == "" then null else $health_url end),
      expected_status:($expected_status|tonumber?),
      health_status:(if $health_status == "null" then null else ($health_status|tonumber?) end),
      health_ok:(if $health_ok == "true" then true elif $health_ok == "false" then false else null end),
      log:$log,
      owner:$owner,
      source:$source,
      port_drift:$port_drift,
      status:$status
    }' >> "$results_file"
  i=$((i + 1))
done

results_json="$(jq -s '.' "$results_file")"
rm -f "$results_file"

down_count="$(jq '[.[] | select(.status == "down" or .status == "degraded" or (.status == "port_drift" and .port_drift != "missing"))] | length' <<<"$results_json")"
warn_count="$(jq '[.[] | select(.status == "warn" or .status == "log_missing" or (.status == "port_drift" and .port_drift == "missing"))] | length' <<<"$results_json")"
ok_count="$(jq '[.[] | select(.status == "ok")] | length' <<<"$results_json")"
build_warn_count="$(jq '[.[] | select(.status != "ok")] | length' <<<"$build_results_json")"
verdict="OK"
if [ "$down_count" -gt 0 ]; then verdict="INCIDENT"; elif [ "$warn_count" -gt 0 ] || [ "$build_warn_count" -gt 0 ]; then verdict="WARN"; fi

incidents_json="$(jq '
  [ .[] | select(.status == "down" or .status == "degraded" or (.status == "port_drift" and .port_drift != "missing")) |
    {
      id: ("OPS-" + (.name | ascii_upcase | gsub("[^A-Z0-9]+";"-"))),
      dept: "Operations",
      severity: (if .status == "down" then "critical" else "high" end),
      message: (.name + " " + .status + " (" + .environment + " " + .host + ":" + (.port|tostring) + ")"),
      ts: .ts
    }
  ]' <<<"$results_json")"
incident_signature="$(jq -r '[.[].id] | sort | join(",")' <<<"$incidents_json")"
prev_signature="$(jq -r '(.service_ops.incident.signature // "") as $s | if $s != "" then $s else ([.service_ops.incident.open[]?.id] | sort | join(",")) end' "$PROGRESS" 2>/dev/null || echo "")"
prev_repeat="$(jq -r '.service_ops.incident.repeat_count // 0' "$PROGRESS" 2>/dev/null || echo 0)"
repeat_count=0
if [ -n "$incident_signature" ]; then
  if [ -n "$prev_signature" ] && [ "${prev_repeat:-0}" -lt 1 ]; then
    prev_repeat=1
  fi
  if [ "$incident_signature" = "$prev_signature" ]; then
    repeat_count=$((prev_repeat + 1))
  else
    repeat_count=1
  fi
fi
recovery_required=false
if [ "$repeat_count" -ge 2 ]; then
  recovery_required=true
fi
partial_recovery=false
close_candidate=false
if [ "$ok_count" -gt 0 ] && [ "$down_count" -gt 0 ]; then
  partial_recovery=true
elif [ "$down_count" -eq 0 ] && [ "$warn_count" -eq 0 ]; then
  close_candidate=true
fi

jq --arg ts "$ts" --arg report "$report_rel" --arg signature "$incident_signature" --argjson repeat "$repeat_count" --argjson recovery "$recovery_required" --argjson partial "$partial_recovery" --argjson close_candidate "$close_candidate" --argjson build "$build_results_json" --argjson health "$results_json" --argjson incidents "$incidents_json" --argjson warn "$warn_count" --argjson alert "$down_count" '
  .service_ops.monitor.stream_active = false |
  .service_ops.monitor.last_check = $ts |
  .service_ops.monitor.last_report = $report |
  .service_ops.monitor.warns_this_sprint = ((.service_ops.monitor.warns_this_sprint // 0) + $warn) |
  .service_ops.monitor.alerts_this_sprint = ((.service_ops.monitor.alerts_this_sprint // 0) + $alert) |
  .service_ops.build = $build |
  .service_ops.health = $health |
  .service_ops.incident.open = $incidents |
  .service_ops.incident.signature = $signature |
  .service_ops.incident.repeat_count = $repeat |
  .service_ops.incident.recovery_required = $recovery |
  .service_ops.incident.partial_recovery = $partial |
  .service_ops.incident.close_candidate = $close_candidate |
  .service_ops.incident.closed = (if $close_candidate then true else false end) |
  .service_ops.incident.last_seen_at = $ts
' "$PROGRESS" > "${PROGRESS}.tmp" && mv "${PROGRESS}.tmp" "$PROGRESS"

{
  echo "# Service-Ops Hourly Report"
  echo ""
  echo "- ts: $ts"
  echo "- production.live: true"
  echo "- build.live: $build_live"
  echo "- base_port: $base_port"
  echo "- services: $service_count"
  echo "- build_commands: $build_count"
  echo "- verdict: $verdict"
  echo "- ok: $ok_count"
  echo "- warnings: $warn_count"
  echo "- alerts: $down_count"
  echo "- incident_signature: ${incident_signature:-none}"
  echo "- repeat_count: $repeat_count"
  echo "- recovery_required: $recovery_required"
  echo "- partial_recovery: $partial_recovery"
  echo "- close_candidate: $close_candidate"
  echo ""
  echo "## Build Environments"
  echo ""
  echo "| Build | Command | Expected Port | Logs | Status |"
  echo "|---|---|---:|---|---|"
  jq -r '.[] |
    "| \(.name) | `\(.command)` | " +
    ((.expected_port // "n/a")|tostring) + " " + .port_state + " " + .port_drift +
    " | " +
    (if (.log.configured|not) then "not configured" elif (.log.exists|not) then "missing" else ((.log.recent_errors|tostring) + " recent errors") end) +
    " | \(.status) |"' <<<"$build_results_json"
  echo ""
  echo "## Service Environments"
  echo ""
  echo "| Service | Env | Port | Health | Logs | Status |"
  echo "|---|---|---:|---|---|---|"
  jq -r '.[] |
    "| \(.name) | \(.environment) | \(.host):" + ((.port // "n/a")|tostring) + " \(.port_state) \(.port_drift) | " +
    (if .health_path == null then "n/a" else ((.health_status // "000")|tostring) + " expected " + ((.expected_status // 200)|tostring) end) +
    " | " +
    (if (.log.configured|not) then "not configured" elif (.log.exists|not) then "missing" else ((.log.recent_errors|tostring) + " recent errors") end) +
    " | \(.status) |"' <<<"$results_json"
  echo ""
  echo "## Raw"
  echo ""
  echo '```json'
  jq -n --argjson build "$build_results_json" --argjson services "$results_json" '{build:$build, services:$services}'
  echo '```'
} > "$report_path"

echo "$report_rel"
