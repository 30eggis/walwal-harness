# Claude 리뷰 (4차)

**판정:** 수정 요청

설계 항목은 대부분 코드에 있습니다. 명시적 대상 완료, 수락 없는 종료 분기, 순위 기반 유효 등급, S의 CTO/CQO 면제, 상향 시 Direct Work SHA 동결, 거부 시 상태 보존이 모두 구현되어 있고, tests/mission-tiers.sh 77개 사례가 실제로 통과합니다. 문제는 판정 파서가 설계의 약속과 달리 일부 흔한 Markdown 판정 표기를 후보로 잡지 못한다는 점입니다. 예를 들어 `Verdict: PASS` 뒤에 `**Verdict**: FAIL`을 쓰면 최신 FAIL이 무시되고 이전 PASS로 완료됩니다. 핵심 불변식 I5의 fail-open이므로 수정이 필요합니다.

**수정 실행 권고:** LLM — 수정 범위가 harness-company-complete.sh의 판정 후보 정규식 한두 줄, tests/mission-tiers.sh 사례 추가, cqo SKILL 문구로 좁습니다. 또 Codex 환경에서는 /hot-fix를 쓸 수 없으므로 직접 수정합니다.

## 확인한 것

- git status --short / git diff --stat: 변경 22개 파일 + 추적되지 않는 tests/, .codex/, .myterm/, 한글 디렉터리를 확인함
- scripts/harness-company-complete.sh 전체(216행)를 읽음: 인자 경로 검증(62~71행, `..`·절대경로·symlink 탈출은 pwd -P 접두사로 차단), lifecycle 분기(77행), lessons→validator→verdict→S 섹션→reachability→spec-pin 순서(88~155행), progress-set 이전에 모든 검사를 끝냄(161행), 수락 없는 종료 로그(158행), lifecycle 보존(201~202행)
- 판정 awk(96~108행)를 테스트 사례와 대조함: 후보 수집 후 마지막 후보만 엄격 검증하고 fallback이 없음을 확인. `**Verdict**:`, `Verdict :`, 하위 헤딩 아래 판정은 후보가 되지 않는 fail-open 경로임을 정적으로 확인
- scripts/harness-worker-evidence-validate.sh diff: mission scope, direct-work-sha(node sha256, 바이트 그대로), 유효 등급 jq 식, S의 cto/cqo 면제, S→M/L 면제의 sha 비교와 Post-Upgrade Work 첫 줄 판정, tier≠0일 때만 cqo-verdict-without-evaluator, mission scope에서 worker Status 검사를 대상 디렉터리로 한정
- scripts/harness-lessons-gate.sh diff: mission scope, S/M의 `## Lessons` 인정, mission_tiers=false일 때 L 처리
- scripts/harness-stop.sh diff: 차단 문구만 변경했고 판정 검사는 추가하지 않음
- commands/goal.md 15·20~29·33행, submission.md, hot-fix.md(15·19·21·25·28행): tier 기록, 명시적 완료 호출, 수락 없는 종료 절차, '필요한 CXX만', S의 CTO/CQO 대체 문장, hot-fix 11번 신호 기반, verbatim 범위 축소를 확인
- HR-Resource/ceo(86·98·125행 Mission Tier), cto(29·33행 Tier S/상향 후 규칙), cqo(29·31·35·125·126행 직접 검증, 판정 줄, OPS N/A, Recurrence none), hiring/resource-manager/ops diff를 확인
- assets/templates/AGENTS.md.template 89~105·196행, AGENTS-ko 89·91·216행: 등급 표, 유효 등급, 마지막 Verdict 규칙을 확인
- assets/templates/config.json: behavior.mission_tiers:true, worker_gate 문구 / package.json 7.1.58 / CHANGELOG 7.1.58에 벤치마크 미측정을 명시한 것을 확인
- apps/harness-dashboard sandbox-e2e.test.ts: 버전 기대값을 package.json 비교로 바꾼 것을 확인(설계에 없던 수정이지만 버전 bump에 따른 필요한 정정)
- 실행: bash -n (수정한 스크립트 4개 + tests/mission-tiers.sh) → SYNTAX_OK
- 실행: node --check bin/init.js, scripts/import-agency-agents.js → OK
- 실행: bash tests/mission-tiers.sh → 'PASS: 77 transition/lessons cases plus SHA, Stop, and legacy backstop checks'
- tests/mission-tiers.sh 전체를 읽고 설계 테스트 계획 1~39와 대조함: 판정 12종, 원자성(cmp 3종), 수락 없는 종료 9조합, OPS/CDO/COO worker 요구, 유효 등급 6종, 상향 면제 7종, legacy·backstop·Stop·spec-pin을 포함함
- 미실행: 임의 edge-case fixture 스크립트, vitest, npm pack dry-run, init 설치 테스트. 추가 Bash 실행이 권한 모드에서 거부되어 돌리지 못했고, 해당 결과는 작업 요약과 CHANGELOG의 주장으로만 남아 있음

## 지적 사항

### [MEDIUM] `**Verdict**: FAIL` 같은 굵게 표시 판정이 후보에서 빠져 이전 PASS로 완료됨

scripts/harness-company-complete.sh 99~100행은 앞쪽 `[[:space:]>*_-]`만 벗긴 뒤 `tolower(candidate) ~ /^verdict:/`로 후보를 고릅니다. 그래서 `**Verdict**: FAIL`은 `Verdict**: FAIL`이 되어 콜론 앞의 `**` 때문에 후보가 되지 못하고, 앞의 `Verdict: PASS`가 마지막 후보로 남아 완료됩니다(정적 추적. 임의 fixture 실행은 권한 거부로 못 했습니다). 설계와 cqo SKILL 125행은 '굵게 표시한 FAIL도 PASS를 덮고, 형식이 틀리면 거부한다'고 약속하는데, 가장 흔한 굵게 표시 형태에서 그 약속이 깨집니다. `Verdict : FAIL`(콜론 앞 공백)도 같은 문제가 있습니다. 고치는 법: 후보 조건을 `tolower(candidate) ~ /^verdict[*_[:space:]]*:/` 정도로 넓혀, 판정을 쓰려 한 줄은 모두 후보로 잡고 엄격 정규식에서 invalid-final-verdict로 거부되게 합니다. tests/mission-tiers.sh 57행의 invalid 목록에 `**Verdict**: FAIL`과 `Verdict : FAIL`을 추가합니다.

### [LOW] CQO Verdict 섹션 안의 하위 헤딩이나 변형 헤딩 아래 판정이 무시됨

harness-company-complete.sh 97~98행은 `## CQO Verdict` 제목과 정확히 일치할 때만 섹션에 들어가고, `#`로 시작하는 줄을 만나면 섹션을 나갑니다. 그래서 `### Re-evaluation` 하위 헤딩 아래나 `## CQO Verdict (Re-test)` 아래에 쓴 `Verdict: FAIL`은 후보가 되지 않고 앞의 PASS가 적용됩니다. 설계 문구대로이긴 하지만 결과적으로 fail-open입니다. 섹션 밖에 있는 `Verdict:` 후보까지 모두 모으거나, `### ` 이하 헤딩에서는 섹션을 나가지 않게 하거나, 적어도 cqo SKILL에 '재판정은 같은 `## CQO Verdict` 섹션 안에 하위 헤딩 없이 쓴다'를 명시하기를 권합니다.

### [LOW] 요약에 없는 부수 변경: 저장소 AGENTS.md·.gitignore와 추적되지 않는 디렉터리

AGENTS.md에 graphify 절 13줄이 추가됐고 .gitignore에 `/.cocoindex_code/`가 추가됐습니다. 추적되지 않는 `.codex/`, `.myterm/`, 한글 이름 디렉터리도 있습니다. 설계는 '이 저장소의 AGENTS.md는 변경하지 않음'이라고 했고, CLAUDE.md 9절은 Owner 승인 없이 AGENTS.md를 수정하지 말라고 합니다. 이 변경들은 작업 요약의 변경 파일 목록에 없으며, 도구(graphify/ccc) 설치가 만든 것인지 작업자가 만든 것인지 코드만으로는 알 수 없습니다. 커밋 전에 출처를 확인하고, 이번 작업과 무관하면 이번 변경분에서 제외하십시오.

### [LOW] 명시적 경로로 legacy 미션을 완료하면 lessons gate가 대상이 아닌 latest-active를 검사함

harness-company-complete.sh 74~85행은 tier가 있을 때만 `gate_scope=mission:<rel>`로 바꿉니다. 그래서 세 번째 인자로 legacy 미션을 지정해도 lessons gate(90행)는 다른 활성 미션을 볼 수 있습니다. legacy는 현행 동작을 보존한다는 설계와 모순되지는 않지만, 명시한 대상과 검사 대상이 어긋납니다. 인자가 3개일 때는 legacy라도 `mission:<rel>` scope로 lessons gate를 부르는 편이 일관됩니다.
