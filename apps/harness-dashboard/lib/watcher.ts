import chokidar from "chokidar";
import path from "node:path";

export interface WatchHandle {
  close(): Promise<void>;
}

export interface WatchOptions {
  /** Coalesce rapid-fire events within this window (ms). */
  debounceMs?: number;
}

// Watches the .harness/ directory for changes that affect the dashboard
// snapshot — progress.json (state), progress.log (activity), actions/* (sprint
// artifacts), archive/* (sprint history).
export function watchHarness(
  rootDir: string,
  onChange: (changedPath: string) => void,
  opts: WatchOptions = {}
): WatchHandle {
  const debounceMs = opts.debounceMs ?? 50;
  const harnessDir = path.join(rootDir, ".harness");
  const watcher = chokidar.watch(
    [
      path.join(harnessDir, "progress.json"),
      path.join(harnessDir, "progress.log"),
      path.join(harnessDir, "actions"),
      path.join(harnessDir, "archive"),
    ],
    {
      ignoreInitial: true,
      awaitWriteFinish: { stabilityThreshold: 100, pollInterval: 50 },
      // Don't crawl deeply into archive — recent dirs only.
      depth: 4,
    }
  );

  let pending: NodeJS.Timeout | null = null;
  let lastPath = "";

  const fire = (changedPath: string) => {
    lastPath = changedPath;
    if (pending) return;
    pending = setTimeout(() => {
      pending = null;
      onChange(lastPath);
    }, debounceMs);
  };

  watcher.on("add", fire).on("change", fire).on("unlink", fire);

  return {
    async close() {
      if (pending) {
        clearTimeout(pending);
        pending = null;
      }
      await watcher.close();
    },
  };
}
