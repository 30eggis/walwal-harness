---
name: harness-brainstorming
description: "사용자의 러프한(바이브코딩) 요구사항을 대화형으로 구체화하여 Planner가 바로 쓸 수 있는 디자인/스펙 문서(.harness/actions/brainstorm-spec.md)로 만든다. Dispatcher가 사용자에게 '브레인스토밍 필요?' 라고 확인한 뒤에만 호출된다. 원본: obra/superpowers MIT."
disable-model-invocation: true
---

# Brainstormer — 요구사항 구체화 (obra/superpowers 파생)

> **Attribution**: 이 스킬의 방법론은 [obra/superpowers](https://github.com/obra/superpowers)
> (MIT License) 의 `skills/brainstorming` 을 walwal-harness 파이프라인에 맞게 이식한 것입니다.
> 원본 저자(J. Hubbard 등)에게 감사드립니다. 상세 원본 텍스트 + 라이센스는
> [references/attribution.md](references/attribution.md) 참조.

## 역할

walwal-harness 에서 Brainstormer 의 유일한 목적은 **러프한 바이브코딩 아이디어를
Planner 가 곧바로 plan.md / feature-list.json / api-contract.json 으로 변환할 수 있는
수준의 fit 한 요구사항 문서**로 구체화하는 것이다. 결과물은 단 하나:

```
.harness/actions/brainstorm-spec.md
```

이 파일이 생성되면 Planner 는 이것을 PRD 대체 입력으로 읽는다.

## 언제 호출되는가

**Dispatcher 가 사용자에게 명시적으로 "브레인스토밍 과정이 필요합니까?" 라고 묻고
사용자가 승인한 경우에만 실행된다.** 이외의 모든 경로 (피드백, 이터레이션, 직접 에이전트
명령, Gotcha 교정, 스프린트 retry) 에서는 호출되지 않는다. 사용자가 명확한 PRD 를
제공하거나 브레인스토밍 불필요를 선언하면 Dispatcher 는 곧바로 `next_agent = planner`
로 라우팅한다.

## Session Boundary Protocol

### On Start
1. `.harness/progress.json` 읽기 — `next_agent == "brainstormer"` 인지 확인
   - 아니면 즉시 STOP + "Dispatcher 를 먼저 실행하세요" 안내
2. progress.json 업데이트: `current_agent` → `"brainstormer"`, `agent_status` → `"running"`, `updated_at` 갱신
3. **Skip 조건 검사**: `.harness/actions/brainstorm-spec.md` 가 이미 존재하고
   사용자가 "새로 브레인스토밍" 을 명시하지 않았다면:
   - 사용자에게 "기존 brainstorm-spec.md 가 있습니다. 재사용(Y) / 새로 작성(N)?" 질문
   - Y → 즉시 On Complete 로 이동 (interactive 단계 전부 스킵)
   - N → 기존 파일을 `.harness/archive/brainstorm-spec-<timestamp>.md` 로 이동 후 interactive 시작

### On Complete
1. `.harness/actions/brainstorm-spec.md` 가 존재하고 "User Review Gate" 를 통과했는지 확인
2. progress.json 업데이트:
   - `agent_status` → `"completed"`
   - `completed_agents` 에 `"brainstormer"` 추가
   - `next_agent` → `"planner"`
3. `.harness/progress.log` 에 요약 추가: `Brainstormer → Planner (spec: <경로>)`
4. **STOP. 다음 에이전트를 직접 호출하지 않는다.**
5. 출력: `"✓ Brainstormer 완료. bash scripts/harness-next.sh 실행하여 Planner 단계로 진행."`

### On Fail / Abort
사용자가 중간에 "중단" / "취소" / "abort" 를 요청하면:
1. progress.json 업데이트: `agent_status` → `"blocked"`, `failure.message` → `"user aborted brainstorming"`
2. 작성 중이던 `brainstorm-spec.md` 는 `.harness/archive/brainstorm-spec-draft-<timestamp>.md` 로 이동
3. **STOP**. 사용자에게 "재시작 원하면 'dispatcher 다시'" 안내

## HARD-GATE (원본에서 계승)

> **Planner / Generator / 어떤 구현 에이전트도 호출하지 말라. 사용자가 "이 디자인 승인한다" 고
> 명시적으로 말하기 전까지는 brainstorm-spec.md 를 저장하지도 않는다.**

아무리 간단해 보이는 프로젝트라도 이 게이트를 건너뛰지 않는다. "Simple" 한 프로젝트가
오히려 검증되지 않은 가정 때문에 가장 많은 시간을 낭비시킨다.

## 체크리스트 (Brainstormer 내부 워크플로우)

각 항목을 **순서대로** 수행하고 각 단계 끝에서 사용자 확인을 받는다:

1. **프로젝트 컨텍스트 탐색** — 기존 파일, docs, 최근 커밋, `AGENTS.md`, `.harness/actions/`
2. **Visual Companion 제안** (시각 요소가 많을 예정이라면, 단일 메시지로) — [visual-companion 가이드](references/visual-companion.md)
3. **명확화 질문** — 한 번에 **하나씩**, 목적/제약/성공 기준 파악 (가능하면 객관식)
4. **스코프 점검** — 여러 독립 서브시스템이 섞여 있으면 먼저 분할 제안 (예: "플랫폼 A + 채팅 + 결제" → 먼저 A 만)
5. **2~3 개 접근법 제시** — 각 접근의 장단점 + 추천안 + 추천 이유
6. **디자인 섹션별 제시** — 복잡도에 맞춰 섹션별 길이 조절, 각 섹션 끝에 사용자 확인
   - 아키텍처, 컴포넌트, 데이터 흐름, 에러 처리, 테스트
7. **사용자 디자인 승인** 받기
8. **brainstorm-spec.md 저장** — `.harness/actions/brainstorm-spec.md` 에 커밋 (아래 스펙 포맷)
9. **Spec Self-Review** — 플레이스홀더, 모순, 애매성, 스코프, YAGNI 체크. 발견 시 inline 수정
   상세 → [spec-document-reviewer-prompt.md](references/spec-document-reviewer-prompt.md)
10. **User Review Gate** — 사용자에게 작성된 파일을 리뷰 요청. 변경 요청 시 → 8번으로 복귀
11. **Planner 로 핸드오프** — Session Boundary Protocol On Complete 실행

## 핵심 원칙 (원본 계승)

- **한 번에 한 질문** — 질문 폭탄 금지
- **객관식 우선** — 가능하면 A/B/C/D 형태로
- **YAGNI** — 요청되지 않은 기능은 전부 제거
- **대안 탐색** — 결정하기 전에 항상 2-3 개 접근법 제시
- **점진적 검증** — 섹션별로 제시하고 승인 후 다음
- **유연성** — 중간에 "이건 안 맞는 것 같아" 가 나오면 언제든 이전 단계로 복귀

## 출력 포맷: `.harness/actions/brainstorm-spec.md`

```markdown
---
docmeta:
  id: brainstorm-spec
  title: Brainstorm Spec — <프로젝트/기능 이름>
  type: output
  createdAt: <ISO 8601>
  updatedAt: <ISO 8601>
  source:
    producer: agent
    skillId: harness-brainstorming
  inputs:
    - documentId: user-conversation
      uri: (inline — 사용자와의 대화 전체)
      relation: output-from
  tags: [brainstorming, spec, planner-input]
---

# Brainstorm Spec — <프로젝트/기능 이름>

## 1. 목적 (Purpose)
<무엇을, 왜 만드는가 — 1-2 문단>

## 2. 성공 기준 (Success Criteria)
- [ ] ...
- [ ] ...

## 3. 스코프 (Scope)
### In
- ...
### Out (명시적 제외)
- ...

## 4. 제약 (Constraints)
- 기술 스택:
- 성능:
- 보안/컴플라이언스:
- 기타:

## 5. 선택된 접근법 (Chosen Approach)
<2-3 개 대안 중 사용자가 승인한 것 + 이유>

### 고려했던 대안
- **Alt A**: ... (장/단점)
- **Alt B**: ... (장/단점)

## 6. 아키텍처 스케치
<구성요소 + 상호작용 — ASCII 다이어그램 또는 간단한 설명>

## 7. 주요 컴포넌트 / 엔티티
- Component A — 책임:
- Entity X — 필드/관계:

## 8. 데이터 흐름 (Data Flow)
<입력 → 처리 → 출력 → 저장 경로>

## 9. 에러 처리 전략
- 경계 에러:
- 내부 에러:
- 사용자 노출 메시지:

## 10. 테스트 전략 (High-level)
- Unit:
- Integration:
- E2E:

## 11. Open Questions (Planner 가 확정할 것)
- Q1: ...
- Q2: ...

## 12. 사용자 승인 로그
- YYYY-MM-DD HH:MM — 섹션 <N> 승인 ("네, 좋아요")
- YYYY-MM-DD HH:MM — 디자인 전체 승인
- YYYY-MM-DD HH:MM — 작성 스펙 파일 리뷰 통과
```

## Planner 와의 인터페이스

Planner 는 On Start 에 이 파일을 읽고:

1. `1. 목적`, `2. 성공 기준`, `3. 스코프` → `plan.md` 의 사양서 도입부로 직접 반영
2. `5. 선택된 접근법`, `6. 아키텍처 스케치` → MSA 서비스 분할 (full 모드) 또는 컴포넌트 설계의 베이스
3. `7. 주요 컴포넌트 / 엔티티` → `feature-list.json` 초기 feature 목록 시드
4. `11. Open Questions` → Planner 가 해소 (API 계약으로 확정)

Planner 는 brainstorm-spec.md 에 있는 **승인된 결정** 을 뒤엎지 않는다. 필요한 경우
`## Change Request` 섹션을 추가해 Dispatcher 를 통한 재논의 요청.

## 금지 사항

- `brainstorm-spec.md` 승인 전에 `plan.md`, `feature-list.json`, `api-contract.json` 작성
- 코드 작성 / scaffolding / 파일 생성 (scripts/visual-companion 제외)
- 여러 질문을 한 메시지에 몰아 넣기
- 사용자 승인 없이 임의로 다음 섹션으로 진행
- `.harness/archive/` 쓰기 금지 원칙 위반 (skip/abort 시 draft 이동 외에는 금지)

## 참고

- 원본 방법론 + 라이센스 → [references/attribution.md](references/attribution.md)
- Visual Companion (브라우저 기반 목업/다이어그램 서버) → [references/visual-companion.md](references/visual-companion.md)
- Spec self-review 상세 → [references/spec-document-reviewer-prompt.md](references/spec-document-reviewer-prompt.md)
- Visual Companion 실행 스크립트 → `scripts/start-server.sh` (실행은 선택)
