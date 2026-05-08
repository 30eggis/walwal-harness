---
docmeta:
  id: AGENTS
  title: Project Context for AI Agents (walwal-harness)
  type: input
  createdAt: 2026-04-09T00:00:00Z
  updatedAt: 2026-05-07T00:00:00Z
  source:
    producer: user
  tags: [project-context, ia-map, permissions, harness]
---

# AGENTS.md — Project Context for AI Agents

> 이 파일은 모든 AI 에이전트(Claude, Cursor, Copilot, Windsurf 등)의 공통 진입점입니다.
> CLAUDE.md는 이 파일의 심볼릭 링크입니다.

## Project

- **Name**: (Planner가 설정)
- **Description**: (Planner가 설정)
- **Phase**: C — Brick Office 대시보드 MVP (FULLSTACK, sprint 1/3)
- **Harness**: `.harness/HARNESS.md` 참조

## Tech Stack

> v5.2 이후 이 섹션의 값은 **scan-project.sh 가 감지한 결과**로 `init-agents-md.sh` 가 동적으로 채운다. 하드코딩된 스택 선언은 제거되었다.

- Backend: (scan-project.sh 가 감지 · `.harness/actions/scan-result.json.tech_stack.backend`)
- Frontend: (scan-project.sh 가 감지 · `.harness/actions/scan-result.json.tech_stack.frontend`)
- Database: (scan-project.sh 가 감지)
- Adaptive Ref-Docs: `.harness/ref/<role>-<stack>.md` (감지된 스택별 best practice 및 validation 프로토콜)
- Gotchas: `.harness/gotchas/<agent>.md` (공통) + `<agent>-<stack>.md` (스택별)

## IA-MAP (Information Architecture)

> 1차원 폴더 맵. 각 경로의 책임과 소유 에이전트를 명시합니다.
> Planner만 이 맵을 수정할 수 있습니다.

```
/
├── apps/
│   ├── gateway/                # [BE] API Gateway — 라우팅·인증·CORS         → Generator-Backend
│   ├── service-*/              # [BE] Microservice — 도메인 로직              → Generator-Backend
│   ├── web/                    # [FE] Frontend — UI·상태·API                 → Generator-Frontend
│   │   └── design/             # [DESIGN] 디자인 토큰·컴포넌트 spec·flows    → Generator-Designer
│   └── harness-dashboard/      # [FE+BE] Brick Office 대시보드 (Phase C)
│       ├── app/                #   [FE] Next.js App Router · 페이지·UI       → Generator-Frontend
│       ├── components/         #   [FE] BrickOfficeCanvas/Room/Minifig/Drawer → Generator-Frontend
│       ├── hooks/              #   [FE] useHarnessStream (EventSource)       → Generator-Frontend
│       ├── lib/                #   [BE] harness-state·safe-json·state-mapping → Generator-Backend
│       ├── app/api/            #   [BE] /api/snapshot · /api/stream (SSE)    → Generator-Backend
│       └── e2e/                #   [FE] Playwright 시나리오                  → Generator-Frontend
├── libs/
│   ├── shared-dto/             # [BE] 공유 DTO — api-contract.json 파생      → Generator-Backend
│   ├── database/               # [BE] DB 모듈                                → Generator-Backend
│   └── common/                 # [BE] 공통 유틸                              → Generator-Backend
├── infra/                      # [INFRA] CI/CD·IaC·시크릿·릴리스             → Generator-DevOps
├── .harness/
│   ├── doctrine/               # [HARNESS] 운영 도큐트린 (NEXUS)             → Planner (Owner 승인)
│   ├── ref/                    # [HARNESS] 스택별 best-practice 참조본       → Planner
│   ├── prompts/                # [HARNESS] 에이전트 프롬프트                 → Planner
│   ├── actions/                # [HARNESS] 활성 스프린트 문서                → 각 에이전트
│   │   ├── meetings/           # [HARNESS] 회의록·prep (followup-review 포함) → Meeting-Manager
│   │   ├── incidents/          # [HARNESS] 사고 타임라인·RCA                 → Service-Ops
│   │   ├── escalations/        # [HARNESS] Owner 보고용                      → Conductor
│   │   ├── onboarding/         # [HARNESS] 부서 온보딩 패키지                → Planner(HR)
│   │   └── hypothesis/         # [HARNESS] COO Hypothesis Cell 산출물 (spike/report/verdict) → Planner(발급)·coo-developer·documentationer
│   ├── ops/                    # [HARNESS] 운영 메트릭 적재                  → Generator-DevOps(append) / Service-Ops(read)
│   ├── baselines/              # [HARNESS] Eval baseline (의존 그래프 등)    → Evaluator-*
│   └── archive/                # [HARNESS] 완료 스프린트 (불변)              → Evaluator
├── gotchas/                    # [HARNESS] 부서별 가드                       → Planner
├── skills/                     # [HARNESS] 부서 스킬 정의                    → Planner(HR)
├── AGENTS.md                   # [META] 프로젝트 컨텍스트                    → Planner
├── CLAUDE.md                   # [META] → AGENTS.md 심볼릭 링크
├── init.sh                     # [HARNESS] 환경 초기화 + 통합 러너
├── nest-cli.json               # [BE] NestJS 모노레포 설정                   → Generator-Backend
├── package.json                # [ROOT] 워크스페이스                         → Generator-Backend
└── docker-compose.yml          # [INFRA] 개발용 오케스트레이션               → Generator-DevOps
```

### IA-MAP 범례

| 태그 | 의미 | 소유 에이전트 |
|------|------|--------------|
| `[BE]` | Backend 영역 | Generator-Backend |
| `[FE]` | Frontend 영역 | Generator-Frontend |
| `[DESIGN]` | 디자인 토큰·컴포넌트 | Generator-Designer |
| `[INFRA]` | 인프라·CI/CD·시크릿 | Generator-DevOps |
| `[HARNESS]` | 하네스 시스템 | Planner / Evaluator / 부서별 (권한 매트릭스 참조) |
| `[META]` | 프로젝트 메타 문서 | Planner |
| `[ROOT]` | 루트 설정 | Generator-Backend (초기), Planner (구조 변경) |

## Organization (v6 — NEXUS-Adapted)

> 하네스는 하나의 회사. 사용자(Owner)는 Dispatcher(CEO)와만 대화한다.
> 상세 도큐트린: `.harness/doctrine/nexus.md`

```
Owner (사용자)
  ↕ (단일 대화 창구)
Dispatcher = CEO  ── 부서 식별 · GOAL 협의 · escalation 보고
  ├─ Conductor          (자율 실행 엔진: Gen↔Eval↔Ops 루프)
  └─ Meeting-Manager    (동기화 엔진: 6종 회의 · 적응형 cadence · parallel-tracks fork-join)
        ↓
   Planner = COO + HR   (Sprint·AC·인선·온보딩)
      └─ COO Hypothesis Cell (직영)
         ├─ Developer 1       (가설 검증용 spike·백데이터 실험)
         └─ Documentationer 1 (웹리서치·보고서·가설 판정)
        ↓
  ┌─────┴────────┬──────────────┐
  CTO            CQO            Service-Ops
  (Gen 총괄)    (Eval 총괄)     (운용·모니터·인시던트·자율회고)
  ├ Gen-BE      ├ Eval-Functional
  ├ Gen-FE      ├ Eval-Visual
  ├ Designer    ├ Eval-CodeQuality
  └ DevOps      ├ Eval-Architecture
                └ Eval-Security
```

### 단일 대화 창구 룰

- **Owner ↔ Dispatcher만** 직접 대화. 다른 부서는 Owner와 직접 대화 X.
- 모든 escalation은 Dispatcher 경유.
- GOAL 작성은 CEO 전용 (CTO와 협의로 구체화).

## Rules (모든 에이전트 공통)

### 읽기/쓰기 권한

| 파일 | 읽기 | 쓰기 |
|------|------|------|
| CONVENTIONS.md | 전체 | 사용자만 (에이전트 수정 금지) |
| AGENTS.md | 전체 | Planner만 |
| .harness/actions/api-contract.json | 전체 | Planner만 |
| .harness/actions/feature-list.json | 전체 | passes 필드: Generator, 나머지: Planner만 |
| .harness/actions/sprint-contract.md | 전체 | Generator-BE(BE섹션), Generator-FE(FE섹션) |
| .harness/actions/evaluation-*.md | 전체 | 해당 Evaluator만 |
| .harness/progress.json | 전체 | 전체 (Session Boundary Protocol에 따라 업데이트) |
| apps/gateway/, apps/service-*/ | 전체 | Generator-Backend만 |
| apps/web/ | 전체 | Generator-Frontend만 |
| libs/ | 전체 | Generator-Backend만 |
| .harness/archive/ | 전체 | 쓰기 금지 (불변) |
| .harness/doctrine/ | 전체 | Planner만 (Owner 승인 시) |
| .harness/ref/ | 전체 | Planner만 |
| .harness/actions/goals.md | 전체 | **CEO(Dispatcher)만** |
| .harness/actions/meetings/ | 전체 | Meeting-Manager만 |
| .harness/actions/incidents/ | 전체 | Service-Ops만 |
| .harness/actions/escalations/ | 전체 | Conductor만 |
| .harness/actions/onboarding/ | 전체 | Planner(HR)만 |
| .harness/actions/cto-review-*.md | 전체 | CTO만 |
| .harness/actions/cqo-audit-*.md | 전체 | CQO만 |
| .harness/actions/ops-report-*.md | 전체 | Service-Ops만 |
| .harness/actions/hr-roster.md | 전체 | Planner(HR)만 |
| .harness/actions/org-chart-*.json | 전체 | Dispatcher(CEO)만 |
| .harness/ops/metrics.jsonl | 전체 | Generator-DevOps(append) / Service-Ops(read) |
| .harness/baselines/ | 전체 | Evaluator-* (자기 baseline만) |
| .harness/actions/hypothesis/ | 전체 | Planner(발급) / coo-developer(spike·observations·repro) / documentationer(brief·report·verdict·evidence) |
| .harness/actions/hypothesis/&lt;id&gt;/spike/ | 전체 | coo-developer만 (실험 코드, 운영 SoT 아님) |
| .harness/actions/hypothesis/&lt;id&gt;/{brief,report,verdict}.* | 전체 | documentationer만 |
| .harness/actions/meetings/&lt;id&gt;/followup-*.md | 전체 | Meeting-Manager만 (followup-review prep·결정) |
| apps/web/design/ | 전체 | Generator-Designer만 |
| apps/harness-dashboard/app/, components/, hooks/, e2e/, public/ | 전체 | Generator-Frontend |
| apps/harness-dashboard/lib/, app/api/ | 전체 | Generator-Backend |
| apps/harness-dashboard/{package.json, next.config.mjs, tsconfig.json, tailwind.config.ts} | 전체 | Generator-Backend (초기 scaffold) |
| infra/ | 전체 | Generator-DevOps만 |
| skills/ | 전체 | Planner(HR)만 |
| gotchas/ | 전체 | Planner만 (verified 승격) / 각 부서 (자기 unverified 추가 가능) |

### COO Hypothesis Cell 운영 규칙

- **목적**: CTO/CQO 정규 라인 투입 전에 가설을 빠르게 검증하는 실험 셀
- **구성**: `coo-developer` 1명 + `documentationer` 1명
- **직속**: Planner(COO)가 직접 운영, Dispatcher/Service-Ops 입력을 받아 기동
- **산출물 경로**: `.harness/actions/hypothesis/<id>/{spike/, brief.md, report.md, verdict.json, evidence/}` (`<id>` = `H-YYYYMMDDTHHMMSSZ`, Planner 발급)
- **허용 범위**:
  - 웹 리서치 기반 가설 수립/보강
  - 백데이터 활용 분석·실험용 코드 작성
  - 아키텍처/코드퀄리티/테스트 엄수 없이도 빠른 spike 허용
  - 보고서 작성 및 가설 유효/무효 판정
- **제한**:
  - 실험 산출물은 운영 코드의 SoT가 아님
  - 정규 배포/운영 경로 투입 전에는 Planner가 결과를 Sprint/GOAL artifact로 재정식화해야 함
  - 정규 팀(CTO/CQO) 평가 없이 "완료" 또는 "운영 가능" 판정 금지

### Parallel Tracks (v6.2 — Fork-Join)

회의 결정이 둘 이상의 부서로 분기되어야 할 때 Meeting-Manager 가 `tracks[]` 길이 ≥ 2 인 결정 JSON 을 작성한다 (skills/meeting-manager/SKILL.md §7.05 참조). 별도 mode 플래그는 없음 — tracks 가 단일 진실.

- 대표 패턴: `track-1: cto/bugfix` + `track-2: planner/hypothesis-validation` → 다음 followup-review 에서 통합 결정.
- Conductor 가 트랙 dispatch 와 rendezvous join 을 자동 처리 (`progress.json.conductor.tracks[]`).
- followup-review 에서 결정자(기본 CTO, fork 가 goal-* 였으면 CEO) 가 `apply-now / backlog / more-validation` 중 하나를 단일 결정으로 마무리.
- followup-review 자체에서 또 fork 금지 (무한 fork 방지).
- 한 sprint 내 parallel fork ≥ 3회면 다음 fork 는 single 강제.

### 변경 요청 프로토콜

Generator/Evaluator가 AGENTS.md 또는 api-contract.json 변경이 필요하다고 판단할 때:

1. `.harness/actions/sprint-contract.md` 또는 evaluation에 `## Change Request` 섹션 추가
2. 변경 사유, 영향 범위, 제안 내용 기술
3. Planner가 다음 스프린트 전환 시 반영 여부 결정

### 금지 사항 (전체)

- AGENTS.md를 Planner 외 에이전트가 수정
- api-contract.json에 없는 엔드포인트 구현/호출
- 서비스 간 직접 DB 접근 (반드시 메시지 패턴)
- 테스트 삭제/약화
- archive/ 내 파일 수정
- 프로젝트를 조기 "완료" 선언
- 아티팩트 상태가 `draft` 미만인 선행 아티팩트에 의존하여 작업 시작

### 품질 게이트 (v3.1 신설)

| 게이트 | 시점 | 내용 |
|--------|------|------|
| **Pre-Eval Gate** | Generator → Evaluator 전환 | tsc, eslint, jest/vitest 자동 실행. 실패 시 Generator 리라우팅 |
| **파일 소유권 검증** | 에이전트 전환 시 | git diff로 권한 밖 파일 수정 감지 |
| **아티팩트 선행조건** | 에이전트 시작 전 | progress.json.artifacts 상태 확인 |
| **에스컬레이션** | 3회 연속 실패 | Planner에게 scope 축소/접근 변경 요청 |

### Evaluation System (v3.2)

| 설정 | 값 |
|------|------|
| PASS 기준 | **2.80 / 3.00 이상** |
| FAIL 기준 | 2.79 이하 (예외 없음) |
| Evidence 없는 Score | 0점 강제 |
| AC 부분 통과 | FAIL (100% 필수) |
| Regression 실패 1건+ | FAIL (신규 점수 무관) |

- Planner는 feature-list.json에 **Executable AC** (type: api/visual/e2e + verify 조건) 필수 작성
- Evaluator는 Adversarial Rules에 따라 적대적으로 검증 (rubber-stamping 금지)
- 이전 Sprint PASS 기능은 Regression Checkpoint로 재검증
- Eval-Functional ↔ Eval-Visual 간 Cross-Validation으로 불일치 감지

### 메모리 오염 방어

- gotcha/memory 항목은 `unverified` 상태로 시작, Planner 리뷰 후 `verified` 승격
- TTL 만료 항목은 Planner 스프린트 전환 시 리뷰 (갱신 또는 삭제)
- 코드/git으로 검증 불가한 항목은 즉시 삭제

## Harness Quick Reference

| 명령 | 설명 |
|------|------|
| `npm run dev` | 통합 러너 (Gateway + 전체 서비스 + Frontend) |
| `bash init.sh` | 환경 확인 + 서비스 기동 |
| `.harness/progress.json` | 현재 진행 상태 (기계 판독) |
| `.harness/actions/` | 활성 스프린트 문서 |
| `.harness/HARNESS.md` | 하네스 상세 가이드 |
