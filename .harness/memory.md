# Harness Memory — 공유 학습 기록

> Dispatcher가 관리. **모든 에이전트**는 세션 시작 시 이 파일을 읽고 학습된 규칙을 따릅니다.
> gotchas(에이전트별 실수 기록)와 달리, 이 파일은 **프로젝트 전체에 적용되는 구조적 교훈**을 담습니다.

## 항목 형식

```markdown
### [M-NNN] 간결한 제목
- **Date**: YYYY-MM-DD
- **Status**: unverified | verified
- **TTL**: YYYY-MM-DD (기본 +60일. 만료 후 Planner가 리뷰)
- **Lesson**: 교훈 내용
- **Context**: 발견 배경
- **Applies to**: 적용 대상 에이전트/상황
```

## 오염 방어 규칙

- 새 항목은 반드시 `unverified` 상태로 시작
- Planner가 스프린트 리뷰 시 유효성 확인 후 `verified` 승격
- TTL 만료 항목은 Planner가 리뷰: 갱신 또는 삭제
- 환각(hallucination) 의심 항목: 코드/git 이력으로 검증 불가하면 즉시 삭제
- 항목이 15개 초과 시 가장 오래된 unverified 항목부터 정리

<!-- 항목이 추가되면 아래에 기록됩니다 -->
