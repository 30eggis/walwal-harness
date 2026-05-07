---
docmeta:
  id: gotchas-generator-frontend
  title: Gotchas — Generator-Frontend
  type: output
  createdAt: 2026-05-07T00:00:00Z
  updatedAt: 2026-05-07T00:00:00Z
  source:
    producer: agent
    skillId: harness-dispatcher
  inputs:
    - documentId: user-feedback-phase-c-sprint-1
      uri: (inline — Phase C Sprint 1 사용자 피드백 + 첨부 레퍼런스 이미지)
      relation: output-from
      note: inline 입력으로 sourceRange 는 단일 1..1 placeholder. targetRange 는 본 문서 [G-001] 항목의 라인 범위.
      sections:
        - sourceRange: { startLine: 1, endLine: 1 }   # 사용자 피드백 메시지 본문 (inline)
          targetRange: { startLine: 22, endLine: 23 } # [G-001] Trigger
        - sourceRange: { startLine: 1, endLine: 1 }   # 첨부 레퍼런스 이미지 (inline, voxel 3D)
          targetRange: { startLine: 24, endLine: 27 } # [G-001] Wrong / Right
        - sourceRange: { startLine: 1, endLine: 1 }   # 사용자 채택 결정 (Q1=R3F, Q2=둘 다 기록)
          targetRange: { startLine: 30, endLine: 31 } # [G-001] Resolution
  tags: [gotchas, generator-frontend, visual-tone, react-three-fiber]
---

# Gotchas — Generator-Frontend

> Dispatcher가 관리. Generator-Frontend는 세션 시작 시 이 파일을 읽고 같은 실수를 반복하지 않습니다.

### [G-001] "isometric SVG 추상 도형" 디폴트 금지
- **Date**: 2026-05-07
- **Status**: unverified
- **TTL**: 2026-07-06
- **Trigger**: Phase C Sprint 1 — Brick Office 대시보드를 단순 SVG 폴리곤(삼각/사각 + Aura 외곽선)으로 구현했더니 사용자가 "내가 원한 건 Roblox/메타버스 풍 voxel isometric이었다" 며 레퍼런스 이미지(low-poly 3D 빌딩 + 캐릭터)를 첨부.
- **Wrong**: 시각 톤 레퍼런스를 사전에 확인하지 않고 SVG 추상 도형으로 진입. brainstorm-spec / plan 의 "SVG 2.5D isometric" 문구를 글자 그대로 해석 — 톤은 명시되지 않았는데 가장 단순한 형태로 가정.
- **Right**: visual feature 작업 직전에 **레퍼런스 이미지/톤을 사용자에게 묻거나 Visual Companion 에 후보 mockup 을 띄워 확인**. 단순 도형 vs voxel 3D vs 일러스트 등 톤 폭이 크면 코드 진입 전에 1 라운드 좁힌다.
- **Why**: "isometric" 한 단어로는 Roblox 풍 voxel 3D / 사진풍 게임 isometric / 비즈니스 다이어그램 / 추상 SVG 가 모두 들어간다. 디폴트 추상 SVG 는 데이터 가시화엔 충분해도 "메타버스/사옥 메타포" 같은 정서적 의도와 어긋난다.
- **Scope**: 모든 visual UI feature 시작 직전. 특히 메타포가 강한 화면(대시보드·게임화·캐릭터 표현).
- **Occurrences**: 1
- **Resolution**: 같은 Sprint 1 안에서 react-three-fiber + drei + (선택적) Kenney CC0 GLB 로 교체. SVG 컴포넌트(Floor.tsx/Minifig.tsx) 제거. 데이터 계층(harness-state, api-contract, agent-roster) 는 변경 없음.
