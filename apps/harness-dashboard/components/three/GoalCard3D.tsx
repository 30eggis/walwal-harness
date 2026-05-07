"use client";
import { Html } from "@react-three/drei";
import type { GoalCard } from "@/lib/types";
import { ROOM_RECTS } from "@/lib/iso";

interface GoalCard3DProps {
  goal: GoalCard | null;
  lang?: "ko" | "en";
}

// Mounted on the back wall of the CEO room. The Html node renders a card-like
// DOM element so long titles/descriptions stay readable instead of being
// crammed into a 3D text mesh that would otherwise need a font load.
export function GoalCard3D({ goal, lang = "ko" }: GoalCard3DProps) {
  const ceo = ROOM_RECTS.find((r) => r.id === "ceo")!;
  const cx = ceo.wx + ceo.ww / 2;
  // North wall is at z = ceo.wy. Push slightly inside so the card faces the camera.
  const cz = ceo.wy + 0.15;

  return (
    <Html
      position={[cx, 0.85, cz]}
      transform
      occlude={false}
      scale={0.16}
      pointerEvents="none"
      zIndexRange={[5, 0]}
    >
      <div
        data-testid="goal-card"
        className="rounded-md border border-aura-typing/60 bg-brick-bg/95 px-3 py-2 shadow-lg text-gray-100 font-mono"
        style={{ minWidth: 220, maxWidth: 320 }}
      >
        {goal ? (
          <>
            <div className="text-[9px] uppercase tracking-widest text-aura-typing">
              GOAL
            </div>
            <div className="text-[14px] leading-tight font-semibold">
              {goal.title}
            </div>
            {goal.description_truncated && (
              <div className="mt-1 text-[10px] leading-snug text-gray-300">
                {goal.description_truncated}
              </div>
            )}
            {typeof goal.adherence === "number" && (
              <div className="mt-1 text-[9px] text-gray-500">
                adherence {(goal.adherence * 100).toFixed(0)}%
              </div>
            )}
          </>
        ) : (
          <>
            <div className="text-[9px] uppercase tracking-widest text-gray-500">
              GOAL
            </div>
            <div className="text-[12px] text-gray-500">
              {lang === "en" ? "No active goal" : "활성 GOAL 없음"}
            </div>
          </>
        )}
      </div>
    </Html>
  );
}
