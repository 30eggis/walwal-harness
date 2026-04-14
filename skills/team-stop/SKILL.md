---
name: harness-team-stop
description: "v4 Agent Teams 중지 + Studio 정리. 실행 중인 Teammate 해산, tmux 세션 종료. 트리거: '/harness-team-stop', 'team 중지', 'agent team 멈춰', '팀 멈춰', '팀 중지'"
disable-model-invocation: false
---

# /harness-team-stop — Agent Teams 중지

## Step 1: Queue 상태 저장

현재 in_progress feature를 ready로 복구합니다 (재시작 시 이어서 가능):

```bash
bash scripts/harness-queue-manager.sh recover .
bash scripts/harness-queue-manager.sh status .
```

## Step 2: tmux Studio 세션 정리

```bash
tmux kill-session -t harness-studio 2>/dev/null && echo "Studio session killed." || echo "No studio session."
```

## Step 3: 완료 안내

```
Teams 중지 완료.
- Queue 상태 보존됨 (in_progress → ready로 복구)
- 재시작: /harness-team-action
```
