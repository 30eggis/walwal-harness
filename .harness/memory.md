---
docmeta:
  id: harness-memory
  title: Harness Memory — 공유 학습 기록
  type: output
  createdAt: 2026-04-09T00:00:00Z
  updatedAt: 2026-05-07T00:00:00Z
  source:
    producer: agent
    skillId: harness-dispatcher
  inputs:
    - documentId: user-feedback-cumulative
      uri: (inline — 누적 사용자 교정/피드백 대화)
      relation: output-from
      note: inline 입력. 각 [M-NNN] 항목이 별개 피드백 사건이며 sourceRange 는 placeholder.
      sections:
        - sourceRange: { startLine: 1, endLine: 1 }   # M-001 Flutter 유령 스킬 피드백
          targetRange: { startLine: 44, endLine: 51 }
        - sourceRange: { startLine: 1, endLine: 1 }   # M-002 시각 톤 레퍼런스 피드백 (Phase C Sprint 1)
          targetRange: { startLine: 53, endLine: 65 }
  tags: [memory, harness-shared, lessons, gotcha-meta]
---

# Harness Memory — 공유 학습 기록

> Dispatcher가 관리. **모든 에이전트**는 세션 시작 시 이 파일을 읽고 학습된 규칙을 따릅니다.
> gotchas(에이전트별 실수 기록)와 달리, 이 파일은 **프로젝트 전체에 적용되는 구조적 교훈**을 담습니다.

## 항목 형식

```markdown
### [M-NNN] 간결한 제목
- **Date**: YYYY-MM-DD
- **Status**: unverified | verified
- **TTL**: YYYY-MM-DD (기본 +60일. 만료 후 Planner가 리뷰)
- **Lesson**: 교훈 내용
- **Context**: 발견 배경
- **Applies to**: 적용 대상 에이전트/상황
```

## 오염 방어 규칙

- 새 항목은 반드시 `unverified` 상태로 시작
- Planner가 스프린트 리뷰 시 유효성 확인 후 `verified` 승격
- TTL 만료 항목은 Planner가 리뷰: 갱신 또는 삭제
- 환각(hallucination) 의심 항목: 코드/git 이력으로 검증 불가하면 즉시 삭제
- 항목이 15개 초과 시 가장 오래된 unverified 항목부터 정리

<!-- 항목이 추가되면 아래에 기록됩니다 -->

---

### [M-001] Flutter 변형 에이전트는 "선언만 된 유령 스킬"이다 [RESOLVED]
- **Date**: 2026-04-17
- **Status**: verified
- **TTL**: 2026-06-16
- **Resolution (2026-04-17)**: META_REFACTOR 스프린트 완료로 해결. `config.json` 에서 `agents["generator-frontend-flutter"]`, `agents["evaluator-functional-flutter"]`, `flow.pipeline_selection.fe_stack_substitution` 모두 제거. `skills/dispatcher/SKILL.md` §5/§7 의 Flutter 치환 참조 제거. 적응형 아키텍처로 전환되어 더 이상 스택별 에이전트 분기는 사용하지 않는다 — 단일 에이전트가 `.harness/ref/<role>-<stack>.md` 를 동적 로드. 설계 교훈(설정만 추가하고 구현은 나중에 금지) 은 verified 로 승격해 보존.
- **Lesson**: `.harness/config.json` agents 섹션과 `skills/dispatcher/SKILL.md` §5·§7 에 `generator-frontend-flutter`, `evaluator-functional-flutter` 가 정의·참조되어 있으나, 실제 `skills/generator-frontend-flutter/SKILL.md`, `skills/evaluator-functional-flutter/SKILL.md` 파일은 **존재하지 않는다** (`~/.claude/skills/` 에도 없음). 문서·설정과 구현체가 불일치한 상태. fe_stack 치환 로직이 호출되는 순간 파일 없음 에러가 발생할 것.
- **Context**: 2026-04-17 사용자가 walwal-harness 를 "적응형"으로 리팩토링하는 논의 중 직접 지적. `ls skills/` 로 확인: brainstorming, dispatcher, evaluator-functional, evaluator-visual, generator-backend, generator-frontend, planner 7개만 존재.
- **Applies to**: 모든 에이전트. 특히 적응형 리팩토링 설계 시 — **config 에 에이전트를 선언할 때 반드시 SKILL.md 파일을 같이 생성**할 것. "설정만 추가하고 구현은 나중에" 패턴 금지. 이번 적응형 작업에서 Flutter 스킬도 같이 실제로 만들거나, config/dispatcher 에서 참조를 제거해야 한다.

### [M-002] Visual feature 진입 전 시각 톤 레퍼런스 사전 확인 필수
- **Date**: 2026-05-07
- **Status**: unverified
- **TTL**: 2026-07-06
- **Lesson**: 메타포가 강한 visual feature(대시보드·게임화·캐릭터·사옥/공간 메타포)에 진입하기 전, **사용자에게 시각 톤 레퍼런스 이미지/예시를 확보**해야 한다. "isometric", "3D", "carded", "minimal" 같은 한 단어 키워드는 표현 폭이 너무 넓다 (isometric 만 해도 voxel 3D / 비즈니스 다이어그램 / 추상 SVG / 사진풍 게임이 모두 포함). 디폴트로 가장 단순한 추상 도형을 고르면 정서적 의도와 어긋날 확률이 매우 높다.
- **Context**: Phase C Sprint 1 — Brick Office 대시보드를 단순 SVG 폴리곤으로 구현했더니 사용자가 Roblox/메타버스 풍 voxel 3D 레퍼런스를 첨부하며 교체 요청. brainstorm-spec.md 의 "SVG 2.5D isometric" 문구를 글자 그대로 해석한 결과. Brainstormer 단계의 Visual Companion 에서 추상 ASCII mockup 만 비교했고 voxel/3D vs 추상 SVG 같은 톤 차원은 옵션화되지 않았다.
- **Applies to**:
  - **Brainstormer**: visual feature 의 layout 옵션을 띄울 때 **시각 톤** (voxel 3D / 추상 다이어그램 / 사실적 일러스트 등) 도 별도 옵션 단계로 분리해 좁힌다.
  - **Generator-Frontend**: feature 작업 직전, 시각 톤이 spec 에 1차원으로만 적혀 있다면 사용자에게 레퍼런스 이미지를 묻거나 후보 mockup 2~3 종을 띄워 1 라운드 좁힌다. 코드 진입 후 교체는 매몰 비용이 크다.
  - **Planner**: visual 비중이 큰 sprint 의 plan §2 성공기준에 "시각 톤 레퍼런스 사용자 승인 완료" 를 별도 체크박스로 둔다.
- **How to apply**: spec/brainstorm 단계에서 "isometric" 같은 키워드가 등장하면 곧바로 (a) 후보 톤 2~3 (voxel 3D / 추상 SVG / 일러스트) 을 사용자에게 보여주거나 (b) 사용자에게 레퍼런스 URL/이미지를 요청. spec 의 "선택된 접근법" 섹션에 톤 결정 줄을 명시.
