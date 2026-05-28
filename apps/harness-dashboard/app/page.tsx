import { readHarnessState } from "@/lib/harness-state";
import { resolveHarnessRoot } from "@/lib/harness-root";
import { Scene } from "@/components/Scene";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export default function Page() {
  const snapshot = readHarnessState(resolveHarnessRoot());
  const banner = snapshot.errorBanner;

  return (
    <main className="h-[100dvh]">
      {banner && (
        <div
          role="alert"
          data-testid="error-banner"
          className={`mx-3 mt-2 rounded border px-3 py-2 text-xs ${
            banner.level === "error"
              ? "border-aura-alert/60 bg-aura-alert/10 text-aura-alert"
              : "border-aura-talking/60 bg-aura-talking/10 text-aura-talking"
          }`}
        >
          <div>{banner.message_ko}</div>
          <div className="mt-1 text-[10px] opacity-60">{banner.message_en}</div>
        </div>
      )}
      <Scene snapshot={snapshot} />
    </main>
  );
}
