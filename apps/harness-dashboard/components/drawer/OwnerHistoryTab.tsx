"use client";
import type { MissionDoc, OwnerPromptEntry } from "@/lib/types";

interface Props {
  ownerHistory: OwnerPromptEntry[];
  mission?: MissionDoc | null;
  onEntryClick?: (entry: OwnerPromptEntry) => void;
}

function extractSectionText(content: string, ...headings: string[]): string | null {
  const body = content.replace(/^---[\s\S]*?---\n+/, "");
  for (const heading of headings) {
    const pattern = new RegExp(`^##\\s+${heading.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}`, "m");
    const match = pattern.exec(body);
    if (!match) continue;
    const start = match.index + match[0].length;
    const rest = body.slice(start);
    const lines = rest.split("\n");
    const snippet: string[] = [];
    for (const line of lines) {
      if (line.startsWith("## ") || line.startsWith("# ")) break;
      const trimmed = line.trim();
      if (trimmed && !trimmed.startsWith("---")) snippet.push(trimmed);
      if (snippet.length >= 6) break;
    }
    const result = snippet.join("\n").slice(0, 600);
    if (result) return result;
  }
  return null;
}

export function OwnerHistoryTab({ ownerHistory, mission, onEntryClick }: Props) {
  // Mission-specific view
  if (mission) {
    const requestText = mission.ceo
      ? extractSectionText(mission.ceo, "Owner 요청 요약", "Owner Request")
      : null;

    // Find closest owner history entry by timestamp
    let closestEntry: OwnerPromptEntry | null = null;
    if (ownerHistory.length > 0) {
      const missionTime = Date.parse(mission.ts);
      let closestDiff = Infinity;
      for (const entry of ownerHistory) {
        const t = Date.parse(entry.ts);
        if (!Number.isNaN(t)) {
          const diff = Math.abs(t - missionTime);
          if (diff < closestDiff) { closestDiff = diff; closestEntry = entry; }
        }
      }
    }

    return (
      <div className="space-y-3">
        <div className="flex items-center gap-2 mb-3">
          <span className="font-mono text-[9px] uppercase tracking-[0.2em] text-gray-500">from</span>
          <span className="rounded bg-amber-500/10 border border-amber-500/30 px-2 py-0.5 text-[10px] text-amber-300 font-mono">
            Owner
          </span>
          <span className="font-mono text-[9px] text-gray-600">→</span>
          <span className="rounded bg-cyan-400/10 border border-cyan-400/30 px-2 py-0.5 text-[10px] text-cyan-300 font-mono">
            CEO
          </span>
          <span className="ml-auto font-mono text-[9px] text-gray-600 truncate max-w-[160px]">
            {mission.missionId}
          </span>
        </div>

        {/* CEO's summary of owner request */}
        {requestText && (
          <div className="rounded border border-cyan-400/20 bg-cyan-400/5 p-2.5">
            <div className="font-mono text-[9px] uppercase tracking-[0.15em] text-cyan-400/60 mb-1.5">
              CEO가 정리한 Owner 요청
            </div>
            <p className="text-[11px] leading-relaxed text-gray-300 whitespace-pre-line">
              {requestText}
            </p>
          </div>
        )}

        {/* Closest matching progress.log entry */}
        {closestEntry && (
          <div
            className={`rounded border border-gray-700/60 bg-black/20 p-2 ${onEntryClick ? "cursor-pointer hover:border-amber-400/30 hover:bg-amber-400/5 transition-colors" : ""}`}
            onClick={onEntryClick ? () => onEntryClick(closestEntry!) : undefined}
          >
            <div className="flex items-center justify-between gap-2 mb-1">
              <span className="font-mono text-[9px] text-gray-500">progress.log</span>
              <div className="flex items-center gap-1.5">
                <span className="font-mono text-[9px] text-gray-600">{closestEntry.ts}</span>
                <span
                  className={`font-mono text-[9px] px-1.5 py-0.5 rounded ${
                    closestEntry.type === "goal"
                      ? "bg-emerald-500/15 text-emerald-300"
                      : closestEntry.type === "submission"
                      ? "bg-sky-500/15 text-sky-300"
                      : closestEntry.type === "hot-fix"
                      ? "bg-rose-500/15 text-rose-300"
                      : "bg-gray-500/15 text-gray-400"
                  }`}
                >
                  {closestEntry.type}
                </span>
              </div>
            </div>
            <p className="text-[11px] leading-relaxed text-gray-400 break-words">{closestEntry.content}</p>
          </div>
        )}

        {!requestText && !closestEntry && (
          <div className="text-gray-500 text-xs">No owner prompt found for this mission.</div>
        )}
      </div>
    );
  }

  // All-history fallback (no mission selected)
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
                  : entry.type === "submission"
                  ? "bg-sky-500/15 text-sky-300"
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
