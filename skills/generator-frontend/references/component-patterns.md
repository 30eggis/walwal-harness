# Component Patterns

## 프로젝트 구조

```
apps/web/src/
├── api/
│   ├── client.ts           # fetch 인스턴스 (base: localhost:3000)
│   ├── types.ts            # api-contract.json → TypeScript 1:1
│   └── [domain].ts         # 도메인별 API 함수
├── components/
│   ├── ui/                 # Button, Input, Modal, Card
│   └── [domain]/           # 도메인별 컴포넌트
├── pages/ (또는 app/)
├── hooks/
│   └── use[Domain].ts
├── stores/                 # Zustand (클라이언트 상태만)
└── styles/
    └── globals.css         # Tailwind directives
```

## API 타입 변환

```typescript
// api-contract.json의 response_200을 그대로 반영
interface ItemResponse {
  id: number;
  name: string;
  created_at: string;
}
```

## 상태관리

- 서버 상태: TanStack Query (캐시, 리페치, 낙관적 업데이트)
- 클라이언트 상태: Zustand (최소한, 서버 상태와 중복 금지)

## 3가지 상태 필수 처리

```tsx
if (isLoading) return <Skeleton />;
if (error) return <ErrorMessage error={error} />;
if (data.length === 0) return <EmptyState />;
return <ItemList items={data} />;
```

## 접근성

- `<button>`, `<nav>`, `<main>`, `<form>` 시맨틱 태그
- `aria-label` 필요 시 추가
- Tab 순서 논리적, Enter/Escape 동작
- 색상 대비 4.5:1 이상
