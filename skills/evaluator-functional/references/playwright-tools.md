# Playwright MCP Tools Reference

## 핵심 도구

| 도구 | 용도 | 주요 사용 Step |
|------|------|---------------|
| `browser_navigate` | URL 이동 | Step 1, 3, 4 |
| `browser_click` | 요소 클릭 | Step 3, 4 |
| `browser_fill` | 입력 필드 작성 | Step 4, 6 |
| `browser_select_option` | 드롭다운 선택 | Step 4 |
| `browser_press_key` | 키보드 (Enter, Escape, Tab) | Step 4, 6 |
| `browser_take_screenshot` | 스크린샷 (증거) | 모든 Step |
| `browser_snapshot` | 접근성 트리 (DOM 구조) | Step 1, 4 |
| `browser_console_messages` | 콘솔 에러 감지 | Step 1, 7 |
| `browser_network_requests` | API 호출 캡처 | Step 2, 4, 5 |
| `browser_wait` | 요소/상태 대기 | Step 4 |
| `browser_resize` | 뷰포트 크기 변경 | Step 4 |
| `browser_tabs` | 탭 목록 | Step 2 |
| `browser_handle_dialog` | alert/confirm 처리 | Step 6 |
| `browser_hover` | 호버 상태 | Step 4 |
| `browser_drag` | 드래그 앤 드롭 | Step 4 |

## 기준 검증 패턴

```
기준: "사용자가 아이템을 생성할 수 있다"

[Action]
1. browser_navigate → /items
2. browser_click → "새 아이템" 버튼
3. browser_fill → name 필드에 "Test"
4. browser_click → "저장"
5. browser_wait → 목록에 "Test" 표시

[Verify]
6. browser_take_screenshot → 결과 캡처
7. browser_network_requests → POST /api/v1/items 확인
8. browser_snapshot → DOM에 "Test" 존재 확인

[Verdict]
Result: PASS / FAIL
Evidence: [스크린샷, 네트워크, 스냅샷]
```
