import { existsSync } from "node:fs";
import path from "node:path";

// Resolves the directory that contains `.harness/`. Search order:
//   1. env HARNESS_ROOT (absolute path) — escape hatch for tests/CI.
//   2. Walk up from cwd until we find a `.harness/` directory.
//   3. Fall back to cwd (caller will see errorBanner via readHarnessState).
export function resolveHarnessRoot(start: string = process.cwd()): string {
  const fromEnv = process.env.HARNESS_ROOT;
  if (fromEnv && existsSync(path.join(fromEnv, ".harness"))) {
    return fromEnv;
  }
  let current = path.resolve(start);
  while (true) {
    if (existsSync(path.join(current, ".harness"))) return current;
    const parent = path.dirname(current);
    if (parent === current) return start;
    current = parent;
  }
}
