"use client";
import { useState } from "react";
import type { GotchaEntry } from "@/lib/types";
import { MarkdownView } from "@/lib/markdown";

interface Props {
  gotchas: GotchaEntry[];
}

export function GotchasTab({ gotchas }: Props) {
  const [selected, setSelected] = useState<GotchaEntry | null>(null);
  const [search, setSearch] = useState("");

  if (selected) {
    return (
      <div className="space-y-3">
        <button
          type="button"
          onClick={() => setSelected(null)}
          className="flex items-center gap-1.5 font-mono text-[10px] text-cyan-400/70 hover:text-cyan-300 transition-colors"
        >
          ← Back
        </button>
        <div className="font-mono text-[10px] text-gray-500">
          .harness/gotchas/{selected.id}.md
        </div>
        <MarkdownView source={selected.content} />
      </div>
    );
  }

  const filtered = search.trim()
    ? gotchas.filter(
        (g) =>
          g.title.toLowerCase().includes(search.toLowerCase()) ||
          g.id.toLowerCase().includes(search.toLowerCase()) ||
          g.tags.some((t) => t.toLowerCase().includes(search.toLowerCase()))
      )
    : gotchas;

  if (gotchas.length === 0) {
    return <div className="text-gray-500 text-xs">No gotchas found in .harness/gotchas/</div>;
  }

  return (
    <div className="space-y-2">
      {/* Search */}
      <input
        type="text"
        value={search}
        onChange={(e) => setSearch(e.target.value)}
        placeholder="Search gotchas…"
        className="w-full rounded border border-gray-700/60 bg-black/30 px-2.5 py-1.5 font-mono text-[11px] text-gray-300 placeholder-gray-600 focus:border-cyan-400/40 focus:outline-none"
      />

      <div className="font-mono text-[9px] text-gray-600 px-0.5">
        {filtered.length} / {gotchas.length} gotchas
      </div>

      <div className="space-y-1.5">
        {filtered.map((g) => (
          <button
            key={g.id}
            type="button"
            onClick={() => setSelected(g)}
            className="w-full text-left rounded border border-gray-700/50 bg-black/20 px-3 py-2 hover:border-amber-400/30 hover:bg-amber-400/5 transition-colors group"
          >
            <div className="font-mono text-[11px] text-gray-200 group-hover:text-amber-200 leading-snug">
              {g.title}
            </div>
            <div className="font-mono text-[9px] text-gray-600 mt-0.5">{g.id}</div>
            {g.tags.length > 0 && (
              <div className="flex flex-wrap gap-1 mt-1">
                {g.tags.slice(0, 5).map((tag) => (
                  <span
                    key={tag}
                    className="rounded bg-gray-700/40 px-1.5 py-0.5 font-mono text-[8px] text-gray-500"
                  >
                    {tag}
                  </span>
                ))}
              </div>
            )}
          </button>
        ))}
      </div>
    </div>
  );
}
