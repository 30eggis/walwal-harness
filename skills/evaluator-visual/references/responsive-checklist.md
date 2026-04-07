# Responsive Checklist

## Breakpoints

| Breakpoint | Size | 검증 항목 |
|------------|------|----------|
| Mobile | 375x812 | 단일 컬럼, 터치 타겟 44px+, 햄버거 메뉴 |
| Tablet | 768x1024 | 적응형 레이아웃, 사이드바 토글 |
| Desktop | 1280x720 | 풀 레이아웃, 사이드바 상시 표시 |

## 검증 절차

각 breakpoint에서 모든 페이지:
```
1. browser_resize → 해당 크기
2. browser_take_screenshot → 캡처
3. browser_snapshot → 레이아웃 구조 확인
```

## 확인 항목

- [ ] 콘텐츠 잘림 / 오버플로우 없음
- [ ] 가로 스크롤 없음
- [ ] 텍스트 가독성 (mobile 최소 14px)
- [ ] 터치 타겟 크기 (mobile 44px+)
- [ ] 네비게이션 접근성

## 키보드 네비게이션

```
1. browser_press_key → Tab (반복)
2. 포커스 이동 순서 논리적인지 확인
3. browser_press_key → Enter (인터랙티브 요소 활성화)
4. browser_press_key → Escape (모달 닫기)
```

## 접근성 트리 (browser_snapshot)

확인:
- 시맨틱: button, nav, main, header, footer, form
- heading 순서: h1 → h2 → h3 (건너뛰기 없음)
- 인터랙티브 요소에 접근 가능한 이름
- 이미지 alt 텍스트
- 폼 label 연결
