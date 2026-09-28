# MyTerminal 진행 단계 표시 + 멈춤 경고 + 중단 시 남는 프로세스 정리 (3차)

## 요약
스크린샷의 "설계 중 · 123:21"은 설계가 123분 동안 계속 진행됐다는 뜻이 아닙니다. 대부분은 기록이 멈춘 뒤에도 경과 시간만 계속 올라간 것입니다. 지금 카드에는 tmux 마지막 6줄과 경과 시간만 나옵니다. 그래서 무엇을 하는지, 기록이 언제 끊겼는지, 얼마나 남았는지 알 수 없습니다.

이번 변경으로 카드에 네 가지를 보여 줍니다.
1. 마지막으로 기록된 일과 그 시각
2. 이번 단계가 보통 걸리는 시간(지난 실행 기준)
3. 새 기록이 오래 없을 때의 경고
4. 단계 안에서 얼마나 진행됐는지는 앱이 알 수 없다는 사실

자동 중단은 하지 않습니다. 사용자가 "중단"을 누르면 순서대로 처리합니다.
1. 그 창의 프로세스 트리를 먼저 얼려서(SIGSTOP) 새 자식 프로세스가 생기지 않게 합니다.
2. 트리 전체를 종료합니다.
3. 종료가 **확인된 경우에만** 실패를 기록합니다.

중단이 진행되는 동안에는 자동 진행, 창이 사라진 것을 이유로 한 실패 판정, 다시 시도를 모두 막습니다.

## 요구 분석
- **무엇을 하는지 알 수 없음**
  - trace에는 도구 호출이 기록됩니다(`Trace.toolUse`).
  - 그런데 카드의 `TraceChips`는 `isBackground`(claude·codex·hook)를 걸러 냅니다. 그래서 설계·리뷰 단계의 평범한 Read·Bash 호출이 카드에 보이지 않습니다.
  - → 걸러 내지 않은 마지막 기록을 "마지막 기록 · Bash · ls … · 12분 전" 형태로 보여 줍니다.
- **어디까지 진행 중인지**
  - 단계 수준(설계→설계리뷰→작업→리뷰)은 기존 `PlacementRow`의 `▶`가 이미 보여 줍니다.
  - 단계 안에서의 %는 CLI가 알려 주지 않으므로 지어내지 않습니다. "단계 안 진척은 알 수 없음"이라고 그대로 적습니다.
- **얼마나 남았는지**
  - 같은 워크스페이스에서 같은 단계·같은 CLI로 성공한 최근 실행 소요 시간의 중앙값을 씁니다.
  - 표시 예: "보통 4분 (지난 7회) · 약 2분 남음", "보통보다 길어지는 중". 표본이 부족하면 "예상 시간 자료 부족".
- **123분씩 모르고 기다림**
  - 새 기록이 5분 넘게 없으면 주황색 경고를 띄웁니다: "N분째 새 기록 없음 — 오래 걸리는 중이거나 멈췄을 수 있어요".
  - 끊을지는 사용자가 "중단"으로 정합니다.
- **(발견) 중단해도 claude가 남음**
  - 지금 `cancel`은 `Tmux.killWindow`로 pane 프로세스(`myterm-agent`)에 SIGHUP만 보냅니다. `runStreaming`이 띄운 CLI와 그 하위 도구는 살아남습니다.
  - → 창의 프로세스 트리 전체를 종료하고 종료를 확인합니다.
- **(2차 리뷰) 중단 중 경합**
  - 종료를 기다리는 동안 1초 주기 `tick → advance → checkAlive`가 먼저 실패를 기록할 수 있습니다. 그러면 다시 시도나 다음 단계 진행이 열립니다. → 이 경로를 막습니다.

## 모호점과 해소안
- **자동 중단 여부** → 하지 않습니다.
  - trace에는 도구 호출·결과·훅만 기록됩니다. 기록이 없다는 것은 멈췄을지 모른다는 근거일 뿐, 멈췄다는 확정이 아닙니다.
- **"활동"의 기준** → `max(trace 파일 수정 시각, 화면 내용이 바뀐 시각, 단계 시작 시각)`
  - 단계마다(작업 id·단계·회차) 처음 읽은 화면은 비교 기준으로만 저장하고 활동으로 치지 않습니다.
- **"마지막 기록"으로 보여 줄 이벤트**
  - `TraceEvent.load`의 마지막 이벤트 중 `kind == "change"`(디스크 변경 알림)는 뺍니다.
  - hook은 포함합니다.
  - "결과 대기 중"처럼 상태를 단정하는 표기는 쓰지 않습니다.
- **경고 기준 5분** → `StepClock.quietAfter = 300` 상수 하나로 둡니다. 나중에 조정하는 손잡이입니다.
- **예상 시간 표본**
  - 대상: `jobs` 가운데 같은 `step`, 같은 CLI(`job.agent(step, round)`), `ok == true`인 최근 10개
  - 소요 시간: `.started` 수정 시각부터 `.result.json` 수정 시각까지
  - 표본이 2개 미만이면 "자료 부족"으로 둡니다. 단계가 바뀔 때 한 번만 계산해 캐시합니다.
- **긴 경과 시간 표기** → 60분 이상은 "2시간 3분"으로 씁니다.
- **종료 방식: 목록 스냅샷 → 트리 얼리기**
  - PID 목록을 한 번 모으면, 신호를 보내기 전에 새로 생긴 자식을 놓칠 수 있습니다(리뷰 지적 수용).
  - 그래서 SIGSTOP을 루트부터 보내고, 프로세스 표를 다시 읽어 새로 보이는 자손에도 SIGSTOP을 보냅니다. 새 pid가 더 나오지 않을 때까지 반복합니다(최대 20회).
  - 트리가 다 얼면 fork할 수 있는 프로세스가 없습니다. 이때 모든 pid에 SIGKILL을 보냅니다.
  - 정상 종료(SIGTERM)의 정리 기회는 포기합니다. 중단한 단계의 결과는 어차피 실패로 버리므로, 새 기록이 생기지 않는 쪽을 택합니다.
  - `git` 같은 도구가 lock 파일을 남길 수 있다는 한계는 알림 문구에 적지 않고, 이 설계서에만 기록합니다.
- **종료 확인 기준**
  - 모든 대상 pid에서 `kill(pid, 0)`이 `ESRCH`를 돌려주면 확인입니다. 확인 대상은 pane 루트를 포함한 트리 전체입니다.
  - 100ms 간격으로 최대 5초 기다립니다.
  - 좀비는 부모(tmux, launchd)가 곧 거둡니다. 5초 안에 사라지지 않으면 **미확인**으로 처리합니다(안전한 쪽).
- **변경 대상 저장소** → `/Users/ted/project/myterminal`만 바꿉니다. walwal-harness는 건드리지 않습니다.

## 변경 파일
- **`Sources/MyTerminal/Pipeline/StepClock.swift` (새 파일, 순수 함수)**
  - `static let quietAfter: TimeInterval = 300`
  - `typical(_:) -> TimeInterval?`: 0 이하 값을 빼고, 2개 이상일 때만 중앙값을 돌려줍니다.
  - `elapsedText(_:)`: 60분 미만은 `m:ss`, 60분 이상은 `N시간 M분`
  - `ago(_:)`: "방금" / "N분 전" / "N시간 M분 전"
  - `estimate(elapsed:typical:samples:) -> String`: "예상 시간 자료 부족" / "보통 4분 (지난 7회) · 약 2분 남음" / "… · 보통보다 길어지는 중"
  - `isQuiet(idle:) -> Bool`: `idle >= quietAfter`
- **`Sources/MyTerminal/Sessions/ProcessMonitor.swift` (`ProcessScanner` actor 확장)**
  - 리뷰 지적대로 표 조회·자손 수집은 `ProcessScanner`에 이미 있으므로 새로 만들지 않습니다.
  - `processTable()`은 `ps` 실행에 실패하거나 종료 코드가 0이 아니면 `nil`을 돌려줍니다. 기존 호출부(`scan`, `terminate`, `descendants`)는 `?? [:]`로 지금 동작을 유지합니다.
  - 새로 `enum StopOutcome { case stopped, unconfirmed(String) }`을 둡니다.
  - 새로 `func stopTree(root: Int32) async -> StopOutcome`을 둡니다. 순서는 다음과 같습니다.
    1. 표를 못 읽으면 `.unconfirmed("프로세스 표를 읽지 못함")`
    2. `root`에 SIGSTOP을 보냅니다. 그다음 표 재조회 → 기존 `descendants(of: [root])` 로직(루트 포함, pid ≤ 1·앱 pid 제외)으로 트리 수집 → 새 pid에 SIGSTOP. 새 pid가 없을 때까지 반복합니다.
       - 대상 pid마다 처음 본 `(parent, args)`를 기억합니다.
       - 재조회 때 같은 pid의 args가 달라져 있으면 pid가 재사용된 것으로 보고 대상에서 빼며 신호를 보내지 않습니다.
       - 20회 안에 멈추지 않으면 `.unconfirmed`
    3. 모든 대상에 SIGKILL을 보냅니다. `kill`이 `ESRCH` 외의 오류를 돌려주면 `.unconfirmed("pid N 신호 실패")`
    4. 100ms 간격으로 최대 5초 동안 `kill(pid,0)`으로 확인합니다. 모두 `ESRCH`면 `.stopped`, 아니면 `.unconfirmed("pid … 가 남아 있음")`
    - SIGKILL 이후에는 어떤 pid에도 신호를 다시 보내지 않습니다. 확인 단계에서 재사용된 pid가 "살아 있음"으로 보이면 미확인이 되는 쪽으로만 틀립니다.
  - 기존 `ProcessMonitor.stop` / `stopAll` → `terminate` 경로는 바꾸지 않습니다. 호출부를 확인한 결과, 사용자가 프로세스 목록에서 직접 끄는 기능이라 이번 경합과 무관합니다.
- **`Sources/MyTerminal/Pipeline/PipelineRunner.swift`**
  - `Live`에 필드를 추가합니다: `lastActivity: Date?`, `lastEvent: (title: String, at: Date)?`, `typical: TimeInterval?`, `samples: Int`
  - `@ObservationIgnored` 캐시를 둡니다: `screens: [String: String]`(key `jobId-step-round`), `typicals: [String: (TimeInterval?, Int)]`
  - `updateLive`: 화면을 비교합니다. 첫 화면은 기준으로만 저장합니다. trace 수정 시각과 `last { $0.kind != "change" }`를 읽어 `lastActivity`를 계산합니다. 활성 단계가 없어지면 캐시를 지웁니다.
  - `stepDurations(step:agent:) -> [TimeInterval]`: 파일 수정 시각 두 개로 최근 10개를 계산합니다.
  - `@ObservationIgnored let scanner = ProcessScanner()`: 전용 인스턴스입니다. actor라서 `ps`가 메인 스레드를 막지 않습니다.
  - **중단 상태를 관측 가능하게 둡니다(`@ObservationIgnored` 아님).**
    - `private(set) var stopping: Set<String>`: 중단 진행 중
    - `private(set) var stopFailed: [String: String]`: 종료 미확인(작업 id → 사유)
  - `advance(_:)` 맨 앞에 가드를 둡니다: `guard !stopping.contains(job.id), stopFailed[job.id] == nil else { return }`. 중단 중이거나 미확인이면 `start`도, `checkAlive`의 실패 판정도 돌지 않습니다.
  - `retry(_:)` 맨 앞에도 같은 가드를 둡니다.
  - `cancel(_:)`
    1. `guard let (step, round) = job.activeStep, !stopping.contains(job.id)`. `stopping.insert`, `stopFailed[job.id] = nil`
    2. `list-panes -t =<session>:=<window> -F #{pane_pid}`로 루트 pid를 얻습니다.
       - **창이 없으면**: 이미 `checkAlive`와 같은 상황이므로 지금처럼 `recordFailure`를 부르고 끝냅니다. 쓰는 쪽(pane)이 이미 없어졌습니다.
       - **창은 있는데 pid를 못 읽으면**: 창을 닫지 않습니다. `stopFailed = "작업 프로세스를 찾지 못했어요 — 다시 중단을 눌러 주세요"`, 기록하지 않음
    3. `await scanner.stopTree(root:)`
       - `.stopped`: `Tmux.killWindow` → `recordFailure(…, "사용자가 중단했어요")`. 이 시점에는 쓰는 쪽이 모두 끝났으므로 기존의 "결과 파일이 있으면 둠" 가드가 경합 없이 성립합니다.
       - `.unconfirmed(reason)`: 창을 닫지 않고, 실패도 기록하지 않습니다. `stopFailed[job.id] = reason`, `lastError = "중단을 확인하지 못했어요: \(reason)"`
    4. `stopping.remove`, `refresh`
  - `migrateLegacyPlan`: pane pid만 기다리던 부분을 같은 `stopTree`로 바꿉니다. `.unconfirmed`면 plan-1 파일을 지우지 않고 meta도 바꾸지 않으며, 새 실행을 시작하지 않습니다(`migrating.remove`, `lastError` 설정). 단계가 여전히 `.failed`이므로 사용자가 다시 시도할 수 있습니다.
  - `tick()`은 테스트를 위해 `private`에서 internal로 바꿉니다.
- **`Sources/MyTerminal/Home/JobCard.swift`**
  - `elapsed(_:)` → `" · " + StepClock.elapsedText(...)`
  - 실행 중인 `AgentRow`의 `LiveActivity` 위에 `StepStatusLine`(같은 파일 안 private)을 둡니다.
    - 1줄: "마지막 기록 · {title} · {ago}". 없으면 "아직 기록 없음"
    - 2줄: "{estimate} · 단계 안 진척은 알 수 없음"
    - `isQuiet`면 1줄을 주황색으로 바꾸고 "N분째 새 기록 없음 — 오래 걸리는 중이거나 멈췄을 수 있어요. 필요하면 중단 후 다시 시도"를 붙입니다.
  - 중단 버튼(261·275행)
    - `stopping`이면 비활성화하고 "중단하는 중…"으로 표시합니다.
    - `stopFailed`가 있으면 사유를 경고색으로 보이고, 버튼 제목을 "다시 중단"으로 바꿉니다.
  - "다시 시도"(278행): `stopping`이거나 `stopFailed`가 있으면 비활성화합니다. `retry`에도 가드가 있으므로 이중 방어입니다.
- **`Sources/MyTermAgent/main.swift`**: 변경하지 않습니다.

## 검증 규칙
- **파일 누락·읽기 실패**(trace·started·result)는 `nil`로 보고 건너뜁니다. 표시에만 영향이 가고("아직 기록 없음", "자료 부족"), 실행 판단에는 쓰지 않습니다.
- **소요 시간이 0 이하인 값**과 `ok != true`인 실행은 표본에서 뺍니다.
- **첫 화면은 활동이 아닙니다.** 단계·회차·다시 시도가 바뀌면 기준 화면과 캐시를 새로 잡습니다.
- **실패 기록은 `.stopped`일 때만** 남깁니다. 표 조회 실패, pid 조회 실패, 신호 전송 오류, 5초 뒤 잔존, 고정점 미도달은 모두 `.unconfirmed`로 처리합니다. 이 경우 기록하지 않고, 창을 닫지 않고, 다시 시도·자동 진행을 막습니다.
  - 예외는 창 자체가 이미 없는 경우 하나입니다. 기존 `checkAlive`와 같은 판정이며 퇴행이 없습니다.
- **중단 중·미확인 상태에서는** `tick`이 여러 번 돌아도 `start`·`checkAlive`·`recordFailure`가 실행되지 않습니다.
- **신호 대상**은 그 창의 pane 루트와 그 트리뿐입니다.
  - pid 0·1·음수와 앱 자신은 제외합니다.
  - 그룹 kill(`kill(-pgid)`)은 쓰지 않습니다.
  - 처음 본 `args`와 다른 pid에는 신호를 보내지 않습니다.
- **경계값**
  - idle: 299초는 경고 없음, 300초는 경고
  - 표본: 1개는 "자료 부족", 2개부터 표시
  - 경과 시간: 3599초는 `59:59`, 3600초는 `1시간 0분`
  - 고정점 반복: 20회를 넘으면 미확인

## 테스트 계획
- **`Tests/MyTerminalTests/StepClockTests.swift`**
  - `typical`: `[]`, `[60]`, `[0,-5,60]` → nil / `[60,240]` → 150 / `[60,120,600]` → 120
  - `elapsedText`: 59초 `0:59`, 3599초 `59:59`, 3600초 `1시간 0분`, 7401초 `2시간 3분`
  - `ago`: 30초 "방금", 125초 "2분 전"
  - `estimate`: 표본 1개는 "자료 부족" / typical 240·경과 130은 "약 2분 남음" / 경과 300은 "보통보다 길어지는 중"
  - `isQuiet`: 299초 false, 300초 true
- **`Tests/MyTerminalTests/ProcessStopTests.swift`** (실제 프로세스 사용)
  - **fork 경합**: `/bin/sh -c 'while :; do /bin/sleep 30 & /bin/sleep 0.01; done'`를 `Process`로 띄우고 0.5초 뒤 `stopTree(root:)`를 부릅니다.
    - 결과가 `.stopped`인지 확인합니다.
    - 시작 전에 기록한 pid와 종료 중에 생긴 `sleep` 자식이 `ps -axo pid,ppid,args`에 남지 않는지 확인합니다. 테스트 시작 뒤 생긴 PPID 1의 `sleep 30`이 없는지도 봅니다.
  - **존재하지 않는 루트**(끝난 프로세스 pid): 신호를 보내지 않고 `.stopped`를 돌려주는지 확인합니다. 트리가 비어 있기 때문입니다.
  - **pid 식별 불일치**: 식별 대조 함수를 순수 함수로 분리합니다(`args`가 바뀐 pid는 대상에서 제외). 가짜 표 두 개(1회차 `{11: "sleep 30"}`, 2회차 `{11: "other"}`)를 넣어 11이 신호 대상에서 빠지는지 확인합니다.
- **`FollowUpPipelineTests` 방식의 러너 테스트**
  - 임시 작업 폴더에 `plan-1.started`만 두고(창 없음) `stopping`에 작업 id를 넣은 뒤 `tick()`을 3회 부릅니다. `plan-1.result.json`이 생기지 않고, `retry`를 불러도 파일 변화가 없는지 확인합니다.
  - `stopFailed`에 사유를 넣은 경우도 같은 결과인지 확인합니다.
  - 가드를 빼면 `checkAlive`가 실패를 기록하므로, 이 테스트가 가드의 회귀 검사가 됩니다.
- **소요 시간 계산 파일 테스트**: `plan-1.started`와 `plan-1.result.json`의 수정 시각을 조작해 계산 결과를 확인합니다. `ok:false`인 결과는 빠져야 합니다.
- **수동 확인**
  1. `swift build && swift test`
  2. 앱을 재빌드하고 요청을 보냅니다. 카드에 "마지막 기록 · Read · … · 방금"과 "예상 시간 자료 부족 · 단계 안 진척은 알 수 없음"이 나오는지 봅니다. 두 번째 작업부터는 "보통 N분 (지난 M회)"이 나오는지 봅니다.
  3. 경고: 설계 중에 `kill -STOP <claude pid>`를 겁니다. 테스트할 때만 `quietAfter`를 30으로 낮춰 주황색 경고가 뜨는지 확인한 뒤 상수를 되돌립니다.
  4. 중단: STOP 상태 그대로 "중단"을 누릅니다. 다음을 확인합니다.
     - "중단하는 중…"이 보이는 동안 "다시 시도"가 비활성화되고 실패 기록이 생기지 않는지
     - 5초 안에 실패로 기록되는지
     - `ps -axo pid,ppid,command | grep -E 'claude -p|codex exec|myterm-agent'`에 이번 작업의 프로세스가 남지 않는지
  5. 앱 재시작: 실행 중에 앱을 다시 켜도 "마지막 기록" 시각이 trace 기준으로 유지되는지 확인합니다.
- **참고**: 이미 남아 있는 고아 claude 프로세스는 별도로 한 번 `kill <pid>`로 정리해야 합니다. 이번 실행은 읽기 전용이라 끄지 않았습니다.

## 리뷰 반영
- [반영] 중단 대기 중 기존 루프가 실패 기록과 재시도를 먼저 허용함
  - 맞는 지적입니다. `tick()`(463행)은 1초마다 `advance → checkAlive`(838행)를 부르고, `checkAlive`는 창이 없으면 곧바로 `recordFailure`를 부릅니다.
  - `stopping`·`stopFailed`를 관측 가능한 상태로 두고 가드를 넣었습니다: `advance`와 `retry`의 맨 앞, 카드의 "다시 시도" 비활성화.
  - 창도 종료가 확인된 뒤에 닫도록 순서를 바꿔, 대기 중에 창 소멸을 이유로 판정할 여지를 없앴습니다.
  - 중단 중 `tick` 3회 테스트를 추가했습니다.
- [반영] 종료 확인 실패를 중단 완료로 처리하는 예외가 남아 있음
  - `StopOutcome.stopped / .unconfirmed`로 구분합니다. 표 조회 실패, pid 조회 실패, 신호 오류, 잔존, 고정점 미도달은 모두 미확인으로 처리해 기록하지 않고, 다시 시도와 자동 진행을 막고, "다시 중단"을 안내합니다.
  - 이를 위해 `processTable()`이 조회 실패를 빈 표가 아닌 `nil`로 구분하게 했습니다.
  - `migrateLegacyPlan`도 미확인이면 plan-1을 지우거나 옮기지 않습니다.
  - 한 가지는 남깁니다. "창 자체가 이미 없으면 기록"하는 경우입니다. 기존 `checkAlive`가 지금도 하는 판정이고, 쓰는 쪽 pane이 이미 사라져 앱이 더 확인할 방법이 없습니다.
  - "자손 목록에 루트가 없다"는 부분은 사실과 다릅니다. 재사용하는 `ProcessScanner.descendants(of:)`(212행)는 `visit(root)`에서 루트를 먼저 `ordered`에 넣습니다. 확인 대상이 루트를 포함한다는 점은 명시했습니다.
- [반영] 한 번 수집한 PID 목록으로 자손 전체의 종료를 보장할 수 없음
  - 스냅샷 방식을 "SIGSTOP으로 트리 얼리기 → 새 pid가 없을 때까지 재수집 → SIGKILL"로 바꿨습니다. 얼어 있는 프로세스는 fork하지 못하므로 수집한 뒤 새 자식이 생기는 틈이 닫힙니다.
  - 얼어 있는 대상은 스스로 끝나지 않으므로, 수집과 SIGKILL 사이에 pid가 재사용될 여지도 사라집니다.
  - 식별 검증은 리뷰가 예로 든 시작 시각 대신, 처음 본 `args`와 재조회 때의 `args`를 대조하는 방식으로 합니다. 시작 시각(`lstart`)은 공백이 든 필드라 지금 `ps` 파서(`maxSplits: 4`)를 바꿔야 합니다. 트리를 얼린 뒤에는 재사용될 수 있는 틈이 수집부터 SIGSTOP까지의 ms 단위뿐이라 `args` 대조로 충분하다고 봅니다.
  - SIGKILL 이후에는 신호를 다시 보내지 않으므로, 확인 단계에서 재사용된 pid는 미확인 쪽으로만 틀립니다.
  - 종료 중 fork하는 가짜 CLI 테스트와 식별 불일치 테스트를 추가했습니다.
- [반영] 재사용할 프로세스 기능의 실제 소유 타입이 설계와 다름
  - 맞는 지적입니다. `processTable`, `Entry`, `descendants`, `terminate`는 `ProcessScanner` actor(75행~)에 있습니다.
  - 새 코드는 `ProcessScanner.stopTree`로 넣고, 기존 `descendants` 로직을 재사용합니다. 1차 설계의 중복 구현안은 뺐습니다.
  - `PipelineRunner`는 자체 `ProcessScanner` 인스턴스로 호출하므로 `ps`가 메인 actor를 막지 않습니다.
  - 기존 `ProcessMonitor.stop/stopAll → terminate` 호출부는 확인했습니다. 사용자가 프로세스 목록에서 직접 끄는 경로이고 결과 파일 기록과 얽히지 않으므로 이번에는 바꾸지 않습니다.