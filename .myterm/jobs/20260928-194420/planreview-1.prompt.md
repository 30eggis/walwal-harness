Claude 가 아래 요청의 설계를 썼다. 구현하기 전에 이 설계를 리뷰해줘.

## 요청
/var/folders/c1/wpbtkszj5_7cf6ggsjfcgbzh0000gn/T/TemporaryItems/NSIRD_screencaptureui_TFiQNm/스크린샷 2026-09-28 19.43.38.png 
또 설계를 123:30초… 초과하며 하고다 

뭘하고있는지 알수도 없고. 어디까지 진행중인지 얼마나 남앗는지 알려달라.. 답답하다

## 작업 담당의 walwal-harness
Codex 는 /goal 를 쓸 수 없어요 (없음: .codex/commands/goal.md, .codex/skills/harness-ceo/SKILL.md) — 실행 방식은 llm 으로 한다.

## 설계 (Claude)
# MyTerminal 단계 진행 가시화 + 멈춘 단계 자동 감지

## 요약
스크린샷의 "설계 중 · 123:21"은 실제로는 설계를 하고 있던 게 아니라 멈춰 있던 시간입니다. 6차 설계(`plan-6`)는 17:40:17에 시작했고, 23초 뒤인 17:40:40 이후로 trace에 한 줄도 쌓이지 않았습니다. 그 claude 프로세스(pid 23412)는 CPU 0%로 2시간 넘게 살아 있습니다. 앱은 tmux 창이 닫혔을 때만 실패로 판단하기 때문에 경과 시간만 계속 올라갔습니다. 이번 변경은 카드에 세 가지를 보여 줍니다. ① 마지막 활동 시각, ② 이 단계가 보통 걸리는 시간과 남은 시간, ③ 오래 움직임이 없으면 멈춤 경고. 일정 시간 넘게 멈추면 자동으로 중단하고 "다시 시도"를 띄웁니다. 중단한 뒤에 claude 프로세스가 고아로 남는 버그도 함께 고칩니다.

## 요구 분석
- **뭘 하고 있는지 알 수 없음**: 지금 카드에는 tmux 마지막 6줄(LiveActivity)과 경과 시간만 있습니다. 그 줄이 방금 찍힌 건지 2시간 전에 찍힌 건지 구분할 수 없습니다. → "마지막 활동 N분 전"을 보여 줍니다.
- **어디까지 진행 중인지**: 배치 줄(`PlacementRow`)의 `▶`와 타임라인이 이미 현재 단계를 보여 줍니다. 부족한 건 이 단계 안에서의 진척입니다. → 경과 시간을 "보통 걸리는 시간"과 비교해 보여 줍니다.
- **얼마나 남았는지**: 같은 워크스페이스에서 끝난 같은 단계·같은 CLI 실행의 소요 시간 중앙값으로 "약 N분 남음" 또는 "예상보다 길어짐"을 보여 줍니다.
- **123분씩 멈춰 있는 문제**: 멈춤을 감지하는 장치가 없습니다(`PipelineRunner.checkAlive`는 창이 있는지만 확인). → 무활동 경고와 자동 중단을 넣습니다.
- **(발견) 고아 프로세스**: 중단(kill-window)하면 `myterm-agent`만 죽습니다. claude는 자기 프로세스 그룹에 있어서 살아남습니다. 증거는 PPID 1인 설계리뷰 claude 두 개(pid 18856, 56124)가 3~6시간째 살아 있는 것입니다. 자동 중단이 제대로 되려면 이것부터 고쳐야 합니다.

## 모호점과 해소안
- **"활동"의 기준** → trace.jsonl의 수정 시각과 tmux 화면 내용이 바뀐 시각 중 늦은 쪽을 씁니다. trace는 도구 호출과 훅마다 기록되지만, 긴 최종 답을 쓰는 동안에는 비어 있을 수 있어서 화면 변화도 함께 봅니다. 앱을 다시 켜면 화면 기준 값은 사라지지만 trace 수정 시각은 파일에 남으므로 그대로 복원됩니다.
- **경고 기준 5분, 자동 중단 기준 20분** → Bash 도구는 최대 10분이면 타임아웃되고, 사고 구간도 몇 분 수준입니다. 그래서 20분 동안 아무 이벤트가 없으면 멈춘 것으로 봐도 됩니다. 두 값은 상수 하나씩으로 둡니다(조정 손잡이).
- **자동 중단 뒤 자동 재시도 여부** → 하지 않습니다. 실패로 기록하고 기존 "다시 시도" 버튼을 띄웁니다. 멈춤의 원인은 알 수 없습니다(이번 경우는 `ls ~/Downloads` 호출 직후 API 스트림이 멈춘 것으로 추정). 원인을 모르는 채로 토큰을 들여 자동 반복하지 않습니다. 필요해지면 1회 자동 재시도는 나중에 넣습니다.
- **"보통 걸리는 시간"의 표본** → `jobs`에 로드된 이 워크스페이스의 작업 중 같은 단계·같은 CLI로 성공한 실행에서 가장 최근 10개를 씁니다. 소요 시간은 `<step>-<n>.started` 수정 시각부터 `result.json` 수정 시각까지입니다. 표본이 2개 미만이면 예상 시간을 보여 주지 않습니다(추측값을 보여 주지 않음).
- **긴 경과 시간 표기** → 60분 이상은 "123:21" 대신 "2시간 3분"으로 씁니다.
- **변경 대상 저장소** → 화면이 MyTerminal이므로 변경은 `/Users/ted/project/myterminal`에서 합니다. walwal-harness는 건드리지 않습니다.

## 변경 파일
- **`Sources/MyTerminal/Pipeline/StepClock.swift` (새 파일)**: 순수 함수만 둡니다(테스트용).
  - `static let staleAfter: TimeInterval = 300`, `static let abortAfter: TimeInterval = 1200`
  - `typical(_ durations: [TimeInterval]) -> TimeInterval?`: 표본이 2개 이상일 때만 중앙값을 돌려줍니다.
  - `elapsedText(_ seconds:)`: 60분 미만은 `m:ss`, 이상은 `N시간 M분`.
  - `status(elapsed:idle:typical:) -> (text: String, stale: Bool)`: 예시 `" · 2:10 · 약 2분 남음 · 방금 활동"`, `" · 2시간 3분 · ⚠ 123분째 움직임 없음"`. `idle`이 60초 미만이면 "방금 활동", 5분 이상이면 stale입니다.
- **`Sources/MyTerminal/Pipeline/PipelineRunner.swift`**
  - `Live`에 `lastActivity: Date?`와 `typical: TimeInterval?`를 추가합니다.
  - `updateLive`: 잡아 온 줄이 이전과 다르면 `now`로 갱신합니다. 그다음 trace 파일 수정 시각, `since`와 비교해 가장 늦은 값을 `lastActivity`로 둡니다. `typical`은 단계가 바뀔 때 한 번만 계산해 `@ObservationIgnored` 딕셔너리(key: `jobId-stepRound`)에 캐시합니다.
  - `checkAlive`: 창이 살아 있어도 `now - lastActivity ≥ StepClock.abortAfter`이면 `cancel`과 같은 경로로 처리합니다. 먼저 `recordFailure(…, "20분 동안 아무 활동이 없어 멈춘 것으로 보고 중단했어요 — 다시 시도를 누르세요")`를 쓰고, 그다음 `Tmux.killWindow`를 부릅니다.
  - 소요 시간 계산 헬퍼 `stepDuration(files, step, round) -> TimeInterval?`(파일 수정 시각 두 개)를 여기에 둡니다.
- **`Sources/MyTerminal/Home/JobCard.swift`**
  - `elapsed(_:)`를 `StepClock.status(...)`로 바꿉니다.
  - stale이면 `AgentRow`의 상태 글자를 주황(`Theme` 기존 주황/경고 색)으로 표시합니다. 그 옆에 "멈춘 것 같아요 — 중단 후 다시 시도" 도움말을 붙입니다. 버튼은 기존 "중단"을 그대로 씁니다.
- **`Sources/MyTermAgent/main.swift`**: 고아 프로세스를 막기 위해 시그널을 넘겨줍니다.
  - 전역 `var childPID: pid_t = 0`를 두고, `runStreaming`에서 `process.run()` 직후에 `childPID = process.processIdentifier`로 설정합니다.
  - 시작할 때 `SIGHUP`, `SIGTERM`, `SIGINT`에 `signal(sig) { s in if childPID > 0 { kill(childPID, SIGTERM) }; _exit(128 + s) }`를 등록합니다. 캡처가 없는 C 함수 형태입니다.
  - 결과 파일은 앱의 `recordFailure`가 먼저 쓰고, agent는 쓰지 않고 곧바로 빠집니다.

## 검증 규칙
- **파일이 없거나 수정 시각을 못 읽는 경우**(trace·started·result): 그 값은 `nil`로 보고 건너뜁니다. `lastActivity`가 `nil`이면 `since`를 씁니다. 둘 다 없으면 자동 중단하지 않습니다. 근거 없이 중단하지 않습니다.
- **소요 시간이 0 이하이거나 음수**(시계 어긋남, 재시도로 started가 새로 생긴 경우): 표본에서 뺍니다.
- **자동 중단은 결과 파일이 없을 때만 합니다**(`recordFailure`의 기존 가드). 단계가 막 끝나며 결과를 쓴 경우에는 성공이 이깁니다.
- **자동 중단 판단은 `activeStep`이 있는 작업에만 합니다.** 사용자 결정 대기(`awaitingStart`/`awaitingDecision`/`awaitingConsensus`)에는 `activeStep`이 없으므로 대상이 아닙니다.
- **시그널 핸들러는 `childPID == 0`이면 자식을 죽이지 않고 종료만 합니다.** 자기 자신이나 그룹 0에 `kill`을 보내지 않도록 `> 0` 조건을 지킵니다.
- **경계값**: idle 299초는 경고 없음, 300초는 경고. 1199초는 유지, 1200초는 중단. 표본 1개는 예상 없음, 2개부터 표시.

## 테스트 계획
- **`Tests/MyTerminalTests/StepClockTests.swift`** (XCTest, 기존 스타일)
  - `typical`: `[]`와 `[60]`은 nil, `[60,240]`은 150, `[60,120,600]`은 120, 음수와 0은 제외.
  - `elapsedText`: 59초는 `0:59`, 3599초는 `59:59`, 3600초는 `1시간 0분`, 7401초는 `2시간 3분`.
  - `status`: idle 30초는 "방금 활동"이고 stale=false. idle 299초와 300초로 경계를 확인합니다. typical 240에 elapsed 130이면 "약 2분 남음", elapsed 300이면 "예상보다 길어짐".
- **`FollowUpPipelineTests`와 같은 방식의 파일 기반 테스트 1개**: 임시 작업 폴더에 `plan-1.started`와 `plan-1.result.json`을 만들고 수정 시각을 조작해 `stepDuration`을 확인합니다.
- **수동 확인**
  1. `swift build && swift test`.
  2. 앱 재빌드 후 간단한 요청으로 카드에 "· 0:42 · 방금 활동"이 뜨는지 봅니다. 두 번째 이후 작업에서는 "약 N분 남음"이 뜨는지 봅니다.
  3. 멈춤 재현: 설계 단계 중 `kill -STOP <claude pid>`를 겁니다. 테스트할 때만 상수를 잠시 30초·90초로 낮춰서 주황 경고, 자동 중단, 실패 문구, "다시 시도" 순서로 나오는지 확인하고 상수는 되돌립니다.
  4. 고아 확인: 카드에서 "중단"을 누른 뒤 `ps -axo pid,ppid,command | grep 'claude -p'`에 PPID 1인 claude가 새로 남지 않는지 봅니다.
- **참고**: 지금 남아 있는 고아 프로세스(18856, 56124)와 멈춘 6차 설계(23412)는 이번 변경과 별개로 한 번 수동 정리가 필요합니다. 23412를 끄려면 카드의 "중단"을 누르고, 18856과 56124는 `kill`로 직접 끕니다. 이 실행은 읽기 전용이라 직접 끄지 않았습니다.