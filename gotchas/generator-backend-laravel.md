---
docmeta:
  id: gotchas-generator-backend-laravel
  title: Generator-Backend Gotchas — Laravel/Livewire/Filament
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
      sections:
        - sourceRange: { startLine: 1, endLine: 1 }
          targetRange: { startLine: 1, endLine: 999 }
  tags: [gotcha, generator-backend, laravel, livewire, filament, phase-b]
---

<!-- Source: https://github.com/msitarzewski/agency-agents (MIT) -->

# Generator-Backend Gotchas — Laravel/Livewire/Filament

> 스택별 가드. 공통 가드는 `gotchas/generator-backend.md` 참조.
> 모든 항목은 `unverified` 상태로 시작, Planner 리뷰 후 `verified` 승격.

## verified

(없음 — 첫 리비전)

## unverified

### G-LV-001 — Livewire 컴포넌트가 Eloquent 모델을 prop으로 받을 때 직렬화 충돌
- **언제**: 부모 컴포넌트 → 자식 컴포넌트로 모델을 직접 props 전달
- **증상**: 새 요청마다 모델 hydrate 실패, lazy load 시 fresh 로드되어 데이터 불일치
- **회피**: ID만 전달 + 자식이 자기 책임으로 fetch, 또는 `serializeable=true` 명시 + 변경 위험 인지

### G-LV-002 — `wire:model.live` 무차별 사용으로 N+1 트래픽 폭발
- **증상**: 입력 1자마다 서버 왕복, 운영에서 큐 폭주
- **회피**: 폼 입력 default `wire:model.live.debounce.500ms` 또는 `wire:model.lazy`

### G-FL-001 — Filament Resource `eagerLoad()` 누락
- **증상**: 인덱스 페이지 1회 로드에 컬럼 수 × 행 수 만큼 쿼리 (N+1)
- **회피**: Resource에 `protected $eagerLoadRelations = ['user', 'category']` 명시. Eval-Architecture가 검출.

### G-FL-002 — Filament Tenancy panel에서 Global scope 누락
- **증상**: 한 테넌트 사용자가 다른 테넌트 데이터 노출
- **회피**: `getEloquentQuery()` 오버라이드 시 `parent::getEloquentQuery()` 후 scope 추가. Eval-Security 적발.

### G-EL-001 — `whereHas` 다단 사용으로 인덱스 미사용 쿼리
- **증상**: relation 깊이 ≥ 2 + 결과 set 크면 secs 단위
- **회피**: subquery 또는 `whereIn(select 1 column)` 패턴, EXPLAIN 첨부

### G-EL-002 — Mass assignment 누락 → 권한 우회
- **증상**: 사용자가 `is_admin` 같은 컬럼을 요청 본문에 끼워 권한 상승
- **회피**: 모든 모델 `$fillable` 또는 `$guarded = []` 의도 명시. Eval-Security CRITICAL.

### G-MIG-001 — 인덱스 없는 외래키 컬럼
- **증상**: parent delete 시 child scan 풀스캔
- **회피**: 마이그레이션에서 `foreignId(...)->index()` 명시

### G-JOB-001 — Job 안에서 retry 비대응 외부 호출
- **증상**: Stripe·외부 API 호출이 retry 시 중복 결제·중복 메시지
- **회피**: idempotency_key 또는 `ShouldBeUnique`. Eval-Security 검토.

### G-CACHE-001 — `Cache::tags()` on file driver
- **증상**: 운영에서 silent fail (tag 무시)
- **회피**: prod cache driver는 redis 강제. config/cache.php boot 시 검증.

### G-AUTH-001 — Sanctum 토큰 회전 정책 부재
- **증상**: 토큰 영구 유효 → 누출 시 영향 무한대
- **회피**: TTL + 사용 흐름별 ability 분리, 회전 명령 정의 (DevOps와 연계)

### G-OBS-001 — observer chain → 부작용 폭발
- **증상**: User saving → Profile observer → Account observer → 무한 루프 또는 dead-lock
- **회피**: observer 안에서 다른 모델 save 금지 룰. 명시적 Action 호출로 대체.

### G-FORM-001 — `$request->validate()` 인라인 사용
- **증상**: 검증 룰 재사용·테스트·문서화 모두 어려움
- **회피**: FormRequest 클래스 강제. Eval-CodeQuality lint 룰.

### G-PERF-001 — Telescope prod 활성
- **증상**: 모든 쿼리·요청 적재 → DB 비대 + 보안 노출
- **회피**: env 분리, prod에서 `TelescopeServiceProvider` 등록 차단. Eval-Security 적발.
