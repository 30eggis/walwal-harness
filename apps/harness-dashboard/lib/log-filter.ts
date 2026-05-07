import { readFileSync, existsSync } from "node:fs";
import path from "node:path";

export interface LogFilterOptions {
  agentId?: string;
  limit?: number;
}

export function readProgressLog(rootDir: string, opts: LogFilterOptions = {}): string[] {
  const limit = opts.limit ?? 50;
  const file = path.join(rootDir, ".harness", "progress.log");
  if (!existsSync(file)) return [];
  let raw: string;
  try {
    raw = readFileSync(file, "utf8");
  } catch {
    return [];
  }
  const lines = raw.split("\n").filter((l) => l.length > 0);
  const filtered = opts.agentId ? lines.filter((l) => l.includes(opts.agentId!)) : lines;
  // Most-recent-first (we tail from the bottom).
  return filtered.slice(-limit);
}
