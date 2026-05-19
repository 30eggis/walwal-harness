"use client";
import { useState } from "react";
import type { MissionDoc, OwnerPromptEntry } from "@/lib/types";
import { MarkdownView } from "@/lib/markdown";

type DocView = "overview" | "ceo" | "cto" | "cqo" | "coo" | "cdo" | "ops" | string;

interface Props {
  mission: MissionDoc | null;
  ownerHistory: OwnerPromptEntry[];
}

// ---------------------------------------------------------------------------
// Helper: extract first 2-3 non-empty lines from a ## section (max 200 chars)
// ---------------------------------------------------------------------------
function extractSection(content: string, heading: string): string | null {
  // Strip frontmatter
  const body = content.replace(/^---[\s\S]*?---\n+/, "");
  const pattern = new RegExp(`^##\\s+${heading.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}`, "m");
  const match = pattern.exec(body);
  if (!match) return null;

  const start = match.index + match[0].length;
  const rest = body.slice(start);
  const lines = rest.split("\n");
  const snippet: string[] = [];

  for (const line of lines) {
    if (line.startsWith("## ") || line.startsWith("# ")) break;
    const trimmed = line.trim();
    if (trimmed && !trimmed.startsWith("---")) {
      snippet.push(trimmed);
    }
    if (snippet.length >= 3) break;
  }

  const result = snippet.join(" · ").slice(0, 200);
  return result || null;
}

// ---------------------------------------------------------------------------
// Chip helpers
// ---------------------------------------------------------------------------
function StepChip({
  role,
  label,
  onClick,
}: {
  role: string;
  label: string;
  onClick?: () => void;
}) {
  const colorMap: Record<string, string> = {
    owner: "bg-amber-500/15 text-amber-300 border-amber-500/30",
    ceo: "bg-cyan-400/15 text-cyan-300 border-cyan-400/30",
    coo: "bg-emerald-500/15 text-emerald-300 border-emerald-500/30",
    cdo: "bg-purple-500/15 text-purple-300 border-purple-500/30",
    cto: "bg-blue-400/15 text-blue-300 border-blue-400/30",
    cqo: "bg-amber-400/15 text-amber-300 border-amber-400/30",
    ops: "bg-rose-400/15 text-rose-300 border-rose-400/30",
    worker: "bg-gray-500/15 text-gray-300 border-gray-500/30",
  };
  const cls = colorMap[role] ?? "bg-gray-600/15 text-gray-400 border-gray-600/30";
  return (
    <span
      className={`inline-flex items-center gap-1 rounded border px-1.5 py-0.5 font-mono text-[9px] ${cls} ${onClick ? "cursor-pointer hover:opacity-80" : ""}`}
      onClick={onClick}
    >
      {label}
    </span>
  );
}

// ---------------------------------------------------------------------------
// DocRow: one step in the flow tree
// ---------------------------------------------------------------------------
function DocRow({
  step,
  roleLabel,
  roleKey,
  snippet,
  status,
  onViewDoc,
  ts,
}: {
  step: number;
  roleLabel: string;
  roleKey: string;
  snippet?: string | null;
  status?: string | null;
  onViewDoc?: () => void;
  ts?: string;
}) {
  return (
    <div className="relative pl-4 border-l border-gray-700/40 ml-2 space-y-1">
      <div className="flex items-center justify-between gap-2">
        <div className="flex items-center gap-1.5">
          <span className="font-mono text-[9px] text-gray-600">{step}</span>
          <StepChip role={roleKey} label={roleLabel} />
          {ts && (
            <span className="font-mono text-[9px] text-gray-600">[{ts}]</span>
          )}
        </div>
        {onViewDoc && (
          <button
            type="button"
            onClick={onViewDoc}
            className="shrink-0 font-mono text-[9px] text-cyan-400/70 hover:text-cyan-300 transition-colors"
          >
            View Doc →
          </button>
        )}
      </div>
      {snippet && (
        <p className="text-[10px] text-gray-500 leading-relaxed pl-5 line-clamp-2">
          {snippet}
        </p>
      )}
      {status && (
        <div className="pl-5 font-mono text-[9px] text-emerald-400">{status}</div>
      )}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Main component
// ---------------------------------------------------------------------------
export function MissionFlowTab({ mission, ownerHistory }: Props) {
  const [docView, setDocView] = useState<DocView>("overview");

  // Handle null mission
  if (!mission) {
    return (
      <div className="text-gray-500 text-xs">
        No mission selected. Click a mission from the timeline below.
      </div>
    );
  }

  // -- Doc view mode --
  if (docView !== "overview") {
    let content: string | null = null;
    let docTitle = docView;

    if (["ceo", "cto", "cqo", "coo", "cdo", "ops"].includes(docView)) {
      content = mission[docView as "ceo" | "cto" | "cqo" | "coo" | "cdo" | "ops"];
      docTitle = `harness-${docView}`;
    } else {
      // worker name
      const w = mission.workers.find((x) => x.name === docView);
      content = w?.content ?? null;
      docTitle = docView;
    }

    return (
      <div className="space-y-3">
        <button
          type="button"
          onClick={() => setDocView("overview")}
          className="flex items-center gap-1.5 font-mono text-[10px] text-cyan-400/70 hover:text-cyan-300 transition-colors"
        >
          ← Back
        </button>
        <div className="font-mono text-[10px] text-gray-500">
          {mission.missionId} · {docTitle}
        </div>
        {content ? (
          <MarkdownView source={content} />
        ) : (
          <div className="text-gray-500 text-xs">No document available.</div>
        )}
      </div>
    );
  }

  // -- Overview mode --

  // Find the owner prompt closest in date to the mission
  let ownerPromptSnippet: string | null = null;
  if (ownerHistory.length > 0) {
    const missionTime = Date.parse(mission.ts);
    let closest: OwnerPromptEntry | null = null;
    let closestDiff = Infinity;
    for (const entry of ownerHistory) {
      const t = Date.parse(entry.ts);
      if (!Number.isNaN(t)) {
        const diff = Math.abs(t - missionTime);
        if (diff < closestDiff) {
          closestDiff = diff;
          closest = entry;
        }
      }
    }
    if (closest) {
      ownerPromptSnippet = closest.content.slice(0, 120);
    }
  }

  const typeBadge =
    mission.type === "hotfix"
      ? "[🔥 hot-fix]"
      : mission.type === "feature"
      ? "[✦ goal]"
      : "[— unknown]";

  let dateStr = "—";
  try {
    dateStr = new Date(mission.ts).toLocaleDateString(undefined, {
      year: "numeric",
      month: "short",
      day: "numeric",
    });
  } catch {
    // ignore
  }

  // Routing breadcrumb
  const routeChips: string[] = ["Owner", "CEO"];
  const cxxOrder: Array<"coo" | "cdo" | "cto" | "cqo" | "ops"> = [
    "coo", "cdo", "cto", "cqo", "ops",
  ];
  for (const r of cxxOrder) {
    if (mission.cxxPresent.includes(r)) routeChips.push(r.toUpperCase());
  }

  // CEO snippets
  const ceoSummarySnippet = mission.ceo
    ? extractSection(mission.ceo, "Owner 요청 요약")
    : null;
  const ceoDecisionSnippet = mission.ceo
    ? extractSection(mission.ceo, "CEO 결정")
    : null;
  const ceoSnippet = [ceoSummarySnippet, ceoDecisionSnippet]
    .filter(Boolean)
    .join(" | ")
    .slice(0, 200) || null;

  // CTO snippet
  const ctoSnippet = mission.cto
    ? extractSection(mission.cto, "변경 요약")
    : null;

  // CQO verdict
  let cqoVerdict: string | null = null;
  if (mission.cqo) {
    if (mission.cqo.includes("ACCEPTED")) cqoVerdict = "검증 결과: ACCEPTED ✅";
    else if (mission.cqo.includes("REJECTED")) cqoVerdict = "검증 결과: REJECTED";
    else cqoVerdict = extractSection(mission.cqo, "검증 결과") ?? extractSection(mission.cqo, "Verdict");
  }

  let stepNum = 1;

  return (
    <div className="space-y-3">
      {/* Mission header */}
      <div>
        <div className="flex items-center gap-2 flex-wrap mb-1">
          <span
            className={`font-mono text-[9px] rounded border px-1.5 py-0.5 ${
              mission.type === "hotfix"
                ? "bg-rose-500/15 text-rose-300 border-rose-500/30"
                : "bg-emerald-500/15 text-emerald-300 border-emerald-500/30"
            }`}
          >
            {typeBadge}
          </span>
          <span className="font-mono text-[10px] text-gray-300 truncate flex-1 min-w-0">
            {mission.missionId}
          </span>
          <span className="font-mono text-[9px] text-gray-500 shrink-0">{dateStr}</span>
        </div>
        {/* Routing breadcrumb */}
        <div className="flex flex-wrap items-center gap-1 mt-1">
          {routeChips.map((label, idx) => {
            const roleKey =
              label === "Owner"
                ? "owner"
                : label === "CEO"
                ? "ceo"
                : label.toLowerCase();
            return (
              <span key={idx} className="flex items-center gap-1">
                {idx > 0 && (
                  <span className="text-gray-600 text-[9px]">→</span>
                )}
                <StepChip role={roleKey} label={label} />
              </span>
            );
          })}
        </div>
      </div>

      {/* Flow tree */}
      <div className="space-y-2">
        {/* OWNER */}
        <DocRow
          step={stepNum++}
          roleLabel="OWNER"
          roleKey="owner"
        />
        {ownerPromptSnippet && (
          <p className="pl-7 text-[10px] text-gray-500 italic leading-relaxed line-clamp-2">
            {ownerPromptSnippet}
            {ownerPromptSnippet.length >= 120 ? "…" : ""}
          </p>
        )}

        {/* CEO */}
        <div className="pl-3 space-y-1">
          <p className="font-mono text-[9px] text-gray-600 pl-2">↓ dispatched to</p>
          <DocRow
            step={stepNum++}
            roleLabel="harness-ceo"
            roleKey="ceo"
            snippet={ceoSnippet}
            onViewDoc={mission.ceo ? () => setDocView("ceo") : undefined}
          />
        </div>

        {/* CTO */}
        {mission.cxxPresent.includes("cto") && (
          <div className="pl-6 space-y-1">
            <p className="font-mono text-[9px] text-gray-600 pl-2">↓ routed to</p>
            <DocRow
              step={stepNum++}
              roleLabel="harness-cto"
              roleKey="cto"
              snippet={ctoSnippet}
              onViewDoc={mission.cto ? () => setDocView("cto") : undefined}
            />
            {/* Workers */}
            {mission.workers.length > 0 && (
              <div className="pl-4 space-y-1">
                <p className="font-mono text-[9px] text-gray-500 pl-1">Workers dispatched:</p>
                {mission.workers.map((worker) => {
                  const fileCount = (worker.content.match(/\| [`].+[`] \|/g) ?? []).length;
                  const fileHint = fileCount > 0 ? `${fileCount} file(s) changed` : null;
                  return (
                    <div
                      key={worker.name}
                      className="relative pl-3 border-l border-gray-700/30 ml-2 space-y-0.5"
                    >
                      <div className="flex items-center justify-between gap-2">
                        <div className="flex items-center gap-1.5">
                          <span className="font-mono text-[9px] text-gray-600">├─</span>
                          <StepChip
                            role="worker"
                            label={worker.name}
                          />
                          <span
                            className={`font-mono text-[9px] ${
                              worker.status === "COMPLETE"
                                ? "text-emerald-400"
                                : "text-amber-400"
                            }`}
                          >
                            {worker.status === "COMPLETE" ? "COMPLETE ✅" : "⏳"}
                          </span>
                        </div>
                        {worker.content && (
                          <button
                            type="button"
                            onClick={() => setDocView(worker.name)}
                            className="shrink-0 font-mono text-[9px] text-cyan-400/70 hover:text-cyan-300 transition-colors"
                          >
                            View Doc →
                          </button>
                        )}
                      </div>
                      {fileHint && (
                        <p className="pl-5 font-mono text-[9px] text-gray-600">
                          {fileHint}
                        </p>
                      )}
                    </div>
                  );
                })}
              </div>
            )}
          </div>
        )}

        {/* COO */}
        {mission.cxxPresent.includes("coo") && (
          <div className="pl-6 space-y-1">
            <p className="font-mono text-[9px] text-gray-600 pl-2">↓ routed to</p>
            <DocRow
              step={stepNum++}
              roleLabel="harness-coo"
              roleKey="coo"
              snippet={mission.coo ? extractSection(mission.coo, "요약") : null}
              onViewDoc={mission.coo ? () => setDocView("coo") : undefined}
            />
          </div>
        )}

        {/* CDO */}
        {mission.cxxPresent.includes("cdo") && (
          <div className="pl-6 space-y-1">
            <p className="font-mono text-[9px] text-gray-600 pl-2">↓ routed to</p>
            <DocRow
              step={stepNum++}
              roleLabel="harness-cdo"
              roleKey="cdo"
              snippet={mission.cdo ? extractSection(mission.cdo, "요약") : null}
              onViewDoc={mission.cdo ? () => setDocView("cdo") : undefined}
            />
          </div>
        )}

        {/* OPS */}
        {mission.cxxPresent.includes("ops") && (
          <div className="pl-6 space-y-1">
            <p className="font-mono text-[9px] text-gray-600 pl-2">↓ routed to</p>
            <DocRow
              step={stepNum++}
              roleLabel="harness-ops"
              roleKey="ops"
              snippet={mission.ops ? extractSection(mission.ops, "요약") : null}
              onViewDoc={mission.ops ? () => setDocView("ops") : undefined}
            />
          </div>
        )}

        {/* CQO */}
        {mission.cxxPresent.includes("cqo") && (
          <div className="pl-6 space-y-1">
            <p className="font-mono text-[9px] text-gray-600 pl-2">↓ routed to</p>
            <DocRow
              step={stepNum++}
              roleLabel="harness-cqo"
              roleKey="cqo"
              snippet={cqoVerdict}
              onViewDoc={mission.cqo ? () => setDocView("cqo") : undefined}
            />
          </div>
        )}
      </div>
    </div>
  );
}
