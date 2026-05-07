---
docmeta:
  id: sprint-contract
  title: Sprint Contract — Sprint 3 (Phase C-3)
  type: output
  createdAt: 2026-05-07T00:00:00Z
  updatedAt: 2026-05-07T00:00:00Z
  source:
    producer: agent
    skillId: harness-planner
  inputs:
    - documentId: plan
      uri: ./plan.md
      relation: output-from
      sections:
        - sourceRange: { startLine: 17, endLine: 30 }
          targetRange: { startLine: 25, endLine: 80 }
    - documentId: api-contract
      uri: ./api-contract.json
      relation: output-from
      sections:
        - sourceRange: { startLine: 45, endLine: 80 }
          targetRange: { startLine: 12, endLine: 18 }
  tags: [sprint-contract, sprint-3, phase-c-3, polish]
---

# Sprint Contract — Sprint 3 (Phase C-3)

## BE 섹션

본 sprint 는 BE 작업 없음. CR-002 (api-contract.json 갱신) 만 Planner 가 처리 완료 (1.1.0 → 1.2.0, GET /api/log 정식 등재). Generator-Backend 단계 skip.

## FE 섹션 (Generator-Frontend)

### 라이브 미리보기 의무

`(cd apps/harness-dashboard && npm run dev:dashboard)` 백그라운드 상시. F-019 → F-021 → F-022 순서로 가시 결과 추가.

### F-019 — GOAL 카드 (CEO실 벽)

**파일**: `apps/harness-dashboard/components/three/GoalCard.tsx`

- 3D 텍스트가 아닌 drei `<Html transform>` 으로 CEO실 북쪽 벽에 부착된 카드 형태.
- props: `goal: GoalCard | null`. null 이면 "No active goal" 플레이스홀더.
- 표시: title (큰 글자) + description_truncated (작은 글자, 200자 truncate `…`).
- Floor3D 또는 Stage3D 에서 `snapshot.goal` 을 prop 으로 받아 CEO 룸 좌표 (wx 1.5, wz 0) 위치에 렌더.

### F-021 — 아카이브 룸 + sprint 카운트

**파일**: `apps/harness-dashboard/components/three/ArchiveBoxes.tsx`

- archive 룸 (rect: wx 5, wy 7, ww 6, wh 2) 내부에 `archive.sprintCount` 만큼 box mesh 누적.
- 박스: 0.4 × 0.3 × 0.3 unit, 갈색-회색 그라디언트.
- 그리드: cols=6, rows=floor(count / 6) + 1.
- 최근 3개 박스에 drei `<Html>` 라벨 (D-NNN/S-NNN), 그 외는 익명. count > 3 일 때 추가로 "+N more" 라벨.

### F-022 — 아카이브 클릭 → archive-list 드로어

**파일**: `components/Scene.tsx` 갱신.

- 룸 id = "archive" 클릭 → drawerTab = "archive-list".
- 이미 Sprint 2 의 ArchiveList 컴포넌트 (Scene.tsx 안) 가 `snapshot.archive.all` 또는 `recent` 를 렌더 — 추가 작업 거의 없음 (rooms.archive 클릭 시 archive-list 탭 자동 활성).

### F-023 — i18n util (ko/en 폴백)

**파일**: `apps/harness-dashboard/lib/i18n.ts` + `lib/__tests__/i18n.test.ts`

```ts
export type Lang = "ko" | "en";
export function t(key: string, lang: Lang = "ko"): string;
```

- 단일 dict (룸 라벨 / 배너 메시지 / 드로어 탭 라벨).
- ko 우선, en fallback, 없으면 key 그대로.
- vitest: 3 case (ko hit / en fallback / missing).

**적용**: page.tsx 의 errorBanner 메시지 + Drawer 탭 라벨 + 헤더 부제. 룸 라벨은 RoomState.label_ko/en 에 이미 있음 (i18n util 거치지 않음).

### F-024 — Playwright E2E 6 시나리오

**파일**: `apps/harness-dashboard/e2e/brick-office.spec.ts` 갱신 (기존 2 시나리오 + 4 추가).

- 시나리오 3-6 은 progress.json 의 직접 mutation + SSE 갱신 대기 패턴 사용.

### F-025 — 성능 가드

**파일**: `apps/harness-dashboard/e2e/perf.spec.ts`

- SSE latency 측정 5회 평균 (fs.write timestamp ↔ 클라이언트 onmessage receipt 시간차).
- 통과 기준: <500ms 평균 (Plan 권고. <200ms 는 시스템 floor 임박).
- 결과를 progress.log 에 보고.

## Pre-Eval Gate

- tsc clean
- vitest (Sprint 1+2 17 + i18n 3 = 20)
- playwright 6 + perf 1 = 7 통과
