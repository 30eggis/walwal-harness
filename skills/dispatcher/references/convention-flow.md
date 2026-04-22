---
docmeta:
  id: convention-flow
  title: Convention Flow — Positive Guide Classifier
  type: output
  createdAt: 2026-04-22T00:00:00Z
  updatedAt: 2026-04-22T00:00:00Z
  source:
    producer: agent
    skillId: harness-dispatcher
  inputs:
    - documentId: harness-dispatcher-skill
      uri: ../SKILL.md
      relation: output-from
      sections:
        - sourceRange:
            startLine: 45
            endLine: 100
          targetRange:
            startLine: 30
            endLine: 140
  tags:
    - dispatcher
    - convention
    - positive-guidance
---

# Convention Flow — Positive Guide Classifier

긍정 가이드("~해야 해", "항상 ~", "이렇게 해줘")를 감지하면
해당 스코프의 `.harness/conventions/<scope>.md` 에 `[C-NNN]` 엔트리로 append.

## 1. 긍정 시그널 감지

다음 패턴 중 하나라도 포함되면 Convention 후보:

- 명령형: "해야 해", "~로 해줘", "이렇게 만들어", "~를 사용해"
- 원칙 선언: "항상 ~", "모든 ~ 는", "우리는 ~ 방식", "표준은 ~"
- 하우스 스타일: "이 프로젝트에서는 ~", "컨벤션상 ~", "규칙은 ~"
- 영어: "always", "must", "should", "we use", "prefer", "standard is"

**부정 시그널과 충돌 시 부정 우선** (Gotcha 로 라우팅). 예: "~ 하지 말고 ~ 해줘" 는 Gotcha.

## 2. Scope 판별

엔트리의 적용 범위를 다음 순서로 판별:

1. **특정 에이전트 명시** → 해당 에이전트 파일
   - 사용자가 명시적으로 이름 언급 ("Generator-BE 는 ~") 또는 문맥상 확실한 키워드
2. **도메인 키워드 매칭** → 대응 에이전트
   | 키워드 | 스코프 |
   |--------|-------|
   | backend, API, controller, service, DTO, NestJS, MSA | `generator-backend` |
   | frontend, React, Next.js, UI, component, hook, Tailwind | `generator-frontend` |
   | plan, sprint, feature-list, api-contract, roadmap | `planner` |
   | Playwright, E2E, browser, functional test | `evaluator-functional` |
   | layout, screenshot, a11y, responsive, viewport, AI slop | `evaluator-visual` |
   | code quality, lint, tsc, architecture, type safety | `evaluator-code-quality` |
3. **매칭 실패 + 여전히 에이전트 국한** → `shared.md`
4. **프로젝트 전체 철학/원칙** (예: "우리는 TDD 한다", "보안 우선") → 루트 `CONVENTIONS.md` 에 사용자 권고 (Dispatcher 직접 수정 금지)

## 3. 중복 감지

대상 파일에서 기존 `[C-NNN]` 엔트리를 읽어:
- **완전 중복** (같은 rule) → append 하지 않고 기존 엔트리의 Date 를 갱신
- **부분 중복** (관련 주제) → 새 엔트리로 추가하되 기존 엔트리 ID 를 `Related:` 필드로 참조

## 4. 엔트리 포맷

```markdown
### [C-NNN] 간결한 제목 (긍정형, 70자 이내)
- **Date**: YYYY-MM-DD
- **Scope**: <agent> | shared
- **Rule**: 사용자가 말한 내용을 긍정 규칙으로 정제. 명령형 문장.
- **Rationale**: 사용자가 설명한 이유 (없으면 "미지정" 표기, 추정 금지)
- **Applies to**: 적용 대상 상세 (특정 파일 경로, 특정 상황, 엔드포인트 등)
- **Added from**: 사용자 프롬프트 (YYYY-MM-DD HH:MM) | migration | manual
- **Related**: C-XXX, C-YYY (선택)
```

### ID 할당

대상 파일의 기존 `[C-NNN]` 최댓값 + 1 을 3자리 zero-pad. 예: 기존에 C-001, C-003 이 있으면 다음은 C-004 (비어있는 번호는 재사용하지 않음).

## 5. 루트 CONVENTIONS.md 처리

루트 `CONVENTIONS.md` 는 **사용자가 자유 기술하는 최상위 원칙 파일**. Dispatcher 가 직접 수정하지 않고, 사용자에게 안내:

```
이 규칙은 프로젝트 전체 철학에 가까워 보여서 CONVENTIONS.md(루트) 에
직접 추가하시는 게 좋겠습니다. 추가 후 모든 에이전트가 세션 시작 시 읽습니다.
```

## 6. 사용자 확인 메시지 포맷

```
Convention 등록 완료:
- ID: [C-004]
- Scope: generator-backend
- Rule: API 응답 필드는 snake_case
- 저장 위치: .harness/conventions/generator-backend.md

Generator-Backend 는 다음 세션 시작 시 이 규칙을 읽고 적용합니다.
```

## 7. 금지 사항

- Convention 파일의 기존 엔트리 삭제/수정 (사용자만 가능)
- `CONVENTIONS.md` (루트) 직접 수정
- 추정성 rationale 작성 (근거 없으면 "미지정")
- 에이전트 SKILL.md 자체 수정 (구조적 변경은 사용자 권고)
