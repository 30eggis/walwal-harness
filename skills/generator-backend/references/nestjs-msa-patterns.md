# NestJS MSA Patterns

## 모노레포 구조

```
apps/
├── gateway/                    # API Gateway (port 3000)
│   └── src/
│       ├── main.ts             # bootstrap, CORS
│       ├── app.module.ts       # ClientsModule 등록
│       ├── controllers/        # HTTP → MessagePattern 변환
│       └── guards/
├── service-[name]/             # Microservice (TCP)
│   └── src/
│       ├── main.ts             # TCP bootstrap
│       ├── [name].module.ts
│       ├── [name].controller.ts  # @MessagePattern 핸들러
│       ├── [name].service.ts
│       └── entities/
└── web/                        # (Frontend — 별도 에이전트)

libs/
├── shared-dto/                 # api-contract.json에서 파생
├── database/                   # TypeORM/Prisma 설정
└── common/                     # 필터, 인터셉터, 가드
```

## 통합 러너 (package.json)

```json
{
  "scripts": {
    "dev": "concurrently \"npm run start:gateway\" \"npm run start:service-a\"",
    "start:gateway": "nest start gateway --watch",
    "start:service-a": "nest start service-a --watch"
  }
}
```

## Gateway ↔ Microservice 패턴

```typescript
// apps/gateway/src/controllers/items.controller.ts
@Controller('api/v1/items')
export class ItemsController {
  constructor(@Inject('SERVICE_A') private readonly serviceA: ClientProxy) {}

  @Post()
  create(@Body() dto: CreateItemDto) {
    return this.serviceA.send({ cmd: 'create_item' }, dto);
  }
}

// apps/service-a/src/items.controller.ts
@Controller()
export class ItemsController {
  @MessagePattern({ cmd: 'create_item' })
  create(dto: CreateItemDto) {
    return this.service.create(dto);
  }
}
```

## 규칙

- Gateway = 라우팅 + 검증만, 비즈니스 로직은 서비스에서
- 서비스 간 통신: `ClientProxy.send()` (요청-응답)
- CORS: Gateway에서 `localhost:5173` 허용
- 각 서비스 독립 기동 가능해야 함
