---
docmeta:
  id: AGENTS
  title: Project Context for AI Agents (walwal-harness)
  type: input
  createdAt: 2026-04-09T00:00:00Z
  updatedAt: 2026-05-11T00:00:00Z
  source:
    producer: user
  tags: [project-context, v7, harness, npm-package, claude, codex]
---

# AGENTS.md — Walwal Harness v7

이 저장소는 **하네스를 사용하는 프로젝트가 아니라, 하네스를 설치하는 npm 패키지**다.

v7의 핵심 전제:

- 이 저장소 루트에 프로젝트 런타임 `.harness/`를 만들지 않는다.
- 사용자는 이 패키지를 npm으로 설치한 뒤 대상 프로젝트에서 `walwal-harness init`을 실행한다.
- `init`은 대상 프로젝트에 `.harness/` 런타임 상태 저장소를 만들고, `.claude/`와 `.codex/`에 command, agent, skill 진입점을 설치한다.
- Claude와 Codex 양쪽에서 같은 company/harness 구조를 사용할 수 있어야 한다.

## Project

- **Name**: `@walwal-harness/cli`
- **Branch**: `v7.0`
- **Purpose**: Claude/Codex용 company-style AI agent harness 설치 패키지
- **Runtime Target**: 패키지 저장소가 아니라, 사용자가 초기화하는 외부 프로젝트

## v7 Command Rule

slash command는 **Owner-facing entrypoint**다. Agent나 Skill이 slash command를 내부 호출할 수 없으므로 command를 내부 부서 호출 수단으로 설계하면 안 된다.

허용 command는 2개다.

| Command | 역할 |
|---|---|
| `/goal` | 목표 설정, 목표 수정, 목표 추가 |
| `/hot-fix` | 현재 goal과 독립된 긴급 수정 |

금지:

- `/ceo`, `/coo`, `/cdo`, `/cto`, `/cqo`, `/ops`를 command로 만들지 않는다.
- `/hiring`, `/resource-manager`, `/brick-office`를 command로 만들지 않는다.
- command를 CXX 간 내부 호출 수단으로 사용하지 않는다.

내부 호출은 agent/skill wiring으로 처리한다.

## Company Structure

Owner는 `/goal` 또는 `/hot-fix`로만 회사를 호출한다. 이후 회사 내부 흐름은 CXX agent와 hired worker skill들이 처리한다.

```
Owner
  └─ /goal 또는 /hot-fix
      └─ CEO agent
          ├─ COO agent  — 기획, 리서치, 가설, 백테스트, 서비스 방향
          ├─ CDO agent  — 브랜딩, UI/UX, 디자인 리뷰
          ├─ CTO agent  — 아키텍처, API, 플랫폼, 구현 총괄
          ├─ CQO agent  — 품질, 회귀, archive, 재발 방지
          └─ OPS agent  — archive 버전 운영, 로그 분석, 긴급 이벤트
```

### Required CXX Agents

CXX 레벨은 npm 설치 시 `.claude/skills/`와 `.codex/skills/`에 미리 존재해야 한다.

- `harness-ceo`
- `harness-coo`
- `harness-cdo`
- `harness-cto`
- `harness-cqo`
- `harness-ops`

보조 내부 agent/skill:

- `harness-hiring`
- `harness-resource-manager`
- `harness-brick-office`

규칙:

- CXX가 전문 worker에게 일을 맡길 때, 해당 worker가 등록되어 있지 않으면 default AI engine으로 대체하지 않는다.
- 먼저 `harness-hiring`으로 HR-Resource에서 채용하고, `harness-resource-manager`로 invocation wording을 wiring한다.
- CXX와 worker는 자기편향을 줄이기 위해 항상 새로운 세션 컨텍스트에서 시작하는 것을 전제로 한다.

## HR-Resource

`HR-Resource/`는 채용 후보 풀이다.

- 원본: `/Users/ted/Downloads/agency-agents-main`
- 변환 형태: `HR-Resource/{skill-name}/SKILL.md`
- 변환 스크립트: `scripts/import-agency-agents.js`
- 패키지 설치 시 대상 프로젝트의 `.harness/shared/HR-Resource/`로 복사된다.

`HR-Resource`의 모든 worker는 직접 실행되는 부서장이 아니라, CXX가 필요할 때 고용하는 전문 직원이다.

## Runtime State

대상 프로젝트에서 `walwal-harness init`을 실행하면 `.harness/`가 생성된다. `.harness/`는 불필요한 것이 아니며, 하네스 본연의 상태 저장소다.

필수 런타임 영역:

| Path | 역할 |
|---|---|
| `.harness/conventions/` | 반복적으로 지켜야 할 규칙 |
| `.harness/gotchas/` | 재발 방지용 실패/주의 기록 |
| `.harness/memories/` | 장기 공유 기억 |
| `.harness/shared/` | HR roster, resource index, 공용 상태 |
| `.harness/documents/{mission_name}/` | goal/hot-fix별 CXX 발언과 결정 기록 |
| `.harness/archive/` | CQO 승인 후 archive |
| `.harness/logs/YYYY-MM-DD/` | OPS 일 단위 로그 |

문서 비대화를 막기 위해 mission 기록은 아래 형태를 따른다.

```
.harness/documents/{mission_name}/ceo.md
.harness/documents/{mission_name}/coo.md
.harness/documents/{mission_name}/cdo.md
.harness/documents/{mission_name}/cto.md
.harness/documents/{mission_name}/cqo.md
.harness/documents/{mission_name}/ops.md
.harness/documents/{mission_name}/workers/{worker-name}.md
```

## IA-MAP

```
/
├── bin/
│   └── init.js                         # npm CLI initializer
├── commands/
│   ├── goal.md                         # Owner-facing command
│   └── hot-fix.md                      # Owner-facing command
├── HR-Resource/
│   └── {skill-name}/SKILL.md           # hireable worker pool and core CXX skills
├── scripts/
│   ├── import-agency-agents.js         # agency-agents -> HR-Resource converter
│   └── *.sh                            # runtime helper scripts copied by init
├── conventions/                        # bundled convention templates
├── gotchas/                            # bundled gotcha templates
├── assets/templates/                   # runtime scaffold templates
├── package.json                        # npm package manifest
└── AGENTS.md                           # this repository context
```

이 저장소의 `.harness/`는 런타임 산출물이므로 커밋하지 않는다.

## Install Contract

`bin/init.js`는 대상 프로젝트에서 다음을 수행해야 한다.

1. `.harness/` 런타임 저장소 생성
2. `.harness/shared/HR-Resource/`에 채용 후보 풀 복사
3. `.claude/commands/`와 `.codex/commands/`에 `/goal`, `/hot-fix`만 설치
4. `.claude/skills/`와 `.codex/skills/`에 CXX 및 core harness skills 설치
5. 기존에 잘못 설치된 `/ceo`, `/coo`, `/cdo`, `/cto`, `/cqo`, `/ops`, `/hiring`, `/resource-manager`, `/brick-office` command 제거
6. 필요한 runtime templates, hooks, scripts 설치

`postinstall`에서 자동으로 대상 프로젝트를 초기화하지 않는다. 초기화는 명시적인 `walwal-harness init`으로만 한다.

## Mission Flow

### Goal

1. Owner가 `/goal`로 목표를 제출한다.
2. CEO가 brainstorming 필요 여부와 즉시 수행 가능 여부를 판단한다.
3. CEO가 CXX에게 goal 달성을 위한 질문을 던진다.
4. 각 CXX는 필요한 worker가 있는지 확인한다.
5. worker가 없으면 `harness-hiring`을 먼저 사용한다.
6. CXX 산출물은 `.harness/documents/{mission_name}/{cxx}.md`에 기록한다.
7. CEO가 결과를 조정하고 다음 CXX 또는 Owner 보고로 라우팅한다.

### Hot Fix

1. Owner가 `/hot-fix`로 긴급 수정 요청을 제출한다.
2. CEO가 CTO/CQO를 우선 소집한다.
3. CTO는 최소 수정 경로를 설계하고 hired worker에게 구현을 맡긴다.
4. CQO는 회귀 검증과 재발 방지책을 강제한다.
5. 수정에서 얻은 교훈은 `.harness/conventions/`, `.harness/gotchas/`, `.harness/memories/`에 등록한다.

## Meetings and Events

- 매일 11:59에 CEO는 CXX 일간 미팅을 진행하는 구조를 전제로 한다.
- CXX는 하위 worker workflow가 완료되면 event를 CEO에게 전달한다.
- CEO는 event 성격에 따라 관련 CXX를 소집하고 다음 진행을 지시한다.
- OPS 긴급 이벤트는 CEO/CTO/CQO를 소집한다.

## OPS Logging

Archive된 결과물을 서비스로 운영할 때 로그는 일 단위로 분리한다.

```
.harness/logs/YYYY-MM-DD/
```

Good case 성공 로그는 선택적이다. Good case가 아닌 모든 예외는 기록한다.

예:

- 잔고 부족으로 체결 실패
- 필수 파라미터 누락
- API 문서와 다른 request/response
- 서비스 crash
- 외부 API 장애
- backend/frontend/platform 원인 미분류 예외

## DDD Rule

모든 Command, Agent, Skill, SubAgent는 DDD 기반 작업을 따른다.

- domain 결정과 application wiring을 구분한다.
- infrastructure와 interface 세부사항을 domain 규칙으로 오염시키지 않는다.
- CXX는 책임 경계를 명확히 하고, worker는 자기 전문 범위 안에서만 산출물을 낸다.

## Editing Rules

- `AGENTS.md`는 Owner 요청 또는 명시적 승인 없이 수정하지 않는다.
- 이 저장소에 프로젝트 런타임 `.harness/`를 생성하거나 커밋하지 않는다.
- command는 2개 원칙을 깨지 않는다.
- CXX를 command로 추가하지 않는다.
- HR-Resource 변환은 `scripts/import-agency-agents.js`를 사용한다.
- 기존 사용자 변경을 되돌리지 않는다.

## Verification

변경 후 기본 검증:

```bash
node --check bin/init.js
node --check scripts/import-agency-agents.js
npm pack --dry-run --cache /private/tmp/walwal-npm-cache
```

init 동작 검증은 임시 프로젝트에서 수행한다.

```bash
mkdir -p /private/tmp/walwal-v7-init-test
cd /private/tmp/walwal-v7-init-test
node /path/to/walwal-harness/bin/init.js init --force
```

기대 결과:

- `.claude/commands/goal.md`
- `.claude/commands/hot-fix.md`
- `.codex/commands/goal.md`
- `.codex/commands/hot-fix.md`
- `.claude/skills/harness-ceo/SKILL.md`
- `.codex/skills/harness-ceo/SKILL.md`
- `.harness/shared/HR-Resource/`

그리고 `.claude/commands/`와 `.codex/commands/`에는 CXX command가 없어야 한다.
