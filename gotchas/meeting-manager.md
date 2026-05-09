---
docmeta:
  id: gotchas-meeting-manager
  title: Gotchas — umeeting-umanager
  type: input
  createdAt: 2026-05-08T00:00:00Z
  updatedAt: 2026-05-08T00:00:00Z
  source:
    producer: user
    skillId: harness-dispatcher
  inputs: []
  tags: [gotchas, meeting-manager]
---

# Gotchas — umeeting-umanager

> Dispatcher 가 관리. umeeting-umanager 는 세션 시작 시 이 파일을 읽고 같은 실수를 반복하지 않습니다.
> 
> 항목 형식은 `gotchas/README.md` 참조. Dispatcher 가 사용자의 실수 지적을 감지하면 자동으로
> `### [G-NNN]` 항목을 append 합니다. 사용자가 직접 편집해도 무방합니다.

<!-- 항목이 추가되면 아래에 기록됩니다 -->

### [G-SYS-MINUTES-NOT-OPS-TABLE] 회의록을 Service-Ops 상태표로 대체하지 말 것

- Status: verified
- Date: 2026-05-10
- Trigger: hourly report 또는 meeting record가 서버 health table, queue 상태, "continue loop" 한 줄만 남기고 CEO/COO/CTO/CQO/Service-Ops가 무엇을 논의했는지 보여주지 않음.
- Rule: Meeting-Manager의 산출물은 운영 리포트가 아니라 임원 회의록이다. `## Role Briefs` 또는 `## Required Role Positions`에 Dispatcher/CEO, Planner/COO, CTO, CQO, Service-Ops 전원의 Position/Evidence/Action이 있어야 하며, `## Discussion`, `## Decision JSON`, `## Action Items`가 없으면 회의 완료로 보고하지 않는다.
- Fix: Service-Ops health table은 evidence로만 넣고, 토론과 decision owner/action_type으로 내부 실행 owner를 지정한다.
