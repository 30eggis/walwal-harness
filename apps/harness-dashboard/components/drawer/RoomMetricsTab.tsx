"use client";
import type { RoomState } from "@/lib/types";

interface RoomMetricsTabProps {
  room: RoomState;
}

const METRIC_LABEL: Record<string, string> = {
  sprint_number: "Cycle",
  last_review: "Last review",
  last_audit: "Last audit",
  last_check: "Last check",
  sprint_verdict: "Verdict",
  open_alerts: "Open alerts",
  open_arch_risks: "Open arch risks",
  open_regressions: "Open regressions",
  cadence: "Cadence",
  next_scheduled: "Next meeting",
  active_tracks: "Active tracks",
  active_hypothesis: "Active hypothesis",
  active_workers: "Active workers",
  open_incidents: "Open incidents",
  pass_rate: "Pass rate",
  contract_signed: "Contract signed",
  eval_scores: "Eval scores",
};

function fmt(key: string, value: unknown): string {
  if (value === null || value === undefined || value === "") return "—";
  if (key === "pass_rate" && typeof value === "number") {
    return `${Math.round(value * 100)}%`;
  }
  if (key === "contract_signed" && typeof value === "object" && value) {
    const v = value as { be?: boolean; fe?: boolean };
    const parts = [v.be ? "BE" : null, v.fe ? "FE" : null].filter(Boolean);
    return parts.length ? parts.join("·") : "—";
  }
  if (key === "eval_scores" && typeof value === "object" && value) {
    const v = value as Record<string, number | null | undefined>;
    const parts = Object.entries(v)
      .filter(([, s]) => typeof s === "number")
      .map(([k, s]) => `${k.slice(0, 3)} ${(s as number).toFixed(1)}`);
    return parts.length ? parts.join(" · ") : "—";
  }
  if (typeof value === "object") return JSON.stringify(value);
  return String(value);
}

export function RoomMetricsTab({ room }: RoomMetricsTabProps) {
  const metrics = room.metrics ?? {};
  const entries = Object.entries(metrics);
  return (
    <div className="space-y-3">
      <div className="text-gray-400 text-[11px]">
        {room.label_ko} <span className="text-gray-600">({room.label_en})</span>
      </div>
      {entries.length === 0 ? (
        <div className="text-gray-500">No metrics available for this room.</div>
      ) : (
        <div className="grid grid-cols-2 gap-2">
          {entries.map(([k, v]) => (
            <div
              key={k}
              data-testid={`metric-${k}`}
              className="rounded border border-brick-wall bg-brick-wall/30 px-2 py-1.5"
            >
              <div className="text-[10px] uppercase tracking-wider text-gray-500">
                {METRIC_LABEL[k] ?? k}
              </div>
              <div className="text-[12px] text-gray-100">{fmt(k, v)}</div>
            </div>
          ))}
        </div>
      )}
      {room.seatLayout && (
        <div className="rounded border border-brick-wall bg-brick-wall/30 px-2 py-1.5">
          <div className="text-[10px] uppercase tracking-wider text-gray-500">
            Seats
          </div>
          <div className="text-[12px] text-gray-100">
            {room.seatLayout.occupants.length} / {room.seatLayout.seats}
            {room.seatLayout.overflow > 0 && (
              <span className="text-aura-alert"> +{room.seatLayout.overflow}</span>
            )}
          </div>
        </div>
      )}
    </div>
  );
}
