# Gotcha Flow — 상세 가이드

## 교정 시그널 감지

| 시그널 패턴 | 예시 | 확신도 |
|------------|------|--------|
| 명시적 부정 | "아니", "틀렸어", "no" | HIGH |
| 행동 교정 | "그렇게 하면 안 돼", "X 하지 마" | HIGH |
| 올바른 방법 제시 | "X는 Y로 해야 해" | HIGH |
| 반복 불만 | "왜 또 이래", "또 같은 실수" | HIGH |
| 암시적 교정 | "그게 아니라", "다시 해봐" | MEDIUM |
| 질문형 | "이게 맞아?" | LOW (확인 후 판단) |

**HIGH/MEDIUM만 Gotcha로 기록.**

## 대상 에이전트 판별

| 도메인 키워드 | 대상 |
|-------------|------|
| API, 엔드포인트, DB, 스키마, NestJS, Gateway, 서비스 | `generator-backend` |
| 컴포넌트, UI, 스타일, 반응형, React, CSS, 상태 | `generator-frontend` |
| 테스트, 검증, 통과, 기준, 채점, PASS/FAIL | `evaluator-functional` |
| 디자인, 접근성, 색상, 레이아웃, 반응형 심사 | `evaluator-visual` |
| 설계, 아키텍처, 기획, 기능 목록, IA, 서비스 분할 | `planner` |
| 불명확 | 사용자에게 질문 |

## Gotcha 항목 형식

`.harness/gotchas/[agent-name].md`에 추가:

```markdown
### [G-NNN] 간결한 제목
- **Date**: 2026-04-07
- **Trigger**: "사용자 원문 요약"
- **Wrong**: 에이전트가 했던 잘못된 행동
- **Right**: 사용자가 지시한 올바른 행동
- **Why**: 왜 잘못인지 근거
- **Scope**: 항상 / 특정 조건에서만
- **Occurrences**: 1
```

## 중복 처리

1. 기존 gotchas 파일 읽기
2. 동일/유사 항목 존재 → `Occurrences` 증가 + 날짜 업데이트
3. 신규 → 다음 G-NNN 번호로 추가

## 관리 규칙

- Dispatcher만 gotchas 파일 쓰기 가능
- 해결된 항목: `[RESOLVED]` 태그 (삭제하지 않음)
- 20개 초과 시 가장 오래된 RESOLVED부터 정리
