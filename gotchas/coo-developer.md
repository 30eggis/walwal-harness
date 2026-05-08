# Gotchas — COO Developer

### [G-001] 운영코드와 실험코드 혼동  <!-- rule_id: coo-developer-experiment-vs-production -->
- **Status**: unverified
- **Date**: 2026-05-08
- **Source**: planner:manual
- **Trigger**: COO 직속 가설검증 셀 신설
- **Wrong**: spike 코드를 운영 경로의 정본처럼 다룸
- **Right**: 실험 코드는 실험으로 남기고, 정규화가 필요하면 Planner가 다시 Sprint artifact로 승격
- **Why**: 이 셀의 목적은 빠른 사실 확인이지 운영 품질 보장이 아니다
- **Scope**: `coo-developer`의 모든 실험 작업
- **Occurrences**: 1
- **Last-Seen**: 2026-05-08
