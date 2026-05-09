---
docmeta:
  id: gotchas-dispatcher
  title: Gotchas — udispatcher
  type: input
  createdAt: 2026-05-08T00:00:00Z
  updatedAt: 2026-05-08T00:00:00Z
  source:
    producer: user
    skillId: harness-dispatcher
  inputs: []
  tags: [gotchas, dispatcher]
---

# Gotchas — udispatcher

> Dispatcher 가 관리. udispatcher 는 세션 시작 시 이 파일을 읽고 같은 실수를 반복하지 않습니다.
> 
> 항목 형식은 `gotchas/README.md` 참조. Dispatcher 가 사용자의 실수 지적을 감지하면 자동으로
> `### [G-NNN]` 항목을 append 합니다. 사용자가 직접 편집해도 무방합니다.

<!-- 항목이 추가되면 아래에 기록됩니다 -->

### [G-001] Owner GOAL 반복 확인 질문 금지

- Status: verified
- Date: 2026-05-08
- Trigger: Owner 가 이미 GOAL 을 명시했거나 `.harness/actions/pipeline.json`, `.harness/actions/goals.md`, `AGENTS.md Active dispatch` 중 하나가 현재 목표를 설명하는데도 “어떤 방식으로 진행할까요”, “다음 단계로 갈까요”, “브레인스토밍할까요”를 반복 질문
- Rule: GOAL 이 존재하면 합리적 해석으로 회사 루프를 진행한다. 질문은 GOAL 자체가 상호 배타적인 두 방향으로 해석되어 자동 선택이 위험할 때 한 번만 허용한다.
- Evidence: okx/seller에서 Owner가 목표를 준 뒤에도 같은 성격의 확인 질문이 3회 반복되어 “알아서 동작하는 회사” 모델을 깨뜨렸다.

### [G-SYS-ROLE-CONTRACT-NOT-PROMPT-ONLY] 역할 계약을 일회성 프롬프트에만 넣지 말 것

- Status: verified
- Date: 2026-05-10
- Trigger: CEO/COO/CTO/CQO/Service-Ops가 각자 해야 할 일과 금지 사항을 이해하지 못하는데, 이를 개별 wake prompt나 회의 템플릿에만 임시로 적어 하위 에이전트에 자동 적용되지 않음.
- Rule: 회사 구조, 자율 구조, 역할별 해야 할 일/하면 안 되는 일은 하네스 공통 convention/gotcha/memory에 들어가야 한다. 개별 프롬프트는 이 SoT를 읽게 해야 하며, SoT 자체를 대체하면 안 된다.
- Fix: 구조적 규칙은 `conventions/shared.md`, 역할별 실수는 `gotchas/<role>.md`, 모든 에이전트 공통 교훈은 `memory.md`에 시스템 entry로 승격한다.
