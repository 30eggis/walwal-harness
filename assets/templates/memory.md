---
docmeta:
  id: memory
  title: Harness Memory — 공유 학습 기록
  type: input
  createdAt: 2026-04-20T00:00:00Z
  updatedAt: 2026-05-07T00:00:00Z
  source:
    producer: user
    skillId: harness
  inputs:
    - documentId: doctrine-nexus
      uri: ../../doctrine/nexus.md
      relation: output-from
      note: NEXUS Foundational Principle P3 (Continuous Loop > End-of-Pipeline) 의 권위 출처. M-NEXUS-P3 항목이 이를 운영 룰로 변환.
      sections:
        - sourceRange: { startLine: 32, endLine: 60 }
          targetRange: { startLine: 56, endLine: 70 }
    - documentId: gotchas-dispatcher
      uri: ../../gotchas/dispatcher.md
      relation: output-from
      note: dispatcher [G-001]~[G-004] 가 본 memory 의 [M-NEXUS-P3] 적용 사례. inline 사용자 피드백 기반.
      sections:
        - sourceRange: { startLine: 17, endLine: 52 }
          targetRange: { startLine: 56, endLine: 70 }
  tags: [harness, memory, template]
---

# Harness Memory — 공유 학습 기록

> Dispatcher가 관리. **모든 에이전트**는 세션 시작 시 이 파일을 읽고 학습된 규칙을 따릅니다.
> gotchas(에이전트별 실수 기록)와 달리, 이 파일은 **프로젝트 전체에 적용되는 구조적 교훈**을 담습니다.

## 항목 형식

```markdown
### [M-NNN] 간결한 제목
- **Date**: YYYY-MM-DD
- **Status**: unverified | verified
- **TTL**: YYYY-MM-DD (기본 +60일. 만료 후 Planner가 리뷰)
- **Lesson**: 교훈 내용
- **Context**: 발견 배경
- **Applies to**: 적용 대상 에이전트/상황
```

## 오염 방어 규칙

- 새 항목은 반드시 `unverified` 상태로 시작
- Planner가 스프린트 리뷰 시 유효성 확인 후 `verified` 승격
- TTL 만료 항목은 Planner가 리뷰: 갱신 또는 삭제
- 환각(hallucination) 의심 항목: 코드/git 이력으로 검증 불가하면 즉시 삭제
- 항목이 15개 초과 시 가장 오래된 unverified 항목부터 정리

<!-- 항목이 추가되면 아래에 기록됩니다 -->

### [M-001] progress.log 가독성 — 상세 로그 필수
- **Date**: 2026-04-20
- **Status**: verified
- **TTL**: 영구
- **Lesson**: Team Worker와 Evaluator가 progress.log에 남기는 로그는 대시보드만 보고도 "무슨 일을 시작했는가 / 무엇을 만들었는가 / 무엇을 어떻게 검증하는가"를 알 수 있어야 한다. 다음 원칙을 반드시 따른다:
  1. `gen-start`에 Feature **제목과 목표**를 함께 기록 ("F-001 \"사용자 회원가입 API\" start — goal=POST /users, 6 AC"). ID만 기록 금지.
  2. `gen-write`는 **변경 파일마다 1건씩** 기록 (경로 + LOC + create/edit/delete). "2 files" 같은 개수 요약 금지.
  3. `gen-done`은 **변경 파일 전체 목록**을 나열. "7 files"처럼 개수만 기록 금지.
  4. `eval-ac`로 **AC 원문**을 먼저 선언 ("AC-3: \"POST /users returns 201 with created user id\""), 그 후 `eval-check`로 증거·판정 기록. "AC-1 count=0" 같은 수치 단독 금지.
  5. `result PASS`는 **SCORE ≥ 2.80**인 경우에만 기록. score=1.00을 PASS로 기록 금지.
  6. 각 단계마다 **어떤 도구/방법으로 검증했는지**(tsc/eslint/curl/playwright 등) 명시.
- **Context**: 사용자가 대시보드 로그만 보고 진행 상황을 파악해야 하는데, 기존 축약 로그로는 4대 질문에 답이 안 보인다는 피드백.
- **Applies to**: Company Worker(Generator + Evaluator), 모든 `logev` 호출 지점.

### [M-NEXUS-P3] Owner ↔ CEO 단일 창구 + 자율 실행 (Inviolable)
- **Date**: 2026-05-07
- **Status**: verified
- **TTL**: 영구
- **Lesson**: walwal-harness 는 NEXUS 회사 메타포다. 다음 두 룰을 **절대로** 어기지 않는다.
  1. **정체성**: 사용자 = **Owner** (회사 외부 주주), Dispatcher = **CEO** (Owner 와의 유일한 대화 창구). 응답·GOAL·로그 어디서도 사용자를 "CEO" 로 호칭하지 않는다. 회사 내부 결정 (sprint 분할, mode 선택, agent 호출, 평가 점수) 을 Owner 에게 떠넘기지 않는다.
  2. **자율 실행 (NEXUS P3)**: GOAL 확정 직후 회사는 **사용자 펌프 없이** 자율 진행. "다음 단계로 진행할까요?", "/harness-next 실행하시겠습니까?" 같은 진행 여부 질문은 자율성 위반. Owner 가 돌아오는 시점은 (a) GOAL 모호성 명료화 (1~2 개 객관식 질문, 한 번만), (b) 결과 보고, (c) escalation 셋 뿐.
- **Context**: v6.0.0 publish 직후 dispatcher 응답이 사용자를 "CEO 직접 리뷰…" 로 호명하고 "/harness-next 자동 진행하시겠습니까?" 로 사용자 펌프를 요구함. Owner 의 명시적 교정.
- **Applies to**:
  - **Dispatcher**: 사용자 호칭/응답 문구, GOAL 정립, 모든 inbound/outbound owner 통신. → anti-pattern: `.harness/gotchas/dispatcher.md` [G-001]~[G-004].
  - **Conductor**: GOAL 확정 직후 자동 시동 (사용자 허락 X), Eval PASS/FAIL 직후 자동 advance/retry, 회사모드 병렬 worker pool 관리.
  - **Planner / CTO / CQO / Generator / Evaluator / Service-Ops**: Owner 와 직접 대화 X. 모든 통신은 Dispatcher 경유.
- **Why this matters**: 회사가 매 단계 사용자 허락을 구하면 NEXUS 메타포 자체가 무너진다. P3 "Continuous Loop > End-of-Pipeline" 가 약속하는 95% 결함 차단·40~60% 단축은 자율 루프에서만 성립한다.

### [M-002] FE Evaluation은 Playwright 필수
- **Date**: 2026-04-20
- **Status**: verified
- **TTL**: 영구
- **Lesson**: 웹 렌더링 가능한 FE Feature(React, Next, Flutter Web, RN Web 등)는 **Evaluator-Functional과 Evaluator-Visual이 반드시 Playwright MCP 도구(`mcp__playwright__browser_*`)를 호출하여 실제 브라우저 조작으로 검증**한다. 코드 열람/grep/정적 분석만으로 PASS 판정 금지. 각 AC에 대해 사용한 playwright 도구 이름과 결과를 `evaluation-*.md`에 증거로 남겨야 하며, 증거 없는 AC는 0점 강제.
- **Context**: FE 피처가 실제 UX를 검증하지 않고 코드 존재 여부만으로 PASS되는 문제.
- **Applies to**:
  - Planner: FE Feature AC에 `type: visual|e2e|a11y` + `verify.tool: "playwright"` + `verify.steps` 명시 필수.
  - Evaluator-Functional / Evaluator-Visual: FE Feature 평가 시 Playwright 도구 호출 없이 진행 금지.
  - 네이티브 모바일/데스크톱 스택은 `validation.visual.enabled == false`일 때만 MANUAL_REQUIRED로 우회 허용.
