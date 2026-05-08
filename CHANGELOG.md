---
docmeta:
  id: CHANGELOG
  title: walwal-harness CHANGELOG
  type: output
  createdAt: 2026-05-07T00:00:00Z
  updatedAt: 2026-05-07T00:00:00Z
  source:
    producer: agent
    skillId: harness-release
  inputs:
    - documentId: agency-mapping
      uri: .harness/agency-mapping.md
      relation: output-from
      sections:
        - sourceRange: { startLine: 41, endLine: 53 }
          targetRange: { startLine: 28, endLine: 40 }
    - documentId: doctrine-nexus
      uri: .harness/doctrine/nexus.md
      relation: output-from
      sections:
        - sourceRange: { startLine: 32, endLine: 60 }
          targetRange: { startLine: 41, endLine: 50 }
    - documentId: package
      uri: package.json
      relation: output-from
  tags: [changelog, release-notes, v6.0.0, nexus]
---

# Changelog

## 6.1.0 — document-driven company loop + task-session isolation (2026-05-08)

### Why
v6.0.x 는 회사형 조직 비유와 Cxx 라우팅을 문서로는 설명했지만, 실제 런타임은 여전히 얕았다. 특히 다음 두 결함이 컸다.

- 회의 결과가 `누가 다음 owner 인가` 를 구조적으로 기록하지 않음
- `goal_adherence` 하락 시 원인 분류 없이 Planner로 보내는 경향이 있음

또한 agent 간 자기강화 편향을 줄이기 위한 문서 중심 task session 분리도 충분히 강제되지 않았다.

### Changes
- **document-driven meeting decision**
  - `meeting-manager` 가 `notice.md`, `prep-*.md`, `meeting-<id>.md` skeleton 을 자동 생성
  - 회의 기록에 `decision.owner`, `action_type`, `rationale`, `evidence`, `drift_classification` JSON 블록 추가
  - `conductor-tick` 은 더 이상 `meeting_reason` 문자열만 보지 않고 회의 decision 문서를 우선 읽어 다음 owner 를 결정
- **goal drift classification**
  - `implementation_drift | planning_drift | ops_drift | goal_drift` 분류 추가
  - 분류별 기본 라우팅:
    - `implementation_drift -> cto`
    - `planning_drift -> planner`
    - `ops_drift -> service-ops`
    - `goal_drift -> dispatcher`
- **task-session isolation**
  - `harness-next` 가 다음 agent 마다 `.harness/actions/task-sessions/<agent>/<id>.md` 생성
  - `handoff.json` 에 `task_session_path` 추가
  - `UserPromptSubmit` 가 running agent 와 다른 `/harness-*` 호출을 경고가 아니라 **hard block**
- **direct invocation policy**
  - 모든 harness skill 의 `disable-model-invocation` 을 `false` 로 통일
  - orchestration/control-plane 과 worker/evaluator 모두 직접 호출 가능 상태로 정리
- **archive reset hardening**
  - archive 시 `workflow`, `meetings.decision`, `service_ops.drift_classification`, `task_sessions.current` 초기화

### Validation
- `bash -n` 으로 주요 스크립트 문법 검증
- `jq empty` 로 `config.json`, `progress.json` 검증
- `/private/tmp` 샌드박스에서:
  - `dispatcher -> meeting-manager` 시 회의 문서 자동 생성 확인
  - 회의 decision 편집 후 `dispatcher / planner / cto` 로 문서 기반 재라우팅 확인
  - `goal_adherence` 하락 시 drift classification 반영 확인
  - context isolation hard block 확인
  - `task_session_path` 생성 확인

## 6.0.5 — migrate 가 gotcha entry / bundle version 까지 sync (2026-05-07)

### Why
Owner 보고 — `npm install @walwal-harness/cli@latest && npx walwal-harness migrate` 가 "이미 최신 버전입니다" 로 종료. 그러나 v6.0.4 에서 새로 추가된 `gotchas/conductor.md` 의 [G-005], [G-006], `gotchas/service-ops.md`, `gotchas/generator-frontend.md [G-001]` 가 사용자 프로젝트에 merge 되지 않음. **존재 여부 (3 항목 — progress v4 / config.mode_selection / M-NEXUS-P3) 만 확인하고 콘텐츠는 비교 안 함** → 본질적 버그.

### Changes
- **bin/init.js `detectMigrationNeeded`** — 두 신규 시그널 추가:
  - `gotchaMissingEntries`: `gotchas/*.md` 별로 패키지 → 사용자 [G-NNN] entry 차이 산출 (memory.md 패턴과 동일)
  - `bundleVersionStale`: `.harness/.bundle-version` 스탬프와 패키지 버전 비교
- **bin/init.js `runMigrate`** — gotcha entry append + bundle stamp 갱신 단계 추가. 사용자가 직접 추가한 [G-NNN] entry 는 절대 건드리지 않으며, 패키지의 신규 시스템 entry 만 끝에 추가.
- **bin/init.js `extractGotchaEntryBlock` / `extractEntryBlock`** — JS 정규식 `\Z` 미지원 fix. 마지막 entry 가 추출 누락되던 버그 동시 해결 (v6.0.2 부터 잠재).
- **bin/init.js main flow** — 콘텐츠 드리프트 없이 stamp 만 누락된 경우 init 종료 시 자동 갱신. stamp 만으로 매번 migrate 권유 알림이 뜨는 것 방지.

### Migration
```bash
npm install @walwal-harness/cli@latest
npx walwal-harness migrate     # gotchas/conductor.md G-005/G-006, gotchas/service-ops.md, gotchas/generator-frontend.md G-001 자동 append + stamp 갱신
npx walwal-harness verify
```
사용자 [G-NNN] entry 는 보존되고 시스템 entry 만 끝에 append. 변경 전 `.harness/archive/migration-<ts>/gotchas-<file>` 백업.

## 6.0.4 — Sub-skill 협업 + Service-Ops 상시 + Team 병렬 spawn (2026-05-07)

### Why
moon_web 사용자 보고 — v6.0.3 이후에도 (a) CTO-Frontend 가 흡수된 agency-agents sub-skill (UX/UI/A11y/Perf) 을 호출하지 않고 단독 작업, (b) build/test 중 Service-Ops 자리 비움 → stderr 의 컴파일/테스트 에러 무감시, (c) `mode=team` 인데도 Conductor 가 직렬로 1개씩 spawn 하여 Team 자동 결정 룰 (ready≥3, features≥6, depth≤2) 만족이 무의미해짐. 세 가지는 형식상 v6 였지만 실효는 6.0 이전 수준.

### Changes
- **gotchas/generator-frontend.md [G-001]** — Sprint Workflow Step 2 에 5개 sub-skill 순차 호출 의무 (engineering-{react,flutter}-developer / design/ux-strategy / design/ui-component-spec / engineering-accessibility-reviewer / engineering-performance-engineer). 결과는 sprint-contract.md FE 섹션 `## Sub-skill Findings` 에 인용. 빈 블록 = Evaluator-Code-Quality FAIL.
- **gotchas/service-ops.md [G-001]** (신규) — build/test/deploy spawn 직전 동일 tick 에서 monitor stream-mode 동반 활성. 정규식 `(error|exception|TestFailure|Cannot find|Failed to compile)` 매칭 시 즉시 red-alert.
- **gotchas/conductor.md [G-005]** — Team mode 직렬 회귀 금지. 매 tick 시작 시 ready 목록 계산 → `min(ready, 3)` 동시 spawn + `team_state.team_<n>.assigned_feature/assigned_agent` 갱신 + `meetings.active=["t1-lead","t2-lead","t3-lead"]` standup 시각화.
- **gotchas/conductor.md [G-006]** — Service-Ops monitor 동반 spawn 룰을 Conductor SKILL §5 spawn 결정 트리에 명시.
- **skills/generator-frontend/SKILL.md** — Sprint Workflow §2.1 sub-skill 호출 시퀀스 표 + visibility partial update 패턴.
- **skills/conductor/SKILL.md** — §5 spawn 결정 트리에 두 라인 추가 + §5.1 Team mode 병렬 알고리즘 + §5.2 Service-Ops 동반 spawn 의사코드.

### Migration
기존 사용자:
```bash
npm install @walwal-harness/cli@latest
npx walwal-harness migrate     # gotchas/service-ops.md 자동 추가
npx walwal-harness verify
```
sub-skill 호출은 generator-frontend SKILL.md 가 갱신되면 다음 sprint 부터 자동 적용. 진행 중 sprint 의 FE 섹션은 Eval-Code-Quality 가 빈 `## Sub-skill Findings` 를 잡아내며 retry 유도.

## 6.0.3 — Visibility + Spawn 검증 + 사용자 슬래시 노출 제거 (2026-05-07)

Owner 의 두 지적을 동시 해결:
1. "Dispatcher 와 대화 중인데 CEO 가 자리에 없다 / 회의실에 모이지도 않는다" — visibility 의무 부재
2. "회사인데 왜 자꾸 나에게 명령을 요구하는가" — 사용자 facing 슬래시 잔재

### Added
- `gotchas/dispatcher.md` [G-005] [G-006] — 사용자 슬래시 명령 요구 금지 + Owner 대화 중 dashboard 가시화 의무
- `gotchas/conductor.md` (신규) — [G-001] inline fallback 금지 (M-001 의 Conductor 적용) / [G-002] spawn 핸드오프 시 회의실 활용 / [G-003] Visibility Checklist 4 시점 / [G-004] Owner 진행 동의 묻지 말 것
- `skills/conductor/SKILL.md` §0.5 "Visibility Checklist (Inviolable)" 신설 — 매 tick 의 4 시점 progress.json partial update 의무 + spawn 사전 검증 (SKILL 존재 검사 → 없으면 escalate, inline fallback 금지)
- 신규 명령 `walwal-harness verify` — 17 SKILL invariants + progress schema + config mode_selection + memory 시스템 entry + deprecated commands 검사. 한 줄로 통합 점검.
- `apps/harness-dashboard` 의 `ActivityIndicator` 컴포넌트 — `last_activity` age 표시. 30 초 이상 정적 → "stale — 회사가 멈춰 보입니다" 빨간 표시.

### Changed
- `commands/harness-next.md` **삭제** — 사용자 슬래시 노출 제거. v6 자율 회사에서 Owner 가 입력할 일 없음. `scripts/harness-next.sh` 는 회사 내부 도구로 유지 (Conductor 자율 호출).
- 9 개 SKILL 본문의 "/harness-next 자동 진행" 안내 → "자동 핸드오프 (Conductor 자율 시동)" 로 일괄 치환.
- `bin/init.js` install 의 commands cleanup 로직이 자동으로 deprecated `harness-next.md` 를 사용자 환경에서 제거 (기존 동작이 모든 `harness-*` 를 갱신하므로).

### Removed
- `commands/harness-next.md` — 사용자 facing 슬래시 (자율 위반)

### Migration (one-liner)
```bash
npm install @walwal-harness/cli@latest
npx walwal-harness migrate    # 이전 버전 사용자
npx walwal-harness verify     # 설치 무결성 점검
```

`verify` 가 점검하는 것:
- 17 개 SKILL 의 frontmatter (name, description) + 파일 존재
- progress.json schema (version ≥ 4, mode_decision, dispatch)
- config.json mode_selection 존재
- memory.md 시스템 entry (M-NEXUS-P3)
- deprecated 사용자 슬래시 (`.claude/commands/harness-next.md`) 잔존 여부

## 6.0.2 — `migrate` 가 memory 시스템 entry 까지 자동 처리 (2026-05-07)

v6.0.1 patch 적용을 위해 사용자가 memory.md 의 [M-NEXUS-P3] 를 수동 추가해야 했던 불편을 제거. `npx walwal-harness migrate` 한 줄로 모두 처리됩니다.

### Changed
- `bin/init.js` 의 `detectMigrationNeeded()` 가 memory.md 의 시스템 entry (M-NEXUS-*, M-SYS-*) 누락도 감지.
- `runMigrate()` 가 누락된 시스템 entry 를 template 에서 발췌해 사용자 memory.md 끝에 append. **사용자 [M-NNN] entry 는 무손상**.
- postinstall 안내 banner 가 누락된 memory entry 목록도 함께 표시.

### Migration (one-liner)
```bash
npm install @walwal-harness/cli@latest
npx walwal-harness migrate          # progress + config + memory 한 번에
```

`migrate` 가 처리하는 것:
- progress.json v3 → v4 (mode → "auto" + mode_decision)
- config.json mode_selection 자동 주입
- **(신규)** memory.md 시스템 entry append (M-NEXUS-P3 등)
- 변경 전 .harness/archive/migration-<ts>/ 에 progress / config / memory 자동 백업.

## 6.0.1 — Owner ↔ CEO 정체성 + 자율 실행 룰 강화 (2026-05-07)

v6.0.0 publish 직후 Owner 의 명시적 교정으로 발견된 두 가지 inviolable 룰 위반 패턴을 패키지에 정식 등재한 patch.

### 발견된 위반 패턴
- Dispatcher 응답이 사용자를 "CEO 직접 리뷰…" 로 호명 — 정체성 혼선
- "/harness-next 자동 진행하시겠습니까?" 식의 사용자 펌프 — NEXUS P3 자율 실행 위반

### Added
- `gotchas/dispatcher.md` — 신규 4개 entry ([G-001]~[G-004]) 정식 등재. install 시 사용자 `.harness/gotchas/dispatcher.md` 로 자동 복사.
  - [G-001] 사용자를 CEO 로 다루지 말 것 (Owner ↔ CEO 정체성)
  - [G-002] 사용자에게 진행 여부 묻지 말 것 (NEXUS P3 자율 실행)
  - [G-003] GOAL 모호성 명료화는 짧게 한 번만
  - [G-004] Owner ↔ Conductor/Planner/Generator/Evaluator 직접 라우팅 금지
- `assets/templates/memory.md` — 신규 [M-NEXUS-P3] 항목. 모든 신규 install 의 시작 memory 에 포함.

### Changed
- `skills/dispatcher/SKILL.md` 상단에 두 inviolable 섹션 신설:
  - "정체성 — Owner ↔ CEO (NEXUS, Inviolable)"
  - "자율 실행 원칙 (NEXUS P3, Inviolable)"
- `skills/conductor/SKILL.md` §0 "자율 시동 트리거" 신설 — Dispatcher GOAL 확정 / Planner feature-list 확정 / Eval PASS / Eval FAIL 4 시점에 자동 시동 명시.

### Why a patch (not a feature)
이 룰들은 v6.0.0 의 NEXUS 도큐트린에 이미 존재했지만 SKILL 본문에서 충분히 강제되지 않아 대화에서 위반이 발생. 룰 자체는 변경 없음, **명시화/강제력 강화** 만.

### Migration
이전 사용자 (v6.0.0 install 자) 가 patch 적용:
```bash
npm install @walwal-harness/cli@latest    # 6.0.1 설치
# .claude/skills/ 와 .harness/gotchas/dispatcher.md 가 자동 갱신됨.
# .harness/memory.md 는 [G-NNN] entry 가 있으면 보존되므로
# [M-NEXUS-P3] 항목을 수동으로 메모에 추가하거나
# memory.md 백업 후 walwal-harness --force 로 template 재적용.
```

## 6.0.0 — NEXUS-Adapted Company Metaphor (2026-05-07)

회사 메타포로의 전면 전환. 기존 단일 dispatcher/planner/generator/evaluator 라인업을 NEXUS 도큐트린에 따라 7부서 + 14 에이전트 조직도로 재해석했습니다.

### Added
- **CEO (Dispatcher 격상)** — Owner ↔ 회사 단일 대화 창구. GOAL 협의·escalation 보고.
- **Conductor** — 자율 실행 엔진. Gen↔Eval 무인 루프.
- **Meeting-Manager** — 동기화 엔진. 5종 회의(standup/planning/review/all-hands/phase-gate) 적응형 cadence.
- **COO (Planner)** — Sprint·AC·HR·온보딩 통합.
- **CTO (Generator 총괄)** — Gen-BE/Gen-FE/Designer/DevOps 4팀 통솔.
- **CQO (Evaluator 총괄)** — Eval-Functional/Visual/CodeQuality + 신규 Architecture/Security.
- **Service-Ops** — 운용·모니터·인시던트·자율회고.
- 신규 14개 SKILL.md (`skills/{conductor,meeting-manager,cto,cqo,service-ops,evaluator-architecture,evaluator-security,generator-designer,generator-devops,...}/SKILL.md`).
- `.harness/doctrine/nexus.md` — Foundational Principles (P1~P5) + 7 Phase Lifecycle.
- `.harness/agency-mapping.md` — agency-agents → walwal-harness 매핑 (Phase A 결과).
- `.harness/memory.md` 기반 공유 학습 시스템 (gotcha 와 분리).
- Brainstormer 스킬 (obra/superpowers 파생, MIT, Visual Companion 포함).
- 적응형 ref-docs (`.harness/ref/<role>-<stack>.md`) — 단일 에이전트가 스택별 best-practice 동적 로드.

### Changed
- `agents` 섹션의 Flutter 변형 (`generator-frontend-flutter` / `evaluator-functional-flutter`) 제거. 단일 에이전트가 `.harness/ref/<role>-<stack>.md` 동적 로드.
- AGENTS.md IA-MAP — 부서 권한 매트릭스 25항 (이전 12항).
- progress.json 스키마 v3 — `org/goals/conductor/meetings/cto/cqo/service_ops` 슬롯 추가.
- Evaluator chain 명시화: `evaluator-code-quality → evaluator-functional → evaluator-visual` (FULLSTACK/FE-ONLY) / `code-quality → functional` (BE-ONLY).

### Removed
- Flutter "유령 스킬" 참조 ([M-001] resolved). config.json + dispatcher SKILL.md 의 fe_stack_substitution 폐기.
- 기존 PRE-NEXUS dispatcher 단일 라인업.
- **Dispatcher 의 Solo/Team 모드 질문**. 사용자 "harness-solo / harness-team 입력하세요" 안내 패턴 제거.

### Mode Decision — User → Conductor 이양 (Breaking)
- `progress.json.mode` 디폴트 `"solo"` → `"auto"`. version 3 → 4.
- 신규 필드 `progress.json.mode_decision = { owner, decided_at, rationale, user_override }`.
- `config.json.mode_selection` 신규 — `force_team_when`(ready≥3 + features≥6 + depth≤2) / `force_solo_when` / tie-breaker=solo.
- Conductor SKILL §7.5: Planner 의 feature-list 확정 직후 자동 결정. 결정은 progress.json + progress.log 에 rationale 명시.
- `/harness-solo`, `/harness-team` 은 사용자 override 명령으로 의미 변경. `mode_decision.user_override` 에 기록되어 현재 sprint 종료까지 유지. "auto 로 돌려" 발화로 자동결정 복귀.
- Dispatcher SKILL §"Mode 결정 위임" — 모드 질문/추천 출력 모두 폐기. 사용자 발화에서 명시적 모드 신호 감지 시만 user_override 로 기록.

### Migration (5.9.x → 6.0.0)

기존 walwal-harness 사용 프로젝트는 `npm install @walwal-harness/cli@latest` 후 다음 한 줄로 자동 마이그레이션 가능:

```bash
npx walwal-harness migrate --dry-run    # 변경 미리보기
npx walwal-harness migrate              # 실제 적용
```

**자동 처리되는 것**:
- `progress.json` v3 → v4 — 기존 `mode` 값 (`"solo"` 또는 `"team"`) 을 `mode_decision.user_override` 로 **그대로 보존**. 새 mode 는 `"auto"` 로 셋되지만 user_override 로 직전 sprint 의 사용자 의도 유지.
- `config.json` 의 `mode_selection` 누락 시 자동 주입 (rules: ready≥3 + features≥6 + depth≤2 → team / 그 외 → solo). 사용자 customization (`behavior`, `flow.pre_eval_gate.*`) 은 **모두 보존**.
- 변경 전 자동 백업: `.harness/archive/migration-<timestamp>/` (progress.json + config.json 원본).

**수동 처리 권장**:
1. AGENTS.md 의 IA-MAP 권한 매트릭스 신규 25항 검토.
2. 기존 sprint 진행 중이라면 `.harness/archive/` 로 수동 이관 후 새 dispatch 시작.
3. `.claude/skills/` 의 신규 14개 부서 SKILL.md 가 정상 설치되었는지 확인 (`ls .claude/skills/` 에 conductor / cto / cqo / meeting-manager / service-ops / evaluator-architecture / evaluator-security 포함).
4. Flutter 프로젝트 사용자: `pubspec.yaml` 자동 감지 + `.harness/ref/generator-frontend-flutter.md` (있을 시) 로 동작. 누락 시 Planner 가 ref 생성 권고.

**Postinstall 안내**: `npm install` 후 v3 detect 시 안내 banner 가 출력될 수 있으나 npm v9+ 의 quiet mode 에서는 누락될 수 있습니다. 의심 시 `npx walwal-harness migrate --dry-run` 으로 직접 확인하세요.

### Reference
Phase C "Brick Office 대시보드 MVP" 가 본 v6 organization 기반 첫 풀사이클 검증 (3 sprints, 25 features, 모든 평가 PASS).

## 5.9.6 — Queue Integrity & Lead Guard (이전)
- queue enqueue/integrity 명령 추가, dashboard orphan 경고, Lead 가드.

## 5.9.5 — Solo/Team Mode Drift Fix
- progress.json mode drift 시 dashboard/tmux 가 SOLO 로 잘못 표시되던 버그 수정.

## 5.9.4 — Graceful Crash Recovery
- progress.json 손상 시 dashboard crash → 안내 메시지로 graceful 처리.

## 5.9.3 — Compressed Output Fix
- 분할 패널에서 Conventions/Memory 가 3 줄만 보이던 압축 출력 수정.
