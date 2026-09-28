# 테스트 지연 원인 분석과 검증 증거 재사용 구현

## 요약

ACFEFW-62의 약 106분은 전체 테스트 반복보다 검증 스크립트 결함·보안 복구·기록 정정에 따른 재작업이 주원인이었습니다. 필요한 재검증은 유지하면서, 조건이 같은 성공 증거를 재사용하고 검증 산출물의 누출·실패 누락을 예방하도록 설계대로 구현했습니다. 커밋·푸시 없이 작업 트리에 남겼으며 외부 프로젝트는 수정하지 않았습니다.

## 변경 파일

- `scripts/harness-verify-fingerprint.sh` — 실행 전후 소스 지문과 기준 실행 기록.
- `scripts/harness-secret-scan.sh` — 비밀 값 노출 없이 누출·정상·검사 실패 구분.
- `HR-Resource/cqo/SKILL.md` — 증거 재사용 조건과 산출물 위생 규칙.
- `HR-Resource/cto/SKILL.md` — 검증 워커에게 해당 규칙 전달.
- `assets/templates/AGENTS.md.template`, `AGENTS-ko.md.template` — 재사용 규칙 일치.
- `tests/verify-evidence.sh` — 신규 스크립트 회귀 검사.
- `CHANGELOG.md` — 변경 내용 기록.
- [verification-analysis.md](/Users/ted/project/walwal-harness/.myterm/jobs/20260928-200727/verification-analysis.md) — 시간 재측정, 원인·타당성 분석, 예방 항목 10개 대조.

## 확인

- 신규 회귀 검사 **62개 통과**, 기존 tier 검사 **91개 및 부가 검사 통과**.
- 문법 검사·패키지 포함·실제 init 설치 계약 확인 통과.
- `graphify update .` 정상 종료.
- 시나리오 작업은 현재 기록 기준 **경과 237분·활동 131분**으로 정정했습니다.
- ViOnyx에 적용하려면 릴리스 후 하네스 재설치가 필요합니다.

## 리뷰 반영

- **누출 검사 실패 구분: 채택** — 읽기 오류를 정상 결과로 처리하지 않으며 누출과 오류가 함께 있는 경우도 검증했습니다.
- **과거 증거 재사용 판정 모순: 채택** — 기존 coverage 실패 결과는 재사용 불가로 유지하고, 성공 기준 실행을 가정한 경우와 분리했습니다.
- **4차 설계리뷰:** 추가 지적 없이 합의된 설계를 반영했습니다.