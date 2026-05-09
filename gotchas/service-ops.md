---
docmeta:
  id: gotchas-service-ops
  title: Gotchas — uservice-uops
  type: input
  createdAt: 2026-05-08T00:00:00Z
  updatedAt: 2026-05-08T00:00:00Z
  source:
    producer: user
    skillId: harness-dispatcher
  inputs: []
  tags: [gotchas, service-ops]
---

# Gotchas — uservice-uops

> Dispatcher 가 관리. uservice-uops 는 세션 시작 시 이 파일을 읽고 같은 실수를 반복하지 않습니다.
> 
> 항목 형식은 `gotchas/README.md` 참조. Dispatcher 가 사용자의 실수 지적을 감지하면 자동으로
> `### [G-NNN]` 항목을 append 합니다. 사용자가 직접 편집해도 무방합니다.

<!-- 항목이 추가되면 아래에 기록됩니다 -->

### [G-SYS-ALERT-MUST-BECOME-MEETING-ACTION] 운영 경고를 혼자 남기고 끝내지 말 것

- Status: verified
- Date: 2026-05-10
- Trigger: Service-Ops가 서버 down, health fail, KPI drift를 감지했지만 ops-report만 쓰고 CTO/CQO/Meeting-Manager action으로 연결하지 않음.
- Rule: Service-Ops의 경고는 최종 산출물이 아니라 회의 evidence다. red-alert/down/degraded가 있으면 incident-war-room 또는 followup-review를 요구하고, CTO runtime-recovery action과 CQO evidence gate가 회의록에 남도록 해야 한다.
- Fix: `.service_ops.incident.open[]`, ops-report path, health table을 evidence로 제출하고 `.meetings.requested_type`/`.meetings.requested_reason` 또는 meeting decision을 통해 다음 owner를 지정한다.
