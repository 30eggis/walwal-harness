---
name: harness-team-action
description: "v4 Agent Teams 시작. feature-queue를 초기화하고 3개 Team worker를 가동한다. 트리거: '/harness-team-action', 'team 시작', 'agent team 가동', '팀 시작'"
disable-model-invocation: false
---

# /harness-team-action — Agent Teams 가동

## 이 스킬이 호출되면

feature-list.json에서 feature-queue.json을 생성(또는 복구)하고, Team worker 3개를 백그라운드 실행합니다. 이미 실행 중인 worker가 있으면 중복 실행하지 않습니다.

## 실행 절차

**아래 명령을 순서대로 실행하세요. 설명 없이 바로 실행합니다.**

### 1. 기존 worker 정리 (중복 방지)

```bash
pkill -f "harness-team-worker" 2>/dev/null || true
sleep 1
```

### 2. Queue 초기화 또는 복구

feature-queue.json이 없으면 feature-list.json에서 생성합니다:

```bash
if [ ! -f .harness/actions/feature-queue.json ]; then
  bash scripts/harness-queue-manager.sh init .
else
  bash scripts/harness-queue-manager.sh recover .
fi
```

### 3. Team Worker 백그라운드 실행

```bash
nohup bash scripts/harness-team-worker.sh 1 . > /tmp/harness-team-1.log 2>&1 &
nohup bash scripts/harness-team-worker.sh 2 . > /tmp/harness-team-2.log 2>&1 &
nohup bash scripts/harness-team-worker.sh 3 . > /tmp/harness-team-3.log 2>&1 &
echo "3 Teams started. Logs: /tmp/harness-team-{1,2,3}.log"
```

### 4. 상태 확인

```bash
bash scripts/harness-queue-manager.sh status .
```

## 실행 후

이 세션은 **오케스트레이터**입니다. Teams가 자율적으로 Gen→Eval을 수행합니다.
- `/harness-generator-*`, `/harness-evaluator-*` 호출 금지
- 상태 확인: `bash scripts/harness-queue-manager.sh status .`
- 실패 feature 재큐: `bash scripts/harness-queue-manager.sh requeue F-XXX .`
- 로그 확인: `tail -f /tmp/harness-team-1.log`
- 중지: `/harness-team-stop`
