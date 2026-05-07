---
docmeta:
  id: generator-frontend
  title: Gotchas — Generator-Frontend
  type: intermediate
  createdAt: 2026-05-07T00:00:00Z
  updatedAt: 2026-05-07T00:00:00Z
  source:
    producer: agent
    skillId: harness-dispatcher
  inputs: []
  tags: [gotcha, generator-frontend, sub-skill, agency-agents]
---

# Gotchas — Generator-Frontend

> Dispatcher가 관리. Generator-Frontend는 세션 시작 시 이 파일을 읽고 같은 실수를 반복하지 않습니다.

## [G-001] CTO-Frontend 단독 작업 금지 — 흡수된 agency-agents sub-skill 명시 호출 (status: verified)

- **Why**: walwal-harness v6 는 agency-agents (MIT) 의 design/UX/A11y/perf 패턴을 부서별로 흡수했지만, generator-frontend SKILL 에는 sub-skill 호출 의무가 누락되어 CTO-Frontend 가 단독으로 컴포넌트를 찍어내고 끝나는 회귀가 있었다 (moon_web 2026-05-07).
- **How to apply**:
  - **Sprint Workflow Step 2 (구현)** 진입 시, 다음 sub-skill 결과를 **순차 호출 후 본 구현에 반영**한다 — 결과 미반영은 PASS 금지:
    1. **engineering-react-developer** (또는 -flutter-developer) — 컴포넌트 골격 패턴 결정
    2. **design/ux-strategy** (CTO-Designer 흡수) — 사용자 흐름 / 정보 구조 검증
    3. **design/ui-component-spec** — 토큰 / variant / state 매핑
    4. **engineering-accessibility-reviewer** — WCAG AA + 키보드 네비
    5. **engineering-performance-engineer** — RSC 우선 / hydration 비용 / IntersectionObserver
  - 호출 결과는 sprint-contract.md FE 섹션의 `## Sub-skill Findings` 블록에 요약 반영. 빈 블록 = FAIL.
  - tmux/3D 대시보드에 visibility 보장: 각 sub-skill 호출 직전 `progress.json.meetings.active = ["generator-frontend", "<sub-skill>"]` partial update 후 1.5s, 호출 후 `[]` 로 복귀.
- **References**: skills/cto/SKILL.md "agency-agents (MIT) 흡수" 섹션, skills/generator-designer/SKILL.md.
