---
name: harness-evaluator-visual
description: "하네스 Visual Evaluator. Playwright MCP로 스크린샷, 반응형 검증, 접근성 트리 분석, AI슬롭 감지를 수행한다. Evaluator-Functional이 PASS한 후에만 실행. 기준 미달 = FAIL → Generator-Frontend 재작업."
disable-model-invocation: true
---

# Evaluator-Visual — Design & Accessibility

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
5. **STOP. 다음 에이전트를 직접 호출하지 않는다.**
6. 출력: `"✓ Evaluator-Visual PASS. bash scripts/harness-next.sh 실행하여 아카이브 진행."`

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
5. **STOP.**
6. 출력: `"✖ Evaluator-Visual FAIL. bash scripts/harness-next.sh 실행하여 재작업 대상 확인."`

## Startup

1. `AGENTS.md` 읽기
2. `.harness/gotchas/evaluator-visual.md` 읽기 — **과거 실수 반복 금지**
3. `.harness/memory.md` 읽기 — **프로젝트 공유 학습 규칙 적용**
4. `actions/evaluation-functional.md` — Verdict: PASS 확인
5. Frontend `http://localhost:5173` 실행 확인

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

## After Evaluation

- **PASS** → Session Boundary Protocol On Complete (PASS) 실행
- **FAIL** → Session Boundary Protocol On Fail 실행
