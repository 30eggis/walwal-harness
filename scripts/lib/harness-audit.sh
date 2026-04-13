#!/bin/bash
# harness-audit.sh — Audit log 헬퍼
#
# 라이프사이클: Planner 시작 → Eval 통과 (1 sprint cycle)
# 새 Planner/Dispatcher 사이클 시작 시 이전 로그는 archive로 이동.
#
# 사용법:
#   source scripts/lib/harness-audit.sh
#   audit_log "gen-backend" "develop" "start" "apps/service-user/" "User 서비스 CRUD 구현"
#   audit_log "eval-func"   "review"  "complete" "POST /api/auth" "FAIL: 409→400 contract 불일치"
#   audit_log "gen-backend" "handoff" "start" "→eval-functional" ""

AUDIT_LOG_FILE=""

# ─────────────────────────────────────────
# init_audit — audit.log 경로 설정 + 헤더 생성
# Args: $1 = project root
# ─────────────────────────────────────────
init_audit() {
  local project_root="${1:-.}"
  AUDIT_LOG_FILE="$project_root/.harness/actions/audit.log"

  # 디렉토리 보장
  mkdir -p "$(dirname "$AUDIT_LOG_FILE")"
}

# ─────────────────────────────────────────
# reset_audit — 새 사이클 시작 시 로그 초기화
# 이전 로그가 있으면 archive로 이동
# Args: $1 = project root, $2 = sprint number (optional)
# ─────────────────────────────────────────
reset_audit() {
  local project_root="${1:-.}"
  local sprint_num="${2:-0}"
  init_audit "$project_root"

  # 기존 로그가 있으면 archive로 이동
  if [ -f "$AUDIT_LOG_FILE" ] && [ -s "$AUDIT_LOG_FILE" ]; then
    local archive_dir="$project_root/.harness/archive"
    mkdir -p "$archive_dir"
    local ts
    ts=$(date +%Y%m%d_%H%M%S)
    mv "$AUDIT_LOG_FILE" "$archive_dir/audit_s${sprint_num}_${ts}.log"
  fi

  # 새 로그 헤더
  cat > "$AUDIT_LOG_FILE" <<HEADER
# Harness Audit Log
# Cycle started: $(date -u +%Y-%m-%dT%H:%M:%SZ)
# Format: TIMESTAMP | AGENT | ACTION | STATUS | TARGET | DETAIL
#─────────────────────────────────────────────────────────────────────────
HEADER
}

# ─────────────────────────────────────────
# audit_log — 로그 엔트리 추가
#
# Args:
#   $1 = agent     (planner, gen-backend, gen-frontend, eval-func, eval-visual)
#   $2 = action    (develop, review, handoff, plan, gate)
#   $3 = status    (start, complete, fail, skip)
#   $4 = target    (파일 경로, 엔드포인트, 에이전트명 등)
#   $5 = detail    (설명, 결과 등)
# ─────────────────────────────────────────
audit_log() {
  if [ -z "$AUDIT_LOG_FILE" ] || [ ! -f "$AUDIT_LOG_FILE" ]; then
    return 0  # audit 미초기화 시 silent pass
  fi

  local agent="${1:-unknown}"
  local action="${2:-unknown}"
  local log_status="${3:-unknown}"
  local target="${4:-}"
  local detail="${5:-}"
  local ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  # 고정폭 포맷
  printf "%-20s | %-14s | %-8s | %-8s | %-30s | %s\n" \
    "$ts" "$agent" "$action" "$log_status" "$target" "$detail" >> "$AUDIT_LOG_FILE"
}

# ─────────────────────────────────────────
# audit_handoff — 핸즈오프 기록 (편의 함수)
# Args: $1=from_agent, $2=to_agent, $3=status(start|complete)
# ─────────────────────────────────────────
audit_handoff() {
  audit_log "$1" "handoff" "$3" "→${2}" ""
}

# ─────────────────────────────────────────
# audit_gate — 게이트 체크 기록 (편의 함수)
# Args: $1=gate_name, $2=status(pass|fail), $3=detail
# ─────────────────────────────────────────
audit_gate() {
  audit_log "system" "gate" "$2" "$1" "$3"
}

# ─────────────────────────────────────────
# render_audit — audit.log를 읽기 좋게 출력
# Args: $1 = project root (optional)
# ─────────────────────────────────────────
render_audit() {
  local project_root="${1:-.}"
  local log_file="$project_root/.harness/actions/audit.log"

  if [ ! -f "$log_file" ]; then
    echo "  (audit log not yet created)"
    return 0
  fi

  cat "$log_file"
}
