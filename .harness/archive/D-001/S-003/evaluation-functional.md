---
docmeta:
  id: evaluation-functional
  title: Evaluation — Functional (Sprint 3 / Phase C-3)
  type: output
  createdAt: 2026-05-07T00:00:00Z
  updatedAt: 2026-05-07T00:00:00Z
  source:
    producer: agent
    skillId: harness-evaluator-functional
  inputs:
    - documentId: evaluation-code-quality
      uri: ./evaluation-code-quality.md
      relation: output-from
      sections:
        - sourceRange: { startLine: 35, endLine: 60 }
          targetRange: { startLine: 25, endLine: 60 }
  tags: [evaluation, functional, sprint-3, phase-c-3, PASS]
---

# Evaluation — Functional (Sprint 3 / Phase C-3)

## Verdict: **PASS** (3.00 / 3.00)

## AC

| AC | Result |
|---|---|
| F-019 GOAL 카드 (active/null) | **PASS** — DOM `[data-testid="goal-card"]` 항상 렌더, goal=null 시 placeholder, active 시 title+truncated description |
| F-021 archive boxes | **PASS** — DOM `[data-testid="archive-boxes"]` 존재, sprintCount 만큼 box mesh |
| F-022 archive 드로어 | **PASS** — Scene 의 archive 룸 클릭 핸들러가 drawerTab="archive-list" 자동 활성 |
| F-023 i18n | **PASS** — vitest 3 case (ko hit / en fallback / missing key) |
| F-024 E2E 6 시나리오 | **PASS** — 7/7 (시나리오 1·2·3·4·5·6 + perf) |
| F-025 SSE perf | **PASS** — 5-sample 평균 **237ms** (목표 500ms 의 47%) |
| 회귀 (C-1+C-2) | **PASS** — 모든 이전 시나리오 그대로 통과 |

## 점수

| 축 | Score |
|---|---|
| F1 AC (7/7) | 3 |
| F2 에러 처리 | 3 |
| F3 통합/E2E | 3 |
| F4 회귀 | 3 |
| **합계** | **3.00** |

```json
{
  "cross_validation_from_functional": {
    "ac_pass_count": 7,
    "sse_latency_avg_ms": 237,
    "sse_samples_ms": [198, 257, 223, 250, 258],
    "regression_pass": true
  }
}
```

```
PASS  3.00/3.00
next_agent: evaluator-visual
```
