---
name: harness-team-stop
description: "v4 Agent Teams 중지. 실행 중인 Team worker 프로세스를 종료한다. 트리거: '/harness-team-stop', 'team 중지', 'agent team 멈춰', '팀 멈춰'"
disable-model-invocation: false
---

# /harness-team-stop — Agent Teams 중지

## 이 스킬이 호출되면

실행 중인 모든 Team worker 프로세스를 종료합니다. Queue 상태는 보존되므로, `/harness-team-action`으로 다시 시작할 수 있습니다.

## 실행 절차

**아래 명령을 실행하세요:**

```bash
pkill -f "harness-team-worker" 2>/dev/null && echo "All Teams stopped." || echo "No running Teams found."
```

### 상태 확인

```bash
bash scripts/harness-queue-manager.sh status .
```

## 재시작하려면

```
❯ /harness-team-action
```
