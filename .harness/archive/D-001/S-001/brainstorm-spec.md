---
docmeta:
  id: brainstorm-spec
  title: Brainstorm Spec — Brick Office 대시보드 MVP (Phase C)
  type: output
  createdAt: 2026-05-07T00:00:00Z
  updatedAt: 2026-05-07T00:00:00Z
  source:
    producer: agent
    skillId: harness-brainstorming
  inputs:
    - documentId: phase-c-handoff-memo
      uri: (inline — 사용자 인계 메모 + 시각/터미널 brainstorm 대화)
      relation: output-from
      note: inline 입력으로 line 주소 없음. 핸드오프 메모의 룸·피규어·인터랙션·상표 회피 항목이 본 spec 전반에 분산 반영됨.
    - documentId: agency-mapping
      uri: ../agency-mapping.md
      relation: output-from
      sections:
        - sourceRange: { startLine: 41, endLine: 53 }   # 조직 구성 트리 (CEO/COO/CTO/CQO/Service-Ops 분기)
          targetRange: { startLine: 46, endLine: 60 }   # spec §3 In — 7개 룸 + 14 미니피규어 정의
        - sourceRange: { startLine: 41, endLine: 53 }   # 동일 조직 트리
          targetRange: { startLine: 136, endLine: 146 } # spec §7 컴포넌트 — Room/Minifig 엔티티 매핑
    - documentId: doctrine-nexus
      uri: ../doctrine/nexus.md
      relation: output-from
      sections:
        - sourceRange: { startLine: 28, endLine: 31 }   # "하나의 하네스 = 하나의 회사" 사상
          targetRange: { startLine: 26, endLine: 30 }   # spec §1 목적 — 회사 메타포 근거
        - sourceRange: { startLine: 32, endLine: 44 }   # P1 Handoff / P2 Evidence-zero 원칙
          targetRange: { startLine: 32, endLine: 42 }   # spec §2 성공 기준 — 라이브 가시화·증거 노출 조항
        - sourceRange: { startLine: 53, endLine: 60 }   # Lifecycle 7 Phases / Planner 모드
          targetRange: { startLine: 194, endLine: 203 } # spec §11 Open Questions Q1 — 스프린트 분할 정책
  tags: [brainstorming, spec, planner-input, phase-c, brick-office, dashboard]
---

# Brainstorm Spec — Brick Office 대시보드 MVP (Phase C)

## 1. 목적 (Purpose)

walwal-harness 의 운영 상태(에이전트 동작·스프린트 진행·GOAL 진척·인시던트)를 **하나의 회사 사옥** 메타포로 시각화한 라이브 대시보드를 구축한다. NEXUS 도큐트린에서 정의한 회사 조직도(CEO/COO/CTO/CQO/Service-Ops + Conductor + Meeting-Manager)를 SVG 2.5D isometric 빌딩의 룸으로 매핑하고, 각 에이전트를 미니피규어로 표현해 동작 상태(idle/typing/talking/red-alert)를 한 화면에서 비교 가능하게 만든다.

목표는 두 가지: (a) Owner 가 "지금 회사가 무엇을 하고 있는가"를 글이 아닌 풍경으로 즉시 파악할 수 있게 한다. (b) 하네스 자체의 동작을 디버깅·소통·온보딩하는 시각 자산이 된다.

## 2. 성공 기준 (Success Criteria)

- [ ] 한 화면에 모든 룸(CEO·회의실·COO·CTO팀·CQO팀·Service-Ops·아카이브)이 isometric으로 표시된다.
- [ ] 에이전트별 미니피규어가 idle/typing/talking/red-alert 4상태로 시각적으로 구분된다 (Aura + 선택적 모션).
- [ ] `.harness/progress.json`, `.harness/progress.log`, `.harness/actions/*` 변경이 **2초 이내** 화면에 반영된다 (chokidar + SSE).
- [ ] 미니피규어 클릭 시 우측 슬라이드 드로어에 **해당 에이전트의 progress.log 필터 + 활성 sprint-contract 발췌** 가 표시된다.
- [ ] 룸 클릭 시 우측 드로어에 **해당 부서의 메트릭** (active sprint, 통과/실패 카운트, last_review/last_audit/last_check 등 부서별 progress.json 슬롯) 이 표시된다.
- [ ] CEO실 벽에 **활성 GOAL 카드** (`progress.json.goals.list[active_id]`) 가 텍스트 카드로 항상 표시된다.
- [ ] 워드마크 "**Brick Office**" 가 헤더에 표시되고 LEGO 상표 회피 점검 통과한다.
- [ ] `progress.json` 손상/누락 시에도 대시보드가 크래시하지 않고 안내 메시지를 표시한다 (memory.md 의 v5.9.4 학습 적용).
- [ ] E2E (Playwright): 첫 로드 → 모든 룸 렌더 → 가짜 progress.json 변경 → 2초 내 미니피규어 상태 전환 → 클릭 → 드로어 열림 시나리오를 검증한다.

## 3. 스코프 (Scope)

### In (Phase C MVP — 풀스코프, T4)
- Next.js 앱 신규 생성: `apps/harness-dashboard/`
- SVG 2.5D isometric 단일 평면도 (Single Floor Plan)
- 7개 룸: CEO, 회의실, COO, CTO팀(BE/FE/Designer/DevOps), CQO팀(Functional/Visual/CodeQuality/Architecture/Security), Service-Ops, 아카이브
- 14명 미니피규어 (CEO 1, COO 1, CTO팀 4, CQO팀 5, Service-Ops 1, Conductor 1, Meeting-Manager 1)
- 4상태 시각화 (idle / typing / talking / red-alert) — Aura 색 발광 + talking 말풍선 + red-alert 진동
- SSE 단방향 푸시 (`app/api/stream/route.ts`)
- chokidar 파일 와처: `.harness/progress.json`, `.harness/progress.log`, `.harness/actions/*`
- 우측 슬라이드 드로어 (피규어 클릭→로그 / 룸 클릭→메트릭, 탭 전환)
- GOAL 카드 (CEO실 벽)
- 회의실 미니피규어 정렬 (`progress.json.meetings.active` 에 등재된 에이전트 피규어를 회의실로 텔레포트)
- 아카이브 룸: `.harness/archive/` 의 완료 sprint 카운트 표시 + 클릭 시 sprint 목록 드로어
- 워드마크: "Brick Office"
- E2E Playwright 테스트 1개

### Out (명시적 제외)
- 양방향 인터랙션 (사용자가 대시보드에서 에이전트 명령 트리거) — Phase D 이후
- 모바일 풀 최적화 (드로어 풀스크린 fallback 만 보장, 평면도는 데스크톱 우선)
- 다중 프로젝트/멀티 하네스 표시
- 사운드 / BGM
- 사용자 계정·권한 (로컬 단일 owner 가정)
- 히스토리 리플레이 / 타임머신 뷰
- 회의록/escalation 본문 inline 렌더 (드로어에서 파일 경로만 노출, 본문은 외부 에디터)
- 데이터 영속화 (모든 데이터는 `.harness/` 파일이 SoT)

## 4. 제약 (Constraints)

- **기술 스택**: Next.js (App Router) + TypeScript + React, fe_stack=react. 렌더링은 순수 SVG (canvas/PixiJS/three.js 사용 금지 — 단순/디버깅/SSR 친화).
- **푸시 프로토콜**: SSE (Server-Sent Events) 단방향. WebSocket 사용 금지 (양방향 불필요, App Router 호환성 우선).
- **데이터 소스**: 오직 `.harness/` 파일 시스템. DB 없음. SoT는 `progress.json`/`progress.log`/`actions/*`/`archive/*`.
- **애니메이션**: CSS keyframe + SVG `<animate>` 만 사용. JS animation loop 금지 (CPU 절약).
- **상표**: LEGO/레고 상표·로고·브릭 패턴(2x4 표준 비율 등) 직접 모방 금지. 자체 isometric 블록 모티프 + 워드마크 "Brick Office".
- **의존성**: `chokidar`, `next`, `react`, `typescript`, `playwright` 외 신규 라이브러리는 Planner 승인 시에만.
- **성능**: 첫 로드 LCP < 2s (로컬), SSE 메시지 latency < 200ms.
- **에러 격리**: `progress.json` 손상/누락/스키마 미스매치 시에도 빈 상태 안내 페이지로 fallback (크래시 금지).
- **권한**: `apps/harness-dashboard/` 쓰기는 Generator-Frontend (UI) + Generator-Backend (SSE/watcher Route Handler). Designer 는 `apps/web/design/` 에 별도 토큰.

## 5. 선택된 접근법 (Chosen Approach)

**Single Floor Plan + Aura/Motion Hybrid + Right Slide-in Drawer + SSE**.

- 모든 룸을 한 평면 isometric으로 펼쳐 한눈에 부서별 동작 비교 가능 (대시보드 본질).
- 미니피규어는 외곽 발광색을 디폴트로 두되 talking 에는 말풍선, red-alert 에는 진동을 추가해 시선을 빼앗는 정보가 균형 잡힘.
- 우측 드로어로 메인 캔버스 컨텍스트를 유지하면서 디테일 노출.
- SSE 가 단방향 푸시·재접속·Edge runtime 호환 모두 만족 — Next.js App Router 표준 패턴.

### 고려했던 대안

- **Multi-Floor Stacked**: 조직 위계는 강조되지만 층 전환 인터랙션이 모니터링 본질을 해침.
- **Hub & Spoke**: 단일 대화창구 룰을 시각화하지만 룸 면적 균형이 어려움.
- **Body Motion (전 피규어 SVG 모션)**: 표현력은 최고지만 14명 동시 모션의 성능 부담 + 디버깅 비용.
- **WebSocket (별도 Node 또는 custom server)**: 대시보드 단방향 요구에 오버스펙 + App Router 권장 패턴 이탈.
- **Polling**: 가장 단순하나 라이브 대시보드의 "살아있는 풍경" 느낌 상실.

## 6. 아키텍처 스케치

```
┌────────────────────────── apps/harness-dashboard/ ────────────────────────┐
│                                                                           │
│  app/                                                                     │
│    page.tsx ─────────► <BrickOfficeCanvas />                              │
│      ├─ <Floor />              SVG 평면 + 룸 영역                         │
│      ├─ <Room id={..} />       각 룸 (CEO/회의실/COO/CTO팀/CQO팀/Ops/Arch)│
│      │     └─ <Minifig agent={..} state={..} />                           │
│      ├─ <GoalCard />           CEO실 벽                                   │
│      └─ <Drawer panel={..} />  우측 슬라이드                              │
│                                                                           │
│    api/                                                                   │
│      stream/route.ts ──► SSE: GET /api/stream                             │
│      │   - chokidar.watch(.harness/{progress.json,progress.log,actions}) │
│      │   - on change → JSON.stringify(diff) → res.write(`data: ...\n\n`) │
│      │                                                                    │
│      snapshot/route.ts ─► GET /api/snapshot  (초기 1회 풀 로드)           │
│      └ readHarnessState() 가 전체 상태를 합쳐 반환                        │
│                                                                           │
│  lib/                                                                     │
│    harness-state.ts   progress.json + meetings + cto/cqo/ops 슬롯 합치기  │
│    state-mapping.ts   agent_status → minifig state 룰                     │
│    safe-json.ts       손상 fallback (memory.md v5.9.4 학습)               │
│                                                                           │
└─── .harness/ (SoT, 외부) ─────────────────────────────────────────────────┘
        progress.json, progress.log, actions/*, archive/*

       ┌──────── client (browser) ─────────┐
       │  EventSource('/api/stream')       │
       │     └ on message → setState       │
       │  fetch('/api/snapshot') 1회       │
       └───────────────────────────────────┘
```

## 7. 주요 컴포넌트 / 엔티티

- **BrickOfficeCanvas** — 최상위 SVG 캔버스. viewBox 기반 반응형. 룸 좌표 grid 정의.
- **Room** — { id, label, agents[], dept, x/y/w/h, accentColor } — 7개. 클릭 시 onSelectRoom.
- **Minifig** — { agentId, state, name, lastActivity } — 14명. Aura 색은 state 매핑. 클릭 시 onSelectAgent.
- **GoalCard** — `progress.json.goals.list[goals.active_id].title/text` 렌더. CEO실 벽 좌표에 고정.
- **Drawer** — { open, mode: "agent-log" | "room-metrics" | "archive-list", payload }. 탭으로 모드 전환 가능.
- **HarnessState** (서버) — progress.json + meetings + cto/cqo/ops 슬롯 통합 스냅샷.
- **StateEvent** (SSE 메시지) — { type: "snapshot" | "patch", payload }.
- **AgentStateMapping** (룰) — `running` → typing, `completed` → idle, `blocked`/escalation → red-alert, `meetings.active 포함` → talking.

## 8. 데이터 흐름 (Data Flow)

```
.harness/progress.json (write by 기존 에이전트)
        ↓ chokidar 'change'
[Server] api/stream/route.ts
   └─ readHarnessState() → 이전 스냅샷과 diff
        ↓ SSE write
[Client] EventSource('/api/stream')
   └─ React state setState → re-render BrickOfficeCanvas
        ↓ 시각 변환
화면: 미니피규어 aura 색/모션, 회의실 인원 이동, GOAL 카드 텍스트
```

초기 로드:
1. 클라이언트가 `/api/snapshot` 으로 풀 스냅샷 fetch.
2. `EventSource('/api/stream')` 으로 이후 변경분 구독.
3. 끊어지면 EventSource 자동 재접속, 재접속 시 서버는 첫 메시지로 다시 풀 스냅샷 송출.

## 9. 에러 처리 전략

- **`progress.json` 손상/JSON parse 실패**: `safe-json.ts` 가 빈 스냅샷 반환 + 빌딩을 회색 톤으로 + "Harness state unreadable — check .harness/progress.json" 배너 (memory.md `[2026-04-09]` v5.9.4 학습 적용).
- **`progress.json` 누락**: 빈 빌딩 + "Run dispatcher first" 배너.
- **chokidar 에러**: 워처 재시작 1회 시도 → 실패 시 폴링 fallback (5초 간격) + 콘솔 경고.
- **SSE 연결 끊김**: 클라이언트 EventSource 자동 재접속. 5회 연속 실패 시 사용자에 토스트.
- **알 수 없는 에이전트 ID**: 룸 매핑에 없으면 "외부인" 영역에 회색 피규어로 노출 (drift 감지용).
- **회의실 over-capacity** (`meetings.active` 가 회의실 좌석 초과): 좌석 wraparound + "+N" 카운터.
- 사용자 노출 메시지는 모두 한국어 + 영문 병기.

## 10. 테스트 전략 (High-level)

- **Unit (Vitest)**:
  - `state-mapping.ts`: agent_status → minifig state 룰 테이블.
  - `safe-json.ts`: 정상/손상/누락 입력 분기.
  - `harness-state.ts`: meetings.active 가 회의실로 이동시키는 머지 로직.
- **Integration (Vitest + 임시 디렉토리)**:
  - chokidar watch 가 fs.write 후 200ms 내 리스너 호출.
  - SSE Route Handler: mock fs 변경 → response stream 에 `data: ...` 출력 검증.
- **E2E (Playwright, eval-functional/visual 게이트)**:
  - 시나리오 1: 빈 `.harness/` 상태에서 첫 로드 → "Run dispatcher first" 배너.
  - 시나리오 2: 정상 progress.json → 7개 룸 + 14 피규어 렌더 → idle 상태.
  - 시나리오 3: 외부에서 progress.json 의 한 에이전트를 `running` 으로 바꿈 → 2초 내 typing 상태 전환.
  - 시나리오 4: meetings.active 에 추가 → 해당 피규어가 회의실 룸으로 이동.
  - 시나리오 5: 미니피규어 클릭 → 우측 드로어 열림 + 해당 에이전트 로그 노출.
  - 시나리오 6: 룸 클릭 → 메트릭 탭 표시.
- **Visual (eval-visual)**: 7개 룸 레이아웃 일관성, 4상태 색대비, GOAL 카드 가독성, 워드마크 위치/크기, LEGO 상표 회피 체크.

## 11. Open Questions (Planner 가 확정할 것)

- Q1: **스프린트 분할 정책** — T4 풀스코프를 한 스프린트로 강행할지, Phase C-1(렌더+SSE)/C-2(인터랙션)/C-3(GOAL+회의실+아카이브) 로 분할할지. memory.md `feedback_no_carryover_with_known_bugs` 정책에 따라 한 스프린트 안에 fix 가능한 단위로 자르는 것을 권장.
- Q2: **미니피규어 ↔ 에이전트 매핑 테이블의 SoT** — `apps/harness-dashboard/lib/agent-roster.ts` 로 둘지, `.harness/agency-mapping.md` 에서 파생할지. Planner 가 결정.
- Q3: **GOAL 카드 텍스트 길이 제한** — `progress.json.goals.list[*].title` 만 표시할지, 짧은 description 까지 자동 truncate 할지.
- Q4: **회의실 좌석 좌표** — 5종 회의(meetings.cadence 별 active 가 다름)에서 최대 동시 좌석 수 결정. 현재 nexus.md 상 standup/all-hands/phase-gate 등 cadence 별 인원 차이.
- Q5: **아카이브 카운트 단위** — sprint 단위인지 phase 단위인지. `.harness/archive/` 의 디렉토리 명명 규칙 확정 필요.
- Q6: **SSE 메시지 포맷** — 풀 스냅샷 매번 vs JSON Patch (RFC 6902). 첫 구현은 풀 스냅샷 (단순), 14명 + 7룸 규모면 페이로드 ~5KB 추정.
- Q7: **i18n** — 룸 라벨/배너를 한국어 우선 + 영문 폴백, 또는 영문 only? 현재 progress.log 가 한국어 혼재.
- Q8: **dev 통합 러너** — `npm run dev` 가 dashboard 도 함께 띄울지, 별도 포트 (3001) 분리할지. AGENTS.md 의 통합 러너 정책과 정합.

## 12. 사용자 승인 로그

- 2026-05-07 — 사용자 dispatcher 단계 Phase C 시작 + Brainstormer Y 승인
- 2026-05-07 — 시각 결정: Single Floor Plan(A) 클릭 선택 (browser event 기록)
- 2026-05-07 — 미니피규어 시각화: D. Hybrid (Aura + Selective Motion) 텍스트 응답
- 2026-05-07 — 인터랙션 패널: A. Right Slide-in Drawer 텍스트 응답
- 2026-05-07 — 푸시 프로토콜: SSE 텍스트 응답
- 2026-05-07 — MVP 스코프: T4 풀스코프 (Planner 가 분할 평가) 텍스트 응답
- 2026-05-07 — 워드마크: Brick Office 텍스트 응답
- 2026-05-07 HH:MM — (대기) 작성 spec 파일 리뷰 통과
