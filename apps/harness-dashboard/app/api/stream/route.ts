import { readHarnessState } from "@/lib/harness-state";
import { resolveHarnessRoot } from "@/lib/harness-root";
import { watchHarness } from "@/lib/watcher";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";
export const revalidate = 0;

const SSE_HEADERS = {
  "Content-Type": "text/event-stream",
  "Cache-Control": "no-cache, no-transform",
  Connection: "keep-alive",
} as const;

function sseFrame(snapshotJson: string): string {
  // Each SSE frame ends with a blank line. Default event = "message".
  return `data: ${snapshotJson}\n\n`;
}

export async function GET(request: Request) {
  const root = resolveHarnessRoot();
  const encoder = new TextEncoder();

  const stream = new ReadableStream<Uint8Array>({
    start(controller) {
      const send = () => {
        try {
          const snap = readHarnessState(root);
          controller.enqueue(encoder.encode(sseFrame(JSON.stringify(snap))));
        } catch (err) {
          // readHarnessState 는 이미 errorBanner 로 fallback 하지만, 만약을
          // 위해 여기서도 안전하게 처리.
          const fallback = JSON.stringify({
            version: "1.1.0",
            ts: new Date().toISOString(),
            errorBanner: {
              level: "error",
              message_ko: "스트림 처리 중 오류가 발생했습니다.",
              message_en: "Stream processing error.",
            },
          });
          controller.enqueue(encoder.encode(sseFrame(fallback)));
        }
      };

      // Initial snapshot.
      send();

      const handle = watchHarness(root, () => send());
      // Local-only data source — push a fresh snapshot every second on top
      // of file-watch events so the dashboard never goes more than 1s stale.
      const tick = setInterval(() => send(), 1000);

      const cleanup = async () => {
        clearInterval(tick);
        try {
          await handle.close();
        } catch {
          /* ignore */
        }
        try {
          controller.close();
        } catch {
          /* ignore — already closed */
        }
      };

      request.signal.addEventListener("abort", () => {
        void cleanup();
      });
    },
  });

  return new Response(stream, { status: 200, headers: SSE_HEADERS });
}
