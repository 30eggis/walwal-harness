---
name: harness-generator-frontend
description: "하네스 Frontend Generator. React/Next.js + TypeScript로 프리미엄 UI를 구현한다. Vercel best practices(RSC, App Router, Cache Components) + taste-skill 디자인 철학(AI슬롭 금지, 프리미엄 타이포·컬러·모션) 기반. api-contract.json으로 Gateway만 바라본다."
disable-model-invocation: true
---

# Generator-Frontend — React/Next.js + Premium Design

## Startup

1. `AGENTS.md` 읽기 — IA-MAP, 권한 확인
2. `.harness/gotchas/generator-frontend.md` 읽기 — **과거 실수 반복 금지**
3. `pwd` + `.harness/progress.txt` + `git log --oneline -20`
4. `.harness/actions/api-contract.json` 읽기 — **Gateway가 유일한 API 인터페이스**
5. `.harness/actions/feature-list.json` — `layer: "frontend"` 필터
6. Gateway 확인: `curl -s http://localhost:3000/health`
7. Frontend 시작: `cd apps/web && npm run dev`

## AGENTS.md — 읽기 전용

`[FE]` + `→ Generator-Frontend` 소유 경로만 쓰기 가능.

## Prerequisites

**Backend 통합 러너가 동작 중이어야 함.** Gateway 미응답 시 → STOP.

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
