---
docmeta:
  id: evaluation-visual
  title: Evaluation — Visual (Sprint 1 / Phase C-1)
  type: output
  createdAt: 2026-05-07T00:00:00Z
  updatedAt: 2026-05-07T00:00:00Z
  source:
    producer: agent
    skillId: harness-evaluator-visual
  inputs:
    - documentId: brainstorm-spec
      uri: ./brainstorm-spec.md
      relation: output-from
      sections:
        - sourceRange: { startLine: 83, endLine: 99 }    # §5 선택된 접근법 (Single Floor Plan / Hybrid Aura)
          targetRange: { startLine: 24, endLine: 48 }    # 본 평가 V1 톤 + V2 레이아웃
    - documentId: evaluation-functional
      uri: ./evaluation-functional.md
      relation: output-from
      sections:
        - sourceRange: { startLine: 78, endLine: 100 }   # cross_validation_from_functional
          targetRange: { startLine: 50, endLine: 90 }    # 본 평가 V3-V5
    - documentId: gotchas-generator-frontend
      uri: ../gotchas/generator-frontend.md
      relation: output-from
      sections:
        - sourceRange: { startLine: 16, endLine: 30 }    # G-001 메타버스 톤 학습
          targetRange: { startLine: 50, endLine: 60 }    # V1 톤 매칭 평가
  tags: [evaluation, visual, sprint-1, phase-c-1, PASS]
---

# Evaluation — Visual (Sprint 1 / Phase C-1)

## Verdict: **PASS** (Weighted 3.00 / 3.00)

베이스라인 스크린샷: `.harness/baselines/visual/sprint-1-overview.png` (1920×1080, demo state with typing+talking).

## 시각 축 평가

### V1. Tone & Style Match — Score **3** / 3

레퍼런스: 사용자 첨부 Roblox/메타버스 voxel isometric 이미지 + brainstorm-spec §5 (Hybrid Aura/Motion + Single Floor Plan) + G-001 학습.

검증 evidence:
- Voxel-ish low-poly 캐릭터: 머리 sphere + 몸통 박스 + 모자 cylinder + 다리 박스 segment (`Minifig3D.tsx:159-192`)
- 박스형 룸 walls + 평면도 floor + 책상/의자 박스 가구 (`Floor3D.tsx:138-168` Desk, Chair, Wall)
- Orthographic 카메라 30°/45° 각도 + 그림자 (`Stage3D.tsx:25` zoom 60 + `directionalLight castShadow`)
- 파스텔 ground (#7ba27a) + 토이타운 트리 (icosahedron leaf + cylinder trunk) (`Floor3D.tsx:319-340`)
- 캐릭터 모자 14가지 색 hashColor 결정 → 식별 가능

→ G-001 의 "추상 SVG 도형 디폴트 금지" 학습 충실 적용. Roblox 톤 정합.

### V2. Layout & Spatial Hierarchy — Score **3** / 3

- 7룸 비겹침 (iso.test.ts:31-46 invariant 통과) + 룸간 1유닛 복도 6개 (수직 4 + 수평 2, CORRIDOR_RECTS).
- 회색 복도 floor mesh 가 룸과 시각 구분되어 통로로 읽힘 (`Floor3D.tsx:298-313`).
- 외부 잔디 (26×22 plane) + 인도 + 트리 10그루로 빌딩 footprint 가 떠있지 않고 환경에 자리잡음.
- 빌딩 footprint x:[0..11] z:[0..9] + 잔디 22 → 카메라 frustum width 32 단위에 적정 비율 (사용자 "2배 크게" 요청 반영).

### V3. Readability & Affordance — Score **3** / 3

- 룸 라벨 (`drei <Html>`, distanceFactor=20) 가 floor 중앙 약간 앞쪽에 한국어로 표시 — 식별 가능.
- 캐릭터 모자색 14종 + 머리/몸 다른 색조 → 군집에서도 개별 식별.
- Aura ring 4상태 (회색 idle / 청록 typing / 황 talking + 작은 sphere indicator / 빨강 alert + shake) → 한 화면에서 상태 한눈 비교.
- 도어 갭이 외벽 segment 분리로 가시 (`Floor3D.tsx:wallSegments` + `DoorFrame` 트림으로 위치 강조).
- 책상 위 모니터 cyan emissive → 책상 위치를 멀리서도 식별.

### V4. Action / Motion Coherence — Score **3** / 3

(브레인스토밍에서 합의된 Hybrid Aura+Selective Motion 정합)

- idle: ROAM_POOL 30+ waypoint 자유 동선 + 책상 사이 보행, 도어 경유 (`path-planning.ts planPath`) → 벽 통과 X (사용자 명시 요구 반영).
- typing: 자기 home desk chair 위치 정착 + 책상 facing.
- talking: meeting 좌석으로 텔레포트 + 작은 노란 sphere 인디케이터 + Aura blink.
- red-alert: home desk 위치 + jitter (translateX) + Aura pulse.
- 보행 모션: 다리 swing (sin t·8) + bobbing (`Minifig3D.tsx:154-160`).
- 사용자 in-flight 피드백 (G-001 메타버스 톤 / "기차놀이 X" / "벽 뚫지 마") 셋 모두 반영.

### V5. Trade-Dress Compliance — Score **3** / 3

- "Brick Office" 워드마크 (font-mono, tracking-[0.18em], 자체 디자인) — LEGO 로고 미모방.
- 캐릭터 형태: voxel 박스 + sphere 머리 — LEGO 미니피규어 표준 비율 (몸통 1:1.5:0.8 등) 미모방, 일반 chunky low-poly.
- 룸 박스: 자유 비율 (3×2, 5×3, 6×2 등). LEGO 2x4 플레이트 표준 비율 (1:2) 회피.
- 색팔레트: 파스텔/그라디언트 — LEGO primary red/yellow/blue 채도 회피.
- HTML 본문에 "lego" 문자열 부재 (Functional AC5 검증).

### 가중 점수

| 축 | Score | Weight | 가중합 |
|---|---|---|---|
| V1 Tone & Style | 3 | 30% | 0.90 |
| V2 Layout | 3 | 20% | 0.60 |
| V3 Readability | 3 | 20% | 0.60 |
| V4 Action/Motion | 3 | 20% | 0.60 |
| V5 Trade-Dress | 3 | 10% | 0.30 |
| **합계** | | | **3.00 / 3.00** |

## Cross-Validation 합치성

- Functional 의 DOM count (rooms=7, minifigs=14) ↔ Visual 의 캡처에서 시각 룸·캐릭터 카운트 일치.
- Code-Quality 의 contract drift (homeRoom) 가 시각에 미치는 영향 X (homeRoom 은 좌석 텔레포트 후 원위치 추적용).

## 베이스라인 등록

- `.harness/baselines/visual/sprint-1-overview.png` (1920×1080) 저장. 다음 sprint 의 Visual eval 이 이 이미지를 reference 로 회귀 비교 가능.

## Adversarial Notes

- 단일 캡처가 "예쁜 한 컷" 일 가능성 — Playwright timing 기반 (8s wait) 으로 motion 안정 후 캡처. 자유 동선이 매 캡처마다 다른 위치를 보여주므로 "동결 상태 위장" 불가능.
- 사용자 레퍼런스 이미지와 직접 비교: 머리/모자/몸통 비율, 박스형 빌딩 스케일, isometric 각도 모두 정합.
- LEGO 회피는 단순 string 부재 + trade-dress (비율/색/형태) 분석 — 시각으로 확인.

## Verdict 요약

```
PASS  3.00/3.00  retry_target: -
next_agent: archive  (sprint 1 chain 완료)
```
