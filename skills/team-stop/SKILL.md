---
name: harness-team-stop
description: "v4 Agent Teams 중지. 실행 중인 Teammate를 모두 해산한다. 트리거: '/harness-team-stop', 'team 중지', 'agent team 멈춰', '팀 멈춰', '팀 중지'"
disable-model-invocation: false
---

# /harness-team-stop — Agent Teams 중지

## 실행

모든 Teammate에게 현재 작업을 마무리하고 종료하라고 메시지를 보내세요.

Queue 상태는 보존되므로, `/harness-team-action`으로 다시 시작할 수 있습니다.

## 재시작

```
❯ /harness-team-action
```
