---
docmeta:
  id: api-layer-pattern
  title: API Layer Pattern (integrated_data_layer)
  type: output
  createdAt: 2026-04-09T00:00:00Z
  updatedAt: 2026-04-09T00:00:00Z
  source:
    producer: agent
    skillId: harness-generator-frontend-flutter
  inputs:
    - documentId: clue-fe-flutter-api-layer
      uri: ../../../../../moon_web/clue-fe-flutter.skill
      relation: output-from
      sections:
        - sourceRange:
            startLine: 1
            endLine: 187
          targetRange:
            startLine: 32
            endLine: 205
  tags:
    - flutter
    - retrofit
    - json-serializable
    - integrated-data-layer
---

# API Layer Pattern (integrated_data_layer)

하네스 Flutter Generator는 `api-contract.json` 을 **Source of Truth** 로 삼아
`integrated_data_layer` 하위에 Dart 타입을 1:1 생성한다.

## 디렉토리 구조

```
integrated_data_layer/
├── lib/
│   ├── 1_repositories/              # Repository (비즈니스 로직 래퍼)
│   │   ├── ac_repository.dart
│   │   ├── visitor_repository.dart
│   │   ├── s3_repository.dart
│   │   ├── oauth_repository.dart
│   │   └── reservation_repository.dart
│   ├── 2_data_sources/
│   │   ├── remote/
│   │   │   ├── rest_api.dart           # 모든 Retrofit 엔드포인트
│   │   │   ├── rest_provider.dart      # Dio/RestClient Provider
│   │   │   ├── request/body/           # Request Body 클래스
│   │   │   └── response/
│   │   │       └── abstract/          # 베이스 응답 (ClueResponseImpl 등)
│   │   └── local/
│   └── 3_others/
│       ├── enum/
│       └── extension/
├── test/                               # lib/ 미러 구조
│   ├── 1_repositories/
│   ├── 2_data_sources/remote/request/body/
│   └── 2_data_sources/remote/response/
└── data_layer.dart                     # 진입점 (dataLayer Provider)
```

## 1. api-contract.json → Request Body 변환

api-contract.json의 요청 스키마를 `@JsonSerializable(includeIfNull: false)`
클래스로 1:1 매핑한다. **필수 지시가 없으면 모든 필드 Nullable.**

```dart
// lib/2_data_sources/remote/request/body/example_body.dart
import 'package:json_annotation/json_annotation.dart';

part 'example_body.g.dart';

@JsonSerializable(includeIfNull: false)  // ★ 필수
class ExampleBody {
  final String? name;       // ★ Nullable 기본
  final int? placeId;
  final String? description;

  const ExampleBody({
    this.name,
    this.placeId,
    this.description,
  });

  factory ExampleBody.fromJson(Map<String, dynamic> json) =>
      _$ExampleBodyFromJson(json);
  Map<String, dynamic> toJson() => _$ExampleBodyToJson(this);
}
```

## 2. Response 변환

응답 베이스 클래스 계층:
- `ClueResponseImpl<T>` — 단일 데이터 (code, data, errors)
- `ClueResponseListImpl<T>` — 목록 (code, data, errors, totalCount)
- `VisitorResponseImpl<T>` — Visitor 서버 전용

```dart
// lib/2_data_sources/remote/response/example_response.dart
import 'package:integrated_data_layer/2_data_sources/remote/response/abstract/clue/clue_response_impl.dart';
import 'package:json_annotation/json_annotation.dart';

part 'example_response.g.dart';

@JsonSerializable(explicitToJson: true)
class ExampleResponse extends ClueResponseImpl<ExampleResponseData> {
  const ExampleResponse({
    required super.code,
    required super.data,
    required super.errors,
  });

  factory ExampleResponse.fromJson(Map<String, dynamic> json) =>
      _$ExampleResponseFromJson(json);
  Map<String, dynamic> toJson() => _$ExampleResponseToJson(this);
}

@JsonSerializable(explicitToJson: true)
class ExampleResponseData {
  final int? id;          // ★ Nullable 기본
  final String? name;

  const ExampleResponseData({this.id, this.name});

  factory ExampleResponseData.fromJson(Map<String, dynamic> json) =>
      _$ExampleResponseDataFromJson(json);
  Map<String, dynamic> toJson() => _$ExampleResponseDataToJson(this);
}
```

**기존 응답 재사용 원칙**: api-contract.json 의 서로 다른 엔드포인트가
동일한 응답 구조를 가지면 새 Response 클래스를 만들지 않는다.

## 3. rest_api.dart 엔드포인트 추가

```dart
// rest_api.dart 내부 — RestClient 클래스에 추가
@GET("/examples/{exampleId}")
Future<ExampleResponse> getExample(
  @Path("exampleId") int exampleId,
);

@POST("/examples")
Future<ExampleResponse> createExample(
  @Body() ExampleBody requestBody,
);

@PUT("/examples/{exampleId}")
Future<ExampleResponse> updateExample(
  @Path("exampleId") int exampleId,
  @Body() ExampleBody requestBody,
);

@DELETE("/examples/{exampleId}")
Future<ClueDefaultResponse> deleteExample(
  @Path("exampleId") int exampleId,
);
```

api-contract.json의 path, method, param 위치를 **그대로** 옮긴다.
경로 변수 추가/제거 금지 — 계약이 Source of Truth.

## 4. Repository 래퍼 추가

```dart
// 1_repositories/ac_repository.dart 내부에 메서드 추가
Future<ExampleResponse> getExample({required int exampleId}) {
  return _restClient.getExample(exampleId);
}
```

Repository는 **순수 래퍼** — 비즈니스 로직 없이 Retrofit 호출을 전달만 한다.
도메인 분기, 에러 매핑은 VM 계층에서 수행.

## 5. 호출 패턴 (VM에서)

```dart
// VM 내부
final result = await ref.read(dataLayer).ac.getExample(exampleId: 123);
if (result.code == 200) {
  // 성공 처리
}
```

## 6. TC 작성 (필수)

**모든 Request Body, Response에 왕복 테스트 필수.**
Evaluator가 test 디렉토리를 점검한다.

```dart
// test/2_data_sources/remote/request/body/example_body_test.dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:integrated_data_layer/2_data_sources/remote/request/body/example_body.dart';

void main() {
  group("example body test", () {
    test("/fromJson & toJson", () {
      ExampleBody body1 = const ExampleBody(
        name: 'test',
        placeId: 1,
      );

      ExampleBody body2 = ExampleBody.fromJson(body1.toJson());

      expect(body1.name, 'test');
      expect(body1.placeId, 1);

      var body1Data = jsonEncode(body1.toJson());
      var body2Data = jsonEncode(body2.toJson());
      expect(body1Data == body2Data, true);
    });

    test("/null fields excluded", () {
      ExampleBody body = const ExampleBody(name: 'test');
      var json = body.toJson();
      expect(json.containsKey('placeId'), false);  // includeIfNull: false 검증
    });
  });
}
```

## 7. 코드 생성

모든 Request/Response 파일 추가/수정 후 **반드시** 실행:

```bash
cd <integrated_data_layer 경로>
flutter pub run build_runner build --delete-conflicting-outputs
```

생성된 `*.g.dart` 파일은 커밋한다 (CI에서 재생성하지 않음).
