# AI Forbidden Patterns — 셀프 체크 목록

> 구현 완료 후 이 목록으로 최종 점검. 하나라도 해당되면 수정.
> 출처: taste-skill, supanova-design-skill 통합

## Visual & CSS

| # | 금지 패턴 | 올바른 대안 |
|---|----------|-----------|
| V-1 | Neon/Outer Glow (`box-shadow` 글로우) | inner border 또는 tinted shadow |
| V-2 | Pure Black `#000000` | `#0a0a0a`, Zinc-950, Slate-950 |
| V-3 | 과포화 Accent (Saturation > 80%) | 뉴트럴과 자연스럽게 블렌딩 |
| V-4 | 과도한 Gradient Text (페이지당 1개 초과) | 1개까지만 허용 |
| V-5 | 커스텀 마우스 커서 | 기본 커서 유지 |
| V-6 | `h-screen` | `min-h-[100dvh]` |
| V-7 | `linear` / `ease-in-out` 트랜지션 | `cubic-bezier(0.16, 1, 0.3, 1)` |
| V-8 | `top/left/width/height` 애니메이션 | `transform` + `opacity` only |
| V-9 | 스크롤 컨테이너에 `backdrop-blur` | fixed/sticky 요소에만 |
| V-10 | 임의 `z-50` 남발 | 시스템 레이어에만 (nav, modal, overlay) |

## Typography

| # | 금지 패턴 | 올바른 대안 |
|---|----------|-----------|
| T-1 | Inter, Noto Sans KR, Roboto, Arial, Open Sans | Pretendard(한국어) + Geist/Outfit/Satoshi(영문) |
| T-2 | 크기로만 계층 표현하는 거대 H1 | weight + color로 계층 |
| T-3 | Dashboard에 Serif 폰트 | Sans-Serif only |
| T-4 | 한국어에 `leading-none` | `leading-tight` ~ `leading-snug` |
| T-5 | 한국어 `break-keep-all` 누락 | 모든 한국어 블록에 적용 |

## Layout & Spacing

| # | 금지 패턴 | 올바른 대안 |
|---|----------|-----------|
| L-1 | 3-Column Equal Card Row | Bento Grid, Zig-Zag, 비대칭 |
| L-2 | 센터 정렬 Hero (VARIANCE > 4) | Split Screen, 좌측 정렬, 비대칭 여백 |
| L-3 | Flexbox calc (`w-[calc(33%-1rem)]`) | CSS Grid |
| L-4 | 인접 섹션 동일 레이아웃 | 섹션마다 다른 패턴 |
| L-5 | Edge-to-edge 콘텐츠 | `max-w-7xl mx-auto` 컨테이너 |
| L-6 | 섹션 간격 부족 | `py-24 md:py-32 lg:py-40` 최소 |

## Content & Data

| # | 금지 패턴 | 올바른 대안 |
|---|----------|-----------|
| C-1 | "John Doe", "김철수" | 하윤서, 박도현, 이서진 |
| C-2 | "Acme Corp", "넥서스" | 스텔라랩스, 베리파이, 루미너스 |
| C-3 | 깨끗한 숫자 `50,000+`, `5.0` | 유기적 숫자 `47,200+`, `4.87` |
| C-4 | AI 클리셰: "혁신적인", "원활한", "차세대" | 구체적, 행동 지향적 카피 |
| C-5 | AI 영문 클리셰: "Elevate", "Seamless", "Unleash" | 구체적 동사 |
| C-6 | Lorem Ipsum, 영문 플레이스홀더 | 자연스러운 한국어 콘텐츠 |
| C-7 | 반말/존댓말 혼용 | 합니다/하세요 통일 |
| C-8 | 이모지 사용 | Phosphor/Radix 아이콘 |

## External Resources

| # | 금지 패턴 | 올바른 대안 |
|---|----------|-----------|
| E-1 | Unsplash URL (깨짐) | `picsum.photos/seed/{name}/{w}/{h}` |
| E-2 | 기본 SVG "egg" 아바타 | `i.pravatar.cc/150?u={name}` 또는 커스텀 |
| E-3 | shadcn/ui 기본 상태 | radius/colors/shadows 커스터마이즈 필수 |
| E-4 | FontAwesome, Material Icons | Phosphor 또는 Radix |
| E-5 | `window.addEventListener('scroll')` | `IntersectionObserver` |
| E-6 | Framer Motion에서 `useState`로 연속 애니메이션 | `useMotionValue` + `useTransform` |

## React / Next.js 특정

| # | 금지 패턴 | 올바른 대안 |
|---|----------|-----------|
| R-1 | Server Component에서 전역 상태 | Client Component로 격리 |
| R-2 | Provider를 Server Component에 직접 배치 | 별도 `'use client'` 래퍼 |
| R-3 | 무분별한 `'use client'` | 인터랙션 필요한 leaf만 |
| R-4 | Perpetual motion이 부모 리렌더 유발 | `React.memo` + 격리 Client Component |
| R-5 | `useEffect` cleanup 없는 애니메이션 | 반드시 cleanup return |
| R-6 | 3rd party import 전 package.json 미확인 | 설치 명령 먼저 출력 |

## Pre-Flight Checklist

구현 완료 후 최종 점검:

- [ ] 위 테이블의 모든 금지 패턴 0개 확인
- [ ] 로딩/에러/빈 상태 3가지 모두 구현
- [ ] 모바일 레이아웃 (`w-full`, `px-4`) 보장
- [ ] `min-h-[100dvh]` 사용 (h-screen 아님)
- [ ] 모든 트랜지션 `cubic-bezier(0.16, 1, 0.3, 1)`
- [ ] useEffect cleanup 함수 존재
- [ ] 한국어 텍스트에 `break-keep-all` 적용
- [ ] 카드 대신 spacing으로 구분 가능한 곳은 spacing 사용
- [ ] 인터랙티브 컴포넌트 `'use client'` 격리
