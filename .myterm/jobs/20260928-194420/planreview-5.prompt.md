Claude 가 아래 요청의 설계를 썼다. 구현하기 전에 이 설계를 리뷰해줘.

## 요청
/var/folders/c1/wpbtkszj5_7cf6ggsjfcgbzh0000gn/T/TemporaryItems/NSIRD_screencaptureui_TFiQNm/스크린샷 2026-09-28 19.43.38.png 
또 설계를 123:30초… 초과하며 하고다 

뭘하고있는지 알수도 없고. 어디까지 진행중인지 얼마나 남앗는지 알려달라.. 답답하다

## 이어서 받은 답과 지시 — 위 요청과 다르면 이쪽을 따른다
- 되물음: 설계와 리뷰를 확인했습니다. 변경 대상은 `/Users/ted/project/myterminal`이지만, 현재 세션은 `walwal-harness`에만 쓰기가 허용되어 구현할 수 없습니다. MyTerminal 저장소를 작업 폴더로 열어 같은 요청을 실행해 주세요. 파일은 변경하지 않았습니다.
  답: myterminal 에 이슈 전달할수 있도록 정리된 문서를 달라.

## 배경 — 앞선 요청의 기록 (이번 요청은 위 "요청" 이다. 원래 요청은 배경으로만 본다)
- 첫 지시 (원래 요청): `.myterm/jobs/20260928-194420/plan-1.prompt.md`
- 설계: `.myterm/jobs/20260928-194420/plan-3.md`
- 설계리뷰: `.myterm/jobs/20260928-194420/planreview-3.md`
- 직전 작업 요약 (3차): `.myterm/jobs/20260928-194420/work-3.md`
이 대화에는 앞의 내용이 없다. 시작하기 전에 필요한 문서를 읽는다.

## 합의 2차
네가 지난번에 재설계를 요청했고 (`.myterm/jobs/20260928-194420/planreview-4.md` — 이 대화에서 쓴 것), Claude 가 지적마다 반영하거나 반박한 새 설계를 냈다.
설계의 "## 리뷰 반영" 을 지적마다 대조한다: 반영은 설계에 실제로 들어갔는지, 반박은 이유가 타당한지.
타당한 반박은 받아들이고, 남은 HIGH · MEDIUM 이 없으면 "합의" 한다.

## 작업 담당의 walwal-harness
Codex 는 /goal 를 쓸 수 없어요 (없음: .codex/commands/goal.md, .codex/skills/harness-ceo/SKILL.md) — 실행 방식은 llm 으로 한다.

## 설계 (Claude)
# MyTerminal 이슈: 단계 진행 표시·멈춤 경고·중단 시 프로세스 트리 정리 (5차, 4차 리뷰 반영)

## 요약
이 문서는 `/Users/ted/project/myterminal`에 이슈로 그대로 올릴 수 있게 정리했습니다. 4차 설계(`plan-4.md`)를 바탕으로 4차 리뷰(`planreview-4.md`)의 지적 네 건을 모두 반영했습니다. 네 건 모두 코드에서 확인했습니다. `delete`는 267행에 가드가 없고, `recordFailure`는 887행에서 성공 여부를 돌려주지 않습니다.

**문제**
- 카드에는 "설계 중 · 123:21"처럼 경과 시간만 보입니다. 사용자는 지금 무엇을 하는지, 기록이 언제 끊겼는지, 얼마나 남았는지 알 수 없습니다.
- "중단"(346행)과 "카드 삭제"(287행)는 `Tmux.killWindow`만 호출합니다. 이 호출은 pane 루트에 SIGHUP만 보내므로 claude·codex와 그 하위 도구가 살아남습니다.

**이번 변경**
- 카드에 마지막 기록, 예상 시간, 무기록 경고를 표시합니다.
- 중단 절차를 바꿉니다. 대상을 식별해 디스크에 먼저 기록한 뒤 트리를 얼리고(SIGSTOP) 강제 종료(SIGKILL)합니다.
- 종료가 확인된 경우에만 실패를 기록합니다. 확인 전에는 진행, 다시 시도, 삭제를 모두 막습니다.
- walwal-harness 쪽은 바꾸지 않습니다.

---

**이슈 제목(안):** `[파이프라인] 단계 진행 상황이 안 보이고, 중단·삭제해도 CLI 프로세스가 남음`

**재현**
1. 설계가 오래 걸리는 요청을 보냅니다. 카드에는 "설계 중 · 123:21"만 보입니다.
2. "중단"을 누르거나 카드를 삭제합니다.
3. `ps -axo pid,ppid,command | grep -E 'claude -p|codex exec'`를 실행하면 이 작업의 CLI가 아직 남아 있습니다.

**원인**
- `JobCard.TraceChips`는 `isBackground` 이벤트(claude·codex·hook)를 걸러 냅니다. 그래서 설계·리뷰 단계의 활동이 카드에 보이지 않습니다.
- `PipelineRunner.updateLive`는 경과 시간만 계산합니다.
- `cancel`과 `delete`는 창만 닫습니다. `runStreaming`이 띄운 CLI와 그 자손은 SIGHUP으로 끝나지 않습니다.

## 요구 분석
- **무엇을 하는지:** trace에서 마지막 이벤트(`kind != "change"`, hook 포함)를 골라 "마지막 기록 · Bash · ls … · 12분 전"처럼 보여 줍니다.
- **어디까지 진행했는지**
  - 단계 단위 진행은 기존 `PlacementRow`의 `▶` 표시를 그대로 씁니다.
  - 단계 안의 진척률은 CLI가 알려 주지 않으므로 만들어 내지 않고 "단계 안 진척은 알 수 없음"으로 표기합니다.
- **얼마나 남았는지:** 같은 워크스페이스에서 같은 단계·같은 CLI로 성공한 최근 10회의 중앙값을 씁니다.
  - 예: "보통 4분 (지난 7회) · 약 2분 남음" / "보통보다 길어지는 중"
  - 표본이 2개 미만이면 "예상 시간 자료 부족"으로 표기합니다.
- **멈춤 경고:** 새 기록이 5분 이상 없으면 주황색 경고를 띄웁니다. 자동으로 중단하지는 않습니다.
- **중단 시 트리 전체 종료**
  - 종료가 확인된 경우에만 실패로 기록합니다.
  - 확인되지 않은 동안에는 자동 진행, 창 소멸을 이유로 한 실패 판정, 다시 시도, 카드 삭제를 모두 막습니다.
- **(4차 HIGH-1)** 종료를 확인하다가 새로 발견한 대상도 신호를 보내기 **전에** 디스크에 기록합니다.
- **(4차 HIGH-2)**
  - 첫 기록 저장에 실패해도 차단은 유지합니다.
  - 실패 결과가 실제로 남았을 때만 stop 기록을 지웁니다.
- **(4차 HIGH-3)** 중단 중이거나 미확인이거나 실행 중이면 카드 삭제를 막습니다(UI와 함수 양쪽). 실행 중 삭제도 같은 고아 프로세스 문제의 원인이므로 함께 막습니다.
- **(4차 MEDIUM)** 루트 pid를 얻지 못한 기록을 명시적으로 표현합니다. 재중단할 때 루트 식별을 다시 시도합니다.

## 모호점과 해소안
- **자동 중단 여부** → 하지 않습니다. 기록이 없다는 것은 멈췄을 가능성일 뿐, 확정 근거가 아닙니다.
- **"활동" 시각** → `max(trace 수정 시각, 화면이 바뀐 시각, 단계 시작 시각)`으로 봅니다. 단계별로 처음 읽은 화면은 비교 기준으로만 쓰고 활동으로 치지 않습니다.
- **경고 기준** → `StepClock.quietAfter = 300` 상수로 둡니다. 나중에 조정할 수 있는 손잡이입니다.
- **예상 시간 표본** → `.started` 수정 시각부터 `.result.json` 수정 시각까지를 씁니다.
  - `ok == true`이고 소요 시간이 0보다 큰 것만 씁니다.
  - 단계가 바뀔 때 한 번 계산해 캐시합니다.
- **프로세스 식별** → `proc_pidinfo(PROC_PIDTBSDINFO)`의 `pbi_start_tvsec`/`pbi_start_tvusec`와 `pbi_ppid`로 `(pid, 시작 시각)`을 만듭니다.
  - `exec`는 pid와 시작 시각을 유지하므로 같은 실행으로 봅니다.
  - pid가 재사용되면 시작 시각이 달라지므로 다른 실행으로 봅니다.
- **대상 편입 규칙(`adopt`)** — `freezeTree`와 `killAndConfirm`이 **같은 함수**를 씁니다.
  1. 후보가 다음 중 하나에 해당해야 합니다.
     - `proc_pidinfo`로 다시 읽은 ppid가 이미 얼린 대상이고, 후보의 시작 시각이 부모보다 이르지 않음
     - `getsid == 루트 pid`이고, 시작 시각이 루트 이후임(중간 프로세스가 죽어 입양된 손자)
  2. `record(기존 ∪ 새 대상)`로 저장합니다.
  3. 저장에 성공하면 SIGSTOP을 보냅니다. 저장에 실패하면 신호를 보내지 않고 `.unconfirmed`로 끝냅니다.

  얼어 있는 부모는 fork할 수 없으므로 ppid 경합이 없습니다. 반복은 최대 20회입니다. 스스로 `setsid`한 프로세스는 잡지 못하며, 이 한계는 이 문서에만 적어 둡니다.
- **종료 방식** → 트리를 SIGSTOP으로 얼린 뒤 SIGKILL을 보냅니다. 보내기 직전에 `(pid, 시작 시각)`을 다시 대조합니다. 중단한 단계의 결과는 버리므로 SIGTERM으로 정리할 기회는 포기합니다.
- **종료 확인** → 대상마다 다음 기준으로 판정합니다. 확인은 100ms 간격으로 최대 5초 동안 합니다.
  - "종료됨": `ESRCH`이거나 시작 시각이 달라짐
  - "미확인": `EPERM`이나 그 밖의 오류

  기록된 targets가 모두 종료됨이고, 루트가 식별된 경우 `getsid` 재탐색에서도 새 잔존 프로세스가 없어야 `.stopped`입니다. **targets가 비어 있고 루트도 없으면 `.stopped`가 아니라 미확인입니다.**
- **중단 기록 파일** → `<step>-<round>.stop.json`
  - 담는 값: `{step, round, root: ProcID?, targets: [ProcID], state: "freezing"|"killing"|"unconfirmed"|"confirmed", reason?}`
  - `root == nil`이면 "루트 미확보"입니다(MEDIUM).
- **첫 기록 저장 실패(HIGH-2)** → 기록 전에는 신호를 보내지 않으므로 프로세스 트리는 손대지 않은 상태입니다.
  - 메모리 차단 `stopBlocked[jobId] = 사유`를 걸고 `lastError`를 표시합니다.
  - 앱을 재시작하면 이 차단은 사라집니다. 신호를 보낸 적이 없으므로 원래 실행 상태로 돌아가는 것은 안전합니다.
  - "다시 중단"에 성공하면 차단을 해제합니다.
- **마무리(HIGH-2)** → 순서는 `confirmed` 저장 → `recordFailure`(Bool 반환) → `killWindow` → stop 파일 삭제입니다.
  - stop 파일은 `recordFailure == true`일 때만 지웁니다. 결과 파일이 이미 있었거나 저장에 성공한 경우입니다.
  - `false`이면 `confirmed` 기록을 남기고 차단을 유지합니다. 다음 `reload`나 "다시 중단" 때 마무리를 멱등하게 다시 합니다.
- **재중단 시 루트 미확보(MEDIUM)** → 기록의 `(step, round)` 창에서 `panePid`를 다시 읽습니다.
  - **성공:** `root`를 저장하고 정상 절차로 수집·종료합니다.
  - **창이 없고 targets가 비어 있음:** 신호를 보낸 대상이 없고 창도 없습니다. 기존 `checkAlive`와 같은 판정이므로 마무리 절차로 갑니다.
  - **창은 있는데 pid를 여전히 읽지 못함:** 미확인을 유지합니다.
- **카드 삭제(HIGH-3)** → 다음 경우에는 삭제를 거부합니다.
  - `stopping`, `pendingStop`, `stopBlocked` 중 하나라도 해당할 때
  - `activeStep != nil`일 때(실행 중)

  거부 안내는 "먼저 중단하세요"와 "중단 확인이 끝나지 않았어요 — '다시 중단'을 눌러 주세요"입니다. 실행 중 삭제를 허용하면 `delete`의 `killWindow`가 고아 프로세스를 그대로 남기기 때문입니다.
- **앱 재시작** → 기록 상태에 따라 처리합니다.
  - `freezing`/`killing`이면 `unconfirmed`로 다시 씁니다(사유: "앱이 중단 도중 종료됨"). 자동으로 다시 중단하지 않고, 얼어 있는 프로세스는 사용자가 누를 때까지 둡니다.
  - `confirmed`이면 마무리를 이어서 합니다.

## 변경 파일
- **`Sources/MyTerminal/Pipeline/StepClock.swift` (새 파일, 순수 함수)**
  - `quietAfter = 300`
  - `typical(_:)`: 0 이하 값을 빼고, 2개 이상일 때만 중앙값
  - `elapsedText(_:)`: 60분 미만은 `m:ss`, 이상은 `N시간 M분`
  - `ago(_:)`, `estimate(elapsed:typical:samples:)`, `isQuiet(idle:)`
- **`Sources/MyTerminal/Sessions/ProcessMonitor.swift` (`ProcessScanner` 확장)**
  - `processTable()`: 실패하면 `nil`을 돌려줍니다. 기존 호출부는 `?? [:]`를 붙여 지금 동작을 유지합니다.
  - `struct ProcID: Codable, Hashable { pid: Int32; startSec: Int64; startUsec: Int32 }`
  - `static func identity(_ pid:) -> Result<(ProcID, ppid: Int32), ProbeError>`: 오류는 `.gone`과 `.unknown(errno)`로 나눕니다.
  - `private func adopt(...)`: 편입 규칙 → `record` → SIGSTOP. 두 진입점이 함께 씁니다(HIGH-1).
  - `func freezeTree(root: ProcID, record: (Set<ProcID>) throws -> Void) async -> Result<Set<ProcID>, StopError>`
  - `func killAndConfirm(_ targets: Set<ProcID>, root: ProcID?, record: (Set<ProcID>) throws -> Void) async -> StopOutcome`
    - 재탐색으로 새 대상을 찾으면 `adopt`로 기록을 먼저 갱신합니다.
    - 반환값은 `enum StopOutcome { case stopped(Set<ProcID>), unconfirmed(String, Set<ProcID>) }`이며, 최종 targets를 함께 돌려줍니다.
    - targets가 비어 있고 `root == nil`이면 `.unconfirmed("대상 없음")`입니다.
  - 순수 판정 `static func isGone(_:probe:) -> Bool?`: `nil`은 미확인입니다.
  - 기존 `terminate`와 `ProcessMonitor.stop/stopAll`은 바꾸지 않습니다.
- **`Sources/MyTerminal/Pipeline/Job.swift`**
  - `JobFiles.stop(_:_:)`과 `StopRecord: Codable`을 추가합니다. `root: ProcID?`입니다.
  - `JobSnapshot.pendingStop`을 추가합니다. 작업 폴더의 `*.stop.json`에서 읽습니다.
  - `retryFailedStep`이 파일을 옮길 때 `.stop.json`은 대상에서 뺍니다.
- **`Sources/MyTerminal/Pipeline/PipelineRunner.swift`**
  - `Live` 필드를 추가합니다: `lastActivity`, `lastEvent`, `typical`, `samples`
  - `@ObservationIgnored` 캐시(`screens`, `typicals`)를 둡니다. `stepDurations(step:agent:)`를 추가합니다.
  - `@ObservationIgnored let scanner = ProcessScanner()`
  - 381행의 pane pid 조회를 `panePid(session:window:) -> Int32?`로 뽑아 냅니다. 테스트에서 바꿔 끼울 수 있게 `@ObservationIgnored var panePid`(기본값은 Tmux 조회) 한 곳으로 둡니다. `cancel`과 `migrateLegacyPlan`이 함께 씁니다.
  - 관측 상태
    - `private(set) var stopping: Set<String>`
    - `private(set) var stopBlocked: [String: String]`(HIGH-2, 메모리 전용)
    - `func isStopHeld(_ job) -> Bool` = `stopping ∪ stopBlocked ∪ pendingStop`
  - **가드:** `advance`, `retry`, `delete` 맨 앞에서 `isStopHeld`이면 반환합니다. `delete`는 `activeStep != nil`일 때도 반환하고 `lastError`에 안내를 넣습니다(HIGH-3).
  - `recordFailure`를 `@discardableResult -> Bool`로 바꿉니다. 결과 파일이 이미 있거나 저장에 성공하면 `true`입니다. 기존 호출부는 바꾸지 않습니다.
  - **`cancel(_ job:)`**
    1. 대상을 정합니다. `pendingStop`이 있으면 그 기록의 `(step, round, root, targets)`를 씁니다. 없으면 `activeStep`을 씁니다. 둘 다 없으면 반환합니다. `stopping`으로 중복 실행을 막습니다.
    2. `root`가 없으면 `panePid`와 `identity`로 루트를 얻습니다(첫 중단과 MEDIUM 재시도 공통).
       - 창이 없고 targets가 비어 있으면 마무리(5번)로 갑니다.
       - 창은 있는데 루트를 얻지 못하면 `StopRecord(root: nil, targets: [], state: .unconfirmed, reason: "작업 프로세스를 찾지 못했어요")`를 저장하고 7번으로 갑니다.
    3. `StopRecord(state: .freezing)`를 저장합니다. **실패하면** 신호 없이 `stopBlocked[id]`와 `lastError`를 설정하고 7번으로 갑니다(HIGH-2). 성공하면 `freezeTree`(root가 있고 살아 있을 때)를 호출합니다.
    4. `.killing`을 저장한 뒤 `killAndConfirm(targets, root, record:)`을 호출합니다. `record`는 같은 stop 파일에 합집합을 저장합니다.
    5. `.stopped`이면 마무리합니다: `confirmed` 저장 → `recordFailure` → `true`일 때만 `killWindow`와 stop 파일 삭제, `stopBlocked` 해제. `false`이면 `confirmed`를 유지하고 `lastError`를 설정합니다.
    6. `.unconfirmed(r, t)`이면 `state: .unconfirmed, reason: r, targets: t`를 저장합니다. 창은 닫지 않고 실패도 기록하지 않습니다.
    7. `stopping.remove` 후 `refresh`합니다.
  - **`init`/`reload`:** `freezing`/`killing`이면 `unconfirmed`로 다시 씁니다. `confirmed`이면 5번 마무리를 합니다.
  - **`migrateLegacyPlan`:** pane pid를 기다리던 부분을 같은 중단 절차로 바꿉니다. `.stopped`일 때만 plan-1을 옮기고 새로 시작합니다.
  - `tick()`을 테스트를 위해 internal로 바꿉니다.
- **`Sources/MyTerminal/Home/JobCard.swift`**
  - `elapsed` 표시에 `StepClock.elapsedText`를 씁니다.
  - 실행 중인 `AgentRow` 위에 private `StepStatusLine`을 둡니다.
    - 마지막 기록과 몇 분 전인지
    - 예상 시간과 "단계 안 진척은 알 수 없음"
    - 무기록이면 주황색 경고
  - 중단 버튼(261·275행)
    - `stopping` 중이면 비활성화하고 "중단하는 중…"으로 표시합니다.
    - `pendingStop`이나 `stopBlocked`가 있으면 phase와 관계없이 사유를 경고색으로 보이고, 제목을 "다시 중단"으로 바꿉니다.
  - "다시 시도"(278행): `isStopHeld`이면 비활성화합니다.
  - **삭제(102행 휴지통, 241행 컨텍스트 메뉴):** `isStopHeld || job.activeStep != nil`이면 비활성화합니다. 도움말에 "실행 중인 작업은 먼저 중단하세요" 또는 "중단 확인이 끝나지 않았어요"를 표시합니다(HIGH-3).
- **`Sources/MyTermAgent/main.swift`:** 변경하지 않습니다.

## 검증 규칙
- trace·started·result 파일을 읽지 못하면 `nil`로 봅니다. 이 값은 표시에만 쓰고 실행 판단에는 쓰지 않습니다.
- **실패 기록은 `.stopped`일 때만** 남깁니다. 다음 경우는 모두 `.unconfirmed`입니다.
  - 표 조회, pid 조회, 식별(`EPERM` 등), 신호 중 하나라도 실패(`ESRCH` 제외)
  - 5초 뒤에도 대상이 남음
  - 20회 안에 수집이 끝나지 않음
  - stop 기록 저장 실패
  - targets가 비어 있고 루트도 없음
- **기록 없이는 신호를 보내지 않습니다.** 대상은 `freezeTree`와 `killAndConfirm` 모두 `adopt` 한 경로로만 편입되고, 저장에 성공해야 신호를 보냅니다. 앱이 어느 시점에 죽어도 신호를 받은 대상은 모두 디스크에 남아 있습니다.
- **창·루트가 사라진 것은 완료 근거가 아닙니다.** 예외는 "targets가 비어 있고 창도 없음" 하나뿐이며, 기존 `checkAlive`와 같은 판정입니다.
- **stop 파일 삭제는 실패 결과가 존재할 때만** 합니다. 그렇지 않으면 `confirmed`가 남아 차단이 유지됩니다.
- **신호 대상:** pid 0, pid 1, 음수 pid, 앱 자신은 제외합니다. 그룹 kill은 쓰지 않습니다. 식별 정보가 일치할 때만 신호를 보냅니다.
- **`isStopHeld` 동안**에는 `tick`이 여러 번 돌아도 다음이 모두 일어나지 않습니다.
  - `start`, `checkAlive`, `recordFailure` 실행
  - `retry`
  - `delete`(작업 폴더 보존)
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
  - **fork 경합:** `sh -c 'while :; do sleep 30 & sleep 0.01; done'`를 띄우고 `freezeTree`→`killAndConfirm`을 호출합니다. `.stopped`여야 하고, 테스트 시작 뒤 생긴 `sleep 30`이 ppid 1로도 남지 않아야 합니다.
  - **부분 종료 후 재중단:** 루트는 SIGKILL하고 자식 하나는 SIGSTOP 상태로 기록합니다. `killAndConfirm`으로 `.stopped`가 나와야 합니다. 자식이 살아 있는 동안에는 `.unconfirmed`여야 합니다.
  - **재탐색 편입 시 기록이 먼저인지(HIGH-1):** setsid 루트 아래에 입양된 손자를 만든 뒤 `killAndConfirm(targets: [루트], root:)`을 호출합니다.
    - `record` 콜백 안에서 새로 들어온 pid를 `ps -o stat=`로 읽었을 때 `T`(정지)가 **아니어야** 합니다. 기록이 신호보다 앞선다는 증거입니다.
    - 마지막 기록에 그 손자가 들어 있어야 합니다.
  - **재탐색 편입 시 저장 실패(HIGH-1):** 두 번째 `record` 호출에서 throw하도록 주입합니다. 결과는 `.unconfirmed`여야 하고, 그 손자는 정지되지 않은(`T`가 아닌) 상태로 살아 있어야 합니다(테스트 끝에 정리).
  - **빈 대상(MEDIUM):** `killAndConfirm([], root: nil, …)`은 `.unconfirmed`여야 합니다.
  - **식별(`isGone`):** 같은 시작 시각은 false / 다른 시작 시각은 true / `EPERM`은 nil. `sh -c 'exec sleep 30'` 사례는 대상으로 남아 종료되어야 합니다.
- **러너 테스트(`FollowUpPipelineTests` 방식, `panePid` 주입)**
  - **차단 회귀:** `plan-1.started`와 `plan-1.stop.json`(`unconfirmed`)을 둡니다. `tick()` 3회와 `retry`를 호출해도 결과 파일이 생기지 않아야 합니다.
  - **삭제 차단(HIGH-3)**
    - 위 상태에서 `delete`를 호출해도 작업 폴더와 `.stop.json`이 남아야 하고 `lastError`가 설정되어야 합니다.
    - `activeStep`만 있는 상태(`plan-1.started`만 있음)에서도 폴더가 남아야 합니다.
    - 결과가 끝난 카드는 기존처럼 삭제되어야 합니다.
  - **첫 기록 저장 실패(HIGH-2):** 작업 폴더를 읽기 전용으로 만들고 `cancel`합니다.
    - `stopBlocked`가 설정되어야 하고, `tick`/`retry`/`delete`가 막혀야 합니다.
    - 주입한 pid(`sleep 30`)가 정지되지 않은 상태로 남아야 합니다(신호 없음).
  - **마무리 저장 실패(HIGH-2):** `confirmed` stop 파일을 두고, 결과 경로에 같은 이름의 디렉터리를 만들어 저장이 실패하게 합니다. `reload` 후에도 `confirmed` 파일이 남아 차단이 유지되어야 합니다. 디렉터리를 치우고 다시 `reload`하면 결과가 기록되고 stop 파일이 삭제되어야 합니다.
  - **재시작 복원:** `freezing` 파일은 `unconfirmed`로 다시 쓰여야 하고, `confirmed` 파일은 마무리되어야 합니다.
  - **루트 미확보 재시도(MEDIUM)**
    - `panePid`가 처음에는 nil(창은 있음)을 돌려주게 합니다. 이때 `root: nil, unconfirmed`가 기록되어야 합니다.
    - 두 번째 `cancel`에서 `sh -c 'sleep 30'`의 pid를 돌려주게 합니다. 이때 `.stopped`, 실패 결과 기록, stop 파일 삭제가 모두 일어나고 해당 pid가 사라져야 합니다.
  - **activeStep이 없을 때:** `ok:false` 결과와 `unconfirmed` stop 파일(targets는 이미 종료된 pid)을 둡니다. `cancel`하면 `.stopped`가 나오고 stop 파일이 삭제되어야 합니다.
  - **소요 시간:** `.started`/`.result.json`의 수정 시각을 조작해 계산 결과를 확인합니다. `ok:false`는 제외되어야 합니다.
- **수동 확인**
  1. `swift build && swift test`
  2. 카드에 "마지막 기록 · … · 방금"과 "예상 시간 자료 부족 · 단계 안 진척은 알 수 없음"이 보이는지 확인합니다. 두 번째 작업부터는 "보통 N분 (지난 M회)"이 보여야 합니다.
  3. `quietAfter`를 30으로 바꾸고 `kill -STOP <claude pid>`를 보내 경고를 확인합니다. 확인 후 상수는 원래대로 돌립니다.
  4. 실행 중에는 삭제가 비활성화되어야 합니다. "중단"을 누르면 5초 안에 실패가 기록되고, `ps`에 이 작업의 `claude -p|codex exec|myterm-agent`가 없어야 합니다.
  5. 중단 도중(`freezing` 상태)에 앱을 강제 종료하고 다시 켭니다. "다시 중단" 안내가 뜨고 삭제·다시 시도가 비활성화되어야 합니다. 누르면 정리가 끝나야 합니다.
- **참고**
  - 이미 남아 있는 고아 claude 프로세스는 한 번 수동으로 `kill <pid>`해야 합니다.
  - 알려진 한계: 스스로 `setsid`한 프로세스는 잡지 못하고, 강제 종료로 남은 lock 파일(git 등)은 정리하지 않습니다.

## 리뷰 반영
- **[반영] 종료 확인 중 새로 발견한 대상은 신호 전에 저장할 경로가 없음(HIGH)**
  - `adopt`(편입 규칙 → `record` → SIGSTOP)를 `freezeTree`와 `killAndConfirm`이 함께 쓰도록 했습니다.
  - `killAndConfirm`에 `record` 인자를 추가하고, `StopOutcome`이 최종 targets를 돌려주게 했습니다.
  - 테스트 두 개를 추가했습니다. 하나는 "`record` 시점에 아직 정지되지 않았는지"로 기록 순서를 증명하고, 다른 하나는 두 번째 `record`가 실패할 때 신호를 보내지 않는지 확인합니다.
- **[반영] 저장 실패 시 차단 유지와 마무리 재개가 보장되지 않음(HIGH)**
  - 코드 확인: `recordFailure`(887행)는 `Void`이고 오류를 `lastError`로만 남깁니다.
  - 첫 저장 실패에는 메모리 차단 `stopBlocked`를 두었습니다. 기록 전에는 신호를 보내지 않으므로 트리는 손대지 않은 상태이고, 재시작 뒤 차단이 해제되어도 안전합니다.
  - `recordFailure`가 Bool을 반환하게 하고, `true`일 때만 stop 파일을 지우게 했습니다. 두 실패 주입 테스트를 추가했습니다.
- **[반영] 카드 삭제가 중단 복구 기록을 통째로 제거함(HIGH)**
  - 코드 확인: `delete`(287행)는 가드 없이 `killWindow`와 `removeItem`을 실행하고, 삭제 버튼(102·241행)은 항상 활성화되어 있습니다.
  - `delete` 맨 앞에 `isStopHeld` 가드를 두고 UI를 비활성화했습니다.
  - 리뷰 범위보다 한 걸음 더 나가 **실행 중(`activeStep != nil`) 삭제도 막았습니다.** `delete`의 `killWindow`도 같은 SIGHUP 경로라서 이슈 본문의 고아 프로세스를 그대로 만들기 때문입니다.
  - 회귀 테스트 3건을 추가했습니다.
- **[반영] 루트 PID를 못 찾은 상태의 "다시 중단" 절차가 정의되지 않음(MEDIUM)**
  - `StopRecord.root`를 옵셔널로 바꿨습니다. `cancel` 2번에서 root가 없으면 첫 중단이든 재중단이든 `panePid`로 다시 식별합니다.
  - "targets도 없고 루트도 없음"은 `.stopped`가 아니라고 규칙으로 고정했습니다. 창도 없을 때만 `checkAlive`와 같은 판정으로 마무리합니다.
  - 테스트 seam으로 381행의 조회를 `panePid` 하나로 뽑아 냈고, "첫 조회 실패 → 두 번째 조회 성공" 테스트를 추가했습니다.