---
docmeta:
  id: brainstorming-attribution
  title: Brainstorming Skill — Attribution & Original Source
  type: output
  createdAt: 2026-04-09T00:00:00Z
  updatedAt: 2026-04-09T00:00:00Z
  source:
    producer: agent
    skillId: harness-brainstorming
  inputs:
    - documentId: obra-superpowers-brainstorming-skill
      uri: https://github.com/obra/superpowers/blob/main/skills/brainstorming/SKILL.md
      relation: output-from
      sections:
        - sourceRange:
            startLine: 1
            endLine: 165
          targetRange:
            startLine: 21
            endLine: 32
        - sourceRange:
            startLine: 29
            endLine: 33
          targetRange:
            startLine: 36
            endLine: 42
        - sourceRange:
            startLine: 12
            endLine: 18
          targetRange:
            startLine: 55
            endLine: 62
    - documentId: obra-superpowers-spec-reviewer
      uri: https://github.com/obra/superpowers/blob/main/skills/brainstorming/spec-document-reviewer-prompt.md
      relation: output-from
      sections:
        - sourceRange:
            startLine: 1
            endLine: 50
          targetRange:
            startLine: 23
            endLine: 24
    - documentId: obra-superpowers-visual-companion
      uri: https://github.com/obra/superpowers/blob/main/skills/brainstorming/visual-companion.md
      relation: output-from
      sections:
        - sourceRange:
            startLine: 1
            endLine: 287
          targetRange:
            startLine: 25
            endLine: 27
  tags: [attribution, license, mit, obra-superpowers]
---

# Attribution — obra/superpowers brainstorming skill

walwal-harness 의 `harness-brainstorming` 스킬은 아래 원본을 기반으로
파이프라인 통합(Session Boundary Protocol, Planner 인터페이스, 출력 경로 등)을
추가한 파생 저작물입니다.

## 원본

- **Repo**: [obra/superpowers](https://github.com/obra/superpowers)
- **Path**: `skills/brainstorming/`
- **Files reused**:
  - `SKILL.md` — 방법론 (HARD-GATE, 한 번에 한 질문, 2-3 접근법, spec self-review)
  - `spec-document-reviewer-prompt.md` — spec 리뷰 서브에이전트 프롬프트 템플릿
  - `visual-companion.md` — 브라우저 기반 시각 도우미 가이드
  - `scripts/frame-template.html`, `helper.js`, `server.cjs`, `start-server.sh`, `stop-server.sh` — visual companion 서버 구현
- **License**: MIT License

## 변경점 (walwal-harness 통합)

1. **Session Boundary Protocol 추가** — On Start / On Complete / On Fail 프로토콜로
   harness 다중 에이전트 흐름에 맞춤
2. **Terminal state 변경** — 원본의 "invoke writing-plans skill" → "hand off to
   harness-planner"
3. **출력 경로 변경** — 원본의 `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md`
   → `.harness/actions/brainstorm-spec.md` (Planner 의 입력 위치)
4. **출력 포맷 변경** — walwal-harness docmeta 프론트매터 + Planner 가 사용하는
   12 개 섹션 (목적/성공기준/스코프/제약/접근법/아키텍처/컴포넌트/데이터흐름/
   에러처리/테스트전략/Open Questions/승인로그) 로 구조화
5. **조건부 호출** — 원본은 "모든 창작 작업 전 필수" 였으나, harness 에서는 Dispatcher 가
   사용자에게 "브레인스토밍 필요?" 확인 후에만 호출 (피드백/이터레이션 케이스에서
   피로 최소화)
6. **Skip 로직** — 기존 brainstorm-spec.md 존재 시 재사용 여부 확인

## 보존된 핵심

- HARD-GATE (구현 전 디자인 필수)
- "Too simple to need a design" 안티패턴 경고
- 한 번에 한 질문 원칙
- 객관식 우선
- 2-3 개 접근법 탐색
- YAGNI
- Spec self-review loop
- User review gate
- Visual Companion 옵션

## MIT License

원본 저장소 [obra/superpowers](https://github.com/obra/superpowers) 의 MIT License
전문은 아래 링크에서 확인할 수 있습니다:
https://github.com/obra/superpowers/blob/main/LICENSE

MIT License 하에 원본 저작권 표시 및 라이센스 고지 의무를 이 파일로 대체합니다.
파생물 배포 시에도 이 attribution 파일을 유지해야 합니다.
