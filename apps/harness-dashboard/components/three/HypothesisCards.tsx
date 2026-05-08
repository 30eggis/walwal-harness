"use client";
import { Html } from "@react-three/drei";
import { ROOM_RECTS } from "@/lib/iso";
import type { HypothesisEntry } from "@/lib/types";

interface HypothesisCardsProps {
  hypothesis: HypothesisEntry[];
}

const VERDICT_TONE: Record<string, string> = {
  pending: "bg-aura-talking/30 text-aura-talking border-aura-talking/40",
  valid: "bg-aura-typing/30 text-aura-typing border-aura-typing/40",
  invalid: "bg-aura-alert/30 text-aura-alert border-aura-alert/40",
};

// Stack of cards on the COO room wall — each card is one hypothesis from the
// COO Hypothesis Cell. Limited to the latest 3 to keep the wall readable.
export function HypothesisCards({ hypothesis }: HypothesisCardsProps) {
  const room = ROOM_RECTS.find((r) => r.id === "coo")!;
  const cx = room.wx + room.ww / 2;
  const cz = room.wy + 0.18;

  if (hypothesis.length === 0) return null;
  const visible = hypothesis.slice(0, 3);
  const overflow = hypothesis.length - visible.length;

  return (
    <Html
      position={[cx, 0.75, cz]}
      transform
      occlude={false}
      scale={0.12}
      pointerEvents="none"
      zIndexRange={[5, 0]}
    >
      <div
        data-testid="hypothesis-cards"
        className="flex flex-col gap-1 rounded-md border border-brick-wall bg-brick-bg/95 px-2 py-2 shadow-lg font-mono"
        style={{ minWidth: 220, maxWidth: 260 }}
      >
        <div className="text-[9px] uppercase tracking-widest text-gray-400">
          COO HYPOTHESIS CELL
        </div>
        {visible.map((h) => (
          <div
            key={h.id}
            data-testid={`hypothesis-${h.id}`}
            className={`rounded border px-1.5 py-0.5 text-[10px] ${
              VERDICT_TONE[h.verdict]
            }`}
          >
            <div className="flex items-center justify-between">
              <span className="opacity-70 tracking-wider">{h.id}</span>
              <span className="uppercase tracking-wide text-[9px]">
                {h.verdict}
              </span>
            </div>
            <div className="text-[10px] leading-tight text-gray-100 truncate">
              {h.brief}
            </div>
          </div>
        ))}
        {overflow > 0 && (
          <div className="text-[9px] text-gray-500 text-right">
            +{overflow} more
          </div>
        )}
      </div>
    </Html>
  );
}
