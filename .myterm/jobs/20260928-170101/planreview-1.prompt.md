Claude 가 아래 요청의 설계를 썼다. 구현하기 전에 이 설계를 리뷰해줘.

## 요청
이 하네스 시스템을 이용하면 꼼꼼하다는 느낌은 있지만, 너무 프로세스가 과도하다는 느낌을 받는다. 가령 LLM 온리로 작업하면 5분이면 끝날것이 1~2시간 걸릴때도 있다. 전체적으로 시스템을 확인하고 어떤 부분을 수정하면 좋을지, 꼼꼼함은 유지하며 , 
시간을 단축 가능한지, 또는 너무 과도한 설계가 있어서, 좋은 모델의 유용성을 해치는 부분은 무엇인지, 확인해달라

## 작업 담당의 walwal-harness
Codex 는 /goal 를 쓸 수 없어요 (없음: .codex/commands/goal.md, .codex/skills/harness-ceo/SKILL.md) — 실행 방식은 llm 으로 한다.

## 설계 (Claude)
# 미션 규모 등급(Tier) 도입과 절차 경량화: 꼼꼼함은 유지하고 소요 시간은 줄인다

## 요약
지금 하네스는 작업 규모와 상관없이 모든 미션에 같은 절차를 강제합니다. 그래서 LLM 단독이면 5분 걸릴 수정도 7~9개의 새 세션을 거칩니다: CEO → hiring → CTO → 개발 worker → CQO → 평가 worker → OPS. 각 세션은 스킬 문서 10~20KB, AGENTS.md 20KB, conventions/gotchas 4종을 매번 새로 읽고, 규정된 섹션을 채운 문서를 씁니다. 이 설계는 CEO가 intake에서 미션을 **S/M/L 등급**으로 분류하게 합니다. S와 M에서는 품질에 기여하지 않는 절차를 걷어냅니다. 대상은 계층별 문서 의식, hiring/worker 계층, OPS watch, 핫픽스마다 gotcha 작성 의무입니다. 꼼꼼함의 핵심은 모든 등급에서 유지합니다. 핵심이란 "만든 사람과 검증한 사람을 분리하고, 실행된 테스트 증거로 판정하는 것"입니다.

## 요구 분석
- 시스템 전체를 진단해 과도한 프로세스가 어디서 시간을 쓰는지 찾는다.
- 꼼꼼함(검증 품질, 증거 기반 판정)은 유지한다.
- 소요 시간 단축안을 제시하고 구현 가능한 수준까지 설계한다.
- 좋은 모델의 능력을 막는 과잉 설계를 짚어낸다.

### 진단: 시간을 먹는 지점 (코드 근거)
| # | 과잉 지점 | 근거 | 비용 |
|---|---|---|---|
| D1 | **규모 예외 전면 금지.** "Small scope is not an exemption", "There is no scope exemption" | `HR-Resource/ceo/SKILL.md:102,163`, `commands/hot-fix.md` 8번 | 한 줄 수정도 전체 파이프라인을 탐 |
| D2 | **CXX 직접 실행 금지와 worker 강제.** CTO는 코드를, CQO는 검증을 직접 할 수 없음. Stop 훅이 이를 강제 | `cto/SKILL.md:100`, `cqo/SKILL.md:89-91`, `harness-worker-evidence-validate.sh`, `harness-stop.sh:158` | Opus급 CXX가 매 작업을 다시 브리핑하고 새 worker 세션을 띄움(컨텍스트를 두 번 적재) → **좋은 모델의 능력을 가장 크게 막는 지점** |
| D3 | **계층마다 반복되는 문서 의식.** ceo/cxx/worker 문서 전부에 Lessons Preflight, Lessons Tally, Implementation Notes(하위 섹션 4개)가 필수. cto.md는 섹션 8개, cqo.md는 9개 | `cqo/SKILL.md:108-118`, `harness-lessons-gate.sh`, 증거 validator의 `has_implementation_notes` | 산출물이 아닌 형식 작성에 턴 소모. 게이트가 누락을 막으므로 재작성 루프까지 발생 |
| D4 | **"verbatim 전파".** 상위 요구를 worker 브리프에 글자 그대로 복사 | `ceo:82`, `cto:23`, `cqo:23` | 브리프가 길어지고 worker 컨텍스트가 커짐 |
| D5 | **worker마다 붙는 부수 작업.** 스폰 전 report seed, `progress-set` 텔레메트리(시작·종료), model 선언, hr-roster 등록 | `cto:44,147-155`, `hiring/SKILL.md` | worker 1명당 셸 호출과 파일 쓰기 5~8회 |
| D6 | **러너블이면 무조건 OPS watch.** 없으면 CQO PASS가 무효 | `cqo:99`, AGENTS Hard Rule 16 | 작은 UI·로직 수정에도 세션 하나가 추가됨 |
| D7 | **핫픽스마다 gotcha 등록 의무** | AGENTS Hard Rule 5, `hot-fix.md` 11번 | 매번 문서 작성, 코퍼스 비대화, 이후 읽기 비용 증가 |
| D8 | **스킬 본문의 중복 서사.** "Reachability", "The Document Is The Record", "Worker Spawn Contract", "Measured: … 70 times" 같은 일화가 CEO/CTO/CQO/AGENTS에 거의 그대로 반복됨 | 각 SKILL.md 후반부 | 모든 세션이 같은 약 5~8KB를 반복 적재 |
| D9 | **CXX 전원이 매번 새 세션.** `/goal` 5번은 COO/CDO/CTO/CQO 모두에게 묻는 문장으로 읽힘 | `commands/goal.md` 5·6번 | 필요 없는 CXX 세션이 생김 |
| D10 | **직렬 파이프라인.** CQO는 CTO가 끝나야 계획을 시작함 | `ceo:165-169` | 병렬화할 수 있는 계획 단계가 대기함 |

### 유지할 꼼꼼함 (등급과 무관한 불변식)
- **I1** 구현자와 판정자를 분리한다. CQO 판정은 구현 세션과 다른 세션에서 낸다.
- **I2** 판정 근거는 실행 증거여야 한다. 명령, exit code, 출력 발췌가 필요하고, LLM이 눈으로 훑은 것은 증거가 아니다.
- **I3** 변경 범위 테스트와 풀 스위트 명령(있으면) 실행.
- **I4** Owner를 테스터로 쓰지 않는다(Hard Rule 15).
- **I5** 루프 종료는 runtime 전이로만 한다(Hard Rule 19). 외부 권한 차단 규칙도 그대로 둔다.
- **I6** headed Playwright 규칙(Hard Rule 18).

## 모호점과 해소안
- **등급은 누가 어떻게 정하나** → intake에서 CEO가 아래 기준으로 판단해 `mission-state.json`의 `tier` 필드(`"S"|"M"|"L"`)와 `ceo.md`에 한 줄 근거를 남긴다. Owner에게 묻지 않는다. 기존 자율 운영 헌장과 맞추기 위해서다.
  - **S**: 예상 변경 파일 3개 이하 또는 약 150줄 이하. 새 의존성·외부 스펙 없음. auth·결제·보안·데이터 마이그레이션·인프라·포트 신규 할당 없음. 기존 테스트 명령으로 검증 가능.
  - **L**: 새 서비스·포트, 외부 스펙 연동, 운영(operating) goal, 프로덕션 배포, 보안·결제·데이터 변경 중 하나라도 해당.
  - **M**: 그 외 전부.
- **tier 필드가 없는 기존 미션** → `L`로 취급한다. 하위 호환을 위해서이고, 기존 동작은 그대로다.
- **분류가 틀렸다면** → 상향만 자동으로 한다. S에서 변경이 기준을 넘거나, 위험 영역을 건드리거나, CQO FAIL이 2회 나오면 CEO가 `tier`를 올리고 `tier_history`에 사유를 추가한다. 이미 쓴 문서는 유지한다. 하향은 금지한다. 꼼꼼함을 줄이는 방향은 자동화하지 않기 위해서다.
- **S에서 CXX 직접 실행을 허용하면 "No CXX self-execution"(Hard Rule 8)과 충돌한다** → 규칙을 "S 등급에서는 CTO가 직접 구현하고, CQO가 **별도 세션에서** 테스트를 직접 실행해 판정한다"로 바꾼다. 원래 규칙이 지키려던 가치는 maker≠checker와 증거 기반 판정이며, 이는 I1·I2로 유지된다. worker 계층은 대규모 병렬화와 전문성 분리가 필요한 M/L에서만 의미가 있다.
- **S에서 CQO self-verification은 Hard Rule 9 위반인가** → S에서는 "LLM 검사로 판정"을 금지하고 "직접 실행한 명령 결과로 판정"은 허용한다. 대신 `cqo.md`에 `## Verification Commands`(명령 / exit code / 출력 발췌)를 의무화하고 validator가 이를 검사한다.
- **Lessons Preflight/Tally를 없애면 v7.1.55~57에서 막은 문제가 되살아나지 않나** → 읽는 순서(계획 전에 읽기)는 모든 등급에서 유지한다. S/M에서는 형식만 줄인다. 역할 문서에 `## Lessons` 한 섹션을 두고 "Preflight: … / Fired: …"를 두 줄로 쓰면 된다. 기존 두 헤딩도 계속 인정한다. worker 보고서에는 요구하지 않고(L 제외), 게이트는 역할 문서만 본다(현재 동작과 같음).
- **Implementation Notes 4개 하위 섹션** → L에서는 유지한다. S/M에서는 `## Implementation Notes` 헤딩 하나에 bullet로 요약해도 된다. validator는 tier에 따라 하위 섹션 검사를 건너뛴다.
- **OPS watch** → L 필수, M은 러너블 서비스의 런타임 설정·포트·기동 경로를 바꿨을 때만, S는 생략(`cqo.md`에 "OPS N/A: tier S" 한 줄).
- **핫픽스 gotcha 의무(Hard Rule 5)** → "재발 가능하거나 비자명한 원인일 때만 등록한다. 아니면 `cqo.md`의 Recurrence Notes에 `none — <이유>` 한 줄"로 바꾼다. 문서 생성 자체를 줄이자는 write-on-signal 방향(v7.1.53, Owner 선호)과도 맞는다.
- **AGENTS.md 수정 금지 규칙** → 이 저장소의 `AGENTS.md`는 건드리지 않는다. 설치 대상에 쓰이는 `assets/templates/AGENTS*.md.template`만 수정한다. 이 요청이 Owner의 명시적 요청에 해당한다.
- **3-command 규칙** → 명령을 추가하지 않는다. `/goal`, `/submission`, `/hot-fix`에 등급 분기만 넣는다.
- **worker 기본 모델(opus)** → 바꾸지 않는다. 꼼꼼함과 트레이드오프가 있는 변경이라 이번 범위에서 제외하고, Open Question으로 남긴다.

### 등급별 흐름 (목표 상태)
| 단계 | S | M | L (현행) |
|---|---|---|---|
| CEO | 메인 세션에서 처리, `ceo.md` 짧은 형식 | 동일 | 현행 |
| COO/CDO | 호출 안 함 | 필요할 때만 | 필요할 때만 |
| CTO | 새 세션, **직접 구현**, `cto.md`(Lessons, 변경 파일, 실행한 테스트, CQO Handoff) | 새 세션, worker 1~N (hiring 필요할 때만) | 현행 |
| CQO | 새 세션, **직접 테스트 실행**, `cqo.md`(Verification Commands, Verdict) | 새 세션, 평가 worker 1명. **CTO와 병렬로 게이트 초안 작성 허용** | 현행 |
| OPS | 생략 | 조건부 | 필수 |
| gotcha | 신호 있을 때만 | 신호 있을 때만 | 현행 |
| 예상 세션 수 | **2~3** | 4~5 | 7~9 |

## 변경 파일
- `HR-Resource/ceo/SKILL.md`
  - "Mission Tier" 섹션을 추가한다. 분류 기준, `tier` 기록, 상향 규칙, 등급별 라우팅 표가 들어간다.
  - Hard Rules의 "Small scope is not an exemption"과 Routing Gate의 "There is no scope exemption"을 "등급이 절차 깊이를 정한다. I1~I6은 모든 등급에서 불변"으로 바꾼다.
  - CEO 자신의 Lessons/Implementation Notes 형식을 등급별로 나눈다.
  - 중복 서사(D8)를 AGENTS 템플릿 참조 한 줄로 바꾼다.
- `HR-Resource/cto/SKILL.md`
  - "Tier S: 직접 구현" 절을 추가한다. worker·hiring·텔레메트리·report seed를 생략하되, 변경 범위 테스트 실행과 CQO Handoff는 필수다.
  - Required output sections를 L 기준으로 명시하고 S/M 축약본을 추가한다.
  - "Reachability", "The Document Is The Record", "Worker Spawn Contract"의 반복 서사는 핵심 규칙 1~2줄과 AGENTS 템플릿 참조로 줄인다. Worker Spawn Contract는 M/L에만 적용된다고 명시한다.
- `HR-Resource/cqo/SKILL.md`
  - "Tier S: 직접 검증" 절을 추가한다. 별도 세션 필수, `## Verification Commands` 필수, LLM 검사 판정 금지.
  - M에서 CTO와 병렬로 게이트 초안을 쓰는 것을 허용한다.
  - OPS watch 조건과 Recurrence Notes `none — 이유` 허용을 반영하고, D8 중복을 축약한다.
- `HR-Resource/ops/SKILL.md` — OPS watch 적용 조건(L 필수, M 조건부, S 생략)을 한 단락 반영한다.
- `HR-Resource/hiring/SKILL.md` — "S 등급에서는 hiring을 호출하지 않는다" 한 줄을 추가한다.
- `commands/goal.md`, `commands/submission.md`, `commands/hot-fix.md`
  - 2번 단계에서 tier 분류와 기록을 추가한다.
  - "ask COO, CDO, CTO, and CQO" → "필요한 CXX만"으로 바꾼다.
  - 7·8번(hired worker 강제)에 "tier M/L" 한정을 붙인다.
  - hot-fix 11번(gotcha 의무)을 신호 기반으로 바꾸고, "Scale the read to the fix" 문장은 그대로 둔다.
- `assets/templates/AGENTS.md.template`, `assets/templates/AGENTS-ko.md.template`
  - §5 Mission Flow에 등급 표를 추가한다.
  - Hard Rules를 개정한다. 1번(cto.md 선행)은 유지한다. 3·8·9번에 "tier M/L", S 대체 규칙을 명시한다. 5번은 신호 기반으로, 16번은 조건부로, 12·20번은 등급별 형식으로 바꾼다.
  - 스킬에서 빠진 공통 서사의 단일 출처를 이 파일로 정한다.
- `scripts/harness-worker-evidence-validate.sh`
  - mission-state의 `tier`를 읽는다(없으면 L).
  - S: worker report 존재 검사를 생략한다. 대신 `cqo.md`가 있으면 `## Verification Commands` 헤딩을 요구하고, Implementation Notes는 `##` 헤딩만 검사한다.
  - M: Implementation Notes 하위 섹션 검사를 생략한다.
  - L: 현행 그대로.
- `scripts/harness-lessons-gate.sh` — S/M에서는 `## Lessons` 단일 헤딩 **또는** 기존 Preflight+Tally 쌍을 통과시킨다. L은 현행 유지.
- `scripts/harness-stop.sh` — 차단 사유 문구를 등급별 요구에 맞춘다. 로직은 validator와 gate의 JSON 결과를 그대로 쓴다.
- `assets/templates/worker-report.md.template` — L 전용이라고 주석으로 명시한다.
- `assets/templates/config.json` — `behavior.mission_tiers: true`(false면 모든 미션을 L로 강제하는 opt-out)와 설명 필드를 추가한다. 스크립트는 이 값이 null이면 true로 본다. jq `//` 함정을 피해 기존 패턴(`if … == null then true else … end`)을 쓴다.
- `CHANGELOG.md`, `package.json` — 릴리스 항목과 버전(7.1.58)을 올린다.
- 변경하지 않는 것: `bin/init.js`(설치 계약 불변. 새 템플릿·스크립트는 기존 복사 경로로 배포됨), 이 저장소의 `AGENTS.md`, 명령 개수.

## 검증 규칙
- **tier 값 검증**: `S|M|L` 외의 값이나 누락은 `L`로 처리한다. 가장 엄격한 쪽으로 fail-safe하고, 차단 사유에 "unknown tier → L 적용"을 표기한다.
- **opt-out**: `behavior.mission_tiers=false`면 tier를 무시하고 L을 적용한다. 명시적 `false`가 `//`에 먹히지 않게 null 비교 패턴을 쓴다(`harness-stop.sh:28` 주석과 같은 함정).
- **S 불변식 검사 (validator)**:
  - `cqo.md`에 `## Verification Commands`가 없으면 위반.
  - `cto.md`와 `cqo.md`가 모두 있어야 complete가 허용된다. 두 문서가 같은 세션에서 작성됐는지는 기계로 판별할 수 없으므로 스킬 규칙으로 두고, CEO가 수락 시 확인한다. 이 한계는 Deviations에 명시한다.
- **상향만 허용**: `tier_history`가 S→M→L 순서를 역행하면 validator 경고를 남긴다(차단은 하지 않음).
- **헤딩 매칭**: 새 헤딩(`## Lessons`, `## Verification Commands`)도 기존 `HEADING2` 정규식(blockquote 허용, 내용 필터 없음. Hard Rule 22)으로 찾는다.
- **범위**: 기존처럼 `latest-active` 미션만 본다. legacy·archive 미션에 tier가 없어도 L로 간주할 뿐 새 차단은 생기지 않는다.
- **jq 사용**: 값 삽입은 `--arg`로 하고, 전이에 실패하면 non-zero exit(기존 fail-loud 규칙).
- **완료 게이트** (`harness-company-complete.sh`): lessons·reachability·spec-pin 게이트는 등급과 무관하게 유지한다. 스크립트 실행이라 비용이 작고, spec-pins.json이 없으면 통과한다.

## 테스트 계획
- **정적 검사**: `node --check bin/init.js`, `node --check scripts/import-agency-agents.js`, 수정한 스크립트마다 `bash -n`, `npm pack --dry-run --cache /private/tmp/walwal-npm-cache`.
- **설치 테스트**: `node ./bin/init.js init --force --project-root /private/tmp/walwal-v7-init-test`를 실행하고 다음을 확인한다.
  - 명령이 goal/submission/hot-fix 3개뿐인지.
  - `harness-{ceo,coo,cdo,cto,cqo,ops}/SKILL.md`에 Tier 섹션이 있는지.
  - AGENTS.md에 등급 표가 있고 `CLAUDE.md` symlink가 유지되는지.
  - `config.json`에 `mission_tiers` 키가 있는지.
- **스크립트 fixture 테스트** (`/private/tmp`에 `.harness/documents/goal-1-x/` 구성, validator·gate를 `json latest-active`로 실행):
  1. tier S + `cto.md`·`cqo.md`(Lessons, Verification Commands, 단일 Implementation Notes) + workers 없음 → ok:true
  2. tier S + `cqo.md`에 Verification Commands 없음 → ok:false
  3. tier M + workers 있음 + Implementation Notes 하위 섹션 없음 → ok:true
  4. tier L(또는 필드 없음) + workers 없음 → ok:false (현행 동작 회귀 방지)
  5. tier `"X"` → L 처리, 차단
  6. `mission_tiers=false` + tier S + workers 없음 → ok:false
  7. lessons gate: S에서 `## Lessons`만 있으면 통과, L에서 `## Lessons`만 있으면 위반
  8. `harness-stop.sh`에 위 fixture를 넣고 `conductor.state=running` 입력 → 등급별 block/통과 JSON 확인
  - 위 fixture는 `scripts/` 옆에 둘 단일 셸 self-check(assert 방식)로 남겨 이후 회귀 검사에 쓴다.
- **실사용 벤치마크** (수동, 결과를 CHANGELOG에 기록):
  - 설치된 테스트 프로젝트에서 같은 소규모 작업(예: 함수 1개 버그 수정과 테스트 추가)을 개선 전 버전과 개선 후 S 등급으로 각각 `/hot-fix` 실행.
  - 세션(Agent 호출) 수, 벽시계 시간, 생성된 문서 수를 `progress.log`와 `.harness/documents` 기준으로 비교.
  - 두 경우 모두 CQO 판정에 실제 테스트 명령과 exit code가 있는지 확인해 꼼꼼함 유지를 검증.
  - 목표: 세션 수 ≥50% 감소, 벽시계 시간 대폭 단축, 판정 증거 동등.
- **Open Questions** (구현 후 Owner 판단):
  - 평가 worker 기본 모델을 sonnet 등으로 차등 선언할지.
  - M 등급 CQO 병렬 착수 효과를 실측한 뒤 L에도 확대할지.