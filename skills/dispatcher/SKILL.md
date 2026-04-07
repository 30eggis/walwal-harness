---
name: harness-dispatcher
description: "AI 하네스 파이프라인 선택 및 Gotcha 관리. 사용자 요청을 분석하여 FULLSTACK/FE-ONLY/BE-ONLY 파이프라인을 결정하고, 실수 지적 시 해당 에이전트의 gotchas에 기록한다. 트리거: '하네스 엔지니어링 시작', '하네스 시작', 'harness start'"
disable-model-invocation: false
---

# Dispatcher — Pipeline Selector + Gotcha Manager

## 1. Request Classification (최우선)

사용자 입력을 먼저 분류합니다:

- **실수 지적** ("아니", "잘못", "그렇게 하면 안 돼", "X로 해야지") → **Gotcha Flow**
- **기능 요청** ("만들어", "추가", "시작", PRD, OpenAPI) → **Pipeline Flow**
- **혼합** → Gotcha 먼저 기록 → Pipeline 이어서

## 2. Gotcha Flow

실수 지적 감지 시 → [Gotcha 상세 가이드](references/gotcha-flow.md)

핵심:
1. 교정 시그널 감지 (HIGH/MEDIUM만 기록)
2. 도메인 분석 → 대상 에이전트 판별
3. `.harness/gotchas/[agent].md`에 항목 추가 (중복 시 Occurrences 증가)
4. 사용자에게 기록 확인

## 3. Initialization Check (Phase 0)

파이프라인 선택 전 초기화 상태 확인:

```
.harness/ 없음     → bash scripts/scan-project.sh . && bash scripts/init-agents-md.sh .
AGENTS.md 없음     → 위와 동일
AGENTS.md 비하네스  → 기존 백업 + 리빌드
정상               → Pipeline Selection 진행
```

상세 → [초기화 가이드](references/initialization.md)

## 4. Pipeline Selection

| 시그널 | 파이프라인 |
|--------|-----------|
| OpenAPI/Swagger + FE 요청 | **FE-ONLY**: Planner(light) → Gen-FE → Eval-Func → Eval-Visual |
| 기존 서버 + BE 추가 | **BE-ONLY**: Planner → Gen-BE → Eval-Func(API-only) |
| 신규 PRD / 제품 설명 | **FULLSTACK**: Planner → Gen-BE → Gen-FE → Eval-Func → Eval-Visual |
| 불명확 | 3개 질문으로 확정 |

상세 → [파이프라인 정의](references/pipeline-definitions.md)

## 5. Output

`.harness/actions/pipeline.json` 생성 → 사용자 확인 → 다음 에이전트 실행
