# MyTerminal 이슈: 단계 진행 표시·멈춤 경고·중단 시 프로세스 트리 정리 (6차, 5차 리뷰 반영)

## 요약
이 문서는 `/Users/ted/project/myterminal`에 이슈로 바로 올릴 수 있게 정리했습니다. 5차 설계(`plan-5.md`)를 바탕으로 5차 리뷰(`planreview-5.md`)의 MEDIUM 지적 두 건을 반영했습니다. 두 건 모두 코드에서 확인했습니다.
- `Job.swift:802`: `activeStep`은 phase에서만 계산합니다. 그래서 단계 결과가 생기면 원래 단계가 대상에서 사라집니다.
- `PipelineRunner.swift:889`: `recordFailure`는 `fileExists`만 봅니다. 그래서 결과 경로에 디렉터리가 있어도 성공으로 처리합니다.

**문제**
- 카드에는 "설계 중 · 123:30"처럼 경과 시간만 보입니다. 사용자는 지금 무엇을 하는지, 기록이 언제 끊겼는지, 얼마나 남았는지 알 수 없습니다.
- "중단"(`PipelineRunner.swift:346`)과 "카드 삭제"(287행)는 `Tmux.killWindow`만 호출합니다. 이 호출은 pane 루트에 SIGHUP만 보내므로 claude·codex와 그 하위 도구가 살아남습니다.

**이번 변경**
- 카드에 마지막 기록, 예상 시간, 무기록 경고를 표시합니다.
- 중단 절차를 바꿉니다. 대상을 식별해 디스크에 먼저 기록한 뒤 트리를 얼리고(SIGSTOP) 강제 종료(SIGKILL)합니다.
- 종료가 확인되고 결과가 실제로 읽힐 때만 차단을 해제합니다. 확인 전에는 진행, 다시 시도, 삭제를 모두 막습니다.
- walwal-harness 쪽은 바꾸지 않습니다.

---

**이슈 제목(안):** `[파이프라인] 단계 진행 상황이 안 보이고, 중단·삭제해도 CLI 프로세스가 남음`

**재현**
1. 설계가 오래 걸리는 요청을 보냅니다. 카드에는 "설계 중 · 123:30"만 보입니다.
2. "중단"을 누르거나 카드를 삭제합니다.
3. `ps -axo pid,ppid,command | grep -E 'claude -p|codex exec'`를 실행하면 이 작업의 CLI가 아직 남아 있습니다.

**원인**
- `JobCard.TraceChips`는 `isBackground` 이벤트(claude·codex·hook)를 걸러 냅니다. 그래서 설계·리뷰 단계의 활동이 카드에 보이지 않습니다.
- `PipelineRunner.updateLive`(478행)는 화면 마지막 6줄과 경과 시간만 계산합니다.
- `cancel`과 `delete`는 창만 닫습니다. `runStreaming`이 띄운 CLI와 그 자손은 SIGHUP으로 끝나지 않습니다.

## 요구 분석
- **무엇을 하는지:** trace에서 마지막 이벤트(`kind != "change"`, hook 포함)를 골라 "마지막 기록 · Bash · ls … · 12분 전"처럼 보여 줍니다.
- **어디까지 진행했는지**
  - 단계 단위 진행은 기존 `PlacementRow`의 `▶` 표시를 씁니다.
  - 단계 안의 진척률은 CLI가 알려 주지 않으므로 "단계 안 진척은 알 수 없음"으로 표기합니다.
- **얼마나 남았는지:** 같은 워크스페이스에서 같은 단계·같은 CLI로 성공한 최근 10회의 중앙값을 씁니다.
  - 예: "보통 4분 (지난 7회) · 약 2분 남음" / "보통보다 길어지는 중"
  - 표본이 2개 미만이면 "예상 시간 자료 부족"으로 표기합니다.
- **멈춤 경고:** 새 기록이 5분 이상 없으면 주황색 경고를 띄웁니다. 자동으로 중단하지는 않습니다.
- **중단 시 트리 전체 종료**
  - 종료가 확인되고 결과가 실제로 읽힐 때만 차단을 해제합니다.
  - 확인되지 않은 동안에는 자동 진행, 창 소멸을 이유로 한 실패 판정, 다시 시도, 카드 삭제를 모두 막습니다.
- **(4차 반영, 유지)**
  - 새로 발견한 대상도 신호 전에 기록합니다.
  - 실행 중이거나 중단이 끝나지 않은 카드는 삭제를 막습니다.
  - 루트를 못 얻은 경우 재중단할 때 다시 식별합니다.
- **(5차 MEDIUM-1)**
  - 첫 stop 기록 저장에 실패하면 메모리에 사유와 함께 중단 대상 전체(`step`, `round`, `root`, `targets`)를 보존합니다.
  - "다시 중단"은 디스크 기록 → 메모리 기록 → 현재 단계 순서로 대상을 정합니다. 그래서 그 사이 결과가 생겨 phase가 바뀌어도 원래 단계를 끝까지 정리합니다.
- **(5차 MEDIUM-2)** `recordFailure`는 "경로가 있음"이 아니라 "`StepResult`로 읽힘"을 성공 조건으로 봅니다. 디렉터리이거나 해석할 수 없는 파일이면 `false`를 돌려주고 차단을 유지합니다.

## 모호점과 해소안
- **자동 중단 여부** → 하지 않습니다. 기록이 없다는 것은 멈췄을 가능성일 뿐, 확정 근거가 아닙니다.
- **"활동" 시각** → `max(trace 수정 시각, 화면이 바뀐 시각, 단계 시작 시각)`으로 봅니다. 단계별로 처음 읽은 화면은 비교 기준으로만 쓰고 활동으로 치지 않습니다.
- **경고 기준** → `StepClock.quietAfter = 300` 상수로 둡니다. 나중에 조정할 수 있는 손잡이입니다.
- **예상 시간 표본** → `.started` 수정 시각부터 `.result.json` 수정 시각까지를 씁니다.
  - `ok == true`이고 0보다 큰 값만 씁니다.
  - 단계가 바뀔 때 한 번 계산해 캐시합니다.
- **프로세스 식별** → `proc_pidinfo(PROC_PIDTBSDINFO)`의 `pbi_start_tvsec`/`pbi_start_tvusec`와 `pbi_ppid`로 `(pid, 시작 시각)`을 만듭니다.
  - `exec`는 같은 실행으로 봅니다.
  - pid가 재사용되면 시작 시각이 다르므로 다른 실행으로 봅니다.
- **대상 편입 규칙(`adopt`)**: `freezeTree`와 `killAndConfirm`이 같은 함수를 씁니다.
  1. 후보가 다음 중 하나여야 합니다.
     - ppid가 이미 얼린 대상이고, 후보의 시작 시각이 부모보다 이르지 않음
     - `getsid == 루트 pid`이고, 시작 시각이 루트 이후임
  2. `record(기존 ∪ 새 대상)`로 저장합니다.
  3. 저장에 성공할 때만 SIGSTOP을 보냅니다. 실패하면 신호 없이 `.unconfirmed`로 끝냅니다.

  반복은 최대 20회입니다. 스스로 `setsid`한 프로세스는 잡지 못하는 한계가 있습니다.
- **종료 방식** → 트리를 SIGSTOP으로 얼린 뒤 SIGKILL을 보냅니다. 보내기 직전에 식별 정보를 다시 대조합니다.
- **종료 확인** → 100ms 간격으로 최대 5초 동안 확인합니다.
  - "종료됨": `ESRCH`이거나 시작 시각이 달라짐
  - "미확인": `EPERM`이나 그 밖의 오류

  `.stopped`가 되려면 targets가 모두 종료됐고, 루트가 식별된 경우 `getsid` 재탐색에서도 잔존 프로세스가 없어야 합니다. targets가 비어 있고 루트도 없으면 미확인입니다.
- **중단 기록 파일** → `<step>-<round>.stop.json`
  - 담는 값: `{step, round, root: ProcID?, targets: [ProcID], state: "freezing"|"killing"|"unconfirmed"|"confirmed", reason?}`
- **첫 기록 저장 실패(5차 MEDIUM-1)** → 신호를 보낸 적이 없으므로 트리는 손대지 않은 상태입니다.
  - `stopBlocked[jobId] = StopRecord(state: .unconfirmed, reason: 저장 실패 사유, step, round, root, targets: [])`를 메모리에 둡니다. 확보한 `root`도 함께 담습니다.
  - 그 사이에도 `refresh`는 돌아서 agent 결과가 반영될 수 있습니다. 하지만 `advance`는 `isStopHeld`로 막혀 있습니다. 그래서 다음 단계의 `.started`가 생기지 않고, 새 CLI도 뜨지 않습니다.
  - "다시 중단"은 이 메모리 기록의 `(step, round, root)`로 정상 절차를 다시 탑니다. 이번에 디스크 저장에 성공하면 이후는 일반 경로와 같습니다.
  - 앱을 재시작하면 메모리 차단은 사라집니다. 신호를 보낸 적이 없으므로 원래 실행 상태로 돌아가는 것은 안전합니다.
- **중단이 걸리기 전에 agent가 결과를 남긴 경우** → 기존 정책(889행 "창이 닫히기 직전에 agent 가 결과를 남겼을 수 있다")대로 그 결과를 보존하고 덮어쓰지 않습니다.
  - 트리 정리가 끝나면 차단을 해제하고 `lastError`에 "중단이 적용되기 전에 단계가 끝나 결과를 보존했어요"를 표시합니다.
  - 결과가 `ok:true`이면 차단 해제 후 다음 단계가 이어집니다. 그 단계는 다시 "중단"할 수 있습니다.
  - 완료된 작업물을 버리지 않는 것이 우선이라는 판단입니다. 별도의 일시정지 상태는 이번 범위에 넣지 않습니다.
- **마무리** → 순서는 `confirmed` 저장 → `recordFailure`(Bool) → `true`일 때만 `killWindow`, stop 파일 삭제, `stopBlocked` 해제입니다.
- **`recordFailure`의 성공 조건(5차 MEDIUM-2)**
  - `JobJSON.decode(StepResult.self, from:) != nil` → 기존 결과를 보존하고 `true`를 돌려줍니다.
  - 경로가 없으면 저장을 시도합니다. 성공하면 `true`, 실패하면 `lastError`를 설정하고 `false`를 돌려줍니다.
  - 경로는 있는데 읽히지 않으면(디렉터리, 깨진 JSON) 덮어쓰지 않습니다. `lastError`에 "결과 파일을 읽을 수 없어요"를 넣고 `false`를 돌려줍니다.
  - 기존 호출부 `checkAlive`에서는 이 경우 이전과 달리 조용히 넘어가지 않고 `lastError`가 보입니다. 의도한 개선입니다.
- **재중단 시 루트 미확보** → 기록의 `(step, round)` 창에서 `panePid`를 다시 읽습니다.
  - 성공하면 `root`를 저장하고 정상 절차로 진행합니다.
  - 창이 없고 targets도 비어 있으면 마무리로 갑니다(`checkAlive`와 같은 판정).
  - 창은 있는데 읽지 못하면 미확인을 유지합니다.
- **카드 삭제** → `isStopHeld`이거나 `activeStep != nil`이면 거부합니다. `delete`의 `killWindow`도 같은 SIGHUP 경로라서 고아 프로세스를 만들기 때문입니다.
- **앱 재시작** → `freezing`/`killing` 기록은 `unconfirmed`로 다시 씁니다(사유: "앱이 중단 도중 종료됨"). `confirmed` 기록은 마무리를 이어서 합니다.

## 변경 파일
- **`Sources/MyTerminal/Pipeline/StepClock.swift` (새 파일, 순수 함수)**
  - `quietAfter = 300`
  - `typical(_:)`: 0 이하 값을 빼고, 2개 이상일 때만 중앙값
  - `elapsedText(_:)`: 60분 미만은 `m:ss`, 이상은 `N시간 M분`
  - `ago(_:)`, `estimate(elapsed:typical:samples:)`, `isQuiet(idle:)`
- **`Sources/MyTerminal/Sessions/ProcessMonitor.swift` (`ProcessScanner` 확장)**
  - `processTable()`: 실패하면 `nil`을 돌려줍니다. 기존 호출부는 `?? [:]`를 붙입니다.
  - `struct ProcID: Codable, Hashable { pid: Int32; startSec: Int64; startUsec: Int32 }`
  - `static func identity(_ pid:) -> Result<(ProcID, ppid: Int32), ProbeError>`: 오류는 `.gone`과 `.unknown(errno)`로 나눕니다.
  - `private func adopt(...)`: 편입 → `record` → SIGSTOP
  - `func freezeTree(root:record:) async -> Result<Set<ProcID>, StopError>`
  - `func killAndConfirm(_ targets:root:record:) async -> StopOutcome`
    - 재탐색에서 찾은 대상은 `adopt`로 편입합니다.
    - `enum StopOutcome { case stopped(Set<ProcID>), unconfirmed(String, Set<ProcID>) }`
    - targets가 비어 있고 `root == nil`이면 `.unconfirmed("대상 없음")`입니다.
  - `static func isGone(_:probe:) -> Bool?`
  - 기존 `terminate`와 `ProcessMonitor.stop/stopAll`은 바꾸지 않습니다.
- **`Sources/MyTerminal/Pipeline/Job.swift`**
  - `JobFiles.stop(_:_:)`과 `StopRecord: Codable`(`root: ProcID?`)을 추가합니다.
  - `JobSnapshot.pendingStop`을 추가합니다. 작업 폴더의 `*.stop.json`에서 읽습니다.
  - `retryFailedStep`이 파일을 옮길 때 `.stop.json`은 대상에서 뺍니다.
- **`Sources/MyTerminal/Pipeline/PipelineRunner.swift`**
  - `Live` 필드를 추가합니다: `lastActivity`, `lastEvent`, `typical`, `samples`. `@ObservationIgnored` 캐시(`screens`, `typicals`)와 `stepDurations(step:agent:)`도 추가합니다.
  - `@ObservationIgnored let scanner = ProcessScanner()`
  - 381행의 pane pid 조회를 `@ObservationIgnored var panePid: (String, String) -> Int32?`(기본값은 Tmux 조회) 하나로 뽑아 냅니다. `cancel`과 `migrateLegacyPlan`이 함께 씁니다.
  - 관측 상태
    - `private(set) var stopping: Set<String>`
    - `private(set) var stopBlocked: [String: StopRecord]`(**5차 MEDIUM-1:** 사유만이 아니라 대상 전체를 담음, 메모리 전용)
    - `func isStopHeld(_ job) -> Bool` = `stopping ∪ stopBlocked ∪ pendingStop`
  - **가드:** `advance`, `retry`, `delete` 맨 앞에서 `isStopHeld`이면 반환합니다. `delete`는 `activeStep != nil`일 때도 반환하고 `lastError`에 안내를 넣습니다.
  - **`recordFailure`를 `@discardableResult -> Bool`로 바꿉니다(5차 MEDIUM-2):**
    - 889행의 `fileExists` 가드를 `JobJSON.decode(StepResult.self, from: url) != nil`(읽힘 → `true`)로 바꿉니다.
    - 경로는 있는데 읽히지 않으면 `lastError`를 설정하고 `false`를 돌려줍니다(덮어쓰지 않음).
    - 경로가 없으면 `save`하고, 성공 여부를 그대로 돌려줍니다.
  - **`cancel(_ job:)`**
    1. 대상을 정합니다. 순서는 `pendingStop`(디스크) → `stopBlocked[id]`(메모리) → `activeStep`입니다. 셋 다 없으면 반환하고, `stopping`으로 중복 실행을 막습니다(5차 MEDIUM-1).
    2. `root`가 없으면 `panePid`와 `identity`로 식별합니다.
       - 창이 없고 targets가 비어 있으면 5번으로 갑니다.
       - 창은 있는데 식별하지 못하면 `root: nil, state: .unconfirmed`를 저장하고 7번으로 갑니다.
    3. `.freezing`을 저장합니다.
       - 실패하면 신호 없이 `stopBlocked[id] = StopRecord(step, round, root, targets: [], .unconfirmed, reason)`를 두고 `lastError`를 설정한 뒤 7번으로 갑니다.
       - 성공하면 루트가 살아 있을 때 `freezeTree`를 호출합니다.
    4. `.killing`을 저장한 뒤 `killAndConfirm(targets, root, record:)`을 호출합니다.
    5. `.stopped`이면 `confirmed`를 저장하고 `recordFailure`를 호출합니다.
       - `true`이면 `killWindow`, stop 파일 삭제, `stopBlocked[id] = nil`을 합니다. 결과가 agent가 남긴 것이면 "중단이 적용되기 전에 단계가 끝나 결과를 보존했어요"를 표시합니다.
       - `false`이면 `confirmed`를 유지하고 `lastError`를 설정합니다.
    6. `.unconfirmed(r, t)`이면 `state: .unconfirmed, reason: r, targets: t`를 저장합니다.
    7. `stopping.remove` 후 `refresh`합니다.
  - **`init`/`reload`:** `freezing`/`killing`은 `unconfirmed`로 다시 쓰고, `confirmed`는 5번 마무리를 합니다.
  - **`migrateLegacyPlan`:** 같은 중단 절차를 쓰고, `.stopped`일 때만 plan-1을 옮깁니다.
  - `tick()`을 테스트를 위해 internal로 바꿉니다.
- **`Sources/MyTerminal/Home/JobCard.swift`**
  - `elapsed` 표시에 `StepClock.elapsedText`를 씁니다.
  - 실행 중인 `AgentRow` 위에 private `StepStatusLine`을 둡니다: 마지막 기록, 예상 시간과 "단계 안 진척은 알 수 없음", 무기록이면 주황색 경고.
  - 중단 버튼(261·275행)
    - `stopping` 중이면 비활성화하고 "중단하는 중…"으로 표시합니다.
    - `pendingStop`이나 `stopBlocked`가 있으면 **phase와 관계없이** 사유를 보이고 "다시 중단" 버튼을 둡니다.
  - "다시 시도"(278행), 삭제(102행, 241행): `isStopHeld`이면 비활성화합니다. 삭제는 `activeStep != nil`일 때도 비활성화하고 안내 도움말을 표시합니다.
- **`Sources/MyTermAgent/main.swift`:** 변경하지 않습니다.

## 검증 규칙
- trace·started·result 파일을 읽지 못하면 `nil`로 봅니다. 이 값은 표시에만 쓰고 실행 판단에는 쓰지 않습니다.
- **차단 해제는 `.stopped`이고 `recordFailure == true`일 때만** 합니다. 다음 경우는 모두 차단을 유지합니다.
  - 표 조회, pid 조회, 식별(`EPERM` 등), 신호 중 하나라도 실패(`ESRCH` 제외)
  - 5초 뒤에도 대상이 남음
  - 20회 안에 수집이 끝나지 않음
  - stop 기록 저장 실패
  - targets가 비어 있고 루트도 없음
  - 결과 경로가 디렉터리이거나 읽히지 않음
- **기록 없이는 신호를 보내지 않습니다.** 대상은 `adopt` 한 경로로만 편입되고, 저장에 성공해야 신호를 보냅니다.
- **창·루트가 사라진 것은 완료 근거가 아닙니다.** 예외는 "targets가 비어 있고 창도 없음" 하나뿐입니다.
- **차단 중 phase 변화:** 결과가 반영돼 `activeStep`이 바뀌거나 사라져도 재중단 대상은 기록된 `(step, round)`입니다. 다음 단계는 `advance` 가드 때문에 시작되지 않습니다.
- **기존 결과는 덮어쓰지 않습니다.** 읽히는 결과는 보존하고, 읽히지 않는 경로는 건드리지 않고 차단을 유지합니다.
- **신호 대상:** pid 0, pid 1, 음수 pid, 앱 자신은 제외합니다. 그룹 kill은 쓰지 않습니다.
- **`isStopHeld` 동안**에는 `tick`을 여러 번 돌려도 `start`, `checkAlive`, `recordFailure`, `retry`, `delete`가 일어나지 않습니다.
- **경계값**
  - 무기록 시간: 299초는 경고 없음, 300초는 경고
  - 예상 시간 표본: 1개는 "자료 부족", 2개부터 표시
  - 경과 시간: 3599초는 `59:59`, 3600초는 `1시간 0분`
  - 수집 반복: 20회를 넘으면 미확인

## 테스트 계획
- **`Tests/MyTerminalTests/StepClockTests.swift`**
  - `typical`: `[]`, `[60]`, `[0,-5,60]`은 nil / `[60,240]`은 150 / `[60,120,600]`은 120
  - `elapsedText`: 59초, 3599초, 3600초, 7401초
  - `ago`: 30초, 125초
  - `estimate`: 표본 1개, 남은 시간, 초과
  - `isQuiet`: 299초, 300초
- **`Tests/MyTerminalTests/ProcessStopTests.swift`(실제 프로세스)**
  - fork 경합: `sh -c 'while :; do sleep 30 & sleep 0.01; done'` → `.stopped`여야 하고 남은 `sleep 30`이 없어야 합니다.
  - 부분 종료 후 재중단: 자식이 살아 있으면 `.unconfirmed`, 모두 끝나면 `.stopped`여야 합니다.
  - 재탐색 편입 시 기록이 먼저인지: `record` 콜백 시점에 새 pid의 `ps -o stat=`가 `T`가 아니어야 하고, 마지막 기록에 그 pid가 들어 있어야 합니다.
  - 재탐색 편입 시 저장 실패: `.unconfirmed`여야 하고 그 pid는 정지되지 않은 상태여야 합니다.
  - 빈 대상: `killAndConfirm([], root: nil, …)`은 `.unconfirmed`여야 합니다.
  - `isGone`: 같은 시작 시각은 false / 다른 시작 시각은 true / `EPERM`은 nil. `exec sleep 30` 사례도 종료되어야 합니다.
- **러너 테스트(`FollowUpPipelineTests` 방식, `panePid` 주입)**
  - **차단 회귀:** `plan-1.started`와 `unconfirmed` stop 파일을 둡니다. `tick()` 3회와 `retry`를 호출해도 결과 파일이 생기지 않아야 합니다.
  - **삭제 차단:** 중단 미확인 상태와 `activeStep`만 있는 상태에서는 폴더가 남아야 합니다. 끝난 카드는 삭제되어야 합니다.
  - **첫 기록 저장 실패 → phase 변화 → 재중단(5차 MEDIUM-1, 신규)**
    1. `plan-1.started`와 `sleep 30` pid(`panePid` 주입)를 둡니다. 작업 폴더를 읽기 전용으로 만들고 `cancel`합니다. `stopBlocked`에 `(plan, 1, root)`가 담기고, 해당 pid는 정지되지 않아야 합니다.
    2. 폴더 권한을 되돌리고 agent가 끝낸 것처럼 `plan-1.result.json`(`ok:true`)을 씁니다. `tick()` 2회 뒤 phase는 `planReviewing`이어야 하고, `planReview-1.started`는 **생기지 않아야** 합니다.
    3. `cancel`을 다시 호출합니다. `plan-1`이 대상이 되어 `sleep 30`이 사라지고, `plan-1.result.json`은 원래 `ok:true` 내용 그대로여야 합니다. `stopBlocked`는 해제되고 stop 파일은 없어야 합니다.
    4. 이후 `tick()`에서 `planReview-1.started`가 생겨 정상 진행되어야 합니다.
  - **마무리 저장 실패(5차 MEDIUM-2, 수정)**
    - `confirmed` stop 파일을 두고 `plan-1.result.json` 경로에 **디렉터리**를 만듭니다. `reload` 후 `recordFailure == false`, `lastError` 설정, `confirmed` 파일 유지, `tick`/`retry`/`delete` 차단이 확인되어야 합니다.
    - 같은 테스트를 깨진 JSON 파일(`{`)로도 돌립니다. 파일 내용은 그대로 남아야 합니다.
    - 디렉터리를 치우고 다시 `reload`하면 `ok:false` 결과가 기록되고 stop 파일이 삭제되어야 합니다.
  - **`recordFailure` 단위:** 읽히는 기존 결과는 `true`이고 내용이 바뀌지 않아야 합니다. 경로가 없으면 저장 후 `true`입니다. 디렉터리와 깨진 JSON은 `false`입니다.
  - **재시작 복원:** `freezing` 파일은 `unconfirmed`로 다시 쓰여야 하고, `confirmed` 파일은 마무리되어야 합니다.
  - **루트 미확보 재시도:** 첫 `panePid`가 nil이면 `root: nil, unconfirmed`여야 합니다. 두 번째에 pid를 주면 `.stopped`, 결과 기록, stop 파일 삭제가 모두 일어나야 합니다.
  - **`activeStep`이 없을 때:** `ok:false` 결과와 `unconfirmed` stop 파일이 있는 상태에서 `cancel`하면 `.stopped`가 나오고 stop 파일이 삭제되어야 합니다.
  - **소요 시간:** 수정 시각을 조작해 계산 결과를 확인합니다. `ok:false`는 제외되어야 합니다.
- **수동 확인**
  1. `swift build && swift test`
  2. 카드에 "마지막 기록 · … · 방금"과 "예상 시간 자료 부족 · 단계 안 진척은 알 수 없음"이 보여야 합니다. 두 번째 작업부터는 "보통 N분 (지난 M회)"이 보여야 합니다.
  3. `quietAfter`를 30으로 바꾸고 `kill -STOP <claude pid>`를 보내 경고를 확인한 뒤, 상수를 원래대로 돌립니다.
  4. 실행 중에는 삭제가 비활성화되어야 합니다. "중단"을 누르면 5초 안에 실패가 기록되고, `ps`에 이 작업의 `claude -p|codex exec|myterm-agent`가 없어야 합니다.
  5. `freezing` 상태에서 앱을 강제 종료하고 다시 켭니다. "다시 중단" 안내가 뜨고 삭제·다시 시도가 비활성화되어야 합니다. 누르면 정리가 끝나야 합니다.
- **참고**
  - 이미 남아 있는 고아 claude 프로세스는 한 번 수동으로 `kill <pid>`해야 합니다.
  - 알려진 한계
    - 스스로 `setsid`한 프로세스는 잡지 못합니다.
    - 강제 종료로 남은 lock 파일(git 등)은 정리하지 않습니다.
    - 중단이 걸리기 전에 끝난 단계의 결과는 보존되어 다음 단계가 이어집니다.

## 리뷰 반영
- **[반영] 최초 저장 실패 후 단계가 끝나면 "다시 중단"이 동작하지 않음(MEDIUM)**
  - 코드 확인: `activeStep`(`Job.swift:802`)은 phase에서만 계산됩니다. 결과가 생기면 원래 단계가 사라지고, 5차의 `stopBlocked: [String: String]`에는 대상이 없었습니다.
  - `stopBlocked`를 `[String: StopRecord]`로 바꿔 `step`, `round`, `root`를 보존했습니다.
  - `cancel` 1번의 대상 결정 순서를 "디스크 → 메모리 → 현재 단계"로 고정했습니다.
  - 중단 표시가 phase와 관계없이 보이도록 했습니다.
  - 차단 중에는 `advance` 가드 때문에 다음 단계가 시작되지 않는다는 점을 명시했습니다.
  - agent가 먼저 끝낸 결과는 기존 889행 정책대로 보존하도록 정했습니다.
  - "저장 실패 → `ok:true` 결과 반영(phase 변화) → 재중단으로 원래 단계 정리·차단 해제" 테스트를 추가했습니다.
- **[반영] 결과 경로의 존재만 확인하면 저장 실패 테스트와 충돌함(MEDIUM)**
  - 코드 확인: `recordFailure`(`PipelineRunner.swift:889`)는 `fileExists(atPath:)`로 디렉터리도 "결과 있음"으로 봅니다.
  - 성공 조건을 `JobJSON.decode(StepResult.self, from:) != nil`(기존 헬퍼, `Job.swift:460`)로 바꿨습니다.
  - 경로는 있는데 읽히지 않으면 덮어쓰지 않고 `false`와 `lastError`를 돌려주도록 했습니다.
  - 디렉터리 충돌 테스트는 그대로 두었습니다. 여기에 깨진 JSON 사례와 `recordFailure` 단위 테스트를 추가했습니다.
  - 기존 호출부 `checkAlive`에도 이 변화가 미칩니다. 읽히지 않는 결과가 조용히 넘어가지 않고 오류로 보이는데, 의도한 개선으로 적어 두었습니다.