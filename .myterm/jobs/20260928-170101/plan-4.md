# 미션 규모 등급(Tier) 도입과 절차 경량화: 꼼꼼함은 유지하고 소요 시간은 줄인다 (4차)

## 요약
지금 하네스는 작업 규모와 상관없이 모든 미션에 같은 절차를 강제합니다. 그래서 LLM 단독이면 5분 걸릴 수정도 7~9개의 새 세션을 거칩니다: CEO → hiring → CTO → 개발 worker → CQO → 평가 worker → OPS. 이 설계는 CEO가 intake에서 미션을 **S/M/L 등급**으로 나누게 하고, S와 M에서는 품질에 기여하지 않는 절차를 걷어냅니다. 대상은 worker 계층, 역할 문서 형식, 브리프 verbatim 복사, 핫픽스마다 붙는 gotcha 작성 의무입니다. 꼼꼼함의 핵심은 모든 등급에서 유지합니다. 핵심이란 "만든 사람과 검증한 사람을 분리하고, 실행된 테스트 증거로 판정하는 것"입니다.

기존 결함 하나도 함께 고칩니다. 지금은 완료 게이트가 대상 미션을 놓쳐 그냥 통과합니다(D10). 이번 설계에서 완료 전이는 대상 미션을 명시적으로 받습니다. 그리고 **정상 완료(수락)와 수락 없는 종료(취소·대체·종료)를 검사 전에 분기**합니다. 정상 완료는 **마지막 `Verdict:` 줄**이 형식에 맞고 값이 PASS일 때만 terminal 상태로 넘어갑니다. 마지막 줄이 무효하면 앞의 줄로 거슬러 올라가지 않고 거부합니다.

## 요구 분석
- 시스템 전체를 진단해 과도한 프로세스가 어디서 시간을 쓰는지 찾는다.
- 꼼꼼함(검증 품질, 증거 기반 판정)은 유지한다.
- 시간을 줄일 방안을 내고, 구현할 수 있는 수준까지 설계한다.
- 좋은 모델의 능력을 막는 과잉 설계를 짚어낸다.

### 진단: 시간을 먹는 지점 (코드 근거)
| # | 과잉 지점 | 근거 | 비용 |
|---|---|---|---|
| D1 | **규모에 따른 예외가 전혀 없음.** "Small scope is not an exemption", 핫픽스의 "even when the fix is small" | `HR-Resource/ceo/SKILL.md`, `commands/hot-fix.md` 8번 | 한 줄 수정도 파이프라인 전체를 거침 |
| D2 | **CXX 직접 실행 금지, worker 강제.** validator가 `{cxx}.md`마다 worker 보고서를 요구함 | Hard Rule 8·9, `harness-worker-evidence-validate.sh`의 `has_worker_report` | Opus급 CXX가 작업마다 브리핑을 다시 쓰고 새 세션을 띄움. **좋은 모델의 능력을 가장 크게 막는 지점** |
| D3 | **모든 계층에 붙는 문서 의식.** 역할 문서마다 Lessons Preflight/Tally와 Implementation Notes 하위 섹션 4개가 필수 | `has_implementation_notes`, `harness-lessons-gate.sh`, `cqo/SKILL.md` | 형식 작성에 턴을 쓰고, 빠지면 재작성 루프가 돎 |
| D4 | **verbatim 전파.** 보고서 골격, Tally, Notes 블록을 브리프에 그대로 복사해야 함 | `hiring/SKILL.md`, `ops/SKILL.md` "Propagate verbatim", Hard Rule 20 | seed된 보고서 파일에 이미 있는 내용을 또 넣음 |
| D5 | **worker마다 붙는 부수 작업.** seed, telemetry, model 선언, roster 등록 | `cto/SKILL.md`, `hiring/SKILL.md` | worker 1명당 셸·쓰기 작업 5~8회 |
| D6 | **핫픽스마다 gotcha 등록 의무** | `hot-fix.md` 11번 | 문서가 계속 늘고 읽기 비용도 커짐 |
| D7 | **스킬 본문의 중복 서사** | CEO/CTO/CQO SKILL 후반부, AGENTS 템플릿 | 세션마다 같은 5~8KB를 다시 적재 |
| D8 | **CXX 전원 호출로 읽히는 문장** | `goal.md` 5번 | 필요 없는 세션이 생김 |
| D9 | **직렬 파이프라인.** CQO는 CTO가 끝나야 계획을 시작함 | `ceo/SKILL.md` | 병렬로 할 수 있는 계획 단계가 기다림 |
| D10 | **(결함) 완료 게이트 우회.** 명령 문서가 `active:false`를 먼저 쓰게 하는데, 게이트는 `latest-active`만 봄. validator는 완료 경로에서 호출되지 않음 | `goal.md` 10번, `submission.md`·`hot-fix.md` 12번, `harness-company-complete.sh` 40행 | 마지막 관문이 비어 있음 |

### 유지할 꼼꼼함 (등급과 무관한 불변식)
- **I1** 구현자와 판정자를 분리한다. CQO 판정은 구현 세션과 다른 세션에서 낸다. 이를 보장할 수 없는 런타임에서는 그 사실을 기록하고 공개한다.
- **I2** 판정 근거는 실행 증거여야 한다. 명령, exit code, 출력 발췌가 있어야 한다.
- **I3** 변경 범위 테스트를 실행하고, 풀 스위트 명령이 있으면 그것도 실행한다.
- **I4** Owner를 테스터로 쓰지 않는다(Hard Rule 15).
- **I5** 루프는 runtime 전이로만 종료한다(Hard Rule 19). **정상 완료 전이는 대상 미션의 마지막 판정 줄이 유효하고 PASS일 때만 성공한다.**
- **I6** Playwright는 headed로 실행한다(Hard Rule 18).
- **I7** OPS watch와 OPS worker 증거 규칙은 현행 그대로다. 등급과 무관하게, 러너블 런타임을 대상으로 한 검증에 적용한다.

## 모호점과 해소안
- **등급은 누가 정하나** → CEO가 intake에서 `mission-state.json`의 `tier`(`"S"|"M"|"L"`)에 기록하고, `ceo.md`에 근거를 한 줄 남긴다. Owner에게는 묻지 않는다.
  - **S**: 예상 변경 파일 3개 이하 또는 약 150줄 이하. 새 의존성·외부 스펙이 없다. auth·결제·보안·데이터 마이그레이션·인프라·포트 신규 할당이 없다. 기존 테스트 명령으로 검증할 수 있다.
  - **L**: 새 서비스·포트, 외부 스펙 연동, operating goal, 프로덕션 배포, 보안·결제·데이터 변경 중 하나라도 해당한다.
  - **M**: 나머지 전부.
- **tier 필드가 없는 미션(legacy)** → L로 취급한다. 완료 전이의 신규 검사(판정 줄, S 섹션, mission 범위 validator)도 적용하지 않는다. 기존 동작과 기존 테스트(`sandbox-e2e.test.ts`, `company-flow.test.ts`)를 그대로 보존하기 위해서다.
- **유효 등급** → 순위를 명시한다: `S=0, M=1, L=2`. 그 밖의 값과 누락은 2다.
  - 계산 대상은 현재 `tier`, 그리고 `tier_history[]`의 `from`과 `to` **모두**다. 이 중 최고 순위가 유효 등급이다.
  - 그래서 최초 L을 `tier:"S"` + `{from:"L",to:"S"}`로 기록해도 유효 등급은 L이다. 하향 기록은 효력이 없다.
  - `behavior.mission_tiers=false`면 모든 미션이 L이다.
  - jq의 문자열 `max`는 쓰지 않는다. 문자 순서(L<M<S)가 등급 순서와 다르기 때문이다.
- **상향 시 기존 산출물 처리** → 원칙: *상향 전에 끝낸 작업은 당시 등급 기준으로 보존하고, 상향 이후 작업과 최종 검증은 새 등급 기준을 따른다.* CEO는 `tier`를 올리고 `tier_history`에 `{from,to,at,reason}`을 추가한다.
  - **worker 보고서 형식은 전 등급에서 현행 그대로다.** seed 템플릿에 하위 섹션 4개가 `None`으로 이미 들어 있으므로, M→L 상향 때 과거 worker 보고서를 고칠 일이 없다.
  - **S→M/L, CTO 면제 범위**: S에서 한 직접 구현은 `cto.md`의 `## Direct Work` 섹션에 있다. 면제는 **이 섹션의 상향 시점 내용에만** 적용한다.
    - 상향할 때 CEO는 `harness-worker-evidence-validate.sh . direct-work-sha mission:<rel>`의 출력을 `tier_history` 항목의 `direct_work_sha256`에 기록한다. 이 값이 없으면 면제도 없다(fail closed).
    - 완료 시점에 `## Direct Work` 본문의 sha256이 기록값과 다르면, 상향 후 구현이 Direct Work에 덧붙은 것으로 보고 거부한다.
    - 상향 후 CTO는 `## Post-Upgrade Work` 섹션을 쓴다. 추가 구현 없이 재검증만 했다면 첫 줄을 `none — <이유>`로 쓰고, CTO worker 없이 통과한다.
    - 그 밖의 내용이 있으면 추가 구현이 있다는 뜻이므로 CTO worker 보고서가 1개 이상 있어야 한다. 섹션이 없어도 거부한다.
    - CQO는 이 면제 대상이 아니다. 새 등급의 `cqo-verdict-without-evaluator`(평가 worker 필수)가 그대로 적용된다.
  - **M→L**: 역할 문서만 L 형식으로 보강한다. Preflight/Tally와 Implementation Notes 하위 섹션 4개를 넣는 편집 한 번이면 된다.
  - 상향 트리거: 기준 초과, 위험 영역 접촉, CQO FAIL 2회.
- **S에서 CXX 직접 실행 vs Hard Rule 8·9** → "유효 등급 S에서는 CTO가 직접 구현하고, CQO가 **별도 세션에서** 테스트를 직접 실행해 판정한다"로 바꾼다. **직접 실행 허용은 CTO와 CQO에만 해당한다.** COO/CDO/OPS가 S 미션에 참여하면 현행 worker 규칙을 따른다.
- **S의 OPS** → 러너블 런타임 검증이 있으면 등급과 무관하게 현행 OPS watch를 적용한다. OPS의 worker 배정·hiring·증거 요구도 그대로다(I7). 따라서 S의 "hiring 호출 안 함"은 "CTO/CQO를 위한 hiring 안 함"으로 한정한다. 이 때문에 S 러너블 검증 미션은 세션이 하나 늘지만, 런타임 감시라는 꼼꼼함을 우선한다.
- **판정 형식** → `## CQO Verdict` 섹션 안에 전용 판정 줄 `Verdict: <PASS|ACCEPTED|FAIL|REJECTED|BLOCKED>`를 둔다(대문자, 줄 전체가 이 형식).
  - **2단계로 판정한다. 후보를 먼저 모으고, 마지막 후보 하나만 엄격하게 검증한다.**
    1. **후보 줄**: 모든 `## CQO Verdict` 섹션에서, 앞쪽 공백·인용 `>`·목록 기호 `-`/`*`·강조 `*`/`_`를 벗겨낸 뒤 대소문자 구분 없이 `verdict:`로 시작하는 줄이다. 판정을 **쓰려고 한** 줄은 형식이 틀려도 전부 후보가 된다. 예: `Verdict: FAIL (회귀 발견)`, `Verdict:`, `**Verdict: FAIL**`, `verdict: fail`.
    2. **최종 판정**: 문서 순서상 **마지막 후보 줄**만 쓴다. 이 줄의 원문이 엄격한 형식 `^[[:space:]]*>?[[:space:]]*Verdict:[[:space:]]*(PASS|ACCEPTED|FAIL|REJECTED|BLOCKED)[[:space:]]*$`에 맞지 않으면 `invalid-final-verdict` 사유로 거부한다. **앞의 유효한 줄로 거슬러 올라가지 않는다.**
  - 판정을 정정할 때는 이전 줄을 `~~Verdict: FAIL~~`로 지우고 새 `Verdict:` 줄을 추가한다. 취소선 줄은 `~~`로 시작하므로 후보가 아니다. 취소선을 쓰지 않은 과거 줄은 후보로 남지만, 마지막 줄만 판정에 쓰므로 결과에는 영향이 없다.
  - 후보가 하나도 없으면 `missing-verdict` 사유로 거부한다. 설명문 안에 들어 있는 `PASS` 토큰은 `verdict:`로 시작하지 않으므로 후보가 되지 않는다.
  - 이 검사는 tier가 있는 미션에만 적용한다. legacy `cqo.md`는 깨지지 않는다.
- **S에서 CQO self-verification** → 직접 실행한 명령 결과로 판정하는 것은 허용한다. 눈으로 훑어본 LLM 검사로 판정하는 것은 금지한다. `cqo.md` 필수 항목은 다음과 같다.
  - `## Verification Commands`: 명령 / exit code / 출력 발췌.
  - `Verification Session: separate|same-session` 한 줄.
- **Codex 세션 분리** → 2차 설계를 유지한다.
  - 별도 세션(Claude Agent, Codex sub-agent, `codex exec`)을 우선한다.
  - 별도 세션이 불가능하면 `same-session`을 기록한다. 이때 완료는 허용하되 경고와 로그를 남기고 Owner 보고에서 공개한다(리뷰가 수용함).
- **종료 유형 분기** → 완료 스크립트는 검사를 시작하기 **전에** 대상 lifecycle로 경로를 나눈다.
  - **정상 완료(수락)**: lifecycle이 `cancelled|superseded|closed`가 아닌 경우다. 신규 검사를 모두 실행하고, 통과하면 스크립트가 `complete`/`active:false`를 기록한다.
  - **수락 없는 종료**: lifecycle이 `cancelled|superseded|closed`인 경우다. 명령 문서가 lifecycle과 `active:false`를 먼저 쓰고 스크립트를 부른다. 스크립트는 mission 범위 검사(lessons·validator·판정·S 섹션·spec-pin)를 **하나도 실행하지 않고**, lifecycle을 보존한다(기존 `case` 문이 이미 보존함). `progress.log`에는 `company-complete | ended-without-acceptance | <lifecycle>`을 남긴다.
  - 전역 검사인 corpus reachability는 현행대로 두 경로 모두에 유지한다.
- **`closed`의 의미** → "수락 없이 끝남"이다(Owner 중단, 다른 미션에 흡수 등). 수락된 작업은 반드시 `complete` 경로를 탄다.
  - `closed`로 판정 검사를 회피하면 기록에 드러난다. log 줄과 문서 lifecycle에 남고, Owner 보고에 "미수락 종료"를 명시할 의무가 있다.
  - Hard Rule 4에 따라 PASS 없이는 archive도 할 수 없다.
- **Lessons 형식** → 계획 전에 읽는 순서는 모든 등급에서 유지한다. 유효 등급 S/M 역할 문서는 `## Lessons` 한 섹션(Preflight/Fired 두 줄)으로 대신할 수 있다. L은 현행 그대로다.
- **Implementation Notes** → 유효 등급 S/M 역할 문서는 `## Implementation Notes` 헤딩과 bullet 요약이면 충분하다. L 역할 문서와 모든 worker 보고서는 현행 형식을 유지한다.
- **브리프 verbatim 복사(D4)** → 보고서 골격, Tally, Notes 블록은 "seed된 보고서 경로를 채워라" 한 줄로 대신한다. 브라우저 규칙처럼 **보고서에 들어 있지 않은 행동 규칙**만 계속 verbatim으로 넣는다.
- **핫픽스 gotcha(D6)** → 재발 가능하거나 원인이 비자명할 때만 등록한다. 그 밖에는 `cqo.md` Recurrence Notes에 `none — <이유>`를 쓴다.
- **완료 전이 대상** → `harness-company-complete.sh . <reason> <mission-rel>`로 대상을 넘긴다. 인자가 없으면 기존 선택 로직과 기존 게이트를 그대로 쓴다(Stop 훅 backstop, 기존 호출자와 호환).
- **범위 밖**: 이 저장소의 `AGENTS.md`, 명령 개수, worker 기본 모델(Open Question으로 남김).

### 등급별 흐름 (목표 상태)
| 단계 | S | M | L (현행) |
|---|---|---|---|
| CEO | 메인 세션, 짧은 `ceo.md` | 동일 | 현행 |
| COO/CDO | 호출 안 함 | 필요할 때만(worker 규칙 현행) | 필요할 때만 |
| CTO | 새 세션, **직접 구현**, `cto.md`(Lessons, Direct Work, CQO Handoff) | worker 1~N | 현행 |
| CQO | **별도 세션**, 직접 테스트 실행, `Verification Commands`·`Verification Session`·`Verdict:` | 평가 worker 1명, CTO와 병렬로 게이트 초안 작성 | 현행 |
| OPS | 러너블 검증일 때만, **현행 worker 규칙** | 동일 | 동일 |
| gotcha | 신호가 있을 때만 | 신호가 있을 때만 | 현행 |
| 정상 완료 | 마지막 `Verdict:` 줄 유효·PASS + S 섹션 + 참여한 COO/CDO/OPS의 worker 증거 | 마지막 `Verdict:` 줄 유효·PASS + worker 증거 | 동일(tier 없으면 현행) |
| 수락 없는 종료 | mission 검사 없음, lifecycle 보존 | 동일 | 동일 |
| 예상 세션 수 | **2~3**(OPS가 필요하면 +1~2) | 4~5 | 7~9 |

## 변경 파일
- `scripts/harness-company-complete.sh`
  - 3번째 인자 `<mission-rel>`을 선택적으로 받는다. 경로를 검증한 뒤 대상을 확정한다. 인자가 없으면 기존 `pick_transition_mission_state`를 쓴다.
  - **분기(검사 시작 전)**: 대상 lifecycle이 `cancelled|superseded|closed`면 수락 없는 종료다. mission 범위 검사를 모두 건너뛰고 reachability만 검사한다. `ended-without-acceptance` 로그를 남기고 runtime 전이를 한다. mission-state는 건드리지 않는다.
  - **정상 완료이고 tier가 있으면**, `harness-progress-set.sh`를 호출하기 **전에** 아래를 순서대로 검사한다. 하나라도 실패하면 `exit 1`로 끝나고 상태 파일은 전혀 수정하지 않는다.
    1. lessons gate(`mission:<rel>`).
    2. validator(`mission:<rel>`).
    3. 판정: 마지막 후보 `Verdict:` 줄이 엄격 형식에 맞고 값이 PASS 또는 ACCEPTED여야 한다.
    4. 유효 등급 S: `cto.md`에 `## Direct Work`가 있어야 하고, `cqo.md`에 `## Verification Commands`와 `Verification Session:` 줄이 있어야 한다. `same-session`이면 경고하고 로그를 남긴다.
    5. 기존 spec-pin 검사를 확정된 대상에 대해 실행한다.
  - 마지막 단계(`complete`/`active:false` 기록)도 확정된 대상을 쓴다.
  - 거부하면 `company-complete | refused | <사유>`를 로그에 남긴다. 대상 문서에 `complete`가 이미 쓰여 있으면, 거부 메시지에 "`active:true`로 되돌리고 다시 시도"를 안내한다.
  - **판정 추출은 awk 한 블록이다.**
    - 섹션 진입 조건은 `^[[:space:]]*>?[[:space:]]*##[[:space:]]+CQO Verdict[[:space:]]*$`이다. validator의 `HEADING2`와 같은 형식이다. 이 상수는 완료 스크립트에 없으므로 같은 정규식을 로컬에 둔다. 다른 `#` 헤딩이 나오면 섹션을 벗어난다.
    - 섹션 안에서 각 줄의 앞쪽 `[[:space:]>*_-]`를 벗기고 `tolower`한 결과가 `verdict:`로 시작하면 후보다. 원문을 `last`에 덮어쓴다.
    - 끝(`END`)에서 `last`가 비어 있으면 `missing`을 출력한다. 엄격 정규식에 맞으면 값을 출력하고, 맞지 않으면 `invalid`를 출력한다.
    - 셸은 `PASS|ACCEPTED`일 때만 통과시킨다. `missing`/`invalid`/그 밖의 값이면 각각 `missing-verdict`, `invalid-final-verdict`, `verdict-not-pass` 사유로 거부한다.
- `scripts/harness-worker-evidence-validate.sh`
  - scope `mission:<rel>`을 추가한다. 해당 디렉터리만 보고, active 여부는 따지지 않는다.
  - mode `direct-work-sha`를 추가한다. `cto.md`의 `## Direct Work` 본문의 sha256을 출력하고, 섹션이 없으면 exit 1이다.
  - 유효 등급은 jq 한 식으로 계산한다: `def r: if .=="S" then 0 elif .=="M" then 1 else 2 end; [.tier, (.tier_history[]?|.from,.to)] | map(r) | max`. `mission_tiers=false`면 2다.
  - **S**: worker 보고서 요구와 `cqo-verdict-without-evaluator`를 **cto·cqo에만** 생략한다. coo/cdo/ops 문서가 있으면 현행대로 검사한다. 역할 문서의 Implementation Notes는 `##` 헤딩만 검사한다.
  - **M**: 역할 문서의 Implementation Notes 하위 섹션 검사를 생략한다. worker 보고서 요구는 유지한다.
  - **M/L이면서 이력에 `from:"S"`가 있을 때 CTO 면제**: 다음 세 조건을 모두 만족해야 한다.
    1. 해당 이력 항목에 `direct_work_sha256`이 있다.
    2. 현재 `## Direct Work`의 sha가 그 값과 같다.
    3. `## Post-Upgrade Work`의 첫 줄이 `none`으로 시작하거나, cto worker 보고서가 1개 이상 있다.
  - 조건이 하나라도 어긋나면 `cto-post-upgrade-work-without-worker` 또는 `cto-direct-work-modified-after-upgrade` 위반이다. cqo는 면제하지 않는다.
  - L과 worker 보고서 형식 검사는 현행 그대로다.
- `scripts/harness-lessons-gate.sh` — scope `mission:<rel>`을 추가한다. 유효 등급 S/M은 `## Lessons` 또는 Preflight+Tally를 인정하고, L은 현행 그대로다. 유효 등급 계산은 validator와 같은 jq 식을 쓴다.
- `scripts/harness-stop.sh` — 차단 문구만 등급별 요구에 맞게 고친다. 판정 검사는 넣지 않는다(완료 전이 전용).
- `commands/goal.md`, `submission.md`, `hot-fix.md`
  - intake 단계에서 `tier`를 분류해 기록한다.
  - **정상 완료**: `active:false`를 먼저 쓰지 않고 `harness-company-complete.sh . <reason> <mission-rel>`을 부른다. 거부되면 미션은 active로 남고 작업을 계속한다.
  - **수락 없는 종료**: `cancelled|superseded|closed`와 `active:false`를 먼저 쓰고 같은 명령을 부른다. `closed`를 "수락 없이 끝남"으로 정의하고, Owner 보고에 "미수락 종료"를 명시하게 한다.
  - "ask COO, CDO, CTO, and CQO"를 "필요한 CXX만"으로 바꾼다.
  - worker 강제 단계에 "유효 등급 M/L, 그리고 S의 COO/CDO/OPS"라는 한정을 붙이고, S의 CTO/CQO 대체 문장을 넣는다.
  - hot-fix 11번을 신호 기반으로 바꾼다.
  - Codex adapter에 CQO 별도 세션 우선 문장을 넣는다.
  - verbatim 범위를 행동 규칙으로 좁힌다.
- `HR-Resource/ceo/SKILL.md`
  - "Mission Tier" 절을 추가한다. 기준, 순위 기반 유효 등급, 상향 절차(`direct_work_sha256` 기록 포함), 등급별 라우팅을 담는다.
  - "no scope exemption"을 "등급이 절차 깊이를 정한다. I1~I7은 불변"으로 바꾼다.
  - 정상 완료와 수락 없는 종료의 호출 형식을 적고, closed·same-session 공개 의무를 넣는다.
  - 중복 서사를 줄인다.
- `HR-Resource/cto/SKILL.md`
  - "Tier S: Direct Work" 절을 추가한다. 테스트 실행과 CQO Handoff는 필수다.
  - 상향 후 규칙을 적는다: `## Direct Work`는 동결하고, 추가 구현은 worker가 하며, `## Post-Upgrade Work`를 작성한다.
  - Required output을 L 기준과 S/M 축약본으로 나눈다.
- `HR-Resource/cqo/SKILL.md`
  - Required output 6번을 바꾼다: "`## CQO Verdict` 안에 `Verdict: <값>` 전용 줄 필수. **문서의 마지막 `Verdict:` 줄이 판정이며, 이 줄이 형식에 어긋나면(부가 문구, 빈 값, 굵게 표시, 소문자) 완료가 거부된다.** 정정은 취소선 후 새 줄로 한다. 판정 사유는 판정 줄이 아닌 다음 줄에 쓴다."
  - "Tier S: Direct Verification" 절을 추가한다. 별도 세션 우선, Verification Commands·Session 필수.
  - M에서 병렬 게이트 초안을 허용한다. Recurrence Notes에 `none — 이유`를 허용한다.
  - OPS 절은 현행 문구를 유지하고, 비러너블일 때 `OPS N/A: <이유>`를 명시한다.
- `HR-Resource/hiring/SKILL.md`
  - "유효 등급 S에서 **CTO/CQO를 위한** hiring은 하지 않는다. COO/CDO/OPS worker는 현행 그대로다"를 추가한다.
  - verbatim 대상에서 보고서 골격, Tally, Notes 블록을 빼고 seed 경로 명시로 바꾼다. 거절 조건도 이에 맞춘다.
- `HR-Resource/resource-manager/SKILL.md` — Appendix를 "seed 템플릿에 포함됨. assignment에는 보고서 경로를 반환"으로 바꾼다.
- `HR-Resource/ops/SKILL.md` — "Propagate verbatim" 목록의 seed 골격, Tally, Notes 블록을 "seed된 보고서 경로"로 바꾼다(D4와 일관). OPS의 worker·watch 규칙은 변경하지 않는다.
- `assets/templates/AGENTS.md.template`, `AGENTS-ko.md.template`
  - §1.1: 별도 세션과 역할 전환을 구분한다.
  - §5: 등급 표를 추가한다.
  - Hard Rule 4: "PASS는 **마지막** `Verdict:` 전용 줄. 형식이 어긋나면 거부"를 명시한다.
  - Hard Rule 8·9: "유효 등급 M/L. S에서는 CTO/CQO만 직접 실행"으로 바꾼다.
  - Hard Rule 12·20: 등급별 역할 문서 형식과 verbatim 범위를 반영한다.
  - Hard Rule 19: 정상 완료와 수락 없는 종료의 호출 형식을 넣는다.
  - Hard Rule 16은 변경하지 않는다.
- `assets/templates/config.json` — `behavior.mission_tiers: true`를 추가하고, null 비교 패턴을 쓴다.
- `CHANGELOG.md`, `package.json` — 7.1.58.
- 변경하지 않는 것: `bin/init.js`(새 파일이 없음), 이 저장소의 `AGENTS.md`, `worker-report.md.template`, 명령 개수.

## 검증 규칙
- **tier 값**: `S|M|L` 이외의 값과 누락은 순위 2(L)로 본다. 차단 사유에 "unknown tier → L"을 표기한다. 단, `tier` 필드 자체가 없으면 legacy 경로다.
- **유효 등급**: `max(rank(tier), rank(history[].from), rank(history[].to))`. 문자열 비교는 쓰지 않는다.
- **opt-out**: `mission_tiers=false`면 전부 L이다. `if … == null then true else … end` 패턴을 쓴다.
- **완료 원자성**: 모든 검사는 `harness-progress-set.sh` 호출 전에 끝낸다. 거부되면 `progress.json`, `todos/state.json`, `mission-state.json` 중 어느 것도 수정하지 않는다.
- **분기 순서**: lifecycle 판별 → (수락 없는 종료면 reachability만) → (정상 완료면 신규 검사와 spec-pin) → 전이. 수락 없는 종료가 완료용 검사에 막히는 경로는 없다.
- **대상 경로**: `.harness/documents/` 아래에 이미 있는 디렉터리여야 하고, `mission-state.json`이 있어야 한다. `..`이 들어가거나 절대경로면 `exit 1`이다.
- **판정 줄**
  - 후보는 `## CQO Verdict` 섹션들 안에서 앞쪽 장식(공백, `>`, `-`, `*`, `_`)을 벗긴 뒤 대소문자 무시로 `verdict:`로 시작하는 줄이다. 취소선(`~~`) 줄은 후보가 아니다.
  - 판정은 **마지막 후보 하나**다. 그 줄이 엄격 형식(`Verdict: <대문자 5종>`, 뒤에 공백만 허용)에 맞지 않으면 거부한다. 이전 후보로 fallback하지 않는다(fail closed).
  - 후보가 없으면 거부한다. 설명문 토큰은 무시한다.
- **Direct Work 동결**: sha 입력은 섹션 본문(헤딩 다음 줄부터 다음 헤딩 전까지)이다. 줄 끝 공백을 정규화하지 않고 바이트 그대로 쓴다. sha 기록이 없으면 면제하지 않는다.
- **Post-Upgrade Work**: 첫 비공백 줄이 `none`으로 시작하면 추가 구현이 없는 것으로 본다. 그 밖의 내용이 있거나 섹션이 없으면 cto worker 보고서를 요구한다.
  - `ponytail:` 이 판단은 문서 선언에 의존한다. 다른 문서 게이트와 같은 신뢰 수준이다. 실제 동작은 새 등급의 CQO 평가 worker가 독립적으로 재검증한다. 코드 차분(git) 기반 검증은 우회 사례가 관측되면 추가한다.
- **S의 worker 면제 범위**: cto·cqo만 면제한다. coo/cdo/ops 문서가 있으면 현행 검사를 적용한다.
- **범위**: Stop 훅은 `latest-active`, 완료 전이는 `mission:<rel>`을 쓴다. legacy 미션에는 새 차단이 없다.
- **jq**: 값 삽입은 `--arg`로 하고, 실패하면 non-zero로 끝낸다.
- **same-session**: 전이는 허용한다. `company-complete | warn | same-session-verification`을 로그에 남기고 stderr로도 경고한다.

## 테스트 계획
- **정적 검사**: `node --check bin/init.js`, `node --check scripts/import-agency-agents.js`, 수정한 스크립트마다 `bash -n`, `npm pack --dry-run --cache /private/tmp/walwal-npm-cache`.
- **설치 테스트**: `node ./bin/init.js init --force --project-root /private/tmp/walwal-v7-init-test`를 실행한 뒤 아래를 확인한다.
  - 명령이 3개뿐이다.
  - `harness-{ceo,coo,cdo,cto,cqo,ops}/SKILL.md`가 있고, ceo/cto/cqo에 Tier 절이 있다.
  - AGENTS.md에 등급 표와 "마지막 `Verdict:` 줄" 규칙이 있다.
  - `CLAUDE.md` symlink가 유지된다.
  - `config.json`에 `mission_tiers`가 있다.
- **스크립트 self-check**: assert 방식 셸 하나를 만든다. `/private/tmp` fixture를 쓰고, 초기 상태는 `running`이다.
  - **판정 파서**
    1. `Verdict: FAIL` + 설명문 "수정 후 PASS 가능" → 거부.
    2. `Verdict: PASS` + 설명문 "이전 FAIL 원인 해결" → 통과.
    3. `~~Verdict: FAIL~~` 다음 `Verdict: PASS` → 통과.
    4. `Verdict: PASS` 다음 `Verdict: FAIL`(재판정) → 거부.
    5. 전용 줄 없이 본문에 "PASS"만 있음 → 거부(`missing-verdict`).
    6. 단독 `Verdict: PASSED`, `Verdict: pass`, `Verdict: PASS (조건부)` → 거부(`invalid-final-verdict`).
    7. `## CQO Verdict` 섹션이 2개이고 두 번째 섹션에 최종 줄이 있음 → 두 번째 섹션 값 적용.
    8. **`Verdict: PASS` 다음 `Verdict: FAIL (회귀 발견)`** → 거부(`invalid-final-verdict`). 앞의 PASS로 돌아가지 않는다.
    9. **`Verdict: PASS` 다음 빈 `Verdict:`** → 거부.
    10. **`Verdict: PASS` 다음 `**Verdict: FAIL**`, 또는 `- verdict: fail`** → 거부.
    11. **섹션 2개: 첫 섹션 `Verdict: PASS`, 두 번째 섹션 마지막 줄 `Verdict: FAIL — 재현됨`** → 거부.
    12. `Verdict: FAIL` 다음 `> Verdict: PASS`(인용) → 통과.
  - **완료 원자성**
    13. tier S이고 `cqo.md`가 없음 → exit 1. `conductor.state=running`, `active:true`가 그대로다.
    14. `<mission-rel>`이 `../x`이거나 존재하지 않음 → exit 1, 상태 보존.
    15. 8번 fixture로 거부된 뒤 상태 파일 3종이 변경되지 않았는지 확인한다.
  - **수락 없는 종료**
    16. S/M/L 각각에 대해 CQO 착수 전의 미완성 문서(`cqo.md` 없음, worker 없음)를 두고 `cancelled`·`superseded`·`closed` 3종을 시험한다. 모두 통과하고, lifecycle이 보존되며, `ended-without-acceptance` 로그가 남는다. `conductor.state=completed`다.
  - **S 정상과 OPS**
    17. S 정상: `cto.md`(Lessons, Direct Work), `cqo.md`(Verification Commands, `Verification Session: separate`, `Verdict: PASS`), worker 없음 → 통과.
    18. S same-session → 통과, warn 로그, stderr 경고.
    19. S + 러너블 검증으로 `ops.md` 있음 + ops worker 없음 → 거부(`ops.md` 위반). ops worker를 추가하면 통과한다. cto/cqo worker는 계속 없는 상태로 둔다.
    20. S + `cdo.md` 있음 + cdo worker 없음 → 거부.
  - **유효 등급**
    21. `tier:"S"` + `[{from:"L",to:"S"}]` → L 적용, worker가 없으므로 거부.
    22. `tier:"S"` + `[{from:"M",to:"S"}]` → M 적용.
    23. `tier:"S"` + `[{from:"S",to:"L"},{from:"L",to:"S"}]` → L.
    24. 이력 값이 `"X"` → L.
    25. `tier:"X"` → L.
    26. `mission_tiers=false` + tier S → L.
  - **상향 면제 범위**
    27. S→M, `direct_work_sha256` 일치 + `## Post-Upgrade Work: none — 재검증만` + cqo 평가 worker + PASS → 통과.
    28. 27과 같은데 Direct Work에 줄을 추가함(sha 불일치) → 거부(`cto-direct-work-modified-after-upgrade`).
    29. 27과 같은데 Post-Upgrade Work에 구현 내용이 있고 cto worker가 없음 → 거부. cto worker를 추가하면 통과.
    30. `direct_work_sha256`이 기록되지 않음 → cto worker 요구(거부).
    31. 27과 같은데 cqo 평가 worker가 없음 → 거부.
    32. S→L: 역할 문서가 L 형식이 아니면 거부, 보강하면 통과.
    33. M→L: worker 보고서는 seed 형식 그대로 두고, 역할 문서 보강 전에는 거부, 보강 후에는 통과.
  - **호환**
    34. tier 없음(legacy): 판정 줄 검사 없이 현행 동작.
    35. 인자 없이 호출하고 활성 미션이 없음 → 현행처럼 통과(backstop).
    36. legacy 비러너블 미션, `ops.md` 없음 → 새 차단 없음.
    37. lessons gate: S/M은 `## Lessons`만 있어도 통과, L은 위반.
    38. Stop 훅에 17번 fixture를 넣음 → block하지 않음.
    39. `direct-work-sha` 모드: 섹션이 없으면 exit 1이고, 같은 입력이면 같은 출력.
- **기존 회귀**: `apps/harness-dashboard`의 vitest(`sandbox-e2e.test.ts`, `company-flow.test.ts`)를 실행한다. 둘 다 인자 없이 완료 스크립트를 호출하므로 그대로 통과해야 한다.
- **실사용 벤치마크**(수동, 결과는 CHANGELOG에 기록)
  - 함수 1개 버그 수정과 테스트 추가를 개선 전 버전과 S 등급 `/hot-fix`로 각각 실행한다.
  - Agent 호출 수, 벽시계 시간, 생성 문서 수를 비교한다.
  - 두 경우 모두 판정에 실제 명령과 exit code가 있는지 확인한다.
  - 목표: 세션 수 50% 이상 감소, 판정 증거 동등.
- **Open Questions**
  - 평가 worker 기본 모델을 등급별로 차등 선언할지.
  - M의 CQO 병렬 착수를 L로 확대할지.
  - `codex exec` 기반 CQO 분리를 기본값으로 굳힐지.
  - 상향 후 구현 판정을 git 차분 기반으로 강화할지.

## 리뷰 반영
- [반영] 최신 판정 줄이 무효이면 과거 PASS가 다시 적용됨 — 맞는 지적이다. 3차의 awk는 엄격 정규식에 맞는 줄만 모은 뒤 마지막 값을 썼다. 그래서 `Verdict: PASS` 뒤의 `Verdict: FAIL (회귀 발견)`은 추출에서 빠지고 과거 PASS가 살아난다. "무효 값은 거부"라는 규칙과 모순이었다.
  - 판정을 **후보 수집 → 마지막 후보만 엄격 검증**의 2단계로 바꿨다(모호점 "판정 형식", 변경 파일의 awk 절, 검증 규칙 "판정 줄").
  - 후보는 앞쪽 장식을 벗긴 뒤 대소문자 무시로 `verdict:`로 시작하는 줄이다. 판정을 쓰려고 한 줄이면 형식이 틀려도 후보가 되므로, 굵게 표시·소문자·부가 문구를 쓴 FAIL도 PASS를 덮는다.
  - 마지막 후보가 무효하면 `invalid-final-verdict`로 거부하고 fallback하지 않는다. 취소선 줄만 후보에서 빠진다.
  - 리뷰가 요구한 사례(PASS → 무효 FAIL, PASS → 빈 `Verdict:`, 여러 섹션 중 마지막이 무효)를 테스트 8·9·11에 넣었다. 장식 변형(10), 인용 줄 정상 통과(12), 거부 시 상태 보존(15)도 추가했다.
  - cqo SKILL 6번과 Hard Rule 4에 "마지막 줄이 판정이며 형식이 어긋나면 거부"와 "사유는 다음 줄에"를 명시해, CQO가 이 규칙에 걸리지 않게 작성법을 안내한다.
  - 부수 정정: 3차는 "기존 HEADING2 패턴을 쓴다"고 했지만, 이 상수는 `harness-worker-evidence-validate.sh:18`에만 있고 `harness-company-complete.sh`에는 없다. 완료 스크립트에 같은 정규식을 로컬로 두도록 고쳐 적었다.