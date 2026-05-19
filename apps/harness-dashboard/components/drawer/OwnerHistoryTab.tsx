"use client";
import type { OwnerPromptEntry } from "@/lib/types";

interface Props {
  ownerHistory: OwnerPromptEntry[];
  onEntryClick?: (entry: OwnerPromptEntry) => void;
}

export function OwnerHistoryTab({ ownerHistory, onEntryClick }: Props) {
  if (!ownerHistory || ownerHistory.length === 0) {
    return <div className="text-gray-500">No prompt history found in progress.log.</div>;
  }
  return (
    <div className="space-y-2">
      <div className="mb-3 flex items-center gap-2">
        <span className="font-mono text-[9px] uppercase tracking-[0.2em] text-gray-500">from</span>
        <span className="rounded bg-amber-500/10 border border-amber-500/30 px-2 py-0.5 text-[10px] text-amber-300 font-mono">
          Owner
        </span>
        <span className="font-mono text-[9px] text-gray-600">→</span>
        <span className="rounded bg-cyan-400/10 border border-cyan-400/30 px-2 py-0.5 text-[10px] text-cyan-300 font-mono">
          CEO
        </span>
      </div>
      {ownerHistory.map((entry, i) => (
        <div
          key={i}
          className={`rounded border border-gray-700/60 bg-black/20 p-2 ${onEntryClick ? "cursor-pointer hover:border-cyan-400/30 hover:bg-cyan-400/5 transition-colors" : ""}`}
          onClick={onEntryClick ? () => onEntryClick(entry) : undefined}
        >
          <div className="flex items-center justify-between gap-2 mb-1">
            <span className="font-mono text-[9px] text-gray-500">{entry.ts}</span>
            <span
              className={`font-mono text-[9px] px-1.5 py-0.5 rounded ${
                entry.type === "goal"
                  ? "bg-emerald-500/15 text-emerald-300"
                  : entry.type === "hot-fix"
                  ? "bg-rose-500/15 text-rose-300"
                  : "bg-gray-500/15 text-gray-400"
              }`}
            >
              {entry.type}
            </span>
          </div>
          <p className="text-[11px] leading-relaxed text-gray-300 break-words">{entry.content}</p>
        </div>
      ))}
    </div>
  );
}
