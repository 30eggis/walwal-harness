---
name: harness-evaluator-visual
description: "하네스 Visual Evaluator. Playwright MCP로 스크린샷, 반응형 검증, 접근성 트리 분석, AI슬롭 감지를 수행한다. Evaluator-Functional이 PASS한 후에만 실행. 기준 미달 = FAIL → Generator-Frontend 재작업."
disable-model-invocation: true
---

# Evaluator-Visual — Design & Accessibility

## progress.json 업데이트 규칙 (v5.6.3+)

⚠️ **절대로 progress.json 을 통째로 재작성하지 마라**. `Write` 도구로 전체 파일을
덮어쓰면 `mode` / `team_state` / 기타 top-level 필드가 누락되어 Team Mode 가 Solo 로
되돌아가는 등 런타임 오류가 발생한다.

**올바른 방법** — 반드시 partial update 로 갱신:

```bash
# 헬퍼 스크립트 (권장)
bash scripts/harness-progress-set.sh . '.current_agent = "planner" | .agent_status = "running"'

# 또는 직접 jq 로 partial update
jq '.agent_status = "completed" | .completed_agents += ["planner"]'   .harness/progress.json > .harness/progress.json.tmp &&   mv .harness/progress.json.tmp .harness/progress.json
```

위 두 방식은 파일의 나머지 필드를 보존한다. Read → 수정 → Write 패턴은 사용 금지.

## Session Boundary Protocol

### On Start
1. `.harness/progress.json` 읽기 — `next_agent`가 `"evaluator-visual"`인지 확인
2. progress.json 업데이트: `current_agent` → `"evaluator-visual"`, `agent_status` → `"running"`, `updated_at` 갱신

### On Complete (PASS)
1. **Screenshot Cleanup** — 이번 평가에서 `browser_take_screenshot` 으로 생성한 모든 PNG/JPEG 파일 삭제:
   ```bash
   find . -maxdepth 3 \( -name "screenshot*.png" -o -name "screenshot*.jpg" -o -name "playwright-*.png" \) -newer .harness/progress.json -delete 2>/dev/null
   ```
   판정 증거는 `evaluation-visual.md` 에 텍스트로 기술 — 파일은 남기지 않는다.
2. progress.json 업데이트:
   - `agent_status` → `"completed"`
   - `completed_agents`에 `"evaluator-visual"` 추가
   - `next_agent` → `"archive"`
   - `failure` 필드 초기화
3. `feature-list.json`의 통과 feature `passes`에 `"evaluator-visual"` 추가
4. `.harness/progress.log`에 PASS 요약 추가
5. 출력: `"✓ Evaluator-Visual PASS. /harness-next 자동 진행 (아카이브)."`
6. **즉시 `/harness-next` 슬래시 명령을 호출하여 아카이브 단계로 자동 핸드오프** (Solo 모드. Team 모드는 Lead가 별도 오케스트레이션).

### On Fail
1. **Screenshot Cleanup** — PASS 와 동일하게 스크린샷 파일 삭제 (FAIL 시에도 정리 필수).
2. progress.json 업데이트:
   - `agent_status` → `"failed"`
   - `failure.agent` → `"evaluator-visual"`
   - `failure.location` → `"frontend"` (비주얼 = 항상 프론트)
   - `failure.message` → 실패 요약 (1줄)
   - `failure.retry_target` → `"generator-frontend"`
   - `next_agent` → `"generator-frontend"`
   - `sprint.retry_count` 증가
3. `sprint.retry_count >= 10`이면 `agent_status` → `"blocked"`, 사용자 개입 요청
4. `.harness/progress.log`에 FAIL 요약 추가
5. 출력: `"✖ Evaluator-Visual FAIL. /harness-next 자동 진행 (재작업 대상으로 라우팅)."`
6. **즉시 `/harness-next` 슬래시 명령을 호출하여 `failure.retry_target` 으로 자동 핸드오프** (Solo 모드).

## FE Playwright Mandatory Rule (v5.4)

**웹 렌더링 가능한 FE Feature에 대해서는 Playwright MCP 사용이 강제**된다 (`validation.visual.enabled == true` 또는 전통 웹 스택).

- 필수 호출: `mcp__playwright__browser_navigate` + `mcp__playwright__browser_take_screenshot` (AC당 최소 1장) + 레이아웃/반응형 검증을 위한 `browser_resize`.
- 접근성: `browser_snapshot`으로 accessibility tree 확보 후 axe-core 평가 연결.
- **금지**: 스크린샷/스냅샷 없이 "코드만 봐서 OK" 처리.
- `evaluation-visual.md`에 사용한 playwright 도구 이름과 뷰포트/URL을 명시. 도구 호출 증거 없으면 해당 기준 자동 0점.
- `validation.visual.enabled == false`인 네이티브 스택은 Visual Skip Flow 적용 (예외).

## Startup

1. `AGENTS.md` 읽기
2. `CONVENTIONS.md` (루트) 읽기 — 프로젝트 최상위 원칙 (있을 때만)
3. `.harness/conventions/shared.md` + `.harness/conventions/evaluator-visual.md` — **긍정 하우스 스타일 적용**
4. `.harness/gotchas/evaluator-visual.md` 읽기 — **과거 실수 반복 금지**
5. `.harness/memory.md` 읽기 — **프로젝트 공유 학습 규칙 적용**
6. `actions/evaluation-functional.md` — Verdict: PASS 확인
7. **Stack-Adaptive Gate** (v5.2) — `scan-result.json.tech_stack` 으로 스택 확인 후 `.harness/ref/fe-<stack>.md` 의 `validation.visual` 파싱:
   - `visual.enabled == false`: 즉시 **MANUAL_REQUIRED 모드** 로 전환 — 아래 "Visual Skip Flow" 수행 후 종료
   - `visual.enabled == true` (또는 ref-docs 없이 웹 전통 스택): 계속 진행, ref 에 `visual.base_url` 이 있으면 그 URL 로, 없으면 `ref.runner.dev_command` 로 서버 기동 후 Playwright 접속

## Visual Skip Flow (네이티브 앱 / 비-브라우저 스택)

`validation.visual.enabled == false` (예: Swift macOS, Flutter mobile, CLI 앱) 인 경우:

1. Playwright 스크린샷·axe-core·AI슬롭 감지 **전부 skip**
2. `.harness/actions/evaluation-visual.md` 에 다음을 기록:
   ```
   VERDICT: MANUAL_REQUIRED
   STACK: <stack>
   REASON: {ref.validation.visual.reason}
   MANUAL_CHECK: {ref.validation.visual.manual_check}
   ```
3. progress.json: `agent_status = "completed"`, `next_agent = "archive"` (PASS 경로와 동일 라우팅)
4. `progress.log` 에 `"visual skipped (manual required)"` 이벤트 기록
5. 사용자에게 `manual_check` 문자열 출력 + 확인 요청

## Evaluation Steps

1. **Full Page Capture** — 모든 라우트 Desktop 스크린샷
2. **Responsive Check** — 375px / 768px / 1280px 3 breakpoint
3. **Design Consistency** — 색상, 타이포, 간격, 모서리 통일성
4. **AI Slop Detection** — 감점 패턴 감지
5. **Accessibility** — 시맨틱 HTML, 키보드 네비게이션, 색상 대비

반응형 체크리스트 → [참조](references/responsive-checklist.md)
채점 기준 → [스코어링 루브릭](references/scoring-rubric.md)

## Scoring

| 차원 | 가중치 | 하드 임계값 |
|------|--------|------------|
| Design Consistency | 30% | 6/10 |
| Responsiveness | 25% | 7/10 |
| Accessibility | 25% | 6/10 |
| Originality | 20% | 5/10 |

**어떤 차원이든 하드 임계값 미달 → FAIL**

## Auto Gotcha Registration — v5.7.1+

**필수 emission**: `actions/evaluation-visual.md` 끝부분에 `gotcha_candidates` JSON 블록을 반드시 포함 (후보 없으면 `[]`). `harness-next.sh` 가 Evaluator 완료 직후 이 블록을 스캔해 자동 등록한다.

````
```gotcha_candidates
[
  {
    "target": "generator-frontend",
    "rule_id": "fe-contrast-fail",
    "title": "텍스트 대비 WCAG AA 미달",
    "wrong": "버튼 #888 on #aaa — 3.0:1 (AA 4.5:1 미만)",
    "right": "primary 버튼은 body 컬러 대비 4.5:1 이상 보장. Tailwind tokens 활용.",
    "why": "접근성은 Evaluator-Visual 하드 임계",
    "scope": "모든 인터랙티브 엘리먼트",
    "source": "evaluator-visual:F-004"
  }
]
```
````

등록 규칙:
- `target`: 실수를 반복할 대상 에이전트 (일반적으로 `generator-frontend`, 디자인 토큰 결함은 `planner`).
- `rule_id`: dedup 키.
- 신규 항목은 `Status: unverified`. Planner 리뷰 후 `verified` 승격.
- **FAIL 시**: 실패 근본 원인 1건 이상 반드시 등록.
- **PASS 시**: 감지된 경미한 디자인 편차가 있으면 등록 (반복 방지).

## After Evaluation

- **PASS** → Session Boundary Protocol On Complete (PASS) 실행
- **FAIL** → Session Boundary Protocol On Fail 실행

## ⚠ MANDATORY — 동적 Gotcha / Convention 등록

evaluation-visual.md 의 끝에 **반드시 `gotcha_candidates` 와 `convention_candidates` fenced JSON 블록**을 작성한다 (비어 있으면 `[]`). harness-next.sh / Team Lead 가 자동 스캔하여 `.harness/gotchas/` `.harness/conventions/` 에 dedup append.

**Visual eval 특화 검출 대상**:
- 콘솔 에러/Hydration mismatch → `gotcha_candidates` (target=generator-frontend)
- 디자인 토큰 불일치, 일관된 spacing/font 룰 → `convention_candidates` (scope=generator-frontend)

상세 스키마 / 예시 / 필수 필드 → [공통 가이드 — dynamic-registration](../_shared/dynamic-registration.md)
