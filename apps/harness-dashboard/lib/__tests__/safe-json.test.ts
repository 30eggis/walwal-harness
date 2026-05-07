import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { readJsonSafe } from "../safe-json";

describe("readJsonSafe", () => {
  let dir: string;

  beforeEach(() => {
    dir = mkdtempSync(path.join(tmpdir(), "safe-json-"));
  });

  afterEach(() => {
    rmSync(dir, { recursive: true, force: true });
  });

  it("valid: returns ok with parsed value", () => {
    const file = path.join(dir, "ok.json");
    writeFileSync(file, JSON.stringify({ a: 1, b: "x" }));
    const result = readJsonSafe<{ a: number; b: string }>(file);
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.value).toEqual({ a: 1, b: "x" });
    }
  });

  it("corrupt: returns ok=false with reason='corrupt' and does not throw", () => {
    const file = path.join(dir, "broken.json");
    writeFileSync(file, "{ not json");
    const result = readJsonSafe(file);
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.reason).toBe("corrupt");
    }
  });

  it("missing: returns ok=false with reason='missing' and does not throw", () => {
    const file = path.join(dir, "absent.json");
    const result = readJsonSafe(file);
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.reason).toBe("missing");
    }
  });
});
