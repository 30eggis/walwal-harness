"use client";
import { Html } from "@react-three/drei";
import { ROOM_RECTS } from "@/lib/iso";
import type {
  ContractSnapshot,
  EvalScores,
  RoomId,
} from "@/lib/types";

interface DeptBoardProps {
  roomId: Extract<RoomId, "cto-team" | "cqo-team">;
  contract: ContractSnapshot;
  evalScores: EvalScores | null;
  passRate: number | null;
  openArchRisks?: number;
  openRegressions?: number;
  sprintVerdict?: "pending" | "PASS" | "FAIL";
}

function fmtRate(rate: number | null): string {
  if (rate === null || !Number.isFinite(rate)) return "—";
  return `${Math.round(rate * 100)}%`;
}

function fmtScore(s: number | null | undefined): string {
  if (s === null || s === undefined) return "—";
  return s.toFixed(2);
}

// Wall board for CTO/CQO rooms. CTO: contract sign-off + pass-rate. CQO:
// 5-axis eval scores + verdict + regressions.
export function DeptBoard({
  roomId,
  contract,
  evalScores,
  passRate,
  openArchRisks,
  openRegressions,
  sprintVerdict,
}: DeptBoardProps) {
  const room = ROOM_RECTS.find((r) => r.id === roomId)!;
  const cx = room.wx + room.ww / 2;
  // Mount on the back wall (wy is the north edge).
  const cz = room.wy + 0.18;
  const isCto = roomId === "cto-team";

  return (
    <Html
      position={[cx, 0.85, cz]}
      transform
      occlude={false}
      scale={0.14}
      pointerEvents="none"
      zIndexRange={[5, 0]}
    >
      <div
        data-testid={`dept-board-${roomId}`}
        className="rounded-md border border-brick-wall bg-brick-bg/95 px-3 py-2 shadow-lg text-gray-100 font-mono"
        style={{ minWidth: 240, maxWidth: 320 }}
      >
        <div className="text-[9px] uppercase tracking-widest text-gray-400">
          {isCto ? "CTO BOARD" : "CQO BOARD"}
        </div>
        <div className="mt-1 grid grid-cols-2 gap-1 text-[10px]">
          <div className="rounded bg-brick-wall/50 px-1.5 py-0.5">
            <span className="text-gray-500">sprint</span>{" "}
            <span data-testid={`board-sprint-${roomId}`}>
              {contract.sprint_number ?? "—"}
            </span>
          </div>
          <div className="rounded bg-brick-wall/50 px-1.5 py-0.5">
            <span className="text-gray-500">pass</span>{" "}
            <span data-testid={`board-pass-${roomId}`}>{fmtRate(passRate)}</span>
          </div>
          {isCto ? (
            <>
              <div className="rounded bg-brick-wall/50 px-1.5 py-0.5">
                <span className="text-gray-500">contract BE</span>{" "}
                <span
                  className={
                    contract.contract_signed.be ? "text-aura-typing" : "text-gray-500"
                  }
                >
                  {contract.contract_signed.be ? "signed" : "—"}
                </span>
              </div>
              <div className="rounded bg-brick-wall/50 px-1.5 py-0.5">
                <span className="text-gray-500">contract FE</span>{" "}
                <span
                  className={
                    contract.contract_signed.fe ? "text-aura-typing" : "text-gray-500"
                  }
                >
                  {contract.contract_signed.fe ? "signed" : "—"}
                </span>
              </div>
              <div className="rounded bg-brick-wall/50 px-1.5 py-0.5 col-span-2">
                <span className="text-gray-500">arch risks</span>{" "}
                <span
                  className={
                    (openArchRisks ?? 0) > 0
                      ? "text-aura-alert"
                      : "text-aura-typing"
                  }
                >
                  {openArchRisks ?? 0}
                </span>
              </div>
            </>
          ) : (
            <>
              <div className="rounded bg-brick-wall/50 px-1.5 py-0.5 col-span-2">
                <span className="text-gray-500">verdict</span>{" "}
                <span
                  className={
                    sprintVerdict === "PASS"
                      ? "text-aura-typing"
                      : sprintVerdict === "FAIL"
                      ? "text-aura-alert"
                      : "text-gray-300"
                  }
                >
                  {sprintVerdict ?? "pending"}
                </span>
              </div>
              <div className="rounded bg-brick-wall/50 px-1.5 py-0.5 col-span-2">
                <span className="text-gray-500">regressions</span>{" "}
                <span
                  className={
                    (openRegressions ?? 0) > 0
                      ? "text-aura-alert"
                      : "text-aura-typing"
                  }
                >
                  {openRegressions ?? 0}
                </span>
              </div>
            </>
          )}
        </div>

        {!isCto && evalScores && (
          <div
            data-testid="eval-scores"
            className="mt-1.5 grid grid-cols-5 gap-1 text-[9px] uppercase"
          >
            {(
              ["functional", "visual", "code_quality", "architecture", "security"] as const
            ).map((axis) => {
              const v = evalScores?.[axis] ?? null;
              const fail = v !== null && typeof v === "number" && v < 2.8;
              return (
                <div
                  key={axis}
                  data-testid={`eval-axis-${axis}`}
                  className={`rounded px-1 py-0.5 text-center ${
                    fail
                      ? "bg-aura-alert/30 text-aura-alert"
                      : "bg-aura-typing/20 text-aura-typing"
                  }`}
                  title={axis}
                >
                  <div className="text-[8px] tracking-wider opacity-70">
                    {axis.slice(0, 3)}
                  </div>
                  <div>{fmtScore(v)}</div>
                </div>
              );
            })}
          </div>
        )}
      </div>
    </Html>
  );
}
