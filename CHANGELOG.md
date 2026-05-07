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
