"use client";
import { useState } from "react";
import type { MissionDoc } from "@/lib/types";

interface Props {
  missions: MissionDoc[];
  role: "ceo" | "cto" | "cqo" | "coo" | "cdo" | "ops" | "worker";
  workerName?: string;
  fromLabel: string;
  toLabel: string;
}

export function MissionDocTab({ missions, role, workerName, fromLabel, toLabel }: Props) {
  const [selectedIdx, setSelectedIdx] = useState(0);
  const mission = missions[selectedIdx];

  if (!missions.length) {
    return (
      <div className="text-gray-500">
        No mission documents found in .harness/documents/
      </div>
    );
  }

  const getContent = (m: MissionDoc): string | null => {
    if (role === "worker" && workerName) {
      return m.workers.find((w) => w.name === workerName)?.content ?? null;
    }
    const cxxRole = role as Exclude<typeof role, "worker">;
    return m[cxxRole] ?? null;
  };

  const content = getContent(mission);

  return (
    <div className="space-y-3">
      {/* Routing breadcrumb */}
      <div className="flex items-center gap-2 flex-wrap">
        <span className="font-mono text-[9px] uppercase tracking-[0.2em] text-gray-500">flow</span>
        <span className="rounded bg-amber-500/10 border border-amber-500/30 px-2 py-0.5 text-[10px] text-amber-300 font-mono">
          {fromLabel}
        </span>
        <span className="text-gray-600">→</span>
        <span className="rounded border border-cyan-400/30 bg-cyan-400/10 px-2 py-0.5 text-[10px] text-cyan-300 font-mono">
          this
        </span>
        <span className="text-gray-600">→</span>
        <span className="rounded border border-gray-600/40 bg-gray-800/30 px-2 py-0.5 text-[10px] text-gray-400 font-mono">
          {toLabel}
        </span>
      </div>

      {/* Mission selector */}
      <div className="flex gap-1 flex-wrap">
        {missions.slice(0, 6).map((m, i) => (
          <button
            key={m.missionId}
            type="button"
            onClick={() => setSelectedIdx(i)}
            className={`rounded px-2 py-1 font-mono text-[9px] transition-colors ${
              i === selectedIdx
                ? "bg-cyan-400/15 text-cyan-300 border border-cyan-400/30"
                : "text-gray-500 hover:text-gray-300 border border-transparent"
            }`}
          >
            {i === 0 ? "current" : m.missionId.slice(0, 16)}
          </button>
        ))}
      </div>

      {/* Mission ID */}
      <div className="font-mono text-[10px] text-gray-500">
        {mission.missionId} · {new Date(mission.ts).toLocaleDateString()}
      </div>

      {/* Document content */}
      {!content ? (
        <div className="text-gray-500 text-[11px]">
          No {role} document for this mission.
          <div className="mt-1 text-[10px] text-gray-600">
            Present: {mission.cxxPresent.join(", ") || "none"}
          </div>
        </div>
      ) : (
        <pre className="whitespace-pre-wrap break-words text-[11px] leading-relaxed text-gray-200 rounded border border-gray-700/60 bg-black/20 p-3 max-h-[60vh] overflow-y-auto">
          {/* Strip YAML frontmatter for cleaner display */}
          {content.replace(/^---[\s\S]*?---\n/, "")}
        </pre>
      )}
    </div>
  );
}
