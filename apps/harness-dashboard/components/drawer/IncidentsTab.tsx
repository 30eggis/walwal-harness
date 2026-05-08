"use client";
import type { IncidentEntry } from "@/lib/types";

const SEVERITY_TONE: Record<string, string> = {
  low: "border-aura-idle/40 bg-aura-idle/10 text-gray-300",
  medium: "border-aura-talking/40 bg-aura-talking/10 text-aura-talking",
  high: "border-aura-alert/40 bg-aura-alert/10 text-aura-alert",
  critical: "border-aura-alert bg-aura-alert/30 text-aura-alert",
};

interface IncidentsTabProps {
  incidents: IncidentEntry[];
}

export function IncidentsTab({ incidents }: IncidentsTabProps) {
  if (incidents.length === 0) {
    return (
      <div className="text-gray-500" data-testid="incidents-empty">
        No open incidents.
      </div>
    );
  }
  return (
    <ul className="space-y-2" data-testid="incidents-list">
      {incidents.map((it) => (
        <li
          key={it.id}
          data-testid={`incident-${it.id}`}
          className={`rounded border px-2 py-1.5 ${
            SEVERITY_TONE[it.severity] ?? SEVERITY_TONE.medium
          }`}
        >
          <div className="flex items-center justify-between text-[11px]">
            <span className="font-semibold">{it.id}</span>
            <span className="uppercase tracking-wider text-[9px]">
              {it.severity}
            </span>
          </div>
          <div className="text-[10px] opacity-80">dept: {it.dept}</div>
          {it.message && (
            <div className="mt-1 text-[11px] text-gray-100">{it.message}</div>
          )}
          {it.ts && (
            <div className="mt-0.5 text-[9px] text-gray-500">{it.ts}</div>
          )}
        </li>
      ))}
    </ul>
  );
}
