---
docmeta:
  id: flutter-web-pattern
  title: Flutter Web 패턴 — fe_target=web 전용
  type: output
  createdAt: 2026-04-09T00:00:00Z
  updatedAt: 2026-04-09T00:00:00Z
  source:
    producer: agent
    skillId: harness-generator-frontend-flutter
  inputs:
    - documentId: harness-generator-frontend-flutter-skill
      uri: ../SKILL.md
      relation: output-from
      sections:
        - sourceRange:
            startLine: 56
            endLine: 90
          targetRange:
            startLine: 21
            endLine: 240
    - documentId: flutter-anti-patterns
      uri: ./anti-patterns.md
      relation: output-from
      sections:
        - sourceRange:
            startLine: 22
            endLine: 75
          targetRange:
            startLine: 90
            endLine: 165
  tags:
    - flutter
    - flutter-web
    - dart-web
    - go-router
---

# Flutter Web 패턴 (`fe_target = web` 전용)

`pipeline.json.fe_target == "web"` 일 때만 적용. Mobile/Desktop 타겟에서는 이 문서의 규칙을 무시한다.

## 1. 프로젝트 활성화

기존 Flutter 프로젝트에 Web 타겟이 없으면:

```bash
flutter config --enable-web
flutter create --platforms=web .
```

`web/index.html`, `web/manifest.json`, `web/favicon.png`, `web/icons/` 가 생성된다.

## 2. 빌드 및 개발 서버

| 명령 | 용도 |
|------|------|
| `flutter run -d chrome` | 개발 서버 (HMR 포함) |
| `flutter run -d chrome --web-port 8080` | 포트 고정 |
| `flutter build web --release` | 프로덕션 빌드 (`build/web/`) |
| `flutter build web --release --web-renderer canvaskit` | CanvasKit 렌더러 (성능 우선) |
| `flutter build web --release --web-renderer html` | HTML 렌더러 (호환성 우선, 작은 번들) |

> **렌더러 선택**: 모바일 사파리 호환성이 중요하면 `html`, 데스크톱/Chrome 중심이면 `canvaskit` (또는 auto).

## 3. 라우팅 — `go_router` 권장

URL 동기화 + 브라우저 history 지원을 위해 `go_router` 사용.

```yaml
# pubspec.yaml
dependencies:
  go_router: ^14.0.0
```

```dart
// lib/router/app_router.dart
import 'package:go_router/go_router.dart';

final pAppRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (ctx, state) => const HomePage()),
      GoRoute(path: '/login', builder: (ctx, state) => const LoginPage()),
      GoRoute(
        path: '/items/:id',
        builder: (ctx, state) => ItemPage(id: state.pathParameters['id']!),
      ),
    ],
  );
});
```

```dart
// main.dart
class App extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(pAppRouterProvider);
    return MaterialApp.router(
      routerConfig: router,
      // ...
    );
  }
}
```

**Hash routing vs Path routing**:
- 기본은 hash routing (`/#/login`)
- Path routing 으로 바꾸려면 `web/index.html` 의 `<base href="/">` 설정 + 서버 fallback (모든 경로 → `index.html`)

## 4. JS Interop (필요할 때만)

크로스플랫폼 코드를 우선하되, Web 전용 API 가 필요하면 `package:web` + `dart:js_interop` 사용.

```dart
import 'package:web/web.dart' as web;
import 'dart:js_interop';

void copyToClipboard(String text) {
  web.window.navigator.clipboard.writeText(text.toJS);
}

String getUserAgent() => web.window.navigator.userAgent;
```

**Conditional import 패턴** (cross-platform 코드를 web/io 로 분기):

```dart
// platform_helper.dart (interface)
abstract class PlatformHelper {
  String get platformName;
}

PlatformHelper getPlatformHelper() => throw UnimplementedError();
```

```dart
// platform_helper_web.dart
import 'package:web/web.dart' as web;
import 'platform_helper.dart';

class WebPlatformHelper implements PlatformHelper {
  @override
  String get platformName => 'web (${web.window.navigator.userAgent})';
}

PlatformHelper getPlatformHelper() => WebPlatformHelper();
```

```dart
// platform_helper_io.dart
import 'dart:io';
import 'platform_helper.dart';

class IoPlatformHelper implements PlatformHelper {
  @override
  String get platformName => 'io (${Platform.operatingSystem})';
}

PlatformHelper getPlatformHelper() => IoPlatformHelper();
```

```dart
// 사용처
import 'platform_helper.dart'
  if (dart.library.html) 'platform_helper_web.dart'
  if (dart.library.io) 'platform_helper_io.dart';

final helper = getPlatformHelper();
print(helper.platformName);
```

## 5. CORS 와 백엔드 연동

Flutter Web 은 브라우저에서 실행되므로 백엔드 API 호출 시 **CORS** 가 적용된다.

- 개발 단계: 백엔드 Gateway 의 `Access-Control-Allow-Origin` 에 `http://localhost:8080` (또는 `*`) 추가
- 프로덕션: 동일 origin 또는 명시적 CORS 화이트리스트
- API 키/인증 토큰은 **HttpOnly cookie** 또는 메모리 보관 (localStorage 는 XSS 위험)

`Dio` 인터셉터로 CSRF 토큰 등을 헤더에 추가:

```dart
final dio = Dio(BaseOptions(
  baseUrl: 'https://api.example.com',
  headers: {'Content-Type': 'application/json'},
));

dio.interceptors.add(InterceptorsWrapper(
  onRequest: (options, handler) {
    final token = ref.read(pAuthProvider).accessToken;
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    return handler.next(options);
  },
));
```

## 6. SEO / Meta Tags

`web/index.html` 의 `<head>` 에 SEO 메타 태그 추가:

```html
<meta name="description" content="Suprema CLUe — Smart Access Control">
<meta property="og:title" content="CLUe">
<meta property="og:description" content="...">
<meta property="og:image" content="/icons/og-image.png">
<link rel="canonical" href="https://app.example.com">
```

> SPA 의 SEO 한계: Flutter Web 은 client-side rendering 이므로 검색엔진이 동적 콘텐츠를 인덱싱하지 못할 수 있다. SSR 이 필요하면 Next.js + REST API 패턴을 고려.

## 7. 자산 최적화

- 이미지: `assets/images/` 에 두고 `pubspec.yaml` 의 `flutter.assets` 에 등록
- 폰트: `web/fonts/` 또는 `assets/fonts/` + `pubspec.yaml` 의 `flutter.fonts`
- 큰 이미지: webp 사용 권장 (`flutter_image_compress` 또는 사전 변환)
- Tree-shaking: `flutter build web --tree-shake-icons` 로 사용하지 않는 Material 아이콘 제거

## 8. PWA (Progressive Web App)

`flutter create --platforms=web` 시 자동 생성되는 `web/manifest.json` 을 채워서 PWA 로 동작:

```json
{
  "name": "CLUe",
  "short_name": "CLUe",
  "start_url": "/",
  "display": "standalone",
  "background_color": "#FFFFFF",
  "theme_color": "#6682FF",
  "icons": [
    { "src": "icons/Icon-192.png", "sizes": "192x192", "type": "image/png" },
    { "src": "icons/Icon-512.png", "sizes": "512x512", "type": "image/png" }
  ]
}
```

Service worker 는 `flutter build web` 시 자동 생성된다 (`flutter_service_worker.js`).

## 9. 디버깅 — Chrome DevTools

- `flutter run -d chrome` 후 Chrome 자체 DevTools 열기 (F12)
- Console 에서 `print()` 출력 확인 가능 (단, 프로덕션 빌드에서는 `print` 금지)
- Source map 활성화: `--web-renderer html --source-maps` (디버그 빌드 기본)
- Network 탭에서 API 호출 직접 검사 가능 → Playwright 기반 `evaluator-functional` 도 동일하게 동작

## 10. Eval 인터페이스

`fe_target = web` 인 경우 `harness-next.sh` 가 다음과 같이 자동 라우팅:

```
generator-frontend-flutter (Self-Verification: flutter analyze + flutter test)
  → evaluator-functional (Playwright MCP — http://localhost:포트 E2E)
  → evaluator-visual (Playwright MCP — 스크린샷 + 반응형 + 접근성)
```

**Generator 의 Self-Verification 단계에서 `flutter build web --release` 가 성공하는지 확인** 후 handoff.

## 11. 호스팅 (참고)

| 호스팅 | 빌드 산출물 |
|--------|------------|
| Vercel | `build/web/` 디렉토리를 정적 호스팅 |
| Netlify | 동일 |
| Firebase Hosting | `firebase deploy --only hosting` (firebase.json 의 public 을 `build/web` 으로) |
| GitHub Pages | `build/web/` 을 gh-pages 브랜치에 푸시 |
| 자체 서버 | nginx 로 정적 파일 서빙 + SPA fallback (`try_files $uri /index.html`) |

호스팅 결정은 Planner / 사용자가 함. Generator 는 빌드 산출물만 보장.
