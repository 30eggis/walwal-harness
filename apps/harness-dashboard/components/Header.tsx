import path from "node:path";
import { Wordmark } from "./Wordmark";
import { resolveHarnessRoot } from "@/lib/harness-root";

export function Header() {
  const root = resolveHarnessRoot();
  const projectName = path.basename(root);
  return (
    <header className="border-b border-brick-wall bg-brick-bg/80 backdrop-blur">
      <div className="mx-auto flex max-w-[1280px] items-center justify-between px-6 py-4">
        <div className="flex items-baseline gap-4">
          <Wordmark />
          <span className="hidden items-baseline gap-2 sm:inline-flex">
            <span
              className="rounded bg-brick-wall/40 px-2 py-0.5 font-mono text-xs font-semibold text-amber-300"
              title={root}
            >
              {projectName}
            </span>
            <span className="text-xs text-gray-400">walwal-harness 라이브 운영 대시보드</span>
          </span>
        </div>
        <nav className="flex items-center gap-3 text-xs font-mono text-gray-500">
          <span className="inline-flex items-center gap-1">
            <span className="size-2 rounded-full bg-aura-idle" /> idle
          </span>
          <span className="inline-flex items-center gap-1">
            <span className="size-2 rounded-full bg-aura-typing" /> typing
          </span>
          <span className="inline-flex items-center gap-1">
            <span className="size-2 rounded-full bg-aura-talking" /> talking
          </span>
          <span className="inline-flex items-center gap-1">
            <span className="size-2 rounded-full bg-aura-alert" /> alert
          </span>
        </nav>
      </div>
    </header>
  );
}
