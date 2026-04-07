# Scoring Rubric — Visual Evaluation

## 차원별 채점

| 차원 | 가중치 | 하드 임계값 |
|------|--------|------------|
| Design Consistency | 30% | 6/10 |
| Responsiveness | 25% | 7/10 |
| Accessibility | 25% | 6/10 |
| Originality | 20% | 5/10 |

**어떤 차원이든 하드 임계값 미달 → FAIL**

## AI Slop 감점표

| 패턴 | 감점 |
|------|------|
| 보라색/파란색 그라디언트 + 흰 카드 | -2 |
| 과도한 box-shadow 남발 | -1 |
| 기본 아이콘팩 무분별 사용 | -1 |
| "Welcome to [AppName]" 히어로 | -1 |
| 둥근 아바타 + 카드 그리드 | -1 |
| 전체 fade-in 애니메이션 | -1 |
| 과도한 보더/구분선 | -1 |

## evaluation-visual.md 출력 형식

```markdown
# Visual Evaluation: Sprint [N]

## Date / Verdict / Attempt

## Responsive Check
| Page | Mobile (375) | Tablet (768) | Desktop (1280) | Issues |

## Design Consistency
- Color Palette: [통일/혼재]
- Typography Scale: [일관/불일관]
- Spacing System: [체계적/비체계적]
- Border Radius: [통일/혼재]

## AI Slop Detection
| Pattern | Found | Deduction |
| **Total Deduction** | | **-X** |

## Accessibility
- Semantic HTML: PASS/FAIL
- Heading Order: PASS/FAIL
- Keyboard Navigation: PASS/FAIL
- Color Contrast: PASS/FAIL
- Form Labels: PASS/FAIL

## Scores
| Dimension | Score | Threshold | Status |

## Failures Detail
### [차원명]
- Issue / Screenshot / Recommendation
```
