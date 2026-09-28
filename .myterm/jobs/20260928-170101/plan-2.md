# 미션 규모 등급(Tier) 도입과 절차 경량화: 꼼꼼함은 유지하고 소요 시간은 줄인다 (2차)

## 요약
지금 하네스는 작업 규모와 상관없이 모든 미션에 같은 절차를 강제합니다. 그래서 LLM 단독이면 5분 걸릴 수정도 7~9개의 새 세션을 거칩니다: CEO → hiring → CTO → 개발 worker → CQO → 평가 worker → OPS. 이 설계는 CEO가 intake에서 미션을 **S/M/L 등급**으로 분류하게 합니다. S와 M에서는 품질에 기여하지 않는 절차를 걷어냅니다. 대상은 worker 계층, 역할 문서 형식, 브리프 verbatim 복사, 핫픽스마다 gotcha 작성 의무입니다. 꼼꼼함의 핵심은 모든 등급에서 유지합니다. 핵심이란 "만든 사람과 검증한 사람을 분리하고, 실행된 테스트 증거로 판정하는 것"입니다.

2차 설계에서는 리뷰가 찾아낸 기존 결함 하나를 함께 고칩니다. 지금은 명령 문서가 `active:false`를 먼저 쓰게 한 뒤 완료 스크립트를 부릅니다. 그래서 완료 스크립트의 lessons 게이트가 대상 미션을 찾지 못하고 통과합니다. 이번에 **완료 전이 자체가 대상 미션의 증거와 판정을 검사한 뒤에만 terminal 상태로 전이**하도록 바꿉니다.

## 요구 분석
- 시스템 전체를 진단해 과도한 프로세스가 어디서 시간을 쓰는지 찾는다.
- 꼼꼼함(검증 품질, 증거 기반 판정)은 유지한다.
- 소요 시간 단축안을 제시하고 구현 가능한 수준까지 설계한다.
- 좋은 모델의 능력을 막는 과잉 설계를 짚어낸다.

### 진단: 시간을 먹는 지점 (코드 근거)
| # | 과잉 지점 | 근거 | 비용 |
|---|---|---|---|
| D1 | **규모 예외 전면 금지.** "Small scope is not an exemption", "There is no scope exemption", 핫픽스의 "even when the fix is small" | `HR-Resource/ceo/SKILL.md`, `commands/hot-fix.md` 8번 | 한 줄 수정도 전체 파이프라인을 탐 |
| D2 | **CXX 직접 실행 금지와 worker 강제.** Stop 훅의 validator가 `{cxx}.md`마다 worker 보고서를 요구함 | `AGENTS.md.template` Hard Rule 8·9, `harness-worker-evidence-validate.sh`의 `has_worker_report` | Opus급 CXX가 매 작업을 다시 브리핑하고 새 worker 세션을 띄움(컨텍스트를 두 번 적재) → **좋은 모델의 능력을 가장 크게 막는 지점** |
| D3 | **계층마다 반복되는 문서 의식.** 모든 역할 문서에 Lessons Preflight/Tally와 Implementation Notes(하위 섹션 4개)가 필수. `cqo.md`는 섹션 9개 | `cqo/SKILL.md` Required output sections, `harness-lessons-gate.sh`, `has_implementation_notes` | 산출물이 아닌 형식 작성에 턴 소모. 게이트가 누락을 막으므로 재작성 루프까지 발생 |
| D4 | **"verbatim 전파".** 보고서 골격, Lessons Tally, Implementation Notes 블록을 worker 브리프에 글자 그대로 복사하고, 빠지면 hire를 거절 | `hiring/SKILL.md` Worker Rule Links, Hard Rule 20 | seed된 보고서 파일에 이미 골격이 있는데도 브리프에 다시 넣음 |
| D5 | **worker마다 붙는 부수 작업.** report seed, `progress-set` 텔레메트리, model 선언, hr-roster 등록 | `cto/SKILL.md`, `hiring/SKILL.md` | worker 1명당 셸 호출과 파일 쓰기 5~8회 |
| D6 | **핫픽스마다 gotcha 등록 의무** | `hot-fix.md` 11번 "mandatory … even for small fixes" | 매번 문서 작성, 코퍼스 비대화, 이후 읽기 비용 증가 |
| D7 | **스킬 본문의 중복 서사.** Reachability, "The Document Is The Record", Worker Spawn Contract, 측정 일화가 CEO/CTO/CQO/AGENTS에 반복됨 | 각 SKILL.md 후반부 | 모든 세션이 같은 약 5~8KB를 반복 적재 |
| D8 | **CXX 전원 호출로 읽히는 문장** | `commands/goal.md` 5번 "CEO asks COO, CDO, CTO, and CQO" | 필요 없는 CXX 세션이 생김 |
| D9 | **직렬 파이프라인.** CQO는 CTO가 끝나야 계획을 시작함 | `ceo/SKILL.md` 라우팅 | 병렬화할 수 있는 계획 단계가 대기함 |
| D10 | **(발견된 결함) 완료 게이트 우회.** 명령 문서는 `active:false`를 먼저 쓰게 하고, 완료 스크립트의 게이트는 `latest-active`만 봄. 그 결과 대상 미션이 빠지고 게이트가 통과함. validator는 완료 경로에서 아예 호출되지 않음 | `commands/goal.md` 10번, `submission.md`·`hot-fix.md` 12번, `harness-company-complete.sh`의 lessons-gate 호출 | 절차는 무겁지만 정작 마지막 관문은 비어 있음 |

### 유지할 꼼꼼함 (등급과 무관한 불변식)
- **I1** 구현자와 판정자를 분리한다. CQO 판정은 구현 세션과 다른 세션에서 낸다. 이를 보장할 수 없는 런타임에서는 그 사실을 기록한다(Codex 절 참조).
- **I2** 판정 근거는 실행 증거여야 한다. 명령, exit code, 출력 발췌가 필요하고, LLM이 눈으로 훑은 것은 증거가 아니다.
- **I3** 변경 범위 테스트를 실행하고, 풀 스위트 명령이 있으면 그것도 실행한다.
- **I4** Owner를 테스터로 쓰지 않는다(Hard Rule 15).
- **I5** 루프 종료는 runtime 전이로만 한다(Hard Rule 19). **완료 전이는 대상 미션의 판정이 PASS일 때만 성공한다(신규).**
- **I6** headed Playwright 규칙(Hard Rule 18).
- **I7** OPS watch 규칙은 현행 그대로다. 러너블 런타임을 대상으로 한 검증에만 적용하고, 등급과 무관하다.

## 모호점과 해소안
- **등급은 누가 어떻게 정하나** → intake에서 CEO가 판단해 `mission-state.json`의 `tier`(`"S"|"M"|"L"`)에 기록하고 `ceo.md`에 한 줄 근거를 남긴다. Owner에게 묻지 않는다(자율 운영 헌장).
  - **S**: 예상 변경 파일 3개 이하 또는 약 150줄 이하. 새 의존성·외부 스펙 없음. auth·결제·보안·데이터 마이그레이션·인프라·포트 신규 할당 없음. 기존 테스트 명령으로 검증 가능.
  - **L**: 새 서비스·포트, 외부 스펙 연동, 운영(operating) goal, 프로덕션 배포, 보안·결제·데이터 변경 중 하나라도 해당.
  - **M**: 그 외 전부.
- **tier 필드가 없는 미션** → L로 취급하고, 완료 전이의 신규 판정 검사도 적용하지 않는다. 이렇게 해서 기존 동작과 기존 테스트(`apps/harness-dashboard/lib/__tests__/sandbox-e2e.test.ts`, `company-flow.test.ts`)를 그대로 유지한다. tier를 빠뜨려도 오늘보다 느슨해지지 않는다.
- **유효 등급(effective tier)** → `tier`와 `tier_history[].to` 중 가장 높은 등급이다. 모르는 값(`"X"` 등)은 L로 본다. `behavior.mission_tiers=false`면 모든 미션이 L이다. 따라서 하향은 기록해도 효력이 없다. 하향 시도는 경고가 아니라 **무시(최고 등급 적용)**로 강제된다.
- **등급 상향 시 기존 산출물 처리** → 원칙: *상향 전에 끝낸 작업은 당시 등급 기준으로 보존하고, 상향 이후의 작업과 최종 검증은 새 등급 기준을 따른다.* CEO는 `tier`를 올리고 `tier_history`에 `{from,to,at,reason}`을 추가한다.
  - **worker 보고서 형식은 등급과 무관하게 현행 그대로다.** seed 템플릿(`worker-report.md.template`)에 4개 하위 섹션이 `None`으로 미리 들어 있어 작성 비용이 거의 없다. 그래서 M→L 상향으로 과거 worker 보고서를 고칠 일이 생기지 않는다.
  - **S→M/L**: S에서 직접 작업한 역할 문서(`cto.md`의 `## Direct Work` 섹션)는 worker 보고서 요구에서 면제한다. 조건은 `tier_history`에 `from:"S"`가 있는 경우다. 과거 작업에 worker 증거를 사후로 만들어낼 필요가 없다. 상향 이후의 추가 구현은 worker로 한다. **최종 CQO 판정은 새 등급 기준을 따른다.** 즉 평가 worker 보고서가 있어야 하므로(`cqo-verdict-without-evaluator` 검사가 그대로 적용됨) 독립 검증이 다시 수행된다. 등급을 올리는 이유가 바로 이것이다.
  - **M→L**: 역할 문서(`{cxx}.md`)만 L 형식으로 보강한다. Lessons Preflight/Tally와 Implementation Notes 4개 하위 섹션이 대상이다. 역할 문서는 살아 있는 문서이므로 헤딩 몇 개를 더하는 한 번의 편집이면 된다.
  - 상향 트리거: 기준 초과, 위험 영역 접촉, CQO FAIL 2회.
- **S에서 CXX 직접 실행 vs Hard Rule 8·9** → 규칙을 이렇게 바꾼다. "유효 등급 S에서는 CTO가 직접 구현하고, CQO가 **별도 세션에서** 테스트를 직접 실행해 판정한다." 원래 규칙이 지키려던 가치는 maker≠checker와 증거 기반 판정이며, 이는 I1·I2로 유지된다.
- **S에서 CQO self-verification** → "LLM 검사로 판정"은 금지하고, "직접 실행한 명령 결과로 판정"은 허용한다. `cqo.md`에는 다음이 필수다.
  - `## Verification Commands`: 명령 / exit code / 출력 발췌.
  - `Verification Session: separate|same-session` 한 줄.
- **Codex 어댑터와 세션 분리 충돌** → 어댑터 문구를 둘로 나눈다.
  - **별도 세션**: Claude의 새 Agent 호출, Codex의 sub-agent 도구, 또는 CEO가 셸로 띄우는 `codex exec` 비대화 세션(CQO 스킬과 미션 파일만 읽는 새 프로세스). CQO에는 이 경로를 우선 사용한다.
  - **역할 전환(same-session)**: 위 경로를 쓸 수 없을 때만 허용한다. 이때 `cqo.md`에 `Verification Session: same-session`을 기록한다. 완료 스크립트는 전이를 허용하되 `progress.log`에 `same-session-verification`을 남기고 stderr로 경고한다. CEO의 Owner 보고에는 "판정자 독립성 미확보"를 명시해야 한다.
  - 이 경우 전이를 **거부하지는 않는다.** 근거는 [반박] 절에 있다.
- **Lessons 형식** → 계획 전에 읽는 순서는 모든 등급에서 유지한다. 유효 등급 S/M의 역할 문서는 `## Lessons` 한 섹션("Preflight: … / Fired: …" 두 줄)으로 대체할 수 있다. 기존 두 헤딩도 계속 인정하고, L은 현행 그대로다.
- **Implementation Notes** → 유효 등급 S/M의 역할 문서는 `## Implementation Notes` 헤딩 하나에 bullet 요약으로 충분하다. L 역할 문서와 모든 worker 보고서는 현행 4개 하위 섹션을 유지한다.
- **브리프 verbatim 복사(D4)** → 보고서 골격, Lessons Tally, Implementation Notes 블록은 seed된 보고서 파일이 이미 담고 있다. 그래서 브리프에는 "seed된 보고서 경로를 채워라" 한 줄로 대신한다. 브라우저 규칙(headless:false)처럼 **보고서에 없는 행동 규칙**만 계속 verbatim으로 넣는다.
- **핫픽스 gotcha 의무(D6)** → 재발 가능하거나 원인이 비자명할 때만 등록한다. 아니면 `cqo.md` Recurrence Notes에 `none — <이유>` 한 줄을 쓴다. 문서 생성을 줄이는 write-on-signal 방향(v7.1.53)과 맞는다.
- **완료 전이 대상** → 명령 문서가 대상 미션 경로를 넘긴다: `harness-company-complete.sh . <reason> <mission-rel>`. 인자가 없으면 기존 선택 로직과 기존 게이트 범위를 그대로 쓴다. Stop 훅 backstop과 기존 호출자가 이 경로라서 호환된다.
- **cancelled/superseded 종료** → 수락할 산출물이 없으므로 판정 검사를 건너뛴다. 기록 자체가 "완료"가 아니라 "취소"로 남으므로 은폐가 아니다.
- **AGENTS.md 수정 금지 규칙** → 이 저장소의 `AGENTS.md`는 건드리지 않고, 설치 템플릿만 수정한다.
- **3-command 규칙** → 명령을 추가하지 않는다.
- **worker 기본 모델** → 이번 범위에서 제외하고 Open Question으로 남긴다.

### 등급별 흐름 (목표 상태)
| 단계 | S | M | L (현행) |
|---|---|---|---|
| CEO | 메인 세션, `ceo.md` 짧은 형식 | 동일 | 현행 |
| COO/CDO | 호출 안 함 | 필요할 때만 | 필요할 때만 |
| CTO | 새 세션, **직접 구현**, `cto.md`(Lessons, Direct Work: 변경 파일·실행한 테스트, CQO Handoff) | 새 세션, worker 1~N(hiring은 필요할 때만) | 현행 |
| CQO | **별도 세션**, 직접 테스트 실행, `cqo.md`(Verification Commands, Verification Session, CQO Verdict) | 별도 세션, 평가 worker 1명. CTO와 병렬로 게이트 초안 작성 허용 | 현행 |
| OPS | 러너블 런타임 검증일 때만(현행 규칙) | 동일 | 동일 |
| gotcha | 신호 있을 때만 | 신호 있을 때만 | 현행 |
| 완료 전이 | 판정 PASS + S 필수 섹션 검사 | 판정 PASS + worker 증거 검사 | 판정 PASS + worker 증거 검사 (tier 없으면 현행) |
| 예상 세션 수 | **2~3** | 4~5 | 7~9 |

## 변경 파일
- `scripts/harness-company-complete.sh`
  - 3번째 인자 `<mission-rel>`(선택)를 받는다. 주면 그 미션을 전이 대상으로 확정하고, 없으면 기존 `pick_transition_mission_state`를 쓴다.
  - 대상이 확정되고 `mission-state.json`에 `tier`가 있으면, **progress.json 전이 전에** 다음을 순서대로 실행하고 하나라도 실패하면 `exit 1`로 끝낸다. 이때 상태 파일은 건드리지 않는다.
    1. lessons 게이트를 `mission:<rel>` 범위로 실행.
    2. worker evidence validator를 `mission:<rel>` 범위로 실행.
    3. 판정 검사: `cqo.md`의 `## CQO Verdict` 섹션(Hard Rule 22 헤딩 정규식, 모든 hit)에서 마지막으로 나오는 `PASS|ACCEPTED|FAIL|REJECTED|BLOCKED` 토큰이 PASS 또는 ACCEPTED여야 한다.
    4. 유효 등급 S: `cto.md`에 `## Direct Work`, `cqo.md`에 `## Verification Commands`와 `Verification Session:` 줄이 있어야 한다. `same-session`이면 경고하고 로그만 남긴다.
  - 대상 lifecycle이 `cancelled|superseded`면 판정 검사를 건너뛴다.
  - 기존의 마지막 단계(대상 `mission-state`를 `complete`로, `active:false`로 기록)도 확정된 대상을 쓴다.
  - 거부할 때는 기존 패턴대로 `progress.log`에 `company-complete | refused | <사유>`를 남긴다.
- `scripts/harness-worker-evidence-validate.sh`
  - scope `mission:<rel>`을 추가한다. 해당 디렉터리만 검사하고 active 여부는 보지 않는다.
  - 유효 등급을 계산한다. jq 한 식이며, 모르는 값·누락·`mission_tiers=false`는 L로 본다.
  - S: 역할 문서의 worker 보고서 요구와 `cqo-verdict-without-evaluator`를 생략하고, 역할 문서 Implementation Notes는 `##` 헤딩만 검사한다.
  - M: 역할 문서 Implementation Notes 하위 섹션 검사를 생략한다. worker 보고서 요구는 유지한다.
  - M/L에서 `tier_history`에 `from:"S"`가 있고 역할 문서에 `## Direct Work`가 있으면, 그 역할의 worker 보고서 요구를 면제한다. 단 cqo의 `cqo-verdict-without-evaluator`는 면제하지 않는다.
  - L: 현행 그대로다. worker 보고서 형식 검사는 전 등급에서 현행 그대로다.
- `scripts/harness-lessons-gate.sh` — scope `mission:<rel>`을 추가한다. 유효 등급 S/M에서는 `## Lessons` 단일 헤딩 **또는** Preflight+Tally 쌍을 통과시키고, L은 현행 그대로다.
- `scripts/harness-stop.sh` — 차단 사유 문구를 등급별 요구에 맞춘다. 로직은 validator와 gate의 JSON을 그대로 쓴다. Stop 훅은 작업 중에 돌기 때문에 판정 검사는 넣지 않는다(완료 전이 전용).
- `commands/goal.md`, `commands/submission.md`, `commands/hot-fix.md`
  - mission-state 작성 단계에서 `tier`를 분류하고 기록한다.
  - 완료 단계를 바꾼다. 완료할 때는 `active:false`를 먼저 쓰지 않고 `harness-company-complete.sh . <reason> <mission-rel>`을 부른다. 스크립트가 검사 후 `complete`/`active:false`를 기록한다. 스크립트가 거부하면 미션은 active로 남고 작업이 계속된다. cancelled/superseded/closed는 문서 상태를 먼저 쓰고 같은 명령을 호출한다.
  - "ask COO, CDO, CTO, and CQO"를 "필요한 CXX만"으로 바꾼다.
  - worker 강제 단계(goal 7·8, hot-fix 6·8)에 "유효 등급 M/L"로 한정한다. S 대체 문장도 넣는다.
  - hot-fix 11번을 신호 기반으로 바꾼다. "Scale the read to the fix"는 유지한다.
  - Codex adapter 블록에 "CQO는 별도 세션(sub-agent 또는 `codex exec`) 우선, 불가 시 same-session 기록" 한 줄을 추가한다.
  - 하단 Lessons 문단의 verbatim 문장을 "보고서에 없는 행동 규칙만 verbatim"으로 좁힌다.
- `HR-Resource/ceo/SKILL.md`
  - "Mission Tier" 섹션을 추가한다. 분류 기준, 유효 등급, 상향 절차와 산출물 처리, 등급별 라우팅 표가 들어간다.
  - "no scope exemption" 문구를 "등급이 절차 깊이를 정한다. I1~I7은 불변"으로 바꾼다.
  - 완료 호출 형식(`<mission-rel>` 전달)과 same-session 공개 의무를 넣는다.
  - 중복 서사는 템플릿 참조 한 줄로 줄인다.
- `HR-Resource/cto/SKILL.md` — "Tier S: Direct Work" 절을 추가한다. worker·hiring·텔레메트리·seed를 생략하되, 변경 범위 테스트 실행과 CQO Handoff는 필수다. Required output을 L 기준과 S/M 축약본으로 나눈다. Worker Spawn Contract는 M/L 전용이라고 명시한다. 중복 서사는 축약한다.
- `HR-Resource/cqo/SKILL.md` — "Tier S: Direct Verification" 절을 추가한다(별도 세션 우선, Verification Commands와 Verification Session 필수, LLM 검사 판정 금지). M에서 병렬 게이트 초안을 허용한다. Recurrence Notes에 `none — 이유`를 허용한다. OPS 절은 **현행 조건 문구를 유지**하고, 비러너블일 때 `OPS N/A: <이유>` 한 줄을 명시한다.
- `HR-Resource/hiring/SKILL.md`
  - "유효 등급 S에서는 hiring을 호출하지 않는다"를 추가한다.
  - Worker Rule Links의 verbatim 대상에서 보고서 골격, Lessons Tally, Implementation Notes 블록을 빼고 "seed된 보고서 경로 명시"로 바꾼다. 브라우저 규칙 등 행동 규칙은 그대로 둔다.
  - 거절 조건도 이에 맞춘다.
- `HR-Resource/resource-manager/SKILL.md` — Mandatory Worker Report Appendix를 "seed된 보고서(템플릿)에 이미 포함됨. assignment에는 보고서 경로를 반환"으로 바꾼다. 하위 섹션 요구 자체는 유지한다(worker 보고서 형식은 전 등급 불변).
- `HR-Resource/ops/SKILL.md` — 변경 없음(OPS 규칙 현행 유지). 1차 설계의 "L 필수" 문장은 철회한다.
- `assets/templates/AGENTS.md.template`, `assets/templates/AGENTS-ko.md.template`
  - §1.1 Codex Adapter: "fresh session"을 별도 세션(sub-agent/`codex exec`)과 역할 전환으로 구분하고, CQO 판정의 same-session 기록 규칙을 넣는다.
  - §5에 등급 표를 추가한다.
  - Hard Rules 개정: 8·9에 "유효 등급 M/L"과 S 대체 규칙, 12·20에 등급별 역할 문서 형식(worker 보고서는 불변)과 verbatim 범위 축소, 19에 "완료 전이는 대상 미션 경로를 넘기고 판정 PASS일 때만 성공". 16은 **변경하지 않는다**.
  - 스킬에서 빠진 공통 서사의 단일 출처로 삼는다.
- `assets/templates/config.json` — `behavior.mission_tiers: true`와 설명을 추가한다. 스크립트는 `if … == null then true else … end` 패턴을 쓴다(`//` 함정 회피).
- `CHANGELOG.md`, `package.json` — 7.1.58.
- 변경하지 않는 것: `bin/init.js`(새 스크립트 파일 없음, 기존 파일만 수정하므로 manifest 불변), 이 저장소의 `AGENTS.md`, `worker-report.md.template`, 명령 개수.

## 검증 규칙
- **tier 값**: `S|M|L` 외의 값이나 누락은 L로 처리한다. 차단 사유에는 "unknown tier → L"을 표기한다.
- **유효 등급**: `max(tier, tier_history[].to)`. 하향 기록은 효력이 없다.
- **opt-out**: `behavior.mission_tiers=false`면 전부 L이다. null 비교 패턴을 쓴다(`harness-lessons-gate.sh`의 기존 주석과 같은 함정).
- **완료 전이 원자성**: 모든 검사는 `harness-progress-set.sh` 호출 **이전**에 끝낸다. 실패하면 `exit 1`이고 `progress.json`, `todos/state.json`, `mission-state.json`을 전혀 수정하지 않는다. "거부가 전이 뒤에 오면 아무것도 거부하지 않은 것"이라는 기존 spec-pin 주석의 원칙과 같다.
- **대상 경로 검증**: `<mission-rel>`은 `.harness/documents/` 아래의 기존 디렉터리이면서 `mission-state.json`을 가져야 한다. `..` 포함이나 절대경로는 거부한다(`exit 1`).
- **판정 토큰**: `## CQO Verdict` 섹션 본문에서 마지막 토큰으로 판정한다. 취소선으로 정정한 뒤 새 판정을 쓰는 기존 관행을 존중하기 위해서다. 섹션이 없으면 거부한다.
- **헤딩 매칭**: 새 헤딩(`## Lessons`, `## Direct Work`, `## Verification Commands`, `## CQO Verdict`)도 기존 `HEADING2` 정규식으로 찾는다(blockquote 허용, 내용 필터 없음, Hard Rule 22).
- **범위**: Stop 훅은 기존처럼 `latest-active`만 본다. 완료 전이에서만 `mission:<rel>` 범위를 쓴다. tier 없는 legacy 미션에는 새 차단이 생기지 않는다.
- **jq 사용**: 값 삽입은 `--arg`로 하고, 실패하면 non-zero exit(fail-loud 규칙).
- **same-session**: 전이는 허용하되 `progress.log`에 `company-complete | warn | same-session-verification`을 남기고 stderr로 경고한다.
- **기존 게이트**: reachability와 spec-pin은 등급과 무관하게 유지한다.

## 테스트 계획
- **정적 검사**: `node --check bin/init.js`, `node --check scripts/import-agency-agents.js`, 수정한 스크립트마다 `bash -n`, `npm pack --dry-run --cache /private/tmp/walwal-npm-cache`.
- **설치 테스트**: `node ./bin/init.js init --force --project-root /private/tmp/walwal-v7-init-test`를 실행하고 확인한다.
  - 명령은 3개뿐인지.
  - `harness-{ceo,coo,cdo,cto,cqo,ops}/SKILL.md`가 있고 ceo/cto/cqo에 Tier 절이 있는지.
  - AGENTS.md에 등급 표와 Codex 세션 구분이 있는지, `CLAUDE.md` symlink가 유지되는지.
  - `config.json`에 `mission_tiers`가 있는지.
- **스크립트 self-check** (`scripts/` 옆에 assert 방식 셸 하나. `/private/tmp`에 fixture 프로젝트를 만들고 `harness-progress-set.sh` 초기 상태를 `running`으로 둠):
  1. **완료 거부 → 상태 보존**: tier S, `cqo.md` 없음 → `harness-company-complete.sh . x goal-1-a`가 exit 1. `progress.json`의 `conductor.state=running`, `mission-state.active=true`가 그대로인지 확인.
  2. **CQO FAIL**: tier M, worker 보고서 있음, Verdict 마지막 토큰 FAIL → 거부, 상태 보존.
  3. **정정 후 PASS**: Verdict에 `~~FAIL~~` 다음 PASS → 통과, `completed`, `active:false`.
  4. **S 정상**: `cto.md`(Lessons, Direct Work), `cqo.md`(Verification Commands, `Verification Session: separate`, Verdict PASS), workers 없음 → 통과.
  5. **S same-session**: 4와 같은데 `same-session` → 통과, `progress.log`에 warn 줄, stderr 경고.
  6. **S→M 상향**: `tier_history=[{from:S,to:M}]`, `cto.md`에 Direct Work·worker 없음, cqo 평가 worker 있음, PASS → 통과. 평가 worker가 없으면 → 거부.
  7. **S→L 상향**: 6과 같고, 역할 문서가 L 형식(Preflight/Tally, 하위 섹션)이 아니면 거부, 보강하면 통과.
  8. **M→L 상향**: worker 보고서는 seed 형식 그대로, 역할 문서 보강 전 거부, 보강 후 통과. 과거 worker 보고서는 고치지 않는다.
  9. **하향 시도**: `tier:"S"` + `tier_history=[{from:S,to:L},{from:L,to:S}]` → 유효 L 적용, workers 없으면 거부.
  10. **tier 없음(legacy)**: 판정 검사 없이 기존 게이트만 적용(현행 동작). `tier:"X"` → L.
  11. **opt-out**: `mission_tiers=false` + tier S + workers 없음 → 거부.
  12. **인자 없음/backstop**: 활성 미션 없이 인자 없이 호출 → 현행처럼 통과(Stop 훅 backstop 교착 방지).
  13. **경로 검증**: `<mission-rel>`=`../x` 또는 존재하지 않는 경로 → exit 1, 상태 보존.
  14. **cancelled**: lifecycle cancelled + `cqo.md` 없음 → 판정 검사 생략, 통과.
  15. **OPS 비러너블(legacy)**: tier 없는 문서형 미션, `ops.md` 없음 → 새 차단 없음(현행 동작 회귀 방지).
  16. **lessons gate**: 유효 S/M에서 `## Lessons`만 있으면 통과, L에서 `## Lessons`만 있으면 위반.
  17. **Stop 훅**: 4번 fixture로 `harness-stop.sh`에 `conductor.state=running`을 입력 → validator·gate가 block하지 않는지 확인.
- **기존 회귀**: `apps/harness-dashboard`의 vitest(`sandbox-e2e.test.ts`, `company-flow.test.ts`)를 실행한다. 두 테스트 모두 인자 없이 완료 스크립트를 부르므로 그대로 통과해야 한다.
- **실사용 벤치마크** (수동, 결과를 CHANGELOG에 기록):
  - 설치된 테스트 프로젝트에서 같은 소규모 작업(함수 1개 버그 수정과 테스트 추가)을 개선 전 버전과 개선 후 S 등급으로 각각 `/hot-fix` 실행한다.
  - Agent 호출 수, 벽시계 시간, 생성 문서 수를 비교한다.
  - 두 경우 모두 CQO 판정에 실제 명령과 exit code가 있는지 확인한다.
  - 목표: 세션 수 ≥50% 감소, 판정 증거 동등.
- **Open Questions** (구현 후 Owner 판단):
  - 평가 worker 기본 모델을 차등 선언할지.
  - M의 CQO 병렬 착수를 실측한 뒤 L로 확대할지.
  - Codex에서 `codex exec` 기반 CQO 분리를 기본값으로 굳힐지.

## 리뷰 반영
- [반영] S 필수 증거 검사가 실제 완료 경로에 연결되지 않음 — 지적이 맞다.
  - 코드 확인 결과, `harness-company-complete.sh`는 validator를 호출하지 않는다. 명령 문서(goal 10번, submission·hot-fix 12번)는 `active:false`를 먼저 쓰게 한다. lessons gate는 `latest-active`라서 대상 미션이 빠진다. 이는 v7.1.56이 막으려던 우회가 실제로 열려 있다는 뜻이다(진단 D10).
  - 반영 내용: 완료 스크립트가 `<mission-rel>`로 대상을 확정한다. lessons gate, validator(`mission:` scope), CQO 판정 PASS, S 필수 섹션을 전이 **전에** 검사한다. 실패하면 모든 상태를 보존한다.
  - 명령 문서의 선행 `active:false` 지시를 제거한다.
  - 거부와 상태 보존 통합 테스트(1·2·13)를 추가했다.
- [반영] 등급 상향 시 기존 산출물을 새 요구에 맞추는 규칙이 없음 — 지적이 맞다.
  - "당시 등급으로 보존, 이후 작업과 최종 검증은 새 등급"을 명시했다. S의 `## Direct Work` 역할 문서는 worker 요구에서 면제하되 CQO 평가 worker 요구는 유지한다.
  - M→L 충돌은 **worker 보고서 형식을 전 등급 불변**으로 두어 없앴다. seed 템플릿에 하위 섹션이 이미 있어 비용이 거의 없다.
  - 하향은 경고가 아니라 유효 등급 = 최고 등급으로 강제한다.
  - S→M, S→L, M→L, 하향 테스트(6~9)를 추가했다.
- [반영·일부 반박] 별도 검증 세션 불변식이 Codex 어댑터와 충돌함 — 충돌 자체는 맞다(`AGENTS.md.template` §1.1 "execute the role protocol sequentially").
  - 반영 내용: 어댑터를 별도 세션(sub-agent, `codex exec`)과 역할 전환으로 구분했다. CQO에는 별도 세션을 우선 쓰게 했다. `Verification Session` 기록, 완료 시 경고와 로그, Owner 보고 공개 의무를 넣었다.
  - 반박하는 부분은 same-session일 때 완료를 **거부**하자는 수준이다. 같은 어댑터 아래에서는 현행 M/L의 "평가 worker"도 같은 Codex 세션에서 역할만 바꿔 실행된다. 따라서 Hard Rule 9의 독립성은 등급과 무관하게 이미 Codex에서 성립하지 않는다.
  - S만 거부하면 Codex 사용자는 M으로 올라가 worker 의식만 늘고 독립성은 그대로다. 요청(과잉 절차 제거)과 반대다. 그래서 독립 경로를 우선하되 불가하면 기록하고 공개하도록 했다.
- [반영·일부 반박] M 경량화를 다시 무효화하는 하위 스킬 요구가 남음 — resource-manager와 hiring이 변경 목록에서 빠진 것은 맞다.
  - 반영 내용: hiring의 verbatim 대상에서 보고서 골격, Tally, Notes 블록을 빼고 seed 경로 명시로 바꿨다. resource-manager의 Appendix 문구는 "seed 템플릿에 포함됨"으로 바꿨다.
  - 반박하는 부분은 "M의 최소 보고서 형식을 정하라"는 제안이다. `worker-report.md.template`은 이미 모든 섹션을 `None`으로 seed하므로 형식 자체의 작성 비용은 작다. 실제 비용은 브리프에 골격을 다시 복사하는 것(D4)이다.
  - worker 보고서 형식을 등급별로 나누면 리뷰가 지적한 M→L 상향 충돌이 다시 생긴다. 그래서 형식은 불변으로 두고 복사만 없앴다.
- [반영] L의 OPS 무조건 필수화가 기존 동작보다 절차를 늘림 — 맞다.
  - 현행 규칙(`cqo/SKILL.md` "OPS must watch runnable verification", Hard Rule 16)은 러너블 런타임 검증에만 적용된다. "L 필수"와 "S 생략"을 모두 철회하고, OPS는 등급과 무관하게 현행 조건 규칙(I7)을 따르도록 했다. 비러너블은 `OPS N/A: <이유>` 한 줄로 처리한다.
  - tier 없는 비실행형 미션 회귀 테스트(15)를 추가했다.