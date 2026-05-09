# CONVENTIONS.md — Project Conventions

> 이 파일은 프로젝트의 코딩 컨벤션, 선호 패턴, 금지 패턴을 자유 형식으로 정의합니다.
> 모든 에이전트는 세션 시작 시 이 파일을 읽고 규칙을 적용합니다.
> 
> **진실의 원천**: 이 파일이 유일한 컨벤션 정의 소스입니다.
> Gotcha나 AGENTS.md에 복사하지 마세요 — 에이전트가 직접 이 파일을 참조합니다.

## Architecture

<!-- 아키텍처 수준의 규칙을 여기에 작성하세요 -->
<!-- 예시:
- 서비스 간 직접 DB 접근 금지 — 반드시 API 또는 메시지 패턴 사용
- 모노리스보다 모듈러 아키텍처 선호
-->

### Walwal-Harness Company Contract

walwal-harness는 단순 작업 파이프라인이 아니라 "회사 구조 + 자율 구조 + 하네스"다.

- Owner는 최초 GOAL과 escalation에만 관여한다. 최초 GOAL 이후 Owner 입력은 interrupt/additional request이며 회사가 대기하는 이유가 아니다.
- Dispatcher/CEO는 Owner와의 유일한 외부 창구다.
- Planner/COO는 GOAL을 work package, queue, 가설, plan으로 바꾼다.
- CTO는 구현, 아키텍처, 기술선택, runtime recovery 책임자다.
- CQO는 품질, 회귀, evidence, PASS/FAIL 책임자다.
- Service-Ops는 운영 신호, KPI, incident, monitor cadence 책임자다.
- Meeting-Manager는 상태표가 아니라 임원 회의록을 남긴다. 회의록에는 CEO/COO/CTO/CQO/Service-Ops의 Position, Evidence, Action이 있어야 한다.

## Code Style

<!-- 코드 스타일 규칙을 여기에 작성하세요 -->
<!-- 예시:
- any 타입 사용 금지
- console.log 대신 structured logger 사용
- 함수는 30줄 이내, 파일은 300줄 이내
-->

## Preferred Patterns

<!-- 선호하는 라이브러리, 패턴, 접근 방식 -->
<!-- 예시:
- 상태관리: Zustand
- API 호출: TanStack Query
- 폼 처리: React Hook Form + Zod
-->

## Avoid

<!-- 사용을 피해야 하는 패턴, 라이브러리, 접근 방식 -->
<!-- 예시:
- CSS-in-JS (styled-components, emotion)
- Class components
- Redux (Zustand으로 대체)
-->

## Testing

<!-- 테스트 관련 규칙 -->
<!-- 예시:
- E2E 테스트는 핵심 사용자 플로우만
- 단위 테스트 커버리지 80% 이상
- mock 최소화, 실제 DB 사용 선호
-->

## Naming

<!-- 네이밍 컨벤션 -->
<!-- 예시:
- 컴포넌트: PascalCase
- 변수/함수: camelCase
- 파일: kebab-case
- DB 테이블: snake_case
-->
