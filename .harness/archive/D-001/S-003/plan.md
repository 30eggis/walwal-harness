---
docmeta:
  id: plan
  title: Plan — Brick Office (Phase C-3 Polish)
  type: output
  createdAt: 2026-05-07T00:00:00Z
  updatedAt: 2026-05-07T00:00:00Z
  source:
    producer: agent
    skillId: harness-planner
  inputs:
    - documentId: feature-list
      uri: ./feature-list.json
      relation: output-from
    - documentId: predecessor-sprint-2
      uri: ../archive/D-001/S-001/feature-list.json
      relation: output-from
      sections:
        - sourceRange: { startLine: 1, endLine: 100 }
          targetRange: { startLine: 15, endLine: 50 }
  tags: [plan, phase-c-3, polish, brick-office]
---

# Plan — Brick Office (Phase C-3 Polish)

## Predecessor

Phase C-1 (Sprint 1) + Phase C-2 (Sprint 2) 모두 평가 chain PASS 후 archive. 본 sprint 가 Phase C 의 마지막. F-020 회의실 텔레포트는 CR-001 에서 선구현되어 Sprint 2 에서 PASS 검증 — marked_complete.

## Sprint 3 active features (6)

- F-019 GOAL 카드 (CEO실 벽)
- F-021 아카이브 룸 + sprint 카운트
- F-022 아카이브 드로어 (depends F-021 + Sprint 2 의 F-015)
- F-023 i18n util (ko/en 폴백)
- F-024 Playwright E2E 6 시나리오 (depends F-019, F-021)
- F-025 성능 가드 (SSE latency)

## CR-002 처리

Sprint 2 Eval-CodeQuality 의 권고 — `GET /api/log` 를 api-contract.json 에 정식 등재. 본 sprint 시작 시 api-contract.json 갱신.

## F-025 목표 완화 권고

Sprint 2 측정: SSE latency 329ms. 시스템 floor (chokidar awaitWriteFinish 100 + 디바운스 50 = 150ms) 고려 시 <200ms 목표는 floor 임박. 운영상 <500ms 로 완화 권고. 본 sprint 에서는 측정 + 보고만 수행, 강제 미달 FAIL 아님.

## Live Preview Policy

계속 적용. F-019 완료 시 GOAL 카드, F-021 시 아카이브 박스, F-022 시 아카이브 드로어가 사용자 화면에 점진 노출.

## Ready Count

C-3 ready=4 (F-019/F-021/F-023/F-025). 룰 충족.

## Phase C 완료 후

archive 후 Phase D (또는 세션 종료) — 다음 사용자 의사 결정 사항.
