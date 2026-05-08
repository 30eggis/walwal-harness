---
docmeta:
  id: gotchas-conductor
  title: Gotchas — uconductor
  type: input
  createdAt: 2026-05-08T00:00:00Z
  updatedAt: 2026-05-08T00:00:00Z
  source:
    producer: user
    skillId: harness-dispatcher
  inputs: []
  tags: [gotchas, conductor]
---

# Gotchas — uconductor

> Dispatcher 가 관리. uconductor 는 세션 시작 시 이 파일을 읽고 같은 실수를 반복하지 않습니다.
> 
> 항목 형식은 `gotchas/README.md` 참조. Dispatcher 가 사용자의 실수 지적을 감지하면 자동으로
> `### [G-NNN]` 항목을 append 합니다. 사용자가 직접 편집해도 무방합니다.

<!-- 항목이 추가되면 아래에 기록됩니다 -->

### [G-001] Team mode 큐 누락 금지

- Status: verified
- Date: 2026-05-08
- Trigger: `progress.json.mode == "team"` 인데 `.harness/actions/feature-queue.json` 이 없거나 teams 가 모두 idle 인 채 단일 `next_agent` 만 진행
- Rule: Team mode 진입 시 반드시 `scripts/harness-queue-manager.sh init|recover` 로 queue 를 준비하고, `auto-dispatch` 결과의 모든 pair 를 background worker 로 spawn 해야 한다. tmux monitor 만 띄우고 worker spawn 없이 종료하면 실패다.
- Evidence: okx/seller 최신 배포본에서 `mode=team` 이지만 `feature-queue.json` 이 없어 병렬 worker 가 시작될 수 없었다.

### [G-002] Parallel tracks 직렬화 금지

- Status: verified
- Date: 2026-05-08
- Trigger: `tracks.length >= 2` 인 회의 결정 후 첫 트랙만 running, 나머지는 pending 으로 두고 완료 후 다음 트랙을 dispatch
- Rule: parallel tracks 는 같은 tick 에 모든 독립 트랙을 running/spawn 대상으로 노출해야 한다. 완료 순서만 rendezvous 에서 join 하며, dispatch 자체를 sequence 로 만들면 안 된다.
- Evidence: v6.2 fork-join 문서와 달리 conductor 구현/meeting-manager 문구가 “첫 번째 트랙 완료 후 다음 pending” 형태로 남아 있었다.
