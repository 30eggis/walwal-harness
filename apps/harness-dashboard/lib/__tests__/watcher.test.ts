import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { watchHarness } from "../watcher";

describe("watchHarness", () => {
  let dir: string;

  beforeEach(() => {
    dir = mkdtempSync(path.join(tmpdir(), "watch-"));
    mkdirSync(path.join(dir, ".harness", "actions"), { recursive: true });
    mkdirSync(path.join(dir, ".harness", "archive"), { recursive: true });
    writeFileSync(path.join(dir, ".harness", "progress.json"), "{}");
  });

  afterEach(() => {
    rmSync(dir, { recursive: true, force: true });
  });

  it("fires onChange when progress.json is rewritten", async () => {
    const events: string[] = [];
    const handle = watchHarness(dir, (p) => events.push(p), { debounceMs: 30 });

    // Wait for chokidar's initial scan to settle.
    await new Promise((r) => setTimeout(r, 250));

    writeFileSync(
      path.join(dir, ".harness", "progress.json"),
      JSON.stringify({ updated: true })
    );

    // Wait long enough for awaitWriteFinish stabilityThreshold (100) +
    // debounce (30) + a little slack.
    await new Promise((r) => setTimeout(r, 400));

    await handle.close();
    expect(events.length).toBeGreaterThan(0);
    expect(events.some((e) => e.endsWith("progress.json"))).toBe(true);
  });

  it("close() releases the watcher cleanly", async () => {
    const handle = watchHarness(dir, () => {});
    await new Promise((r) => setTimeout(r, 100));
    await handle.close();
    // No assertion — test passes if close() resolves without throwing.
  });
});
