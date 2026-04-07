# API Contract Schema

```json
{
  "version": "1.0.0",
  "gateway_base_url": "/api/v1",
  "services": {
    "gateway": { "port": 3000, "description": "API Gateway" },
    "service-a": { "port": 3001, "transport": "TCP", "description": "..." }
  },
  "endpoints": [
    {
      "id": "EP-001",
      "method": "POST",
      "path": "/api/v1/items",
      "gateway_route": true,
      "target_service": "service-a",
      "message_pattern": "create_item",
      "description": "...",
      "request_body": { "name": "string (required)" },
      "response_200": { "id": "number", "name": "string", "created_at": "string (ISO 8601)" },
      "response_errors": [
        { "status": 400, "when": "유효성 검증 실패" }
      ],
      "related_features": ["F-001"]
    }
  ]
}
```

## 규칙
- Gateway가 외부 진입점, 내부 서비스는 message pattern으로 통신
- request/response 스키마는 Pydantic/class-validator로 직접 변환 가능한 수준
- 이 계약서가 Frontend ↔ Gateway ↔ Services 간 유일한 진실의 원천
