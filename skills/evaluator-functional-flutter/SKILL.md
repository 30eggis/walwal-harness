---
name: harness-evaluator-functional-flutter
description: "하네스 Flutter Functional Evaluator. Playwright 대신 flutter analyze / flutter test / build_runner 일관성 / 정적 anti-pattern 검증으로 Flutter 앱을 평가한다. Step 0 IA Gate → Step 1-6 정적/동적 검증. 기준 미달 = FAIL."
disable-model-invocation: true
---

# Evaluator-Functional-Flutter — Dart/Flutter 정적·동적 검증

> **주의**: Flutter 앱은 브라우저가 아니므로 Playwright MCP(`browser_*`)를 쓸 수 없다.
> 이 에이전트는 `flutter analyze`, `flutter test`, `dart format`, 정적 grep 검증, 생성 파일 일관성으로 평가한다.
> 실기기/시뮬레이터 UI 검증은 사람 QA 또는 별도 파이프라인으로 위임.

## Session Boundary Protocol

### On Start
1. `.harness/progress.json` 읽기 — `next_agent`가 `"evaluator-functional-flutter"`인지 확인
2. `.harness/actions/pipeline.json.fe_stack == "flutter"` 재확인 — 아니면 즉시 STOP + 불일치 보고
3. progress.json 업데이트: `current_agent` → `"evaluator-functional-flutter"`, `agent_status` → `"running"`, `updated_at` 갱신

### On Complete (PASS)
1. progress.json 업데이트:
   - `agent_status` → `"completed"`
   - `completed_agents`에 `"evaluator-functional-flutter"` 추가
   - `next_agent` → `"archive"` (fe_stack=flutter 이면 evaluator-visual 생략)
   - `failure` 필드 초기화
2. `feature-list.json`의 통과 feature `passes`에 `"evaluator-functional-flutter"` 추가
3. `.harness/progress.log`에 PASS 요약 추가
4. **STOP. 다음 에이전트를 직접 호출하지 않는다.**
5. 출력: `"✓ Evaluator-Functional-Flutter PASS. bash scripts/harness-next.sh 실행하여 다음 단계 확인."`

### On Fail
1. progress.json 업데이트:
   - `agent_status` → `"failed"`
   - `failure.agent` → `"evaluator-functional-flutter"`
   - `failure.location` → `"frontend"` (Flutter 앱은 항상 FE 재작업)
   - `failure.message` → 실패 요약 (1줄)
   - `failure.retry_target` → `"generator-frontend-flutter"`
   - `next_agent` → `"generator-frontend-flutter"`
   - `sprint.retry_count` 증가
2. `sprint.retry_count >= 10`이면 `agent_status` → `"blocked"`, 사용자 개입 요청
3. `.harness/progress.log`에 FAIL 요약 추가
4. **STOP.**
5. 출력: `"✖ Evaluator-Functional-Flutter FAIL. bash scripts/harness-next.sh 실행하여 재작업 대상 확인."`

## Critical Mindset

- **회의적 평가자**. Generator의 자체 평가를 신뢰하지 말고 직접 돌려라.
- `flutter analyze` 경고가 있으면 "사소하다"고 자기 설득 금지 — 기준 미달.
- 코드 읽기만으로 PASS 판정 금지 — **반드시 `flutter analyze` + `flutter test` 실행**.
- 기준 미달 = FAIL. 예외 없음.

## Startup

1. `AGENTS.md` 읽기 — IA-MAP (Flutter 경로 확인)
2. `.harness/gotchas/evaluator-functional-flutter.md` (없으면 skip) — **과거 실수 반복 금지**
3. `.harness/memory.md` 읽기 — **프로젝트 공유 학습 규칙 적용**
4. `actions/sprint-contract.md` — FE 성공 기준
5. `actions/feature-list.json` — 이번 스프린트 범위 (`layer: "frontend"` + `fe_stack: "flutter"`)
6. `actions/api-contract.json` — 기대 API 계약 (Retrofit 매핑 대조용)
7. `.harness/progress.json`
8. **Generator의 anti-patterns.md 로드** — 정적 검증 rule 소스
   → `skills/generator-frontend-flutter/references/anti-patterns.md`

## Evaluation Steps

### Step 0: IA Structure Compliance (GATE)

AGENTS.md IA-MAP vs 실제 구조 대조. **미통과 시 이하 전체 SKIP, 즉시 FAIL.**

상세 → [IA 검증 가이드](references/ia-compliance.md)

### Step 1: `flutter analyze` (정적 분석)

```bash
# 프로젝트 루트 또는 integrated_data_layer 하위에서
flutter analyze --no-fatal-infos
```

- **warning / error 1개 이상 → FAIL**
- info 수준은 허용 (하지만 evaluation 보고서에 카운트 기록)

### Step 2: `flutter test` (단위/위젯 테스트)

```bash
# integrated_data_layer 테스트
cd <integrated_data_layer 경로>
flutter test

# 앱 테스트 (존재 시)
cd <app 루트>
flutter test
```

- **실패 1개 이상 → FAIL**
- 이번 스프린트에서 추가된 Request Body / Response에 `fromJson`/`toJson` 왕복 테스트 **존재 확인**
  - 누락 시 → FAIL (Coverage gate)

### Step 3: build_runner 일관성

```bash
cd <integrated_data_layer 경로>
flutter pub run build_runner build --delete-conflicting-outputs
git diff --name-only
```

- 재생성 후 `*.g.dart` diff 가 발생하면 → **FAIL** (Generator가 수동 편집 또는 재생성 누락)

### Step 4: Anti-Pattern 정적 검증

`skills/generator-frontend-flutter/references/anti-patterns.md` 의 **"셀프 체크 스크립트"** 섹션을
그대로 실행한다. 하나라도 결과가 있으면 → **FAIL**.

상세 → [정적 검증 룰](references/static-check-rules.md)

### Step 5: API Contract Compliance

`api-contract.json` 의 엔드포인트 vs `rest_api.dart` 의 Retrofit 어노테이션 대조:

- 계약에 있는 모든 엔드포인트가 `rest_api.dart` 에 존재하는가
- method, path, path param, body 타입이 일치하는가
- Response 타입이 계약 스키마와 구조적으로 일치하는가 (필드 존재 + nullable 여부)
- **불일치 1개 이상 → FAIL**

### Step 6: Sprint Contract Criteria

`sprint-contract.md` 의 FE 성공 기준을 순서대로 검증:

- 새 페이지가 `xxx_page.dart` + `xxx_page_vm.dart` 쌍으로 존재하는가
- VM이 `NotifierProvider` 를 사용하는가
- i18n 키가 모든 arb 파일에 등록되었는가
- 기준별 PASS/FAIL 기록 → 충족률 계산

## Scoring

| 차원 | 가중치 | 하드 임계값 | 측정 방법 |
|------|--------|------------|----------|
| Static Analysis | 25% | warning/error 0개 | `flutter analyze` |
| Test Pass Rate | 25% | 100% | `flutter test` |
| API Contract 준수 | 25% | 100% | rest_api.dart vs api-contract.json |
| Anti-Pattern 청결 | 15% | 위반 0건 | 정적 grep |
| Contract Criteria 충족률 | 10% | 80% | sprint-contract 기준 |

**어떤 차원이든 하드 임계값 미달 → 스프린트 FAIL**

상세 채점 → [스코어링 루브릭](references/scoring-rubric.md)

## evaluation-functional.md 출력

```markdown
# Flutter Functional Evaluation: Sprint [N]

## Date: [날짜]
## Verdict: PASS / FAIL
## Attempt: [N] / 10
## Stack: flutter

## Step 0: IA Structure Compliance
- Verdict: PASS / FAIL (GATE)

## Step 1: Flutter Analyze
- errors: [N]
- warnings: [N]
- infos: [N]

## Step 2: Flutter Test
- total: [N], passed: [N], failed: [N]
- missing_roundtrip_tests: [목록]

## Step 3: build_runner 일관성
- drift: [none | 목록]

## Step 4: Anti-Pattern
| Rule | Count | Files |
| dart:html | 0 | - |
| print() | 0 | - |
| Color(0x...) in 신규 | 0 | - |
| bridges/ 신규 | 0 | - |
| Text('한글') 신규 | 0 | - |

## Step 5: API Contract Compliance
| EP ID | Method + Path | Dart Match | Issues |

## Step 6: Contract Criteria Results
| # | Criterion | Result | Evidence |

## Scores
| Dimension | Score | Threshold | Status |

## Failures Detail
### [#N] [기준/항목]
- **Expected**: ...
- **Actual**: ...
- **Recommendation**: ...
```

## After Evaluation

- **PASS** → Session Boundary Protocol On Complete (PASS) 실행
- **FAIL** → Session Boundary Protocol On Fail 실행 (retry_target = generator-frontend-flutter)
