---
docmeta:
  id: planner-hr-onboard
  title: Planner HR Module — Onboarding
  type: output
  createdAt: 2026-05-07T00:00:00Z
  updatedAt: 2026-05-07T00:00:00Z
  source:
    producer: agent
    skillId: harness-planner
  inputs:
    - documentId: agency-agents-specialized
      uri: https://github.com/msitarzewski/agency-agents
      relation: output-from
      sections:
        - sourceRange: { startLine: 1, endLine: 1 }   # specialized/hr-onboarding.md
          targetRange: { startLine: 1, endLine: 200 }
  tags: [planner, hr, onboarding, phase-b]
---

<!-- Source: https://github.com/msitarzewski/agency-agents (MIT) — specialized/hr-onboarding.md -->

# Planner HR Module — Onboarding (서브 모듈)

> Recruiting 모듈에서 import한 신규 부서가 첫날 일을 시작할 수 있도록 자료·라우팅·관계를 갖춰주는 절차.

## 1. 입력

- Recruiting 산출물: 새 `skills/<role>/SKILL.md`
- `.harness/actions/scan-result.json` (현재 스택)
- `.harness/agency-mapping.md` (분류 정보)

## 2. 온보딩 절차

```
1. gotchas 인벤토리 생성
   - gotchas/<role>.md (공통 가드)
   - gotchas/<role>-<stack>.md (스택별, 해당 시)
   - 첫 입사일에는 verified 0건, unverified 후보만 명시
   - "스택별 gotcha 후보"는 직전 스프린트의 fail 패턴 참고

2. ref-doc 작성 (필요 시)
   - .harness/ref/<role>-<stack>.md
   - best practice + Eval 검증 기준 1차 정의
   - 예: backend-laravel.md (Phase B-10 산출)

3. 권한 매트릭스 갱신
   - AGENTS.md 의 "읽기/쓰기 권한" 표에 신규 부서 행 추가
   - IA-MAP에 해당 부서가 책임지는 폴더 표기

4. dispatcher 라우팅 카탈로그 갱신
   - skills/dispatcher/persona-ceo.md "부서 카탈로그 룩업" 표에 추가
   - Runbook 매칭 매트릭스에서 어디 편성될지 명시

5. progress.json 보강
   - org.<role> = "active"
   - 해당 부서 전용 필드 (예: eval_security, generator_designer 등)

6. 대시보드 (Brick Office) 데이터 갱신
   - apps/harness-dashboard/data/org.json 에 책상 추가
   - 부서별 색상·아이콘 결정

7. Conductor 라우팅 룰 등록
   - skills/conductor/SKILL.md 의 spawn 결정 트리에 신규 부서 진입 조건 추가

8. 첫 미션 등록 (선택)
   - feature-list.json 에 ramp-up feature 1건 자동 등록
   - 이는 부서가 자기 산출물 양식을 한 번 출력해 보는 dry-run

9. 회의 참석자 매트릭스 갱신
   - skills/meeting-manager/SKILL.md 의 회의 종류별 참석자 표 업데이트
```

## 3. 산출물 체크리스트

새 부서 active 선언 전 모두 통과해야 함:

```
[ ] skills/<role>/SKILL.md 존재 + frontmatter + 출처 주석
[ ] gotchas/<role>.md 인벤토리 (unverified 후보 ≥ 3건 또는 N/A 명시)
[ ] (스택 의존 시) .harness/ref/<role>-<stack>.md 작성
[ ] AGENTS.md 권한 매트릭스 행 추가
[ ] dispatcher 카탈로그 + Runbook 편성 명시
[ ] progress.json 필드 정의
[ ] (대시보드 활성 시) apps/harness-dashboard/data/org.json 갱신
[ ] Conductor 진입 조건 등록
[ ] meeting-manager 참석자 매트릭스 갱신
[ ] hr-roster.md 의 recruiting → active 이동
```

체크리스트 미통과 항목 1건이라도 있으면 부서 status는 `recruiting` 으로 유지, Sprint에 합류 X.

## 4. 인계 (Handoff Package)

신규 부서가 받는 첫 패키지:

```
.harness/actions/onboarding/<role>/
├── welcome.md        (역할 정의·기대치·금지사항)
├── stack-context.md  (현재 스택·conventions·관련 ref-doc 링크)
├── interfaces.md     (어느 부서에 무엇을 보내고 받는지)
├── first-mission.md  (선택: ramp-up feature 명세)
└── escalation.md     (문제 시 누구에게 어떻게 알리는지)
```

## 5. 동료 관계 (Cross-Department Edges)

부서 신설 시 즉시 정의해야 할 관계:

| 질문 | 예시 (Eval-Architecture 신설 시) |
|---|---|
| 누가 산출물을 받아주나? | CQO (audit 통합) |
| 누구의 산출물을 받아 일하나? | Generator-* (코드·diff) |
| 어느 회의 참석? | Sprint Review, Spec Review |
| 어느 Eval과 cross-validate? | Functional, Security, CodeQuality |
| Conductor가 언제 spawn? | Generator 완료 후 / Sprint 종료 회귀 시 |

이 관계가 모호하면 부서가 Idle 상태로 떠도게 됨.

## 6. 안전 가드

- 체크리스트 미통과 active 선언 거부
- 스택과 무관한 ref-doc 강제 작성 금지 (필요 시에만)
- 한 Sprint에 동시 ≥ 3 부서 신설 금지 (혼란 방지) — Owner override 가능

## 7. Off-boarding과의 대칭

부서 폐지 시 대칭적 절차:
- AGENTS.md 권한 행 제거(주석으로 비활성 표시)
- dispatcher 카탈로그에서 제외
- Conductor 진입 조건 비활성
- progress.json.org.<role> = "inactive"
- 파일·gotcha·ref-doc 보존 (재활성 가능)
- hr-roster.md inactive 섹션 이동 + 사유 명시
