---
docmeta:
  id: planner-hr-recruit
  title: Planner HR Module — Recruiting
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
        - sourceRange: { startLine: 1, endLine: 1 }   # specialized/recruitment-specialist.md
          targetRange: { startLine: 1, endLine: 200 }
  tags: [planner, hr, recruiting, phase-b]
---

<!-- Source: https://github.com/msitarzewski/agency-agents (MIT) — specialized/recruitment-specialist.md -->

# Planner HR Module — Recruiting (서브 모듈)

> 본 문서는 `skills/planner/SKILL.md` 의 보조 모듈. Dispatcher 부서식별 결과나 CTO/Conductor 채용 제안을 받아 신규 부서 import 절차 수행.

## 1. 입력

- **트리거 1**: Dispatcher org-chart에 새 must/should 부서가 비활성 상태로 표기됨
- **트리거 2**: CTO 또는 Conductor가 Owner에 채용 제안 (Dispatcher 경유 → Owner 승인) → Planner에 위임
- **자료**: `.harness/agency-mapping.md`, `progress.json.org`, `hr-roster.md`

## 2. 채용 절차

```
1. 후보 매칭
   a. agency-mapping.md 의 "✅ 확정 채택" 카탈로그에서 직접 매핑
   b. 없으면 같은 카테고리 다른 항목 (보류 상태)
   c. 그래도 없으면 → 직접 작성 모드 (별도 절차)

2. 자격 검증
   - CN-only 필터 (WeChat/Weibo/Douyin/Baidu/Bilibili/Kuaishou/
     Xiaohongshu/Zhihu/Feishu/cross-border 보류) 자동 제외
   - License 확인 (MIT 외 라이선스는 Owner 명시 승인 필요)

3. Owner 승인
   Dispatcher 통해:
   [채용 제안]
   부서: <role>
   사유: <one-line>
   출처: agency-agents/<path> (MIT)
   온보딩 비용: 1 sprint ramp
   승인하시겠습니까? (y/n)

4. Import
   - raw fetch: https://raw.githubusercontent.com/msitarzewski/agency-agents/main/<path>
   - 변환: agency 양식 → walwal SKILL.md 양식
     · YAML frontmatter (name, description, disable-model-invocation)
     · Source 주석 첨부 (MIT)
     · docmeta 추가
     · 우리 조직도 용어로 정렬 (CEO/COO/CTO/CQO/Service-Ops/Conductor 등)
   - 저장 위치: skills/<role>/SKILL.md

5. Onboarding 모듈로 핸드오프 (`hr-onboard.md`)
```

## 3. 변환 룰 (agency → walwal)

| agency 양식 | walwal 양식 |
|---|---|
| `name: Foo Bar` | `name: harness-foo-bar` (kebab + 접두) |
| `description: ...` | description 마지막에 트리거 키워드 추가 |
| `color`, `emoji`, `vibe` | 제거 또는 주석으로 보존 |
| 호출 양식 ("Please spawn...") | progress.json next_agent 패턴으로 재작성 |
| Phase 라이프사이클 언급 | 우리 NEXUS-adapted Phase 0~6에 매핑 |
| 다른 agency 에이전트 호출 | 우리 부서 이름으로 치환 (혹은 Pending 표시) |

## 4. 직접 작성 모드 (카탈로그 부재 시)

agency-agents에 없는 부서가 필요할 때:

1. CTO·Owner와 책임 정의 합의 (Spec Review Meeting)
2. 기존 walwal 스킬을 베이스로 새 SKILL.md 초안
3. gotchas/<role>.md 빈 인벤토리 생성 (verified 0건)
4. ref-doc 필요 여부 판단 (스택 의존이면 작성)

## 5. 산출물

- 새 `skills/<role>/SKILL.md` (변환 또는 직접)
- `gotchas/<role>.md` 초안 (Onboarding 책임)
- `.harness/actions/hr-roster.md` 갱신 (`recruiting → active`)
- progress.json.org.<role> = "active"

## 6. 안전 가드

- Owner 승인 없이 import 금지
- 동일 role 중복 채용 시도 거부 (이미 active이면 무시)
- License MIT 외 항목은 import 전 사용자에게 명시 (Apache 2.0/BSD는 자동 OK, GPL은 거부)
- Import된 파일은 `Source: <url> (LICENSE)` 주석 필수, 누락 시 자체 reject
