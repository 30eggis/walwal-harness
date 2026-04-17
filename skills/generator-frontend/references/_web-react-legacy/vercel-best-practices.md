# Vercel / Next.js Best Practices

> 출처: Vercel Engineering, Next.js App Router 공식 문서

## Framework 기본값

- **Next.js App Router** + **Server Components** 기본
- `'use client'`는 인터랙션이 필요한 곳에만 추가
- `proxy.ts` (Next.js 16+) 또는 `middleware.ts`로 인터셉션, 인증 게이트, 리다이렉트
- Cache Components, `next/image`, `next/font` 우선 사용

## RSC (React Server Components) 규칙

- **RSC 안전**: 전역 상태는 Client Components에서만 동작
- Next.js에서 Provider는 별도 `'use client'` 컴포넌트로 래핑
- **인터랙티비티 격리**: 모션/인터랙션이 있는 UI는 독립 leaf 컴포넌트로 추출 + `'use client'`
- Server Components는 정적 레이아웃만 렌더링

## 렌더링 전략

- **SSG (Static)**: 변하지 않는 페이지
- **ISR (Incremental)**: 주기적 갱신이 필요한 페이지
- **SSR (Dynamic)**: 요청마다 달라지는 페이지
- **PPR (Partial Prerendering)**: 정적 쉘 + 동적 홀 조합

## 성능 최적화

- `next/image`: 자동 최적화, `loading="lazy"`, `sizes` 속성 필수
- `next/font`: 빌드 타임 폰트 최적화, 레이아웃 시프트 방지
- **번들 사이즈**: `'use client'` 경계에서 트리쉐이킹 확인
- **Core Web Vitals**: LCP < 2.5s, FID < 100ms, CLS < 0.1 목표

## 상태관리 전략

- **서버 상태**: TanStack Query (캐시, 리페치, 낙관적 업데이트)
- **클라이언트 상태**: Zustand (최소한, 서버 상태와 중복 금지)
- `useState`/`useReducer`: 격리된 UI 로직에만
- 전역 상태: deep prop-drilling 회피 목적으로만

## 의존성 검증 [필수]

3rd party 라이브러리 import 전 반드시 `package.json` 확인.
없으면 설치 명령 먼저 출력. **존재를 가정하지 않는다.**

## Tailwind CSS 버전 관리

- `package.json`에서 v3/v4 확인 후 해당 문법 사용
- v4: `postcss.config.js`에 `tailwindcss` 플러그인 사용 금지 → `@tailwindcss/postcss` 또는 Vite 플러그인
- v3 프로젝트에 v4 문법 혼용 금지

## shadcn/ui 사용 시

- 기본 상태 그대로 사용 **금지**
- radius, colors, shadows를 프로젝트 디자인 시스템에 맞게 커스터마이즈 필수
