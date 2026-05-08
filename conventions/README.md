---
docmeta:
  id: conventions-readme
  title: Conventions — House Style Registry
  type: input
  createdAt: 2026-04-22T00:00:00Z
  updatedAt: 2026-04-22T00:00:00Z
  source:
    producer: user
    skillId: harness-dispatcher
  tags:
    - conventions
    - house-style
    - registry
---

# Conventions — House Style Registry

> 이 디렉토리는 프로젝트의 **긍정 규범(house style)** 을 누적 기록합니다.
> Gotcha(실수 기록) 가 사고 이후의 방어선이라면, Convention 은 합의된 원칙입니다.
> Dispatcher 가 사용자의 긍정 가이드("~해야 해", "~이렇게 해줘") 를 감지하면
> 해당 에이전트/스코프의 convention 파일에 `### [C-NNN]` 으로 append 합니다.

## 파일 구조

```
.harness/conventions/
├── README.md                        # 이 파일
├── shared.md                        # 모든 에이전트 공통 규범
│
├── conductor.md
├── dispatcher.md
├── meeting-manager.md
├── planner.md
├── cto.md
├── cqo.md
├── service-ops.md
│
├── coo-developer.md
├── documentationer.md
│
├── generator-backend.md
├── generator-frontend.md
├── generator-designer.md
├── generator-devops.md
│
├── evaluator-code-quality.md
├── evaluator-functional.md
├── evaluator-visual.md
├── evaluator-architecture.md
└── evaluator-security.md
```

루트의 `CONVENTIONS.md` 는 사용자가 자유롭게 기술하는 **최상위 원칙** 용도로
그대로 유지됩니다. 여기 `.harness/conventions/` 는 대화 중 Dispatcher 가
자동 누적하는 계층화된 하위 규범 저장소입니다.

## 읽기 순서 (모든 에이전트)

세션 시작 시 각 에이전트는 아래 순서로 적용합니다:

1. `CONVENTIONS.md` (루트, 최상위 원칙)
2. `.harness/conventions/shared.md` (공통)
3. `.harness/conventions/<self>.md` (자기 스코프)
4. `.harness/gotchas/<self>.md` (과거 실수 방어)
5. **(v6.2) parallel-tracks 형제 트랙 owner 의 gotcha** — `progress.json.conductor.tracks[]` 에서 자기 트랙이 아닌 형제 트랙의 owner 를 식별, 해당 owner 의 `gotchas/<owner>.md` 도 한 번 훑기. fork 회의에서 같은 결정으로 함께 출발한 부서의 가드를 무시하지 않기 위함.
6. `.harness/memory.md` (구조적 교훈)

**충돌 시 우선순위**: `<self>` > `shared` > 루트 `CONVENTIONS.md`.
형제 트랙 gotcha 는 **참고**용 — 자기 결정과 충돌 시 자기 스코프가 우선.

## 항목 형식

```markdown
### [C-NNN] 간결한 제목
- **Date**: YYYY-MM-DD
- **Scope**: <agent> | shared
- **Rule**: 규범 내용 (긍정형)
- **Rationale**: 왜 이렇게 하는가
- **Applies to**: 적용 대상 (에이전트·파일 경로 등)
- **Added from**: 출처 (사용자 프롬프트 / 마이그레이션 / 수동)
```

## 데이터 보존

- `npm install` postinstall 은 `### [C-NNN]` 엔트리가 있는 파일을 **절대 덮어쓰지 않습니다** (v5.6.0+).
- 스캐폴드 템플릿인 경우에만 갱신됩니다.
- 원본 백업: `.harness/archive/pre-harness-*.md.bak` (최초 설치 시 마이그레이션)

## 수동 편집

사용자가 직접 편집해도 됩니다. `### [C-NNN]` 형식만 지키면 Dispatcher 가 다음 자동 append 시 번호를 이어서 부여합니다.
