---
docmeta:
  id: evaluator-functional-gotchas
  title: Gotchas — Evaluator-Functional
  type: input
  createdAt: 2026-04-08T00:00:00Z
  updatedAt: 2026-04-27T00:00:00Z
  source:
    producer: user
    skillId: harness-dispatcher
  inputs: []
  tags: [harness, gotcha, evaluator, evaluator-functional]
---

# Gotchas — Evaluator-Functional

> Dispatcher가 관리. Evaluator-Functional은 세션 시작 시 이 파일을 읽고 같은 실수를 반복하지 않습니다.

<!-- 항목이 추가되면 아래에 기록됩니다 -->

## [G-001] 런타임 버그 인지 후 PASS 판정 금지 (verified · 2026-04-27)

**Status**: verified
**Severity**: HIGH
**Occurrences**: 1+ (실제 사례: harness-clue Sprint 3 F-209)

**규칙**: Evaluator (functional / visual / code-quality 모두) 가 평가 중 런타임 버그를 발견했거나 worker 가 보고서에 런타임 버그를 명시한 경우, **PASS 판정 절대 금지**. carry-over / 다음 sprint 처리 / follow-up 으로 미루기도 금지. 같은 sprint 안에서 fix 완료 후에만 PASS.

**검출 시그널** (eval 자체 + worker report 둘 다 스캔):
- "runtime bug", "런타임 버그/에러", "runtime error"
- RSC ↔ Client Component 경계 위반 (`use client` 누락 등)
- `not-found.tsx`, `error.tsx`, `loading.tsx` 누락/오류
- typed-routes / TypeScript route 타입 미스매치
- Hydration error, Hydration mismatch
- 콘솔 uncaught error, unhandled promise rejection
- worker 가 자기 결과를 "carry-over", "다음 sprint", "추후", "follow-up" 으로 표현

**처리**: 위 시그널 1 건 이상 → VERDICT=FAIL, score 무관, retry_target = 결함 위치 Generator. 점수가 2.80+ 이어도 FAIL 강제 (Adversarial Rule).

**Why**: 사용자 명시 — "오류가 있는 것을 인지한 채로 스프린트를 넘어가는 행위는 절대 용납할 수 없다. 견고하게 기반을 다져나가야 한다."

**How to apply**: Eval 종료 직전 자기 보고서 + Generator 보고서를 위 키워드로 grep. 1 건이라도 매치하면 verdict 를 FAIL 로 강제 변환하고 evaluation-*.md 의 결론 섹션에 "Hard Gate G-001 위반: <검출 키워드> — 같은 sprint 내 fix 후 재평가 필요" 명시.
