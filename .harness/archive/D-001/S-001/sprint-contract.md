---
docmeta:
  id: sprint-contract
  title: Sprint Contract — Sprint 1 / Phase C-1 (Foundation)
  type: output
  createdAt: 2026-05-07T00:00:00Z
  updatedAt: 2026-05-07T00:00:00Z
  source:
    producer: agent
    skillId: harness-generator-backend
  inputs:
    - documentId: plan
      uri: ./plan.md
      relation: output-from
      sections:
        - sourceRange: { startLine: 102, endLine: 140 }   # plan §5 아키텍처
          targetRange: { startLine: 24, endLine: 80 }     # BE 섹션 파일 경로/엔드포인트
        - sourceRange: { startLine: 162, endLine: 190 }   # plan §8.5 라이브 미리보기
          targetRange: { startLine: 32, endLine: 50 }     # F-001 dev:dashboard 의무
    - documentId: feature-list
      uri: ./feature-list.json
      relation: output-from
    - documentId: api-contract
      uri: ./api-contract.json
      relation: output-from
      sections:
        - sourceRange: { startLine: 1, endLine: 200 }
          targetRange: { startLine: 60, endLine: 80 }     # /api/snapshot 명세
  tags: [sprint-contract, sprint-1, phase-c-1, foundation, backend]
---

# Sprint Contract — Sprint 1 / Phase C-1 (Foundation)

> Sprint 1 은 **Foundation**: scaffold + 정적 평면도 + idle 미니피규어. SSE/4상태/드로어는 Sprint 2.

## BE 섹션 (Generator-Backend 작성)

### F-001 — Next.js + Tailwind scaffold

**작업 범위**: `apps/harness-dashboard/` 신규 패키지 생성.

**파일**:
- `apps/harness-dashboard/package.json` — name `@walwal-harness/dashboard`, scripts: `dev:dashboard`(port 3001), `build`, `start`, `test`(vitest), `e2e`(playwright). deps: `next@^15`, `react@^19`, `react-dom@^19`, `chokidar@^4`. devDeps: `typescript@^5`, `@types/{node,react,react-dom}`, `tailwindcss@^3`, `postcss`, `autoprefixer`, `vitest@^2`, `@vitest/ui`, `@playwright/test@^1`.
- `apps/harness-dashboard/next.config.mjs` — appDir 기본, `output: 'standalone'` 미설정.
- `apps/harness-dashboard/tsconfig.json` — `target: ES2022`, `moduleResolution: bundler`, `paths: { "@/*": ["./*"] }`.
- `apps/harness-dashboard/tailwind.config.ts` — content 패턴, 색 토큰: `aura-idle/typing/talking/alert`.
- `apps/harness-dashboard/postcss.config.js`
- `apps/harness-dashboard/app/layout.tsx` — root layout (FE 가 §F-002 에서 워드마크 주입).
- `apps/harness-dashboard/app/page.tsx` — placeholder ("Brick Office boot — see Sprint 1 progress").
- `apps/harness-dashboard/app/globals.css` — Tailwind directives + reset.

**라이브 미리보기 의무 (plan §8.5)**: Generator-FE 가 작업 시작 시 `(cd apps/harness-dashboard && npm run dev:dashboard)` 를 백그라운드 실행하고 사용자에게 `http://localhost:3001` 안내. dev:dashboard 스크립트는 `next dev -p 3001`.

**검증**:
- `test -d apps/harness-dashboard`
- `jq -e '.scripts["dev:dashboard"]' apps/harness-dashboard/package.json`
- `cd apps/harness-dashboard && npx tsc --noEmit` (타입 체크)

### F-003 — lib/safe-json.ts + 단위 테스트

**파일**:
- `apps/harness-dashboard/lib/safe-json.ts` — `readJsonSafe<T>(filePath): { ok: true; value: T } | { ok: false; reason: 'missing' | 'corrupt'; error?: unknown }`. `fs.readFileSync` + try/catch. 절대 throw 하지 않음.
- `apps/harness-dashboard/lib/__tests__/safe-json.test.ts` — vitest. 3 cases: valid JSON / 손상 JSON / 누락 파일.

**검증**:
- `cd apps/harness-dashboard && npx vitest run lib/__tests__/safe-json.test.ts` → 3 PASS

### F-004 — lib/agent-roster.ts + lib/harness-state.ts + 테스트

**파일**:
- `apps/harness-dashboard/lib/agent-roster.ts` — 14명 정적 SoT. 각 entry: `{ id, name, dept, room, talkingPreviewMaxLen?: number }`. agency-mapping.md §"조직 구성" 에서 1회 파생.
- `apps/harness-dashboard/lib/types.ts` — `HarnessSnapshot`, `AgentState`, `RoomState`, `GoalCard`, `ArchiveStat`, `MeetingsState`, `ErrorBanner` (api-contract.json 스키마와 1:1).
- `apps/harness-dashboard/lib/harness-state.ts` — `readHarnessState(rootDir: string): HarnessSnapshot`.
  - `progress.json` 읽기 → safe-json. 손상/누락 시 `errorBanner` 세팅 + 빈 스냅샷.
  - `agent-roster` 14명 + `progress.json` 의 current/completed/meetings/failure/service_ops 정보 머지.
  - 모든 에이전트 default `minifigState: "idle"` (Sprint 1 은 단일 상태). state-mapping 은 Sprint 2.
  - rooms[] 7개 + metrics 슬롯 (cto/cqo/service_ops 에서 발췌).
  - archive: `.harness/archive/` 의 `sprint-*` 디렉토리 카운트 + 최근 3개.
  - meetings: `progress.json.meetings.{active, cadence, next_scheduled}`.
- `apps/harness-dashboard/lib/__tests__/harness-state.test.ts` — vitest, tmp dir 시나리오:
  1. tmp/.harness/progress.json 정상 → 14 agents idle
  2. tmp/.harness 누락 → errorBanner.level === 'error'
  3. tmp/.harness/progress.json 손상 → errorBanner.level === 'error'

**검증**:
- `vitest run lib/__tests__/harness-state.test.ts` → 3 PASS

### F-005 — GET /api/snapshot Route Handler

**파일**:
- `apps/harness-dashboard/app/api/snapshot/route.ts` — Next.js Route Handler.
  - `import { readHarnessState } from '@/lib/harness-state'`
  - `export const dynamic = 'force-dynamic'` (캐시 금지)
  - `export async function GET()`: rootDir = process.cwd 의 부모로 추적해 `.harness/` 위치 찾기 (env `HARNESS_ROOT` override 가능).
  - 응답: `Response.json(snapshot, { status: 200 })`. 절대 5xx 로 떨어지지 않음.

**검증**:
- `npm run dev:dashboard` (백그라운드) → `curl -s http://localhost:3001/api/snapshot | jq -e '.version, .agents | length == 14'`
- progress.json 임시 백업 → `curl ...` 200 + `errorBanner.level == "error"`

### BE 섹션 완료 기준 (Pre-Eval Gate)

- [ ] `cd apps/harness-dashboard && npx tsc --noEmit` PASS
- [ ] `vitest run` 모든 테스트 PASS (safe-json 3 + harness-state 3)
- [ ] `curl http://localhost:3001/api/snapshot` 200 + 스키마 검증
- [ ] `feature-list.json` 의 F-001/F-003/F-004/F-005 `passes` 에 `generator-backend` 추가

## FE 섹션 (Generator-Frontend)

### 라이브 미리보기 (의무)

`(cd apps/harness-dashboard && npm run dev:dashboard)` 를 백그라운드 실행. 사용자에게 `http://localhost:3001` 안내. F-002 부터 가시 결과 노출.

### F-002 — 글로벌 layout + Brick Office 워드마크 + 색 토큰

**파일**:
- `apps/harness-dashboard/components/Wordmark.tsx` — "Brick Office" 로고 텍스트 (LEGO 회피: 단순 sans 또는 슬랩 세리프, 2x4 비율 도형 없음).
- `apps/harness-dashboard/components/Header.tsx` — `<header>` semantic, Wordmark + 부제 ("walwal-harness 라이브 운영 대시보드").
- `apps/harness-dashboard/app/layout.tsx` — `<Header />` 주입.

**검증**:
- `curl http://localhost:3001/` → HTML 안에 "Brick Office" 문자열 + `LEGO` 부재
- Tailwind 토큰 (aura-idle/typing/talking/alert) — 이미 F-001 에서 정의됨, F-002 에서 헤더에 색 사용 검증

### F-006 — Floor SVG 7룸 + iso 좌표 헬퍼

**파일**:
- `apps/harness-dashboard/lib/iso.ts` — `worldToScreen(x: number, y: number): { sx: number; sy: number }`. 30°/30° isometric 변환. 룸 좌표 그리드 상수.
- `apps/harness-dashboard/components/Floor.tsx` — `<g>` 7룸 영역 (CEO·회의실·COO·CTO팀·CQO팀·Service-Ops·아카이브). 영역 겹침 없음. 라벨 ko 우선.
- `apps/harness-dashboard/components/BrickOfficeCanvas.tsx` — `<svg viewBox="0 0 1200 720">` 최상위. props: `snapshot: HarnessSnapshot`. Floor + Rooms + Minifigs 합성.

**검증**:
- 룸 영역 좌표 표 (lib/iso.ts) → 7개 사각형이 viewBox 내부에 들어가고 서로 겹치지 않음 (수동 점검 + 단위 테스트)
- 룸 라벨 한국어 노출

### F-007 — Room + Minifig (idle)

**파일**:
- `apps/harness-dashboard/components/Room.tsx` — props `room: RoomState; agents: AgentState[]`. 룸 외곽 + 라벨 + 좌석 그리드 + 자식 미니피규어.
- `apps/harness-dashboard/components/Minifig.tsx` — props `agent: AgentState`. SVG `<g>`: 머리(원) + 몸통(사다리꼴 isometric) + Aura 외곽선. idle 은 `aura-idle` 색. `<title>` 태그로 이름 hover (CSS only).

**검증**:
- 14명 모두 자기 룸에 idle 상태 렌더 (snapshot 의 agent.room 기준)
- 회색 Aura 외곽선 — `stroke="theme(aura-idle)"`
- hover 시 SVG `<title>` 노출

### F-008 — page.tsx 통합 + Playwright E2E

**파일**:
- `apps/harness-dashboard/app/page.tsx` — RSC. `fetch('/api/snapshot')` → `<BrickOfficeCanvas snapshot={...} />`. errorBanner 시 배너 노출.
- `apps/harness-dashboard/playwright.config.ts` — webServer auto start (`npm run dev:dashboard`), baseURL `http://localhost:3001`.
- `apps/harness-dashboard/e2e/brick-office.spec.ts` — Sprint 1 시나리오 2개:
  1. 빈 .harness → "Run dispatcher first" 배너 노출
  2. 정상 progress.json → 7룸 + 14피규어 idle 렌더 (data-testid 카운트)

### FE 섹션 완료 기준 (Pre-Eval Gate)

- [ ] `npx tsc --noEmit` PASS
- [ ] `vitest run` 모든 테스트 PASS (BE 6 + iso 헬퍼 새 테스트 추가)
- [ ] 브라우저(http://localhost:3001) 에서 시각 확인: 워드마크 / 7룸 / 14피규어 / 룸 라벨
- [ ] `playwright test` 2 시나리오 PASS
- [ ] `feature-list.json` 의 F-002/F-006/F-007/F-008 `passes` 에 `generator-frontend` 추가

## Change Request

### CR-001 (2026-05-07) — 사용자 시각/상호작용 사양 추가, Sprint 2 일부 선반영

**제출자**: Generator-Frontend (사용자 in-flight 피드백 수용)

**배경**: Sprint 1 구현 직후 사용자가 다음을 명시적으로 추가 요청 — (a) SVG 추상 도형 → R3F 메타버스 isometric 3D, (b) 캔버스 2배 크기, (c) 룸간 도어 + 복도 연결, (d) 룸별 capacity 책상/의자, (e) 상태별 액션 (idle 자유 동선 / typing 책상 착석 / talking 회의실 이동), (f) 자유 동선이되 벽 통과 금지 (도어 경유).

**적용 변경 (Sprint 1 안에서 fix, eval 진입 전)**:
- `@react-three/fiber` + `drei` + `three` 도입. SVG 컴포넌트 (`Floor.tsx` / `Minifig.tsx` / `BrickOfficeCanvas.tsx`) 제거.
- `components/three/{Stage3D,Floor3D,Minifig3D}.tsx` 신규.
- `lib/iso.ts` ROOM_RECTS 재배치 (룸간 1유닛 corridor) + `CORRIDOR_RECTS` + `ROAM_POOL` 추가.
- `lib/furniture.ts` — 룸 capacity 기반 책상/의자 + 도어 위치.
- `lib/path-planning.ts` — `zoneAt` + `exitWaypoint` + `planPath` (도어 경유 경로 강제).
- `lib/state-mapping.ts` — Sprint 2 F-012 일부 선반영 (current_agent → typing, meetings.active → talking, failure.agent → red-alert).
- `lib/types.ts` — `AgentState.homeRoom` 추가 (talking 텔레포트 후에도 원래 룸 추적).
- `components/Scene.tsx` — max-w 1920 + aspect-[16/9] 로 시각 면적 확장.

**영향받는 feature**:
- F-002·F-006·F-007·F-008 — 모두 R3F 기반으로 재구현. AC 본질 (워드마크 / 7룸 / 14 미니피규어 / page 통합 + E2E) 은 모두 충족.
- Sprint 2 F-012 (state-mapping) — Sprint 1 에서 부분 선구현.
- Sprint 2 F-013·F-014 (Aura/모션/말풍선) — 기본 시각 표현 선구현 (말풍선은 sphere 인디케이터로 단순화).

**Planner 다음 스프린트 시 결정 요청**:
- (a) Sprint 2 의 F-012/F-013/F-014 를 "이미 충족" 으로 marking 할지, 아니면 SSE 라이브 변경 + 풀 motion 검증을 위해 full re-test 할지
- (b) Kenney/Quaternius CC0 GLB 통합 (Designer 작업) 추가 feature 신설 여부
- (c) Path-planning 의 corridor crossing (수직↔수평 corridor 교차) 를 더 정교한 그래프 탐색으로 업그레이드 필요성

**검증 결과**:
- tsc clean
- vitest 15/15 (safe-json 3 + harness-state 3 + iso 3 + state-mapping 6)
- Playwright E2E 2/2 (DOM 인덱스 7룸·14피규어 검출, "Run dispatcher first" 배너 fallback)
- 시각 캡처: 7룸 + 도어 + 복도 + 책상 + 14 캐릭터 + 자유 동선(룸/복도/잔디 waypoint)

**학습 기록**:
- `gotchas/generator-frontend.md` [G-001] — visual feature 진입 전 톤 레퍼런스 사전 확인 의무
- `memory.md` [M-002] — "isometric" 같은 한 단어 키워드는 표현 폭 넓음, 톤 차원 별도 옵션화
