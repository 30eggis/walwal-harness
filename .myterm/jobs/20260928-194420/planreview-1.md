# MyTerminal 단계 진행 가시화·자동 중단 설계리뷰

## 요약

진행 상태와 마지막 활동 시각을 보여 주는 방향은 타당하지만, 현재 설계 그대로 자동 중단까지 구현하기에는 위험합니다. 실제 코드에는 활동 확인 순서와 결과 저장 경합 문제가 있으며, 제안한 시그널 전달만으로는 프로세스 종료를 보장하지 못합니다. 또한 과거 소요 시간 비교만으로는 사용자가 요청한 현재 작업 내용과 단계 내부 진척을 충분히 설명하지 못합니다.

## 지적 사항

### [HIGH] 출력이 없다는 이유만으로 정상 작업을 자동 중단할 수 있음

- 위치: 설계의 “활동의 기준”, “자동 중단 기준 20분” · [Trace.swift](/Users/ted/project/myterminal/Sources/MyTermAgent/Trace.swift:74), [main.swift](/Users/ted/project/myterminal/Sources/MyTermAgent/main.swift:554)
- 문제: trace는 모든 실행 활동을 기록하지 않고, 화면도 수신한 이벤트를 처리해야 바뀝니다. 긴 도구 실행·응답 대기·추론 중에는 두 신호가 모두 조용할 수 있습니다. Claude의 Bash 제한을 근거로 Codex와 MCP까지 포함한 모든 단계를 20분 후 종료하는 것은 성립하지 않습니다. CPU 0%와 로그 정지는 멈춤을 의심할 근거이지 확정할 근거가 아닙니다.
- 수정안: 무출력 상태는 우선 “활동 확인 안 됨”으로 표시하고 수동 중단을 제공합니다. 자동 중단을 유지하려면 실행 중인 도구와 대기 상태를 구분하고, 해당 실행에 적용되는 명시적 제한 시간을 정의해야 합니다. 정상적인 장시간 무출력 실행이 중단되지 않는 검증을 추가합니다.

### [HIGH] 최신 활동을 읽기 전에 중단 판정이 실행됨

- 위치: `updateLive`·`checkAlive` 변경안 · [PipelineRunner.swift](/Users/ted/project/myterminal/Sources/MyTerminal/Pipeline/PipelineRunner.swift:463)
- 문제: 현재 `tick()`은 `advance → checkAlive → refresh`를 수행한 뒤 `updateLive`를 호출합니다. 제안대로 `checkAlive`가 `Live.lastActivity`를 사용하면 직전 관측값으로 종료를 결정하므로, 제한 시간 직전에 새 출력이 생겨도 종료할 수 있습니다. 앱 재시작 후 첫 화면을 기존 값과 다르다고 간주해 `now`로 갱신하면 오래된 출력도 방금 발생한 활동으로 표시됩니다.
- 수정안: 같은 실행의 최신 trace·화면을 관측한 뒤 중단을 판정합니다. 첫 화면은 비교 기준으로만 저장하고 새 활동으로 간주하지 않습니다. 상태는 단계·회차·재시도별로 초기화하며, 제한 직전 활동 발생과 앱 재시작을 검증합니다.

### [HIGH] 기존 결과 파일 가드는 성공 우선 처리를 보장하지 않음

- 위치: “결과 파일이 없을 때만 자동 중단”, `recordFailure` 후 `killWindow` · [PipelineRunner.swift](/Users/ted/project/myterminal/Sources/MyTerminal/Pipeline/PipelineRunner.swift:844), [main.swift](/Users/ted/project/myterminal/Sources/MyTermAgent/main.swift:345)
- 문제: `recordFailure`의 파일 존재 검사와 저장은 하나의 원자적 작업이 아닙니다. 검사 직후 agent가 성공을 저장하면 앱이 실패로 덮어쓸 수 있고, 반대로 agent의 `writeResult`가 앱의 실패를 덮어쓸 수도 있습니다. `recordFailure`가 기존 결과 때문에 반환해도 이후 `killWindow` 호출은 막지 못합니다. 파일의 원자적 교체는 두 작성자 간 경합을 해결하지 않습니다.
- 수정안: 완료와 중단의 우선순위를 공통 종료 절차로 정의합니다. 예를 들어 종료 요청 후 agent 종료를 확인하고 결과를 다시 읽은 다음, 결과가 없을 때만 실패를 기록합니다. 종료 확인 전에는 재시도를 허용하지 않고, 성공 저장과 중단이 동시에 발생하는 검증을 추가합니다.

### [HIGH] 단일 PID에 SIGTERM을 보내고 즉시 종료하면 고아 프로세스가 남을 수 있음

- 위치: `childPID`와 시그널 핸들러 변경안 · [main.swift](/Users/ted/project/myterminal/Sources/MyTermAgent/main.swift:283)
- 문제: 제안은 직접 자식 하나에 SIGTERM을 보낸 뒤 부모를 즉시 종료합니다. 자식이 신호를 무시하거나 종료가 지연되면 그대로 남고, CLI가 실행한 하위 도구도 종료 대상에서 빠집니다. 설계의 `SIGSTOP` 재현에서도 SIGTERM 전송만으로 즉시 종료를 보장하지 못합니다. 정상 종료 후 PID 초기화가 없으면 Enter 대기 중에도 과거 PID를 대상으로 신호를 보냅니다.
- 수정안: 소유권이 확인된 실행 프로세스 그룹을 대상으로 정상 종료 요청, 제한 시간 대기, 필요 시 강제 종료, 종료 확인 순서를 둡니다. 정상 실행과 셸 fallback 모두 PID 등록·해제를 처리하고, 시그널 핸들러는 종료 요청 전달에 필요한 최소 작업만 수행합니다. 가짜 CLI로 SIGTERM 무시·SIGSTOP·하위 프로세스 생성 사례를 검증합니다.

### [MEDIUM] 시간 추정이 현재 작업 내용과 실제 진척을 대신하고 있음

- 위치: 요구 분석의 “뭘 하고 있는지”, “어디까지 진행 중인지” · [JobCard.swift](/Users/ted/project/myterminal/Sources/MyTerminal/Home/JobCard.swift:141)
- 문제: 마지막 활동 시각은 로그의 신선도를 알려 주지만 현재 무엇을 처리하는지는 설명하지 않습니다. 과거 실행 시간의 중앙값도 이번 단계에서 완료한 일이나 남은 일을 나타내지 않습니다. 현재 설계는 사용자가 답답해한 기존 마지막 6줄 표시에 시간 정보만 추가하므로, 핵심 요구가 일부 남습니다.
- 수정안: 기존 이벤트에서 확인 가능한 현재 작업과 상태를 함께 표시합니다. 예를 들어 “파일 조회 요청 · 결과 대기”처럼 관측 사실을 보여 주고, 알 수 없는 진척은 “확인 불가”로 표시합니다. 예상 시간은 “이 단계의 과거 실행 기준 추정”임을 명시하고, 표본 부족 시에도 “예상 시간 자료 부족”을 표시합니다.

## 판정

재설계

## 실행 방식

llm — 요청에서 지정한 대로 harness 없이 관련 Swift 파일과 실행 검증을 직접 처리합니다.