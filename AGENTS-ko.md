---
docmeta:
  id: AGENTS-ko
  title: AI 에이전트 프로젝트 컨텍스트 (walwal-harness) — 한국어
  type: input
  createdAt: 2026-05-12T00:00:00Z
  updatedAt: 2026-05-12T00:00:00Z
  source:
    producer: user
  tags: [project-context, v7.1, harness, npm-package, claude, codex, ko]
---

# AGENTS.md — walwal-harness v7.1 (패키지 저장소)

이 저장소는 **하네스를 설치하는 npm 패키지**다. 하네스를 실행하는 프로젝트가 아니다.

이 저장소에 `.harness/`를 만들지 않는다. 런타임 프로젝트로 취급하지 않는다.

---

## 1. 패키지 정체

- **패키지**: `@walwal-harness/cli`
- **버전**: v7.1
- **목적**: 외부 프로젝트에 company-mode AI agent harness를 설치
- **런타임 대상**: 사용자가 `walwal-harness init`을 실행하는 외부 프로젝트

---

## 2. 수정 전 확인

가정하지 않는다. 무엇을, 왜 변경하는지 먼저 밝힌다.

- 설치 계약을 달성하는 최소한의 변경만 한다. 추측성 추가는 금지.
- 기존 코드 스타일을 따른다. 인접 코드를 정리하지 않는다.
- `bin/init.js` 또는 스크립트를 변경한 후에는 반드시 검증 후 완료로 처리한다.

**검증:**
```bash
node --check bin/init.js
node --check scripts/import-agency-agents.js
npm pack --dry-run --cache /private/tmp/walwal-npm-cache
```

**init 테스트:**
```bash
mkdir -p /private/tmp/walwal-v7-init-test
node ./bin/init.js init --force --project-root /private/tmp/walwal-v7-init-test
```

**init 후 기대 결과:**
- `.claude/commands/goal.md`, `submission.md`, `hot-fix.md` — 다른 command 없음
- `.claude/skills/harness-{ceo,coo,cdo,cto,cqo,ops}/SKILL.md`
- `.harness/shared/HR-Resource/`
- `CLAUDE.md` → `AGENTS.md` 심볼릭 링크

---

## 3. 설치 계약

`bin/init.js`는 대상 프로젝트에서 정확히 아래 순서로 수행한다:

1. `.harness/` 런타임 디렉터리 생성
2. `HR-Resource/` → `.harness/shared/HR-Resource/` 복사
3. `.claude/commands/`와 `.codex/commands/`에 `/goal`, `/submission`, `/hot-fix`만 설치
4. `.claude/skills/`와 `.codex/skills/`에 CXX skills 설치
5. 잘못 설치된 CXX slash command(`/ceo`, `/cto`, `/cqo` 등) 제거
6. 런타임 스크립트와 훅 설치
7. `assets/templates/AGENTS.md.template`으로 `AGENTS.md` 작성 후 `CLAUDE.md → AGENTS.md` 심볼릭 링크 생성

`postinstall`에서 자동 초기화하지 않는다. 명시적인 `walwal-harness init`으로만 실행된다.

---

## 4. IA-MAP

```
/
├── bin/init.js                        # CLI 진입점 — walwal-harness init
├── commands/
│   ├── goal.md                        # Owner command (대상에 설치됨)
│   ├── submission.md                  # Owner command (대상에 설치됨)
│   └── hot-fix.md                     # Owner command (대상에 설치됨)
├── HR-Resource/{skill-name}/SKILL.md  # 채용 후보 worker pool
├── scripts/
│   ├── import-agency-agents.js        # agency-agents → HR-Resource 변환기
│   └── *.sh                           # init이 설치하는 런타임 스크립트
├── assets/templates/
│   └── AGENTS.md.template             # 대상 프로젝트 CLAUDE.md/AGENTS.md 소스
├── conventions/                       # 번들 convention 템플릿
├── gotchas/                           # 번들 gotcha 템플릿
└── package.json
```

---

## 5. Company 구조 (v7.1)

init 후 대상 프로젝트는 company mode로 동작한다:

```
Owner
  └─ /goal, /submission, 또는 /hot-fix
      └─ harness-ceo
          ├─ harness-coo
          ├─ harness-cdo
          ├─ harness-cto
          ├─ harness-cqo
          └─ harness-ops
```

지원 skill: `harness-hiring`, `harness-resource-manager`, `harness-brick-office`

---

## 6. Command 규칙

Owner-facing command는 정확히 세 개. 이 규칙은 예외 없음:

| Command | 역할 |
|---|---|
| `/goal` | 미션 접수 |
| `/submission` | 활성 goal 하위의 추가 요구사항 |
| `/hot-fix` | 활성 goal 하위의 긴급 수정 |

`/ceo`, `/cto`, `/cqo`, `/ops`, `/hiring` 또는 어떤 CXX도 command로 추가하지 않는다.

---

## 7. HR-Resource

CXX 에이전트가 고용하는 전문 worker pool.

- 소스: `HR-Resource/{skill-name}/SKILL.md`
- 설치 위치: 대상 프로젝트의 `.harness/shared/HR-Resource/`
- 변환: `scripts/import-agency-agents.js` (agency-agents 포맷 → HR-Resource 포맷)

---

## 8. 편집 규칙

- Owner 요청 또는 명시적 승인 없이 `AGENTS.md`를 수정하지 않는다.
- 이 저장소에 `.harness/`를 생성하거나 런타임 상태를 커밋하지 않는다.
- HR-Resource 변환은 `scripts/import-agency-agents.js`만 사용한다.
- 사용자가 만든 변경을 명시적 지시 없이 되돌리지 않는다.
- 2-command 규칙은 Owner 승인 없이 변경하지 않는다.
