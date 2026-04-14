---
docmeta:
  id: design-v4
  title: "Harness v4.0 — Feature-Level Parallel Agent Teams"
  type: output
  createdAt: "2026-04-14T11:00:00Z"
  updatedAt: "2026-04-14T11:00:00Z"
  source:
    producer: agent
    skillId: brainstorming
  inputs: []
  tags: [architecture, v4, parallel, agent-teams, design]
---

# Harness v4.0 — Feature-Level Parallel Agent Teams

## 1. Overview

### Current (v3.x)
```
Planner → Gen(F-001~028 전부) → Eval(전부) → 실패시 Gen 재시도
```

### Target (v4.0)
```
Planner → 3 Teams 병렬, 각 Team이 Feature 단위 Gen→Eval 루프
```

## 2. Architecture Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Execution mode | `claude -p` headless | 자율 실행, 로그만 표시, 비용 효율적 |
| Queue strategy | Dependency-aware (topological sort) | depends_on 그래프 존중, 병렬 가능한 것만 동시 분배 |
| Code isolation | Feature branch + auto-merge | conflict 시 rebase→re-eval→merge |
| Eval strategy | Full eval per feature (opus/ultrathink) | 현재와 동일 수준 품질 보장 |

## 3. Layout

```
┌──────────────────────┬─────────────────────────┐
│  Dashboard            │ Team 1: F-001           │
│  (Feature Queue +     │  Gen→Eval→Pass→F-004    │
│   Team Status +       ├─────────────────────────┤
│   Dependency Graph)   │ Team 2: F-002           │
│                       │  Gen→Eval→FAIL→retry    │
├──────────────────────┤                          │
│  Control              ├─────────────────────────┤
│  harness> assign F-005│ Team 3: F-003           │
│  harness> pause 2     │  Gen→Eval→Pass→F-006    │
└──────────────────────┴─────────────────────────┘
```

## 4. Core Components

### 4.1 Feature Queue System

**File**: `.harness/actions/feature-queue.json`

```json
{
  "version": "4.0",
  "concurrency": 3,
  "queue": {
    "ready": ["F-002", "F-003", "F-004"],
    "blocked": {
      "F-005": ["F-002"],
      "F-008": ["F-003"]
    },
    "in_progress": {
      "F-002": { "team": 1, "phase": "eval", "attempt": 1 },
      "F-003": { "team": 2, "phase": "gen", "attempt": 1 },
      "F-004": { "team": 3, "phase": "gen", "attempt": 1 }
    },
    "passed": ["F-001"],
    "failed": []
  },
  "teams": {
    "1": { "status": "busy", "feature": "F-002", "branch": "feature/F-002", "pid": 12345 },
    "2": { "status": "busy", "feature": "F-003", "branch": "feature/F-003", "pid": 12346 },
    "3": { "status": "busy", "feature": "F-004", "branch": "feature/F-004", "pid": 12347 }
  }
}
```

**Topological Sort**: Planner가 feature-list.json 작성 시 depends_on 기반으로 정렬.
Queue manager가 `passed` 상태 변경 시 `blocked` → `ready` 전이를 수행.

### 4.2 Team Worker

**File**: `scripts/harness-team-worker.sh`

각 Team이 실행하는 루프:

```
while feature = dequeue():
    1. git checkout -b feature/{feature_id}
    2. claude -p "Generate {feature_id}" --model sonnet
    3. Pre-eval gate: tsc + eslint + test
    4. if gate FAIL → retry gen (max 3)
    5. claude -p "Evaluate {feature_id}" --model opus
    6. if eval FAIL → retry gen with eval feedback (max 3)
    7. if 3x FAIL → mark failed, dequeue next
    8. if PASS → git merge to main → update queue → unblock dependents
```

### 4.3 Branch Orchestra

```
main ─────────────────────────────────────────
  ├─ feature/F-001 (T1) ──✓merge──
  ├─ feature/F-002 (T2) ──✓merge──
  └─ feature/F-003 (T3) ──✗conflict
       → auto-rebase → re-eval → merge
```

**Merge protocol**:
1. Team completes Gen+Eval PASS on feature branch
2. Attempt `git merge --no-ff` to main
3. If conflict: `git rebase main` → re-run pre-eval gate → re-eval
4. If rebase+re-eval PASS → merge
5. If rebase+re-eval FAIL → re-gen on rebased branch

### 4.4 State Management

**Per-feature state** (replaces sprint-centric progress.json):

```json
{
  "features": {
    "F-001": {
      "status": "passed",
      "team": 1,
      "gen_attempts": 1,
      "eval_score": 2.95,
      "branch": "feature/F-001",
      "merged_at": "2026-04-14T10:12:00Z",
      "history": [
        { "phase": "gen", "attempt": 1, "result": "ok", "files": 3 },
        { "phase": "eval", "attempt": 1, "score": 2.95, "result": "pass" }
      ]
    },
    "F-002": {
      "status": "in_progress",
      "team": 2,
      "gen_attempts": 2,
      "phase": "gen",
      "history": [
        { "phase": "gen", "attempt": 1, "result": "ok" },
        { "phase": "eval", "attempt": 1, "score": 2.40, "result": "fail", "feedback": "AC-003 미충족" },
        { "phase": "gen", "attempt": 2, "result": "in_progress" }
      ]
    }
  }
}
```

## 5. Generator Skill Changes

### Current
- Reads all features from feature-list.json (batch)
- Generates entire sprint at once

### v4.0
- Receives `FEATURE_ID` environment variable (or via handoff)
- Filters feature-list.json to single feature
- Generates only that feature's code
- Commits to feature branch

**Prompt template for claude -p**:
```
Read .harness/actions/feature-list.json, filter to feature {FEATURE_ID} only.
Read .harness/actions/api-contract.json for relevant endpoints.
Generate the code for this single feature.
Follow CONVENTIONS.md.
Commit when done.
```

## 6. Evaluator Skill Changes

### Current
- Evaluates entire sprint (all features)
- Regression checkpoint against archive
- Cross-validation between eval-func and eval-visual

### v4.0
- Evaluates single feature's AC
- Regression: check previously-passed features still work
- No cross-validation at feature level (deferred to sprint-end)

**Prompt template for claude -p**:
```
Evaluate feature {FEATURE_ID} from feature-list.json.
Run all AC for this feature.
Check that previously passed features ({PASSED_LIST}) still work.
Score using R1-R5 rubric.
Output: PASS/FAIL with score and feedback.
```

## 7. Control Commands

| Command | Action |
|---------|--------|
| `start` | Launch all idle teams |
| `pause <team>` | Pause specific team |
| `resume <team>` | Resume paused team |
| `assign <feature> <team>` | Force-assign feature to team |
| `requeue <feature>` | Move failed feature back to ready |
| `status` | Refresh dashboard |
| `concurrency <N>` | Change parallel team count |
| `log <msg>` | Manual note |

## 8. Cost Analysis

### Serial (v3.x, 8 sprints)
```
Planner:     opus/ultraplan  × 1  = $0.30
Gen-FE:      sonnet          × 8  = $0.24
Eval-Func:   opus/ultrathink × 8  = $2.00
Eval-Visual: opus/ultrathink × 8  = $2.00
                                    ─────
Total:                              $4.54
```

### Parallel (v4.0, 28 features, ~1.5 attempts avg)
```
Planner:     opus/ultraplan  × 1   = $0.30
Gen-FE:      sonnet          × 42  = $1.26  (28 × 1.5 avg attempts)
Eval-Func:   opus/ultrathink × 42  = $10.50
                                      ─────
Total:                                $12.06
```

**Cost increase**: ~2.7× but with per-feature quality guarantee and 3× throughput.

## 9. Implementation Phases

### Phase 1: Feature Queue + Worker (this sprint)
- [ ] `feature-queue.json` schema + topological sort
- [ ] `harness-team-worker.sh` — single feature Gen→Eval loop
- [ ] `harness-queue-manager.sh` — ready/blocked state transitions
- [ ] progress-v4.json schema

### Phase 2: tmux Studio v4
- [ ] Dashboard: Feature Queue + Team status visualization
- [ ] 3 Team panes: worker log streaming
- [ ] Control: start/pause/resume/assign/requeue

### Phase 3: Branch Orchestration
- [ ] Auto feature branch creation
- [ ] Merge + conflict detection
- [ ] Auto-rebase + re-eval on conflict

### Phase 4: Skill Adaptation
- [ ] Generator: FEATURE_ID filter parameter
- [ ] Evaluator: single-feature mode
- [ ] Planner: topological sort enforcement

## 10. Migration Path

v3.x → v4.0 is **not** backward-compatible.

- `config.json` gains `execution_mode: "parallel"` field
- `feature-list.json` keeps same schema (depends_on already exists)
- `progress.json` replaced by `feature-queue.json` + per-feature state
- Skills receive feature filter via environment/handoff
- Studio layout changes from 5-pane to new 5-pane arrangement
