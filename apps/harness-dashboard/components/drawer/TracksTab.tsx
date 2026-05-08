"use client";
import type { ParallelTrack } from "@/lib/types";

const STATUS_TONE: Record<string, string> = {
  dispatched: "border-aura-talking/40 bg-aura-talking/10 text-aura-talking",
  in_progress: "border-aura-typing/40 bg-aura-typing/10 text-aura-typing",
  joined: "border-aura-typing/60 bg-aura-typing/20 text-aura-typing",
  blocked: "border-aura-alert/40 bg-aura-alert/10 text-aura-alert",
};

interface TracksTabProps {
  tracks: ParallelTrack[];
}

export function TracksTab({ tracks }: TracksTabProps) {
  if (tracks.length === 0) {
    return (
      <div className="text-gray-500" data-testid="tracks-empty">
        No parallel tracks active.
      </div>
    );
  }
  return (
    <ul className="space-y-2" data-testid="tracks-list">
      {tracks.map((t) => (
        <li
          key={t.id}
          data-testid={`track-row-${t.id}`}
          className={`rounded border px-2 py-1.5 ${
            STATUS_TONE[t.status] ?? STATUS_TONE.dispatched
          }`}
        >
          <div className="flex items-center justify-between text-[11px]">
            <span className="font-semibold">{t.id}</span>
            <span className="uppercase tracking-wider text-[9px]">{t.status}</span>
          </div>
          <div className="mt-1 text-[10px] text-gray-300">
            {t.from_meeting} → {t.to_dept} ({t.to_room})
          </div>
          {t.label && (
            <div className="mt-0.5 text-[11px] text-gray-100">{t.label}</div>
          )}
        </li>
      ))}
    </ul>
  );
}
