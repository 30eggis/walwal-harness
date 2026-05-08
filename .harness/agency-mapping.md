---
docmeta:
  id: agency-mapping
  title: agency-agents → walwal-harness 매핑안
  type: output
  createdAt: 2026-05-07T00:00:00Z
  updatedAt: 2026-05-07T00:00:00Z
  source:
    producer: agent
    skillId: harness-dispatcher
  inputs:
    - documentId: agency-agents-repo
      uri: https://github.com/msitarzewski/agency-agents
      relation: output-from
      note: 입력은 원격 저장소(디렉토리 트리)로 단일 .md 라인 주소가 없어, 카테고리 디렉토리를 논리 섹션으로 매핑함
      sections:
        - sourceRange: { startLine: 1, endLine: 1 }   # design/ 카테고리
          targetRange: { startLine: 89, endLine: 99 }
        - sourceRange: { startLine: 1, endLine: 1 }   # engineering/ 카테고리
          targetRange: { startLine: 65, endLine: 86 }
        - sourceRange: { startLine: 1, endLine: 1 }   # testing/ 카테고리
          targetRange: { startLine: 110, endLine: 122 }
        - sourceRange: { startLine: 1, endLine: 1 }   # specialized/ 카테고리
          targetRange: { startLine: 130, endLine: 142 }
        - sourceRange: { startLine: 1, endLine: 1 }   # support/ + product/ (Service-Ops)
          targetRange: { startLine: 144, endLine: 158 }
        - sourceRange: { startLine: 1, endLine: 1 }   # 제외 (CN-only)
          targetRange: { startLine: 24, endLine: 26 }
  tags: [harness, mapping, agency-agents, phase-a]
---

# agency-agents → walwal-harness 매핑 (Phase A)

> Source: https://github.com/msitarzewski/agency-agents (MIT)
> 채택된 모든 파일은 상단에 출처 주석 명시 필수.

## 제외 (CN-only, 16건)

`engineering-feishu-integration-developer`, `engineering-wechat-mini-program-developer`, `marketing-baidu-seo-specialist`, `marketing-bilibili-content-strategist`, `marketing-china-ecommerce-operator`, `marketing-china-market-localization-strategist`, `marketing-douyin-strategist`, `marketing-kuaishou-strategist`, `marketing-livestream-commerce-coach`, `marketing-private-domain-operator`, `marketing-short-video-editing-coach`, `marketing-wechat-official-account`, `marketing-weibo-strategist`, `marketing-xiaohongshu-specialist`, `marketing-zhihu-strategist`, `marketing-cross-border-ecommerce`(중국 맥락 강함, 보류)

## 조직 구성 (확정)

```
사용자 (Owner) ── 대화 ──► CEO(Dispatcher)
                              │ GOAL 협의 (CTO와 함께 사용자에게 제안→확정)
                              ▼
                   ┌──────────┼─────────────┬──────────────────┐
                   COO        CTO           CQO                Service-Ops
                  (Planner)  (Gen 총괄)    (Eval 총괄)         (운용팀)
                    │
           Hypothesis Cell
        Developer 1 · Documentationer 1
                              │              │                  │
                  ┌────┬──────┼─────┐  ┌─────┼────┬─────┐   ┌───┴──────┐
                  BE   FE  Designer DevOps  Func Visual CQ  Arch Sec  Monitor Incident AutoRetro
```

## 매핑 테이블

### 1. CEO (Dispatcher 격상)
| 채택 | 출처 | 배치 |
|---|---|---|
| ✅ | specialized-chief-of-staff | `skills/dispatcher/` 페르소나 보강 |
| ✅ | specialized-workflow-architect | dispatcher 라우팅 로직 |
| ✅ | strategy/EXECUTIVE-BRIEF.md, nexus-strategy | CEO 의사결정 reference |

### 2. COO (Planner 보강)
| 채택 | 출처 | 배치 |
|---|---|---|
| ✅ | product-manager | `skills/planner/` PRD/AC 분해 보강 |
| ✅ | product-sprint-prioritizer | 우선순위 알고리즘 |
| ✅ | project-manager-senior | 멀티스프린트 로드맵 |
| ✅ | project-management-studio-producer | 부서 간 조율 |
| ✅ | project-management-experiment-tracker | A/B·실험 추적 |
| ➖ | project-management-jira-workflow-steward | 외부 JIRA 미사용 시 보류 |

### 2-1. COO Direct Hypothesis Cell (신규)
| 채택 | 출처 | 배치 |
|---|---|---|
| ✅ | engineering-rapid-prototyper | `skills/coo-developer/` 빠른 spike 구현 |
| ✅ | engineering-data-engineer | 백데이터 기반 가설 검증 |
| ✅ | engineering-technical-writer | `skills/documentationer/` 실험 문서화 |
| ✅ | specialized-document-generator | 보고서 초안 자동화 |
| ✅ | design-ux-researcher | 리서치 질문 설계·가설 보강 |

### 3. CTO (Generator 총괄, 신규)
| 채택 | 출처 | 배치 |
|---|---|---|
| ✅ | engineering-software-architect | `skills/cto/` 페르소나 핵심 |
| ✅ | engineering-senior-developer | 코드 품질 가드레일 |
| ✅ | engineering-minimal-change-engineer | 최소변경 원칙 강제 |
| ✅ | engineering-git-workflow-master | 커밋·브랜치 정책 |
| ✅ | engineering-codebase-onboarding-engineer | 신규 프로젝트 진입 |

### 3-1. Generator-Backend (기존, 보강)
| 채택 | 출처 | 배치 |
|---|---|---|
| ✅ | engineering-backend-architect | `gotchas/generator-backend.md` 보강 |
| ✅ | engineering-data-engineer | 데이터 파이프라인 |
| ✅ | engineering-database-optimizer | DB 인덱싱·쿼리 |
| ✅ | engineering-cms-developer | Laravel/Filament ref-doc 후보 |
| ✅ | engineering-filament-optimization-specialist | **Laravel/Filament 약점 5번 직격** |
| ✅ | engineering-ai-engineer | AI 기능 통합 |
| ✅ | engineering-email-intelligence-engineer | 이메일 처리 도메인 |
| ➖ | engineering-embedded-firmware-engineer | 임베디드, 도메인 시 채택 |
| ➖ | engineering-solidity-smart-contract-engineer | 블록체인 시 채택 |
| ➖ | engineering-voice-ai-integration-engineer | 음성 도메인 시 채택 |

### 3-2. Generator-Frontend (기존, 보강)
| 채택 | 출처 | 배치 |
|---|---|---|
| ✅ | engineering-frontend-developer | 기존 보강 |
| ✅ | engineering-mobile-app-builder | 모바일 분기 |
| ✅ | engineering-rapid-prototyper | MVP/spike |

### 3-3. Generator-Designer (신규, FE 디자인 약점 1)
| 채택 | 출처 | 배치 |
|---|---|---|
| ✅ | design-ui-designer | `skills/generator-designer/` 핵심 |
| ✅ | design-ux-architect | 정보구조 |
| ✅ | design-ux-researcher | 가설/리서치 |
| ✅ | design-brand-guardian | 브랜드 일관성 |
| ✅ | design-visual-storyteller | 시각 내러티브 |
| ✅ | design-inclusive-visuals-specialist | 접근성·포용성 |
| ✅ | design-whimsy-injector | 디테일/마이크로인터랙션 |
| ✅ | design-image-prompt-engineer | 생성형 이미지 프롬프트 |

### 3-4. Generator-DevOps/Deployer (신규, 약점 4)
| 채택 | 출처 | 배치 |
|---|---|---|
| ✅ | engineering-devops-automator | `skills/generator-devops/` 핵심 |
| ✅ | engineering-sre | 운영 신뢰성 (Service-Ops와 공유) |
| ✅ | engineering-autonomous-optimization-architect | 자율 최적화 |

### 4. CQO (Evaluator 총괄, 신규)
| 채택 | 출처 | 배치 |
|---|---|---|
| ✅ | engineering-code-reviewer | `skills/cqo/` 페르소나 |
| ✅ | testing-reality-checker | rubber-stamping 방지 |
| ✅ | testing-evidence-collector | Evidence-zero=0점 강제 보강 |
| ✅ | testing-test-results-analyzer | 결과 종합 |
| ✅ | testing-tool-evaluator | 도구 검증 |
| ✅ | testing-workflow-optimizer | 평가 루프 효율화 |

### 4-1. Eval-Functional (기존, 보강)
| ✅ | testing-api-tester | `skills/evaluator-functional/` |
| ✅ | testing-performance-benchmarker | 성능 AC |

### 4-2. Eval-Visual (기존, 보강 — 약점 1·2)
| ✅ | testing-accessibility-auditor | `skills/evaluator-visual/` 접근성 축 추가 |
| ✅ | design-brand-guardian | 시각 일관성 검증 (designer와 공유) |

### 4-3. Eval-Code-Quality (기존, 보강)
| ✅ | engineering-code-reviewer | 기존 |
| ✅ | engineering-minimal-change-engineer | 변경 최소성 검증 |

### 4-4. Eval-Architecture (신규 — 약점 2 백엔드 아키텍처)
| 채택 | 출처 | 배치 |
|---|---|---|
| ✅ | engineering-software-architect | `skills/evaluator-architecture/` |
| ✅ | engineering-backend-architect | BE 아키텍처 적대적 검증 |
| ✅ | engineering-database-optimizer | DB 설계 검증 |

### 4-5. Eval-Security (신규 — 약점 6)
| 채택 | 출처 | 배치 |
|---|---|---|
| ✅ | engineering-security-engineer | `skills/evaluator-security/` 핵심 |
| ✅ | engineering-threat-detection-engineer | 위협 모델링 |
| ✅ | specialized-blockchain-security-auditor | 블록체인 시 |
| ✅ | specialized-compliance-auditor | 규제 준수 |
| ✅ | support-legal-compliance-checker | 법적 컴플라이언스 |
| ✅ | specialized-agentic-identity-trust | AI 신뢰성/identity |
| ✅ | specialized-zk-steward | ZK 도메인 |

### 5. Service-Ops (운용팀, 신규 — 약점 3·7·8)
| 채택 | 출처 | 배치 |
|---|---|---|
| ✅ | engineering-sre | `skills/service-ops/monitor/` |
| ✅ | engineering-incident-response-commander | `skills/service-ops/incident/` (약점 8) |
| ✅ | support-infrastructure-maintainer | 운용 베이스 |
| ✅ | support-analytics-reporter | 리포트 생성 (CTO 핸드오프) |
| ✅ | support-executive-summary-generator | CEO 요약 |
| ✅ | product-feedback-synthesizer | 자율 피드백 (약점 7) |
| ✅ | testing-reality-checker | GOAL adherence 체크 |
| ✅ | engineering-autonomous-optimization-architect | Auto-Retro |
| ✅ | specialized-automation-governance-architect | 자율수정 거버넌스 |
| ✅ | specialized-report-distribution-agent | 리포트 라우팅 |

### 6. 횡단 도구 (신규 commands/skills)
| 채택 | 출처 | 배치 |
|---|---|---|
| ✅ | engineering-technical-writer | `skills/technical-writer/` (문서/시각화 약점 9) |
| ✅ | specialized-document-generator | 자동 문서 |
| ✅ | specialized-mcp-builder | MCP 통합 시 |
| ✅ | specialized-lsp-index-engineer | 코드 인덱싱 (대시보드 데이터 소스) |
| ✅ | specialized-developer-advocate | DX 보강 |
| ✅ | engineering-ai-data-remediation-engineer | 데이터 정합성 |

### 7. 보류 (도메인 의존, 프로젝트별 옵트인)
- `academic/*` — 학술 프로젝트 시 활성화
- `finance/*` — 핀테크 시
- `game-development/*` — 게임 시 (blender/godot/unity/unreal/roblox 디렉토리)
- `paid-media/*`, `sales/*` — 마케팅·영업 도메인 시
- `marketing/*` (CN 제외 14개) — 컨텐츠/그로스 도메인 시
- `spatial-computing/*` — XR/visionOS 시
- `specialized/{healthcare,hospitality,legal,real-estate,retail,recruitment,study-abroad,supply-chain,salesforce,korean-business-navigator,french-consulting-market,civil-engineer,corporate-training,government-digital-presales}` — 산업 옵트인
- `integrations/*` — 다른 코딩 에이전트 통합 (claude-code 외 보류)

## Phase B 우선 이식 순서

1. **CTO·CQO 페르소나** (`skills/cto/`, `skills/cqo/`) — 라우팅 허브
2. **Eval-Security** (`skills/evaluator-security/`) — 약점 6 즉효
3. **Eval-Architecture** (`skills/evaluator-architecture/`) — 약점 2
4. **Generator-Designer** (`skills/generator-designer/`) — 약점 1
5. **Service-Ops 3종** (monitor / incident / auto-retro) — 약점 3·7·8
6. **Generator-DevOps** — 약점 4
7. **Laravel/Filament ref-doc** (`gotchas/generator-backend-laravel.md`, `.harness/ref/backend-laravel.md`) — 약점 5

## Phase C 대시보드 (Brick Office)

- 위치: `apps/harness-dashboard/` (Next.js, SVG 2.5D isometric)
- 룸: CEO실 / COO실(Planner + Hypothesis Cell) / CTO팀룸(BE·FE·Designer·DevOps 책상) / CQO팀룸(Func·Visual·CQ·Arch·Sec) / Service-Ops룸(모니터 벽) / 회의실(Sprint Planning) / 아카이브 창고
- 데이터: `progress.json` + `progress.log` + `actions/*` chokidar watch → WS push
- 미니피규어 상태: idle / typing / talking(handoff) / red-alert
- 인터랙션: 미니피규어 클릭→로그 패널, 룸 클릭→부서 메트릭, GOAL 카드는 CEO실 벽에 핀
- LEGO 상표 회피: 워드마크 "Brick Office" / "Studio Office"

## GOAL 협의 프로토콜

- 권한자: **CEO**(Dispatcher 페르소나) — 사용자 대화로부터 GOAL 추출/확정
- 협의 채널: **CTO ↔ User** — 기술적 실현 가능성 검토 후 CEO에 회신
- 산출물: `.harness/actions/goals.md` (id, title, success_metrics, deadline, kpi[], owner, status)
- 사용처: Planner(COO)는 GOAL을 입력으로 Sprint·feature-list·AC 분해
- 진행 추적: `progress.json.goals[]` + `progress.json.ops.goal_adherence`
