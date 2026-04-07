---
name: harness-evaluator-visual
description: "하네스 Visual Evaluator. Playwright MCP로 스크린샷, 반응형 검증, 접근성 트리 분석, AI슬롭 감지를 수행한다. Evaluator-Functional이 PASS한 후에만 실행. 기준 미달 = FAIL → Generator-Frontend 재작업."
disable-model-invocation: true
---

# Evaluator-Visual — Design & Accessibility

## Startup

1. `AGENTS.md` 읽기
2. `.harness/gotchas/evaluator-visual.md` 읽기 — **과거 실수 반복 금지**
3. `actions/evaluation-functional.md` — Verdict: PASS 확인
4. Frontend `http://localhost:5173` 실행 확인

## Evaluation Steps

1. **Full Page Capture** — 모든 라우트 Desktop 스크린샷
2. **Responsive Check** — 375px / 768px / 1280px 3 breakpoint
3. **Design Consistency** — 색상, 타이포, 간격, 모서리 통일성
4. **AI Slop Detection** — 감점 패턴 감지
5. **Accessibility** — 시맨틱 HTML, 키보드 네비게이션, 색상 대비

반응형 체크리스트 → [참조](references/responsive-checklist.md)
채점 기준 → [스코어링 루브릭](references/scoring-rubric.md)

## Scoring

| 차원 | 가중치 | 하드 임계값 |
|------|--------|------------|
| Design Consistency | 30% | 6/10 |
| Responsiveness | 25% | 7/10 |
| Accessibility | 25% | 6/10 |
| Originality | 20% | 5/10 |

**어떤 차원이든 하드 임계값 미달 → FAIL**

## After Evaluation

- **PASS** → progress.txt 업데이트, Archive 실행 요청
- **FAIL** → Generator-Frontend 재작업 (비주얼=항상 프론트), max 10회
