import { test, expect } from "@playwright/test";
import { readFileSync, writeFileSync } from "node:fs";
import path from "node:path";

const PROGRESS_PATH = path.resolve(
  process.cwd(),
  "..",
  "..",
  ".harness",
  "progress.json"
);

test("F-025 SSE latency < 500ms (5-sample average)", async ({ page }) => {
  await page.goto("/");
  // The current dashboard is the mission-centric Scene (no 3D canvas); wait for
  // the header chrome to confirm the app mounted before measuring SSE latency.
  await page.waitForSelector("header");
  await page.waitForTimeout(2500);

  // Record onmessage timestamps from the page side.
  await page.evaluate(() => {
    (window as any).__sseSamples = [];
    const es = (window as any).__sseSamples;
    const stream = new EventSource("/api/stream");
    stream.onmessage = () => {
      es.push(Date.now());
    };
    (window as any).__perfStream = stream;
  });

  // Wait for the test stream's first frame so we don't measure
  // the connection-handshake interval.
  await page.waitForFunction(
    () => ((window as any).__sseSamples?.length ?? 0) >= 1
  );

  const original = readFileSync(PROGRESS_PATH, "utf8");
  const samples: number[] = [];

  for (let i = 0; i < 5; i++) {
    const baselineCount = await page.evaluate(
      () => (window as any).__sseSamples.length
    );
    const writeTs = Date.now();
    const d = JSON.parse(original);
    d.updated_at = `perf-sample-${i}-${writeTs}`;
    writeFileSync(PROGRESS_PATH, JSON.stringify(d, null, 2));

    await page.waitForFunction(
      (prev) => ((window as any).__sseSamples.length ?? 0) > (prev as number),
      baselineCount,
      { timeout: 5000 }
    );

    const arrivedAt = await page.evaluate(
      () => (window as any).__sseSamples.at(-1) as number
    );
    samples.push(arrivedAt - writeTs);

    await page.waitForTimeout(400); // settle between samples
  }

  // Restore.
  writeFileSync(PROGRESS_PATH, original);

  await page.evaluate(() => {
    (window as any).__perfStream?.close();
  });

  const avg = samples.reduce((a, b) => a + b, 0) / samples.length;
  console.log("[perf] SSE samples:", samples, "avg:", avg.toFixed(0), "ms");
  expect(avg).toBeLessThan(500);
});
