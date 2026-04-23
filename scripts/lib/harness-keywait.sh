#!/bin/bash
# harness-keywait.sh — 패널 refresh/quit 키 대기 헬퍼
#
# 사용법:
#   source scripts/lib/harness-keywait.sh
#   while true; do
#     render_panel
#     echo "  [r] refresh  [q] quit"
#     if wait_or_refresh 3; then
#       # 타임아웃 → 일반 주기 리프레시
#       :
#     else
#       # 'r' 키 즉시 리프레시 (반환값 != 0)
#       :
#     fi
#   done
#
# 키 처리:
#   'r' / 'R' / Enter → 즉시 복귀 (return 1 — 강제 리프레시 신호)
#   'q' / 'Q'         → exit 0 (패널 종료)
#   그 외 / 타임아웃  → return 0 (정상 주기 리프레시)
#
# TTY 가 아니면 plain sleep 으로 동작 (Claude Code Bash 도구 등에서도 안전).

wait_or_refresh() {
  local secs="${1:-3}"

  # Non-TTY fallback
  if ! [ -t 0 ]; then
    sleep "$secs"
    return 0
  fi

  local key=""
  # -t: timeout, -n 1: 1글자, -s: 에코 안함
  # read 는 Enter 에서도 타임아웃 전에 즉시 복귀 (빈 키)
  if IFS= read -rsn 1 -t "$secs" key 2>/dev/null; then
    case "$key" in
      q|Q)
        # 커서 복원 후 종료
        tput cnorm 2>/dev/null || true
        clear
        exit 0
        ;;
      r|R|"")
        # 강제 리프레시 시그널
        return 1
        ;;
      *)
        # 기타 키는 무시하고 일반 복귀
        return 0
        ;;
    esac
  fi
  # 타임아웃
  return 0
}
