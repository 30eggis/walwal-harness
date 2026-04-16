# /harness-stop — Team Mode 중단

실행 중인 Team 모드를 안전하게 중단합니다.
진행 중인 피처는 ready 상태로 복구되어, 이후 Solo 또는 Team 모드에서 이어갈 수 있습니다.

## 실행 절차

### Step 1: 현재 모드 확인

```bash
MODE=$(jq -r '.mode // "solo"' .harness/progress.json 2>/dev/null)
echo "현재 모드: $MODE"
```

- **solo** → "이미 Solo 모드입니다. Team을 시작하려면 /harness-team 을 사용하세요." 안내 후 중단.
- **team** → Step 2로 진행.

### Step 2: Queue 상태 보존

```bash
# in_progress features를 ready로 복구
bash scripts/harness-queue-manager.sh recover .

# 현재 큐 상태 출력
bash scripts/harness-queue-manager.sh status .
```

### Step 3: 모드 전환

```bash
# mode를 paused로 설정 (team에서 명시적으로 중단)
jq '.mode = "paused" | .team_state.active_teams = 0 | .team_state.paused_at = (now | todate)' .harness/progress.json > /tmp/progress_tmp.json && mv /tmp/progress_tmp.json .harness/progress.json
```

### Step 4: tmux 세션 정리 (선택)

```bash
# harness-studio tmux 세션이 있으면 정리
tmux kill-session -t harness-studio 2>/dev/null && echo "tmux 세션 정리 완료" || echo "활성 tmux 세션 없음"
```

### Step 5: 재개 안내

다음 안내를 사용자에게 전달합니다:

```
Team 모드가 안전하게 중단되었습니다.
진행 중이던 피처는 ready 상태로 복구되었습니다.

재개 방법:
  /harness-team    → Team 모드 재개 (남은 피처 자동 할당)
  /harness-solo    → Solo 모드로 전환 (프롬프트 기반 순차 진행)
```
