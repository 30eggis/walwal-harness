---
docmeta:
  id: anti-patterns
  title: Flutter Anti-Patterns & Forbidden APIs
  type: output
  createdAt: 2026-04-09T00:00:00Z
  updatedAt: 2026-04-09T00:00:00Z
  source:
    producer: agent
    skillId: harness-generator-frontend-flutter
  inputs:
    - documentId: clue-fe-flutter-skill
      uri: ../../../../../moon_web/clue-fe-flutter.skill
      relation: output-from
      sections:
        - sourceRange:
            startLine: 62
            endLine: 103
          targetRange:
            startLine: 32
            endLine: 180
  tags:
    - flutter
    - anti-patterns
    - forbidden
    - lint
---

# Flutter Anti-Patterns & Forbidden APIs

**Generator는 구현 완료 전 이 문서를 보고 셀프 체크한다.**
**Evaluator-Functional-Flutter 는 이 문서의 패턴을 `grep` 기반 정적 검증에 사용한다.**

각 항목은 **패턴 → 이유 → 대체 방법** 형태.

## 1. 웹 전용 API 직접 참조 (fe_target 별 차이)

### `fe_target = mobile` 또는 `desktop` — 금지
```dart
import 'dart:html';                              // ✗
import 'package:universal_html/html.dart';       // ✗
import 'package:web/web.dart';                   // ✗ (가드 없으면)
```

### 이유
Flutter 모바일/데스크톱 빌드에서 `dart:html` 참조는 즉시 빌드 실패한다.
가드 없이 import 하면 cross-platform 코드가 깨진다.

### 대체
- `kIsWeb` 분기로 플랫폼 체크 후 조건부 import
- `if (kIsWeb) { ... }` 가드 안에서만 web API 사용
- 또는 conditional import (`stub.dart` / `web.dart` / `io.dart`)

### `fe_target = web` — 허용 (단, 권장 패턴 준수)
```dart
import 'package:web/web.dart' as web;            // ✓ 권장 (modern)
import 'dart:js_interop';                        // ✓ JS interop
import 'dart:html';                              // ✓ (legacy, 신규 코드는 package:web 권장)
```

### Web 권장 패턴
- 새 코드는 `package:web` + `dart:js_interop` 사용 (Flutter 3.7+ 에서 stable)
- `dart:html` 은 legacy — 마이그레이션 대상이지만 즉시 금지는 아님
- 가능하면 web 전용 코드를 별도 파일로 분리하고 conditional import:
  ```dart
  // _web_helper.dart 또는 conditional import
  import 'platform_helper.dart'
    if (dart.library.html) 'platform_helper_web.dart'
    if (dart.library.io) 'platform_helper_io.dart';
  ```

### 검증
```bash
# fe_target = mobile/desktop: 0개여야 함
grep -rn "dart:html\|universal_html\|package:web" lib/ integrated_data_layer/lib/

# fe_target = web: 매치 OK, 단 'kIsWeb' 가드 또는 conditional import 와 함께 쓰는지 인접 라인 확인
```

---

## 2. print / console 남발

### 금지
```dart
print("user clicked");
debugPrint("response: $data");
```

### 이유
프로덕션 빌드에 로그가 섞이면 성능/보안 문제. 통일된 로거가 없으면 분석 불가.

### 대체
프로젝트의 `logger` 모듈 사용 (`Logger().d()`, `.i()`, `.w()`, `.e()`).
디버그 전용 출력도 `kDebugMode` 가드 필수.

### 검증
```bash
grep -rn "^\s*print(" lib/ integrated_data_layer/lib/
grep -rn "console\.log" lib/
```

---

## 3. 하드코딩 색상

### 금지
```dart
Container(color: Color(0xFF6682FF))
Text('Hello', style: TextStyle(color: Colors.blue))
```

### 이유
디자인 시스템 붕괴 + 다크모드/브랜딩 변경 시 전역 수정 불가.

### 대체
```dart
Container(color: ColorManager.primary)
Text('Hello', style: TextStyle(color: ColorManager.textPrimary))
```

`ColorManager` (또는 프로젝트의 Design Token) 경유 필수.

### 검증
```bash
grep -rn "Color(0x" lib/ui/ | grep -v "ColorManager\|color_manager"
```
신규 파일에서 결과 0개여야 함 (레거시 파일은 예외).

---

## 4. StatefulWidget 내 직접 API 호출

### 금지
```dart
class _MyPageState extends State<MyPage> {
  @override
  void initState() {
    super.initState();
    DataLayer.instance.ac.getExample(exampleId: 1).then((res) {  // ✗
      setState(() { _data = res; });
    });
  }
}
```

### 이유
테스트 불가능, 상태 공유 불가, UI와 비즈니스 로직 결합.

### 대체
VM (`NotifierProvider`) 에 API 호출을 옮기고 Page는 `ConsumerWidget` 으로.
상세 → [riverpod-pattern.md](./riverpod-pattern.md)

### 검증
`grep` 으로 자동 감지 어려움 — Evaluator가 신규 `*_page.dart` 파일에서
`dataLayer\|DataLayer` 호출 패턴을 확인하고, 파트너 `*_page_vm.dart` 파일에
동일 호출이 있는지 대조한다.

---

## 5. bridges/ 신규 사용

### 금지
```dart
import 'package:clue_mobile_app/bridges/xxx.dart';
```
신규 코드에서 참조 금지.

### 이유
BLOC 기반 레거시 — Riverpod 마이그레이션 방침에 따라 유지보수만 허용.

### 대체
신규 상태관리는 `NotifierProvider` + `Notifier<State>`.

### 검증
신규/수정 파일의 git diff에서 `bridges/` import 추가 여부 확인.
```bash
git diff --name-only HEAD~1 | xargs grep -l "bridges/" 2>/dev/null
```
새로 추가된 줄이 있으면 FAIL.

---

## 6. 하드코딩 문자열 (다국어 미처리)

### 금지
```dart
Text('취소')
Text('로그인 실패')
```

### 이유
i18n 원칙 위반 — 다국어 전환 시 즉시 깨짐.

### 대체
```dart
Text(LocaleAssist().of.cancel)
Text(LocaleAssist().of.loginFailed)
```

상세 → [i18n-pattern.md](./i18n-pattern.md)

### 검증
```bash
grep -rn "Text('[가-힣ぁ-んァ-ヶ一-龯]" lib/ui/
```
신규 파일에서 결과 0개여야 함.

---

## 7. JsonSerializable 누락 / includeIfNull 잘못 설정

### 금지
```dart
// @JsonSerializable 없이 수동 fromJson/toJson
@JsonSerializable()  // includeIfNull 누락 → 기본값 true
class UserBody { ... }
```

### 이유
서버가 null 필드를 bad request 처리하는 API 계약 위배. 코드 생성 불일치.

### 대체
```dart
@JsonSerializable(includeIfNull: false)
class UserBody { ... }
```

Request Body는 **항상** `includeIfNull: false`.

### 검증
```bash
grep -rn "@JsonSerializable" integrated_data_layer/lib/2_data_sources/remote/request/body/ | grep -v "includeIfNull: false"
```
결과 0개여야 함.

---

## 8. Non-null 남용

### 금지
```dart
// 서버 응답에 대해 non-null 단정
class ExampleData {
  final String name;       // ✗ 필수 지시 없으면 Nullable
  final int id;
}
```

### 이유
서버는 언제든 필드를 누락할 수 있음. non-null은 런타임 crash 유발.

### 대체
```dart
class ExampleData {
  final String? name;
  final int? id;
}
```

**필수 지시가 api-contract.json 에 명시된 필드만 non-null 허용.**

---

## 9. API 키 / 시크릿 하드코딩

### 금지
```dart
const apiKey = "sk-1234567890abcdef";
const Dio().options.headers['Authorization'] = 'Bearer xxx';
```

### 이유
APK 디컴파일로 즉시 노출 — 보안 사고.

### 대체
`--dart-define` 또는 `flutter_dotenv` + `.env` (gitignore).
런타임에 서버에서 발급받는 토큰 사용.

### 검증
```bash
grep -rEn "(api[_-]?key|secret|token)\s*=\s*['\"][A-Za-z0-9]{16,}['\"]" lib/ integrated_data_layer/lib/
```

---

## 셀프 체크 스크립트

Generator는 handoff 전 다음 명령을 모두 실행하고 결과를 sprint-contract.md에 기록한다.
**`fe_target` 에 따라 1번 룰의 적용 여부가 달라진다.**

```bash
# fe_target 읽기
FE_TARGET=$(jq -r '.fe_target // "web"' .harness/actions/pipeline.json 2>/dev/null || echo "web")

# 1. 웹 API 직접 참조 — fe_target=web 이 아닐 때만 검사
if [ "$FE_TARGET" != "web" ]; then
  grep -rn "dart:html\|universal_html\|package:web" lib/ integrated_data_layer/lib/ || echo "OK (FL-01 mobile/desktop)"
else
  # web 타겟: 가드 없는 사용만 경고 (수동 검토)
  grep -rn "dart:html\|package:web" lib/ | grep -v "kIsWeb\|conditional import" || echo "OK (FL-01 web — manual review)"
fi

# 2. print 남발
grep -rn "^\s*print(" lib/ integrated_data_layer/lib/ || echo "OK"

# 3. 하드코딩 색상 (신규 파일만 — git diff 기반)
git diff --name-only --diff-filter=A HEAD | grep '\.dart$' | xargs grep -n "Color(0x" 2>/dev/null || echo "OK"

# 4. bridges/ 신규 참조
git diff HEAD | grep "^+" | grep "bridges/" || echo "OK"

# 5. JsonSerializable + includeIfNull 확인
grep -rn "@JsonSerializable" integrated_data_layer/lib/2_data_sources/remote/request/body/ | grep -v "includeIfNull: false" || echo "OK"

# 6. 하드코딩 한글 (신규 UI)
git diff --name-only --diff-filter=AM HEAD | grep 'lib/ui/.*\.dart$' | xargs grep -n "Text('[가-힣]" 2>/dev/null || echo "OK"
```

모두 `OK` 여야 handoff 가능.
