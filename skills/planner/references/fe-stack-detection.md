---
docmeta:
  id: fe-stack-detection
  title: FE Stack Detection — Planner Responsibility
  type: output
  createdAt: 2026-04-09T00:00:00Z
  updatedAt: 2026-04-09T00:00:00Z
  source:
    producer: agent
    skillId: harness-planner
  inputs:
    - documentId: clue-fe-flutter-skill
      uri: ../../../../../moon_web/clue-fe-flutter.skill
      relation: output-from
      sections:
        - sourceRange:
            startLine: 1
            endLine: 103
          targetRange:
            startLine: 79
            endLine: 94
    - documentId: harness-planner-skill
      uri: ../SKILL.md
      relation: output-from
      sections:
        - sourceRange:
            startLine: 26
            endLine: 56
          targetRange:
            startLine: 27
            endLine: 78
  tags:
    - planner
    - fe-stack
    - flutter
    - pipeline
---

# FE Stack Detection — Planner Responsibility

Planner는 Sprint 1 착수 전 반드시 `fe_stack`을 확정하고 `pipeline.json`에 기록해야 한다.

## 1. 감지 순서 (자동)

```
1. .harness/actions/scan-result.json 의 tech_stack.fe_stack 읽기
2. 값이 "flutter" 또는 "react" 면 → 그대로 사용
3. 값이 없거나 "unknown" 이면 → 아래 추가 감지
```

### 추가 감지 (fallback)

| 시그널 | 판정 |
|--------|------|
| 루트 `pubspec.yaml` + `flutter:` 키 존재 | `flutter` |
| 하위 경로(예: `mobile/`, `apps/mobile/`, `clue_mobile_app/`)에 pubspec.yaml | `flutter` |
| `package.json` 에 `react`, `next`, `vite` 등 | `react` |
| `lib/` + `.dart` 파일 다수 | `flutter` |
| 둘 다 존재 (Flutter + Web 혼재) | **사용자 질문 필수** |

## 2. 사용자 질문 (불명확 시 단 한 번)

```
프론트엔드 스택을 확인합니다:

(A) React / Next.js / Vite 기반 Web
(B) Flutter (Dart, 모바일/데스크톱)

현재 감지된 시그널:
- pubspec.yaml: [있음/없음]
- package.json: [있음/없음]
- Next.js config: [있음/없음]

어떤 스택으로 진행하시겠습니까? (A/B)
```

혼재 프로젝트(Web + Flutter mobile)라면 사용자에게 **현 스프린트의 타깃**을 묻는다 — 파이프라인은 한 번에 하나의 `fe_stack`만 취급한다.

## 2.5 fe_target 확정 (Flutter 전용)

`fe_stack == "flutter"` 인 경우, **반드시** `fe_target` 도 함께 확정해야 한다 (`web` | `mobile` | `desktop`).
이는 Flutter Web vs Mobile/Desktop 에서 사용 가능한 API, 빌드 명령, evaluator 가 달라지기 때문이다.

### 자동 감지 (scan-result.json 의 `tech_stack.fe_target`)

| 시그널 | fe_target |
|--------|-----------|
| `<flutter_root>/web/index.html` 존재 | `web` |
| `<flutter_root>/android/` 또는 `ios/` 존재, web/ 없음 | `mobile` |
| `<flutter_root>/macos/`, `windows/`, `linux/` 존재 (mobile/web 없음) | `desktop` |
| 없음 | `unknown` |

### 사용자 질문 (불명확하거나 multi-target)

```
Flutter 프로젝트의 타깃을 확인합니다:

(A) Web — 브라우저 (Chrome/Safari/Firefox), 컴파일 결과는 HTML+JS+CSS
(B) Mobile — Android / iOS 네이티브 빌드
(C) Desktop — macOS / Windows / Linux 네이티브 빌드

감지된 시그널:
- web/index.html: [있음/없음]
- android|ios/: [있음/없음]
- macos|windows|linux/: [있음/없음]

이번 스프린트의 타깃은? (A/B/C)
```

### fe_target → Eval 흐름

| fe_target | Generator | Eval-Functional | Eval-Visual |
|-----------|-----------|----------------|-------------|
| `web` | `generator-frontend-flutter` | `evaluator-functional` (Playwright!) | `evaluator-visual` (Playwright!) |
| `mobile` | `generator-frontend-flutter` | `evaluator-functional-flutter` (정적 분석) | SKIP |
| `desktop` | `generator-frontend-flutter` | `evaluator-functional-flutter` (정적 분석) | SKIP |

**핵심**: Flutter Web 의 빌드 결과물(HTML/JS/CSS)은 일반 웹앱과 동일하므로 Playwright 기반
React 경로의 evaluator 를 그대로 재사용한다. Generator-Frontend-Flutter 의 Self-Verification
단계에서 `flutter analyze`/`flutter test`/`flutter build web` 정적 검증이 이미 통과한 상태로 handoff 된다.

## 3. pipeline.json 갱신

`fe_stack` + `fe_target` 확정 후 `pipeline.json`에 반드시 추가:

```json
{
  "pipeline": "FULLSTACK",
  "planner_mode": "full",
  "fe_stack": "flutter",
  "fe_target": "web",
  "agents_active": [
    "planner",
    "generator-backend",
    "generator-frontend-flutter",
    "evaluator-functional",
    "evaluator-visual"
  ],
  "agents_skipped": [
    "generator-frontend",
    "evaluator-functional-flutter"
  ],
  "evaluator_mode": "playwright-web",
  "notes": "Flutter Web — 컴파일 결과가 HTML+JS+CSS 이므로 React 경로의 Playwright evaluator 사용. Generator 의 Self-Verification 에서 flutter analyze/test 통과 전제."
}
```

### fe_stack + fe_target → 파이프라인 매핑

| pipeline | fe_stack | fe_target | agents_active 예시 |
|----------|----------|-----------|-------------------|
| FULLSTACK | react | (n/a) | planner, generator-backend, generator-frontend, evaluator-functional, evaluator-visual |
| FULLSTACK | flutter | **web** | planner, generator-backend, generator-frontend-flutter, evaluator-functional, evaluator-visual |
| FULLSTACK | flutter | mobile | planner, generator-backend, generator-frontend-flutter, evaluator-functional-flutter |
| FULLSTACK | flutter | desktop | planner, generator-backend, generator-frontend-flutter, evaluator-functional-flutter |
| FE-ONLY | react | (n/a) | planner, generator-frontend, evaluator-functional, evaluator-visual |
| FE-ONLY | flutter | **web** | planner, generator-frontend-flutter, evaluator-functional, evaluator-visual |
| FE-ONLY | flutter | mobile | planner, generator-frontend-flutter, evaluator-functional-flutter |
| BE-ONLY | (무관) | (n/a) | planner, generator-backend, evaluator-functional |

## 4. Flutter 선택 시 추가 작업

Flutter로 확정되면 Planner는:

1. **AGENTS.md IA-MAP** 의 `[FE]` 섹션을 Flutter 구조로 바꿔야 한다.
   - `apps/web/` → `lib/ui/pages/`, `lib/ui/component/`
   - `libs/shared-dto/` 대신 `integrated_data_layer/` 경로 등록
   - 소유자: `→ Generator-Frontend-Flutter`

2. **api-contract.json** 은 언어 중립적이어야 한다 — Planner는 TypeScript 타입이 아니라 **스키마 JSON** 으로만 작성. Flutter Generator가 Retrofit/JsonSerializable로 변환한다.

3. **feature-list.json** 의 `layer: "frontend"` feature들은 `fe_stack: "flutter"` 태그를 달아서 Evaluator가 구분하도록 한다.

## 5. 금지

- 파이프라인 실행 도중 `fe_stack` 변경 금지 — 스프린트 경계에서만 가능
- React/Flutter 코드 혼재 생성 금지 — Generator는 하나의 stack만 담당
- 사용자가 명시적으로 한 스택을 지시했는데 감지 결과로 다른 스택을 강제하지 말 것
