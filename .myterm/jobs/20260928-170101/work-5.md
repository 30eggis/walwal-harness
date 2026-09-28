# 완료 게이트 리뷰 반영

## 요약

Markdown 판정 표기가 누락되어 이전 PASS로 완료되는 문제와 legacy 미션의 검사 대상 불일치를 수정했습니다. 회귀 검사를 추가했으며, 커밋·푸시 없이 작업 트리에 남겼습니다.

## 변경 파일

- `scripts/harness-company-complete.sh` — 판정 후보·섹션 인식 확대, legacy 검사 범위 수정.
- `tests/mission-tiers.sh` — 판정 변형과 legacy 대상 분리 검사 추가.
- `HR-Resource/cqo/SKILL.md` — 재판정 작성법과 검사 범위 명시.
- `CHANGELOG.md` — 수정 사항과 검증 결과 기록.

## 확인

- 미션 회귀 검사 91개 통과.
- sandbox 포함 기존 테스트 34개 통과.
- 문법 검사, 설치 실행, 패키징 dry-run, `git diff --check` 통과.
- graphify 코드 그래프 갱신.

## 리뷰 반영

1. **채택** — `**Verdict**: FAIL`, `Verdict : FAIL`도 후보로 잡고 `invalid-final-verdict`로 거부합니다.
2. **채택** — 하위 헤딩과 `CQO Verdict (Re-test)`의 재판정을 검사합니다. 무관한 최상위·동급 섹션은 제외합니다.
3. **원복 미반영** — 해당 파일·디렉터리는 4차 작업 최초 `git status`부터 존재했습니다. 이번 작업에서 생성한 변경이 아니므로 기존 작업을 보존했습니다.
4. **채택** — 세 번째 인자로 지정한 legacy 미션도 `mission:<rel>` 범위로 lessons를 검사합니다.