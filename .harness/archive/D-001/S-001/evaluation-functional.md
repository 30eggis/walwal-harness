---
docmeta:
  id: evaluation-functional
  title: Evaluation — Functional (Sprint 1 / Phase C-1)
  type: output
  createdAt: 2026-05-07T00:00:00Z
  updatedAt: 2026-05-07T00:00:00Z
  source:
    producer: agent
    skillId: harness-evaluator-functional
  inputs:
    - documentId: feature-list
      uri: ./feature-list.json
      relation: output-from
    - documentId: api-contract
      uri: ./api-contract.json
      relation: output-from
    - documentId: evaluation-code-quality
      uri: ./evaluation-code-quality.md
      relation: output-from
      sections:
        - sourceRange: { startLine: 145, endLine: 175 }   # cross_validation_from_code_quality
          targetRange: { startLine: 25, endLine: 75 }
  tags: [evaluation, functional, sprint-1, phase-c-1, PASS]
---

# Evaluation — Functional (Sprint 1 / Phase C-1)

## Verdict: **PASS** (Weighted 3.00 / 3.00)

## Cross-Validation Input (from Code-Quality)

- contract_divergence: AgentState.homeRoom (additive, Planner 권한 — 본 평가 영향 없음)
- type_holes: 0
- layer_violations: 0
- 동작 검증을 본 평가에서 직접 수행

## AC 검증 결과

| AC | Feature | Method | Result |
|---|---|---|---|
| AC1 | F-005 GET /api/snapshot | curl + 스키마 검증 | **PASS** — HTTP 200, 3108B, 8 필수 필드 모두 존재, agents=14, rooms=7 (ceo/meeting/coo/cto-team/cqo-team/service-ops/archive) |
| AC2 | F-005 errorBanner fallback | progress.json swap + curl | **PASS** — `errorBanner.level=error`, message="progress.json not found — run Dispatcher first.", agents 여전히 14 (no crash) |
| AC3 | F-012(부분) state mapping | progress.json patch + GET | **PASS** — `current_agent=generator-backend, agent_status=running` → typing 1명. `meetings.active=[dispatcher,planner]` → talking 2명, room=meeting (텔레포트). idle 11명. 우선순위 룰 (talking > typing) 부합 |
| AC4 | F-008 E2E 시나리오 | Playwright 2/2 | **PASS** — 시나리오 1 (정상 상태 → 7룸·14피규어 idle, LEGO 부재) 874ms. 시나리오 2 (errorBanner) 93ms. |
| AC5 | F-002·F-006·F-007 DOM | curl + grep | **PASS** — DOM rooms=7, minifigs=14, "Brick Office" 워드마크 노출, "lego" 문자열 부재, 한국어 룸 라벨 (회의실/CEO실) sr-only 인덱스 노출 |
| AC6 | F-001 dev:dashboard 스크립트 | npm run + 포트 3001 | **PASS** — `next dev -p 3001` 즉시 응답. 라이브 미리보기 정책 충족 |

## 회귀 검증 (Regression)

- 이전 Sprint 없음 (Phase C-1 첫 sprint). Regression 항목 N/A.

## 통합 검증

- vitest 15/15 (BE/FE 모두) ✓
- Playwright 2/2 ✓
- tsc --noEmit clean ✓
- 라이브 dev 서버 응답 안정 ✓

## 점수

| 축 | Score | Weight | 가중합 |
|---|---|---|---|
| F1 AC 충족도 | 3 | 40% | 1.20 |
| F2 에러/경계 입력 | 3 | 25% | 0.75 |
| F3 통합 검증 | 3 | 20% | 0.60 |
| F4 회귀 (Phase C-1 N/A) | 3 | 15% | 0.45 |
| **합계** | | | **3.00 / 3.00** |

## Adversarial Notes

- "동작하니 PASS" 자기설득 X — 6개 AC 별 evidence 수집.
- progress.json 손상 시 비정상 종료 가능성을 직접 검증 (swap-and-restore).
- talking 텔레포트가 단순히 minifigState 만 바뀌는 게 아니라 `room` 필드도 "meeting" 으로 바뀌는지 확인 — 통과.
- 라이브 미리보기 dev 서버가 BG 운영 중에도 Playwright webServer.reuseExistingServer=true 로 충돌 없음 — 통과.

## Cross-Validation Block (Visual 참조용)

```json
{
  "cross_validation_from_functional": {
    "ac_pass_count": 6,
    "ac_fail_count": 0,
    "rendered_dom_counts": {
      "rooms": 7,
      "minifigs": 14
    },
    "wordmark": "Brick Office (no LEGO trademark)",
    "korean_labels_present": true,
    "live_state_transitions_verified": [
      "current_agent → typing",
      "meetings.active → talking + room=meeting",
      "progress.json missing → errorBanner fallback"
    ],
    "risk_areas_to_re_test_visually": [
      "isometric voxel/메타버스 톤 매칭 (사용자 G-001 학습)",
      "룸간 도어 갭 가시성 + 복도 회색 바닥",
      "캐릭터 자유 동선 (룸/복도/외부 잔디 waypoint, 벽 통과 금지)",
      "책상/의자/모니터 배치"
    ]
  }
}
```

## Verdict 요약

```
PASS  3.00/3.00  retry_target: -
next_agent: evaluator-visual
```
