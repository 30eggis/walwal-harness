"use client";
import { useEffect, useState } from "react";
import type { MissionDoc, OwnerPromptEntry, RuntimeSnapshot } from "@/lib/types";
import { MarkdownView } from "@/lib/markdown";

type DocView = "overview" | "ceo" | "cto" | "cqo" | "coo" | "cdo" | "ops" | string;

interface Props {
  mission: MissionDoc | null;
  ownerHistory: OwnerPromptEntry[];
  runtime: RuntimeSnapshot;
}

// ---------------------------------------------------------------------------
// Section extractors
// ---------------------------------------------------------------------------

/** Extract up to maxLines non-empty lines from a ## section */
function extractSection(content: string, heading: string, maxLines = 3): string | null {
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
    if (trimmed && !trimmed.startsWith("---")) snippet.push(trimmed);
    if (snippet.length >= maxLines) break;
  }
  const result = snippet.join(" · ").slice(0, 240);
  return result || null;
}

/** Try multiple heading alternatives, return first match */
function extractSectionAny(content: string, ...headings: string[]): string | null {
  for (const h of headings) {
    const r = extractSection(content, h, 4);
    if (r) return r;
  }
  return null;
}

/** Parse markdown table rows from "생성/수정 파일" or "구현 파일 목록" sections */
function extractFilesTable(content: string, maxRows = 5): Array<{ file: string; action: string }> {
  const body = content.replace(/^---[\s\S]*?---\n+/, "");
  const lines = body.split("\n");
  const results: Array<{ file: string; action: string }> = [];
  let inFileTable = false;

  for (const line of lines) {
    // Detect table header with "파일" column
    if (line.startsWith("|") && (line.includes("파일") || line.includes("File"))) {
      inFileTable = true;
      continue;
    }
    if (inFileTable) {
      if (line.trim() === "" || (!line.startsWith("|") && !line.startsWith("|-"))) {
        inFileTable = false;
        continue;
      }
      if (line.includes("---")) continue; // divider row
      if (!line.startsWith("|")) continue;
      const cells = line.split("|").map((c) => c.trim()).filter(Boolean);
      if (cells.length < 1) continue;
      const file = cells[0].replace(/`/g, "").trim();
      if (!file || file.toLowerCase() === "파일" || file.toLowerCase() === "file") continue;
      // Truncate long action text
      const raw = cells[1]?.replace(/`/g, "").trim() ?? "";
      const action = raw.length > 60 ? raw.slice(0, 60) + "…" : raw;
      results.push({ file, action });
      if (results.length >= maxRows) break;
    }
  }
  return results;
}

/** Extract CTO's worker instruction section */
function extractCtoWorkerInstructions(content: string): string | null {
  return extractSection(content, "워커 지시", 6);
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
  onViewDoc,
}: {
  step: number;
  roleLabel: string;
  roleKey: string;
  snippet?: string | null;
  onViewDoc?: () => void;
}) {
  return (
    <div className="relative pl-4 border-l border-gray-700/40 ml-2 space-y-1">
      <div className="flex items-center justify-between gap-2">
        <div className="flex items-center gap-1.5">
          <span className="font-mono text-[9px] text-gray-600">{step}</span>
          <StepChip role={roleKey} label={roleLabel} />
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
        <p className="text-[10px] text-gray-500 leading-relaxed pl-5 line-clamp-3">
          {snippet}
        </p>
      )}
    </div>
  );
}

// ---------------------------------------------------------------------------
// WorkerCard: shows worker + file list
// ---------------------------------------------------------------------------
function WorkerCard({
  worker,
  onViewDoc,
  active,
}: {
  worker: { name: string; content: string; status: string; owner?: string };
  onViewDoc?: () => void;
  active?: boolean;
}) {
  const files = extractFilesTable(worker.content, 4);
  return (
    <div
      className={`relative pl-3 border-l border-gray-700/30 ml-2 space-y-1 pb-1 ${active ? "border-cyan-400/40" : ""}`}
    >
      <div className="flex items-center justify-between gap-2">
        <div className="flex items-center gap-1.5">
          <span className="font-mono text-[9px] text-gray-600">├─</span>
          <StepChip role="worker" label={worker.name} />
          <span
            className={`font-mono text-[9px] ${
              worker.status === "COMPLETE" ? "text-emerald-400" : "text-amber-400"
            }`}
          >
            {worker.status === "COMPLETE" ? "COMPLETE ✅" : "⏳"}
          </span>
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

      {/* Changed files */}
      {files.length > 0 && (
        <div className="pl-5 space-y-0.5">
          {files.map((f, i) => (
            <div key={i} className="flex items-start gap-1.5">
              <span className="font-mono text-[9px] text-gray-600 shrink-0 mt-0.5">▸</span>
              <div className="min-w-0">
                <span className="font-mono text-[9px] text-blue-300/80 break-all leading-tight">
                  {f.file}
                </span>
                {f.action && (
                  <span className="font-mono text-[9px] text-gray-600 ml-1">— {f.action}</span>
                )}
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Main component
// ---------------------------------------------------------------------------
function RuntimeStrip({ runtime }: { runtime: RuntimeSnapshot }) {
  const isActive = runtime.agentStatus === "running";
  const command = runtime.ownerPrompt?.command ?? "input";
  const summary = runtime.ownerPrompt?.summary ?? null;
  return (
    <div
      data-testid="runtime-strip"
      data-current-agent={runtime.currentAgent ?? ""}
      data-agent-status={runtime.agentStatus}
      className={`rounded border px-2.5 py-2 ${
        isActive
          ? "border-cyan-400/30 bg-cyan-400/10"
          : runtime.agentStatus === "blocked" || runtime.agentStatus === "failed"
          ? "border-rose-400/30 bg-rose-400/10"
          : "border-gray-700/60 bg-black/20"
      }`}
    >
      <div className="flex flex-wrap items-center gap-1.5">
        <span className="font-mono text-[9px] uppercase tracking-[0.18em] text-gray-500">
          live runtime
        </span>
        <StepChip role={runtime.currentAgent ?? "worker"} label={runtime.currentAgent ?? "none"} />
        <span
          className={`font-mono text-[9px] ${
            isActive ? "text-cyan-300" : "text-gray-400"
          }`}
        >
          {runtime.agentStatus}
        </span>
        {runtime.nextAgent && (
          <span className="font-mono text-[9px] text-gray-500">
            next: {runtime.nextAgent}
          </span>
        )}
      </div>
      {summary && (
        <p className="mt-1.5 text-[10px] leading-relaxed text-gray-400 line-clamp-2">
          <span className="font-mono text-gray-500">{command}</span>
          <span className="text-gray-600"> · </span>
          {summary}
        </p>
      )}
    </div>
  );
}

export function MissionFlowTab({ mission, ownerHistory, runtime }: Props) {
  const [docView, setDocView] = useState<DocView>("overview");

  useEffect(() => {
    setDocView("overview");
  }, [mission?.missionId]);

  if (!mission) {
    return (
      <div className="space-y-3">
        <RuntimeStrip runtime={runtime} />
        <div className="text-gray-500 text-xs">
          No mission selected. Click a mission from the timeline below.
        </div>
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
      const w = mission.workers.find((x) => x.name === docView);
      content = w?.content ?? null;
      docTitle = docView;
    }

    return (
      <div className="space-y-3">
        <RuntimeStrip runtime={runtime} />
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

  // Find owner prompt closest to mission date
  let ownerPromptSnippet: string | null = null;
  if (ownerHistory.length > 0) {
    const missionTime = Date.parse(mission.ts);
    let closest: OwnerPromptEntry | null = null;
    let closestDiff = Infinity;
    for (const entry of ownerHistory) {
      const t = Date.parse(entry.ts);
      if (!Number.isNaN(t)) {
        const diff = Math.abs(t - missionTime);
        if (diff < closestDiff) { closestDiff = diff; closest = entry; }
      }
    }
    if (closest) ownerPromptSnippet = closest.content.slice(0, 140);
  }

  const typeBadge =
    mission.type === "hotfix" ? "[🔥 hot-fix]"
    : mission.type === "submission" ? "[+ submission]"
    : mission.type === "goal" || mission.type === "feature" ? "[✦ goal]"
    : "[— unknown]";

  let dateStr = "—";
  try {
    dateStr = new Date(mission.ts).toLocaleDateString(undefined, {
      year: "numeric", month: "short", day: "numeric",
    });
  } catch { /* ignore */ }

  // Routing breadcrumb
  const routeChips: string[] = ["Owner", "CEO"];
  const cxxOrder: Array<"coo" | "cdo" | "cto" | "cqo" | "ops"> = ["coo", "cdo", "cto", "cqo", "ops"];
  for (const r of cxxOrder) {
    if (mission.cxxPresent.includes(r)) routeChips.push(r.toUpperCase());
  }

  // CEO snippets
  const ceoRequestSnippet = mission.ceo
    ? extractSectionAny(mission.ceo, "Owner 요청 요약", "Owner Request")
    : null;
  const ceoDecisionSnippet = mission.ceo
    ? extractSectionAny(mission.ceo, "CEO 결정", "CXX Decisions")
    : null;
  const ceoSnippet = [ceoRequestSnippet, ceoDecisionSnippet].filter(Boolean).join(" | ").slice(0, 240) || null;

  // CTO snippet + worker instructions
  const ctoSnippet = mission.cto
    ? extractSectionAny(mission.cto, "변경 요약", "Summary")
    : null;
  const ctoWorkerInstructions = mission.cto
    ? extractCtoWorkerInstructions(mission.cto)
    : null;

  // CQO verdict
  let cqoVerdict: string | null = null;
  if (mission.cqo) {
    if (mission.cqo.includes("ACCEPTED")) cqoVerdict = "검증 결과: ACCEPTED ✅";
    else if (mission.cqo.includes("REJECTED")) cqoVerdict = "검증 결과: REJECTED ❌";
    else cqoVerdict = extractSectionAny(mission.cqo, "검증 결과", "Verdict") ?? null;
  }

  let stepNum = 1;

  return (
    <div className="space-y-3">
      <RuntimeStrip runtime={runtime} />
      {/* Mission header */}
      <div>
        <div className="flex items-center gap-2 flex-wrap mb-1">
          <span
            className={`font-mono text-[9px] rounded border px-1.5 py-0.5 ${
              mission.type === "hotfix"
                ? "bg-rose-500/15 text-rose-300 border-rose-500/30"
                : mission.type === "submission"
                ? "bg-sky-500/15 text-sky-300 border-sky-500/30"
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
            const roleKey = label === "Owner" ? "owner" : label === "CEO" ? "ceo" : label.toLowerCase();
            return (
              <span key={idx} className="flex items-center gap-1">
                {idx > 0 && <span className="text-gray-600 text-[9px]">→</span>}
                <StepChip role={roleKey} label={label} />
              </span>
            );
          })}
        </div>
      </div>

      {/* Flow tree */}
      <div className="space-y-2">
        {/* OWNER */}
        <DocRow step={stepNum++} roleLabel="OWNER" roleKey="owner" />
        {ownerPromptSnippet && (
          <p className="pl-7 text-[10px] text-gray-500 italic leading-relaxed line-clamp-2">
            {ownerPromptSnippet}{ownerPromptSnippet.length >= 140 ? "…" : ""}
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
          {/* Legacy flat workers: protocol violation / unknown owner */}
          {mission.workers.some((w) => w.owner === "unknown") && (
            <div className="pl-4 space-y-2 mt-1">
              <p className="font-mono text-[9px] text-rose-300/80 pl-1">
                Unowned legacy workers (CEO/CXX bypass suspected):
              </p>
              {mission.workers.filter((w) => w.owner === "unknown").map((worker) => (
                <WorkerCard
                  key={worker.name}
                  worker={worker}
                  onViewDoc={worker.content ? () => setDocView(worker.name) : undefined}
                />
              ))}
            </div>
          )}
        </div>

        {/* COO */}
        {mission.cxxPresent.includes("coo") && (
          <div className="pl-6 space-y-1">
            <p className="font-mono text-[9px] text-gray-600 pl-2">↓ routed to</p>
            <DocRow
              step={stepNum++}
              roleLabel="harness-coo"
              roleKey="coo"
              snippet={mission.coo ? extractSectionAny(mission.coo, "요약", "Summary") : null}
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
              snippet={mission.cdo ? extractSectionAny(mission.cdo, "요약", "Summary") : null}
              onViewDoc={mission.cdo ? () => setDocView("cdo") : undefined}
            />
          </div>
        )}

        {/* CTO + Workers */}
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

            {/* CTO worker instructions */}
            {ctoWorkerInstructions && (
              <div className="pl-7 mt-1">
                <div className="rounded border border-blue-400/15 bg-blue-400/5 px-2 py-1.5">
                  <span className="font-mono text-[9px] text-blue-300/50 uppercase tracking-wider">
                    워커 지시
                  </span>
                  <p className="text-[10px] text-gray-400 leading-relaxed mt-0.5">
                    {ctoWorkerInstructions}
                  </p>
                </div>
              </div>
            )}

            {/* Workers */}
            {mission.workers.some((w) => w.owner === "cto") && (
              <div className="pl-4 space-y-2 mt-1">
                <p className="font-mono text-[9px] text-gray-500 pl-1">CTO workers:</p>
                {mission.workers.filter((w) => w.owner === "cto").map((worker) => (
                  <WorkerCard
                    key={worker.name}
                    worker={worker}
                    onViewDoc={worker.content ? () => setDocView(worker.name) : undefined}
                  />
                ))}
              </div>
            )}
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
              snippet={mission.ops ? extractSectionAny(mission.ops, "요약", "Summary") : null}
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
            {mission.workers.some((w) => w.owner === "cqo") && (
              <div className="pl-4 space-y-2 mt-1">
                <p className="font-mono text-[9px] text-gray-500 pl-1">CQO evaluators:</p>
                {mission.workers.filter((w) => w.owner === "cqo").map((worker) => (
                  <WorkerCard
                    key={worker.name}
                    worker={worker}
                    onViewDoc={worker.content ? () => setDocView(worker.name) : undefined}
                  />
                ))}
              </div>
            )}
          </div>
        )}
      </div>
    </div>
  );
}
