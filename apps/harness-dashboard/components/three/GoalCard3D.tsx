"use client";
import { Html } from "@react-three/drei";
import type {
  ContractSnapshot,
  EscalationEntry,
  GoalCard,
} from "@/lib/types";
import { ROOM_RECTS } from "@/lib/iso";

interface GoalCard3DProps {
  goal: GoalCard | null;
  lang?: "ko" | "en";
  contract?: ContractSnapshot;
  escalations?: EscalationEntry[];
}

const PIPELINE_TONE: Record<string, string> = {
  FULLSTACK: "bg-aura-typing/30 text-aura-typing",
  "FE-ONLY": "bg-aura-talking/30 text-aura-talking",
  "BE-ONLY": "bg-aura-talking/30 text-aura-talking",
  META_REFACTOR: "bg-aura-alert/20 text-aura-alert",
};

// Mounted on the back wall of the CEO room. The Html node renders a card-like
// DOM element so long titles/descriptions stay readable instead of being
// crammed into a 3D text mesh that would otherwise need a font load.
//
// CEO wall now also carries the pipeline + sprint badge and an open-escalation
// counter — these are CEO-only signals (Owner-facing). Putting them here keeps
// the doctrine "Owner ↔ Dispatcher only" intuition visible.
export function GoalCard3D({
  goal,
  lang = "ko",
  contract,
  escalations = [],
}: GoalCard3DProps) {
  const ceo = ROOM_RECTS.find((r) => r.id === "ceo")!;
  const cx = ceo.wx + ceo.ww / 2;
  const cz = ceo.wy + 0.15;

  const pipelineTone = contract?.pipeline
    ? PIPELINE_TONE[contract.pipeline] ?? "bg-gray-500/30 text-gray-300"
    : "bg-gray-500/30 text-gray-400";

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
        style={{ minWidth: 240, maxWidth: 320 }}
      >
        {goal ? (
          <>
            <div className="flex items-center justify-between gap-2">
              <div className="text-[9px] uppercase tracking-widest text-aura-typing">
                GOAL
              </div>
              <div className="flex items-center gap-1">
                {contract?.sprint_number !== null && contract?.sprint_number !== undefined && (
                  <span
                    data-testid="ceo-sprint-pill"
                    className="rounded bg-aura-typing/20 px-1 py-0.5 text-[9px] uppercase text-aura-typing"
                  >
                    sprint {contract.sprint_number}
                  </span>
                )}
                {contract?.pipeline && (
                  <span
                    data-testid="ceo-pipeline-pill"
                    className={`rounded px-1 py-0.5 text-[9px] uppercase ${pipelineTone}`}
                  >
                    {contract.pipeline}
                  </span>
                )}
              </div>
            </div>
            <div className="text-[14px] leading-tight font-semibold">
              {goal.title}
            </div>
            {goal.description_truncated && (
              <div className="mt-1 text-[10px] leading-snug text-gray-300">
                {goal.description_truncated}
              </div>
            )}
            <div className="mt-1 flex items-center justify-between">
              {typeof goal.adherence === "number" ? (
                <span className="text-[9px] text-gray-500">
                  adherence {(goal.adherence * 100).toFixed(0)}%
                </span>
              ) : (
                <span className="text-[9px] text-gray-600">adherence —</span>
              )}
              {escalations.length > 0 && (
                <span
                  data-testid="ceo-escalation-pill"
                  className="rounded bg-aura-alert/30 px-1.5 py-0.5 text-[9px] uppercase text-aura-alert"
                >
                  ↑ {escalations.length} escalation{escalations.length === 1 ? "" : "s"}
                </span>
              )}
            </div>
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
