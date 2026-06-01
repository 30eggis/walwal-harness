#!/bin/bash
# harness-wake-control.sh — per-project hourly-wake launchd control, keyed by HARNESS_BASE_PORT.
#
# The perpetual operating loop (Mode 1) relies on the hourly launchd wake to
# resume cycles across sessions. This gives the dashboard a deterministic,
# per-project on/off handle: the launchd job Label is anchored to the project's
# HARNESS_BASE_PORT (e.g. com.walwal.harness-wake.43000), so each project's wake
# daemon is uniquely addressable and independently toggleable.
#
# launchd periodic jobs are StartInterval execs, not listening daemons, so there
# is no TCP port to bind — the base-port-keyed Label IS the fixed control id.
#
# Usage (all print JSON status except `label`):
#   harness-wake-control.sh status <project-root>
#   harness-wake-control.sh on     <project-root> [--dry-run]
#   harness-wake-control.sh off    <project-root>
#   harness-wake-control.sh label  <project-root>

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WAKE_SH="$SCRIPT_DIR/harness-wake.sh"
INSTALL_SH="$SCRIPT_DIR/harness-wake-install.sh"
CMD="${1:-status}"
PROJECT_ROOT="${2:-$PWD}"
PROJECT_ROOT="$(cd "$PROJECT_ROOT" 2>/dev/null && pwd || echo "$PROJECT_ROOT")"
DRYRUN=0
[ "${3:-}" = "--dry-run" ] && DRYRUN=1

LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
LOG_DIR="$HOME/.walwal-harness/logs"
PROJECTS_LIST="$HOME/.walwal-harness/projects.list"
STATE_DIR="$PROJECT_ROOT/.harness/runtime"
GLOBAL_LABEL="com.walwal.harness-wake"
DOMAIN="gui/$(id -u 2>/dev/null || echo 0)"

command -v jq >/dev/null 2>&1 || { echo '{"supported":false,"error":"jq required"}'; exit 0; }

resolve_base_port() {
  local p=""
  if [ -f "$PROJECT_ROOT/.env" ]; then
    p=$(grep -E '^[[:space:]]*HARNESS_BASE_PORT=' "$PROJECT_ROOT/.env" 2>/dev/null | tail -1 | cut -d= -f2 | tr -dc '0-9')
  fi
  if [ -z "$p" ] && [ -f "$PROJECT_ROOT/.harness/config.json" ]; then
    p=$(jq -r '.runtime.ports.base // empty' "$PROJECT_ROOT/.harness/config.json" 2>/dev/null | tr -dc '0-9')
  fi
  echo "$p"
}

BASE_PORT="$(resolve_base_port)"
if [ -n "$BASE_PORT" ]; then KEY="$BASE_PORT"; else KEY="p$(printf '%s' "$PROJECT_ROOT" | cksum | cut -d' ' -f1)"; fi
LABEL="$GLOBAL_LABEL.$KEY"
PLIST="$LAUNCH_AGENTS_DIR/$LABEL.plist"

supported() { [ "$(uname 2>/dev/null)" = "Darwin" ] && command -v launchctl >/dev/null 2>&1; }
is_loaded() { launchctl print "$DOMAIN/$1" >/dev/null 2>&1; }
in_global_list() { [ -f "$PROJECTS_LIST" ] && grep -Fxq "$PROJECT_ROOT" "$PROJECTS_LIST" 2>/dev/null; }

# XML-escape values interpolated into the plist (paths may contain & < > " ').
xml_escape() {
  printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g' -e "s/'/\&apos;/g"
}

write_plist() { # path
  mkdir -p "$(dirname "$1")"
  local e_label e_wake e_out e_err e_path e_root
  e_label="$(xml_escape "$LABEL")"
  e_wake="$(xml_escape "$WAKE_SH")"
  e_out="$(xml_escape "$LOG_DIR/wake.$KEY.stdout.log")"
  e_err="$(xml_escape "$LOG_DIR/wake.$KEY.stderr.log")"
  e_path="$(xml_escape "$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin")"
  e_root="$(xml_escape "$PROJECT_ROOT")"
  cat > "$1" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$e_label</string>
    <key>ProgramArguments</key>
    <array><string>/bin/bash</string><string>$e_wake</string></array>
    <key>StartInterval</key><integer>3600</integer>
    <key>RunAtLoad</key><true/>
    <key>StandardOutPath</key><string>$e_out</string>
    <key>StandardErrorPath</key><string>$e_err</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key><string>$e_path</string>
        <key>WALWAL_HARNESS_PROJECTS</key><string>$e_root</string>
    </dict>
</dict>
</plist>
PL
}

write_state() { # enabled-bool
  mkdir -p "$STATE_DIR"
  jq -n --arg label "$LABEL" --arg plist "$PLIST" --arg base "$BASE_PORT" --arg key "$KEY" \
        --arg root "$PROJECT_ROOT" --argjson enabled "$1" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
    {label:$label, plist:$plist, key:$key,
     base_port:($base | if . == "" then null else (tonumber? // .) end),
     project_root:$root, enabled:$enabled, updated_at:$now}' \
    > "$STATE_DIR/wake-control.json" 2>/dev/null || true
}

status_json() {
  local sup="false" pp="false" gl="false" ing="false" eff="false" plx="false"
  supported && sup="true"
  if supported; then
    is_loaded "$LABEL" && pp="true"
    is_loaded "$GLOBAL_LABEL" && gl="true"
  fi
  in_global_list && ing="true"
  [ -f "$PLIST" ] && plx="true"
  if [ "$pp" = "true" ] || { [ "$gl" = "true" ] && [ "$ing" = "true" ]; }; then eff="true"; fi
  jq -nc \
    --argjson supported "$sup" --argjson enabled "$eff" \
    --argjson per_project_loaded "$pp" --argjson global_loaded "$gl" --argjson in_global_list "$ing" \
    --argjson plist_exists "$plx" \
    --arg label "$LABEL" --arg key "$KEY" --arg plist "$PLIST" --arg root "$PROJECT_ROOT" \
    --arg base "$BASE_PORT" '
    {supported:$supported, enabled:$enabled,
     per_project_loaded:$per_project_loaded, global_loaded:$global_loaded, in_global_list:$in_global_list,
     plist_exists:$plist_exists, label:$label, key:$key, plist:$plist, project_root:$root,
     base_port:($base | if . == "" then null else (tonumber? // .) end),
     interval_seconds:3600}'
}

case "$CMD" in
  label) echo "$LABEL" ;;
  status) status_json ;;
  on)
    if ! supported; then status_json; exit 0; fi
    if [ "$DRYRUN" = "1" ]; then write_plist "$STATE_DIR/$LABEL.plist.preview"; write_state true; status_json; exit 0; fi
    write_plist "$PLIST"
    launchctl bootout "$DOMAIN/$LABEL" >/dev/null 2>&1 || launchctl unload "$PLIST" >/dev/null 2>&1 || true
    launchctl bootstrap "$DOMAIN" "$PLIST" >/dev/null 2>&1 || launchctl load "$PLIST" >/dev/null 2>&1 || true
    # per-project job is authoritative; drop from the legacy global list to avoid double-wake.
    [ -x "$INSTALL_SH" ] && bash "$INSTALL_SH" remove "$PROJECT_ROOT" >/dev/null 2>&1 || true
    write_state true
    status_json
    ;;
  off)
    if ! supported; then status_json; exit 0; fi
    launchctl bootout "$DOMAIN/$LABEL" >/dev/null 2>&1 || launchctl unload "$PLIST" >/dev/null 2>&1 || true
    rm -f "$PLIST"
    [ -x "$INSTALL_SH" ] && bash "$INSTALL_SH" remove "$PROJECT_ROOT" >/dev/null 2>&1 || true
    write_state false
    status_json
    ;;
  *) echo '{"error":"usage: status|on|off|label <project-root> [--dry-run]"}' >&2; exit 2 ;;
esac
