---
docmeta:
  id: riverpod-pattern
  title: Riverpod 상태관리 패턴 (Page + VM)
  type: output
  createdAt: 2026-04-09T00:00:00Z
  updatedAt: 2026-04-09T00:00:00Z
  source:
    producer: agent
    skillId: harness-generator-frontend-flutter
  inputs:
    - documentId: clue-fe-flutter-riverpod
      uri: ../../../../../moon_web/clue-fe-flutter.skill
      relation: output-from
      sections:
        - sourceRange:
            startLine: 1
            endLine: 149
          targetRange:
            startLine: 32
            endLine: 180
  tags:
    - flutter
    - riverpod
    - state-management
    - notifier-provider
---

# Riverpod 상태관리 패턴 (Page + VM)

## 기본 구조: Page + VM 쌍

모든 화면은 `xxx_page.dart` + `xxx_page_vm.dart` 쌍으로 구성.
이는 테스트 가능성과 UI/로직 분리를 위한 강제 규약.

### VM (ViewModel)

```dart
// example_page_vm.dart
import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:integrated_data_layer/data_layer.dart';

final pExampleProvider =
    NotifierProvider<ExampleNotifier, ExampleState>(ExampleNotifier.new);

class ExampleNotifier extends Notifier<ExampleState> {
  @override
  ExampleState build() {
    return const ExampleState();
  }

  Future<void> loadData() async {
    state = state.copyWith(isLoading: true);
    try {
      final result = await ref.read(dataLayer).ac.getExample(exampleId: 1);
      if (result.code == 200) {
        state = state.copyWith(
          isLoading: false,
          data: result.data,
        );
      } else {
        state = state.copyWith(
          isLoading: false,
          error: 'code=${result.code}',
        );
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }
}

class ExampleState extends Equatable {
  final bool isLoading;
  final dynamic data;
  final String? error;

  const ExampleState({
    this.isLoading = false,
    this.data,
    this.error,
  });

  ExampleState copyWith({
    bool? isLoading,
    dynamic data,
    String? error,
  }) {
    return ExampleState(
      isLoading: isLoading ?? this.isLoading,
      data: data ?? this.data,
      error: error ?? this.error,
    );
  }

  @override
  List<Object?> get props => [isLoading, data, error];
}
```

### Page

```dart
// example_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'example_page_vm.dart';

class ExamplePage extends ConsumerStatefulWidget {
  const ExamplePage({super.key});

  @override
  ConsumerState<ExamplePage> createState() => _ExamplePageState();
}

class _ExamplePageState extends ConsumerState<ExamplePage> {
  @override
  void initState() {
    super.initState();
    // 초기 데이터 로드는 addPostFrameCallback 으로
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(pExampleProvider.notifier).loadData();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(pExampleProvider);  // watch로 상태 구독

    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null) {
      return Center(child: Text(state.error!));
    }
    // ... 정상 상태 렌더링
    return const SizedBox.shrink();
  }
}
```

## Family 패턴 (다중 자식 컴포넌트)

리스트 아이템처럼 동일 타입 인스턴스가 여러 개 필요할 때:

```dart
// relay_tile_vm.dart
final pRelayItemProvider = NotifierProvider.family<
    RelayItemNotifier,
    RelayItemState,
    ({int ioId, String topic})>(
  () => RelayItemNotifier(),
);

class RelayItemNotifier
    extends FamilyNotifier<RelayItemState, ({int ioId, String topic})> {
  @override
  RelayItemState build(({int ioId, String topic}) arg) {
    ref.onDispose(() {
      // 정리 로직 (스트림 구독 해제 등)
    });
    return RelayItemState(ioId: arg.ioId, topic: arg.topic);
  }

  Future<void> doAction() async {
    final result = await ref.read(dataLayer).ac.someMethod(id: state.ioId);
    state = state.copyWith(/* ... */);
  }
}
```

사용:
```dart
// Page/Widget에서
final itemState = ref.watch(
  pRelayItemProvider((ioId: item.ioId, topic: item.topic)),
);
```

## 핵심 규칙

| 규칙 | 설명 |
|------|------|
| `ref.watch` | UI rebuild이 필요한 곳 (build 메서드 내) |
| `ref.read` | 일회성 호출 (이벤트 핸들러, initState 콜백) |
| `dataLayer` 접근 | VM 내에서 `ref.read(dataLayer).repository.method()` |
| State 불변성 | Equatable 상속 + copyWith 패턴 |
| Provider 네이밍 | `p` 접두사 + PascalCase + Provider (예: `pHomePageProvider`) |
| 초기 로드 | `addPostFrameCallback` 으로 첫 프레임 이후 호출 |
| 에러/로딩 | State에 `isLoading`, `error` 필수 포함 (UI 3가지 상태 처리) |

## 금지

- `bridges/` 사용 금지 — BLOC 기반 레거시
- StatefulWidget 내 직접 API 호출 — 반드시 VM 경유
- `setState` 로 API 응답 상태 관리 — Riverpod 상태로 대체
- `ref.read`를 build 메서드 내에서 사용 (→ `ref.watch`)
- VM 내 UI 의존 코드 (Navigator, ScaffoldMessenger 등) — UI 콜백으로 분리
