---
docmeta:
  id: evaluator-visual-gotchas
  title: Gotchas — Evaluator-Visual
  type: input
  createdAt: 2026-04-08T00:00:00Z
  updatedAt: 2026-04-27T00:00:00Z
  source:
    producer: user
    skillId: harness-dispatcher
  inputs: []
  tags: [harness, gotcha, evaluator, evaluator-visual]
---

# Gotchas — Evaluator-Visual

> Dispatcher가 관리. Evaluator-Visual은 세션 시작 시 이 파일을 읽고 같은 실수를 반복하지 않습니다.

<!-- 항목이 추가되면 아래에 기록됩니다 -->

## [G-001] 런타임 버그 인지 후 PASS 판정 금지 (verified · 2026-04-27)

**Status**: verified · **Severity**: HIGH

**규칙**: Visual eval 중 콘솔 에러/Hydration mismatch/RSC↔CC 경계 위반/렌더 실패가 한 번이라도 관찰되면 PASS 절대 금지. 스크린샷이 멀쩡해 보여도 console.error 가 1 건 이상이면 FAIL. carry-over/follow-up 으로 미루기 금지.

**검출 시그널**: console error/warning, Hydration error, "use client" 누락, not-found/error.tsx 미렌더, layout shift 비정상, 404/500 응답.

**처리**: VERDICT=FAIL, retry_target=generator-frontend, evaluation-visual.md 결론에 "Hard Gate G-001 위반" 명시. 같은 sprint 내 fix 완료 후에만 재평가.

**Why**: 사용자 명시 — "오류가 있는 것을 인지한 채로 스프린트를 넘어가는 행위는 절대 용납할 수 없다."
