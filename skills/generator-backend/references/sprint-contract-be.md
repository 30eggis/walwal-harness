# Sprint Contract — Backend Section Template

```markdown
## Backend Scope

### Services Affected
| Service | Port | Changes |
|---------|------|---------|
| gateway | 3000 | EP-XXX 라우팅 추가 |
| service-a | 3001 | message_pattern 핸들러 추가 |

### Message Patterns
| Pattern | From | To | Payload | Response |
|---------|------|----|---------|----------|
| create_item | gateway | service-a | CreateItemDto | ItemResponse |

### Database Schema Changes
- Service-A DB: items (id, name, description, created_at, updated_at)

### Shared DTOs (libs/shared-dto)
- CreateItemDto: { name: string, description?: string }
- ItemResponse: { id: number, name: string, created_at: string }

### Success Criteria (Backend)
1. [ ] Gateway → POST /api/v1/items → service-a → 201
2. [ ] 유효성 검증 — 빈 name → 400
3. [ ] 서비스 간 TCP 통신 정상
4. [ ] Jest 통과

### Test Commands
curl -X POST http://localhost:3000/api/v1/items -H "Content-Type: application/json" -d '{"name":"Test"}'
```
