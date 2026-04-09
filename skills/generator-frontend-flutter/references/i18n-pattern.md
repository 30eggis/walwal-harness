---
docmeta:
  id: i18n-pattern
  title: 다국어 (i18n) ARB 패턴
  type: output
  createdAt: 2026-04-09T00:00:00Z
  updatedAt: 2026-04-09T00:00:00Z
  source:
    producer: agent
    skillId: harness-generator-frontend-flutter
  inputs:
    - documentId: clue-fe-flutter-i18n
      uri: ../../../../../moon_web/clue-fe-flutter.skill
      relation: output-from
      sections:
        - sourceRange:
            startLine: 1
            endLine: 60
          targetRange:
            startLine: 32
            endLine: 110
  tags:
    - flutter
    - i18n
    - arb
    - l10n
---

# 다국어 (i18n) ARB 패턴

## ARB 파일 기반 l10n

### 파일 경로

- 영어: `lib/l10n/app_en.arb`
- 한국어: `lib/l10n/app_ko.arb`
- 일본어: `lib/l10n/app_ja.arb`

프로젝트에 따라 `assets/strings/en.json` 등 다른 경로를 쓸 수 있다.
`AGENTS.md` / sprint-contract.md 의 기존 컨벤션을 우선한다.

### 작업 순서

1. 문자열 언어 판별 (예: "취소" → ko, "Cancel" → en)
2. 해당 언어 arb 파일에 **키 존재 여부 확인** (중복 방지)
3. 없으면 모든 언어 파일에 동시 추가 (`app_en.arb`, `app_ko.arb`, `app_ja.arb`)
4. 코드 치환 → `LocaleAssist().of.키이름`

### 사용법

```dart
// 기본 문자열
Text(
  LocaleAssist().of.cancel,
  style: MyTextStyle.size15.w500.xFF9CA3AF,
)

// 문자열 내 스타일 별도 구현 (ClueText 등 프로젝트 커스텀 위젯 사용)
ClueText(
  "${LocaleAssist().of.all} (${count})",
  style: MyTextStyle.size16.w500,
  targetList: [
    TargetModel(
      text: "(${count})",
      style: MyTextStyle.size16.w500.xFF6682FF,
    ),
  ],
)
```

### ARB 키 네이밍 규칙

```json
{
  "cancel": "취소",
  "confirm": "확인",
  "doorOpen": "문 열기",
  "networkError": "네트워크 오류가 발생했습니다"
}
```

- **camelCase** 사용
- 모든 arb 파일(en, ko, ja)에 **동일 키 동시 추가**
- 기존 키 검색 후 중복 방지 (`grep -rn '"cancel"' lib/l10n/`)
- 플레이스홀더 필요 시 ICU MessageFormat 사용

## 필수 원칙

- 영문 전용 표기 지시가 없는 한 **모든 사용자 노출 문자열은 다국어 처리**
- 하드코딩된 문자열 사용 금지 (`Text('취소')` ✗)
- 새 페이지 추가 시 관련 문자열 **일괄 등록** — 스프린트 중 누락 방지
- 모든 arb 파일의 키 집합은 동일해야 한다 (Evaluator가 diff 검사)

## Self-Check

```bash
# 하드코딩된 한글 탐지
grep -rn "Text('[가-힣]" lib/ui/

# 누락 키 탐지 (en 기준)
python3 -c "import json; en=set(json.load(open('lib/l10n/app_en.arb')).keys()); ko=set(json.load(open('lib/l10n/app_ko.arb')).keys()); print('missing in ko:', en - ko); print('missing in en:', ko - en)"
```
