---
docmeta:
  id: gotchas-conductor
  title: Gotchas — Conductor (Autonomous Engine)
  type: input
  createdAt: 2026-05-07T00:00:00Z
  updatedAt: 2026-05-07T00:00:00Z
  source:
    producer: agent
    skillId: harness-dispatcher
  inputs:
    - documentId: user-feedback-v6.0.2
      uri: (inline — Owner 의 "잘 워킹하고 있다는 느낌이 들지 않는다" 지적)
      relation: output-from
      sections:
        - sourceRange: { startLine: 1, endLine: 1 }
          targetRange: { startLine: 17, endLine: 60 }
  tags: [gotchas, conductor, autonomy, visibility, ghost-spawn]
---

# Gotchas — Conductor (자율 실행 엔진)

> Conductor 는 walwal-harness 의 손. Dispatcher (CEO) 가 GOAL 을 확정하면 손이 알아서 돌린다. 매 세션 시작 / 매 tick 시 이 파일을 읽고 같은 실수를 반복하지 않는다.

### [G-001] 정의되지 않은 부서를 inline 으로 처리하지 말 것 (M-001 의 Conductor 적용)
- **Date**: 2026-05-07
- **Status**: verified
- **Trigger**: v6.0.2 install 환경에서 Conductor 가 `evaluator-uiux` (정의 X) 를 spawn 하려다 "별도 SKILL 이 없으므로 Conductor 가 직접 검증" 식으로 inline 처리. Owner 가 "잘 워킹하고 있다는 느낌이 들지 않는다" 보고.
- **Wrong**: spawn 대상이 `.claude/skills/harness-<name>/SKILL.md` 에 없을 때 (a) Conductor 가 inline 검증으로 우회 (b) 사용자 모르게 fallback 으로 진행.
- **Right**: spawn 직전 SKILL 존재 검사. 없으면 즉시 escalate:
  ```bash
  bash scripts/harness-progress-set.sh . \
    '.failure = {"agent":"conductor","location":"spawn","message":"unknown agent: evaluator-uiux","retry_target":null} |
     .next_agent = "dispatcher" |
     .agent_status = "blocked"'
  ```
  Dispatcher 가 받아 Owner 에게 "정의되지 않은 부서 호출 시도. 표준 chain (code-quality/functional/visual) 또는 신규 SKILL 등록 필요" 보고.
- **Why**: M-001 ("선언만 된 유령 스킬") 의 Conductor 차원 적용. inline 우회는 (a) 사용자 신뢰 깨짐 (b) audit 흔적 부재 (c) verify 명령으로 catch 불가능.
- **Scope**: 모든 spawn 결정. Tick Loop §5 spawn 결정 트리.

### [G-002] Spawn 핸드오프 시 회의실 활용 (visibility)
- **Date**: 2026-05-07
- **Status**: verified
- **Trigger**: Owner 발화 "CQO/COO/회의실 등에 모이지도 않고…"
- **Wrong**: spawn 핸드오프 시 progress.json 만 갱신하고 `meetings.active` 미사용. dashboard 에서 회의실이 텅 빔.
- **Right**: 핸드오프 직전 from→to 짧은 회의를 시각화:
  ```bash
  # 핸드오프 시작
  bash scripts/harness-progress-set.sh . \
    '.meetings.active = ["dispatcher","planner"] | .meetings.cadence = "handoff"'
  sleep 1.5  # 시각적으로 회의실에 잠깐 모임
  # 실제 spawn
  bash scripts/harness-progress-set.sh . \
    '.meetings.active = [] | .current_agent = "planner" | .agent_status = "running"'
  ```
- **Why**: NEXUS 메타포 — 핸드오프 = 짧은 회의. dashboard 에서 회의실로 두 미니피규어 텔레포트 → 회사가 진짜 일한다는 신뢰.
- **Scope**: 모든 inter-agent 핸드오프.

### [G-003] Visibility Checklist 4 시점 누락 금지 (Inviolable)
- **Date**: 2026-05-07
- **Status**: verified
- **Trigger**: G-002 의 일반화. Conductor 가 매 tick 마다 progress.json 의 4 시점 partial update 를 누락하면 dashboard 가 stale.
- **Wrong**: Conductor 가 spawn → 검증 → 결과 처리 사이에 progress.json 갱신을 잊거나 일부만 함.
- **Right**: 매 tick 의 4 시점에 의무 update (skills/conductor/SKILL.md §0.5 참조):
  1. **tick 시작**: `current_agent="conductor"`, `agent_status="running"`, `conductor.last_tick`, `tick_count++`
  2. **spawn 직전**: `meetings.active=[from,to]`, `meetings.cadence="handoff"` (1~2초)
  3. **spawn 직후**: `meetings.active=[]`, `current_agent="<spawned>"`, `agent_status="running"`
  4. **tick 완료**: `current_agent` 그대로 (다음 에이전트 작업 중) 또는 `null` + `agent_status="completed"`
- **Scope**: 모든 tick 사이클. 1~3 시점 누락 시 dashboard 의 회의실 텔레포트 / 미니피규어 활동 시각화 깨짐.

### [G-005] Team mode 직렬 회귀 금지 — ready ≥ 2 면 병렬 spawn (status: verified)
- **Date**: 2026-05-07
- **Trigger**: Owner 보고 "솔로모드로 만 동작하는것처럼 다중 에이전트 상태가 아님" (moon_web 2026-05-07). progress.json.mode="team" 인데도 Conductor 가 한 번에 한 generator 만 spawn 하고 evaluator 핸드오프도 직렬.
- **Wrong**: Tick 마다 ready 목록에서 1개만 골라 spawn. tmux 의 T1/T2/T3 패널이 비어있어도 무시.
- **Right**: 매 tick 시작 시 ready 목록 (depends_on 충족 + agent_status≠running) 을 계산. mode="team" 이면 **min(ready, 3)** 만큼 동시 spawn — 각 팀 슬롯 (T1/T2/T3) 에 배정 + progress.json.team_state.team_<n>.assigned_feature, .assigned_agent 갱신. 동시 spawn 직전 meetings.active=["t1-lead","t2-lead","t3-lead"] 로 짧은 standup 시각화.
- **Scope**: §4 Tick Loop, §5 Spawn 결정 트리. Solo 모드는 1개 spawn 유지.
- **Why**: Team 자동 결정 룰 (ready≥3, features≥6, depth≤2) 을 만족시켜놓고 직렬로 돌리면 Team mode 가 형식상 활성이지만 실효 없음. 비용 + 시각적 신뢰 모두 낭비.

### [G-006] Build/Deploy 실행 중 service-ops/monitor 동반 spawn (status: verified)
- **Date**: 2026-05-07
- **Trigger**: Owner 보고 "Service ops 는 build/배포 환경 로그 모니터링하면서 에러 캐치해야 하는데 공석". moon_web 빌드 중 `flutter test --platform chrome` 의 WebSocketChannelException 이 stderr 에 흘렀지만 service-ops 룸은 빈 채.
- **Wrong**: generator-frontend / evaluator-functional 이 build·test 명령을 단독 실행. cron 사이 공백 동안 stderr 무감시.
- **Right**: build/test/deploy 를 트리거하는 spawn 직전, 동일 tick 에 service-ops/monitor 를 stream-mode 로 함께 spawn (handoff-bridge). 자식 프로세스 종료 시까지 stream_active=true. 스트림 매칭 정규식 (error|exception|TestFailure|Cannot find|Failed to compile) 시 즉시 red-alert.
- **Scope**: §5 Spawn 결정 트리에 "[generator-* or evaluator-functional spawn 직전] → service-ops/monitor stream-mode 동시 spawn" 라인 추가.

### [G-004] Owner 에게 진행 동의 묻지 말 것 (Dispatcher [G-002] 의 Conductor 적용)
- **Date**: 2026-05-07
- **Status**: verified
- **Trigger**: NEXUS P3 위반 패턴 재발 방지
- **Wrong**: Conductor 가 Eval PASS 후 "다음 sprint 시작할까요?" 같은 질문을 Dispatcher 통해 전달.
- **Right**: PASS → 다음 평가자 chain / sprint advance 자동. FAIL → retry_target 자동 라우팅. 3 회 연속 FAIL / 인시던트 / GOAL 위반 시에만 escalation.
- **Scope**: Tick Loop §6 Escalation 트리거.
