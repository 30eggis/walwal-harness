---
docmeta:
  id: dynamic-registration
  title: 동적 Gotcha / Convention 등록 — 모든 worker mandatory
  type: input
  createdAt: 2026-04-27T00:00:00Z
  updatedAt: 2026-04-27T00:00:00Z
  source:
    producer: user
    skillId: harness
  inputs: []
  tags: [harness, gotcha, convention, dynamic-registration, mandatory]
---

# 동적 Gotcha / Convention 등록 — 모든 worker mandatory

모든 Generator / Evaluator / Lead 는 자기 작업 결과물(`evaluation-*.md` / `gen-report-*.md` / `lead-report-*.md`) 끝에 **두 개의 fenced JSON 블록**을 반드시 포함한다. `harness-next.sh` 와 Team mode Lead 가 작업 직후 자동으로 `harness-gotcha-register.sh --scan-all` 을 호출하여 두 블록을 dedup append 한다.

**왜 mandatory 인가**: 사용자 명시 — "Gen/Eval 이 발견한 패턴은 메뉴얼로 시키기 전에 동적으로 등록되어야 한다. 자동으로 패턴화되는 이슈는 등록하라." 한 번 발견된 실수가 다음 sprint 에서 반복되지 않게 하려면 발견자가 그 자리에서 등록하는 것이 유일한 closure.

**금지**: 두 블록 중 하나라도 누락된 채로 작업 종료. 비어 있어도 `[]` 로 명시 (블록 자체 생략 금지).

---

## 1) gotcha_candidates — 부정 가이드 (실수 패턴)

**누가 등록**:
- Evaluator: 평가 중 발견한 generator 의 반복 가능한 결함
- Generator: 자기 작업 중 한 번 시도했다가 깨졌던 접근, 자체 fix 한 코드 실수
- Lead (Team mode): worker 보고서들에서 N 회 반복되는 패턴 (≥2 occurrences 권장)

**검출 기준** (하나라도 해당):
- 같은 sprint 내 다른 feature 에서도 재발할 가능성이 있는 결함
- generator 가 자주 빠뜨리는 케이스 (RSC↔CC 경계, schema 누락, missing not-found.tsx 등)
- spec/contract 위반 패턴
- AC 부분 통과 / Hard Gate 위반 사유
- lint/type 이 한 번에 안 잡힌 케이스 (정적 분석으로 못 잡는 결함)

**스키마**:
```gotcha_candidates
[
  {
    "target": "generator-frontend",
    "rule_id": "rsc-cc-boundary-monitoring",
    "title": "Server Component 에서 useState/useEffect 호출",
    "wrong": "app/monitoring/page.tsx 에 'use client' 없이 hook 사용 → 빌드 통과해도 런타임에 깨짐",
    "right": "client-side state 사용 시 파일 최상단에 'use client' 명시. 또는 server component 로 유지하면서 client 부분만 분리.",
    "why": "Next.js App Router 의 RSC↔CC 경계는 정적 분석으로 100% 안 잡힘. F-209 에서 발견.",
    "scope": "app/**/page.tsx, app/**/layout.tsx",
    "source": "evaluator-functional:F-209"
  }
]
```

비어 있으면:
```gotcha_candidates
[]
```

필수 필드: `target`, `rule_id`, `title`. 권장 필드: `wrong`, `right`, `why`, `scope`, `source`.

`target` 가능 값: `planner`, `dispatcher`, `brainstorming`, `generator-backend`, `generator-frontend`, `generator-frontend-flutter`, `evaluator-code-quality`, `evaluator-functional`, `evaluator-visual`, `evaluator-functional-flutter`.

`rule_id` 는 dedup key — 같은 rule_id 가 이미 있으면 Occurrences +1 만 증가하고 본문은 안 바뀜. **kebab-case 짧고 의미 있는 식별자**.

---

## 2) convention_candidates — 긍정 가이드 (반복 가능한 best practice)

**누가 등록**:
- Evaluator: 평가 중 확립된 반복 가능한 모범 사례
- Generator: 작업 중 적용한 일관된 패턴 (다른 feature 에 모방되어야 하는)
- Lead: sprint 전반에서 합의된 룰

**검출 기준**:
- 같은 sprint 의 다른 feature 가 모방해야 할 패턴
- API 계약 / 폴더 구조 / 명명 규칙 관련 결정
- 사용자가 "이렇게 해" 라고 한 한 번의 발언이 평가/생성에서 일반화 가능한 경우

**스키마**:
```convention_candidates
[
  {
    "scope": "generator-frontend",
    "rule_id": "route-segment-files",
    "title": "App Router 세그먼트 필수 파일 세트",
    "rule": "모든 app/**/page.tsx 는 같은 폴더에 not-found.tsx, error.tsx, loading.tsx 를 함께 배치한다.",
    "why": "Next.js 의 segment-level 에러/로딩 처리. 누락 시 default 흰 화면 노출. F-209 평가에서 표준화 결정.",
    "source": "evaluator-functional:F-209"
  }
]
```

비어 있으면:
```convention_candidates
[]
```

필수 필드: `rule_id`, `title`, `rule`. 권장 필드: `scope`, `why`, `source`.

`scope` 가능 값: `shared` (전체 공통), `generator-backend`, `generator-frontend`, `evaluator-*`, `planner`. 미지정 시 `shared`.

---

## 3) 등록 결과 확인

작업 완료 후 다음 명령으로 등록된 항목 확인 가능:
```bash
bash scripts/harness-gotcha-register.sh . --scan-all  # 수동 재스캔
ls .harness/gotchas/ .harness/conventions/             # 누적 결과
tail -20 .harness/progress.log | grep gotcha-register  # 등록 로그
```

## 4) Team mode 추가 룰

Team mode 에서 Lead 는 worker PASS/FAIL 처리 직후 (merge 전) 다음을 실행한다:
```bash
bash scripts/harness-gotcha-register.sh . --scan-all
```
이로써 worker 가 작성한 두 블록이 즉시 누적되며, 다음 worker spawn 시 새 worker 가 갱신된 gotchas/conventions 를 startup 에 읽어 같은 실수를 반복하지 않는다.
