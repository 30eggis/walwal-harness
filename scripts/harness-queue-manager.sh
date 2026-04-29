#!/bin/bash
# harness-queue-manager.sh — Feature Queue Manager (v5 unified)
#
# feature-list.json에서 depends_on 그래프를 읽어 topological sort 후
# feature-queue.json을 생성/관리한다.
#
# Commands:
#   init          feature-list.json → feature-queue.json 초기 생성
#   dequeue <team> ready 큐에서 feature를 꺼내 team에 배정
#   pass <fid>    feature를 passed로 이동, blocked→ready 전이
#   fail <fid>    feature를 failed로 이동
#   requeue <fid> failed feature를 ready로 복귀
#   status        현재 큐 상태 출력
#
# Usage: bash scripts/harness-queue-manager.sh <command> [args...] [project-root]

set -uo pipefail

# ── Resolve project root ──
resolve_root() {
  local dir="${1:-.}"
  dir="$(cd "$dir" 2>/dev/null && pwd || echo "$dir")"
  while [ "$dir" != "/" ]; do
    if [ -d "$dir/.harness" ]; then echo "$dir"; return 0; fi
    dir="$(dirname "$dir")"
  done
  return 1
}

CMD="${1:-status}"
shift || true

# Last arg might be project root
PROJECT_ROOT=""
for arg in "$@"; do
  if [ -d "$arg/.harness" ]; then PROJECT_ROOT="$arg"; fi
done
if [ -z "$PROJECT_ROOT" ]; then
  PROJECT_ROOT="$(resolve_root ".")" || { echo "[queue] .harness/ not found."; exit 1; }
fi

FEATURES="$PROJECT_ROOT/.harness/actions/feature-list.json"
QUEUE="$PROJECT_ROOT/.harness/actions/feature-queue.json"
CONFIG="$PROJECT_ROOT/.harness/config.json"
QUEUE_LOCK="$PROJECT_ROOT/.harness/.queue-lock"

# ── Atomic queue lock — prevent race conditions between teams ──
acquire_queue_lock() {
  local max_wait=30 waited=0
  while ! mkdir "$QUEUE_LOCK" 2>/dev/null; do
    sleep 0.1
    waited=$((waited + 1))
    if [ "$waited" -ge $((max_wait * 10)) ]; then
      rm -rf "$QUEUE_LOCK"
      mkdir "$QUEUE_LOCK" 2>/dev/null || true
      break
    fi
  done
}

release_queue_lock() {
  rm -rf "$QUEUE_LOCK" 2>/dev/null || true
}

# ── Concurrency from config ──
CONCURRENCY=3
if [ -f "$CONFIG" ]; then
  _c=$(jq -r '.flow.team.concurrency // .flow.parallel.concurrency // 3' "$CONFIG" 2>/dev/null)
  if [ "$_c" -gt 0 ] 2>/dev/null; then CONCURRENCY=$_c; fi
fi

# ══════════════════════════════════════════
# init — Build queue from feature-list.json
# Usage: init [sprint_number]
#   sprint_number: optional, filter features by sprint (default: all)
# ══════════════════════════════════════════
cmd_init() {
  local sprint_filter="${1:-all}"

  if [ ! -f "$FEATURES" ]; then
    echo "[queue] feature-list.json not found."
    exit 1
  fi

  # Build dependency graph and topological sort
  # Output: feature-queue.json with ready (no deps) and blocked (has deps)
  jq --argjson concurrency "$CONCURRENCY" --arg sprint "$sprint_filter" '
    # Build passed set (features already passed by evaluator)
    def passed_set:
      [.features[] | select(
        ((.passes // []) | length > 0) and
        ((.passes // []) | any(. == "evaluator-functional"))
      ) | .id] ;

    # Filter features by sprint if specified
    def target_features:
      if $sprint == "all" then .features
      else [.features[] | select((.sprint // 1) == ($sprint | tonumber))]
      end ;

    # Separate ready vs blocked
    def classify(features; passed):
      reduce features[] as $f (
        { ready: [], blocked: {} };
        ($f.depends_on // []) as $deps |
        if ($f.id | IN(passed[])) then .  # already passed, skip
        elif ($deps | length == 0) then
          .ready += [$f.id]
        elif (passed | length > 0) and ($deps | all(. as $d | $d | IN(passed[]))) then
          .ready += [$f.id]  # all deps satisfied
        else
          .blocked[$f.id] = ($deps - passed)
        end
      ) ;

    passed_set as $passed |
    target_features as $targets |
    classify($targets; $passed) as $classified |
    {
      version: "5.0",
      concurrency: $concurrency,
      current_sprint: (if $sprint == "all" then null else ($sprint | tonumber) end),
      queue: {
        ready: $classified.ready,
        blocked: $classified.blocked,
        in_progress: {},
        passed: $passed,
        failed: []
      },
      teams: (
        [range(1; $concurrency + 1)] | map({
          key: (. | tostring),
          value: { status: "idle", feature: null, branch: null, pid: null }
        }) | from_entries
      )
    }
  ' "$FEATURES" > "$QUEUE"

  local ready_count blocked_count passed_count
  ready_count=$(jq '.queue.ready | length' "$QUEUE")
  blocked_count=$(jq '.queue.blocked | length' "$QUEUE")
  passed_count=$(jq '.queue.passed | length' "$QUEUE")

  echo "[queue] Initialized (sprint=$sprint_filter): $ready_count ready, $blocked_count blocked, $passed_count already passed"
  echo "[queue] Concurrency: $CONCURRENCY teams"
}

# ══════════════════════════════════════════
# next-sprint — Auto-advance to next sprint
# Checks if current sprint is complete, loads next sprint features
# ══════════════════════════════════════════
cmd_next_sprint() {
  if [ ! -f "$QUEUE" ]; then echo "[queue] Run 'init' first."; exit 1; fi
  if [ ! -f "$FEATURES" ]; then echo "[queue] feature-list.json not found."; exit 1; fi

  acquire_queue_lock

  local ready in_prog failed
  ready=$(jq '.queue.ready | length' "$QUEUE" 2>/dev/null || echo 0)
  in_prog=$(jq '.queue.in_progress | length' "$QUEUE" 2>/dev/null || echo 0)
  failed=$(jq '.queue.failed | length' "$QUEUE" 2>/dev/null || echo 0)

  # Current sprint still has work
  if [ "$ready" -gt 0 ] || [ "$in_prog" -gt 0 ]; then
    release_queue_lock
    echo "[queue] Current sprint still active: $ready ready, $in_prog in progress"
    return 1
  fi

  # Failed features block advancement
  if [ "$failed" -gt 0 ]; then
    release_queue_lock
    echo "[queue] Cannot advance: $failed failed features. Requeue or fix them first."
    return 1
  fi

  # Find current sprint number
  local current_sprint
  current_sprint=$(jq -r '.current_sprint // 0' "$QUEUE" 2>/dev/null)
  if [ "$current_sprint" = "null" ] || [ "$current_sprint" = "0" ]; then
    # Detect from passed features
    current_sprint=$(jq -r --slurpfile q "$QUEUE" '
      [.features[] | select(.id as $fid | $q[0].queue.passed | index($fid)) | .sprint // 1] | max // 1
    ' "$FEATURES" 2>/dev/null)
  fi

  local next_sprint=$((current_sprint + 1))

  # Check if next sprint features exist
  local next_count
  next_count=$(jq --arg s "$next_sprint" '[.features[] | select((.sprint // 1) == ($s | tonumber))] | length' "$FEATURES" 2>/dev/null)

  if [ "$next_count" -eq 0 ]; then
    release_queue_lock
    echo "[queue] ALL SPRINTS COMPLETE. No Sprint $next_sprint features found."
    echo "[queue] Total passed: $(jq '.queue.passed | length' "$QUEUE")"
    return 0
  fi

  release_queue_lock

  # Re-init with next sprint (preserves passed from previous sprints)
  echo "[queue] Sprint $current_sprint complete! Advancing to Sprint $next_sprint ($next_count features)"
  cmd_init "$next_sprint"
}

# ══════════════════════════════════════════
# dequeue — Assign next ready feature to team
# ══════════════════════════════════════════
cmd_dequeue() {
  local team_id="${1:-}"
  if [ -z "$team_id" ]; then echo "[queue] Usage: dequeue <team_id>"; exit 1; fi
  if [ ! -f "$QUEUE" ]; then echo "[queue] Run 'init' first."; exit 1; fi

  acquire_queue_lock

  local feature
  feature=$(jq -r '.queue.ready[0] // empty' "$QUEUE")

  if [ -z "$feature" ]; then
    release_queue_lock
    echo "[queue] No features in ready queue."
    local in_prog blocked
    in_prog=$(jq '.queue.in_progress | length' "$QUEUE")
    blocked=$(jq '.queue.blocked | length' "$QUEUE")
    if [ "$in_prog" -eq 0 ] && [ "$blocked" -eq 0 ]; then
      echo "[queue] ALL FEATURES COMPLETE."
    fi
    return 1
  fi

  jq --arg fid "$feature" --arg tid "$team_id" '
    .queue.ready -= [$fid] |
    .queue.in_progress[$fid] = { team: ($tid | tonumber), phase: "gen", attempt: 1 } |
    .teams[$tid] = { status: "busy", feature: $fid, branch: ("feature/" + $fid), pid: null }
  ' "$QUEUE" > "${QUEUE}.tmp" && mv "${QUEUE}.tmp" "$QUEUE"

  release_queue_lock
  echo "$feature"
}

# ══════════════════════════════════════════
# pass — Mark feature as passed, unblock dependents
# ══════════════════════════════════════════
cmd_pass() {
  local fid="${1:-}"
  if [ -z "$fid" ]; then echo "[queue] Usage: pass <feature_id>"; exit 1; fi
  if [ ! -f "$QUEUE" ]; then echo "[queue] Run 'init' first."; exit 1; fi

  acquire_queue_lock

  local team_id
  team_id=$(jq -r --arg fid "$fid" '.queue.in_progress[$fid].team // empty' "$QUEUE")

  jq --arg fid "$fid" --arg tid "${team_id:-0}" '
    # Remove from in_progress
    del(.queue.in_progress[$fid]) |

    # Add to passed
    .queue.passed += [$fid] |
    .queue.passed |= unique |

    # Free team
    (if $tid != "0" then
      .teams[$tid] = { status: "idle", feature: null, branch: null, pid: null }
    else . end) |

    # Unblock dependents: for each blocked feature, remove $fid from its deps
    # If deps become empty, move to ready
    .queue.blocked as $blocked |
    reduce ($blocked | keys[]) as $blocked_fid (
      .;
      .queue.blocked[$blocked_fid] -= [$fid] |
      if (.queue.blocked[$blocked_fid] | length) == 0 then
        del(.queue.blocked[$blocked_fid]) |
        .queue.ready += [$blocked_fid]
      else . end
    )
  ' "$QUEUE" > "${QUEUE}.tmp" && mv "${QUEUE}.tmp" "$QUEUE"

  local newly_ready
  newly_ready=$(jq -r '.queue.ready | join(", ")' "$QUEUE")
  release_queue_lock
  echo "[queue] $fid PASSED. Ready: [$newly_ready]"
}

# ══════════════════════════════════════════
# fail — Mark feature as failed
# ══════════════════════════════════════════
cmd_fail() {
  local fid="${1:-}"
  if [ -z "$fid" ]; then echo "[queue] Usage: fail <feature_id>"; exit 1; fi
  if [ ! -f "$QUEUE" ]; then exit 1; fi

  acquire_queue_lock

  local team_id
  team_id=$(jq -r --arg fid "$fid" '.queue.in_progress[$fid].team // empty' "$QUEUE")

  jq --arg fid "$fid" --arg tid "${team_id:-0}" '
    del(.queue.in_progress[$fid]) |
    .queue.failed += [$fid] |
    .queue.failed |= unique |
    (if $tid != "0" then
      .teams[$tid] = { status: "idle", feature: null, branch: null, pid: null }
    else . end)
  ' "$QUEUE" > "${QUEUE}.tmp" && mv "${QUEUE}.tmp" "$QUEUE"

  release_queue_lock
  echo "[queue] $fid FAILED."
}

# ══════════════════════════════════════════
# requeue — Move failed feature back to ready
# ══════════════════════════════════════════
cmd_requeue() {
  local fid="${1:-}"
  if [ -z "$fid" ]; then echo "[queue] Usage: requeue <feature_id>"; exit 1; fi

  acquire_queue_lock

  jq --arg fid "$fid" '
    .queue.failed -= [$fid] |
    .queue.ready += [$fid]
  ' "$QUEUE" > "${QUEUE}.tmp" && mv "${QUEUE}.tmp" "$QUEUE"

  release_queue_lock
  echo "[queue] $fid requeued to ready."
}

# ══════════════════════════════════════════
# update_phase — Update in_progress feature phase/attempt
# ══════════════════════════════════════════
cmd_update_phase() {
  local fid="${1:-}" phase="${2:-}" attempt="${3:-}"
  if [ -z "$fid" ] || [ -z "$phase" ]; then
    echo "[queue] Usage: update_phase <feature_id> <phase> [attempt]"
    exit 1
  fi

  acquire_queue_lock

  local jq_expr
  jq_expr=".queue.in_progress[\"$fid\"].phase = \"$phase\""
  if [ -n "$attempt" ]; then
    jq_expr="$jq_expr | .queue.in_progress[\"$fid\"].attempt = ($attempt | tonumber)"
  fi

  jq "$jq_expr" "$QUEUE" > "${QUEUE}.tmp" && mv "${QUEUE}.tmp" "$QUEUE"
  release_queue_lock
}

# ══════════════════════════════════════════
# status — Print queue state
# ══════════════════════════════════════════
cmd_status() {
  if [ ! -f "$QUEUE" ]; then
    echo "[queue] Not initialized. Run: bash scripts/harness-queue-manager.sh init"
    return
  fi

  local ready blocked in_prog passed failed
  ready=$(jq -r '.queue.ready | length' "$QUEUE")
  blocked=$(jq -r '.queue.blocked | length' "$QUEUE")
  in_prog=$(jq -r '.queue.in_progress | length' "$QUEUE")
  passed=$(jq -r '.queue.passed | length' "$QUEUE")
  failed=$(jq -r '.queue.failed | length' "$QUEUE")
  local total=$((ready + blocked + in_prog + passed + failed))

  echo ""
  echo "  Feature Queue ($passed/$total done)"
  echo "  ─────────────────────────────"
  echo "  Ready:       $ready"
  echo "  Blocked:     $blocked"
  echo "  In Progress: $in_prog"
  echo "  Passed:      $passed"
  echo "  Failed:      $failed"
  echo ""

  # Team status
  local team_count
  team_count=$(jq '.teams | length' "$QUEUE")
  echo "  Teams"
  echo "  ─────────────────────────────"
  for i in $(seq 1 "$team_count"); do
    local t_status t_feature
    t_status=$(jq -r ".teams[\"$i\"].status // \"idle\"" "$QUEUE")
    t_feature=$(jq -r ".teams[\"$i\"].feature // \"—\"" "$QUEUE")
    printf "  Team %d: %-6s %s\n" "$i" "$t_status" "$t_feature"
  done
  echo ""

  # In-progress details
  if [ "$in_prog" -gt 0 ]; then
    echo "  In Progress"
    echo "  ─────────────────────────────"
    jq -r '.queue.in_progress | to_entries[] | "  \(.key): team \(.value.team) — \(.value.phase) (attempt \(.value.attempt))"' "$QUEUE"
    echo ""
  fi
}

# ══════════════════════════════════════════
# recover — Move stale in_progress back to ready (after studio restart)
# ══════════════════════════════════════════
cmd_recover() {
  if [ ! -f "$QUEUE" ]; then echo "[queue] Not initialized."; return; fi

  local stale_count
  stale_count=$(jq '.queue.in_progress | length' "$QUEUE" 2>/dev/null)

  if [ "${stale_count:-0}" -eq 0 ]; then
    echo "[queue] No stale in_progress entries."
    return
  fi

  # Move all in_progress → ready, reset all teams to idle
  jq '
    .queue.ready += [.queue.in_progress | keys[]] |
    .queue.ready |= unique |
    .queue.in_progress = {} |
    .teams |= with_entries(.value = { status: "idle", feature: null, branch: null, pid: null })
  ' "$QUEUE" > "${QUEUE}.tmp" && mv "${QUEUE}.tmp" "$QUEUE"

  echo "[queue] Recovered ${stale_count} stale features back to ready queue."
}

# ══════════════════════════════════════════
# auto-dispatch — Pair all idle teams with ready features in one atomic step.
#   Output: JSON array of {team, feature} on stdout.
#   Atomically moves ready → in_progress + teams[tid] = busy for each pair.
#   Dependencies are already honored (ready queue only holds unblocked features).
# ══════════════════════════════════════════
cmd_auto_dispatch() {
  if [ ! -f "$QUEUE" ]; then echo "[queue] Run 'init' first." >&2; exit 1; fi

  acquire_queue_lock

  local result
  result=$(jq '
    . as $root |
    ($root.teams | to_entries | map(select(.value.status == "idle")) | map(.key)) as $idle |
    ($root.queue.ready) as $ready |
    (if ($idle | length) < ($ready | length) then ($idle | length) else ($ready | length) end) as $n |
    [range(0; $n) | { team: ($idle[.] | tonumber), feature: $ready[.] }] as $pairs |
    (reduce $pairs[] as $p ($root;
      .queue.ready -= [$p.feature] |
      .queue.in_progress[$p.feature] = { team: $p.team, phase: "gen", attempt: 1 } |
      .teams[($p.team | tostring)] = {
        status: "busy",
        feature: $p.feature,
        branch: ("feature/" + $p.feature),
        pid: null
      }
    )) as $updated |
    { state: $updated, pairs: $pairs }
  ' "$QUEUE")

  local new_state pairs
  new_state=$(echo "$result" | jq '.state')
  pairs=$(echo "$result" | jq -c '.pairs')

  # Write updated state
  echo "$new_state" > "${QUEUE}.tmp" && mv "${QUEUE}.tmp" "$QUEUE"

  release_queue_lock

  # Emit pairs (single JSON line) for caller
  echo "$pairs"
}

# ══════════════════════════════════════════
# idle-slots — Report how many teams are idle + how many ready features wait.
#   No state mutation. Useful for dashboards / quick checks.
# ══════════════════════════════════════════
cmd_idle_slots() {
  if [ ! -f "$QUEUE" ]; then echo "[queue] Run 'init' first." >&2; exit 1; fi
  jq '{
    idle_teams: [.teams | to_entries[] | select(.value.status == "idle") | .key],
    ready_features: .queue.ready,
    dispatchable: (
      (if ([.teams | to_entries[] | select(.value.status == "idle") | .key] | length) <
          (.queue.ready | length)
        then [.teams | to_entries[] | select(.value.status == "idle") | .key] | length
        else .queue.ready | length
      end)
    )
  }' "$QUEUE"
}

# ── Rate-Limit Hold checkpoint (v5.6.7+) ──
CHECKPOINT="$PROJECT_ROOT/.harness/actions/team-checkpoint.json"

cmd_hold() {
  # Args: <reason> [retry_seconds=600]
  local reason="${1:-rate_limit}"
  local retry_secs="${2:-600}"
  local now_iso retry_iso
  now_iso="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  retry_iso="$(date -u -v+"${retry_secs}"S +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
              || date -u -d "+${retry_secs} seconds" +%Y-%m-%dT%H:%M:%SZ)"
  acquire_queue_lock
  trap release_queue_lock EXIT
  local in_progress pending
  in_progress="$(jq '[.teams[] | select(.current_feature != null) |
                     {team: .team_id, feature: .current_feature, phase: (.current_phase // "gen")}]' "$QUEUE")"
  pending="$(jq '[.features[] | select(.status == "ready") | .id]' "$QUEUE")"
  local tmp="${CHECKPOINT}.tmp"
  jq -n --arg ts "$now_iso" --arg retry "$retry_iso" --arg reason "$reason" \
        --argjson inprog "$in_progress" --argjson ready "$pending" \
        '{timestamp:$ts, retry_at:$retry, last_error:$reason,
          in_progress:$inprog, ready_features:$ready,
          hold_count: 1, escalate_after: 72}' > "$tmp" && mv "$tmp" "$CHECKPOINT"
  release_queue_lock
  trap - EXIT
  echo "[hold] checkpoint written — retry_at=$retry_iso reason=$reason"
}

cmd_resume_probe() {
  # Lightweight probe — called on ScheduleWakeup resume.
  # Exits 0 if ready to resume, 1 if still held, 2 if escalated.
  [ ! -f "$CHECKPOINT" ] && { echo "[resume] no checkpoint — nothing to resume"; exit 0; }
  local hold_count escalate_after
  hold_count="$(jq -r '.hold_count // 1' "$CHECKPOINT")"
  escalate_after="$(jq -r '.escalate_after // 72' "$CHECKPOINT")"
  if [ "$hold_count" -ge "$escalate_after" ]; then
    echo "[resume] ESCALATED — held $hold_count cycles (max=$escalate_after). Manual intervention required."
    exit 2
  fi
  # Probe: minimal claude call — if rate-limited, exits non-zero quickly.
  if command -v claude >/dev/null 2>&1; then
    if echo "ping" | timeout 30 claude -p "reply only: pong" >/dev/null 2>&1; then
      echo "[resume] probe OK — clearing hold"
      rm -f "$CHECKPOINT"
      exit 0
    fi
  fi
  # Still held — increment and report
  local tmp="${CHECKPOINT}.tmp"
  jq '.hold_count = (.hold_count + 1) | .last_probe_at = now | todate' "$CHECKPOINT" > "$tmp" && mv "$tmp" "$CHECKPOINT"
  echo "[resume] still held (cycle $((hold_count+1))/$escalate_after) — schedule another wake-up"
  exit 1
}

# ══════════════════════════════════════════
# enqueue — Append feature to feature-list.json AND insert into queue (canonical path).
#
# Lead 가 ad-hoc 핫픽스 / 새 sprint feature 를 추가할 때 jq 로 큐를 직접 편집하면
# feature-list.json 과 큐가 갈라진다 (실제 사고: F-716, F-800~F-806 이 큐에만 등록).
# 이 명령은 feature-list append → queue insert (deps 미해소면 blocked) 를 한 트랜잭션으로 처리.
#
# Usage: enqueue <feature-json-file>   # 파일 경로
#        enqueue -                     # stdin 으로 JSON
#
# 입력 JSON 최소 필드: {id, title, sprint, depends_on?, layer?, service?, acceptance_criteria?}
# ══════════════════════════════════════════
cmd_enqueue() {
  local input="${1:-}"
  if [ -z "$input" ]; then
    echo "[queue] enqueue: feature JSON 파일 경로 또는 '-' (stdin) 필요" >&2
    exit 1
  fi
  if [ ! -f "$FEATURES" ]; then echo "[queue] feature-list.json not found." >&2; exit 1; fi
  if [ ! -f "$QUEUE" ]; then echo "[queue] feature-queue.json not found. init 먼저." >&2; exit 1; fi

  local feat_json
  if [ "$input" = "-" ]; then
    feat_json=$(cat)
  else
    feat_json=$(cat "$input")
  fi

  if ! echo "$feat_json" | jq -e '.id and .title and .sprint' >/dev/null 2>&1; then
    echo "[queue] enqueue: id/title/sprint 필수 필드 누락" >&2
    exit 1
  fi

  local fid
  fid=$(echo "$feat_json" | jq -r '.id')

  acquire_queue_lock

  if jq -e --arg id "$fid" '.features[] | select(.id == $id)' "$FEATURES" >/dev/null 2>&1; then
    release_queue_lock
    echo "[queue] enqueue: $fid 이 feature-list.json 에 이미 존재" >&2
    exit 1
  fi

  if jq -e --arg id "$fid" '
    ($id | IN(.queue.ready[]?,.queue.passed[]?)) or
    (.queue.in_progress[$id]?) or (.queue.blocked[$id]?) or
    (.queue.failed[$id]? // (.queue.failed | type == "array" and ($id | IN(.queue.failed[]?))))
  ' "$QUEUE" >/dev/null 2>&1; then
    release_queue_lock
    echo "[queue] enqueue: $fid 이 큐에 이미 존재" >&2
    exit 1
  fi

  local tmp_features="${FEATURES}.tmp.$$"
  if ! jq --argjson new "$feat_json" '.features += [$new]' "$FEATURES" > "$tmp_features" 2>/dev/null; then
    rm -f "$tmp_features"; release_queue_lock
    echo "[queue] enqueue: feature-list.json 업데이트 실패" >&2; exit 1
  fi
  mv "$tmp_features" "$FEATURES"

  local deps unmet
  deps=$(echo "$feat_json" | jq -c '.depends_on // []')
  unmet=$(jq --argjson d "$deps" '
    ($d - (.queue.passed // [])) | length
  ' "$QUEUE" 2>/dev/null || echo 0)

  local tmp_queue="${QUEUE}.tmp.$$"
  if [ "${unmet:-0}" -gt 0 ]; then
    jq --arg id "$fid" --argjson deps "$deps" '.queue.blocked[$id] = $deps' "$QUEUE" > "$tmp_queue" 2>/dev/null
  else
    jq --arg id "$fid" '.queue.ready += [$id]' "$QUEUE" > "$tmp_queue" 2>/dev/null
  fi
  if [ ! -s "$tmp_queue" ]; then
    rm -f "$tmp_queue"; release_queue_lock
    echo "[queue] enqueue: feature-queue.json 업데이트 실패" >&2; exit 1
  fi
  mv "$tmp_queue" "$QUEUE"

  release_queue_lock

  if [ "${unmet:-0}" -gt 0 ]; then
    echo "[queue] enqueue: $fid → blocked (unmet deps: ${unmet})"
  else
    echo "[queue] enqueue: $fid → ready"
  fi
}

# ══════════════════════════════════════════
# integrity — feature-list ↔ queue divergence 검사.
# 큐에 있지만 feature-list 에 없는 feature ID 를 출력. 0건이면 종료코드 0.
# ══════════════════════════════════════════
cmd_integrity() {
  if [ ! -f "$FEATURES" ] || [ ! -f "$QUEUE" ]; then
    echo "[integrity] feature-list 또는 feature-queue 없음"
    exit 0
  fi
  local orphans
  orphans=$(jq -r --slurpfile q "$QUEUE" '
    ([.features[].id]) as $fl |
    (($q[0].queue.ready // []) +
     ($q[0].queue.passed // []) +
     (($q[0].queue.failed // []) | if type == "object" then keys else . end) +
     (($q[0].queue.in_progress // {}) | keys) +
     (($q[0].queue.blocked // {}) | keys)) as $qids |
    ($qids - $fl) | unique | .[]
  ' "$FEATURES" 2>/dev/null)

  if [ -z "$orphans" ]; then
    echo "[integrity] OK — feature-list ↔ queue 동기화됨"
    exit 0
  fi
  echo "[integrity] ⚠ feature-list 에 없는 queue-only feature 발견:"
  echo "$orphans" | sed 's/^/  - /'
  echo "[integrity] 복구 방법:"
  echo "  1) Planner 가 해당 feature 를 feature-list.json 에 sprint 지정해서 추가하거나"
  echo "  2) bash scripts/harness-queue-manager.sh enqueue <feature.json>  로 canonical path 사용"
  exit 1
}

cmd_hold_status() {
  if [ ! -f "$CHECKPOINT" ]; then
    echo '{"held":false}'
    return
  fi
  jq '. + {held:true}' "$CHECKPOINT"
}

# ── Dispatch ──
case "$CMD" in
  init)           cmd_init "$@" ;;
  dequeue)        cmd_dequeue "$@" ;;
  auto-dispatch)  cmd_auto_dispatch ;;
  idle-slots)     cmd_idle_slots ;;
  pass)           cmd_pass "$@" ;;
  fail)           cmd_fail "$@" ;;
  requeue)        cmd_requeue "$@" ;;
  update_phase)   cmd_update_phase "$@" ;;
  recover)        cmd_recover ;;
  next-sprint)    cmd_next_sprint ;;
  status)         cmd_status ;;
  hold)           cmd_hold "$@" ;;
  resume-probe)   cmd_resume_probe ;;
  hold-status)    cmd_hold_status ;;
  enqueue)        cmd_enqueue "$@" ;;
  integrity)      cmd_integrity ;;
  *)
    echo "Usage: harness-queue-manager.sh <init|dequeue|auto-dispatch|idle-slots|pass|fail|requeue|recover|next-sprint|update_phase|status|hold|resume-probe|hold-status|enqueue|integrity> [args]"
    exit 1
    ;;
esac
