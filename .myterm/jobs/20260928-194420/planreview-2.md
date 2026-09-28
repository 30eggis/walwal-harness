# MyTerminal 진행 표시·중단 처리 2차 설계리뷰

## 요약

자동 중단 철회, 첫 화면의 활동 오인 방지, 마지막 기록과 추정 시간의 구분은 이전 지적을 적절히 반영했습니다. 소유권이 보장되지 않은 프로세스 그룹에 신호를 보내지 않겠다는 판단도 수용합니다. 다만 비동기 중단 중 기존 루프가 실패를 먼저 기록할 수 있고, 종료 확인 실패 시에도 재시도를 허용하는 문제가 남아 재설계가 필요합니다.

## 지적 사항

### [HIGH] 중단 대기 중 기존 루프가 실패 기록과 재시도를 먼저 허용함

- 위치: `cancel`의 비동기 종료 대기와 `stopping` 처리 · [PipelineRunner.swift](/Users/ted/project/myterminal/Sources/MyTerminal/Pipeline/PipelineRunner.swift:463)
- 문제: `stopWindow`가 대기하는 동안에도 1초 주기의 `tick → advance → checkAlive`가 실행됩니다. 창은 이미 닫혔으므로 `checkAlive`가 종료 확인 전에 실패를 기록하고, `refresh`가 `.failed`를 노출합니다. 따라서 “실패 기록이 종료 확인 뒤에 생겨 재시도가 차단된다”는 설명은 현재 코드와 맞지 않습니다. 중단 버튼만 비활성화해도 재시도와 자동 단계 진행은 막히지 않습니다.
- 수정안: `stopping`인 작업은 자동 진행·창 소멸 실패 판정에서 제외하고, 재시도와 실행을 전환하는 진입점에도 가드를 둡니다. 상태 표시에 사용하는 `stopping`은 관측 가능하게 노출합니다. 중단 대기 중 여러 번 `tick`을 실행해도 실패 기록·재시도·다음 단계 실행이 발생하지 않는 검증을 추가합니다.

### [HIGH] 종료 확인 실패를 중단 완료로 처리하는 예외가 남아 있음

- 위치: 검증 규칙의 “pane pid를 못 얻으면 기존대로 기록”, “SIGKILL 뒤에도 남으면 기록은 그대로”
- 문제: 두 예외는 “작성자인 agent가 종료된 뒤에만 실패를 기록한다”는 핵심 보장을 깨뜨립니다. agent가 살아 있다면 결과 파일을 나중에 덮어쓸 수 있고, 하위 도구가 남았다면 재시도와 동시에 같은 파일을 수정할 수 있습니다. `lastError` 알림만으로 이를 막을 수 없습니다. 자손 목록은 pane 루트 자체도 포함하지 않으므로 루트 종료 확인 역시 명시해야 합니다.
- 수정안: 종료 헬퍼가 `종료 확인`, `종료 미확인`을 구분해 반환하도록 합니다. pane 루트와 대상 자손의 종료가 확인되지 않으면 중단 완료로 전환하거나 재시도를 허용하지 않습니다. PID 조회 실패·프로세스 표 조회 실패·신호 전송 실패를 “종료됨”과 구분하고, 이 경우에도 `migrateLegacyPlan`이 기존 결과를 지우고 새 실행을 시작하지 않도록 합니다.

### [HIGH] 한 번 수집한 PID 목록으로 자손 전체의 종료를 보장할 수 없음

- 위치: `stopWindow`의 자손 수집 → 창 닫기 → SIGTERM → SIGKILL 순서 · [ProcessMonitor.swift](/Users/ted/project/myterminal/Sources/MyTerminal/Sessions/ProcessMonitor.swift:149)
- 문제: 프로세스 표를 읽은 뒤 신호를 보내기 전까지 CLI가 새 자식을 만들 수 있습니다. 이후 부모가 종료되면 그 자식은 기존 목록에도 없고 pane의 자손으로도 추적되지 않습니다. 또한 5초 뒤 PID 숫자의 존재만 확인하면 종료된 대상의 PID를 재사용한 다른 프로세스에 SIGKILL을 보낼 수 있습니다. 양수 PID와 앱 PID 제외만으로는 소유권을 보장하지 못합니다.
- 수정안: PID 방식은 유지할 수 있지만, 종료 중 추가 생성되는 자손을 통제·포착하는 절차와 프로세스 식별 검증을 명시해야 합니다. 최초 수집 시 PID와 시작 시각 등 식별 정보를 확보하고 후속 신호 전에 대조합니다. 종료 직전 자식을 생성하는 가짜 CLI와 PID 식별 불일치 사례를 검증에 포함합니다.

### [LOW] 재사용할 프로세스 기능의 실제 소유 타입이 설계와 다름

- 위치: `ProcessMonitor.processTable()` 공개 및 `descendants` 추가안 · [ProcessMonitor.swift](/Users/ted/project/myterminal/Sources/MyTerminal/Sessions/ProcessMonitor.swift:75)
- 문제: 실제 `processTable`, `Entry`, `descendants`, `terminate`는 `ProcessMonitor`가 아닌 `ProcessScanner` actor에 있습니다. 자손 수집도 이미 구현되어 있어 별도 구현은 중복이며, 표 조회를 UI actor로 옮기면 동기 `ps` 실행이 화면을 막을 수 있습니다.
- 수정안: 기존 `ProcessScanner` 내부 기능을 확장하고 종료 결과만 호출자에게 반환합니다. 기존 프로세스 모니터의 종료 호출부도 함께 확인합니다.

## 판정

재설계

## 실행 방식

llm — 작업 담당이 harness를 사용할 수 없으므로 관련 Swift 코드와 종료 경합 검증을 직접 처리합니다.