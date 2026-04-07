# IA Structure Compliance — Step 0 (Gate)

## 검증 방법

```bash
# 1. 실제 폴더 구조 확인
ls -R apps/ libs/ 2>/dev/null

# 2. git diff로 소유권 위반 검출
git log --name-only --pretty=format: HEAD~[sprint_commits].. | sort -u
```

## 검증 항목

| 검증 | 판정 | 예시 |
|------|------|------|
| IA-MAP 경로가 실제 존재하는가 | 누락 → FAIL | apps/service-a/ 미생성 |
| IA-MAP에 없는 경로가 생겼는가 | 미등록 → DRIFT 기록 | apps/service-c/ 무단 생성 |
| [BE] 소유를 FE가 수정했는가 | 침범 → FAIL | apps/gateway/ FE 수정 |
| [FE] 소유를 BE가 수정했는가 | 침범 → FAIL | apps/web/ BE 수정 |
| [META]/[HARNESS]를 Generator가 수정했는가 | 침범 → FAIL | AGENTS.md 수정 |

## 판정 규칙

- **경로 누락 / 소유권 침범** → 즉시 FAIL, Step 1 이하 SKIP
- **미등록 경로 (Drift)** → FAIL 아님, evaluation에 `## AGENTS.md Drift` 기록

## Output (evaluation-functional.md에 포함)

```markdown
## Step 0: IA Structure Compliance
- Verdict: PASS / FAIL (GATE)
- IA-MAP paths checked: [N]개
- Missing paths: [목록 또는 "none"]
- Unregistered paths: [목록 또는 "none"]
- Ownership violations: [목록 또는 "none"]
```
