---
docmeta:
  id: scoring-rubric
  title: Flutter Functional Evaluation 스코어링 루브릭
  type: output
  createdAt: 2026-04-09T00:00:00Z
  updatedAt: 2026-04-09T00:00:00Z
  source:
    producer: agent
    skillId: harness-evaluator-functional-flutter
  inputs:
    - documentId: react-evaluator-scoring-rubric
      uri: ../../evaluator-functional/references/scoring-rubric.md
      relation: output-from
      sections:
        - sourceRange:
            startLine: 1
            endLine: 53
          targetRange:
            startLine: 32
            endLine: 160
  tags:
    - evaluator
    - flutter
    - scoring
    - rubric
---

# Flutter Functional Evaluation 스코어링 루브릭

## 차원별 채점

| 차원 | 가중치 | 하드 임계값 | 측정 방법 |
|------|--------|------------|----------|
| Static Analysis | 25% | warning/error 0개 | `flutter analyze --no-fatal-infos` |
| Test Pass Rate | 25% | 100% | `flutter test` 모든 스위트 |
| API Contract 준수 | 25% | 100% | rest_api.dart vs api-contract.json 대조 — 불일치 즉시 FAIL |
| Anti-Pattern 청결 | 15% | 위반 0건 | static-check-rules.md 의 FL-01 ~ FL-08 |
| Contract Criteria 충족률 | 10% | 80% | sprint-contract.md FE 기준 통과 수 / 전체 |

**어떤 차원이든 하드 임계값 미달 → 스프린트 FAIL**

## 차원별 점수 계산

### Static Analysis (25점)

| 결과 | 점수 |
|------|------|
| error 0, warning 0 | 25 |
| error 0, warning 1~2 | 0 (하드 임계값 미달 → FAIL) |
| error 1+ | 0 (즉시 FAIL) |

info 수준은 점수에 반영하지 않지만 보고서에 카운트 기록.

### Test Pass Rate (25점)

```
score = 25 * (passed / total)
```

- `total == 0` (테스트 존재하지 않음) → **0점 + FAIL** (Coverage gate)
- `fromJson/toJson` 왕복 테스트 누락 (이번 스프린트 추가분) → **FAIL**

### API Contract 준수 (25점)

```
score = 25 * (matched_endpoints / total_endpoints)
```

불일치 허용 없음 — 1개라도 불일치면 즉시 FAIL (하드 임계값 100%).

매칭 체크:
- method (GET/POST/PUT/DELETE)
- path (변수명 포함)
- path param → `@Path(...)` 매핑
- body → `@Body() XxxBody`
- response 타입 → 계약 스키마의 code/data/errors 구조

### Anti-Pattern 청결 (15점)

```
score = 15 * (passed_rules / total_rules)
```

- 8개 룰 중 1개라도 FAIL → **0점 + 스프린트 FAIL**
- 위반 0건이면 15점

### Contract Criteria 충족률 (10점)

```
score = 10 * (passed_criteria / total_criteria)
```

- 80% 미달 → FAIL
- 개별 기준의 실패 사유를 "Failures Detail"에 기록

## Total

```
total = static_analysis + test_pass + api_contract + anti_pattern + contract_criteria
verdict = PASS (if all hard thresholds met AND total >= 80) else FAIL
```

## failure_location 라우팅

Flutter 앱은 항상 FE 재작업이므로:

| location | 재작업 대상 |
|----------|-----------|
| `frontend` (기본) | `generator-frontend-flutter` |

예외: API Contract 불일치가 **서버 측 계약 오류**로 확인된 경우 → Planner에게 계약 수정 요청 필요.
이 경우 evaluation에 `## Change Request` 섹션 추가.

## evaluation-functional.md 헤더

```markdown
# Flutter Functional Evaluation: Sprint [N]

## Date: [YYYY-MM-DD]
## Verdict: PASS / FAIL
## Attempt: [N] / 10
## Stack: flutter

## Total Score: [N] / 100
| Dimension | Score | Threshold | Status |
| Static Analysis | X/25 | warning=0 | PASS/FAIL |
| Test Pass Rate | X/25 | 100% | PASS/FAIL |
| API Contract | X/25 | 100% | PASS/FAIL |
| Anti-Pattern | X/15 | 0 violations | PASS/FAIL |
| Contract Criteria | X/10 | 80% | PASS/FAIL |
```
