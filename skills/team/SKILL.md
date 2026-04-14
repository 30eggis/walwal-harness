---
name: harness-team
description: "v4 Parallel Agent Teams 모드 실행. 3개 Team이 Feature 단위 Gen→Eval 루프를 병렬 실행하는 tmux Studio를 띄운다."
---

# /harness-team — Parallel Agent Teams

이 스킬이 호출되면 **즉시** tmux Studio v4를 실행합니다.

## 실행 절차

1. `npx walwal-harness v4` 를 Bash로 실행
2. 현재 Claude 세션은 종료됨 (tmux가 터미널을 인수)
3. tmux Studio v4 레이아웃이 활성화:
   - Main (left): Claude --dangerously-skip-permissions 자동 실행
   - Dashboard (mid): Feature Queue + Team 상태 실시간 갱신
   - Team 1~3 (right): claude -p headless worker 자동 실행

## 실행

아래 명령을 **반드시 실행**하세요. 설명이나 확인 없이 바로 실행합니다:

```bash
exec npx walwal-harness v4
```

위 명령은 `exec`로 현재 셸을 대체하므로, Claude 세션이 tmux Studio로 전환됩니다.
