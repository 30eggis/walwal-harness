---
docmeta:
  id: gotchas-planner
  title: Gotchas — Planner
  type: input
  createdAt: 2026-04-22T00:00:00Z
  updatedAt: 2026-04-22T00:00:00Z
  source:
    producer: agent
    skillId: harness-dispatcher
  inputs: []
  tags: [gotchas, planner]
---

# Gotchas — Planner

> Dispatcher가 관리. Planner는 세션 시작 시 이 파일을 읽고 같은 실수를 반복하지 않습니다.

<!-- 항목이 추가되면 아래에 기록됩니다 -->

### [G-001] Startup 체크리스트의 루트 CONVENTIONS.md 읽기 스킵
- **Date**: 2026-04-22
- **Status**: unverified
- **TTL**: 2026-05-22
- **Trigger**: "CONVENTIONS.md §FE Evaluator UI Automation Smoke Test 절차가 있는데 왜 무시했냐"
- **Wrong**: `.harness/conventions/planner.md` 와 `shared.md` 가 비어있는 것을 확인하고 "컨벤션 없음" 으로 판단, 루트 `CONVENTIONS.md` 읽기를 생략했다. 결과적으로 plan.md §6 검증 방법을 "flutter_test" 로만 작성.
- **Right**: SKILL.md Startup #2 의 "CONVENTIONS.md (루트) 읽기 — 프로젝트 최상위 원칙 (있을 때만)" 은 **하위 파일이 비어있어도 독립적으로 실행**. 루트 파일이 존재하면 전 조항을 plan/sprint-contract 에 반영.
- **Why**: 하위 스코프 conventions 의 비어있음은 "루트 원칙도 비어있다" 를 의미하지 않는다. 두 파일은 병렬 계층.
- **Scope**: 모든 Planner 세션 시작 시, 그리고 feature-list / plan / sprint-contract 초안 작성 직전.
- **Occurrences**: 1
