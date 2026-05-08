# @walwal-harness/cli

AI 에이전트 개발을 위한 회사형 하네스 프레임워크.

walwal-harness 는 단일 에이전트를 오래 붙잡는 대신, 문서와 상태 파일을 기준으로 여러 역할을 이어 붙입니다.  
핵심 개념은 "하나의 프로젝트 = 하나의 회사" 입니다.

- Owner: 사용자
- Dispatcher: CEO, 유일한 대화 창구
- Planner: COO, 기획·가설·HR
- CTO: 구현 총괄
- CQO: 품질 총괄
- Service-Ops: 운영·모니터링·회고
- Conductor: 자율 라우터
- Meeting-Manager: 회의 소집기

이 프레임워크는 Anthropic 의 harness engineering 방향과 NEXUS-style company loop 를 walwal-harness 구조에 맞게 재해석한 것입니다.

## 핵심 원칙

- 에이전트는 대화 기억보다 문서 팩트를 우선합니다.
- 작업 전환은 항상 `progress.json`, `handoff.json`, `task session` 을 기준으로 이뤄집니다.
- 회의는 동기화와 의사결정에 쓰고, 단순 런타임 복구는 값싼 상태 기반 로직으로 처리합니다.
- TokenLimit, retry, drift, handoff 같은 운영 문제를 코드가 아니라 하네스 레벨에서 다룹니다.

## 회사 구조

```text
Owner
  ↕
Dispatcher (CEO)
  ├─ Conductor
  └─ Meeting-Manager
       ↓
  Planner (COO + HR)
    ├─ COO Hypothesis Cell
    │  ├─ coo-developer
    │  └─ documentationer
    ├─ CTO
    │  ├─ generator-backend
    │  ├─ generator-frontend
    │  ├─ generator-designer
    │  └─ generator-devops
    ├─ CQO
    │  ├─ evaluator-code-quality
    │  ├─ evaluator-functional
    │  ├─ evaluator-visual
    │  ├─ evaluator-architecture
    │  └─ evaluator-security
    └─ Service-Ops
```

### 각 부서가 하는 일

- `Dispatcher`: 사용자 요청을 회사가 처리할 목표와 루프로 변환
- `Meeting-Manager`: Standup, Sprint Review, Spec Review, Incident War Room, All-Hands 소집
- `Conductor`: 다음 owner 와 next agent 를 재결정
- `Planner`: 스펙, feature-list, api-contract, 가설 검증 셀 운영
- `CTO`: 구현 라인 총괄, hotfix/기술 판단
- `CQO`: 적대적 평가와 회귀 차단
- `Service-Ops`: cadence, 운영 drift, auto-retro
- `coo-developer`: 빠른 spike, backdata 검증
- `documentationer`: 웹 리서치, 실험 보고서, 가설 유효/무효 판정

## 설치

프로젝트 루트에서:

```bash
npm i @walwal-harness/cli
```

설치 후 Claude Code 를 재시작합니다.

초기화가 필요하면:

```bash
npx walwal-harness
```

기존 설치를 현재 패키지 버전에 맞게 다시 정리하려면:

```bash
npx walwal-harness --force
```

## 시작 방법

새 Claude Code 세션의 첫 메시지:

```text
하네스 엔지니어링 시작
```

기본 흐름:

1. `dispatcher` 가 요청을 분류하고 pipeline/runbook 을 정합니다.
2. 필요하면 `meeting-manager` 가 CEO intake 회의를 엽니다.
3. `planner` 가 `plan.md`, `feature-list.json`, `api-contract.json` 을 만듭니다.
4. `conductor` 가 회사 루프에 따라 CTO/CQO/Service-Ops/Meeting 으로 라우팅합니다.
5. generator / evaluator / cqo / ops 가 문서 기반으로 이어집니다.

## 상태 파일

하네스의 기준 상태는 `.harness/` 아래에 있습니다.

| 파일 | 역할 |
|---|---|
| `.harness/progress.json` | 현재 회사 상태의 단일 기준 |
| `.harness/handoff.json` | 다음 agent 실행 문서 |
| `.harness/progress.log` | 사람 읽기용 활동 로그 |
| `.harness/actions/` | 활성 sprint 문서 |
| `.harness/archive/` | 완료 sprint 보관 |

### 중요한 progress 필드

- `current_agent`, `agent_status`, `next_agent`
- `workflow.stage`
- `meetings.*`
- `task_sessions.current`
- `task_stop.*`
- `goals.*`
- `conductor.*`, `planner.*`, `cto.*`, `cqo.*`, `service_ops.*`

## Task Session

각 agent 전환 시 `.harness/actions/task-sessions/<agent>/...md` 가 생성됩니다.

목적:

- 이전 채팅 문맥을 들고 가지 않기
- 자기편향적 사고를 줄이기
- 사실과 추론을 분리하기
- 재개 시에도 문서 기준으로만 이어가기

에이전트는 task session, handoff, progress 를 단일 사실원으로 사용해야 합니다.

## 회의 시스템

회의는 계속 유지됩니다. 토큰 제한 복구 로직이 회의를 대체하지 않습니다.

지원 회의:

- `Standup`
- `Sprint Review`
- `Spec Review`
- `Incident War Room`
- `All-Hands`

역할:

- 회의: owner 결정, drift 분류, evidence 집계, action item 생성
- Conductor: 회의 결과를 읽고 next agent 갱신
- Service-Ops: cadence 계산

기본 cadence:

- `light`: 30m
- `normal`: 1h
- `heavy`: 4h

## TokenLimit Hold / Resume

`TokenLimit` 은 회의가 아니라 런타임 중단 복구 문제로 취급합니다.

즉:

- 회의 시스템은 그대로 유지
- TokenLimit 은 별도 저비용 복구 레이어로 처리

### 동작 방식

토큰 한도로 작업이 중단되면:

```bash
bash scripts/harness-token-limit.sh . mark
```

기본 정책:

- `TaskStopReason = TokenLimit`
- 현재 작업은 `paused`
- `progress.json.task_stop` 에 아래가 기록됨
  - `wake_target`
  - `resume_after`
  - `stopped_agent`
  - `stopped_next_agent`
  - `task_session_path`

그 다음:

- `SessionStart` 는 별도 모델 probe 없이 시간만 확인
- 아직 hold 중이면 `retry_after` 와 `wake target` 만 출력
- 시간이 지나면 `# Harness resume ready` 를 출력하고 원래 CXX/agent 로 복귀

테스트용:

```bash
bash scripts/harness-token-limit.sh . mark 300
```

중요:

- 회의는 유지됩니다.
- TokenLimit checker 는 회의를 대체하지 않습니다.
- 에이전트는 복귀 시 이전 대화가 아니라 `task_session_path` 와 문서를 보고 이어갑니다.

## COO Hypothesis Cell

정규 CTO/CQO 라인에 넣기 전, COO 직속으로 빠른 가설 검증 셀을 돌릴 수 있습니다.

구성:

- `coo-developer`
- `documentationer`

흐름:

1. `planner.requested_mode = "hypothesis"`
2. `documentationer` 가 리서치/질문 정리
3. `coo-developer` 가 spike / backdata 실험
4. `documentationer` 가 보고서와 verdict 작성
5. `planner` 가 결과를 정규 sprint artifact 로 승격하거나 폐기

핵심은 운영 품질이 아니라 빠른 사실 확인입니다.

## 모드

### Company / Team

기본 경로입니다. Conductor 가 `mode=auto` 에서 선택합니다.

특징:

- 회사형 루프 유지
- control-plane 과 worker-plane 분리
- feature queue 기반 병렬 처리
- tmux studio 사용 가능

강제 전환:

```text
/harness-team
```

### Solo

비상용 fallback 입니다.

사용 시점:

- 디버깅
- 스크립트 장애
- 짧은 수동 복구

강제 전환:

```text
/harness-solo
```

### Stop

Team 모드를 안전하게 멈추고 진행 중이던 feature 를 ready 로 복구합니다.

```text
/harness-stop
```

## Team Studio

Team 모드에서는 tmux 기반 Studio 레이아웃을 사용합니다.

시작:

```text
/harness-team
```

또는:

```bash
npx walwal-harness team
```

Team Studio 는 보통 다음을 보여줍니다.

- Dashboard
- Gotchas
- Conventions
- Memory
- Team 1~3 worker pane
- Archive prompt

Queue 관련 유용한 명령:

```bash
bash scripts/harness-queue-manager.sh status .
bash scripts/harness-queue-manager.sh auto-dispatch .
bash scripts/harness-queue-manager.sh idle-slots .
```

## Generator / Evaluator Chain

구현과 평가는 분리됩니다.

일반적인 흐름:

1. `generator-backend`
2. `generator-frontend`
3. `evaluator-code-quality`
4. `evaluator-functional`
5. `evaluator-visual`
6. `cqo`
7. `service-ops`

평가자 체인 원칙:

- 앞단 FAIL 시 뒤 평가는 생략 가능
- Evidence 없는 점수는 0
- regression 1건 이상이면 전체 FAIL
- evaluator 는 읽기 전용

## Gotchas / Conventions / Memory

하네스는 피드백을 세 저장소로 나눠 누적합니다.

| 종류 | 용도 |
|---|---|
| `gotchas/` | 에이전트가 반복한 실수 |
| `.harness/conventions/` | 하우스 스타일 |
| `.harness/memory.md` | 프로젝트 전역 교훈 |

각 agent 는 세션 시작 시 다음 순서로 읽습니다.

1. `CONVENTIONS.md`
2. `.harness/conventions/shared.md`
3. `.harness/conventions/<self>.md`
4. `.harness/gotchas/<self>.md`
5. `.harness/memory.md`

## 주요 스크립트

| 스크립트 | 역할 |
|---|---|
| `scripts/harness-next.sh` | handoff 생성과 다음 agent 결정 |
| `scripts/conductor-tick.sh` | company loop 라우팅 |
| `scripts/harness-session-start.sh` | 새 세션 시작 시 자동 안내 |
| `scripts/harness-user-prompt-submit.sh` | prompt 훅 주입/차단 |
| `scripts/harness-task-session.sh` | agent 별 task session 생성 |
| `scripts/harness-token-limit.sh` | TokenLimit hold/resume 마킹 |
| `scripts/harness-queue-manager.sh` | team queue 관리 |
| `scripts/harness-dashboard.sh` | dashboard 렌더 |
| `scripts/harness-meeting-doc.sh` | 회의 문서 skeleton / decision 처리 |

## 디렉토리 구조

```text
.harness/
├── actions/
│   ├── plan.md
│   ├── feature-list.json
│   ├── api-contract.json
│   ├── sprint-contract.md
│   ├── meetings/
│   ├── incidents/
│   └── task-sessions/
├── archive/
├── progress.json
├── handoff.json
├── progress.log
├── config.json
└── doctrine/
```

상세 조직 규칙은 다음 문서를 봅니다.

- `AGENTS.md`
- `.harness/doctrine/nexus.md`
- `.harness/agency-mapping.md`
- `.harness/HARNESS.md`

## Troubleshooting

### 다음 agent 가 안 뜸

```bash
cat .harness/progress.json | jq '{current_agent, agent_status, next_agent, workflow, task_stop}'
```

### handoff 재생성

```bash
bash scripts/harness-next.sh .
```

### SessionStart 안내 확인

```bash
bash scripts/harness-session-start.sh
```

### TokenLimit hold 상태 확인

```bash
cat .harness/progress.json | jq '.task_stop'
```

### queue 상태 확인

```bash
bash scripts/harness-queue-manager.sh status .
```

### mode 강제 전환

```text
/harness-team
/harness-solo
/harness-stop
```

## 버전 호환성

README 는 v6.1 계열 회사형 하네스를 기준으로 작성되었습니다.

이 문서에서 전제하는 기능:

- company loop
- conductor / meeting-manager / cto / cqo / service-ops
- task-session isolation
- COO hypothesis cell
- TokenLimit hold/resume

## License

MIT
