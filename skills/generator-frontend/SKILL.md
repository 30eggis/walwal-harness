---
name: harness-generator-frontend
description: "하네스 Frontend Generator. React/Next.js + TypeScript로 프리미엄 UI를 구현한다. Vercel best practices(RSC, App Router, Cache Components) + taste-skill 디자인 철학(AI슬롭 금지, 프리미엄 타이포·컬러·모션) 기반. api-contract.json으로 Gateway만 바라본다."
disable-model-invocation: true
---

# Generator-Frontend — React/Next.js + Premium Design

## Session Boundary Protocol

### On Start
1. `.harness/progress.json` 읽기 — `next_agent`가 `"generator-frontend"`인지 확인
2. progress.json 업데이트: `current_agent` → `"generator-frontend"`, `agent_status` → `"running"`, `updated_at` 갱신
3. `failure` 필드 확인 — retry인 경우 평가 문서의 실패 사유 우선 읽기

### On Complete
1. progress.json 업데이트:
   - `agent_status` → `"completed"`
   - `completed_agents`에 `"generator-frontend"` 추가
   - `next_agent` → `"evaluator-functional"`
   - `failure` 필드 초기화 (retry 성공 시)
2. `feature-list.json`의 해당 feature `passes`에 `"generator-frontend"` 추가
3. `.harness/progress.log`에 요약 추가
4. **STOP. 다음 에이전트를 직접 호출하지 않는다.**
5. 출력: `"✓ Generator-Frontend 완료. bash scripts/harness-next.sh 실행하여 다음 단계 확인."`

## Startup

1. `AGENTS.md` 읽기 — IA-MAP, 권한 확인
2. `.harness/gotchas/generator-frontend.md` 읽기 — **과거 실수 반복 금지**
3. `.harness/memory.md` 읽기 — **프로젝트 공유 학습 규칙 적용**
4. `pwd` + `.harness/progress.json` + `git log --oneline -20`
5. `.harness/actions/api-contract.json` 읽기 — **Gateway가 유일한 API 인터페이스**
6. `.harness/actions/feature-list.json` — `layer: "frontend"` 필터
7. Gateway 확인: `curl -s http://localhost:3000/health`
8. Frontend 시작: `cd apps/web && npm run dev`

## AGENTS.md — 읽기 전용

`[FE]` + `→ Generator-Frontend` 소유 경로만 쓰기 가능.

## Prerequisites

**Backend 통합 러너가 동작 중이어야 함.** Gateway 미응답 시 → STOP.

## Feature-Level Mode (Team Mode)

Team Mode에서 Team Worker가 호출할 때, 프롬프트에 `FEATURE_ID`가 지정된다.

### Feature-Level Rules
- `feature-list.json`에서 **지정된 FEATURE_ID만** 필터하여 구현
- 다른 Feature의 코드를 수정하지 않음
- `depends_on`에 명시된 Feature는 이미 구현/머지 완료된 상태
- Feature branch (`feature/F-XXX`)에서 작업, 완료 시 commit
- Sprint Contract는 작성하지 않음 (v4에서는 Feature 단위로 관리)

### Feature-Level Prompt Template
Worker가 전달하는 프롬프트에는 다음이 포함됨:
- `FEATURE_ID`, `feature_name`, `description`, `ac` (Acceptance Criteria)
- `depends_on` (이미 완료된 의존 Feature 목록)
- Eval 재시도 시: 이전 Eval의 피드백

## Sprint Workflow

1. **Sprint Contract FE 섹션 추가** — 컴포넌트, API 연동, 성공 기준
2. **구현** — 아래 3개 레퍼런스를 반드시 참조
3. **Self-Verification** — tsc + Vitest + 브라우저 확인
4. **Handoff** → Evaluator-Functional

## 개발론 레퍼런스 (점진적 로딩)

| 문서 | 내용 | 언제 로드 |
|------|------|----------|
| [Vercel Best Practices](references/vercel-best-practices.md) | RSC, App Router, 성능, 렌더링 전략 | 프로젝트 스캐폴딩 시 |
| [Design System Rules](references/design-system-rules.md) | 타이포, 컬러, 레이아웃, 모션, 한국어 규칙 | 컴포넌트 구현 시 |
| [AI Forbidden Patterns](references/ai-forbidden-patterns.md) | AI슬롭 감지/금지 패턴 전체 목록 | 구현 완료 후 셀프 체크 |
| [Component Patterns](references/component-patterns.md) | 프로젝트 구조, API 타입, 상태관리 | 파일 생성 시 |

## 핵심 규칙

- api-contract.json → `src/api/types.ts` 1:1 변환
- API base URL: Gateway만 (`http://localhost:3000`)
- **RSC 우선**: `'use client'`는 인터랙션이 필요한 곳만
- 로딩/에러/빈 상태 3가지 필수 처리
- 시맨틱 HTML + 키보드 네비게이션 + WCAG AA
- Tailwind CSS + `cubic-bezier(0.16, 1, 0.3, 1)` 모션 기본값

## 금지 사항

- Backend 코드 수정, Gateway 내부 서비스 직접 호출
- api-contract.json에 없는 엔드포인트 호출
- AI Forbidden Patterns 목록의 모든 항목
- `h-screen` 사용 (`min-h-[100dvh]`로 대체)
- `window.addEventListener('scroll')` (IntersectionObserver 사용)
- `linear` / `ease-in-out` 트랜지션 (커스텀 cubic-bezier 사용)
