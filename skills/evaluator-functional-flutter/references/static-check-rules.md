---
docmeta:
  id: static-check-rules
  title: Flutter 정적 검증 룰 (Anti-Pattern Gate)
  type: output
  createdAt: 2026-04-09T00:00:00Z
  updatedAt: 2026-04-09T00:00:00Z
  source:
    producer: agent
    skillId: harness-evaluator-functional-flutter
  inputs:
    - documentId: flutter-anti-patterns
      uri: ../../generator-frontend-flutter/references/anti-patterns.md
      relation: output-from
      sections:
        - sourceRange:
            startLine: 1
            endLine: 280
          targetRange:
            startLine: 32
            endLine: 180
  tags:
    - evaluator
    - flutter
    - static-check
    - anti-pattern
---

# Flutter 정적 검증 룰

Generator의 `anti-patterns.md` 를 Source of Truth 로 삼아 정적 검증을 수행한다.
Generator가 신규 룰을 추가하면 Evaluator는 자동으로 그 룰을 따르게 된다 — **두 문서 간 drift 금지.**

## 실행 방법

**Evaluator는 반드시** `skills/generator-frontend-flutter/references/anti-patterns.md` 의
"셀프 체크 스크립트" 섹션을 **파일로 읽어서 그대로 실행**한다. 하네스의 단일 진실 원칙.

```bash
# anti-patterns.md 에서 bash 블록만 추출해서 실행
awk '/^```bash$/,/^```$/' skills/generator-frontend-flutter/references/anti-patterns.md
```

## 룰 요약 (Evaluator가 결과를 표로 정리)

| Rule ID | 설명 | 명령 | Fail 조건 |
|---------|------|------|----------|
| FL-01 | 웹 API 직접 참조 | `grep -rn "dart:html\|universal_html" lib/ integrated_data_layer/lib/` | 매치 1+ |
| FL-02 | print/console 남발 | `grep -rn "^\s*print(" lib/ integrated_data_layer/lib/` | 매치 1+ |
| FL-03 | 하드코딩 색상 (신규) | `git diff --name-only --diff-filter=A HEAD~N..HEAD \| grep '\.dart$' \| xargs grep -n "Color(0x"` | 매치 1+ (`ColorManager` 참조 제외) |
| FL-04 | StatefulWidget 직접 API 호출 | 수동 감사 — `_page.dart` 에 `dataLayer\|DataLayer` 호출이 있는데 짝 `_page_vm.dart` 없음 | 패턴 발견 |
| FL-05 | bridges/ 신규 참조 | `git diff HEAD~N..HEAD \| grep "^+.*bridges/"` | 매치 1+ |
| FL-06 | 하드코딩 한글 (신규 UI) | `git diff --name-only --diff-filter=AM HEAD~N..HEAD \| grep 'lib/ui/.*\.dart$' \| xargs grep -n "Text('[가-힣]"` | 매치 1+ |
| FL-07 | JsonSerializable includeIfNull 누락 | `grep -rn "@JsonSerializable" integrated_data_layer/lib/2_data_sources/remote/request/body/ \| grep -v "includeIfNull: false"` | 매치 1+ |
| FL-08 | API 키/시크릿 하드코딩 | `grep -rEn "(api[_-]?key\|secret\|token)\s*=\s*['\"][A-Za-z0-9]{16,}['\"]" lib/ integrated_data_layer/lib/` | 매치 1+ |

> `HEAD~N` 의 N은 sprint_commits 수 — `git log --format=%h HEAD~sprint_start..HEAD` 로 결정.

## FL-04 수동 감사 방법

```bash
# 1. 신규/수정된 page 파일 목록
PAGES=$(git diff --name-only HEAD~N..HEAD | grep '_page\.dart$')

# 2. 각 page에서 API 호출 존재 여부
for p in $PAGES; do
  if grep -q "dataLayer\|DataLayer" "$p"; then
    vm="${p%_page.dart}_page_vm.dart"
    if [ -f "$vm" ] && grep -q "dataLayer\|DataLayer" "$vm"; then
      echo "OK (VM handles API): $p"
    else
      echo "FAIL (page calls API without VM): $p"
    fi
  fi
done
```

VM이 없고 페이지가 직접 호출하면 **FL-04 FAIL**.

## 결과 집계

```markdown
## Step 4: Anti-Pattern

| Rule | Status | Count | Files |
|------|--------|-------|-------|
| FL-01 dart:html | PASS/FAIL | 0 | - |
| FL-02 print | PASS/FAIL | 0 | - |
| FL-03 color hardcode | PASS/FAIL | 0 | - |
| FL-04 stateful API call | PASS/FAIL | 0 | - |
| FL-05 bridges/ new | PASS/FAIL | 0 | - |
| FL-06 ko hardcode | PASS/FAIL | 0 | - |
| FL-07 includeIfNull missing | PASS/FAIL | 0 | - |
| FL-08 secret hardcode | PASS/FAIL | 0 | - |

Overall: PASS / FAIL
```

**어떤 룰이든 FAIL 1건 → Step 4 전체 FAIL → 스프린트 FAIL** (하드 임계값: 위반 0건).
