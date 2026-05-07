import { Wordmark } from "./Wordmark";

export function Header() {
  return (
    <header className="border-b border-brick-wall bg-brick-bg/80 backdrop-blur">
      <div className="mx-auto flex max-w-[1280px] items-center justify-between px-6 py-4">
        <div className="flex items-baseline gap-4">
          <Wordmark />
          <span className="hidden text-xs text-gray-400 sm:inline">
            walwal-harness 라이브 운영 대시보드
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
