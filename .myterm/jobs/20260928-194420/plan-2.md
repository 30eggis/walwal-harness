# MyTerminal 진행 단계 표시 + 멈춤 경고 + 중단 시 남는 프로세스 정리 (2차)

## 요약
스크린샷의 "설계 중 · 123:21"은 설계가 계속 진행된 시간이 아닙니다. 대부분은 기록이 멈춘 뒤에도 경과 시간이 계속 올라간 것입니다. 지금 카드는 tmux 마지막 6줄과 경과 시간만 보여 줍니다. 그래서 무엇을 하고 있는지, 기록이 언제 끊겼는지, 얼마나 남았는지 알 수 없습니다. 이번 변경으로 카드에 네 가지를 보여 줍니다: ① 마지막으로 기록된 일과 그 시각, ② 이번 단계가 보통 걸리는 시간(지난 실행 기준), ③ 새 기록이 오래 없으면 경고, ④ 앱은 단계 내부 진척을 알 수 없다는 사실. 자동 중단은 하지 않습니다. 대신 "중단"을 누르면 claude·codex와 그 하위 프로세스까지 실제로 종료한 것을 확인하고, 그다음에 실패를 기록합니다.

## 요구 분석
- **뭘 하고 있는지 알 수 없음**
  - trace에는 도구 호출이 기록됩니다(`Trace.toolUse`의 `add("claude","tool", "Bash · ls …")`).
  - 그런데 카드의 `TraceChips`는 `isBackground`(claude·codex·hook)를 걸러 냅니다. 그래서 설계·리뷰 단계의 평범한 Read·Bash 호출은 카드에 보이지 않습니다.
  - → 걸러 내지 않은 마지막 기록을 "마지막 기록 · Bash · ls ~/Downloads · 12분 전" 형태로 보여 줍니다.
- **어디까지 진행 중인지**: 단계 수준(설계→설계리뷰→작업→리뷰)은 기존 `PlacementRow`의 `▶`가 이미 보여 줍니다. 단계 안에서 몇 %까지 왔는지는 CLI가 알려 주지 않으므로 지어내지 않습니다. 대신 "도구 N회 사용"처럼 관측한 사실과 "단계 안 진척은 알 수 없음"을 그대로 표시합니다.
- **얼마나 남았는지**
  - 같은 워크스페이스에서 같은 단계·같은 CLI로 성공한 최근 실행의 소요 시간 중앙값을 씁니다.
  - "보통 4분 (지난 7회 기준) · 약 2분 남음" 또는 "보통보다 길어지는 중"으로 표시합니다.
  - 표본이 모자라면 "예상 시간 자료 부족"이라고 씁니다.
- **123분씩 모르고 기다림**: 새 기록이 5분 넘게 없으면 주황 경고 "N분째 새 기록 없음 — 오래 걸리는 중이거나 멈췄을 수 있어요"를 띄웁니다. 끊을지는 사용자가 기존 "중단" 버튼으로 결정합니다.
- **(발견) 중단해도 claude가 남음**
  - `Tmux.killWindow`는 tmux 창(pane) 프로세스인 `myterm-agent`에만 SIGHUP을 보냅니다.
  - `runStreaming`이 `Process`로 띄운 CLI와 그 하위 도구는 살아남습니다(PPID 1인 claude가 몇 시간째 남아 있던 사례).
  - → 중단할 때 창의 자손 프로세스 전체를 종료하고 종료를 확인합니다.

## 모호점과 해소안
- **자동 중단 여부** → 하지 않습니다.
  - trace는 도구 호출·결과·훅만 기록합니다. 긴 추론, 긴 도구 실행, Codex·MCP 대기 중에는 trace와 화면 모두 조용할 수 있습니다.
  - 기록이 없다는 건 멈춤을 의심할 근거일 뿐, 멈췄다는 확정은 아닙니다(리뷰 지적 수용).
  - 사용자가 요청한 것은 가시성이므로 경고와 수동 중단으로 충분합니다.
  - 자동 중단은 도구별 명시적 제한 시간이 생길 때 다시 검토합니다.
- **"활동"의 기준** → `max(trace 파일 수정 시각, 화면 내용이 바뀐 시각, 단계 시작 시각)`.
  - 단계(작업 id·단계·회차)마다 처음 읽은 화면은 비교 기준으로만 저장하고 활동으로 치지 않습니다. 그래서 앱을 재시작해도 오래된 화면이 "방금 활동"으로 보이지 않습니다.
  - 재시작 뒤에는 trace 수정 시각이 기준이 됩니다.
- **"마지막 기록"으로 보여 줄 이벤트**
  - `TraceEvent.load`의 마지막 이벤트 중 `kind == "change"`(디스크 변경 알림)는 뺍니다. 사용자에게 의미가 없습니다.
  - hook은 포함합니다. "PostToolUse:Bash hook"도 무언가 끝났다는 사실이기 때문입니다.
  - 도구를 불렀는데 결과 기록이 없는 경우도, 일반 도구는 결과를 남기지 않으므로 "대기 중"이라고 단정하지 않습니다.
- **경고 기준 5분** → `StepClock.quietAfter = 300` 상수 하나로 둡니다(조정 손잡이). 경고만 띄우므로 잘못 맞아도 비용이 작습니다.
- **예상 시간 표본**
  - 대상: `jobs`에 로드된 작업 중 같은 `step`, 같은 CLI(`job.agent(step, round)`), 결과 `ok == true`인 실행 가운데 최근 10개.
  - 소요 시간: `<step>-<n>.started` 수정 시각부터 `<step>-<n>.result.json` 수정 시각까지.
  - 2개 미만이면 "자료 부족"으로 표시합니다.
  - 단계가 바뀔 때 한 번만 계산해 캐시합니다.
- **긴 경과 시간 표기** → 60분 이상은 "2시간 3분"으로 씁니다.
- **변경 대상 저장소** → `/Users/ted/project/myterminal`만 바꿉니다. walwal-harness는 건드리지 않습니다.

## 변경 파일
- **`Sources/MyTerminal/Pipeline/StepClock.swift` (새 파일)** — 순수 함수만 둡니다.
  - `static let quietAfter: TimeInterval = 300`
  - `typical(_ durations: [TimeInterval]) -> TimeInterval?` — 0 이하 값을 빼고, 2개 이상일 때만 중앙값을 돌려줍니다.
  - `elapsedText(_:)` — 60분 미만은 `m:ss`, 이상은 `N시간 M분`.
  - `ago(_ seconds:)` — 60초 미만은 "방금", 그 외는 "N분 전" / "N시간 M분 전".
  - `estimate(elapsed:typical:samples:) -> String`
    - 표본 부족: "예상 시간 자료 부족"
    - 경과 < typical: "보통 4분 (지난 7회) · 약 2분 남음"
    - 경과 ≥ typical: "보통 4분 (지난 7회) · 보통보다 길어지는 중"
  - `isQuiet(idle:) -> Bool` — `idle >= quietAfter`.
- **`Sources/MyTerminal/Pipeline/PipelineRunner.swift`**
  - `Live`에 추가: `lastActivity: Date?`, `lastEvent: (title: String, at: Date)?`, `typical: TimeInterval?`, `samples: Int`.
  - `@ObservationIgnored` 캐시 두 개를 둡니다. `screens: [String: String]`(key `jobId-step-round`, 비교 기준 화면)과 `typicals: [String: (TimeInterval?, Int)]`.
  - `updateLive`:
    - 화면을 읽습니다. 캐시에 기준 화면이 없으면 저장만 하고, 기준과 다를 때만 "화면 변경 시각 = now"로 둡니다.
    - trace 수정 시각과 `TraceEvent.load(trace).last { $0.kind != "change" }`를 읽습니다.
    - `lastActivity = max(trace 시각, 화면 변경 시각, since)`.
    - 활성 단계가 없어지면 해당 키 캐시를 지웁니다.
  - `stepDurations(step:agent:) -> [TimeInterval]` — `jobs`를 훑어 파일 수정 시각 두 개로 계산합니다(최근 10개).
  - `cancel` → 창 자손 프로세스 종료를 확인한 뒤 기록합니다. `migrateLegacyPlan`의 "창 닫기 → 5초 대기 → 강제 종료" 패턴을 공통화한 것입니다.
    1. `@ObservationIgnored stopping: Set<String>`으로 중복 중단을 막습니다.
    2. `list-panes … #{pane_pid}`로 pane pid를 얻고, `ProcessMonitor` 프로세스 표에서 그 pid의 자손 pid를 모두 모읍니다(창을 닫기 전에 모아야 PPID가 1로 바뀌기 전에 잡힙니다).
    3. `Tmux.killWindow`를 부르고, 모은 pid에 `SIGTERM`을 보냅니다.
    4. 100ms 간격으로 최대 5초 기다리고, 남은 pid에는 `SIGKILL`을 보냅니다.
    5. 모두 종료된 것을 확인한 뒤 `recordFailure(…, "사용자가 중단했어요")`를 부릅니다. 이 시점에는 agent가 이미 끝났으므로 `recordFailure`의 "결과 파일이 이미 있으면 그대로 둠" 가드가 경합 없이 성립합니다. agent가 종료 직전에 성공을 써 두었다면 성공이 남습니다.
    6. `refresh`를 부르고 `stopping`에서 제거합니다.
  - `migrateLegacyPlan`도 같은 헬퍼(`stopWindow(session:window:) async`)를 쓰게 바꿉니다. 헬퍼는 2~4단계를 담당하고, 기존의 pane pid만 죽이던 부분이 자손까지 넓어집니다.
- **`Sources/MyTerminal/Sessions/ProcessMonitor.swift`** — `processTable()`을 `static`(internal)으로 바꿔 재사용합니다. 자손 수집은 `parent` 필드로 트리를 훑는 작은 함수 `static descendants(of:in:) -> [Int32]`로 추가합니다.
- **`Sources/MyTerminal/Home/JobCard.swift`**
  - `elapsed(_:)`를 `" · " + StepClock.elapsedText(...)`로 바꿉니다.
  - 실행 중인 `AgentRow`의 `LiveActivity` 위에 한 줄(`StepStatusLine`, 같은 파일 private)을 둡니다.
    - 첫째 줄: "마지막 기록 · {lastEvent.title} · {ago}". 없으면 "아직 기록 없음".
    - 둘째 줄: "{estimate} · 단계 안 진척은 알 수 없음".
    - `isQuiet`이면 첫째 줄을 기존 경고색(`Theme`의 주황 계열)으로 바꾸고 "N분째 새 기록 없음 — 오래 걸리는 중이거나 멈췄을 수 있어요. 필요하면 중단 후 다시 시도" 문구를 붙입니다.
  - 중단 중(`stopping`)에는 중단 버튼을 비활성화하고 "중단하는 중…"으로 표시합니다.
- **`Sources/MyTermAgent/main.swift`** — 변경하지 않습니다. 1차 설계의 시그널 핸들러는 철회합니다.

## 검증 규칙
- **파일이 없거나 수정 시각·내용을 못 읽는 경우**(trace·started·result): 그 값은 `nil`로 보고 건너뜁니다. 표시만 달라지고("아직 기록 없음", "자료 부족") 실행 판단에는 쓰지 않습니다.
- **소요 시간이 0 이하**(시계 어긋남, 다시 시도로 started가 새로 생김): 표본에서 뺍니다. 실패한 실행(`ok != true`)도 뺍니다.
- **첫 화면은 활동이 아닙니다**. 단계·회차·다시 시도가 바뀌면 기준 화면과 캐시를 새로 잡습니다.
- **프로세스 종료 대상**은 중단 시점에 그 창의 pane pid에서 시작한 자손만입니다.
  - 앱 자신의 pid, 0, 1, 음수는 제외합니다.
  - 그룹 단위 `kill(-pgid)`는 쓰지 않습니다. 남의 그룹을 건드리지 않기 위해서입니다.
  - pane pid를 못 얻으면 기존대로 창만 닫고 기록합니다(퇴행 없음).
- **실패 기록은 자손 종료를 확인한 뒤에만** 남깁니다. SIGKILL 뒤에도 남은 pid가 있으면 기록은 그대로 하고 `lastError`에 "일부 프로세스(pid …)를 끝내지 못했어요"를 알립니다.
- **다시 시도**는 `phase == .failed`일 때만 동작합니다(기존 가드). 실패 기록이 종료 확인 뒤에 생기므로, 종료 전에는 다시 시도할 수 없습니다.
- **경계값**
  - idle 299초는 경고 없음, 300초는 경고.
  - 표본 1개는 "자료 부족", 2개부터 표시.
  - 경과 3599초는 `59:59`, 3600초는 `1시간 0분`.

## 테스트 계획
- **`Tests/MyTerminalTests/StepClockTests.swift`** (XCTest, 기존 스타일)
  - `typical`: `[]`, `[60]`, `[0,-5,60]`은 nil. `[60,240]`은 150. `[60,120,600]`은 120.
  - `elapsedText`: 59초 `0:59`, 3599초 `59:59`, 3600초 `1시간 0분`, 7401초 `2시간 3분`.
  - `ago`: 30초 "방금", 125초 "2분 전".
  - `estimate`: 표본 1개는 "자료 부족". typical 240·경과 130은 "약 2분 남음". 경과 300은 "보통보다 길어지는 중".
  - `isQuiet`: 299초 false, 300초 true.
- **`ProcessMonitor.descendants` 테스트**: 가짜 표 `{10→1, 11→10, 12→11, 13→1}`에서 `descendants(of:10)`가 `{11,12}`인지 확인합니다.
- **파일 기반 테스트 1개**(`FollowUpPipelineTests` 방식): 임시 작업 폴더에 `plan-1.started`와 `plan-1.result.json`을 만들고 수정 시각을 조작해 소요 시간 계산을 확인합니다. 실패 결과는 빠져야 합니다.
- **수동 확인**
  1. `swift build && swift test`.
  2. 앱을 다시 빌드하고 간단한 요청을 보냅니다. 카드에 "마지막 기록 · Read · … · 방금"과 "예상 시간 자료 부족 · 단계 안 진척은 알 수 없음"이 뜨는지 봅니다. 두 번째 작업부터 "보통 N분 (지난 M회)"이 뜨는지 봅니다.
  3. 경고: 설계 중 `kill -STOP <claude pid>`를 겁니다. 테스트할 때만 `quietAfter`를 30초로 낮춰 주황 경고가 뜨는지 확인하고, 상수를 되돌린 뒤 `kill -CONT`로 풉니다.
  4. 중단: STOP 상태 그대로 카드의 "중단"을 누릅니다(SIGTERM이 무시되는 경우로 SIGKILL 단계까지 확인). 5초 안팎에 실패로 기록되는지, 그리고 `ps -axo pid,ppid,command | grep -E 'claude -p|codex exec'`에 이번 작업의 프로세스가 남지 않는지 확인합니다.
  5. 앱 재시작: 실행 중에 앱을 다시 켜도 "마지막 기록" 시각이 trace 기준으로 유지되고 "방금"으로 바뀌지 않는지 봅니다.
- **참고**: 이미 남아 있는 고아 프로세스는 이번 변경과 별개로 한 번 수동 정리가 필요합니다(`kill <pid>`). 이 실행은 읽기 전용이라 직접 끄지 않았습니다.

## 리뷰 반영
- [반영] 출력이 없다는 이유만으로 정상 작업을 자동 중단할 수 있음 — 자동 중단(`abortAfter`, `checkAlive` 변경)을 모두 뺐습니다. 5분 무기록은 "오래 걸리는 중이거나 멈췄을 수 있어요" 경고만 띄우고, 끊을지는 사용자가 기존 "중단"으로 정합니다. trace는 도구 호출·결과·훅만 기록하므로(`Trace.claude`) 무기록을 멈춤으로 확정할 수 없다는 지적이 맞습니다.
- [반영] 최신 활동을 읽기 전에 중단 판정이 실행됨 — 중단 판정을 없애 순서 문제가 사라졌습니다. 표시 값은 `tick()`의 `refresh` 뒤에 도는 `updateLive`에서 한 번에 계산합니다. "첫 화면은 기준으로만 저장, 활동 아님"과 "단계·회차·다시 시도마다 캐시 초기화"를 검증 규칙과 수동 확인 5번에 넣었습니다.
- [반영] 기존 결과 파일 가드는 성공 우선 처리를 보장하지 않음 — 자동 중단 경로는 없어졌습니다. 남은 경로인 `cancel`도 순서를 바꿔 "자손 프로세스 종료 확인 → `recordFailure`"로 합니다. 쓰는 쪽(agent)이 끝난 뒤에 존재 검사를 하므로 두 작성자 간 경합이 없습니다. 실패 기록 전에는 `phase`가 `.failed`가 아니라서 다시 시도도 막힙니다.
- [반영] 단일 PID에 SIGTERM을 보내고 즉시 종료하면 고아 프로세스가 남을 수 있음 — agent 쪽 시그널 핸들러를 철회했습니다. 대신 앱에서 pane pid의 자손 전체를 창 닫기 전에 모으고, SIGTERM → 5초 대기 → SIGKILL → 종료 확인 순서로 처리합니다. 이미 있는 `migrateLegacyPlan`의 대기·강제 종료 패턴과 `ProcessMonitor.processTable`을 재사용합니다. 셸 fallback(`zsh -lc exec`)도 자손 트리에 포함되므로 따로 처리하지 않아도 됩니다. SIGSTOP(SIGTERM이 무시되는 경우) 재현을 테스트 계획에 넣었습니다. 한 가지 차이는 있습니다. 리뷰가 제안한 "프로세스 그룹 대상"은 받지 않고 pid 목록 대상으로 합니다. `Process`가 띄운 자식의 그룹 소속을 이 앱이 보장하지 않아서, 그룹 kill은 남의 그룹을 칠 위험이 있기 때문입니다.
- [반영] 시간 추정이 현재 작업 내용과 실제 진척을 대신하고 있음 — `TraceChips`가 `isBackground`(claude·codex·hook)를 걸러 내서 평범한 도구 호출이 카드에 안 보이던 것이 "뭘 하는지 모름"의 직접 원인이었습니다. 걸러 내지 않은 마지막 기록과 시각을 따로 보여 줍니다. 예상 시간은 "지난 N회 기준"으로 출처를 밝히고, 표본이 부족하면 "예상 시간 자료 부족", 단계 안 진척은 "알 수 없음"으로 명시합니다. 리뷰 예시의 "결과 대기"처럼 상태를 단정하는 표기는 쓰지 않습니다. 일반 도구는 결과 이벤트를 남기지 않아서(`toolResult`는 읽기·찾기·곁들인 도구만 기록) 대기 중인지 판정할 근거가 없기 때문입니다.