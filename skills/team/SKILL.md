---
name: harness-team
description: "v4 Parallel Agent Teams 모드 활성화. feature-queue 초기화 후 3개 Team worker를 백그라운드 실행한다. 트리거: '/harness-team', 'agent team 시작', 'team 모드'"
disable-model-invocation: false
---

# /harness-team — Parallel Agent Teams 활성화

## 이 스킬이 호출되면

1. **feature-queue.json 확인/초기화** — 없으면 feature-list.json에서 생성, 있으면 stale 복구
2. **3개 Team Worker를 백그라운드로 시작** — 각각 claude -p로 Gen→Eval 루프 자율 실행
3. **현재 세션은 유지** — 사용자는 오케스트레이터 역할 (모니터링, 실패 대응, 수동 개입)

## 실행 절차

아래 명령을 순서대로 실행하세요:

### Step 1: Queue 초기화/복구

```bash
bash scripts/harness-queue-manager.sh init .
```

이미 queue가 있으면:

```bash
bash scripts/harness-queue-manager.sh recover .
```

### Step 2: Team Worker 백그라운드 실행

```bash
nohup bash scripts/harness-team-worker.sh 1 . > /tmp/harness-team-1.log 2>&1 &
nohup bash scripts/harness-team-worker.sh 2 . > /tmp/harness-team-2.log 2>&1 &
nohup bash scripts/harness-team-worker.sh 3 . > /tmp/harness-team-3.log 2>&1 &
```

### Step 3: 상태 확인

```bash
bash scripts/harness-queue-manager.sh status .
```

## 실행 후 역할

이 세션은 **오케스트레이터**입니다:
- `/harness-generator-*`, `/harness-evaluator-*` 스킬 호출 금지 (Teams가 처리)
- 할 수 있는 것: 큐 상태 확인, 실패 분석, 코드 리뷰, gotcha 등록, requeue

### 유용한 명령

```bash
# 큐 상태
bash scripts/harness-queue-manager.sh status .

# 실패한 feature 재큐
bash scripts/harness-queue-manager.sh requeue F-XXX .

# Team 로그 실시간 확인
tail -f /tmp/harness-team-1.log
tail -f /tmp/harness-team-2.log
tail -f /tmp/harness-team-3.log

# 모든 Team 중지
pkill -f harness-team-worker || true
```

## tmux Studio (선택사항)

별도 터미널에서 tmux 레이아웃을 원하면:

```bash
npx walwal-harness v4
```

이 명령은 **Claude 세션 밖에서** (일반 터미널에서) 실행해야 합니다.
