---
docmeta:
  id: doctrine-nexus
  title: Walwal-Harness Operational Doctrine (NEXUS-Adapted)
  type: output
  createdAt: 2026-05-07T00:00:00Z
  updatedAt: 2026-05-07T00:00:00Z
  source:
    producer: agent
    skillId: harness-dispatcher
  inputs:
    - documentId: agency-agents-strategy
      uri: https://github.com/msitarzewski/agency-agents/tree/main/strategy
      relation: output-from
      note: NEXUS 프레임워크(EXECUTIVE-BRIEF, nexus-strategy, playbooks, coordination, runbooks)에서 사상·구조 흡수, walwal-harness 조직도(Dispatcher/Conductor/Meeting-Manager/Planner/CTO/CQO/Service-Ops)에 맞게 재해석
      sections:
        - sourceRange: { startLine: 1, endLine: 1 }
          targetRange: { startLine: 1, endLine: 999 }
  tags: [doctrine, nexus, harness, phase-b]
---

<!--
Source attribution: https://github.com/msitarzewski/agency-agents (MIT License)
This document adapts the NEXUS strategy framework to walwal-harness organizational chart.
NEXUS's 9-division × 7-phase model is translated to our CEO/COO/CTO/CQO + Conductor/Meeting-Manager/Service-Ops structure.
-->

# Walwal-Harness Operational Doctrine

> "하나의 하네스 = 하나의 회사. 사용자는 대표(Owner). Dispatcher는 그 회사의 CEO이자 유일한 대화 창구."

## 1. Foundational Principles (NEXUS-Adapted)

### P1. Handoff is the highest-leverage intervention
NEXUS 발견: 멀티에이전트 프로젝트의 73%가 핸드오프 경계에서 실패. 표준화된 핸드오프 양식과 컨텍스트 연속성이 가장 큰 효과.
→ walwal-harness 적용: `sprint-contract.md` + `meeting-<id>.md` 통합 양식이 모든 부서간 전환의 정문.

### P2. Evidence-zero ⇒ Score-zero
"Fantasy approval"(증거 없는 A+ 평가) 방지. CQO/Eval은 default-to-FAIL 자세 + 증거(스크린샷/로그/E2E 출력) 없으면 점수 0.
→ 우리 v3.2 "Evidence 없는 Score = 0점 강제" 규칙과 정확히 일치.

### P3. Continuous Loop > End-of-Pipeline
배치 검증보다 Gen↔Eval 연속 루프가 95% 결함을 통합 전 차단.
→ Conductor가 이 루프를 자율 실행. 사용자 펌프 없음.

### P4. Parallel Workstreams compress 40~60%
Core/Quality/Brand/Growth 4트랙 병렬 = 16주 프로젝트에서 4~8주 단축.
→ 우리 Team Mode(병렬 3팀)·sprint Phase 모드의 사상적 근거.

### P5. Phase Gate Governance
Phase 전환은 All-Hands(Phase Gate) Meeting에서 승인. 통과 못한 Phase는 진입 금지.

## 2. Lifecycle — 7 Phases

agency-agents/strategy/playbooks/phase-{0..6} 흡수. 각 phase는 Planner(COO)의 모드로 매핑.

| Phase | NEXUS 명 | walwal Planner 모드 | 주요 부서 | 종료 게이트 |
|---|---|---|---|---|
| 0 | Discovery | `planner.discovery` | CEO·COO·Research(옵트인) | GOAL 초안 + 도메인 감지 완료 |
| 1 | Strategy | `planner.strategy` | CEO·COO·CTO | feature-list draft + IA-MAP |
| 2 | Foundation | `planner.foundation` | CTO팀(BE·FE·Designer·DevOps) | 스캐폴드·스택 확정·api-contract draft |
| 3 | Build | `planner.build` | Gen ↔ Eval (Conductor 가동) | Sprint별 PASS ≥ 2.80 누적 |
| 4 | Hardening | `planner.hardening` | CQO 5축 + Service-Ops | Eval-Security/Arch/Visual/Func/CQ 모두 PASS |
| 5 | Launch | `planner.launch` | DevOps + Service-Ops | 배포·헬스체크·Rollback 리허설 |
| 6 | Operate | `planner.operate` | Service-Ops + Auto-Retro | 정기 Standup + Sprint Review 사이클 정착 |

`progress.json.phase` 필드 추가. Phase 전환은 항상 Phase Gate Meeting을 통과해야 함.

## 3. Organization (확정)

```
Owner (사용자)
  ↕ (단일 대화 창구)
Dispatcher = CEO  ── 부서 식별 · GOAL 협의 · escalation 보고
  ├─ Conductor          (자율 실행: Gen↔Eval↔Ops 루프)
  └─ Meeting-Manager    (동기화: cron + event 회의)
        ↓
   Planner = COO + HR   (Sprint·AC·인선·온보딩)
        ↓
  ┌─────┴────────┬──────────────┐
  CTO            CQO            Service-Ops
  (Gen 총괄)    (Eval 총괄)     (운용·모니터·인시던트)
  ├ Gen-BE      ├ Eval-Functional
  ├ Gen-FE      ├ Eval-Visual
  ├ Designer    ├ Eval-CodeQuality
  └ DevOps      ├ Eval-Architecture
                └ Eval-Security
```

### 권한 매트릭스 (요약)
- **Owner ↔ Dispatcher만** 직접 대화. 다른 부서는 Owner와 직접 대화 X (escalation 시 Dispatcher 경유).
- **GOAL 작성**: CEO 단독 권한, CTO와 협의로 구체화.
- **Sprint·AC 작성**: Planner(COO) 단독.
- **api-contract.json·AGENTS.md 쓰기**: Planner 단독.
- **코드 쓰기**: 해당 영역 Generator만 (BE/FE/Designer/DevOps).
- **PASS/FAIL 판정**: 해당 Evaluator만, CQO가 cross-validate.
- **자율 실행 spawn**: Conductor 단독.
- **회의 소집**: Meeting-Manager 단독.
- **운영 리포트 → CTO 핸드오프**: Service-Ops 단독.

## 4. Handoff Protocol (NEXUS handoff-templates 흡수)

모든 부서간 핸드오프는 다음 양식 중 하나:

### H-1. Sprint Handoff (Planner → Generator)
- `feature-list.json` (Executable AC 포함)
- `sprint-contract.md` (BE/FE 섹션)
- `api-contract.json` (변경 시)

### H-2. Eval Result (Generator → Evaluator → Generator)
- `evaluation-<feature>.md` (rubric 점수 + Evidence)
- PASS ≥ 2.80 → 다음 Feature, FAIL → 같은 Generator 리라우팅 + 피드백

### H-3. Cross-Eval Validation (Eval ↔ Eval, CQO 중재)
- 두 Eval 의견 충돌 시 CQO가 Reality Check 수행

### H-4. Spec Change Request (Eval → Planner via Spec Review Meeting)
- 발신 Eval이 `## Change Request` 섹션 첨부 → Spec Review 소집

### H-5. Ops Report (Service-Ops → CTO)
- `ops-report-<ts>.md` (GOAL adherence + 권장 수정안 + 우선순위)
- CTO가 Hotfix Feature로 변환 → Planner 등록

### H-6. Escalation (any → Dispatcher → Owner)
- 3회 연속 FAIL / 승인 필요 / GOAL 위반 / 인시던트 P0~P1
- Dispatcher는 Owner에게 1회 보고 + 의사결정 요청

### H-7. Phase Gate (All-Hands Meeting)
- 전 부서 사전 prep → All-Hands → CEO 승인 → Phase 전환

## 5. Continuous Loop (Conductor 자율 실행)

```
loop:
  state = read(progress.json)
  next  = decide_next(state)        # planner | gen-* | eval-* | meeting | ops
  if next == "spawn-meeting":
      Meeting-Manager.convene(...)
  else:
      spawn(next, context=handoff_package(state))
  result = collect(next)
  write_progress(result)
  if escalation_needed(result):
      Dispatcher.report_to_owner(result)
      pause until Owner reply
  else:
      continue
```

- **3회 FAIL 룰**: 같은 Feature·Eval 축에서 3회 연속 FAIL → 자동 escalation.
- **GOAL adherence < 0.7**: 즉시 Spec Review Meeting 소집.
- **인시던트 red-alert**: 즉시 Incident War Room.

## 6. Meeting Cadence (적응형)

| 모드 | Standup 주기 | 진입 조건 |
|---|---|---|
| `light` | 30m | 활성 Sprint + Service-Ops 이벤트율 < 1/h |
| `normal` | 1h | 기본 |
| `heavy` | 4h | idle / 배포 후 안정기 |

전환은 Service-Ops가 직전 3회 standup의 `goal_adherence`·`event_count`로 자동 결정. Owner는 `/meeting-cadence light|normal|heavy` 로 수동 override 가능.

## 7. Evidence Rubric (CQO 강화)

NEXUS Reality Checker 패턴 흡수. 모든 Eval 점수는 다음 증거 중 1개 이상 필수:

| Eval 축 | 필수 증거 |
|---|---|
| Functional | E2E 실행 로그 + AC 매핑표 |
| Visual | 스크린샷 + 디자인 토큰 일치 비교 |
| CodeQuality | tsc/eslint/test 통과 출력 + diff stat |
| Architecture | 의존 그래프 + 결합도 측정 |
| Security | SAST/DAST 출력 + OWASP 체크리스트 매핑 |

증거 없으면 해당 축 0점 + Evaluator 자신이 FAIL 받음.

## 8. Scenario Runbooks (NEXUS runbooks 흡수)

Dispatcher는 첫 발화에서 다음 4종 중 자동 매칭:

| Runbook | 트리거 키워드 예시 | 부서 편성 |
|---|---|---|
| **Startup MVP** (4~6주) | "MVP", "프로토", "스타트업" | BE·FE·Designer + Eval-Func/Visual + DevOps |
| **Enterprise Feature** | "기존 시스템에 추가", "엔터프라이즈" | + Eval-Arch/Security + Service-Ops |
| **Marketing/Content** | "랜딩", "캠페인", "콘텐츠" | Designer + Marketing(옵트인) + Eval-Visual |
| **Incident Response** | "장애", "다운", "긴급" | Incident-Responder + Service-Ops + 관련 Gen |

## 9. Memory & Doctrine 진화

- 본 doctrine은 **읽기 전용**. 수정은 Owner 승인 + Planner의 phase-end retrospective 산출물로만.
- 부서가 이 doctrine 위반을 발견하면 → Spec Review Meeting 소집 → doctrine 개정안 합의 → Owner 승인.
- agency-agents 신규 패턴 발견 시 Planner(HR)가 import 제안 → Owner 승인 후 본 doctrine에 부속서로 추가.

## 10. Attribution

본 doctrine은 https://github.com/msitarzewski/agency-agents (MIT License) 의 NEXUS 프레임워크에서 다음을 흡수·재해석함:
- `strategy/EXECUTIVE-BRIEF.md` — 핵심 통찰 4가지(P1~P4)
- `strategy/nexus-strategy.md` — 7-Phase 라이프사이클 골격
- `strategy/coordination/handoff-templates.md` — H-1~H-7 핸드오프 양식
- `strategy/coordination/agent-activation-prompts.md` — 부서 호출 패턴
- `strategy/playbooks/phase-{0..6}` — Planner phase 모드 정의
- `strategy/runbooks/scenario-{startup-mvp, enterprise-feature, marketing-campaign, incident-response}` — Section 8 Scenario Runbooks
- `specialized/agents-orchestrator` — Conductor 부서의 직접 영감
- `specialized/specialized-chief-of-staff` — Dispatcher CEO 페르소나의 보좌적 측면
- `testing/testing-reality-checker` — CQO의 default-to-FAIL 자세

원본 저작권은 원 저자(msitarzewski)에게 있으며, 본 적응본은 walwal-harness 컨텍스트 한정.
