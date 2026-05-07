import { readFileSync } from "node:fs";

export type SafeJsonResult<T> =
  | { ok: true; value: T }
  | { ok: false; reason: "missing" | "corrupt"; error?: unknown };

export function readJsonSafe<T = unknown>(filePath: string): SafeJsonResult<T> {
  let raw: string;
  try {
    raw = readFileSync(filePath, "utf8");
  } catch (error) {
    const code = (error as NodeJS.ErrnoException)?.code;
    if (code === "ENOENT") {
      return { ok: false, reason: "missing", error };
    }
    return { ok: false, reason: "corrupt", error };
  }
  try {
    const value = JSON.parse(raw) as T;
    return { ok: true, value };
  } catch (error) {
    return { ok: false, reason: "corrupt", error };
  }
}
