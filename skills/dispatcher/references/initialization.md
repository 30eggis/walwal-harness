# Initialization Guide — Phase 0

## Phase 0a: 전체 초기화 (빈 프로젝트 / 하네스 미설치)

```bash
bash scripts/scan-project.sh .
bash scripts/init-agents-md.sh .
```

## Phase 0b: AGENTS.md 없음 (하네스는 있으나 문서 누락)

```bash
bash scripts/scan-project.sh .
bash scripts/init-agents-md.sh .
```

## Phase 0c: 기존 CLAUDE.md 보존 + 리빌드 (브라운필드)

```bash
# 1. 스캔 — 기존 CLAUDE.md 내용을 scan-result.json에 보존
bash scripts/scan-project.sh .

# 2. 리빌드 — 기존 규칙을 "Preserved Rules" 섹션으로 이관
#    원본은 .harness/archive/pre-harness-backup/ 에 백업
bash scripts/init-agents-md.sh .
```

## Phase 0 이후 사용자 확인

```
AGENTS.md가 생성/리빌드되었습니다.

스캔 결과:
- 프로젝트 타입: [fullstack / backend-only / frontend-only / empty]
- 감지된 스택: [BE] / [FE] / [DB]
- 미분류 경로: [N]개 ([?] 태그)
- 기존 규칙 이관: [Y/N]

[?] 태그 경로를 확인해 주세요. 확인 후 요청사항을 말씀해 주시면 파이프라인을 선택합니다.
```

## scan-project.sh 감지 항목

| 항목 | 감지 방법 |
|------|----------|
| NestJS | nest-cli.json |
| FastAPI | requirements.txt + "fastapi" |
| Next.js | next.config.* |
| React/Vite | vite.config.* |
| 모노레포 | turbo.json, nx.json, pnpm-workspace.yaml |
| DB | package.json 내 typeorm/prisma/mongoose |
| OpenAPI | openapi.json/yaml, swagger.json/yaml |
| Git | .git/ 존재, 커밋 수, 브랜치 |
