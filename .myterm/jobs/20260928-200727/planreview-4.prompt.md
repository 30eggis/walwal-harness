Claude 가 아래 요청의 설계를 썼다. 구현하기 전에 이 설계를 리뷰해줘.

## 요청
내 기준에서 간단한 추가 요청같은것으로 테스트를 거의 1시간 2시간 단위로 하는일이 많다. 내 생각엔 과도하다고 생각한다. 

~/vionyx/ViOnyx-WebFront 에서 동작한 myterminal 기록을 보면, 테스트를 거진 2시간동안 돌린다. 

왜 이렇게 많은 테스트를 돌리는지 이해가 되지 않는다. 

기록을 좀 살펴보고, 근본 원인과 타당한 테스트였는지 분석해보자

## 합의 4차
네가 지난번에 재설계를 요청했고 (`.myterm/jobs/20260928-200727/planreview-3.md` — 이 대화에서 쓴 것), Claude 가 지적마다 반영하거나 반박한 새 설계를 냈다.
설계의 "## 리뷰 반영" 을 지적마다 대조한다: 반영은 설계에 실제로 들어갔는지, 반박은 이유가 타당한지.
타당한 반박은 받아들이고, 남은 HIGH · MEDIUM 이 없으면 "합의" 한다.

## 작업 담당의 walwal-harness
Codex 는 /goal 를 쓸 수 없어요 (없음: .codex/commands/goal.md, .codex/skills/harness-ceo/SKILL.md) — 실행 방식은 llm 으로 한다.

## 설계 (Claude)
# 테스트 과다 실행의 근본 원인 분석과 검증 증거 재사용·산출물 위생 설계 (합의 4차)

## 요약
ViOnyx-WebFront에 남은 MyTerminal 기록 11건을 측정했습니다. 테스트 명령만으로 1~2시간이 걸린 작업은 "시나리오 등록과 실행" 요청 하나였고, 그 작업은 테스트를 돌리는 것이 곧 결과물이었습니다. 나머지 작업이 1~2시간씩 걸린 이유는 세 가지입니다.
- 검증 스크립트에 결함이 있어 반려와 재작업이 되풀이됐습니다.
- 대상 프로젝트에 tier 도입 이전 버전이 설치돼 있어, 라운드마다 Agent 4~7개를 띄우는 L 절차로 돌았습니다.
- 승인 대기 같은 유휴 시간이 있었습니다.

이 설계에서 하는 일은 세 가지입니다.
- **검증 산출물 위생 규칙을 스킬에 넣습니다.** 검증 스크립트가 처음부터 비밀을 새지 않고, 실패하면 실패로 끝나게 합니다. 누출 검사 스크립트(`harness-secret-scan.sh`)도 함께 둡니다. 이 스크립트는 누출 발견, 누출 없음, 검사 실패를 구분해서 돌려줍니다.
- **전체 테스트 결과는 조건을 모두 만족할 때만 재사용합니다.** 조건은 두 가지입니다. 실행 전후 소스 지문이 같았던 기준 실행이 있어야 하고, 명령·런타임·관련 환경이 같아야 합니다. 기준 실행은 기록 스크립트(`harness-verify-fingerprint.sh run`)로만 남깁니다.
- **재사용 규칙과 설치되는 상위 지침의 문구가 어긋나지 않게 맞춥니다.**

## 요구 분석
- **요청 1 — 기록을 살펴보고 근본 원인을 찾는다.**

  - 활동 시간은 plan·work·review 단계 실행 시간의 합입니다. 각 단계는 `*.started`부터 `*.result.json`의 mtime까지로 잽니다.
  - 유휴 시간은 전체 경과 시간에서 활동 시간을 뺀 값입니다.

  | 작업 | 전체 경과 | 활동 | 유휴 | 테스트 명령이 차지한 시간 |
  |---|---|---|---|---|
  | `20260928-151022` GOV→GOP | 7분 | 7분 | 0 | 없음 |
  | `20260923-163458` ACFEFW-62 | 106분 | 106분 | 0 | 라운드당 수 분 (아래 분해 참조) |
  | `20260923-165719` AICP-56 | 이틀 이상 | 121분 | 대부분 | vitest 1회, 약 1분 |
  | `20260928-160819` 시나리오 테스터 | 248분 | 131분 | 117분 (승인 대기 16:39→18:25) | work-3 72분 중 `cli.mjs run` 20회, 약 63분 |
  | `20260922-*` 3건 | 각 약 141분 | 37~66분 | 75~104분 | 라운드당 `npm test`와 headed 테스트 1~6분 |

  **ACFEFW-62 시간 분해**

  | 단계 | 시간 | Agent 수 | 내용과 범주 |
  |---|---|---|---|
  | plan 1~2, planreview 1~2 | 12분 | 0 | 설계 |
  | work-2 | 25.4분 | 7 | 구현과 필수 검증. 실행: targeted vitest 2회, `test:coverage` 2회, lint 2회, headed 4회. 전체 게이트는 8175/8175 통과. 다만 `test:coverage` 명령은 손대지 않은 파일 29개의 전역 100% 임계값 미달로 **non-zero로 끝났고**, 범위 밖 기존 문제로 분류됐습니다. 두 번째 coverage는 `onChanged` 제거로 제품이 바뀐 뒤에 돌렸으므로 **필요**했습니다 |
  | review-2 | 6.9분 | 0 | 지적 4건: 비밀번호 하드코딩과 URL 쿼리에 실린 세션 티켓, 전체 화면 얼굴 캡처, 실패해도 성공으로 끝나는 스크립트, 하네스 종료 실패 |
  | work-3 | 29.2분 | 6 | 제품 테스트 재실행 **0회**. headed 스크립트 11회, evaluator 2회. PUT 본문으로 얼굴 데이터가 새는 것을 **추가로 발견**했고, 그 보안 복구와 재검증은 **필요**했습니다. 결함 자체는 **예방 가능**했습니다 |
  | review-3 | 10.3분 | 0 | 붙여넣기 대조군 미assert(예방 가능), 민감 파일 잔존(Owner 권한 필요), 기록 불일치 |
  | work-4 | 12.2분 | 4 | 제품 테스트 재실행 **0회**. 대조군 assert 추가와 기록 정정 |
  | review-4 | 9.6분 | 0 | 제품 파일 6개의 MD5가 같아서 work-2의 증거를 인용하고 승인 |

- **근본 원인 R1 — 설치본이 tier 이전 버전이라 모든 미션이 L 절차로 돈다.**
  - ViOnyx의 `.claude/commands/hot-fix.md`에는 `tier`라는 말이 한 번도 나오지 않습니다.
  - 그래서 한 줄짜리 수정에도 라운드마다 Agent 4~7개가 새 세션으로 뜹니다. 세션마다 lessons를 읽고 역할 문서를 씁니다.
  - 해결책은 워킹트리에 아직 커밋하지 않은 tier 작업(`commands/*.md`, `HR-Resource/ceo|cqo|cto`, `tests/mission-tiers.sh`)에 이미 있습니다. 이번 설계는 그 작업을 중복하지 않습니다.
  - 남은 조치는 릴리스 후 대상 프로젝트에서 `walwal-harness init`을 다시 실행하는 것입니다.
- **근본 원인 R2 — 반려 라운드는 대부분 검증 산출물과 하네스 기록 때문이었다.**
  - ACFEFW-62의 review-2·3 지적 7건 가운데 제품 코드를 지적한 것은 0건입니다.
  - AICP-56의 반려 5회 가운데 4회는 하네스 기록 문제였습니다.
  - 반려 1회에 work와 review를 합쳐 약 15~40분이 듭니다.
  - 대상 프로젝트는 검증 스크립트 결함을 gotcha(`verification-artifacts-leak-secrets-and-biometrics.md`)로만 남겼습니다. "시스템적 반복 문제는 gotcha가 아니라 SKILL.md에 구조적으로 넣는다"는 원칙에 따라 스킬로 올립니다.
- **근본 원인 R3(잠재) — 규칙상 미션마다 전체 테스트가 필요하다.**
  - 다음 세 곳이 모든 tier에서 "changed-scope + full suite" 실행을 요구합니다.
    - `AGENTS.md.template:109`
    - `AGENTS-ko.md.template:95`
    - `HR-Resource/cqo/SKILL.md:31`
  - tier 체계가 설치되면 hot-fix와 submission에도 이 문구가 적용됩니다. ACFEFW-62에서는 우연히 피한 비용이, 앞으로는 규칙으로 강제됩니다.
- **요청 2 — 테스트가 타당했는지 판정한다.**
  - **ACFEFW-62:** 제품 테스트는 타당했고 중복도 없었습니다. 과했던 것은 절차입니다.
    - 예방할 수 있었던 재작업은 약 60분입니다(review-2 지적 3건, review-3 대조군 1건).
    - 보안 복구 뒤의 재검증은 필요했습니다.
  - **시나리오 작업:** 요청 자체가 "등록하고 수행"이었습니다.
    - v1.2가 해당 영역을 바꿨으므로 기존 시나리오 10개를 다시 돌린 것은 타당합니다.
    - 실패한 뒤에는 `--cases`로 일부만 다시 돌렸습니다.
    - 체감 시간 가운데 1시간 46분은 승인 대기였습니다.
  - **GOV→GOP:** 적정합니다.
  - **원인이 아닌 것:** `slowMo: 120`, 약 2분 걸리는 vitest 전체 실행 1회.

## 모호점과 해소안
- **지문의 위상** → 소스 지문은 재사용의 **필요조건**일 뿐, 충분조건이 아닙니다.
  - 재사용하려면 지문 외에 다음이 모두 같아야 합니다: 명령과 옵션, 런타임 버전, 선언한 환경 입력 파일, 합격 기준.
  - 제외된 입력(설치된 의존성, 환경 파일, 서버 데이터·세션)이 같은지 확인할 수 없으면 해당 항목만 다시 실행합니다.
- **지문 입력** → 다음을 해시합니다.
  - `HEAD` 커밋
  - `.harness/`·`.myterm/`을 뺀 `git diff HEAD --binary`
  - gitignore되지 않은 비추적 파일의 경로와 내용 해시
  - `--include`로 지정한 파일의 경로와 내용 해시
    - 대상은 gitignore된 `.env.test`나 대상 밖 E2E 스크립트 같은 파일입니다.
    - 파일이 없으면 `MISSING` 표지를 넣습니다. 그래서 파일이 생기거나 사라져도 지문이 바뀝니다.
    - 파일 값은 출력하지 않습니다.
  - 전체 환경을 해시하는 시스템은 만들지 않습니다.
- **기준 실행 시점** → 기준 실행은 `harness-verify-fingerprint.sh run`으로만 기록합니다.
  - 명령 실행 **직전과 직후**의 지문이 같을 때만 `Baseline:` 줄을 출력합니다.
  - 둘이 다르면 `Baseline:` 줄 없이 exit 3으로 끝나고, 그 실행은 재사용할 수 없습니다.
  - 사람이 손으로 쓴 `Baseline:` 줄은 재사용 근거로 인정하지 않습니다.
- **기존 문제로 실패하는 명령** → 명령의 exit이 0이 아니면 기준 실행이 될 수 없습니다. 재사용 조건은 완화하지 않습니다.
  - 예: ACFEFW-62의 `test:coverage`는 범위 밖 전역 임계값 때문에 실패했습니다.
  - 재사용 대상으로 삼으려면 합격 기준과 exit 의미가 일치하는 명령으로 기준 실행을 합니다. 예를 들어 테스트 전체 실행 명령과, 기존 규칙에 있는 변경 범위 coverage 판정을 따로 둡니다.
- **E2E·실기기** → 다음이 모두 같다고 확인될 때만 재사용합니다.
  - 지문(E2E 스크립트 포함)
  - 명령
  - `target`(호스트·장치·계정·빌드)
  - `preconditions`(데이터·설정·세션 전제)

  라이브 서버 상태처럼 확인할 수 없는 전제가 있으면 다시 실행합니다. 따라서 E2E는 대부분 다시 실행되고, 절감은 주로 전체 단위 테스트에서 나옵니다.
- **실행 횟수** → 절대 상한은 두지 않습니다. 최종 트리에 대한 유효한 기준 실행이 있으면 되고, 조건이 같은 라운드에서는 반복하지 않습니다.
- **누출 검사 방법** → 비밀 값을 명령 인자나 출력에 싣지 않는 스크립트를 제공합니다.
  - 인자로는 환경변수 **이름**만 받고, 값은 스크립트 안에서 `${!name}`으로 읽습니다.
  - 패턴은 bash 내장 `printf`와 프로세스 치환으로 `grep -f`에 넘깁니다.
  - 출력은 발견된 파일 경로와 건수뿐입니다.
- **누출 검사의 결과 구분** → 결과는 세 가지로 나눕니다.
  - grep 종료 코드 0: 누출 발견
  - grep 종료 코드 1: 누출 없음
  - grep 종료 코드 2 이상: 검사 실패

  읽기 오류 등으로 검사가 불완전하면 `leaks=0`을 발행하지 않습니다. 확인한 grep은 BSD grep 2.6.0(GNU 호환)이고, 0/1/>1 규약을 따릅니다. 일치하는 줄과 오류가 함께 있으면 GNU·BSD 모두 2를 돌려줍니다.
- **템플릿 수정** → 수정합니다. 템플릿은 설치물의 소스라서, 문구가 충돌하면 실행 담당자가 모순된 지시를 받습니다. 괄호 한 구절만 덧붙입니다.
- **완료 게이트 스크립트** → 수정하지 않습니다. `harness-company-complete.sh`는 S tier에서 `## Verification Commands` 제목과 `Verification Session` 줄만 검사하므로, `Baseline:`·`Reused:` 줄이 있어도 통과합니다.
- **리뷰어가 하네스 기록까지 검토해서 라운드가 늘어나는 문제(AICP-56)** → MyTerminal 앱 쪽 문제라 이 저장소에서는 다루지 않습니다. 결과 보고에 권고로 남깁니다.
- **보안 이슈의 tier** → 보안 분류를 완화할지는 Owner가 판단할 사항이라 바꾸지 않습니다.

## 변경 파일
- `scripts/harness-verify-fingerprint.sh` (신규, 약 40줄) — `harness-spec-pin.sh`처럼 `case "$CMD"` 구조를 씁니다.
  - **지문 모드:** `harness-verify-fingerprint.sh [--root DIR] [--include FILE]...`
    - 지문을 64자리 16진수 한 줄로 출력합니다.
    - 해시 도구는 `hash_of`와 같은 방식으로 고릅니다. `shasum -a 256`을 먼저 쓰고, 없으면 `sha256sum`을 씁니다.
    - 해시 도구가 둘 다 없으면 exit 2로 끝납니다.
  - **run 모드:** `harness-verify-fingerprint.sh run --log PATH [--root DIR] [--include FILE]... -- CMD...`
    - 실행 전 지문을 계산하고, CMD의 stdout·stderr를 `PATH`에 기록한 뒤, 실행 후 지문을 다시 계산합니다.
    - 전후 지문이 같으면 stdout에 다음 한 줄을 출력하고 CMD의 exit code로 끝납니다.
      `Baseline: cmd=<CMD> exit=<n> log=<PATH> fingerprint=<fp> includes=<목록>`
    - 전후 지문이 다르면 stderr에 `tree changed during run`을 쓰고, `Baseline:` 줄 없이 exit 3으로 끝납니다.
  - `init`이 `scripts/`를 통째로 복사하므로 설치 절차는 바꾸지 않습니다.
- `scripts/harness-secret-scan.sh` (신규, 약 20줄) — 사용법: `harness-secret-scan.sh VAR_NAME... -- PATH...`
  - 다음 경우에는 이름만 stderr에 쓰고 exit 2로 끝납니다.
    - 변수가 설정되지 않았거나 값이 비었을 때. 빈 패턴은 모든 줄에 일치하므로 오탐도 이 검사로 막습니다.
    - 경로가 없을 때
  - 검사 명령: `out=$(grep -rlF -f <(printf '%s\n' "${vals[@]}") -- PATH...); rc=$?`
  - 결과 처리:
    - `rc=0`: `leak: <파일경로>` 줄들과 `leaks=<건수>`를 출력하고 exit 1로 끝납니다.
    - `rc=1`: `leaks=0`을 출력하고 exit 0으로 끝납니다. 이 경우에만 누출 없음으로 판정합니다.
    - `rc≥2`: 발견된 경로가 있으면 `leak:` 줄만 출력하고, stderr에 `scan incomplete (grep rc=<rc>)`를 쓴 뒤 exit 2로 끝납니다. `leaks=0`은 출력하지 않습니다. grep 자신의 stderr(파일명과 오류 사유)는 값을 담지 않으므로 그대로 둡니다.
- `HR-Resource/cqo/SKILL.md`
  - `:31`(Tier S): "execute changed-scope tests and the available full suite directly" 뒤에 "(or cite a still-valid run under Evidence Reuse below)"를 붙입니다.
  - "Test Coverage Scope And Full Gate" 2번의 "once, near the end"를 "once valid for the final tree; rerun only when Evidence Reuse conditions fail"로 바꿉니다.
  - **Evidence Reuse** 문단을 추가합니다.
    1. 전체 테스트와 E2E는 `harness-verify-fingerprint.sh run`으로 실행합니다.
       - 출력된 `Baseline:` 줄을 `## Verification Commands`에 그대로 옮기고 `runtime=`(예: `node -v` 출력)과 `criteria=`(합격 기준 참조)를 덧붙입니다.
       - E2E라면 `target=`과 `preconditions=`도 적습니다.
       - `Baseline:` 줄이 나오지 않은 실행(exit 3)은 재사용할 수 없습니다.
    2. 재사용하려면 다음이 모두 성립해야 합니다.
       - 새로 실행한 지문 스크립트가 exit 0이고, 같은 `--include` 집합으로 계산한 출력이 baseline과 같습니다.
       - `cmd`, `runtime`, `criteria`가 같습니다.
       - baseline의 `exit=0`입니다.

       조건을 모두 확인하면 `Reused: <baseline 문서#항목> fingerprint=<fp>`로 재실행을 대신합니다.
    3. 기존 범위 밖 문제로 non-zero로 끝나는 명령은 기준 실행이 될 수 없습니다. 합격 기준과 exit 의미가 일치하는 명령으로 기준 실행을 합니다.
    4. baseline 이후 의존성을 다시 설치했거나 환경 파일이 바뀌었으면 다시 실행합니다. 그런 일이 있었는지 확인할 수 없어도 다시 실행합니다. E2E의 `preconditions`를 확인할 수 없을 때도 다시 실행합니다.
    5. 검증 로직의 결함(fail-open, 대조군 미검증 등)이 지적되면 그 로직에 의존한 증거는 모두 무효입니다.
    6. 병행 세션이 제품 파일을 편집하고 있다면 편집이 끝난 뒤 기준 실행을 합니다. 원하면 `git worktree`의 고정 checkout에서 검증해도 됩니다.
    7. M/L tier에서는 evaluator 워커가 재사용 여부를 판단하고, CQO는 그 보고를 인용합니다.
  - **Verification Artifact Hygiene** 섹션을 새로 만듭니다.
    - **기존 도구 우선:** 새 스크립트를 쓰기 전에 프로젝트에 있는 러너(시나리오 러너, vitest, playwright 설정)를 먼저 씁니다.
    - **비밀정보**
      - 자격 증명은 환경변수로만 받습니다. 없으면 브라우저를 열기 전에 non-zero로 끝냅니다.
      - 비밀을 명령줄, 로그, 도구 출력, 임시 파일, 패턴 파일에 쓰지 않습니다.
      - 누출 검사는 `bash scripts/harness-secret-scan.sh <VAR 이름>... -- <산출물 경로>`로만 합니다. `grep "$VAR"`처럼 값을 인자로 넘기는 방식은 금지합니다.
      - `exit 0`과 `leaks=0`이 함께 나왔을 때만 누출 없음으로 판정합니다. exit 2(검사 실패)는 누출 없음이 아닙니다.
    - **정제**
      - URL은 경로만 기록하고 쿼리는 뺍니다.
      - 인증 헤더, 쿠키, 티켓, 요청·응답 원문은 기록하지 않습니다. 키 목록, 개수, 식별자만 남깁니다.
      - 결과를 저장하기 직전에 금지 패턴을 검사하고, 발견하면 실패로 끝냅니다.
    - **캡처:** 검증 대상 요소 단위로 찍거나 마스킹합니다. 개인정보나 얼굴이 담긴 전체 화면 캡처는 금지합니다.
    - **fail-closed**
      - 필수 단계를 `if` 뒤에 두지 말고 assert합니다.
      - 요청 건수는 정확한 값으로 assert합니다. 빈 배열에 `every()`를 쓰지 않습니다.
      - 양성·음성 대조군을 모두 assert합니다.
      - 예외가 나면 non-zero로 끝냅니다.
      - `pass=true`는 마지막에만 설정합니다.
    - **fail-closed 입증:** 다음 네 경로가 각각 non-zero로 끝나는지 기록합니다: 자격 증명 누락, 대상 없음 또는 요청 0건, 대조군 실패, 예외.
    - **보관**
      - 산출물은 gitignore된 경로에 둡니다.
      - `Baseline`이 참조하는 정제된 증거는 보존합니다.
      - 정제 전 중간 산출물은 판정 후 삭제합니다.
- `HR-Resource/cto/SKILL.md` — "Test Coverage Scope"에 한 줄을 추가합니다: "검증 스크립트를 쓰거나 맡길 때 CQO의 Verification Artifact Hygiene과 Evidence Reuse를 따르고, 두 절을 워커 브리프에 그대로 옮긴다."
- `assets/templates/AGENTS.md.template:109` — "run changed-scope tests and the available full suite" 뒤에 " (a prior run is reusable only under CQO Evidence Reuse)"를 붙입니다.
- `assets/templates/AGENTS-ko.md.template:95` — 같은 위치에 "(이전 실행은 CQO 증거 재사용 조건을 충족할 때만 재사용)"을 붙입니다.
- `tests/verify-evidence.sh` (신규) — 두 스크립트의 회귀 검사입니다. 사례는 테스트 계획에 적었습니다.
- `CHANGELOG.md` — 아직 커밋하지 않은 현재 릴리스 항목에 두 줄을 추가합니다.
  - 실행 전후 지문 기반 증거 재사용
  - 검증 산출물 위생과, 값을 노출하지 않고 fail-closed로 동작하는 누출 검사

## 검증 규칙
- **지문 스크립트**
  - `--root`를 생략하면 `.`을 씁니다.
  - 경로가 없거나 git 저장소가 아니면 stdout 없이 exit 2로 끝납니다.
  - 해시 도구가 없어도 exit 2로 끝납니다.
  - 정상 출력은 64자리 16진수 한 줄뿐입니다.
  - `--include` 파일이 없으면 `MISSING` 표지로 해시합니다.
- **run 모드**
  - `--log`나 `--`가 없으면 exit 2로 끝납니다.
  - 전후 지문이 다르면 `Baseline:` 줄 없이 exit 3으로 끝납니다.
  - 그 밖에는 CMD의 exit code를 그대로 돌려줍니다.
  - 기준 실행이 유효한지는 **stdout에 `Baseline:` 줄이 있는지로만** 판단합니다. CMD 자신이 3을 돌려줄 수도 있어서 exit code만으로는 구분할 수 없기 때문입니다.
- **누출 검사 스크립트**
  - 변수 이름이 없거나, 값이 비었거나, 경로가 없으면 exit 2로 끝납니다.
  - grep 결과에 따라 이렇게 끝납니다.
    - grep `rc=0`: exit 1
    - grep `rc=1`: `leaks=0`, exit 0
    - grep `rc≥2`: `leaks=0` 없이 exit 2
  - 누출 없음으로 판정하는 경우는 exit 0뿐입니다.
  - 어떤 경로로 끝나든 stdout·stderr에 값을 출력하지 않습니다.
- **재사용은 실패 쪽이 기본값입니다.** 다음 경우에는 모두 다시 실행합니다.
  - 지문 불일치
  - 지문 스크립트의 exit가 0이 아님
  - 로그 또는 `Baseline:` 줄이 없음
  - baseline의 `exit≠0`
  - `cmd`, `runtime`, `criteria` 중 하나라도 다름
  - 제외된 입력이 같은지 확인할 수 없음
  - 검증 로직의 결함이 지적됨
- **지문 경계**
  - 지문이 유지되는 경우: `.harness/`·`.myterm/` 문서 변경, `--include`에 없는 gitignore 산출물 변경
  - 지문이 바뀌는 경우: 추적 파일의 수정·삭제·추가, lockfile·설정 변경, gitignore되지 않은 비추적 파일 추가, `--include` 파일의 변경·생성·삭제
- **남는 한계:** 실행 중에 바뀌었다가 끝나기 전에 원상 복구된 변경(ABA)은 전후 비교로 잡지 못합니다. 병행 편집이 예상되면 편집이 끝난 뒤 기준 실행을 하거나 고정 checkout을 씁니다. 이 한계는 스크립트에 `ponytail:` 주석으로 남깁니다.
- **문서만 바뀐 라운드:** 기존 규칙대로 `OPS N/A: docs-only`로 기록합니다.
- **tier:** 재사용 규칙은 S/M/L 공통입니다. `unknown → L` 기본값은 바꾸지 않습니다.

## 테스트 계획
- `bash tests/verify-evidence.sh` — `/private/tmp` 픽스처에서 `git init`을 하고 아래 사례를 모두 assert합니다. 하나라도 실패하면 exit 1입니다.
  - **지문**
    - 변경이 없으면 지문이 같다.
    - 추적 파일을 수정하거나 삭제하면 지문이 달라진다.
    - 비추적 파일을 추가하면 지문이 달라진다.
    - `package-lock.json`을 수정하면 지문이 달라진다.
    - staged만 된 변경도 지문을 바꾼다.
    - `.harness/` 아래 파일을 수정해도 지문이 같다.
    - gitignore된 `test-results/` 파일을 추가해도 지문이 같다.
    - gitignore된 `.env.test`를 `--include`로 지정하면 내용 변경, 생성, 삭제가 모두 지문을 바꾼다.
    - git 저장소가 아닌 디렉터리에서는 exit 2이고 stdout이 비어 있다.
  - **run 모드**
    - `-- true`: stdout에 `Baseline:` 줄이 있고 `exit=0`이며, 지문이 단독 실행 결과와 같다.
    - `-- false`: `Baseline:` 줄에 `exit=1`이 기록되고 스크립트도 exit 1로 끝난다.
    - 실행 중 입력 변경 `-- sh -c 'echo x >> tracked.txt'`: exit 3이고 stdout에 `Baseline:` 줄이 없다.
  - **누출 검사** (`DUMMY_SECRET=wh-dummy-7f3a` 사용)
    - 값이 들어 있는 파일: exit 1, `leaks=1`, 파일 경로 출력.
    - 탐지되더라도 stdout·stderr를 합친 출력에 `wh-dummy-7f3a`가 **없다**.
    - 깨끗한 디렉터리: exit 0, `leaks=0`.
    - 변수가 설정되지 않았거나 비어 있음: exit 2이고 출력에 값이 없다.
    - 읽기 오류: 깨끗한 파일 하나와 `chmod 000` 파일 하나를 둔 디렉터리.
      - exit 2이고 출력에 `leaks=0`이 **없다**.
      - `id -u`가 0이면 권한 검사가 무의미하므로 `SKIP: root`를 출력하고 넘어간다.
    - 읽기 오류와 누출이 함께 있는 경우: 값이 든 파일과 `chmod 000` 파일이 함께 있는 디렉터리.
      - exit 2이고 `leak:` 경로는 출력되지만 `leaks=0`은 없다.
      - 출력에 값이 없다.
- `bash tests/mission-tiers.sh` — 기존 tier 게이트 회귀가 모두 통과하는지 확인합니다. 게이트 스크립트는 바꾸지 않았습니다.
- **기본 검사**
  - `node --check bin/init.js`
  - `node --check scripts/import-agency-agents.js`
  - `bash -n scripts/harness-verify-fingerprint.sh scripts/harness-secret-scan.sh`
  - `npm pack --dry-run --cache /private/tmp/walwal-npm-cache` — 출력에 신규 스크립트 두 개가 포함되는지 확인합니다.
- **init 테스트:** `node ./bin/init.js init --force --project-root /private/tmp/walwal-v7-init-test`를 실행한 뒤 다음을 확인합니다.
  - 신규 스크립트 두 개가 설치되었고 실행 권한이 있다.
  - `.claude/skills/harness-cqo/SKILL.md`와 `.codex/skills/harness-cqo/SKILL.md`에서 `Evidence Reuse`, `Verification Artifact Hygiene`, `harness-secret-scan.sh`가 grep으로 검색된다.
  - 생성된 `AGENTS.md`에 재사용 괄호 문구가 있다.
  - 명령은 `goal.md`, `submission.md`, `hot-fix.md` 세 개뿐이다.
  - `CLAUDE.md → AGENTS.md` 심볼릭 링크가 있다.
- **기록 대조(수동, 대조표로 작성)**
  - **위생 조항 대조:** review-2·3에서 나온 지적 10개를 위생 조항과 하나씩 연결합니다. 연결되지 않는 지적이 0건이어야 합니다. 대상 지적은 다음과 같습니다.
    - 비밀번호 하드코딩
    - URL 쿼리의 티켓
    - PUT 원문의 얼굴 데이터
    - 전체 화면 캡처
    - 팝업 캡처 실패 시 필수 검사를 건너뜀
    - PUT 0건인데 통과
    - catch 후 rc=0
    - 붙여넣기 대조군 미assert
    - 도구 출력에 찍힌 비밀번호
    - 패턴 파일에 든 비밀번호
  - **역사적 기록에 규칙 적용:** ACFEFW-62 기록을 그대로 넣으면 전체 테스트 재사용은 **불가**로 나와야 합니다. 새 규칙이 기존 결과를 성공으로 바꾸지 않는지 확인하는 것이 목적입니다. 불가 사유는 두 가지입니다.
    - `run` 모드가 만든 `Baseline:` 줄이 없습니다.
    - `test:coverage`가 전역 임계값 때문에 `exit≠0`으로 끝났습니다.
  - **가상 적용:** 다음을 전제로 둡니다.
    - work-2에서 합격 기준과 exit 의미가 일치하는 전체 테스트 명령을 `run` 모드로 실행했고, `Baseline:` 줄과 `exit=0`이 나왔습니다.
    - 이후 의존성과 환경 파일은 바뀌지 않았습니다.

    이 전제에서 work-3·4에 규칙을 적용하면 결과는 이렇게 나와야 합니다.
    - 제품 지문, `cmd`, `runtime`, `criteria`가 같으므로 전체 테스트는 재사용합니다.
    - E2E 스크립트(`--include` 대상)가 바뀌었으므로 headed E2E는 다시 실행합니다.
- `graphify update .` — 변경 후 지식 그래프를 갱신합니다.

## 리뷰 반영
- **[반영] 누출 검사 실패와 정상적인 미탐지를 구분해야 합니다 (MEDIUM)**
  - 지적이 맞습니다. 사전 경로 검사는 디렉터리 안 파일의 읽기 오류나 검사 도중 파일이 사라지는 경우를 막지 못합니다. grep은 이런 경우 `rc≥2`를 돌려줍니다. 이 환경의 grep은 BSD grep 2.6.0(GNU 호환)이고, 0/1/>1 규약을 따릅니다.
  - 변경 파일의 `harness-secret-scan.sh` 항목을 다음과 같이 바꿨습니다.
    - `rc=0`: 누출 발견, exit 1
    - `rc=1`: 누출 없음. `leaks=0`을 출력하고 exit 0. 누출 없음은 이 경우에만 판정합니다.
    - `rc≥2`: 검사 실패, exit 2. `leaks=0`은 출력하지 않고, 발견된 경로는 계속 보고합니다.
  - 검증 규칙과 위생 조항에 "exit 2는 누출 없음이 아니다"를 명시했습니다.
  - 회귀 검사에 두 사례를 추가했습니다: 읽기 오류만 있는 경우, 읽기 오류와 누출이 함께 있는 경우. root로 실행하면 권한 검사가 무의미하므로 SKIP합니다.
- **[반영] 과거 사례 대조의 예상 결과가 새 재사용 조건과 맞지 않습니다 (LOW)**
  - 지적이 맞습니다. work-2 trace에 "Global 100% coverage threshold fails on 29 untouched files"와 "Full gate 8175/8175 pass"가 함께 기록돼 있습니다. `test:coverage` 명령은 non-zero로 끝났고, 당시에는 `run` 모드 baseline도 없었습니다. 새 규칙을 그대로 적용하면 재사용할 수 없습니다.
  - 테스트 계획의 기록 대조를 둘로 나눴습니다.
    - **역사적 기록에 규칙 적용:** 결과가 재사용 불가로 나와야 합니다.
    - **가상 적용:** 유효한 `Baseline:` 줄, `exit=0`, 환경 불변을 전제로 명시했습니다.
  - 재사용 조건은 완화하지 않았습니다. 대신 이 사례에서 드러난 공백을 Evidence Reuse 3번에 적었습니다. 기존 범위 밖 문제로 실패하는 명령은 기준 실행이 될 수 없으므로, 합격 기준과 exit 의미가 일치하는 명령으로 기준 실행을 해야 합니다. 요구 분석의 work-2 행에도 이 사실을 반영했습니다.