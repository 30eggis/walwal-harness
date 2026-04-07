# Scoring Rubric — Functional Evaluation

## 차원별 채점

| 차원 | 가중치 | 하드 임계값 | 측정 방법 |
|------|--------|------------|----------|
| Contract 충족률 | 40% | 80% | 통과 기준 수 / 전체 기준 수 |
| API 계약 준수 | 25% | 100% | api-contract.json 불일치 = 즉시 FAIL |
| 에러 내성 | 20% | 6/10 | 에러 시나리오 처리 수준 |
| 콘솔 청결 | 15% | JS 에러 0개 | 콘솔 에러 개수 |

**어떤 차원이든 하드 임계값 미달 → 스프린트 FAIL**

## evaluation-functional.md 출력 형식

```markdown
# Functional Evaluation: Sprint [N]

## Date: [날짜]
## Verdict: PASS / FAIL
## Attempt: [N] / 3

## Step 0: IA Structure Compliance
- Verdict: PASS / FAIL (GATE)

## Regression Test
| Previous Feature | Status | Note |

## Contract Criteria Results
| # | Criterion | Result | Failure Location | Evidence |

## API Contract Compliance
| EP ID | Method + Path | Schema Match | Issues |

## Scores
| Dimension | Score | Threshold | Status |

## Failures Detail
### [#N] [기준명]
- **failure_location**: backend / frontend
- **Expected**: ...
- **Actual**: ...
- **Recommendation**: ...
```

## failure_location 라우팅

| location | 재작업 대상 |
|----------|-----------|
| `backend` | Generator-Backend |
| `frontend` | Generator-Frontend |
| 혼합 | Backend 먼저 → Frontend |
