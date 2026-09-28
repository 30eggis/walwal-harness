# 테스트 과다 실행의 근본 원인 분석과 재검증 범위 축소 설계

## 요약
ViOnyx-WebFront의 MyTerminal 기록(`.myterm/jobs/*` 11건)을 단계별 시각과 trace로 분석했습니다. 1~2시간이 걸린 작업의 대부분은 제품 변경을 검증하는 시간이 아니었습니다. 대부분 세 가지에 쓰였습니다.
- 리뷰 지적이 나올 때마다 전체 검증 게이트를 처음부터 다시 돌렸습니다.
- 검증용으로 새로 만든 스크립트와 산출물이 다시 리뷰 대상이 되어 되돌이 수정이 이어졌습니다.
- tier가 없는 미션이 L(최중량) 절차로 처리되었습니다.

이 설계는 두 가지를 하네스 스킬과 명령 문서에 넣습니다. 제품 파일이 바뀌지 않은 재작업에서는 이전 증거를 재사용하게 하고, 검증 산출물을 처음부터 깨끗하게 만들게 합니다.

## 요구 분석
- **요청 1. 기록을 살펴보고 근본 원인을 찾는다.** 작업별 실측 결과는 아래와 같습니다. 시간은 `*.started`와 `*.result.json`의 mtime, trace의 도구 호출 간격으로 계산했습니다.

| 작업 | 요청 성격 | 총 소요 | 시간이 쓰인 곳 |
|---|---|---|---|
| `20260928-151022` GOV→GOP 라벨 | 단순 | 약 5분 | plan 1분, review 3분. LLM 트랙이라 적정 |
| `20260923-163458` ACFEFW-62 User ID readonly | 단순(파일 2개) | 약 1시간 46분 | 제품 구현과 검증은 work-2(25분)에서 끝났고, review-2가 "핵심 구현은 설계대로 동작"이라고 인정. 이후 work-3(29분), work-4(12분), 리뷰 2회(약 25분), 합계 약 66분은 모두 **검증 스크립트 수정과 하네스 상태 복구**에 쓰임. 지적 내용: 비밀번호 하드코딩, 원문 PUT 본문 기록, 전체 화면 얼굴 스크린샷, assert가 없는 붙여넣기 대조군, 완료 전환 누락 |
| `20260923-165719` AICP-56 | 중간 | 7라운드, 이틀에 걸침 | hotfix-1~3의 사유가 계약 가정, lifecycle과 BLOCKED 표기, 오래된 교차참조. 제품보다 **문서 정합성**을 고친 라운드가 다수 |
| `20260928-160819` v1.2 시나리오 테스터 | 요청 자체가 테스트 | 약 3시간 30분 | 설계 3라운드 30분. 16:38~18:25 **1시간 47분은 승인 대기(유휴)**. work-3 73분 중 약 57분이 실기기 `node cli.mjs run`(50~54 F12 스위트가 1회 3~7분, 실패 후 재실행 포함). review-3가 "19개 단일 세션 연속 PASS"와 비밀번호 마스킹을 요구해서 work-4에 17분 추가 |

- **근본 원인 R1 — tier가 없으면 L 절차가 된다.** 기록 속 미션(goal-8, goal-10, 모든 hotfix)의 `mission-state.json`에 `tier`가 없습니다.
  - 설치된 하네스가 tier 도입 이전 버전이기 때문입니다.
  - 그래서 readonly 한 줄 수정에도 다음이 모두 돌았습니다: 워커 고용, evaluator 워커, OPS 감시, 전체 커버리지(8175개 테스트) 2회, lint 2회, headed 실기기 E2E 2회, Agent 호출 5회.
  - 현재 워킹트리에는 미커밋 상태로 S/M/L tier 도입이 이미 들어 있습니다(`commands/*.md`, `HR-Resource/ceo|cqo|cto`, `tests/mission-tiers.sh`).
  - 이 설계는 그 작업을 중복하지 않습니다. tier 기록이 빠지는 경로 하나만 막습니다(아래 hot-fix와 submission 1단계).
- **근본 원인 R2 — 재작업 라운드마다 전체 게이트를 다시 돌린다.**
  - CQO 스킬은 S에서도 "changed-scope + available full suite"를 매 미션 실행하게 되어 있습니다(`HR-Resource/cqo/SKILL.md` Tier S, Test Coverage Scope And Full Gate).
  - 리뷰 한 번이 hot-fix 미션 하나가 되므로, 문서나 검증 스크립트만 고친 라운드도 전체 게이트를 다시 탑니다.
- **근본 원인 R3 — 일회용 검증 산출물이 새 리뷰 표면이 된다.**
  - ad-hoc headed 스크립트(`test-results/goal-8-cqo/headed-userid.mjs`)와 로그, 스크린샷이 저장소에 남습니다.
  - 리뷰어가 이것을 보안과 판정 결함으로 지적하고, 고치면 또 검증하는 루프가 2라운드 발생했습니다.
  - 대상 프로젝트는 이 문제를 gotcha로만 등록했습니다(`verification-artifacts-leak-secrets-and-biometrics.md`). 메모리 원칙("시스템적 반복 문제는 gotcha가 아니라 SKILL.md에 구조적으로")에 따라 스킬로 올려야 합니다.
- **요청 2. 테스트가 타당했는지 판정한다.**
  - ACFEFW-62: targeted vitest(수 초), 전체 커버리지 1회(약 1.5분), 실기기 확인 1회까지는 타당합니다. 그 이후의 재실행과 스크립트 보강 루프는 제품 변경을 추가로 검증하지 않았으므로 **과도**합니다.
  - 시나리오 작업: 테스트가 곧 산출물이라 실행 자체는 타당합니다.
    - 기존 F12 스위트(50~54)를 전체 재실행한 것은 설계가 정한 합격 기준("19개 연속 PASS") 때문이었습니다.
    - 체감 2시간 중 약 1시간 47분은 테스트가 아니라 승인 대기였습니다.
  - GOV→GOP: 적정합니다(5분).
- **원인이 아닌 것.**
  - `slowMo: 120`: 동작 수백 개 × 120ms는 수십 초 수준이라 원인이 아닙니다.
  - 전체 vitest 실행 시간: 1회 약 1.5분이라 원인이 아닙니다.

## 모호점과 해소안
- **MyTerminal 리뷰어가 하네스 내부 문서와 lifecycle까지 리뷰하고 "Harness" 모드를 권고해 범위가 넓어지는 문제** → 이 저장소 밖(MyTerminal 앱)이라 이번 변경에 넣지 않습니다. 결과 보고에 권고로만 남깁니다.
  - 권고 1: 리뷰 대상은 제품 diff와 요청 산출물로 한정합니다. `.harness/documents`는 제외합니다.
  - 권고 2: 문서만 지적된 경우 LLM 트랙으로 처리합니다.
- **"19개 단일 세션 연속 PASS" 같은 합격 기준** → MyTerminal 설계 단계의 결정이므로 하네스 규칙으로 바꾸지 않습니다.
- **ViOnyx 설치본이 구버전이라 R1이 계속되는 문제** → 코드 변경이 아니라 릴리스 후 대상 프로젝트에서 `walwal-harness init` 재실행이 필요합니다. 결과 보고에 명시합니다.
- **증거 재사용의 판단 기준** → 직전 PASS 게이트에서 기록한 제품 파일 해시(`md5`/`sha256`)가 현재와 같을 때만 재사용합니다.
  - goal-8 review-4가 이미 이 방식으로 증거를 재사용했고 리뷰어도 받아들였습니다.
  - 해시가 다르거나 기록이 없으면 기존대로 다시 실행합니다(fail-safe).
- **완료 게이트 스크립트 수정 여부** → 수정하지 않습니다.
  - `harness-company-complete.sh`는 S에서 `## Verification Commands` 제목과 `Verification Session` 줄만 검사합니다.
  - 따라서 재사용 줄을 그 섹션에 쓰면 그대로 통과합니다. 스크립트 변경은 불필요합니다(YAGNI).
- **`AGENTS.md.template`에 넣을지** → 넣지 않습니다. AGENTS.md 계열은 Owner 승인 사항이고, 역할 스킬로 충분합니다.

## 변경 파일
- `HR-Resource/cqo/SKILL.md`
  - "Test Coverage Scope And Full Gate"에 **재검증 범위** 문단을 추가합니다.
    - 대상: `/hot-fix`·`/submission` 재작업이나 리뷰 반영 라운드.
    - 제품 파일(src·tests·설정)이 직전 PASS 게이트 이후 바뀌지 않았으면 full-suite와 E2E를 다시 돌리지 않습니다.
    - 대신 `## Verification Commands`에 `reused: <이전 로그 경로> · <파일별 해시> match`를 기록합니다.
    - 문서나 검증 스크립트만 바뀌었으면 바뀐 스크립트의 `node --check`와 그 스크립트 1회만 실행합니다.
    - 제품 파일이 바뀌었으면 바뀐 범위의 테스트와 full-suite 1회를 실행합니다.
    - 전체 게이트는 미션당 마지막에 1회만 둡니다(라운드마다 반복 금지).
  - 같은 파일에 **Verification Artifact Hygiene** 짧은 섹션을 추가합니다.
    - 새 스크립트보다 프로젝트의 기존 테스트 도구(시나리오 러너, vitest 등)를 먼저 씁니다.
    - 자격 증명은 환경변수로만 받고, 없으면 브라우저를 열기 전에 non-zero로 종료합니다.
    - 요청과 응답 본문 원문을 저장하지 않습니다(요약 필드만).
    - 스크린샷은 검증 대상 요소로 한정합니다(전체 화면이나 얼굴 금지).
    - 기록만 하는 대조군은 대조군이 아닙니다. 양성 대조군도 assert하고 실패 시 종료합니다.
    - 산출물은 gitignore된 경로에 두고, 판정 후 불필요한 run 산출물은 삭제합니다.
- `HR-Resource/cto/SKILL.md` — "Test Coverage Scope"에 한 줄을 추가합니다: 검증 스크립트나 산출물을 만들거나 워커에게 맡길 때 CQO의 Verification Artifact Hygiene을 따르고, 그 절을 워커 브리프에 그대로 옮깁니다.
- `commands/hot-fix.md`
  - 1단계 "CEO must create/select one"에 "새로 만드는 goal의 `mission-state.json`에도 분류한 `tier`를 기록"을 추가합니다.
  - 재검증 범위는 CQO의 재검증 범위 규칙을 따른다는 한 줄을 추가합니다.
- `commands/submission.md` — 1단계에 hot-fix와 같은 tier 기록 문구를 추가합니다.
- `CHANGELOG.md` — 현재 미커밋 릴리스 항목에 두 줄을 추가합니다: 재작업 라운드의 증거 재사용, 검증 산출물 위생 규칙.

## 검증 규칙
- **증거 재사용 조건.** 다음이 모두 맞을 때만 재사용합니다.
  - 파일별 해시가 전부 일치합니다.
  - 이전 로그 경로가 실제로 존재합니다.
  - 이전 게이트의 종료 코드가 기록되어 있습니다.
  - 하나라도 빠지면 재실행합니다. 재사용 불가를 기본으로 봅니다.
- **해시 대상.** 해시를 계산할 파일 목록은 CTO handoff의 변경 파일 목록과 그 테스트 파일로 합니다. "제품 파일 없음"을 이유로 대상 없이 재사용하는 것을 금지합니다.
- **문서만 바뀐 라운드.** 런타임을 띄우지 않았으면 `OPS N/A: docs/verification-script only`로 기록합니다. OPS를 기다리지 않습니다.
- **tier 경계.** 새로 만든 goal 레코드에 `tier`가 없으면 기존 규칙대로 L입니다(`unknown → L` 유지). 이번 변경은 기록을 강제할 뿐 기본값은 바꾸지 않습니다.
- **L 미션.** 재사용 규칙은 S/M/L 공통입니다. 다만 L은 evaluator 워커가 재사용 판단을 내리고 CQO가 그 보고를 인용합니다(CQO 직접 실행 금지 규칙 유지).

## 테스트 계획
- `bash tests/mission-tiers.sh` — 기존 tier 게이트 회귀가 전부 통과하는지 확인합니다. 스크립트는 바꾸지 않았으므로 결과가 같아야 합니다.
- `node --check bin/init.js`, `node --check scripts/import-agency-agents.js`, `npm pack --dry-run --cache /private/tmp/walwal-npm-cache`.
- init 테스트를 실행합니다: `node ./bin/init.js init --force --project-root /private/tmp/walwal-v7-init-test`. 이어서 다음을 확인합니다.
  - `.claude/skills/harness-cqo/SKILL.md`와 `.codex/skills/harness-cqo/SKILL.md`에 "Verification Artifact Hygiene"과 재검증 범위 문단이 있는지 grep합니다.
  - `.claude/commands/hot-fix.md` 1단계에 tier 문구가 있는지 확인합니다.
  - 명령이 `goal.md`, `submission.md`, `hot-fix.md` 3개뿐인지 확인합니다.
- 기록 대조(수동): ACFEFW-62 흐름에 새 규칙을 적용해 봅니다.
  - review-3·4의 수정은 제품 파일 해시가 일치하는 라운드이므로(review-4가 MD5 6개 일치를 확인), 전체 커버리지와 E2E를 다시 돌리지 않고 스크립트만 다시 실행하는 경로가 되는지 문서상으로 따라갑니다.
  - 위생 규칙이 review-2·3의 지적 4건(비밀번호 하드코딩, 원문 본문, 전체 화면 스크린샷, assert 없는 대조군)을 각각 막는지 대조표로 확인합니다.
- `graphify update .` — 변경 후 지식 그래프를 갱신합니다.