---
docmeta:
  id: ref-backend-laravel
  title: Backend Reference — Laravel + Livewire + Filament
  type: output
  createdAt: 2026-05-07T00:00:00Z
  updatedAt: 2026-05-07T00:00:00Z
  source:
    producer: agent
    skillId: harness-planner
  inputs:
    - documentId: agency-agents-engineering
      uri: https://github.com/msitarzewski/agency-agents
      relation: output-from
      note: filament-optimization-specialist · cms-developer · backend-architect · database-optimizer 흡수
      sections:
        - sourceRange: { startLine: 1, endLine: 1 }   # engineering-filament-optimization-specialist.md
          targetRange: { startLine: 28, endLine: 95 }
        - sourceRange: { startLine: 1, endLine: 1 }   # engineering-cms-developer.md
          targetRange: { startLine: 97, endLine: 140 }
        - sourceRange: { startLine: 1, endLine: 1 }   # engineering-backend-architect.md
          targetRange: { startLine: 142, endLine: 175 }
        - sourceRange: { startLine: 1, endLine: 1 }   # engineering-database-optimizer.md
          targetRange: { startLine: 177, endLine: 210 }
  tags: [ref, backend, laravel, livewire, filament, phase-b]
---

<!--
Source: https://github.com/msitarzewski/agency-agents (MIT)
재해석 출처:
- engineering/engineering-filament-optimization-specialist.md
- engineering/engineering-cms-developer.md
- engineering/engineering-backend-architect.md
- engineering/engineering-database-optimizer.md
-->

# Backend Reference — Laravel + Livewire + Filament

> Adaptive ref-doc. Generator-Backend가 Laravel 스택일 때 우선 참조.
> Eval-Architecture / Eval-Security 검증 기준의 일부.

## 1. 프로젝트 구조 (Laravel 11+)

```
app/
├── Models/                  # Eloquent 모델
├── Http/
│   ├── Controllers/         # API 컨트롤러 (얇게)
│   ├── Requests/            # FormRequest 검증
│   ├── Resources/           # API Resource (응답 직렬화)
│   └── Middleware/
├── Services/                # 도메인 서비스 (비즈니스 로직)
├── Actions/                 # 단일 책임 액션 (Lorisleiva/Actions 패턴)
├── Repositories/            # 데이터 접근 (선택, 복잡한 쿼리만)
├── Filament/
│   ├── Resources/           # Filament 리소스
│   ├── Pages/
│   └── Widgets/
├── Livewire/                # Livewire 컴포넌트 (full-page or partial)
├── Jobs/                    # 큐 잡
├── Events/, Listeners/      # 이벤트
└── Policies/                # 권한 (Gate)
```

## 2. 컨트롤러는 얇게 (Skinny Controller)

- 컨트롤러는 5 라인 룰: validate → call action/service → return resource
- 비즈니스 로직은 `Services/` 또는 `Actions/`
- 검증은 항상 `FormRequest` 클래스 (인라인 `$request->validate` 금지)

## 3. Eloquent 룰

- N+1 방지: 모든 list 응답은 `with()` eager load 명시. Eval-Architecture가 검출.
- `whereHas` 최소화 → 복잡 시 `select` + subquery 또는 raw 명시
- 대량 처리 → `chunk()` / `cursor()` / `lazy()`
- 모델 이벤트(observer) 남용 금지 → 명시적 Action/Service 선호
- `$fillable` 또는 `$guarded` 둘 중 하나 일관 (프로젝트 단위 통일)

## 4. Livewire 베스트 프랙티스

- Volt 단일 파일 컴포넌트는 prototype 단계만, 운영 진입 전 클래스 컴포넌트로 분리
- `wire:model.live` 남용 금지 → debounce 또는 lazy
- 컴포넌트 prop은 primitive 우선, Eloquent 모델 직렬화는 `serializeable=true` 명시
- `dispatch()` 이벤트 이름은 dot-namespaced (`order.created`)
- a11y: Livewire 업데이트 시 포커스 보존(`@this` + `wire:loading.focus`)

## 5. Filament 룰

`engineering-filament-optimization-specialist` 핵심 패턴:

### 5.1 Resource 정의
- 한 모델당 한 Resource. 엔드포인트는 Filament Panel 라우트로만 노출.
- `eagerLoad()` 명시 → 인덱스/디테일에서 N+1 방지
- 큰 테이블은 `defaultSort()` + 인덱스 일치 필수

### 5.2 Form 빌드
- `Schema::make()` 컴포넌트는 reusable trait/method로 추출
- `relationship()` 호출은 select preload 옵션 검토 (메모리 vs 쿼리 트레이드오프)
- File upload는 디스크 명시 + visibility 명시 (`s3-private` 등)

### 5.3 Table 최적화
- `searchable()` 컬럼은 DB 인덱스 필수
- `getEloquentQuery()` 오버라이드 시 권한 scope 잊지 말 것 (Tenancy)
- `recordUrl(null)` + 모달 액션이 row 클릭보다 가벼움

### 5.4 Tenancy / Authorization
- Filament Tenancy 적용 시 panel별 `tenant()` 메서드 일관
- Policy 누락된 액션 자동 거부 (`shouldRegisterNavigation`)
- Eval-Security가 panel별 권한 매트릭스 검증

## 6. Queue / Jobs

- 잡은 idempotent 설계. retry 시 부작용 없도록.
- `ShouldBeUnique` 활용으로 중복 방지
- 실패 시 `failed_jobs` 모니터링 + Service-Ops 알림 endpoint
- 대용량은 batch (`Bus::batch()`)

## 7. 인증·권한

- API: Sanctum 토큰 또는 Passport (선택)
- 세션: Cookie + CSRF 활성
- 권한: Policy 우선, Gate는 단일 액션에만
- 다중 가드: `auth:web,api` 명시
- MFA·SSO 도입 시: Eval-Security cross-validation

## 8. 데이터베이스 (Eval-Architecture와 공유)

- 마이그레이션은 양방향(`up` + `down`) 모두 작성, DevOps의 rollback runbook과 연동
- 인덱스는 마이그레이션 동시 작성, 별도 PR 금지
- Foreign key 제약 명시 + `onDelete('cascade'|'restrict')` 의도 표기
- `decimal()` 화폐 컬럼, JSON 컬럼은 가상 컬럼·인덱스 검토
- Soft delete는 명시적 도메인 요구일 때만 (default 사용 X)

## 9. 캐시·세션

- Cache tag 미지원 드라이버(file/database) 주의 → tag 사용 시 redis/memcached 강제
- 세션 드라이버 prod에서 file 금지(클러스터 환경 비호환)
- Cache invalidation 룰: 모델 이벤트 + 명시적 invalidate command

## 10. 관찰성 (Service-Ops 공급)

- 로그: `Log::withContext()` 로 request_id·user_id 첨부
- 메트릭: `prometheus-laravel` 또는 statsd exporter
- 에러: Sentry/Bugsnag SDK + release 태그 (DevOps와 연결)
- 성능: Telescope는 dev/staging만, prod 비활성

## 11. 테스트

- Feature 테스트 우선, Unit은 도메인 로직(Service/Action)만
- DB: `RefreshDatabase` + sqlite-memory (CI 가속) 또는 mysql 컨테이너
- Livewire: `Livewire::test()` actions/assertions
- Filament: `Filament\Tests` helper (panel mount 테스트)
- HTTP: `actingAs()` + 권한 시나리오 매트릭스

## 12. 흔한 안티패턴 (Eval-Architecture 자동 검출 후보)

| 안티패턴 | 검출 룰 | Severity |
|---|---|---|
| Controller에 비즈니스 로직 | 컨트롤러 메서드 > 30 라인 | High |
| N+1 in Filament Resource | eagerLoad() 누락 + relation render | High |
| Mass assignment 누락 | `$fillable`·`$guarded` 미설정 | Critical |
| Policy 누락 | API 라우트에 `can:` 미들웨어 X | Critical |
| Migration 부재 마이그레이션 컬럼 add | 마이그레이션 PR과 컬럼 사용 PR 분리 | Medium |
| Eloquent observer chain | observer 안에서 또 다른 모델 save | High |
| Cache::tags on file driver | 드라이버 검증 없는 tag 호출 | Medium |
| Job non-idempotent | retry 시 중복 외부 호출 | High |

## 13. 출처 (Attribution)

agency-agents (MIT) 흡수:
- `engineering-filament-optimization-specialist` (Section 5)
- `engineering-cms-developer` (Section 1, 4, 11)
- `engineering-backend-architect` (Section 2, 7, 12)
- `engineering-database-optimizer` (Section 3, 8, 12)
