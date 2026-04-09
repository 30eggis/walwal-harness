---
docmeta:
  id: ia-compliance
  title: IA Structure Compliance — Step 0 (Gate) for Flutter
  type: output
  createdAt: 2026-04-09T00:00:00Z
  updatedAt: 2026-04-09T00:00:00Z
  source:
    producer: agent
    skillId: harness-evaluator-functional-flutter
  inputs:
    - documentId: evaluator-functional-ia-compliance
      uri: ../../evaluator-functional/references/ia-compliance.md
      relation: output-from
      sections:
        - sourceRange:
            startLine: 1
            endLine: 37
          targetRange:
            startLine: 32
            endLine: 120
  tags:
    - evaluator
    - flutter
    - ia-compliance
    - gate
---

# IA Structure Compliance — Step 0 (Gate) for Flutter

## 검증 방법

```bash
# 1. 실제 Flutter 구조 확인
ls -R lib/ integrated_data_layer/lib/ 2>/dev/null

# 2. git diff로 소유권 위반 검출 (이번 스프린트 범위)
git log --name-only --pretty=format: HEAD~[sprint_commits].. | sort -u
```

## 검증 항목

| 검증 | 판정 | 예시 |
|------|------|------|
| IA-MAP 경로가 실제 존재하는가 | 누락 → FAIL | `lib/ui/pages/` 미생성 |
| IA-MAP에 없는 경로가 생겼는가 | 미등록 → DRIFT 기록 | `lib/services/` 무단 생성 |
| `[FE]` 소유를 BE가 수정했는가 | 침범 → FAIL | `lib/ui/` BE 수정 |
| `[META]`/`[HARNESS]` 침범 | 침범 → FAIL | `AGENTS.md` 수정 |
| `pubspec.yaml` 의존성 추가가 계약 범위 내인가 | 범위 이탈 → DRIFT 기록 | 승인 없는 의존성 추가 |

## Flutter 전용 추가 검증

| 검증 | 판정 |
|------|------|
| `integrated_data_layer/lib/2_data_sources/remote/` 내 파일이 프로젝트 컨벤션(`request/body/`, `response/`, `rest_api.dart`)을 지키는가 | 위반 → FAIL |
| `lib/ui/pages/` 내 새 페이지가 `xxx_page.dart` + `xxx_page_vm.dart` 쌍으로 존재하는가 | 파트너 누락 → FAIL |
| `bridges/` 하위에 신규 파일이 추가되었는가 | 추가 → FAIL (레거시 금지) |
| `lib/l10n/` 의 arb 파일 키 집합이 모든 언어에서 동일한가 | 불일치 → FAIL |

## 판정 규칙

- **경로 누락 / 소유권 침범 / 파트너 누락** → 즉시 FAIL, Step 1 이하 SKIP
- **미등록 경로 (Drift)** → FAIL 아님, evaluation에 `## AGENTS.md Drift` 기록
- **arb 키 불일치** → FAIL (i18n 원칙 위반)

## Output (evaluation-functional.md에 포함)

```markdown
## Step 0: IA Structure Compliance
- Verdict: PASS / FAIL (GATE)
- IA-MAP paths checked: [N]개
- Missing paths: [목록 또는 "none"]
- Unregistered paths: [목록 또는 "none"]
- Ownership violations: [목록 또는 "none"]
- Page/VM pair check: [N pages checked, N missing partners]
- arb key diff: [none | "app_ja.arb missing: cancel, confirm"]
```
