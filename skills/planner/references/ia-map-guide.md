# IA-MAP Guide

## 형식

```
├── path/to/dir/    # [TAG] 한줄 설명    → 소유 에이전트
```

## 태그

| 태그 | 의미 | 소유 |
|------|------|------|
| `[BE]` | Backend | Generator-Backend |
| `[FE]` | Frontend | Generator-Frontend |
| `[HARNESS]` | 하네스 시스템 | Planner / Evaluator |
| `[META]` | 프로젝트 메타 | Planner |
| `[INFRA]` | 인프라/배포 | Planner |
| `[TEST]` | 테스트 코드 | Evaluator / Generator |
| `[?]` | 미분류 | TBD (Planner가 확정) |

## 갱신 시점

- Sprint 0 (최초): 전체 구조 설계
- Sprint 간 전환: 새 폴더/파일 반영, Change Request 처리
- Generator/Evaluator가 남긴 Change Request 검토 후 반영

## 규칙

- Planner만 AGENTS.md 수정 가능
- Generator는 sprint-contract.md에 `## Change Request`로 요청
- Evaluator는 evaluation에 `## AGENTS.md Drift`로 보고
