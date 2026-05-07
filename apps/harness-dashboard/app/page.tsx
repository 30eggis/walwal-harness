import { readHarnessState } from "@/lib/harness-state";
import { resolveHarnessRoot } from "@/lib/harness-root";
import { Scene } from "@/components/Scene";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export default function Page() {
  const snapshot = readHarnessState(resolveHarnessRoot());
  const banner = snapshot.errorBanner;

  return (
    <main className="min-h-[100dvh]">
      {banner && (
        <div
          role="alert"
          data-testid="error-banner"
          className={`mx-auto max-w-[1280px] mt-4 px-4 py-3 rounded border text-sm ${
            banner.level === "error"
              ? "border-aura-alert/60 bg-aura-alert/10 text-aura-alert"
              : "border-aura-talking/60 bg-aura-talking/10 text-aura-talking"
          }`}
        >
          <div>{banner.message_ko}</div>
          <div className="opacity-60 text-xs mt-1">{banner.message_en}</div>
        </div>
      )}
      <Scene snapshot={snapshot} />
      <footer className="mx-auto max-w-[1280px] px-6 pb-8 text-xs text-gray-500 font-mono flex items-center justify-between">
        <span>Sprint 1 / Phase C-1 — Foundation</span>
        <span data-testid="snapshot-ts">{snapshot.ts}</span>
      </footer>
    </main>
  );
}
