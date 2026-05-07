---
docmeta:
  id: evaluation-code-quality
  title: Evaluation — Code Quality (Sprint 1 / Phase C-1)
  type: output
  createdAt: 2026-05-07T00:00:00Z
  updatedAt: 2026-05-07T00:00:00Z
  source:
    producer: agent
    skillId: harness-evaluator-code-quality
  inputs:
    - documentId: sprint-contract
      uri: ./sprint-contract.md
      relation: output-from
      sections:
        - sourceRange: { startLine: 28, endLine: 105 }     # BE 섹션 명세
          targetRange: { startLine: 36, endLine: 70 }      # 본 평가 §C1-C5
        - sourceRange: { startLine: 107, endLine: 165 }    # FE 섹션 명세
          targetRange: { startLine: 36, endLine: 70 }      # 본 평가 §C1-C5
        - sourceRange: { startLine: 167, endLine: 220 }    # Change Request CR-001
          targetRange: { startLine: 78, endLine: 98 }      # 본 평가 §Contract divergence + verdict
    - documentId: feature-list
      uri: ./feature-list.json
      relation: output-from
    - documentId: api-contract
      uri: ./api-contract.json
      relation: output-from
  tags: [evaluation, code-quality, sprint-1, phase-c-1, PASS]
---

# Evaluation — Code Quality (Sprint 1 / Phase C-1)

## Verdict: **PASS** (Weighted 3.00 / 3.00)

평가자: Evaluator-Code-Quality (적대적 모드 / 정적 분석 only / 동작 검증 X).

---

## Step 0 — Diff Scope

신규 패키지 `apps/harness-dashboard/` 가 통째로 untracked. 변경 파일:

```
.harness/gotchas/generator-frontend.md      (M-002 학습 등록)
.harness/memory.md                          (docmeta + M-002)
.harness/progress.json                      (state transitions)
AGENTS.md                                   (Phase C, IA-MAP 세분화, 권한 매트릭스 갱신)
.harness/actions/{brainstorm-spec, plan, feature-list, api-contract, sprint-contract}.md/.json
apps/harness-dashboard/                     (신규)
  app/{layout,page,globals.css,api/snapshot/route}
  components/{Header, Wordmark, Scene, three/{Stage3D, Floor3D, Minifig3D}}
  lib/{safe-json, types, agent-roster, harness-root, harness-state,
       state-mapping, iso, furniture, path-planning}
  lib/__tests__/{safe-json, iso, harness-state, state-mapping}.test.ts
  e2e/brick-office.spec.ts
  package.json + next.config.mjs + tsconfig.json + tailwind.config.ts +
  postcss.config.js + vitest.config.ts + playwright.config.ts + .gitignore
```

총 작업물 ~2,100 LOC + 설정. 변경 폭 정상 (>50 변경 한도 미초과 — Planner 에스컬레이션 불요).

## Step 1 — Static Toolchain

| Tool | Result | 비고 |
|---|---|---|
| `tsc --noEmit` (strict) | **PASS** | 출력 무 |
| `eslint .` | **N/A** | ESLint v9 flat config 미설정. tsc strict + 테스트로 정적 게이트 충족. (Planner 에서 다음 스프린트 시 eslint flat config 도입 권고) |
| `vitest run` | **PASS** | 15/15 (safe-json 3 + iso 3 + harness-state 3 + state-mapping 6) |

Step 1 통과 → C1-C5 진행.

## Step 2 — C1-C5 Axis Scoring

### C1. Layer & Boundary — Score **3** / 3

- IA-MAP 권한 매트릭스 (AGENTS.md:148-150) 와 코드 배치 일치:
  - BE 영역 (`lib/`, `app/api/`) — `harness-state.ts`, `safe-json.ts`, `path-planning.ts`, `state-mapping.ts`, `harness-root.ts`, `agent-roster.ts`, `furniture.ts`, `iso.ts`, `types.ts`, `app/api/snapshot/route.ts`
  - FE 영역 (`app/`, `components/`, `e2e/`) — `app/{layout,page}.tsx`, `components/**`
- 의존성 방향 단방향: components → lib (역방향 X). `lib/path-planning.ts:2` 가 `lib/iso.ts` `lib/furniture.ts` 만 의존 (단일 layer 내부).
- Route Handler `app/api/snapshot/route.ts:3-4` 가 `@/lib/harness-state` + `@/lib/harness-root` 만 의존, components 미참조 ✓.
- `app/page.tsx:1-3` (RSC) 가 `lib/harness-state` (server-side) + `components/Scene` (client wrapper) — 표준 패턴.
- `components/Scene.tsx:4` 의 dynamic import 로 R3F 클라이언트 전용 코드 격리 (`ssr: false`) ✓.
- Cross-package import 없음 (workspace 단일 패키지).

### C2. Readability & Complexity — Score **3** / 3

- 네이밍: `Stage3D`, `Floor3D`, `Minifig3D`, `BrickOfficeCanvas` (제거됨), `planPath`, `zoneAt`, `deriveMinifigState`, `roamPath` (제거됨), `homeDeskFor` — 의도 명확.
- 함수 길이:
  - `Floor3D.tsx:RoomBlock` 89줄 — JSX 7개 mesh group 의 자연스런 spec 길이. 분해 시 인지 부하 증가, 유지.
  - `Minifig3D.tsx:Minifig` useFrame 100여 줄 — state 별 분기 + path queue + animation 통합. 분기 5개에 각 ≤20 줄, 가독성 OK.
- 매직 넘버:
  - `Floor3D.tsx:23-26` 의 `FLOOR_THICKNESS / WALL_HEIGHT / WALL_THICKNESS` = 명명상수화 ✓
  - `Minifig3D.tsx` 의 `0.18, 1.6, 8` 등은 인라인 — animation phase 라 합리적
- 주석: 의도 설명 (Why) 만 작성 — 예 `path-planning.ts:18-21`, `iso.ts:50-58`, `harness-state.ts:131-133`. WHAT 주석 미작성 ✓.
- Dead code: `lib/iso.ts:rectBounds/roomPolygon/seatPositions` 가 더 이상 컴포넌트에서 미사용이지만 테스트가 일부 사용 — 잔존 정당. **단** SVG 시절 흔적 (`worldToScreen`/`ISO_ORIGIN`) 은 R3F 전환 후 무용 → 차후 정리 권고 (블로커 아님).

### C3. Reuse & DRY — Score **3** / 3

- 단일 SoT 패턴 일관:
  - 14 미니피규어 → `lib/agent-roster.ts:AGENT_ROSTER`
  - 7 룸 좌표 → `lib/iso.ts:ROOM_RECTS`
  - 룸 라벨 ko/en → `lib/agent-roster.ts:ROOM_LABELS`
  - 룸 정원 → `lib/furniture.ts:ROOM_CAPACITY`
  - 도어 위치 → `lib/furniture.ts:doorsForRoom`
  - 자유 동선 풀 → `lib/iso.ts:ROAM_POOL`
- 중복 없음: 미니피규어 SVG 도형이 R3F 전환 후 단일 컴포넌트 (`Minifig3D.tsx`). Floor 의 `Wall/Desk/Chair` 가 룸 7개에서 재사용.
- 조기 추상화 X: `Wall` 컴포넌트는 7룸 × 4벽 = 28회 사용으로 가치 입증.

### C4. Type Safety & Error Handling — Score **3** / 3

- `any` 사용: **0건** (`grep -rn "\bany\b" lib app components` empty).
- Discriminated union — `SafeJsonResult<T>` (`safe-json.ts:3-5`) 가 `{ ok: true; value: T } | { ok: false; reason: 'missing' | 'corrupt' }` 으로 호출자 분기 강제.
- Boundary input validation:
  - `safe-json.ts:8-22` — fs ENOENT 와 JSON parse 분리, 절대 throw X
  - `harness-state.ts:174-194` — progress.json missing/corrupt → `errorBanner` fallback (memory.md v5.9.4 학습 적용)
  - `harness-root.ts:8-19` — env override + cwd ascend, 무한 루프 가드 (`parent === current`)
- `null!` 사용 (`Minifig3D.tsx:43-45`) — three.js R3F 가이드라인 (`useRef<Group>(null!)` 가 공식 패턴, mount 후 항상 채워짐).
- API Route (`route.ts:9-15`) 가 항상 200 + JSON 반환, throw 경로 없음 — 명세와 부합 (`api-contract.json:14-16` "절대 5xx 로 떨어지지 않음").

### C5. Test Quality — Score **3** / 3

- **행동 기반**, 구현 결합 X. 예:
  - `safe-json.test.ts` — fs.write tmp dir → 실제 파일 IO 검증 (mock 미사용).
  - `harness-state.test.ts:18-58` — tmp dir 에 progress.json 작성 → readHarnessState → state mapping 검증. 내부 함수 직접 호출 X.
  - `state-mapping.test.ts` — 우선순위 (red-alert > talking > typing > idle) 분기 전수 6 case.
  - `iso.test.ts` — ROOM_RECTS 비겹침 + corridor 비겹침 (사용자 요청 직후 추가) — 시각 사양의 invariant 보호.
- AC 매핑:
  - F-003 → 3 cases (valid/corrupt/missing) ✓
  - F-004 → 3 cases (valid/missing/corrupt) ✓
  - F-005 → E2E 시나리오 + tsc 통합 ✓
  - F-006 → iso.test.ts (룸 비겹침) ✓
  - F-008 → e2e/brick-office.spec.ts (7룸·14피규어 idle / errorBanner) ✓
  - 추가 (사용자 in-flight) → state-mapping.test.ts 6 case ✓
- Mock 남용 X (외부 라이브러리 mock 0건). 유일한 stub 은 tmp dir 파일.
- Coverage 의미: 핵심 분기 (typing/talking/idle/red-alert + path-planning zone, errorBanner fallback) 모두 검증.

### 가중 점수

| 축 | Score | Weight | 가중합 |
|---|---|---|---|
| C1 Layer & Boundary | 3 | 25% | 0.75 |
| C2 Readability | 3 | 15% | 0.45 |
| C3 Reuse | 3 | 20% | 0.60 |
| C4 Type Safety | 3 | 25% | 0.75 |
| C5 Test Quality | 3 | 15% | 0.45 |
| **합계** | | | **3.00 / 3.00** |

PASS 기준 2.80 이상 — 충족.

## Step 3 — Cross-Reference With Contracts

### api-contract.json ↔ 구현 일치성

- `GET /api/snapshot` (api-contract:14-22) ↔ `app/api/snapshot/route.ts` 시그니처 일치 ✓
- HarnessSnapshot schema:`{ version, ts, agents, rooms, goal, archive, meetings, errorBanner }` ↔ `lib/types.ts:HarnessSnapshot` 1:1 ✓
- AgentState schema 와 lib/types.ts 비교: **drift 1건**.
  - `api-contract.json:101-117` AgentState 는 `{ id, name, dept, room, minifigState, lastActivity?, talkingPreview?, alertReason? }`.
  - `lib/types.ts:34-44` 는 추가 필드 `homeRoom: RoomId` 보유.
  - 응답 JSON 에도 homeRoom 필드 노출 — contract 외 추가 필드.
  - **성격**: additive only (제거/타입 변경 X), forward-compatible (구버전 클라이언트 무시 가능).
  - **컨텍스트**: CR-001 (sprint-contract.md:171-220) 에서 사용자 in-flight 요구로 의도적 추가. talking 텔레포트 후에도 원래 룸 추적이 필요해 도입.
  - **권한**: api-contract.json 갱신은 Planner 단독 권한 (AGENTS.md:127). Generator 가 직접 수정 불가.
  - **판정**: 평가자가 retry 시킬 만한 본질적 위반이 아님 — additive·CR-001 명시·Planner 권한이라 Generator 가 자체 fix 불가능.

### feature-list.json ↔ 구현 위치 (IA-MAP)

- F-001 (foundation) → `apps/harness-dashboard/{package.json, next.config.mjs, tsconfig.json, tailwind.config.ts}` ✓
- F-003 (safe-json BE) → `lib/safe-json.ts` ✓
- F-004 (harness-state BE) → `lib/harness-state.ts` ✓
- F-005 (snapshot API BE) → `app/api/snapshot/route.ts` ✓
- F-002 (워드마크 FE) → `components/Wordmark.tsx + Header.tsx + app/layout.tsx` ✓
- F-006 (Floor 3D FE) → `components/three/{Stage3D, Floor3D}.tsx + lib/iso.ts` ✓
- F-007 (Minifig FE) → `components/three/Minifig3D.tsx + lib/agent-roster.ts` ✓
- F-008 (page+E2E FE) → `app/page.tsx + e2e/brick-office.spec.ts + components/Scene.tsx` ✓
- 미정의 새 모듈 (`lib/state-mapping.ts`, `lib/path-planning.ts`, `lib/furniture.ts`) → CR-001 에 명시, Planner 다음 sprint 시 feature-list 갱신 필요.

## Step 4 — Verdict

| 룰 | 적용 | 판정 |
|---|---|---|
| 가중 점수 ≥ 2.80 | 3.00 | OK |
| 축별 Score 0 없음 | min=3 | OK |
| Step 1 toolchain | PASS | OK |
| Contract 불일치 1건 이상 → FAIL | 1건 (homeRoom additive) | **재량 판정** |

Contract 불일치 룰의 의도는 "client/server 가 contract 외 엔드포인트/DTO 로 통신" 같은 본질적 drift 차단. 본 사례는 (a) additive only (b) forward-compat (c) CR-001 에 의도 명시 (d) Planner 권한 영역으로 Generator 셀프 픽스 불가능 (e) 단일 패키지 (서버↔클라이언트 동일 build).

→ Strict 가 아닌 **재량 판정**: **PASS** + Planner 다음 sprint 시 api-contract.json 의 AgentState 에 `homeRoom: RoomId` 추가 강력 권고.

## Cross-Validation Block (Functional / Visual 참조용)

```json
{
  "cross_validation_from_code_quality": {
    "layer_violations": [],
    "type_holes": [],
    "contract_divergence": [
      {
        "field": "AgentState.homeRoom",
        "kind": "additive",
        "implementation": "lib/types.ts:43",
        "contract": "api-contract.json:101-117 (AgentState properties)",
        "owner_for_fix": "planner",
        "severity": "minor",
        "note": "CR-001 에서 의도된 추가. Planner 의 다음 sprint 갱신 항목."
      }
    ],
    "test_evidence": {
      "vitest": "15/15 PASS",
      "playwright": "2/2 PASS",
      "tsc_strict": "clean"
    },
    "risk_areas_to_re_test": [
      "동작 검증은 Functional 단계에서 직접 — 본 평가는 코드 정적 분석만",
      "isometric 시각 톤 / 메타버스 룩 매칭 → Visual 평가에서"
    ]
  }
}
```

## 권고 사항 (블로커 아님 — Planner 다음 sprint 시 처리)

1. `api-contract.json` AgentState 에 `homeRoom: RoomId` 추가.
2. ESLint flat config (`eslint.config.js`) 도입으로 `no-unused-vars` / `no-floating-promises` 자동 검출 추가.
3. `lib/iso.ts` 의 SVG 시절 미사용 함수 (`worldToScreen` 외 일부) 정리 — 테스트 dependency 만 보존하거나 `iso-svg-legacy.ts` 로 분리.
4. Sprint 2 의 F-012/F-013/F-014 가 본 sprint 에서 부분 구현됨 (CR-001) — Planner 가 "이미 충족" 으로 marking 할지 SSE 라이브 변경 후 full re-test 할지 결정.

## Verdict 요약

```
PASS  3.00/3.00  retry_target: -
next_agent: evaluator-functional
```
