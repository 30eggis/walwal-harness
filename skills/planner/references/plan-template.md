# Plan Template

```markdown
# Product Specification: [제품명]

## 1. Vision & Value Proposition
[왜 이 제품이 존재해야 하는가]

## 2. User Persona
[타겟 사용자, 사용 시나리오]

## 3. System Architecture

### 3.1 MSA Service Map
- API Gateway (NestJS) — 라우팅, 인증, 레이트리밋
- Service A: [도메인] — [책임]
- Service B: [도메인] — [책임]

### 3.2 Communication
- Dev: TCP transport
- Prod: RabbitMQ / NATS

### 3.3 Monorepo Structure
project-root/
├── apps/
│   ├── gateway/
│   ├── service-a/
│   └── web/
├── libs/
│   ├── shared-dto/
│   ├── database/
│   └── common/
└── package.json

### 3.4 Tech Stack Decisions
- 각 결정의 **근거** 포함

## 4. Data Model
[서비스별 핵심 엔티티 — 서비스 경계 명확히]

## 5. Sprint Roadmap
### Sprint 1: [테마]
  - BE-Gateway: [작업]
  - BE-ServiceA: [작업]
  - FE: [작업]
  - 의존성: [선행 조건]

## 6. AI Integration Opportunities

## 7. Non-Functional Requirements
```
