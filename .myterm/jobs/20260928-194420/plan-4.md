# MyTerminal 이슈: 단계 진행 표시·멈춤 경고·중단 시 프로세스 트리 정리 (4차, 3차 리뷰 반영)

## 요약
이 문서는 `/Users/ted/project/myterminal`에 그대로 이슈로 올릴 수 있게 정리한 것입니다. 3차 설계(`plan-3.md`)가 바탕이고, 3차 리뷰(`planreview-3.md`)의 지적 네 건을 모두 설계에 넣었습니다.

**문제**
- 작업 카드에는 "설계 중 · 123:21"처럼 경과 시간과 tmux 마지막 6줄만 나옵니다. 사용자는 지금 무슨 일을 하는지, 기록이 언제 끊겼는지, 얼마나 남았는지 알 수 없습니다.
- "중단"을 눌러도 pane 루트에만 SIGHUP이 갑니다. 그래서 claude·codex와 그 하위 도구가 계속 살아 있습니다.

**이번 변경**
- 카드에 마지막 기록, 예상 시간, 무기록 경고를 보여 줍니다.
- 중단 처리를 바꿉니다. 대상 프로세스를 식별해 먼저 디스크에 기록하고, 트리를 얼린(SIGSTOP) 뒤 강제 종료(SIGKILL)합니다. 앱이 재시작돼도 이어서 확인하고, 종료가 확인됐을 때만 실패를 기록합니다.

**변경 범위**
- walwal-harness 쪽은 바꾸지 않습니다.

---

**이슈 제목(안):** `[파이프라인] 단계 진행 상황이 안 보이고, 중단해도 CLI 프로세스가 남음`

**재현**
1. 설계 단계가 오래 걸리는 요청을 보냅니다.
2. 카드에는 "설계 중 · 123:21"만 보입니다. 무엇을 하는지, 기록이 언제 끊겼는지, 얼마나 남았는지 알 수 없습니다.
3. "중단"을 누릅니다.
4. `ps -axo pid,ppid,command | grep -E 'claude -p|codex exec'`로 확인하면 이번 작업의 CLI가 아직 남아 있습니다.

**원인**
- `JobCard`의 `TraceChips`는 `isBackground`(claude·codex·hook) 이벤트를 걸러 냅니다. 그래서 설계·리뷰 단계의 도구 호출이 카드에 보이지 않습니다.
- `PipelineRunner.updateLive`는 경과 시간만 계산합니다. 활동 시각이나 예상 시간은 없습니다.
- `PipelineRunner.cancel`(346행)은 `Tmux.killWindow`만 호출합니다. 이 호출은 pane 프로세스(`myterm-agent`)에 SIGHUP을 보낼 뿐이라, `runStreaming`이 띄운 CLI와 그 자손은 살아남습니다.

## 요구 분석
- **무엇을 하는지:** trace에서 마지막 이벤트(`kind != "change"`)를 골라 "마지막 기록 · Bash · ls … · 12분 전"으로 보여 줍니다. hook 이벤트도 포함합니다.
- **어디까지 진행했는지**
  - 단계 단위 진행은 기존 `PlacementRow`의 `▶` 표시를 그대로 씁니다.
  - 단계 안 진척률은 CLI가 알려 주지 않으므로 지어내지 않고 "단계 안 진척은 알 수 없음"으로 표기합니다.
- **얼마나 남았는지**
  - 같은 워크스페이스에서 같은 단계·같은 CLI로 성공한 최근 10회 소요 시간의 중앙값을 씁니다. 예: "보통 4분 (지난 7회) · 약 2분 남음" / "보통보다 길어지는 중".
  - 표본이 2개 미만이면 "예상 시간 자료 부족"으로 표기합니다.
- **멈춤 경고:** 새 기록이 5분 이상 없으면 주황색 경고를 띄웁니다. 자동 중단은 하지 않습니다.
- **중단 시 트리 전체 종료**
  - 종료가 확인된 경우에만 실패로 기록합니다.
  - 종료 대기 중이거나 종료를 확인하지 못한 상태에서는 자동 진행, 창 소멸을 이유로 한 실패 판정, 다시 시도를 모두 막습니다.
- **(3차 리뷰 HIGH-1) 부분 종료 뒤 재중단:** 창이나 루트가 사라졌다는 사실은 완료의 근거가 아닙니다. 처음 확보한 대상 목록을 기준으로 이어서 확인합니다.
- **(3차 리뷰 HIGH-2) 앱 재시작:** 중단 상태와 대상 목록을 신호를 보내기 **전에** 작업 폴더에 기록하고, 시작할 때 복원합니다.
- **(3차 리뷰 HIGH-3) 프로세스 식별:** `args` 비교 대신 `(pid, 시작 시각)`으로 실행 인스턴스를 구분합니다. 식별이 불확실하면 "확인 안 됨"으로 둡니다.
- **(3차 리뷰 MEDIUM) 재중단의 기준:** 현재 `activeStep`이 아니라 저장해 둔 중단 기록(단계·회차·대상)을 기준으로 동작합니다.

## 모호점과 해소안
- **자동 중단 여부** → 하지 않습니다. trace에는 도구 호출·결과·훅만 남습니다. 기록이 없다는 것은 멈췄을 수 있다는 근거일 뿐, 멈췄다는 확정이 아닙니다.
- **"활동" 시각** → `max(trace 수정 시각, 화면이 바뀐 시각, 단계 시작 시각)`
  - 단계(`jobId-step-round`)마다 처음 읽은 화면은 비교 기준으로만 저장하고 활동으로 치지 않습니다.
- **경고 기준** → `StepClock.quietAfter = 300` 상수로 둡니다. 나중에 조정하는 손잡이입니다.
- **예상 시간 표본** → `.started` 수정 시각부터 `.result.json` 수정 시각까지로 계산합니다.
  - `ok == true`이고 소요 시간이 0보다 큰 것만 씁니다.
  - 단계가 바뀔 때 한 번 계산해 캐시합니다.
- **프로세스 식별 방법** → `proc_pidinfo(pid, PROC_PIDTBSDINFO)`의 `pbi_start_tvsec`/`pbi_start_tvusec`와 `pbi_ppid`를 씁니다(Darwin libproc).
  - `exec`는 pid와 시작 시각을 유지하므로 같은 실행으로 봅니다. pid가 재사용되면 시작 시각이 달라지므로 다른 실행입니다.
  - `ps` 파서(`maxSplits: 4`)는 바꾸지 않습니다. 트리 탐색에는 기존 `processTable()`을 쓰고, 식별만 `proc_pidinfo`로 합니다.
- **대상 수집과 경합**
  - 루트부터 위에서 아래로 얼립니다.
  - 자식 후보는 다음 두 조건을 모두 만족할 때만 대상에 넣고 SIGSTOP을 보냅니다.
    - `proc_pidinfo`로 다시 읽은 `pbi_ppid`가 **이미 얼린 대상**의 pid일 것
    - 그 후보의 시작 시각이 부모의 시작 시각보다 이르지 않을 것
  - 얼어 있는 부모는 fork할 수 없습니다. 따라서 ppid가 얼린 부모인 프로세스는 그 부모의 진짜 자식입니다. `ps`를 읽은 뒤 pid가 재사용되는 경합도 이 조건으로 걸러집니다.
  - 새 대상이 더 나오지 않을 때까지 반복합니다(최대 20회).
- **중간 프로세스가 먼저 죽어 launchd로 입양된 손자** → 추가 규칙으로 잡습니다.
  - `getsid(pid) == 루트 pid`이고, 시작 시각이 루트 시작 시각 이후인 프로세스도 대상에 넣습니다. tmux pane 루트는 세션 리더이기 때문입니다.
  - 스스로 `setsid`한 데몬화 프로세스는 잡지 못합니다. 이 한계는 이 문서에만 적어 둡니다.
- **종료 방식** → SIGSTOP으로 트리를 얼린 뒤 SIGKILL을 보냅니다.
  - SIGTERM을 받고 정리할 기회는 포기합니다. 중단한 단계의 결과는 어차피 버리기 때문입니다.
  - SIGKILL 직전에 대상의 `(pid, 시작 시각)`을 다시 대조하고, 일치할 때만 보냅니다.
- **종료 확인** → 대상마다 다음 중 하나이면 "종료됨"입니다.
  - `proc_pidinfo`가 `ESRCH`로 실패함
  - 시작 시각이 달라짐(원래 실행은 끝났고 pid만 재사용됨)
  - `EPERM`이나 그 밖의 오류는 "미확인"으로 봅니다.
  - 확인은 100ms 간격으로 최대 5초 동안 합니다. 이에 더해 `getsid == 루트`로 다시 훑었을 때 새 잔존 프로세스가 없어야 합니다.
- **중단 기록 파일** → `<step>-<round>.stop.json`
  - 담는 값: `{step, round, rootPid, rootStart, targets:[{pid, startSec, startUsec}], state: "freezing"|"killing"|"unconfirmed"|"confirmed", reason?}`
  - 기록 시점: 신호를 보내기 전에 `JobJSON.save`로 원자적으로 씁니다. 대상이 추가될 때마다 먼저 기록을 갱신한 다음 신호를 보냅니다.
- **앱을 재시작했을 때** → 중단 기록이 `confirmed`가 아니면 `unconfirmed`로 복원합니다. 차단 상태를 유지하고 "다시 중단"을 안내합니다.
  - 자동으로 다시 중단하지 않습니다. 얼어 있는 프로세스는 자원을 쓰지 않으므로 사용자가 누를 때까지 두어도 됩니다.
  - `confirmed` 기록이 남아 있으면 마무리 단계(실패 기록 → 창 닫기 → 기록 삭제)를 멱등하게 이어서 합니다.
- **결과 파일과 중단이 겹친 경우** → 결과 파일이 이미 있으면 기존 가드대로 실패를 덮어쓰지 않습니다. 그래도 중단 기록이 있는 동안은 차단이 유지됩니다. 중단 기록이 사라진 뒤에만 다음으로 진행합니다.

## 변경 파일
- **`Sources/MyTerminal/Pipeline/StepClock.swift` (새 파일, 순수 함수)**
  - `quietAfter = 300`
  - `typical(_:)`: 0 이하 값을 빼고, 값이 2개 이상일 때만 중앙값을 냅니다.
  - `elapsedText(_:)`: 60분 미만은 `m:ss`, 60분 이상은 `N시간 M분`
  - `ago(_:)`
  - `estimate(elapsed:typical:samples:)`
  - `isQuiet(idle:)`
- **`Sources/MyTerminal/Sessions/ProcessMonitor.swift` (`ProcessScanner` actor 확장)**
  - `processTable()`: 실패하거나 종료 코드가 0이 아니면 `nil`을 돌려줍니다. 기존 호출부(`scan`, `terminate`, `descendants`)는 `?? [:]`를 붙여 지금 동작을 유지합니다.
  - `struct ProcID: Codable, Hashable { pid: Int32; startSec: Int64; startUsec: Int32 }`와 `static func identity(_ pid:) -> Result<(ProcID, ppid: Int32), ProbeError>`를 추가합니다. `proc_pidinfo`를 쓰고, 오류를 `.gone`(ESRCH)과 `.unknown(errno)`으로 나눕니다.
  - `func freezeTree(root: Int32, record: (Set<ProcID>) throws -> Void) async -> Result<Set<ProcID>, StopError>`
    - 위에서 아래로 수집하면서 SIGSTOP을 보냅니다.
    - 새 대상은 `record`로 먼저 저장한 뒤에 신호를 보냅니다. 저장에 실패하면 신호를 보내지 않고 `.unconfirmed`를 돌려줍니다.
  - `func killAndConfirm(_ targets: Set<ProcID>, sessionRoot: ProcID?) async -> StopOutcome`
    - 식별이 일치하는 대상에만 SIGKILL을 보내고, 확인 루프를 돕니다.
    - `sessionRoot`가 있으면 `getsid`로 다시 훑어 새로 발견한 대상도 얼리고 죽입니다.
  - `enum StopOutcome { case stopped, unconfirmed(String) }`
  - 순수 판정 `static func isGone(_ target: ProcID, probe: Result<(ProcID, Int32), ProbeError>) -> Bool?`를 분리해 테스트합니다. `nil`은 미확인을 뜻합니다.
  - 기존 `terminate`와 `ProcessMonitor.stop/stopAll`은 바꾸지 않습니다. 사용자가 프로세스 목록에서 직접 끄는 경로이기 때문입니다.
- **`Sources/MyTerminal/Pipeline/Job.swift`**
  - `JobFiles.stop(_ step:, _ round:) -> URL`(`"\(step.rawValue)-\(round).stop.json"`)과 `StopRecord: Codable`을 추가합니다.
  - `JobSnapshot`에 `pendingStop: StopRecord?`를 추가합니다. 작업 폴더에서 `*.stop.json`을 찾아 읽습니다.
  - `retryFailedStep`이 파일을 옮길 때 `.stop.json`은 대상에 넣지 않습니다. 이 파일은 확인이 끝나면 지워지기 때문입니다.
- **`Sources/MyTerminal/Pipeline/PipelineRunner.swift`**
  - `Live` 필드를 추가합니다: `lastActivity`, `lastEvent: (title, at)?`, `typical`, `samples`
  - `@ObservationIgnored` 캐시(`screens`, `typicals`)를 둡니다. `updateLive`에서 화면을 비교하고 trace를 읽습니다. 활성 단계가 없으면 캐시를 지웁니다.
  - `stepDurations(step:agent:)`를 추가합니다.
  - `@ObservationIgnored let scanner = ProcessScanner()`: 전용 인스턴스를 두어 메인 스레드를 막지 않습니다.
  - 관측 상태 `private(set) var stopping: Set<String>`을 둡니다. 미확인 사유는 `job.pendingStop?.reason`으로 표시합니다. 디스크가 원본입니다.
  - **가드**: `advance(_:)`와 `retry(_:)` 맨 앞에서 `stopping`에 있거나 `job.pendingStop != nil`이면 반환합니다. `start`, `checkAlive`, `recordFailure` 모두 실행되지 않습니다.
  - **`cancel(_ job:)`**
    1. 대상 단계를 정합니다. `job.pendingStop`이 있으면 그 기록의 `(step, round)`와 targets를 이어서 씁니다. 없을 때만 `job.activeStep`을 씁니다. 둘 다 없으면 반환합니다. 중복 실행은 `stopping`으로 막습니다.
    2. 첫 중단이면 `list-panes`로 루트 pid를 읽습니다.
       - pid를 읽지 못하고 창이 **없으면**, 기존 `checkAlive`와 같은 조건이므로 `recordFailure`만 합니다. 이 경우는 대상이 비어 있고 쓰는 쪽도 이미 없습니다.
       - pid를 읽지 못하고 창이 **있으면**, 미확인 기록을 남깁니다(사유: "작업 프로세스를 찾지 못했어요").
    3. 루트 식별 정보로 `StopRecord(state: .freezing)`를 먼저 저장하고 `freezeTree`를 호출합니다. 재중단일 때는 기록된 targets를 기준으로 하되, 식별이 일치하는 루트가 살아 있으면 새 대상도 더 수집합니다.
    4. 상태를 `.killing`으로 저장한 뒤 `killAndConfirm`을 호출합니다.
    5. 결과가 `.stopped`이면 `state: .confirmed` 저장 → `recordFailure(…, "사용자가 중단했어요")` → `Tmux.killWindow` → stop 파일 삭제 순서로 처리합니다.
    6. 결과가 `.unconfirmed(r)`이면 `state: .unconfirmed, reason: r`을 저장합니다. 창을 닫지 않고, 실패를 기록하지 않으며, `lastError`를 설정합니다.
    7. `stopping.remove` 후 `refresh`합니다.
  - **`init`/`reload`**: `pendingStop.state`가 `.freezing`이나 `.killing`이면 `.unconfirmed`로 다시 씁니다(사유: "앱이 중단 도중 종료됨"). `.confirmed`이면 5번 마무리 단계를 이어서 합니다.
  - **`migrateLegacyPlan`**: pane pid를 기다리는 부분을 같은 중단 절차로 바꿉니다. 결과가 `.unconfirmed`이면 plan-1을 지우거나 옮기지 않고, meta도 바꾸지 않으며, 새로 시작하지 않습니다.
  - `tick()`은 테스트를 위해 `private`에서 internal로 바꿉니다.
- **`Sources/MyTerminal/Home/JobCard.swift`**
  - `elapsed` 표시에 `StepClock.elapsedText`를 씁니다.
  - 실행 중인 `AgentRow` 위에 `StepStatusLine`(같은 파일 안의 private 뷰)을 둡니다.
    - 1줄: 마지막 기록과 몇 분 전인지
    - 2줄: 예상 시간과 "단계 안 진척은 알 수 없음"
    - `isQuiet`이면 주황색으로 "N분째 새 기록 없음 — 오래 걸리는 중이거나 멈췄을 수 있어요. 필요하면 중단 후 다시 시도"를 보여 줍니다.
  - 중단 버튼(261·275행)
    - `stopping` 중이면 비활성화하고 "중단하는 중…"으로 표시합니다.
    - `job.pendingStop`이 있으면 **phase와 관계없이** 사유를 경고색으로 보이고, 버튼 제목을 "다시 중단"으로 바꿉니다.
  - "다시 시도"(278행): `stopping` 중이거나 `pendingStop`이 있으면 비활성화합니다.
- **`Sources/MyTermAgent/main.swift`**: 변경하지 않습니다.

## 검증 규칙
- trace·started·result 파일이 없거나 읽기에 실패하면 `nil`로 봅니다. 이 값은 표시에만 쓰고, 실행 판단에는 쓰지 않습니다.
- **실패 기록은 `.stopped`일 때만** 남깁니다. 아래 경우는 모두 `.unconfirmed`로 처리하고 기록을 남기지 않습니다.
  - 표 조회 실패, pid 조회 실패
  - 식별 오류(`EPERM` 등)
  - 신호 오류(`ESRCH` 제외)
  - 5초 뒤에도 남은 대상
  - 20회 안에 대상 수집이 끝나지 않음
  - stop 기록 저장 실패
- **창·루트가 사라진 것은 완료 근거가 아닙니다.** 판정은 기록된 targets 전부와 `getsid` 재탐색 결과를 기준으로 합니다. 예외는 "첫 중단인데 창도 pid도 없음" 하나뿐이며, 이는 기존 `checkAlive`와 같은 판정입니다.
- **신호는 기록된 뒤에만 보냅니다.** 앱이 어느 시점에 죽어도, 보낸 신호의 대상은 모두 디스크에 남아 있습니다.
- **신호 대상 조건**
  - pid 0, pid 1, 음수 pid, 앱 자신은 제외합니다.
  - 그룹 kill(`kill(-pgid)`)은 쓰지 않습니다.
  - 식별 정보(pid, 시작 시각)가 일치하는 경우에만 신호를 보냅니다.
- **`stopping`이거나 `pendingStop`이 있는 동안**에는 `tick`이 여러 번 돌아도 `start`, `checkAlive`, `recordFailure`가 실행되지 않고, `retry`도 동작하지 않습니다.
- **경계값**
  - 무기록 시간: 299초는 경고 없음, 300초는 경고
  - 예상 시간 표본: 1개는 "자료 부족", 2개부터 표시
  - 경과 시간: 3599초는 `59:59`, 3600초는 `1시간 0분`
  - 대상 수집 반복: 20회를 넘으면 미확인

## 테스트 계획
- **`Tests/MyTerminalTests/StepClockTests.swift`**
  - `typical`: `[]`, `[60]`, `[0,-5,60]`은 nil / `[60,240]`은 150 / `[60,120,600]`은 120
  - `elapsedText`: 59초, 3599초, 3600초, 7401초
  - `ago`: 30초는 "방금", 125초는 "2분 전"
  - `estimate`: 표본 1개 / 약 2분 남음 / 보통보다 길어지는 중
  - `isQuiet`: 299초와 300초
- **`Tests/MyTerminalTests/ProcessStopTests.swift`** (실제 프로세스를 띄워 확인)
  - **fork 경합**
    - `/bin/sh -c 'while :; do /bin/sleep 30 & /bin/sleep 0.01; done'`를 실행하고 0.5초 뒤 `freezeTree` → `killAndConfirm`을 호출합니다.
    - 결과가 `.stopped`여야 합니다.
    - 테스트 시작 뒤에 생긴 `sleep 30`이 ppid 1 상태로도 남아 있지 않아야 합니다.
  - **부분 종료 후 재중단 (HIGH-1)**
    - 루트는 SIGKILL하고, 자식 하나는 SIGSTOP 상태로 남겨 기록합니다. 대상 2개가 담긴 `StopRecord`로 재현합니다.
    - 다시 `killAndConfirm(기록 targets)`을 호출하면 남은 자식이 종료되고 `.stopped`가 나와야 합니다.
    - 루트가 없다는 이유만으로 `.stopped`가 나오면 안 됩니다. targets 중 하나가 살아 있으면 `.unconfirmed`여야 합니다.
  - **식별 판정 (HIGH-3), `isGone` 순수 함수**
    - 같은 pid에 같은 시작 시각이면 살아 있음(false)
    - 같은 pid에 다른 시작 시각이면서 명령도 같으면 종료됨(true)
    - `exec` 사례: 실제 `sh -c 'exec sleep 30'`은 pid와 시작 시각이 유지되므로 대상으로 남고 종료되어야 합니다.
    - `.unknown(EPERM)`이면 nil(미확인)
  - **입양된 손자**
    - `sh -c '(sleep 30 &) ; sleep 30'`처럼 중간 프로세스가 먼저 끝나 ppid 1로 입양된 손자를 만듭니다.
    - 이 손자도 `getsid` 규칙으로 잡혀 종료되어야 합니다(테스트에서는 루트를 `setsid`로 띄움).
- **러너 테스트 (`FollowUpPipelineTests` 방식)**
  - `plan-1.started`만 두고(창 없음) `plan-1.stop.json`(`state: unconfirmed`)을 둡니다. `tick()`을 3회 호출하고 `retry`를 불러도 `plan-1.result.json`이 생기지 않고 파일에 변화가 없어야 합니다. 가드를 빼면 실패해야 하는 회귀 테스트입니다.
  - **재시작 복원 (HIGH-2)**
    - `state: freezing`인 stop 파일을 두고 `PipelineRunner`를 새로 만들면 `unconfirmed`로 다시 쓰이고 차단이 유지되어야 합니다.
    - `state: confirmed`이면 실패 결과가 기록되고 stop 파일이 삭제되어야 합니다.
  - **activeStep이 없을 때 (MEDIUM)**
    - `plan-1.result.json`(`ok:false`)과 `unconfirmed` stop 파일을 함께 둬서 phase를 `.failed`로 만듭니다.
    - `cancel`이 즉시 반환하지 않고 stop 기록의 단계로 동작해야 합니다. 테스트에서는 scanner를 대체할 수 없으므로, 대상이 이미 종료된 pid인 경우에 `.stopped`와 stop 파일 삭제를 확인합니다.
  - **소요 시간 계산**: `.started`와 `.result.json`의 수정 시각을 조작해 계산 결과를 확인합니다. `ok:false`인 결과는 빠져야 합니다.
- **수동 확인**
  1. `swift build && swift test`
  2. 요청을 보내고 카드에 "마지막 기록 · Read · … · 방금"과 "예상 시간 자료 부족 · 단계 안 진척은 알 수 없음"이 보이는지 확인합니다. 두 번째 작업부터는 "보통 N분 (지난 M회)"이 보여야 합니다.
  3. `quietAfter`를 잠시 30으로 바꾸고 `kill -STOP <claude pid>`를 보내 주황색 경고가 뜨는지 확인합니다. 확인 후 상수는 원래대로 돌립니다.
  4. "중단"을 누르는 동안 "다시 시도"가 비활성화되는지 확인합니다. 5초 안에 실패가 기록되고, `ps … | grep -E 'claude -p|codex exec|myterm-agent'`에 이번 작업의 프로세스가 남지 않아야 합니다.
  5. 중단 도중(`.stop.json`이 `freezing`일 때) 앱을 강제 종료하고 다시 켭니다. "다시 중단"이 안내되고 자동 진행이 막혀 있어야 합니다. 누르면 정리가 끝나야 합니다.
- **참고**
  - 이미 남아 있는 고아 claude 프로세스는 이 변경과 별개로 한 번 수동으로 정리해야 합니다(`kill <pid>`).
  - 알려진 한계: 스스로 `setsid`한 프로세스는 잡지 못합니다. 강제 종료된 도구가 남긴 lock 파일(git 등)도 정리하지 않습니다.

## 리뷰 반영 (3차 리뷰 → 4차)
- **[HIGH-1] 부분 종료 뒤 재중단 시 누락 → 반영**
  - 대상 목록을 `.stop.json`에 보존하고, 재중단 때 그 목록을 이어서 확인합니다.
  - 창·루트 소멸은 완료 근거에서 뺐습니다.
  - "루트가 없으면 `.stopped`"라는 3차 테스트는 삭제하고 반대 방향 테스트로 바꿨습니다.
- **[HIGH-2] 앱 재시작 시 차단 소실 → 반영**
  - 신호를 보내기 전에 기록하고, 시작할 때 `freezing`/`killing` 상태를 `unconfirmed`로 복원합니다.
  - `confirmed`는 마무리 단계를 멱등하게 재개합니다.
  - 차단 여부는 메모리가 아니라 디스크(`pendingStop`)가 원본입니다.
- **[HIGH-3] `args` 비교로는 식별 불가 → 반영**
  - `proc_pidinfo`의 시작 시각으로 `(pid, 시작 시각)` 식별로 바꿨습니다.
  - 자식은 "이미 얼린 부모의 ppid" 조건으로만 받아들여, 얼리기 전 경합을 없앴습니다.
  - 식별 오류는 미확인으로 처리합니다. `exec` 사례와 pid 재사용 사례 테스트를 추가했습니다.
- **[MEDIUM] 재중단이 `activeStep`에 의존 → 반영**
  - `cancel`은 `pendingStop`의 단계·회차·대상을 우선으로 씁니다.
  - 카드는 phase와 관계없이 `pendingStop`이 있으면 "다시 중단"을 보여 줍니다.