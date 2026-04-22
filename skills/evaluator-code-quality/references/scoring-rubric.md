---
docmeta:
  id: scoring-rubric
  title: Code-Quality Scoring Rubric
  type: output
  createdAt: 2026-04-22T00:00:00Z
  updatedAt: 2026-04-22T00:00:00Z
  source:
    producer: agent
    skillId: harness-evaluator-code-quality
  inputs:
    - documentId: harness-evaluator-code-quality-skill
      uri: ../SKILL.md
      relation: output-from
      sections:
        - sourceRange:
            startLine: 76
            endLine: 84
          targetRange:
            startLine: 20
            endLine: 85
  tags:
    - evaluator
    - code-quality
    - rubric
---

# Code-Quality Scoring Rubric (C1-C5)

Score 척도: 0 (Evidence 없음 / Critical 위반) · 1 (Major 위반) · 2 (Minor 위반) · 3 (위반 없음 + 긍정 evidence)

## C1. Layer & Boundary (25%)

**본다:**
- AGENTS.md IA-MAP 을 위반하는 import (예: FE에서 BE internal 참조)
- MSA 서비스 간 직접 DB 접근 (메시지 패턴이 원칙)
- Backend: controller → service → repo 단방향. 역방향/건너뜀 금지.
- Frontend: view 가 fetch/store 를 직접 조작하지 않고 VM/hook 경유
- libs/shared-dto 가 apps/ 를 역참조하지 않음

**0점 조건:** 레이어 역방향 의존 1건 이상, 또는 MSA 경계 위반.

## C2. Readability & Complexity (15%)

**본다:**
- 함수/메서드 50줄 초과, 중첩 4단 초과
- 매직 넘버/문자열 (상수화 없음)
- 네이밍: 역할을 말하지 않는 이름 (`data`, `tmp`, `handle`)
- 주석이 what을 설명 (코드로 말해야 함) / 왜를 빠뜨림
- dead code, 주석 처리된 블록

**0점 조건:** 300줄 이상 단일 함수, 또는 다수의 dead code 블록 방치.

## C3. Reuse & DRY (20%)

**본다:**
- 이미 존재하는 util/hook/service 를 무시하고 재구현
- 3회 이상 반복되는 동일 로직
- 조기 추상화 (단 1회 사용하는 generic factory 등) — 반대 방향 위반
- lib/shared-dto 확장 없이 로컬 DTO 중복 선언

**0점 조건:** 기존 util 무시하고 동일 로직 3건+ 재구현.

## C4. Type Safety & Error Handling (25%)

**본다:**
- `any`, `as any`, `@ts-ignore`, `@ts-expect-error` — 각 건 근거 필수
- nullable 무시, non-null 단언(`!`) 남용
- try/catch 가 오류를 삼킴 (`catch {}`, `catch(e) { console.log }`)
- 경계(API/외부 입력)에서 zod/class-validator 등 검증 부재
- 비동기 race / unhandled promise

**0점 조건:** unhandled promise 1건 이상, 또는 비타당한 `any` 3건 이상.

## C5. Test Quality (15%)

**본다:**
- 테스트가 구현 세부(내부 함수 호출 순서)에 결합
- mock 남용 — 실제 계약이 아닌 스텁 세계를 검증
- AC 와 테스트 케이스 매핑 부재
- 행복 경로만, 엣지/에러 케이스 없음
- 커버리지 숫자 채우기용 (`expect(x).toBeDefined()`)

**0점 조건:** 신규 기능에 테스트 0건, 또는 AC와 매핑되는 테스트 0건.

## Weighted Verdict

```
Weighted = C1*0.25 + C2*0.15 + C3*0.20 + C4*0.25 + C5*0.15
PASS  : Weighted >= 2.80 AND 모든 축 Score > 0
FAIL  : Weighted < 2.80 OR any axis = 0 OR toolchain error OR contract divergence
```

## Evidence 형식

모든 Score 주장은 아래 형식의 evidence 를 동반해야 한다:

```
[C4:1] apps/service-user/src/user.service.ts:42
  - `result as any` 로 타입 우회. DTO 정의 존재(libs/shared-dto/user.dto.ts:15)에도
    불구하고 강제 캐스팅. 타당한 사유 없음.
```

Evidence 없는 Score 는 **자동 0점 재계산**.
