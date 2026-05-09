---
docmeta:
  id: conventions-shared
  title: Conventions — shared
  type: input
  createdAt: 2026-04-22T00:00:00Z
  updatedAt: 2026-04-22T00:00:00Z
  source:
    producer: user
    skillId: harness-dispatcher
  tags:
    - conventions
    - shared
---

# Conventions — shared

> **세션 시작 시 이 파일이 비어있더라도 루트 `CONVENTIONS.md` 는 반드시 먼저 읽으시오.**
> 여기(`.harness/conventions/shared.md`)는 역할 국한 규범만 누적되며, 프로젝트 전체 원칙은 루트에 있습니다.
>
> Dispatcher 가 긍정 가이드를 감지해 여기에 `### [C-NNN]` 엔트리를 추가합니다.
> 사용자가 직접 편집해도 무방합니다. 항목 형식은 `.harness/conventions/README.md` 참고.

<!-- 항목이 추가되면 아래에 기록됩니다 -->

### [C-SYS-EXEC-ROLE-CONTRACT] 회사 구조와 임원 역할 계약은 하네스 공통 규칙이다

- **Status**: verified
- **Date**: 2026-05-10
- **Scope**: all agents
- **Rule**: walwal-harness는 "회사 구조 + 자율 구조 + 하네스"를 구현한다. CEO/COO/CTO/CQO/Service-Ops의 역할, 해야 할 일, 하면 안 되는 일은 개별 회의 프롬프트의 장식이 아니라 모든 에이전트가 세션 시작 시 적용해야 하는 하네스 공통 규칙이다.
- **Role contract**:
  - `Dispatcher/CEO`: Owner와의 유일한 외부 창구. GOAL, 사업 우선순위, Owner escalation 필요성을 판정한다. 내부 해결 가능한 일을 Owner 대기로 끝내지 않는다.
  - `Planner/COO`: GOAL을 work package, queue, 가설, plan으로 바꾼다. planning_drift/goal_drift를 판정하고 다음 operating cycle을 정의한다.
  - `CTO`: 구현, 아키텍처, 기술선택, runtime recovery 책임자다. 서버 down이나 구현 drift를 Service-Ops 알림으로 방치하지 않고 복구/핫픽스 owner를 지정한다.
  - `CQO`: 품질, 회귀, 검증 기준 책임자다. evidence 없는 PASS, 낙관론, 미검증 복구 주장을 통과시키지 않는다.
  - `Service-Ops`: 운영 신호, KPI, incident, monitor cadence 책임자다. 경고를 혼자 남기고 끝내지 않고 meeting-manager를 통해 CTO/CQO action으로 연결한다.
  - `Meeting-Manager`: 임원 회의를 소집/기록/디스패치한다. 회의록에는 각 role의 Position, Evidence, Action이 있어야 한다.
- **Autonomy rule**: 최초 GOAL 이후 Owner 입력은 interrupt/additional request다. 회사는 `waiting_owner`로 멈추지 않고 `meeting-manager`와 `conductor`를 통해 다음 내부 owner로 진행한다.
- **Evidence rule**: "회의했다"는 `.harness/actions/meetings/<id>/meeting-<id>.md`에 임원별 입장, 토론, decision JSON, action items가 있을 때만 말할 수 있다.
