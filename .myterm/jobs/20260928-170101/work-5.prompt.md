Claude 가 4차 작업을 리뷰했다. 지적을 검토해서 코드를 고쳐줘.
합의가 목표다: 맞는 지적은 반영하고, 동의하지 않는 지적은 고치지 말고 요약의 "리뷰 반영" 에 코드 근거와 함께 반박한다.
Claude 가 그 반박을 읽고 다시 리뷰한다.

## 이번 요청
이 하네스 시스템을 이용하면 꼼꼼하다는 느낌은 있지만, 너무 프로세스가 과도하다는 느낌을 받는다. 가령 LLM 온리로 작업하면 5분이면 끝날것이 1~2시간 걸릴때도 있다. 전체적으로 시스템을 확인하고 어떤 부분을 수정하면 좋을지, 꼼꼼함은 유지하며 , 
시간을 단축 가능한지, 또는 너무 과도한 설계가 있어서, 좋은 모델의 유용성을 해치는 부분은 무엇인지, 확인해달라

## 지난 문서
- 첫 지시 (원래 요청): `.myterm/jobs/20260928-170101/plan-1.prompt.md`
- 설계: `.myterm/jobs/20260928-170101/plan-4.md`
- 설계리뷰: `.myterm/jobs/20260928-170101/planreview-4.md`
- 직전 작업 요약 (4차): `.myterm/jobs/20260928-170101/work-4.md`
- 직전 리뷰 전문 (4차): `.myterm/jobs/20260928-170101/review-4.result.md`
같은 대화를 이어 가고 있어서 이미 본 내용이다. 다시 읽지 말고, 기억이 흐리거나 확인이 필요할 때만 연다.

## Claude 리뷰 (4차)
설계 항목은 대부분 코드에 있습니다. 명시적 대상 완료, 수락 없는 종료 분기, 순위 기반 유효 등급, S의 CTO/CQO 면제, 상향 시 Direct Work SHA 동결, 거부 시 상태 보존이 모두 구현되어 있고, tests/mission-tiers.sh 77개 사례가 실제로 통과합니다. 문제는 판정 파서가 설계의 약속과 달리 일부 흔한 Markdown 판정 표기를 후보로 잡지 못한다는 점입니다. 예를 들어 `Verdict: PASS` 뒤에 `**Verdict**: FAIL`을 쓰면 최신 FAIL이 무시되고 이전 PASS로 완료됩니다. 핵심 불변식 I5의 fail-open이므로 수정이 필요합니다.

### 지적 사항
1. [MEDIUM] `**Verdict**: FAIL` 같은 굵게 표시 판정이 후보에서 빠져 이전 PASS로 완료됨 — scripts/harness-company-complete.sh 99~100행은 앞쪽 `[[:space:]>*_-]`만 벗긴 뒤 `tolower(candidate) ~ /^verdict:/`로 후보를 고릅니다. 그래서 `**Verdict**: FAIL`은 `Verdict**: FAIL`이 되어 콜론 앞의 `**` 때문에 후보가 되지 못하고, 앞의 `Verdict: PASS`가 마지막 후보로 남아 완료됩니다(정적 추적. 임의 fixture 실행은 권한 거부로 못 했습니다). 설계와 cqo SKILL 125행은 '굵게 표시한 FAIL도 PASS를 덮고, 형식이 틀리면 거부한다'고 약속하는데, 가장 흔한 굵게 표시 형태에서 그 약속이 깨집니다. `Verdict : FAIL`(콜론 앞 공백)도 같은 문제가 있습니다. 고치는 법: 후보 조건을 `tolower(candidate) ~ /^verdict[*_[:space:]]*:/` 정도로 넓혀, 판정을 쓰려 한 줄은 모두 후보로 잡고 엄격 정규식에서 invalid-final-verdict로 거부되게 합니다. tests/mission-tiers.sh 57행의 invalid 목록에 `**Verdict**: FAIL`과 `Verdict : FAIL`을 추가합니다.
2. [LOW] CQO Verdict 섹션 안의 하위 헤딩이나 변형 헤딩 아래 판정이 무시됨 — harness-company-complete.sh 97~98행은 `## CQO Verdict` 제목과 정확히 일치할 때만 섹션에 들어가고, `#`로 시작하는 줄을 만나면 섹션을 나갑니다. 그래서 `### Re-evaluation` 하위 헤딩 아래나 `## CQO Verdict (Re-test)` 아래에 쓴 `Verdict: FAIL`은 후보가 되지 않고 앞의 PASS가 적용됩니다. 설계 문구대로이긴 하지만 결과적으로 fail-open입니다. 섹션 밖에 있는 `Verdict:` 후보까지 모두 모으거나, `### ` 이하 헤딩에서는 섹션을 나가지 않게 하거나, 적어도 cqo SKILL에 '재판정은 같은 `## CQO Verdict` 섹션 안에 하위 헤딩 없이 쓴다'를 명시하기를 권합니다.
3. [LOW] 요약에 없는 부수 변경: 저장소 AGENTS.md·.gitignore와 추적되지 않는 디렉터리 — AGENTS.md에 graphify 절 13줄이 추가됐고 .gitignore에 `/.cocoindex_code/`가 추가됐습니다. 추적되지 않는 `.codex/`, `.myterm/`, 한글 이름 디렉터리도 있습니다. 설계는 '이 저장소의 AGENTS.md는 변경하지 않음'이라고 했고, CLAUDE.md 9절은 Owner 승인 없이 AGENTS.md를 수정하지 말라고 합니다. 이 변경들은 작업 요약의 변경 파일 목록에 없으며, 도구(graphify/ccc) 설치가 만든 것인지 작업자가 만든 것인지 코드만으로는 알 수 없습니다. 커밋 전에 출처를 확인하고, 이번 작업과 무관하면 이번 변경분에서 제외하십시오.
4. [LOW] 명시적 경로로 legacy 미션을 완료하면 lessons gate가 대상이 아닌 latest-active를 검사함 — harness-company-complete.sh 74~85행은 tier가 있을 때만 `gate_scope=mission:<rel>`로 바꿉니다. 그래서 세 번째 인자로 legacy 미션을 지정해도 lessons gate(90행)는 다른 활성 미션을 볼 수 있습니다. legacy는 현행 동작을 보존한다는 설계와 모순되지는 않지만, 명시한 대상과 검사 대상이 어긋납니다. 인자가 3개일 때는 legacy라도 `mission:<rel>` scope로 lessons gate를 부르는 편이 일관됩니다.