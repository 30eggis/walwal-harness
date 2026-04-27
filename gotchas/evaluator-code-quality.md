---
docmeta:
  id: evaluator-code-quality-gotchas
  title: Gotchas — Evaluator-Code-Quality
  type: input
  createdAt: 2026-04-22T00:00:00Z
  updatedAt: 2026-04-22T00:00:00Z
  source:
    producer: user
    skillId: harness-dispatcher
  tags:
    - gotchas
    - evaluator
    - code-quality
---

# Gotchas — Evaluator-Code-Quality

> Dispatcher가 관리. Evaluator-Code-Quality는 세션 시작 시 이 파일을 읽고 같은 실수를 반복하지 않습니다.

<!-- 항목이 추가되면 아래에 기록됩니다 -->

## [G-001] 런타임 버그 인지 후 PASS 판정 금지 (verified · 2026-04-27)

**Status**: verified · **Severity**: HIGH

**규칙**: Code-quality eval 단계에서 SSR/RSC↔CC 경계 위반, 잘못된 라우트 타입, missing not-found/error.tsx 등 **런타임에 깨질 정적 결함**을 발견하면 즉시 FAIL. "스타일/구조 문제만 본다" 는 자기 합리화로 런타임 결함을 functional 단계로 넘기지 말 것.

**Why**: 사용자 명시 — "오류가 있는 것을 인지한 채로 스프린트를 넘어가는 행위는 절대 용납할 수 없다." Code-quality 가 정적 분석으로 잡을 수 있었던 결함을 통과시키면 evaluator chain 전체가 신뢰성을 잃는다.

**How to apply**: tsc/eslint 외에도 Next.js App Router 규칙 (use client 경계, typed routes), 라우트 세그먼트 필수 파일 (not-found/error/loading) 누락 여부를 정적으로 검사. 1 건이라도 발견 시 VERDICT=FAIL, retry_target=결함 위치 Generator.
