"use client";

/* =============================================================
   walwal-harness · VIEW 3 — TIMELINE (cadence heatmap + swimlanes)
   Ported from harness/views-timeline.jsx (design handoff), wired to REAL
   per-lane activity marks (s.marks) instead of the prototype's random marks.
   Exports: TimelineView, Cadence
   ============================================================= */

import React from "react";
import type { CSSProperties } from "react";

import type {
  AgentRole,
  ContractState,
  ContractWorker,
  DocTarget,
  TimelineMark,
} from "../../lib/brick/contract";
import { StatusDot, Label } from "./ui";

const SPAN_MS = 12 * 3600 * 1000; // 12h window, now=left

/** Inline style that also carries the per-agent `--hue` CSS custom property. */
type HueStyle = CSSProperties & { "--hue": string };

/* ---- Cadence (also rendered by the COMMAND view) ---------------------- */

export interface CadenceProps {
  /** 24 hourly buckets = owner prompts/hour. */
  cadence: number[];
}

export function Cadence({ cadence }: CadenceProps) {
  const max = Math.max(...cadence, 1);
  return (
    <div className="cadence">
      <Label right={"max " + max + " · 24h"}>CADENCE · owner prompts / h</Label>
      <div className="cad-row">
        {cadence.map((v, i) => (
          <div
            key={i}
            className="cad-cell"
            title={v + " / h"}
            style={{
              background:
                v === 0 ? "transparent" : `rgba(229,72,77,${0.28 + 0.55 * (v / max)})`,
              borderColor: v === 0 ? "var(--bd)" : "rgba(229,72,77,0.5)",
            }}
          />
        ))}
      </div>
      <div className="cad-axis">
        <span>now</span>
        <span>−12h</span>
        <span>−24h</span>
      </div>
    </div>
  );
}

/* ---- TimelineView ----------------------------------------------------- */

export interface TimelineViewProps {
  /** The single source-of-truth contract state. */
  s: ContractState;
  /** Open a document (agent report or worker brief) in the DocViewer. */
  openDoc?: (target: DocTarget) => void;
}

type SwimRow = {
  kind: "exec" | "worker";
  id: string;
  /** activity lane id: "cto" for an exec, "cto:worker-name" for a worker. */
  laneId: string;
  label: string;
  hue: string;
  agent: AgentRole;
  status: string;
  progress?: number | null;
  worker?: ContractWorker;
};

export function TimelineView({ s, openDoc }: TimelineViewProps) {
  const order: AgentRole[] = ["ceo", "coo", "cto", "cqo", "cdo", "ops"];

  // Build rows: each exec + the real WORKERS under it. Worker rows come from the
  // activity sub-lanes ("cxx:worker-name") and the active-mission workers — NOT
  // from missions — so a CXX lists the workers that actually ran under it.
  const rows: SwimRow[] = [];
  order.forEach((role) => {
    const a = s.agents.find((x) => x.id === role);
    if (!a) return;
    rows.push({ kind: "exec", id: role, laneId: role, label: a.name, hue: a.hue, agent: role, status: a.status });

    const lanes = new Map<string, { label: string; worker?: ContractWorker }>();
    for (const laneId of Object.keys(s.marks)) {
      if (laneId.startsWith(role + ":")) {
        lanes.set(laneId, { label: laneId.slice(role.length + 1) });
      }
    }
    // active-mission workers (carry a report + status); key matches the sub-lane id.
    for (const w of s.workers) {
      if (w.agent === role) lanes.set(w.id, { label: w.name, worker: w });
    }
    for (const [laneId, info] of lanes) {
      rows.push({
        kind: "worker",
        id: laneId,
        laneId,
        label: info.label,
        hue: a.hue,
        agent: role,
        status: info.worker?.status ?? "idle",
        progress: info.worker?.progress ?? null,
        worker: info.worker,
      });
    }
  });

  const xOf = (ago: number): number => Math.max(0, Math.min(100, (ago / SPAN_MS) * 100));
  const ticks: number[] = [];
  for (let h = 0; h <= 12; h += 2) ticks.push(h);
  const fmtAt = (at: number): string => {
    const d = new Date(at);
    return Number.isFinite(d.getTime()) ? d.toTimeString().slice(0, 8) : "?";
  };

  // Label click → the whole row's report.
  const openRow = (r: SwimRow) => {
    if (!openDoc) return;
    if (r.worker) openDoc({ type: "worker", agent: r.agent, worker: r.worker });
    else openDoc({ type: "agent", agent: r.agent });
  };
  // Block click → detail for that one activity mark (what the lane did at that moment).
  const openMark = (r: SwimRow, m: TimelineMark, e: React.MouseEvent) => {
    e.stopPropagation();
    if (!openDoc) return;
    if (r.worker) openDoc({ type: "worker", agent: r.agent, worker: r.worker, at: m.at, mission: m.mission });
    else openDoc({ type: "agent", agent: r.agent, at: m.at, mission: m.mission });
  };

  const workerCount = rows.filter((r) => r.kind === "worker").length;

  return (
    <div className="timelineview">
      <Cadence cadence={s.cadence} />
      <div className="swim">
        <Label right={workerCount + " workers · " + order.length + " execs"}>
          ORCHESTRATION TIMELINE · now → −12h
        </Label>
        <div className="swim-axis">
          <div className="swim-axis-pad" />
          <div className="swim-axis-track">
            {ticks.map((h) => (
              <span key={h} className="swim-tick" style={{ left: (h / 12) * 100 + "%" }}>
                {h === 0 ? "now" : "−" + h + "h"}
              </span>
            ))}
          </div>
        </div>
        <div className="swim-rows">
          {rows.map((r) => {
            const marks = (s.marks[r.laneId] ?? []).filter(
              (m) => s.now - m.at >= 0 && s.now - m.at <= SPAN_MS
            );
            return (
              <div
                key={r.id}
                className={"swim-row " + (r.kind === "exec" ? "is-exec" : "is-worker")}
                onClick={() => openRow(r)}
              >
                <div className="swim-label" style={{ "--hue": r.hue } as HueStyle}>
                  {r.kind === "exec" ? (
                    <span
                      className="glyph glyph-sm"
                      style={{ color: r.hue, borderColor: r.hue + "55" }}
                    >
                      {r.label}
                    </span>
                  ) : (
                    <span className="swim-wlabel">
                      <span className="swim-tree">└</span>
                      {r.label}
                    </span>
                  )}
                  {r.kind === "exec" && <StatusDot status={r.status} size={6} />}
                </div>
                <div className="swim-track">
                  <div className="swim-gridlines">
                    {ticks.map((h) => (
                      <span key={h} style={{ left: (h / 12) * 100 + "%" }} />
                    ))}
                  </div>
                  {marks.map((m, i) => (
                    <span
                      key={i}
                      className="swim-block"
                      role="button"
                      title={fmtAt(m.at) + (m.mission ? " · " + m.mission : "")}
                      onClick={(e) => openMark(r, m, e)}
                      style={{
                        left: xOf(s.now - m.at) + "%",
                        width: "9px",
                        cursor: "pointer",
                        background: r.hue,
                        opacity: r.kind === "exec" ? 0.85 : 0.6,
                      }}
                    />
                  ))}
                  {r.kind === "worker" && r.progress != null && (
                    <span
                      className="swim-now-prog"
                      style={{ background: r.hue }}
                      title={Math.round(r.progress) + "%"}
                    />
                  )}
                </div>
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
}
