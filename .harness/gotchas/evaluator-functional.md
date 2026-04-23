---
docmeta:
  id: gotchas-evaluator-functional
  title: Gotchas — Evaluator-Functional
  type: input
  createdAt: 2026-04-22T00:00:00Z
  updatedAt: 2026-04-22T00:00:00Z
  source:
    producer: agent
    skillId: harness-dispatcher
  inputs: []
  tags: [gotchas, evaluator-functional]
---

# Gotchas — Evaluator-Functional

> Dispatcher가 관리. Evaluator-Functional은 세션 시작 시 이 파일을 읽고 같은 실수를 반복하지 않습니다.

<!-- 항목이 추가되면 아래에 기록됩니다 -->

### [G-001] CONVENTIONS.md UI Automation Smoke Test 절차를 무시하고 widget test 만으로 PASS 판정
- **Date**: 2026-04-22
- **Status**: unverified
- **TTL**: 2026-05-22
- **Trigger**: "CONVENTIONS.md 에 FE Evaluator 는 debug APK 빌드 + adb + uiautomator + screencap + logcat 으로 검증하라고 명시돼 있는데 왜 flutter_test 만 돌리고 PASS 했냐"
- **Wrong**: Team Worker 가 spawn 한 내부 Evaluator Agent 가 plain Agent 로 실행되어 SKILL.md Startup 체크리스트 (CONVENTIONS.md 읽기 포함) 가 자동 주입되지 않았고, widget test 통과만으로 VERDICT=PASS 를 반환.
- **Right**: 평가 시작 전 Lead 가 주입한 **`{PREFLIGHT_BUNDLE}`** (루트 CONVENTIONS.md 포함) 을 먼저 요약 출력하고, CONVENTIONS.md 의 "Mandatory" 절차 (FE UI Automator 스모크) 를 실제 실기기/에뮬레이터 대상으로 수행한 증거 (adb 로그, screencap 경로, uiautomator dump, logcat tail) 를 EVIDENCE 에 첨부해야 PASS 판정 가능.
- **Why**: widget test 는 Flutter 레이어 내부 위젯만 검증 — 실기기에서의 네이티브 렌더링/권한/플러그인/딥링크 이슈를 전혀 못 잡는다. CONVENTIONS.md 가 이 구멍을 막기 위해 UI Automator 스모크를 의무화한 것.
- **Scope**: 모든 Evaluator-Functional 세션 (Team Worker 내부 호출 포함). 특히 Flutter/React Native/네이티브 앱 대상 피처.
- **Occurrences**: 1
