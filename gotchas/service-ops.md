---
docmeta:
  id: service-ops
  title: Gotchas — Service-Ops
  type: intermediate
  createdAt: 2026-05-07T00:00:00Z
  updatedAt: 2026-05-07T00:00:00Z
  source:
    producer: agent
    skillId: harness-dispatcher
  inputs: []
  tags: [gotcha, service-ops, monitor, presence]
---

# Gotchas — Service-Ops

> Dispatcher가 관리. Service-Ops 는 세션 시작 시 이 파일을 읽고 같은 실수를 반복하지 않습니다.

## [G-001] Build/Deploy 진행 중 자리 비움 금지 — monitor 모듈 활성 의무 (status: verified)

- **Why**: Service-Ops 의 monitor 는 cron + red-alert 이벤트로만 spawn 되도록 설계됐으나, generator/evaluator 가 build·flutter test·deploy 를 실행하는 동안에는 cron 주기 사이 공백이 길어 대시보드에서 "SERVICE-OPS 룸 빈 채" 가 관찰됨 (moon_web 2026-05-07). 빌드 stderr 의 WebSocketChannelException, 컴파일 에러, dart analyze warning 을 실시간으로 캐치하지 못하면 이후 evaluator-functional 단계에서야 발견 → 비용 증가.
- **How to apply**:
  - Conductor 가 generator-* 또는 evaluator-functional 을 spawn 하기 **직전**, 동일 tick 에 service-ops/monitor 를 **stream-mode 로 함께 spawn** (handoff-bridge). progress.json.service_ops.monitor.stream_active = true.
  - Stream-mode monitor 의 책임: 자식 프로세스 stdout/stderr 를 tail → 정규식 (`error:|exception|TestFailure|Cannot find|Failed to compile`) 매칭 시 즉시 conductor 에 red-alert 발행.
  - 자식 프로세스 종료 시 stream_active = false + ops-report 짧은 요약 append.
  - Visibility: monitor 활성 동안 progress.json.agents 에 service-ops minifig 가 service-ops 룸 (또는 모니터링 대상 룸 인접) 에 위치하도록 partial update.
- **References**: skills/service-ops/SKILL.md service_ops.monitor 섹션.
