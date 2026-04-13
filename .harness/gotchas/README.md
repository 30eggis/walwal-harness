# Gotchas — Agent Mistake Registry

> 이 디렉토리는 각 에이전트가 반복하는 실수를 누적 기록합니다.
> Dispatcher가 사용자의 실수 지적을 감지하면 해당 에이전트의 gotchas 파일에 추가합니다.
> 각 에이전트는 세션 시작 시 자신의 gotchas 파일을 읽고 같은 실수를 반복하지 않습니다.

## 파일 구조

```
.harness/gotchas/
├── README.md                      # 이 파일
├── planner.md                     # Planner의 반복 실수
├── generator-backend.md           # Generator-Backend의 반복 실수
├── generator-frontend.md          # Generator-Frontend의 반복 실수
├── evaluator-functional.md        # Evaluator-Functional의 반복 실수
└── evaluator-visual.md            # Evaluator-Visual의 반복 실수
```

## 항목 형식

```markdown
### [G-NNN] 간결한 제목
- **Date**: YYYY-MM-DD
- **Status**: unverified | verified | resolved
- **TTL**: YYYY-MM-DD (만료일, 기본 +30일. 만료 후 Planner가 리뷰)
- **Trigger**: 사용자가 한 말 (원문 요약)
- **Wrong**: 에이전트가 했던 잘못된 행동
- **Right**: 올바른 행동
- **Why**: 왜 잘못인지 근거
- **Scope**: 이 규칙이 적용되는 조건/범위
- **Occurrences**: 1 (반복 시 증가)
```

### Status 정의

| Status | 의미 |
|--------|------|
| `unverified` | 첫 기록. 아직 재발 방지 효과 미확인 |
| `verified` | 동일 상황에서 올바르게 동작함을 확인 (Planner가 스프린트 리뷰 시 승격) |
| `resolved` | 코드/구조 변경으로 더 이상 발생 불가. 삭제 대상 |

### TTL (Time-To-Live)

- 기본 TTL: 작성일 + 30일
- TTL 만료된 항목은 Planner가 스프린트 전환 시 리뷰:
  - 여전히 유효 → TTL 갱신 + verified 승격
  - 더 이상 무관 → resolved 처리
  - 검증 불가 → 삭제

## 관리 규칙

- Dispatcher만 gotchas 파일에 쓰기 가능
- 각 에이전트는 자신의 gotchas 파일을 읽기 전용으로 참조
- 중복 항목 금지 — 같은 실수는 기존 항목에 Occurrences 증가
- 해결된 항목은 삭제하지 않고 `[RESOLVED]` 태그 + `resolved` Status 설정
- 항목이 20개 초과 시 가장 오래된 resolved 항목부터 정리
- **Planner 스프린트 전환 체크리스트**: TTL 만료 gotcha 리뷰, unverified 항목 검증
