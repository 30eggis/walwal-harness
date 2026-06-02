"use client";

/* =============================================================
   walwal-harness · VIEW 2 — ORCHESTRATION (node-edge graph)
   Ported from design_handoff_harness_dashboard/harness/views-graph.jsx.
   Exports: GraphView, useSize

   Renders the CEO -> exec -> worker node/edge graph (animated active
   edges, ResizeObserver sizing) plus a detail panel for the selected
   node. Every value comes from the real-data Contract (ContractState);
   where the contract is honest about missing data (null heartbeat /
   progress / event time) we render an em-dash, never a fake number.
   ============================================================= */

import React, { useState, useRef, useLayoutEffect } from "react";
import {
  fmt,
  statusColor,
  type AgentRole,
  type AgentStatus,
  type ContractState,
  type ContractAgent,
  type ContractWorker,
  type DocTarget,
} from "../../lib/brick/contract";
import { StatusDot, Label } from "./ui";

/* ---- sizing hook ------------------------------------------------------ */

export interface Size {
  w: number;
  h: number;
}

export function useSize(ref: React.RefObject<HTMLElement | null>): Size {
  const [size, setSize] = useState<Size>({ w: 1000, h: 600 });
  useLayoutEffect(() => {
    if (!ref.current) return;
    const ro = new ResizeObserver((ents) => {
      const r = ents[0].contentRect;
      setSize({ w: r.width, h: r.height });
    });
    ro.observe(ref.current);
    return () => ro.disconnect();
  }, [ref]);
  return size;
}

/* ---- helpers ---------------------------------------------------------- */

interface Point {
  x: number;
  y: number;
}

/** Inline `--hue` custom property (kept as the mockup's per-node convention). */
type HueStyle = React.CSSProperties & { "--hue"?: string };

const isActive = (st: AgentStatus): boolean =>
  st === "typing" || st === "talking" || st === "active" || st === "live";

const edge = (a: Point, b: Point): string =>
  `M${a.x} ${a.y} C ${(a.x + b.x) / 2} ${a.y}, ${(a.x + b.x) / 2} ${b.y}, ${b.x} ${b.y}`;

/** Honest progress width: null -> 0 (no fabricated bar). */
const progWidth = (p: number | null): number => (p == null ? 0 : Math.round(p));
/** Honest progress label: null -> em-dash. */
const progLabel = (p: number | null): string => (p == null ? "—" : Math.round(p) + "%");

/* ---- props ------------------------------------------------------------ */

export interface GraphViewProps {
  s: ContractState;
  /** Selected node id (controlled). Falls back to an internal default. */
  sel?: AgentRole;
  setSel?: (id: AgentRole) => void;
  /** Open a report document for an agent or worker. */
  openDoc?: (target: DocTarget) => void;
}

/* ---- GraphView -------------------------------------------------------- */

export function GraphView({ s, sel: selProp, setSel: setSelProp, openDoc }: GraphViewProps) {
  const wrapRef = useRef<HTMLDivElement | null>(null);
  const { w: W, h: H } = useSize(wrapRef);
  const [selLocal, setSelLocal] = useState<AgentRole>("cto");
  const sel = selProp ?? selLocal;
  const setSel = setSelProp ?? setSelLocal;

  const pad = 56;
  const order: AgentRole[] = ["ceo", "coo", "cto", "cqo", "cdo", "ops"];
  const execs: ContractAgent[] = order
    .map((id) => s.agents.find((a) => a.id === id))
    .filter((a): a is ContractAgent => Boolean(a));

  // workers grouped by exec order
  const workers: ContractWorker[] = [];
  execs.forEach((e) =>
    s.workers.filter((w) => w.agent === e.id).forEach((w) => workers.push(w))
  );
  const N = Math.max(workers.length, 1);

  const xCEO = pad + 24;
  const xExec = Math.max(260, W * 0.4);
  const xWork = Math.max(520, W * 0.8);

  const wpos: Record<string, Point> = {};
  workers.forEach((w, i) => {
    wpos[w.id] = { x: xWork, y: pad + ((i + 0.5) * (H - 2 * pad)) / N };
  });
  const epos: Record<string, Point> = {};
  execs.forEach((e, i) => {
    const mine = workers.filter((w) => w.agent === e.id);
    const y = mine.length
      ? mine.reduce((acc, w) => acc + wpos[w.id].y, 0) / mine.length
      : pad + ((i + 0.5) * (H - 2 * pad)) / execs.length;
    epos[e.id] = { x: xExec, y };
  });
  const ceoPos: Point = { x: xCEO, y: H / 2 };

  const selAgent: ContractAgent = s.agents.find((a) => a.id === sel) ?? execs[0];
  const selWorkers = s.workers.filter((w) => w.agent === sel);
  const selEvents = s.events.filter((e) => e.agent === sel).slice(-10).reverse();

  return (
    <div className="graphview">
      <div className="graph-wrap" ref={wrapRef}>
        <svg className="graph-edges" width={W} height={H}>
          {execs.map((e) => {
            const active = isActive(e.status);
            return (
              <path
                key={"ce" + e.id}
                d={edge(ceoPos, epos[e.id])}
                className={"gedge" + (active ? " is-active" : "")}
                style={{ stroke: e.hue, "--hue": e.hue } as HueStyle}
              />
            );
          })}
          {workers.map((w) => {
            const e = s.agents.find((a) => a.id === w.agent);
            const active = isActive(w.status);
            return (
              <path
                key={"ew" + w.id}
                d={edge(epos[w.agent], wpos[w.id])}
                className={"gedge gedge-w" + (active ? " is-active" : "")}
                style={{ stroke: e?.hue, "--hue": e?.hue } as HueStyle}
              />
            );
          })}
        </svg>

        {/* CEO root */}
        <div
          className="gnode gnode-root"
          style={{ left: ceoPos.x, top: ceoPos.y, "--hue": "#4cc2ff" } as HueStyle}
          onClick={() => setSel("ceo")}
        >
          <span className="gnode-ring" />
          <span className="glyph" style={{ color: "#4cc2ff", borderColor: "#4cc2ff66" }}>
            CEO
          </span>
          <span className="gnode-cap">root loop</span>
        </div>

        {/* exec nodes */}
        {execs
          .filter((e) => e.id !== "ceo")
          .map((e) => {
            const active = isActive(e.status);
            return (
              <div
                key={e.id}
                className={
                  "gnode gnode-exec" +
                  (sel === e.id ? " is-sel" : "") +
                  (active ? " is-alive" : "")
                }
                style={{ left: epos[e.id].x, top: epos[e.id].y, "--hue": e.hue } as HueStyle}
                onClick={() => setSel(e.id)}
              >
                {active && <span className="gnode-ring" />}
                <span className="glyph" style={{ color: e.hue, borderColor: e.hue + "66" }}>
                  {e.name}
                </span>
                <span className="gnode-meta">
                  <StatusDot status={e.status} size={6} />
                  {e.workers}w
                </span>
              </div>
            );
          })}

        {/* worker nodes */}
        {workers.map((w) => {
          const e = s.agents.find((a) => a.id === w.agent);
          const hue = e?.hue;
          const fresh = w.started != null && s.now - w.started < 4000;
          return (
            <div
              key={w.id}
              className={
                "gnode gnode-worker" +
                (sel === w.agent ? " is-dim-on" : "") +
                (fresh ? " is-fresh" : "")
              }
              style={{ left: wpos[w.id].x, top: wpos[w.id].y, "--hue": hue } as HueStyle}
              onClick={() => setSel(w.agent)}
              title={w.name}
            >
              <span className="gw-dot" style={{ background: hue }} />
              <span className="gw-name">{w.name}</span>
              <span className="gw-prog">
                <span style={{ width: progWidth(w.progress) + "%", background: hue }} />
              </span>
            </div>
          );
        })}

        <div className="graph-legend">
          <span>CEO → exec → worker · animated edge = active dispatch</span>
        </div>
      </div>

      <aside className="graph-detail">
        <Label right={selAgent.loop}>NODE · {selAgent.name}</Label>
        <div className="gd-head" style={{ "--hue": selAgent.hue } as HueStyle}>
          <span
            className="glyph glyph-lg"
            style={{ color: selAgent.hue, borderColor: selAgent.hue + "66" }}
          >
            {selAgent.name}
          </span>
          <div>
            <div className="gd-role">{selAgent.role}</div>
            <div className="gd-status" style={{ color: statusColor(selAgent.status) }}>
              <StatusDot status={selAgent.status} size={7} />
              {selAgent.status} · loop {selAgent.loop}
            </div>
          </div>
          <button
            className="gd-read"
            onClick={() => openDoc && openDoc({ type: "agent", agent: selAgent.id })}
          >
            read report ↗
          </button>
        </div>
        <div className="gd-work">{selAgent.work}</div>
        <div className="gd-stats">
          <div>
            <b>{selWorkers.length}</b>
            <span>workers</span>
          </div>
          <div>
            <b>{selAgent.todos}</b>
            <span>open todos</span>
          </div>
          <div>
            <b>{selAgent.heartbeat == null ? "—" : fmt.ago(s.now - selAgent.heartbeat)}</b>
            <span>heartbeat</span>
          </div>
        </div>
        <Label>SPAWNED WORKERS</Label>
        <div className="gd-workers">
          {selWorkers.length === 0 && <div className="gd-empty">no active workers</div>}
          {selWorkers.map((w) => (
            <button
              key={w.id}
              className="gd-worker"
              onClick={() => openDoc && openDoc({ type: "worker", agent: selAgent.id, worker: w })}
            >
              <StatusDot status={w.status} size={6} />
              <span className="gd-wname">{w.name}</span>
              <span className="gd-wprog">
                <span className="prog-bar">
                  <span
                    className="prog-fill"
                    style={{ width: progWidth(w.progress) + "%", background: selAgent.hue }}
                  />
                </span>
                {progLabel(w.progress)}
              </span>
            </button>
          ))}
        </div>
        <Label>RECENT · {selAgent.name}</Label>
        <div className="gd-events">
          {selEvents.map((e) => (
            <button
              key={e.id}
              className="gd-ev"
              onClick={() => openDoc && openDoc({ type: "agent", agent: selAgent.id })}
            >
              <span className="sl-time">{e.at == null ? "—" : fmt.time(new Date(e.at))}</span>
              <span className="sl-msg">
                {e.verb} <span className="sl-obj">`{e.obj}`</span>
              </span>
            </button>
          ))}
        </div>
      </aside>
    </div>
  );
}
