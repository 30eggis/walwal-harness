"use client";
import type { HypothesisEntry } from "@/lib/types";

const VERDICT_TONE: Record<string, string> = {
  pending: "border-aura-talking/40 bg-aura-talking/10 text-aura-talking",
  valid: "border-aura-typing/40 bg-aura-typing/10 text-aura-typing",
  invalid: "border-aura-alert/40 bg-aura-alert/10 text-aura-alert",
};

interface HypothesisTabProps {
  hypothesis: HypothesisEntry[];
}

export function HypothesisTab({ hypothesis }: HypothesisTabProps) {
  if (hypothesis.length === 0) {
    return (
      <div className="text-gray-500" data-testid="hypothesis-empty">
        No active hypothesis.
      </div>
    );
  }
  return (
    <ul className="space-y-2" data-testid="hypothesis-list">
      {hypothesis.map((h) => (
        <li
          key={h.id}
          data-testid={`hypothesis-row-${h.id}`}
          className={`rounded border px-2 py-1.5 ${
            VERDICT_TONE[h.verdict] ?? VERDICT_TONE.pending
          }`}
        >
          <div className="flex items-center justify-between text-[11px]">
            <span className="font-semibold">{h.id}</span>
            <span className="uppercase tracking-wider text-[9px]">{h.verdict}</span>
          </div>
          <div className="mt-1 text-[11px] text-gray-100">{h.brief}</div>
          {h.ts && <div className="mt-0.5 text-[9px] text-gray-500">{h.ts}</div>}
        </li>
      ))}
    </ul>
  );
}
