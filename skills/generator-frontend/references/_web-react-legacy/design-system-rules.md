# Design System Rules

> 출처: taste-skill (Leonxlnx), supanova-design-skill (uxjoseph)
> React/Next.js 앱 컨텍스트에 맞게 적응

## 디자인 변수 (Baseline)

```
DESIGN_VARIANCE: 8   (1=대칭, 10=비대칭)
MOTION_INTENSITY: 6  (1=정적, 10=시네마틱)
VISUAL_DENSITY: 4    (1=갤러리, 10=콕핏)
```

사용자 요청에 따라 동적 조정. Planner의 plan.md에 명시된 톤에 맞춤.

## 1. Typography

### 한국어
- **Primary**: Pretendard (CDN 또는 next/font)
- Headlines: `text-4xl md:text-5xl lg:text-6xl tracking-tight leading-tight font-bold`
- Body: `text-base md:text-lg text-gray-600 leading-relaxed max-w-[65ch]`
- **`break-keep-all`** 필수 (한국어 단어 중간 줄바꿈 방지)
- **`leading-tight` ~ `leading-snug`** (한국어는 Latin보다 수직 여백 필요)

### 영문 Display
- `Geist`, `Outfit`, `Cabinet Grotesk`, `Satoshi` 중 택 1
- Headlines: `tracking-tighter leading-none`
- Dashboard/Software UI: Serif 폰트 **금지** → Sans-Serif만 (`Geist` + `Geist Mono`)

### 금지 폰트
Inter, Noto Sans KR, Roboto, Arial, Open Sans, Helvetica, Malgun Gothic

## 2. Color

- **Accent 1개만.** Saturation < 80%
- **THE LILA BAN**: AI 보라색/파란색 그라디언트 **금지**
- Neutral base: Zinc/Slate 계열
- Accent: Emerald, Electric Blue, Warm Amber, Deep Rose 중 택 1
- 페이지 전체 warm/cool gray **혼용 금지**
- **NO Pure Black**: `#000000` 금지 → `#0a0a0a`, Zinc-950, Slate-950

### 다크모드
- 랜딩페이지: 다크 기본 권장 (`bg-zinc-950`)
- 앱/대시보드: 라이트 기본, 다크 옵션 (`dark:` prefix)

## 3. Layout

- **ANTI-CENTER BIAS**: DESIGN_VARIANCE > 4 일 때 센터 정렬 Hero **금지**
  - Split Screen (50/50), 좌측 정렬/우측 에셋, 비대칭 여백 사용
- **NO 3-Column Equal Cards**: Bento Grid, Zig-Zag, 비대칭 그리드 사용
- **Grid over Flex-Math**: `grid grid-cols-1 md:grid-cols-3 gap-6` (flexbox calc 금지)
- **컨테이너**: `max-w-7xl mx-auto px-4 sm:px-6 lg:px-8`
- **섹션 간격**: `py-24 md:py-32 lg:py-40` (디자인이 숨쉬도록)
- **모바일 오버라이드**: `< 768px`에서 `w-full px-4 py-8` 단일 컬럼 강제

### Bento Grid 패턴
```
grid grid-cols-12
- col-span-8 row-span-2 (큰 카드)
- col-span-4 (작은 카드 2개 스택)
```

## 4. Components

### Card Architecture (Double-Bezel)
```
Outer: bg-white/5 ring-1 ring-white/10 p-1.5 rounded-[2rem]
Inner: bg-distinct shadow-[inset_0_1px_1px_rgba(255,255,255,0.15)] rounded-[calc(2rem-0.375rem)]
```
- Card는 elevation이 hierarchy를 전달할 때만 사용
- VISUAL_DENSITY > 7: card 대신 `border-t`, `divide-y`, negative space

### CTA Button
```
rounded-full px-8 py-4 text-lg
hover:scale-[1.02] active:scale-[0.98]
transition: all 0.5s cubic-bezier(0.16, 1, 0.3, 1)
```
- 화살표 아이콘: 원형 래퍼 안에 배치 (`w-8 h-8 rounded-full bg-black/5`)
- 모바일 최소 48px 높이

### Eyebrow Tag
```
rounded-full px-3 py-1 text-[11px] uppercase tracking-[0.15em] font-medium bg-accent/10 text-accent
```

## 5. Motion

### 전역 트랜지션 기본값
```css
transition: all 0.5s cubic-bezier(0.16, 1, 0.3, 1);
```
`linear`, `ease-in-out` **금지**. 모든 인터랙티브 요소에 이 curve 적용.

### 스크롤 진입
```css
@keyframes fadeInUp {
  from { opacity: 0; transform: translateY(2rem); filter: blur(4px); }
  to   { opacity: 1; transform: translateY(0);    filter: blur(0);   }
}
```
- `IntersectionObserver`로 트리거 (`window.addEventListener('scroll')` 금지)
- 형제 요소 stagger: `animation-delay: calc(var(--index) * 80ms)`

### Framer Motion (MOTION_INTENSITY > 5)
- Spring physics: `type: "spring", stiffness: 100, damping: 20`
- `layout` / `layoutId`로 레이아웃 전환
- `useMotionValue` + `useTransform` (연속 애니메이션에 useState 금지)
- Perpetual motion은 `React.memo`로 격리된 Client Component에서만
- `<AnimatePresence>` 필수

### 성능
- **GPU만**: `transform`, `opacity`만 애니메이션. `top/left/width/height` 금지
- **Blur 제한**: `backdrop-blur`는 fixed/sticky 요소에만
- **Z-index**: sticky nav(`z-40`), overlay(`z-50`)에만. 임의 z-50 남발 금지
- **Grain/Noise**: `position: fixed; pointer-events: none; z-[60]`에서만

## 6. Viewport & Responsiveness

- **`min-h-[100dvh]`** 사용 (`h-screen` **금지** — iOS Safari 깨짐)
- Breakpoints: `sm:640` `md:768` `lg:1024` `xl:1280`
- 모바일 터치 타겟: 최소 44px
- 텍스트 가독성: 모바일 최소 14px

## 7. 한국어 콘텐츠 기준

- **자연스러운 한국어**: 번역체 금지
- 존댓말 일관성: 합니다/하세요 통일
- CTA: "무료로 시작하기", "3분만에 만들어보기", "지금 바로 체험하기"
- **금지 표현**: "혁신적인", "획기적인", "차세대", "원활한", "게임 체인저"
- 이름: 하윤서, 박도현, 이서진, 김하늘 (김철수/John Doe 금지)
- 숫자: `47,200+`, `4.87/5.0` (50,000+, 5.0 같은 깨끗한 숫자 금지)

## 8. Icons

- **Phosphor Icons** (`@phosphor-icons/react`) 또는 **Radix Icons** (`@radix-ui/react-icons`)
- strokeWidth 전역 통일 (1.5 또는 2.0 중 택 1)
- **이모지 금지**: 코드, 마크업, 텍스트 어디에서든
- FontAwesome, Material Icons 금지 (두꺼운 선)
