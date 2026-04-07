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
- **Trigger**: 사용자가 한 말 (원문 요약)
- **Wrong**: 에이전트가 했던 잘못된 행동
- **Right**: 올바른 행동
- **Why**: 왜 잘못인지 근거
- **Scope**: 이 규칙이 적용되는 조건/범위
```

## 관리 규칙

- Dispatcher만 gotchas 파일에 쓰기 가능
- 각 에이전트는 자신의 gotchas 파일을 읽기 전용으로 참조
- 중복 항목 금지 — 같은 실수는 기존 항목에 횟수 증가
- 해결된 항목은 삭제하지 않고 `[RESOLVED]` 태그 추가
- 항목이 20개 초과 시 가장 오래된 RESOLVED 항목부터 정리
