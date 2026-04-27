#!/bin/bash
# harness-tmux.sh — Unified Harness Studio layout
#
# Team Mode (--team):
# ┌──────────────┬──────────────┬──────────────┐
# │              │              │   TEAM 1     │
# │  Dashboard   │              │              │
# │  (queue +    │  Gotcha &    ├──────────────┤
# │   status +   │  Memory      │   TEAM 2     │
# │   features)  │              │              │
# ├──────────────┤              ├──────────────┤
# │ Archive      │              │   TEAM 3     │
# │ Prompt       │              │              │
# └──────────────┴──────────────┴──────────────┘
# (Archive Prompt는 별도 패널 — Dashboard 모니터링 영역 보호)
#
# Rendering strategy:
#   1. iTerm2 detected → native split panes (no tmux needed)
#   2. tmux available  → tmux session
#   3. Fallback        → open new terminal windows
#
# Usage:
#   bash scripts/harness-tmux.sh [project-root] --team
#   bash scripts/harness-tmux.sh [project-root] --solo
#   bash scripts/harness-tmux.sh [project-root] --team --force-tmux  # skip iTerm2, use tmux
#   bash scripts/harness-tmux.sh --kill

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SESSION_NAME="harness-studio"

PROJECT_ROOT=""
MODE=""
DETACH=false
FORCE_TMUX=false

for arg in "$@"; do
  case "$arg" in
    --team)   MODE="team" ;;
    --solo)   MODE="solo" ;;
    --detach) DETACH=true ;;
    --force-tmux) FORCE_TMUX=true ;;
    --kill)
      tmux kill-session -t "$SESSION_NAME" 2>/dev/null && echo "tmux session killed." || true
      # Also try to close iTerm2 studio tab if exists
      if [ "${TERM_PROGRAM:-}" = "iTerm.app" ]; then
        osascript -e '
          tell application "iTerm2"
            repeat with w in windows
              repeat with t in tabs of w
                if name of current session of t contains "harness-studio" then
                  close t
                end if
              end repeat
            end repeat
          end tell
        ' 2>/dev/null || true
      fi
      echo "Killed."
      exit 0
      ;;
    *)
      if [ -d "$arg" ]; then PROJECT_ROOT="$arg"; fi
      ;;
  esac
done

if [ -z "$PROJECT_ROOT" ]; then
  dir="$(pwd)"
  while [ "$dir" != "/" ]; do
    if [ -d "$dir/.harness" ]; then PROJECT_ROOT="$dir"; break; fi
    dir="$(dirname "$dir")"
  done
fi

if [ -z "$PROJECT_ROOT" ] || [ ! -d "$PROJECT_ROOT/.harness" ]; then
  echo "Error: .harness/ not found."
  exit 1
fi

# Auto-detect mode from progress.json if not specified
if [ -z "$MODE" ]; then
  if command -v jq &>/dev/null && [ -f "$PROJECT_ROOT/.harness/progress.json" ]; then
    MODE=$(jq -r '.mode // "solo"' "$PROJECT_ROOT/.harness/progress.json" 2>/dev/null)
  fi
  MODE="${MODE:-solo}"
fi

echo "Project: $PROJECT_ROOT"
echo "Mode: $MODE"

# ══════════════════════════════════════════
# Strategy 1: iTerm2 native split panes
# ══════════════════════════════════════════
launch_iterm2_team() {
  osascript <<APPLESCRIPT
    tell application "iTerm2"
      activate

      -- Create new window with first session (Prompt History)
      set studioWindow to (create window with default profile)

      tell studioWindow
        tell current session of current tab
          set name to "harness-studio"
          write text "cd '${PROJECT_ROOT}' && bash '${SCRIPT_DIR}/harness-dashboard.sh' '${PROJECT_ROOT}'"

          -- Split down (bottom of Dashboard column) → Archive Prompt
          set archivePane to (split horizontally with default profile)
          tell archivePane
            write text "cd '${PROJECT_ROOT}' && bash '${SCRIPT_DIR}/harness-prompt-history.sh' '${PROJECT_ROOT}'"
          end tell

          -- Split right → Gotcha & Memory (combined view; tmux 경로는 3분할 사용)
          set dashPane to (split vertically with default profile)
          tell dashPane
            write text "cd '${PROJECT_ROOT}' && bash '${SCRIPT_DIR}/harness-gotcha-memory.sh' '${PROJECT_ROOT}'"

            -- Split right → Team 1
            set t1Pane to (split vertically with default profile)
            tell t1Pane
              write text "cd '${PROJECT_ROOT}' && bash '${SCRIPT_DIR}/harness-monitor.sh' '${PROJECT_ROOT}' --team 1"

              -- Split down → Team 2
              set t2Pane to (split horizontally with default profile)
              tell t2Pane
                write text "cd '${PROJECT_ROOT}' && bash '${SCRIPT_DIR}/harness-monitor.sh' '${PROJECT_ROOT}' --team 2"

                -- Split down → Team 3
                set t3Pane to (split horizontally with default profile)
                tell t3Pane
                  write text "cd '${PROJECT_ROOT}' && bash '${SCRIPT_DIR}/harness-monitor.sh' '${PROJECT_ROOT}' --team 3"
                end tell
              end tell
            end tell
          end tell
        end tell
      end tell
    end tell
APPLESCRIPT
}

launch_iterm2_solo() {
  # Solo 레이아웃 (Team 모드와 동일 구조, 우측만 단일 Monitor 패널):
  #   Left col : Dashboard (top) + Prompt History (bottom)
  #   Middle   : Gotcha · Memory · Conventions
  #   Right    : Monitor (lifecycle stream, 단일 에이전트)
  osascript <<APPLESCRIPT
    tell application "iTerm2"
      activate

      set studioWindow to (create window with default profile)

      tell studioWindow
        tell current session of current tab
          set name to "harness-studio"
          write text "cd '${PROJECT_ROOT}' && bash '${SCRIPT_DIR}/harness-dashboard.sh' '${PROJECT_ROOT}'"

          -- Split down (bottom of Dashboard column) → Prompt History
          set archivePane to (split horizontally with default profile)
          tell archivePane
            write text "cd '${PROJECT_ROOT}' && bash '${SCRIPT_DIR}/harness-prompt-history.sh' '${PROJECT_ROOT}'"
          end tell

          -- Split right → Gotcha · Memory · Conventions (combined view; tmux 경로는 3분할)
          set dashPane to (split vertically with default profile)
          tell dashPane
            write text "cd '${PROJECT_ROOT}' && bash '${SCRIPT_DIR}/harness-gotcha-memory.sh' '${PROJECT_ROOT}'"

            -- Split right → Monitor (solo 단일 에이전트 라이프사이클)
            set monPane to (split vertically with default profile)
            tell monPane
              write text "cd '${PROJECT_ROOT}' && bash '${SCRIPT_DIR}/harness-monitor.sh' '${PROJECT_ROOT}'"
            end tell
          end tell
        end tell
      end tell
    end tell
APPLESCRIPT
}

# ══════════════════════════════════════════
# Strategy 2: tmux
# ══════════════════════════════════════════
launch_tmux_team() {
  tmux kill-session -t "$SESSION_NAME" 2>/dev/null || true

  PANE_DASH=$(tmux new-session -d -s "$SESSION_NAME" -c "$PROJECT_ROOT" -x 220 -y 55 -P -F '#{pane_id}')
  PANE_GOTCHA=$(tmux split-window -h -p 70 -t "$PANE_DASH" -c "$PROJECT_ROOT" -P -F '#{pane_id}')
  PANE_T1=$(tmux split-window -h -p 60 -t "$PANE_GOTCHA" -c "$PROJECT_ROOT" -P -F '#{pane_id}' \
    "bash --norc --noprofile -c 'exec bash \"${SCRIPT_DIR}/harness-monitor.sh\" \"${PROJECT_ROOT}\" --team 1'")
  PANE_T2=$(tmux split-window -v -p 66 -t "$PANE_T1" -c "$PROJECT_ROOT" -P -F '#{pane_id}' \
    "bash --norc --noprofile -c 'exec bash \"${SCRIPT_DIR}/harness-monitor.sh\" \"${PROJECT_ROOT}\" --team 2'")
  PANE_T3=$(tmux split-window -v -p 50 -t "$PANE_T2" -c "$PROJECT_ROOT" -P -F '#{pane_id}' \
    "bash --norc --noprofile -c 'exec bash \"${SCRIPT_DIR}/harness-monitor.sh\" \"${PROJECT_ROOT}\" --team 3'")
  # Dashboard 열을 상(Dashboard)/하(Archive Prompt)로 분할 — archive가 길어져도 모니터링 유지
  PANE_ARCHIVE=$(tmux split-window -v -p 35 -t "$PANE_DASH" -c "$PROJECT_ROOT" -P -F '#{pane_id}' \
    "bash --norc --noprofile -c 'exec bash \"${SCRIPT_DIR}/harness-prompt-history.sh\" \"${PROJECT_ROOT}\"'")

  # Gotcha 패널을 3 개 sub-pane 으로 수직 분할: Gotchas / Conventions / Memory
  # 각 pane 은 tmux copy-mode (prefix + [) 로 독립 스크롤 가능
  PANE_CONV=$(tmux split-window -v -p 60 -t "$PANE_GOTCHA" -c "$PROJECT_ROOT" -P -F '#{pane_id}' \
    "bash --norc --noprofile -c 'exec bash \"${SCRIPT_DIR}/harness-gotcha-memory.sh\" \"${PROJECT_ROOT}\" --mode conventions'")
  PANE_MEM=$(tmux split-window -v -p 50 -t "$PANE_CONV" -c "$PROJECT_ROOT" -P -F '#{pane_id}' \
    "bash --norc --noprofile -c 'exec bash \"${SCRIPT_DIR}/harness-gotcha-memory.sh\" \"${PROJECT_ROOT}\" --mode memory'")

  tmux send-keys -t "$PANE_DASH"   "bash \"${SCRIPT_DIR}/harness-dashboard.sh\" \"${PROJECT_ROOT}\"" Enter
  tmux send-keys -t "$PANE_GOTCHA" "bash \"${SCRIPT_DIR}/harness-gotcha-memory.sh\" \"${PROJECT_ROOT}\" --mode gotcha" Enter

  tmux select-pane -t "$PANE_DASH"    -T "Dashboard"
  tmux select-pane -t "$PANE_ARCHIVE" -T "Archive Prompt"
  tmux select-pane -t "$PANE_GOTCHA"  -T "Gotchas (scrollable: prefix + [ )"
  tmux select-pane -t "$PANE_CONV"    -T "Conventions (scrollable: prefix + [ )"
  tmux select-pane -t "$PANE_MEM"     -T "Shared Memory (scrollable: prefix + [ )"
  tmux select-pane -t "$PANE_T1"      -T "TEAM 1"
  tmux select-pane -t "$PANE_T2"      -T "TEAM 2"
  tmux select-pane -t "$PANE_T3"      -T "TEAM 3"
  tmux select-pane -t "$PANE_DASH"

  tmux set-option -t "$SESSION_NAME" pane-border-status top 2>/dev/null || true
  tmux set-option -t "$SESSION_NAME" pane-border-format " #{pane_title} " 2>/dev/null || true
}

launch_tmux_solo() {
  # Solo 레이아웃 (Team 모드와 동일 구조, 우측만 단일 Monitor 패널).
  tmux kill-session -t "$SESSION_NAME" 2>/dev/null || true

  PANE_DASH=$(tmux new-session -d -s "$SESSION_NAME" -c "$PROJECT_ROOT" -x 200 -y 50 -P -F '#{pane_id}')
  PANE_GOTCHA=$(tmux split-window -h -p 70 -t "$PANE_DASH" -c "$PROJECT_ROOT" -P -F '#{pane_id}')
  PANE_MONITOR=$(tmux split-window -h -p 50 -t "$PANE_GOTCHA" -c "$PROJECT_ROOT" -P -F '#{pane_id}' \
    "bash --norc --noprofile -c 'exec bash \"${SCRIPT_DIR}/harness-monitor.sh\" \"${PROJECT_ROOT}\"'")
  PANE_HISTORY=$(tmux split-window -v -p 35 -t "$PANE_DASH" -c "$PROJECT_ROOT" -P -F '#{pane_id}' \
    "bash --norc --noprofile -c 'exec bash \"${SCRIPT_DIR}/harness-prompt-history.sh\" \"${PROJECT_ROOT}\"'")

  # Gotcha 패널을 3 개 sub-pane 으로 수직 분할: Gotchas / Conventions / Memory
  PANE_CONV=$(tmux split-window -v -p 60 -t "$PANE_GOTCHA" -c "$PROJECT_ROOT" -P -F '#{pane_id}' \
    "bash --norc --noprofile -c 'exec bash \"${SCRIPT_DIR}/harness-gotcha-memory.sh\" \"${PROJECT_ROOT}\" --mode conventions'")
  PANE_MEM=$(tmux split-window -v -p 50 -t "$PANE_CONV" -c "$PROJECT_ROOT" -P -F '#{pane_id}' \
    "bash --norc --noprofile -c 'exec bash \"${SCRIPT_DIR}/harness-gotcha-memory.sh\" \"${PROJECT_ROOT}\" --mode memory'")

  tmux send-keys -t "$PANE_DASH"   "bash \"${SCRIPT_DIR}/harness-dashboard.sh\" \"${PROJECT_ROOT}\"" Enter
  tmux send-keys -t "$PANE_GOTCHA" "bash \"${SCRIPT_DIR}/harness-gotcha-memory.sh\" \"${PROJECT_ROOT}\" --mode gotcha" Enter

  tmux select-pane -t "$PANE_DASH"    -T "Dashboard"
  tmux select-pane -t "$PANE_HISTORY" -T "Prompt History"
  tmux select-pane -t "$PANE_GOTCHA"  -T "Gotchas (scrollable: prefix + [ )"
  tmux select-pane -t "$PANE_CONV"    -T "Conventions (scrollable: prefix + [ )"
  tmux select-pane -t "$PANE_MEM"     -T "Shared Memory (scrollable: prefix + [ )"
  tmux select-pane -t "$PANE_MONITOR" -T "Monitor"
  tmux select-pane -t "$PANE_DASH"

  tmux set-option -t "$SESSION_NAME" pane-border-status top 2>/dev/null || true
  tmux set-option -t "$SESSION_NAME" pane-border-format " #{pane_title} " 2>/dev/null || true
}

# ══════════════════════════════════════════
# Dispatch: pick best strategy
# ══════════════════════════════════════════

# Detect iTerm2 — works even from Claude Code's non-TTY Bash
IS_ITERM=false
if [ "${TERM_PROGRAM:-}" = "iTerm.app" ]; then
  IS_ITERM=true
elif [ "$(uname)" = "Darwin" ]; then
  # Check if iTerm2 is running (for non-TTY environments like Claude Code)
  if pgrep -q "iTerm2" 2>/dev/null; then
    IS_ITERM=true
  fi
fi

HAS_TMUX=false
if command -v tmux &>/dev/null; then
  HAS_TMUX=true
fi

# --force-tmux overrides iTerm2 detection
if [ "$FORCE_TMUX" = true ]; then
  if [ "$HAS_TMUX" != true ]; then
    echo "ERROR: --force-tmux specified but tmux not installed. Run: brew install tmux"
    exit 1
  fi
  IS_ITERM=false
fi

if [ "$IS_ITERM" = true ]; then
  echo "Strategy: iTerm2 native split panes"
  if [ "$MODE" = "team" ]; then
    launch_iterm2_team
  else
    launch_iterm2_solo
  fi
  echo "Layout ready"

elif [ "$HAS_TMUX" = true ]; then
  echo "Strategy: tmux"
  if [ "$MODE" = "team" ]; then
    launch_tmux_team
  else
    launch_tmux_solo
  fi

  # Attach to tmux
  if [ "$DETACH" = true ]; then
    echo "Session created. Attach: tmux attach -t $SESSION_NAME"
    echo "Layout ready"
  elif ! tty -s 2>/dev/null; then
    # Non-TTY (e.g., Claude Code Bash tool) — open in new terminal
    if [ "$(uname)" = "Darwin" ]; then
      osascript -e "
        tell application \"Terminal\"
          do script \"tmux attach -t $SESSION_NAME\"
          activate
        end tell
      " 2>/dev/null && echo "OPENED_TERMINAL=true" || echo "Layout ready"
    else
      echo "Session created. Attach: tmux attach -t $SESSION_NAME"
      echo "Layout ready"
    fi
  else
    if [ -n "${TMUX:-}" ]; then
      tmux switch-client -t "$SESSION_NAME"
    else
      echo "Launching Harness Studio ($MODE mode)..."
      tmux attach -t "$SESSION_NAME"
    fi
  fi

else
  echo "ERROR: Neither iTerm2 nor tmux found."
  echo "Install tmux: brew install tmux"
  echo "Or use iTerm2: https://iterm2.com"
  exit 1
fi
