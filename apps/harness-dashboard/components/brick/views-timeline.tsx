"use client";

/* =============================================================
   walwal-harness · VIEW 3 — TIMELINE (cadence heatmap + swimlanes)
   Ported from harness/views-timeline.jsx (design handoff).
   Exports: TimelineView, Cadence
   ============================================================= */

import React, { useRef } from "react";
import type { CSSProperties } from "react";

import type {
  AgentRole,
  ContractState,
  ContractWorker,
  DocTarget,
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

type SwimMark = { ago: number; dur: number };

type SwimRow = {
  kind: "exec" | "worker";
  id: string;
  label: string;
  hue: string;
  agent: AgentRole;
  status: string;
  progress?: number | null;
};

export function TimelineView({ s, openDoc }: TimelineViewProps) {
  // stable seeded marks per row id
  const markCache = useRef<Record<string, SwimMark[]>>({});
  function seedMarks(id: string, density: number): SwimMark[] {
    const cached = markCache.current[id];
    if (cached) return cached;
    const arr: SwimMark[] = [];
    const n = Math.floor(density * (4 + Math.random() * 7));
    for (let i = 0; i < n; i++) {
      arr.push({ ago: Math.random() * SPAN_MS, dur: 40000 + Math.random() * 600000 });
    }
    markCache.current[id] = arr;
    return arr;
  }

  // build rows: exec + its workers
  const order: AgentRole[] = ["ceo", "coo", "cto", "cqo", "cdo", "ops"];
  const rows: SwimRow[] = [];
  order.forEach((id) => {
    const a = s.agents.find((x) => x.id === id);
    if (!a) return;
    rows.push({ kind: "exec", id: a.id, label: a.name, hue: a.hue, agent: a.id, status: a.status });
    s.workers
      .filter((w) => w.agent === id)
      .forEach((w) => {
        rows.push({
          kind: "worker",
          id: w.id,
          label: w.name,
          hue: a.hue,
          agent: a.id,
          status: w.status,
          progress: w.progress,
        });
      });
  });

  // live marks from recent events (last 6 min) keyed to exec rows
  const liveByAgent: Record<string, number[]> = {};
  s.events.forEach((e) => {
    if (e.at == null || e.agent === "") return;
    const age = s.now - e.at;
    if (age < 6 * 60 * 1000) {
      (liveByAgent[e.agent] = liveByAgent[e.agent] || []).push(age);
    }
  });

  const xOf = (ago: number): number => Math.max(0, Math.min(100, (ago / SPAN_MS) * 100));

  // axis ticks
  const ticks: number[] = [];
  for (let h = 0; h <= 12; h += 2) ticks.push(h);

  const openRow = (r: SwimRow) => {
    if (!openDoc) return;
    if (r.kind === "exec") {
      openDoc({ type: "agent", agent: r.agent });
      return;
    }
    const worker: ContractWorker | undefined = s.workers.find((w) => w.id === r.id);
    if (worker) openDoc({ type: "worker", agent: r.agent, worker });
  };

  return (
    <div className="timelineview">
      <Cadence cadence={s.cadence} />
      <div className="swim">
        <Label
          right={
            rows.filter((r) => r.kind === "worker").length +
            " workers · " +
            order.length +
            " execs"
          }
        >
          ORCHESTRATION TIMELINE · now → −12h
        </Label>
        <div className="swim-axis">
          <div className="swim-axis-pad" />
          <div className="swim-axis-track">
            {ticks.map((h) => (
              <span
                key={h}
                className="swim-tick"
                style={{ left: (h / 12) * 100 + "%" }}
              >
                {h === 0 ? "now" : "−" + h + "h"}
              </span>
            ))}
          </div>
        </div>
        <div className="swim-rows">
          {rows.map((r) => {
            const marks = seedMarks(r.id, r.kind === "exec" ? 1.4 : 0.8);
            const live = r.kind === "exec" ? liveByAgent[r.agent] || [] : [];
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
                      style={{
                        left: xOf(m.ago) + "%",
                        width: Math.max(0.6, (m.dur / SPAN_MS) * 100) + "%",
                        background: r.hue,
                        opacity: r.kind === "exec" ? 0.85 : 0.55,
                      }}
                    />
                  ))}
                  {live.map((age, i) => (
                    <span
                      key={"l" + i}
                      className="swim-live"
                      style={{ left: xOf(age) + "%", background: r.hue }}
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
