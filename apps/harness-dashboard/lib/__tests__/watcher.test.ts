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
    mkdirSync(path.join(dir, ".harness", "documents"), { recursive: true });
    mkdirSync(path.join(dir, ".harness", "shared", "HR-Resource"), { recursive: true });
    writeFileSync(path.join(dir, ".harness", "progress.json"), "{}");
    writeFileSync(path.join(dir, ".harness", "shared", "hr-roster.json"), "{\"hired\":[]}");
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

  it("fires onChange when hired workers or mission documents change", async () => {
    const events: string[] = [];
    const handle = watchHarness(dir, (p) => events.push(p), { debounceMs: 30 });

    await new Promise((r) => setTimeout(r, 250));

    writeFileSync(
      path.join(dir, ".harness", "shared", "hr-roster.json"),
      JSON.stringify({ hired: [{ worker: "react-ui-worker", owner: "cto" }] })
    );
    await new Promise((r) => setTimeout(r, 300));

    mkdirSync(
      path.join(dir, ".harness", "shared", "HR-Resource", "react-ui-worker"),
      { recursive: true }
    );
    writeFileSync(
      path.join(dir, ".harness", "shared", "HR-Resource", "react-ui-worker", "SKILL.md"),
      "# React UI Worker\n"
    );
    await new Promise((r) => setTimeout(r, 300));

    mkdirSync(
      path.join(dir, ".harness", "documents", "goal-1", "cto", "workers"),
      { recursive: true }
    );
    writeFileSync(
      path.join(dir, ".harness", "documents", "goal-1", "cto", "workers", "react-ui-worker.md"),
      "## Status\nIN_PROGRESS\n"
    );

    await new Promise((r) => setTimeout(r, 500));

    await handle.close();
    expect(events.some((e) => e.endsWith("hr-roster.json"))).toBe(true);
    expect(events.some((e) => e.endsWith("SKILL.md"))).toBe(true);
    expect(events.some((e) => e.endsWith("react-ui-worker.md"))).toBe(true);
  });
});
