---
docmeta:
  id: plan
  title: Plan — Brick Office 대시보드 (Phase C, FULLSTACK)
  type: output
  createdAt: 2026-05-07T00:00:00Z
  updatedAt: 2026-05-07T00:00:00Z
  source:
    producer: agent
    skillId: harness-planner
  inputs:
    - documentId: brainstorm-spec
      uri: ./brainstorm-spec.md
      relation: output-from
      sections:
        - sourceRange: { startLine: 26, endLine: 30 }      # §1 Purpose
          targetRange: { startLine: 24, endLine: 30 }      # plan §1 제품 개요
        - sourceRange: { startLine: 32, endLine: 42 }      # §2 Success Criteria
          targetRange: { startLine: 32, endLine: 46 }      # plan §2 목표
        - sourceRange: { startLine: 46, endLine: 69 }      # §3 Scope In/Out
          targetRange: { startLine: 48, endLine: 80 }      # plan §3 스코프
        - sourceRange: { startLine: 71, endLine: 81 }      # §4 Constraints
          targetRange: { startLine: 82, endLine: 100 }     # plan §4 제약
        - sourceRange: { startLine: 100, endLine: 134 }    # §6 Architecture sketch
          targetRange: { startLine: 102, endLine: 140 }    # plan §5 아키텍처
        - sourceRange: { startLine: 194, endLine: 203 }    # §11 Open Questions
          targetRange: { startLine: 192, endLine: 220 }    # plan §8 Open Q 해소
    - documentId: pipeline
      uri: ./pipeline.json
      relation: output-from
    - documentId: agency-mapping
      uri: ../agency-mapping.md
      relation: output-from
      sections:
        - sourceRange: { startLine: 41, endLine: 53 }
          targetRange: { startLine: 142, endLine: 175 }    # plan §6 부서·룸 매핑
  tags: [plan, phase-c, brick-office, fullstack, dashboard]
---

# Plan — Brick Office 대시보드 (Phase C, FULLSTACK)

## 1. 제품 개요

walwal-harness 의 운영 상태를 회사 사옥 메타포로 시각화한 라이브 대시보드(`apps/harness-dashboard/`)를 구축한다. NEXUS 도큐트린의 조직도(CEO/COO/CTO/CQO/Service-Ops + Conductor + Meeting-Manager)를 SVG 2.5D isometric 빌딩의 7개 룸 + 14명 미니피규어로 매핑하고, `.harness/progress.json` · `progress.log` · `actions/*` · `archive/*` 의 변화를 chokidar + SSE 로 실시간 반영한다. 상표는 "Brick Office", LEGO 직접 모방 금지.

## 2. 목표 (Success Criteria)

- [ ] 한 화면 Single Floor Plan 에 7개 룸 + 14 미니피규어가 동시 렌더된다.
- [ ] 미니피규어 4상태(idle/typing/talking/red-alert)를 Hybrid (Aura + 선택적 모션)로 시각화한다.
- [ ] `.harness/progress.json` 변경이 **2초 이내** 화면에 반영된다 (chokidar + SSE).
- [ ] 미니피규어 클릭 → 우측 슬라이드 드로어 (agent-log 탭) / 룸 클릭 → 드로어 (room-metrics 탭).
- [ ] CEO실 벽에 활성 GOAL 카드(title + 200자 truncate description) 노출.
- [ ] `meetings.active` 의 에이전트는 회의실 룸으로 텔레포트 (좌석 7개 + wraparound).
- [ ] 아카이브 룸에 `.harness/archive/sprint-*` 카운트 + 클릭 시 목록 드로어.
- [ ] `progress.json` 손상/누락 시 크래시 없이 안내 배너 (memory.md v5.9.4 학습).
- [ ] LCP < 2s (로컬), SSE latency < 200ms.
- [ ] Playwright E2E 6 시나리오 + Vitest unit/integration 통과.
- [ ] LEGO 상표 회피 점검(자체 isometric 모티프 + "Brick Office" 워드마크) 통과.

## 3. 스코프

### In (Phase C 전체 = C-1 + C-2 + C-3)

- 신규 패키지 `apps/harness-dashboard/` (Next.js App Router + TypeScript + Tailwind)
- 7개 룸: CEO, 회의실, COO, CTO팀(BE/FE/Designer/DevOps), CQO팀(Functional/Visual/CodeQuality/Architecture/Security), Service-Ops, 아카이브
- 14 미니피규어: Dispatcher(CEO 1) · Conductor(CTO팀 무대 뒤 1) · Meeting-Manager(회의실 1) · Planner(COO 1) · CTO팀 4 · CQO팀 5 · Service-Ops 1
- 4상태 시각화 (Hybrid: Aura + talking 말풍선 + red-alert 진동)
- SSE 단방향 푸시 (`GET /api/stream`) + 초기 풀 스냅샷 (`GET /api/snapshot`)
- chokidar watcher: progress.json / progress.log / actions/* / archive/*
- 우측 슬라이드 드로어 (agent-log / room-metrics / archive-list 탭)
- GOAL 카드 (CEO실 벽)
- 회의실 텔레포트 (meetings.active 기반)
- 아카이브 룸 + sprint 카운트
- i18n (ko 우선, en fallback) — 룸 라벨/배너
- Playwright E2E 6 시나리오 + Vitest unit/integration

### Out (명시적 제외)

- 양방향 인터랙션 (대시보드에서 에이전트 명령 트리거)
- 모바일 풀 최적화 (드로어 풀스크린 fallback 만)
- 다중 프로젝트/멀티 하네스
- 사운드/BGM
- 사용자 계정·권한
- 히스토리 리플레이
- 회의록/escalation 본문 inline 렌더 (경로 링크만)
- DB/영속화 (모든 데이터는 `.harness/` 파일이 SoT)

## 4. 제약

- **스택**: Next.js 15+ App Router, React 19, TypeScript 5+, Tailwind CSS, Vitest, Playwright. fe_stack=`react`.
- **렌더링**: 순수 SVG (canvas/PixiJS/three.js 금지).
- **푸시**: SSE only (WebSocket 금지).
- **데이터 SoT**: `.harness/` 파일 시스템.
- **애니메이션**: CSS keyframe + SVG `<animate>` 만 (JS rAF 루프 금지).
- **상표**: LEGO 로고/2x4 표준 비율 직접 모방 금지. 자체 isometric 블록 모티프 + "Brick Office" 워드마크.
- **포트**: dashboard dev 는 3001 (기존 통합 러너 영향 금지).
- **권한**: `apps/harness-dashboard/` 쓰기는 Generator-Backend (lib/, app/api/) + Generator-Frontend (app/, components/, public/, design/).

## 5. 아키텍처

```
apps/harness-dashboard/
  app/
    layout.tsx                  글로벌 + Brick Office 헤더
    page.tsx                    초기 snapshot fetch + SSE 구독 + <BrickOfficeCanvas/>
    api/
      snapshot/route.ts         GET → HarnessSnapshot (lib.harness-state.read())
      stream/route.ts           GET → text/event-stream (chokidar.watch + diff push)
  components/
    BrickOfficeCanvas.tsx       <svg viewBox> 단일 캔버스
    Floor.tsx                   7룸 좌표 그리드
    Room.tsx                    {id, label, agents[], dept} props
    Minifig.tsx                 {agentId, state, name} → Aura/모션
    GoalCard.tsx                CEO실 벽 고정 좌표
    Drawer.tsx                  우측 슬라이드 (agent-log/room-metrics/archive-list 탭)
    Wordmark.tsx                "Brick Office"
  lib/
    agent-roster.ts             14명 정적 매핑 (SoT, agency-mapping.md 에서 1회 파생)
    harness-state.ts            progress.json + meetings + cto/cqo/ops 슬롯 + archive 머지
    state-mapping.ts            agent_status / meetings.active / failure → minifig state 룰
    safe-json.ts                손상/누락 fallback
    i18n.ts                     ko/en 폴백 (룸 라벨, 배너)
  hooks/
    useHarnessStream.ts         EventSource 구독 + setState
  e2e/
    brick-office.spec.ts        Playwright 6 시나리오
  package.json                  next/react/tailwind/chokidar/vitest/playwright
  next.config.mjs
  tsconfig.json
  tailwind.config.ts
```

데이터 흐름:

```
.harness/progress.json (외부 에이전트가 write)
   ↓ chokidar 'change'
api/stream/route.ts: harness-state.read() → JSON.stringify(snapshot) → SSE write
   ↓ EventSource onmessage
useHarnessStream → setState
   ↓
BrickOfficeCanvas re-render (Aura/모션, 회의실 텔레포트, GOAL 카드)
```

## 6. 부서 ↔ 룸 ↔ 미니피규어 매핑 (agency-mapping.md 출처)

| Room | Dept | Agents (id → name) |
|---|---|---|
| CEO | Dispatcher | dispatcher → CEO (Dispatcher) |
| 회의실 | Meeting | meeting-manager → Meeting Manager |
| COO | Planner | planner → COO (Planner) |
| CTO팀 | Generator | conductor → Conductor · generator-backend → CTO Lead BE · generator-frontend → CTO Lead FE · generator-designer → Designer · generator-devops → DevOps |
| CQO팀 | Evaluator | cqo → CQO Lead · evaluator-functional → Eval Func · evaluator-visual → Eval Visual · evaluator-code-quality → Eval CQ · evaluator-architecture → Eval Arch · evaluator-security → Eval Sec |
| Service-Ops | Operations | service-ops → Service Ops |
| 아카이브 | Archive | (피규어 없음, sprint 박스 표시) |

총 미니피규어 14명 (Dispatcher 1 · Meeting-Manager 1 · Planner 1 · Conductor 1 · CTO팀 4 · CQO팀 5 · Service-Ops 1).

상태 매핑 (`state-mapping.ts`):

| 조건 (progress.json) | minifig state | Aura | 추가 모션 |
|---|---|---|---|
| `agent_status == "running"` 이고 `current_agent == self` | typing | 청록 펄스 | (없음) |
| `meetings.active` 에 self 포함 | talking | 황 깜빡 | 말풍선 |
| `failure.agent == self` 또는 `service_ops.incident.open` 에 dept 포함 | red-alert | 빨강 점멸 | 진동 |
| 그 외 (`completed`, `pending`, `idle`) | idle | 회색 | (없음) |

## 7. 스프린트 분할 (3 sprints)

**Sprint 1 (Phase C-1) — Foundation**: scaffold, safe-json, harness-state, snapshot API, 정적 평면도 + idle 미니피규어. 데이터는 1회 fetch (SSE 없음).

**Sprint 2 (Phase C-2) — Live + Interaction**: chokidar + SSE, 4상태 시각화 (Aura + 모션), 우측 드로어 (agent-log + room-metrics 탭), 클릭 핸들러.

**Sprint 3 (Phase C-3) — Polish + E2E**: GOAL 카드, 회의실 텔레포트, 아카이브 룸 + 드로어, i18n, Playwright E2E, 성능 가드.

각 sprint 시작 시점에 ready feature ≥ 3 보장 (feature-list.json 참조).

## 8. Open Questions 해소 (brainstorm-spec.md §11)

| Q | 결정 |
|---|---|
| Q1 분할 | **3 sprint 분할** (C-1/C-2/C-3) — memory.md no-carryover-with-known-bugs + ready≥3 룰 |
| Q2 agent-roster SoT | `apps/harness-dashboard/lib/agent-roster.ts` (정적, agency-mapping.md 1회 파생) |
| Q3 GOAL 카드 | `title` 전체 + `description` 200자 truncate("…") |
| Q4 회의실 좌석 | 7석 + wraparound ("+N" 카운터) |
| Q5 아카이브 단위 | sprint 단위. 디렉토리: `.harness/archive/sprint-N-<phase>/` |
| Q6 SSE 포맷 | 풀 스냅샷 매번 (페이로드 ~5KB, JSON Patch 는 후속 최적화) |
| Q7 i18n | ko 우선, en fallback. 룸 라벨/배너만 i18n. progress.log 그대로 |
| Q8 dev 러너 | 별도 포트 3001. `npm run dev:dashboard` 추가, 기존 `npm run dev` 무영향 |

## 8.5 라이브 미리보기 정책 (의무)

Phase C 의 자연스러운 부산물로 `apps/harness-dashboard/` 자체가 라이브 결과 사이트가 된다. Generator 작업 중에 사용자가 즉시 화면을 보고 코멘트할 수 있도록 다음을 의무화한다.

- **Generator-Frontend 는 Phase C 작업 시작 시 `npm run dev:dashboard`(port 3001)를 백그라운드로 항상 띄운다.** 작업이 끝나기 전까지 종료하지 않는다.
- **Generator 는 사용자에게 `http://localhost:3001` 을 안내**하고 변경마다 HMR 로 자동 갱신됨을 명시한다.
- **사용자 코멘트는 즉각 처리.** sprint 내 fix 가 가능하면 같은 sprint 에서 해결하고, 구조적 변경이 필요하면 `## Change Request` 로 Planner 회신.
- 같은 Generator-Backend 도 SSE/snapshot 변경 시 dev 서버를 재시작 가능 (Next.js Route Handler 는 핫 리로드 지원).
- F-001 의 AC 에 dev:dashboard 스크립트 정의가 포함되며, F-002 완료 시점부터 첫 가시 결과(워드마크 헤더)가 노출된다.

가시 결과 단계 표:

| Feature | 라이브 사이트에서 보이는 것 |
|---|---|
| F-002 완료 | 헤더에 "Brick Office" 워드마크 |
| F-006 완료 | 7룸 빈 평면도 SVG |
| F-007 완료 | 14 미니피규어 idle 상태 렌더 |
| F-008 완료 | 실제 `.harness/progress.json` 반영 (Sprint 1 핵심) |
| F-013 완료 | 4상태 Aura 시각화 (Sprint 2) |
| F-018 완료 | 클릭 → 우측 드로어 (Sprint 2 완료) |
| F-024 완료 | E2E 6 시나리오 모두 통과 (Sprint 3 완료) |

## 9. 검증 방법

- **Vitest** (`apps/harness-dashboard/` 내):
  - `lib/safe-json.test.ts` — 정상/손상/누락 분기
  - `lib/state-mapping.test.ts` — 상태 매핑 테이블 전수
  - `lib/harness-state.test.ts` — 임시 디렉토리에서 fs.write 후 snapshot 머지
- **Integration**:
  - chokidar watcher: tmp dir 변경 → 200ms 내 콜백
  - SSE Route: mock fs 변경 → response stream에 `data: ...` 송출
- **Playwright E2E** (`e2e/brick-office.spec.ts`):
  1. 빈 `.harness/` → "Run dispatcher first" 배너
  2. 정상 progress.json → 7룸 + 14피규어 idle 렌더
  3. progress.json patch (agent_status=running) → 2초 내 typing 전환
  4. meetings.active 추가 → 피규어 회의실 텔레포트
  5. 미니피규어 클릭 → Drawer 열림 + agent-log 탭
  6. 룸 클릭 → Drawer room-metrics 탭
- **Visual**: 7룸 정렬, 4상태 색대비(WCAG AA), GOAL 카드 가독성, 워드마크, LEGO 상표 회피.
- **성능**: LCP < 2s (Lighthouse 로컬), SSE 메시지 latency < 200ms (Date.now 비교).

## 10. 리스크 & 완화

| 리스크 | 완화 |
|---|---|
| chokidar 가 macOS 에서 이벤트 누락 | `usePolling: false` 우선, 누락 감지 시 폴링 fallback (5초) |
| SSE 가 dev 모드 HMR 과 충돌 | dev 에서 EventSource 재접속 로깅 + 무한 루프 가드 |
| LEGO 상표 위반 가능성 | Visual eval 에서 워드마크/블록 모양 체크리스트 강제 |
| 미니피규어 동시 모션 성능 저하 | CSS animation 만 사용, 14개 동시 가능성 사전 측정 |
| progress.json 스키마 미스매치 (드리프트) | safe-json + zod 또는 수동 가드 + "Unknown agent" 회색 처리 |
