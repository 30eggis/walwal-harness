---
docmeta:
  id: HARNESS
  title: walwal-harness — NEXUS Company Harness 가이드
  type: output
  createdAt: 2026-05-08T00:00:00Z
  updatedAt: 2026-05-08T00:00:00Z
  source:
    producer: agent
    skillId: harness-release
  inputs:
    - documentId: AGENTS
      uri: ../../AGENTS.md
      relation: output-from
      sections:
        - sourceRange: { startLine: 121, endLine: 126 }
          targetRange: { startLine: 11, endLine: 22 }
        - sourceRange: { startLine: 94, endLine: 120 }
          targetRange: { startLine: 24, endLine: 45 }
        - sourceRange: { startLine: 35, endLine: 81 }
          targetRange: { startLine: 49, endLine: 102 }
        - sourceRange: { startLine: 170, endLine: 195 }
          targetRange: { startLine: 144, endLine: 161 }
        - sourceRange: { startLine: 214, endLine: 237 }
          targetRange: { startLine: 171, endLine: 179 }
        - sourceRange: { startLine: 238, endLine: 243 }
          targetRange: { startLine: 181, endLine: 187 }
  tags: [harness, template, nexus, v6.1.4, doctrine]
---

# walwal-harness — NEXUS Company Harness 가이드

> Anthropic 블로그 "Harness Design for Long-Running Application Development" 기반.
> v6 NEXUS 도큐트린: 하네스를 **하나의 회사**로 본다. Owner(사용자)는 Dispatcher(CEO)와만 대화하고, 회사 내부 부서가 자율적으로 GOAL 을 실행·검증·운영한다.
>
> 이 파일은 **빠른 운영 가이드** 입니다. 프로젝트별 살아있는 컨텍스트는 `AGENTS.md` (CLAUDE.md = AGENTS.md 심볼릭 링크) 를 참조하세요.

## 단일 대화 창구 (Doctrine)

```
Owner (사용자)
  ↕ (단일 대화 창구)
Dispatcher = CEO   ── 부서 식별 · GOAL 협의 · escalation 보고
```

- Owner ↔ Dispatcher만 직접 대화. 다른 부서가 Owner와 직접 대화하는 것은 **금지**.
- 모든 escalation은 Dispatcher 경유.
- GOAL 작성·수정은 CEO 전용 (`.harness/actions/goals.md`, CTO와 협의로 구체화).

## 조직 구조 (v6 NEXUS)

```
Owner
  ↕
Dispatcher (CEO)
  ├─ Conductor          # 자율 실행 엔진 (Gen↔Eval↔Ops 루프, escalation 트리거)
  └─ Meeting-Manager    # 동기화 엔진 (6종 회의 · 적응형 cadence · parallel-tracks fork-join)
        ↓
   Planner (COO + HR)   # Sprint·AC·인선·온보딩
      └─ COO Hypothesis Cell (직영)
         ├─ coo-developer       # 가설 검증 spike·백데이터 실험
         └─ documentationer     # 웹리서치·보고서·가설 판정
        ↓
  ┌─────┴────────┬──────────────┐
  CTO            CQO            Service-Ops
  (Gen 총괄)    (Eval 총괄)     (운용·모니터·인시던트·자율회고)
  ├ Gen-BE       ├ Eval-Functional
  ├ Gen-FE       ├ Eval-Visual
  ├ Designer     ├ Eval-CodeQuality
  └ DevOps       ├ Eval-Architecture
                 └ Eval-Security
```

각 역할의 상세 트리거·산출물·금기는 `.claude/skills/harness-<role>/SKILL.md` 와 `gotchas/<role>.md`, `conventions/<role>.md` 에 명시.

## 디렉토리 구조

### 프로젝트 루트 (개발자가 직접 보는 파일)

```
AGENTS.md           # 프로젝트 컨텍스트 (Planner 가 유지) · v6 IA-MAP·조직도·권한 매트릭스
CLAUDE.md           # → AGENTS.md 심볼릭 링크 (Claude Code 진입점)
CONVENTIONS.md      # 프로젝트 최상위 규칙 (사용자 작성, 에이전트 읽기 전용)
gotchas/<role>.md   # 부서별 부정형 규칙 (G-NNN entry append)
conventions/<role>.md  # 부서별 긍정형 규칙 (C-NNN entry append)
scripts/            # 하네스 스크립트 (init.js 가 동기화)
.claude/skills/harness-<role>/  # Claude Code 가 로드하는 스킬 정의 (init.js 가 동기화)
```

### `.harness/` 런타임 (회사가 작동하면서 만드는 산출물)

```
.harness/
├── HARNESS.md              # 이 파일
├── config.json             # 하네스 설정 (mode_selection, behavior, flow gates)
├── progress.json           # 기계 판독 상태 (세션 오케스트레이션 SoT)
├── progress.log            # 사람 판독 히스토리 (append-only)
├── handoff.json            # 세션 전환 문서 (prompt, model, artifacts, regression)
├── memory.md               # 시스템 entry (예: M-NEXUS-P3) + 사용자 메모
├── doctrine/nexus.md       # NEXUS 도큐트린 본문
├── ref/<role>-<stack>.md   # 스택별 best-practice (FE/BE/Designer/DevOps)
├── prompts/                # 에이전트 프롬프트
├── baselines/              # Eval baseline (의존 그래프, 시각 baseline 등)
├── ops/metrics.jsonl       # 운영 메트릭 (DevOps append / Service-Ops read)
├── actions/                # 활성 스프린트 산출물 (각 부서 쓰기)
│   ├── pipeline.json       # Dispatcher 결정 (FULLSTACK / FE-ONLY / BE-ONLY)
│   ├── plan.md             # Planner — 제품 사양
│   ├── feature-list.json   # Planner — Executable AC
│   ├── api-contract.json   # Planner — API 계약 (BE/FE 공유)
│   ├── sprint-contract.md  # Planner → BE/FE 가 섹션별로 채움
│   ├── evaluation-*.md     # Evaluator-* 별 결과
│   ├── goals.md            # CEO (Dispatcher) 전용
│   ├── meetings/           # Meeting-Manager — 회의록·prep (followup-review 포함)
│   ├── incidents/          # Service-Ops — 사고 타임라인·RCA
│   ├── escalations/        # Conductor — Owner 보고용
│   ├── onboarding/         # Planner(HR) — 부서 온보딩 패키지
│   ├── hypothesis/<id>/    # COO Hypothesis Cell (spike/, brief.md, report.md, verdict.json)
│   ├── hr-roster.md        # Planner(HR) — 활성 부서 명단
│   ├── cto-review-*.md     # CTO 전용
│   ├── cqo-audit-*.md      # CQO 전용
│   └── ops-report-*.md     # Service-Ops 전용
└── archive/                # 완료 스프린트 (불변, Evaluator 가 archive)
    └── D-NNN/S-NNN/        # design-NNN / sprint-NNN
```

## 실행 흐름 (Conductor-driven)

```
Owner: "X 만들어줘" (자유 형식)
   │
   ▼
Dispatcher (CEO)
   ├─ Goal 협의 (모호하면 1회 짧게 명료화)
   └─ pipeline.json 결정 → Conductor 핸드오프
   │
   ▼
Conductor (자율 실행 엔진)
   │
   ▼
Planner ─ ┐
   │      ├─ light  → 기존 PRD 만 보강
   │      └─ full   → plan.md + feature-list + api-contract 확정
   ▼
CTO ── 실행 분할 ── ┐
   ▼              ▼
Gen-BE ⇄ Gen-FE  (병렬 / Team 모드)
   │
   ▼
CQO 적대적 검증 (early-exit chain)
   ├─ Eval-CodeQuality  (정적 · 저비용)
   ├─ Eval-Functional   (동작 · 중비용 · Playwright/curl)
   ├─ Eval-Visual       (렌더 · 고비용 · screenshot)
   ├─ Eval-Architecture (IA-MAP·계층 위반·의존 그래프)
   └─ Eval-Security     (OWASP·SAST·시크릿·CVE)
        │
        ▼
Service-Ops (상시) ── monitor · auto-retro · incident
        │
        ▼
Archive  (sprint advance)
```

앞단 FAIL 시 뒤 단계는 실행하지 않고 즉시 재작업으로 리라우팅.
3회 연속 FAIL · GOAL 위반 · 인시던트 → Conductor 가 Dispatcher 통해 Owner에게 escalation.

## 6종 회의 (Meeting-Manager)

| 회의 | 시점 | 결정자 |
|------|------|--------|
| **standup** | 적응형 cadence (light 30m / normal 1h / heavy 4h) | 부서 발신 |
| **sprint-review** | sprint advance 직전 | CTO |
| **spec-review** | Planner 산출물 변경 | CTO |
| **incident-war-room** | Service-Ops 인시던트 발신 | CEO + CTO |
| **all-hands** | 분기/대형 결정 | CEO |
| **followup-review** | parallel-tracks fork 종료 후 | CTO (goal-* fork 면 CEO) |

### Parallel Tracks (Fork-Join, v6.2)

회의 결정의 `tracks[]` 길이 ≥ 2 면 fork. Conductor 가 트랙 dispatch 와 rendezvous join 을 자동 처리.

- 대표 패턴: `track-1: cto/bugfix` + `track-2: planner/hypothesis-validation` → followup-review 에서 통합 결정.
- followup-review 에서 결정자가 `apply-now / backlog / more-validation` 중 하나로 마무리.
- followup-review 자체에서 또 fork 금지 (무한 fork 방지).
- 한 sprint 내 parallel fork ≥ 3 회면 다음 fork 는 single 강제.

## Solo / Team / Hypothesis 모드

| 모드 | 트리거 | 실행 |
|------|--------|------|
| **Solo** | 기본 | 한 번에 한 에이전트 spawn (1개 슬롯 유지) |
| **Team** | `progress.json.mode = "team"` (Owner 또는 Conductor 결정) | 매 tick `min(ready, 3)` 동시 spawn, parallel evaluator |
| **Hypothesis** | Planner `requested_mode = "hypothesis"` | `documentationer → coo-developer → documentationer → planner` 가설 검증 루프 |

## 품질 게이트

| 게이트 | 시점 | 동작 |
|--------|------|------|
| **Pre-Eval Gate** | Generator → Evaluator 전환 | tsc / eslint / jest&#124;vitest 자동 실행. 실패 시 Generator 리라우팅 |
| **파일 소유권 검증** | 에이전트 전환 시 | git diff 로 권한 밖 파일 수정 감지 |
| **아티팩트 선행조건** | 에이전트 시작 전 | progress.json.artifacts 상태 확인 |
| **Evaluation PASS 기준** | Evaluator 결과 | 2.80 / 3.00 이상. Evidence 없는 score = 0. AC 부분 통과 = FAIL. Regression 1건 = FAIL |
| **Known-Bug Hard Gate** | sprint advance | 알려진 런타임 버그 보유 시 PASS / sprint advance 금지 |

## Conventions / Gotchas (Hierarchical)

- **gotchas/**: 부서별 부정형 규칙. Dispatcher 가 Owner 의 실수 지적을 받아 `### [G-NNN]` 으로 append.
- **conventions/**: 부서별 긍정형 규칙. 같은 메커니즘으로 `### [C-NNN]` append.
- **메모리 오염 방어**: 신규 entry 는 `unverified` 로 시작 → Planner 리뷰 시 `verified` 승격. TTL 만료 항목은 sprint 전환 시 갱신/삭제.
- **검증 불가능 항목 즉시 삭제**.

## 자주 쓰는 명령

| 명령 | 설명 |
|------|------|
| `npx walwal-harness` | 첫 설치 / 안전 init (G-NNN, C-NNN 보존) |
| `npx walwal-harness --force` | 시스템 파일 강제 갱신 (G/C entry 는 여전히 보존) |
| `npx walwal-harness migrate` | 구버전 progress.json / config.json schema 정상화 |
| `npx walwal-harness team` | tmux/iTerm Team 스튜디오 기동 |
| `bash scripts/harness-dashboard-up.sh` | Brick Office 라이브 대시보드 (http://localhost:3001) |
| `bash scripts/harness-session-start.sh` | SessionStart 훅 (자동 호출) |

## 다음 단계

1. `AGENTS.md` 의 `[?]` 태그를 Planner 가 분류하도록 요청.
2. `gotchas/<role>.md`, `conventions/<role>.md` 의 Preserved Rules 섹션 정리.
3. Owner 는 "하네스 엔지니어링 시작" 또는 자유 형식 지시로 Dispatcher 를 깨운다 — 이후는 Conductor 가 이어받는다.
