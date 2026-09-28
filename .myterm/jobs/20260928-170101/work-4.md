# 미션 등급 도입과 절차 경량화

## 요약

S/M/L 등급을 도입해 작은 작업의 worker 호출과 보고서 작성을 줄였습니다. 실행 증거·OPS 검증은 유지하고, 완료 게이트가 대상 미션의 마지막 판정을 검사하도록 수정했습니다. 변경은 커밋·푸시 없이 작업 트리에 남겼습니다.

## 변경 파일

- `scripts/harness-{company-complete,worker-evidence-validate,lessons-gate,stop}.sh` — 등급별 검사, 완료·취소 분기, 상향 시 증거 보존.
- `commands/{goal,submission,hot-fix}.md` — 등급 분류와 명시적 완료 절차.
- `HR-Resource/{ceo,cto,cqo,hiring,resource-manager,ops}/SKILL.md` — 직접 실행 허용 범위와 보고서 경량화.
- `assets/templates/AGENTS*.template`, `config.json` — 설치 프로젝트의 등급 규칙과 설정.
- `tests/mission-tiers.sh` — 신규 회귀 검사.
- `apps/harness-dashboard/lib/__tests__/sandbox-e2e.test.ts` — 오래된 버전 기대값 수정.
- `package.json`, `package-lock.json`, `CHANGELOG.md` — 7.1.58 및 검증·측정 한계 기록.

## 확인

- 신규 회귀 77개와 기존 테스트 34개 통과.
- 문법 검사, 설치 계약, 패키징 dry-run 통과.
- graphify 코드 그래프 갱신.
- 실제 LLM 작업의 시간 단축률은 미측정입니다.

## 리뷰 반영

- 4차 리뷰는 추가 지적 없이 합의했습니다. 마지막 무효 판정의 이전 PASS 재사용 금지와 거부 시 상태 보존을 구현·검증했습니다.