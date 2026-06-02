"use client";

/* =============================================================
   walwal-harness · VIEW 1 — COMMAND (health strip + agent grid + live stream)
   Ported from design_handoff_harness_dashboard/harness/views-grid.jsx.

   Exports: GridView, HealthStrip, LiveStream, AlertRail.
   Renders entirely from the Contract (lib/brick/contract). Honest about
   missing data: a null progress/heartbeat/timestamp renders "—" and the
   progress bar is hidden — never a fabricated number.
   ============================================================= */

import React, { useEffect, useRef } from "react";
import {
  AGENT_DEFS,
  fmt,
  statusColor,
  type AgentRole,
  type ContractState,
  type ContractAgent,
  type ContractWorker,
  type ContractTask,
  type ContractEvent,
  type ContractAlert,
  type ContractMetrics,
  type DocTarget,
} from "../../lib/brick/contract";
import { StatusDot, Panel, Label, Spark, Bars } from "./ui";
import { Cadence } from "./views-timeline";

/* ---- shared local types ---------------------------------------------- */

/** Card vs. list rendering of the agents region (Tweak `agentLayout`). */
export type AgentLayout = "card" | "list";

/** Open the document viewer for an agent or one of its workers. */
export type OpenDoc = (target: DocTarget) => void;

const STALE_MS = 120_000;

/** Lookup the static def (hue) for an agent role, tolerating "". */
function defOf(agent: AgentRole | "") {
  return AGENT_DEFS.find((x) => x.id === agent);
}

/* ---- health strip ----------------------------------------------------- */

interface MetricTileProps {
  label: string;
  value: React.ReactNode;
  sub?: string;
  color: string;
  /** Small qualifier shown next to the label, e.g. "est." for estimates. */
  tag?: string;
  /** line sparkline data; null/empty -> no sparkline */
  spark?: number[] | null;
  /** bar distribution data; null/empty -> no bars */
  bars?: number[] | null;
}

function MetricTile({ label, value, sub, color, tag, spark, bars }: MetricTileProps) {
  const hasSpark = !!spark && spark.length > 0;
  const hasBars = !!bars && bars.length > 0;
  return (
    <div className="mtile">
      <div className="mtile-top">
        <span className="mtile-label">
          {label}
          {tag && <span className="mtile-tag">{tag}</span>}
        </span>
        {hasSpark && <Spark data={spark!} color={color} w={56} h={16} />}
        {hasBars && <Bars data={bars!} color={color} w={56} h={16} />}
      </div>
      <div className="mtile-val" style={{ color }}>
        {value}
      </div>
      {sub && <div className="mtile-sub">{sub}</div>}
    </div>
  );
}

export interface HealthStripProps {
  s: ContractState;
}

/**
 * The 8 metric tiles. Null metrics (tokensPerMin, costToday, cpu) render "—"
 * and their sparkline (mtrend/ctrend) is hidden — never fabricated.
 */
export function HealthStrip({ s }: HealthStripProps) {
  const m: ContractMetrics = s.metrics;
  const aliveWorkers = s.workers.length;
  const aliveAgents = s.agents.filter((a) => a.status !== "idle").length;
  // CPU may be null (no telemetry) -> color stays green; only flips red when
  // there is a real reading over 80%.
  const cpuColor = m.cpu != null && m.cpu > 80 ? "#f0506b" : "#3fd17a";
  const cpuValue = m.cpu != null ? m.cpu + "%" : "—";
  // Context-window occupancy of the most-active session (real, from transcripts).
  const ctxColor = m.contextPct != null && m.contextPct > 80 ? "#f0506b" : "#4cc2ff";
  const ctxValue = m.contextPct != null ? m.contextPct + "%" : "—";
  // costToday is a price-table estimate -> show a small "est." qualifier when present.
  const costTag = m.costToday != null && m.costEstimated ? "est." : undefined;
  return (
    <div className="healthstrip">
      <MetricTile
        label="ALIVE AGENTS"
        value={aliveAgents + "/" + s.agents.length}
        sub="loops running"
        color="#3fd17a"
      />
      <MetricTile
        label="WORKERS"
        value={aliveWorkers}
        sub="spawned · active"
        color="#4cc2ff"
        bars={s.agents.map((a) => a.workers)}
      />
      <MetricTile
        label="TOKENS / MIN"
        value={fmt.k(m.tokensPerMin)}
        sub="rolling"
        color="#c084fc"
        spark={s.mtrend}
      />
      <MetricTile
        label="COST · TODAY"
        value={fmt.money(m.costToday)}
        sub="usd"
        color="#f0a23b"
        tag={costTag}
        spark={s.ctrend}
      />
      <MetricTile
        label="CONTEXT"
        value={ctxValue}
        sub="active session"
        color={ctxColor}
      />
      <MetricTile
        label="THROUGHPUT"
        value={m.throughput == null ? "—" : m.throughput}
        sub="events / min"
        color="#4cc2ff"
      />
      <MetricTile label="CPU" value={cpuValue} sub="harness host" color={cpuColor} />
      <MetricTile label="HOT-FIX" value={m.hotfix} sub="queued patches" color="#8b95a4" />
      <MetricTile
        label="EVENTS"
        value={fmt.k(m.eventsTotal)}
        sub="session total"
        color="#8b95a4"
      />
    </div>
  );
}

/* ---- agent card ------------------------------------------------------- */

interface AgentCardProps {
  a: ContractAgent;
  now: number;
  workers: ContractWorker[];
  openDoc: OpenDoc;
}

function AgentCard({ a, now, workers, openDoc }: AgentCardProps) {
  const c = statusColor(a.status);
  const alive = a.loop === "running" && a.status !== "idle";
  const hasHb = a.heartbeat != null;
  const age = hasHb ? now - a.heartbeat! : null;
  const stale = age != null && age > STALE_MS;
  const active = workers.filter((w) => w.status !== "idle");
  return (
    <div
      className={"acard" + (alive ? " is-alive" : "")}
      style={{ ["--hue" as string]: a.hue }}
      role="button"
      tabIndex={0}
      onClick={() => openDoc({ type: "agent", agent: a.id })}
    >
      {alive && <span className="acard-ring" />}
      <div className="acard-head">
        <span className="glyph" style={{ color: a.hue, borderColor: a.hue + "55" }}>
          {a.name}
        </span>
        <div className="acard-id">
          <div className="acard-role">{a.role}</div>
          <div className="acard-status" style={{ color: c }}>
            <StatusDot status={a.status} size={7} />
            {a.status}
            {a.loop === "running" ? " · loop" : ""}
          </div>
        </div>
        <div className="acard-hb">
          <div className={"hb-mono" + (stale ? " is-stale" : "")}>
            {age == null ? "—" : fmt.ago(age)}
          </div>
          <Bars data={a.spark} color={a.hue} w={64} h={18} />
        </div>
      </div>
      <div className="acard-work">{a.work}</div>
      {active.length > 0 && (
        <div className="acard-workers">
          {active.map((w) => (
            <button
              key={w.id}
              className="wrow"
              onClick={(e) => {
                e.stopPropagation();
                openDoc({ type: "worker", agent: a.id, worker: w });
              }}
            >
              <StatusDot status={w.status} size={5} pulse={false} />
              <span className="wrow-name">{w.name}</span>
              <span className="wrow-prog">
                <span className="prog-bar prog-bar-sm">
                  {w.progress != null && (
                    <span
                      className="prog-fill"
                      style={{ width: Math.round(w.progress) + "%", background: a.hue }}
                    />
                  )}
                </span>
              </span>
              <span className="wrow-pct">
                {w.progress != null ? Math.round(w.progress) + "%" : "—"}
              </span>
            </button>
          ))}
        </div>
      )}
      <div className="acard-foot">
        <span className="chip">
          <b>{a.workers}</b> workers
        </span>
        <span className="chip">
          <b>{a.todos}</b> todos
        </span>
        <span className="chip chip-read">read report ↗</span>
        {stale && a.loop === "running" && (
          <span className="chip chip-warn">stale {age == null ? "" : fmt.ago(age)}</span>
        )}
      </div>
    </div>
  );
}

/* ---- agent row (list layout) ----------------------------------------- */

interface AgentRowProps {
  a: ContractAgent;
  now: number;
  workers: ContractWorker[];
  openDoc: OpenDoc;
}

function AgentRow({ a, now, workers, openDoc }: AgentRowProps) {
  const c = statusColor(a.status);
  const hasHb = a.heartbeat != null;
  const age = hasHb ? now - a.heartbeat! : null;
  const stale = age != null && age > STALE_MS;
  const active = workers.filter((w) => w.status !== "idle");
  return (
    <React.Fragment>
      <button
        className="arow"
        onClick={() => openDoc({ type: "agent", agent: a.id })}
        style={{ ["--hue" as string]: a.hue }}
      >
        <span className="arow-name">
          <span className="glyph glyph-sm" style={{ color: a.hue, borderColor: a.hue + "55" }}>
            {a.name}
          </span>
        </span>
        <span className="arow-status" style={{ color: c }}>
          <StatusDot status={a.status} size={6} />
          {a.status}
        </span>
        <span className="arow-loop">{a.loop}</span>
        <span className="arow-work">{a.work}</span>
        <span className="arow-num">{a.workers}</span>
        <span className="arow-num">{a.todos}</span>
        <span className={"arow-age" + (stale ? " is-stale" : "")}>
          {age == null ? "—" : fmt.ago(age)}
        </span>
        <span className="arow-spark">
          <Bars data={a.spark} color={a.hue} w={70} h={16} />
        </span>
      </button>
      {active.map((w) => (
        <button
          key={w.id}
          className="arow arow-sub"
          onClick={() => openDoc({ type: "worker", agent: a.id, worker: w })}
          style={{ ["--hue" as string]: a.hue }}
        >
          <span className="arow-name arow-subname">
            <span className="swim-tree">└</span> {w.name}
          </span>
          <span className="arow-status" style={{ color: statusColor(w.status) }}>
            <StatusDot status={w.status} size={5} pulse={false} />
            {w.status}
          </span>
          <span className="arow-loop">worker</span>
          <span className="arow-work arow-subwork">brief · {w.name}</span>
          <span className="arow-num" />
          <span className="arow-num" />
          <span className="arow-age">
            {w.started == null ? "—" : fmt.ago(now - w.started)}
          </span>
          <span className="arow-spark arow-subprog">
            <span className="prog-bar">
              {w.progress != null && (
                <span
                  className="prog-fill"
                  style={{ width: Math.round(w.progress) + "%", background: a.hue }}
                />
              )}
            </span>
          </span>
        </button>
      ))}
    </React.Fragment>
  );
}

/* ---- task rail (WORK · IN FLIGHT) ------------------------------------- */

interface TaskRailProps {
  s: ContractState;
  openDoc: OpenDoc;
}

function TaskRail({ s, openDoc }: TaskRailProps) {
  const { running, queued, done } = s.tasks;
  return (
    <Panel title="WORK · IN FLIGHT" right={running.length + " running"} className="taskpanel">
      <div className="tasksum">
        <div className="tsum">
          <b style={{ color: "#3fd17a" }}>{running.length}</b>
          <span>running</span>
        </div>
        <div className="tsum">
          <b style={{ color: "#f0a23b" }}>{queued.length}</b>
          <span>queued</span>
        </div>
        <div className="tsum">
          <b style={{ color: "#8b95a4" }}>{done.length}</b>
          <span>done</span>
        </div>
      </div>
      <div className="tasklist">
        {running.map((t: ContractTask) => {
          const hue = defOf(t.agent)?.hue;
          return (
            <button
              key={t.id}
              className="taskitem"
              onClick={() => openDoc({ type: "agent", agent: t.agent })}
            >
              <StatusDot status="active" hue={statusColor("active")} size={6} />
              <span className="task-owner" style={{ color: hue }}>
                {t.owner}
              </span>
              <span className="task-title">{t.title}</span>
              <span className="task-prog">
                <span className="prog-bar">
                  {t.progress != null && (
                    <span
                      className="prog-fill"
                      style={{ width: Math.round(t.progress) + "%", background: hue }}
                    />
                  )}
                </span>
                {t.progress != null ? Math.round(t.progress) + "%" : "—"}
              </span>
            </button>
          );
        })}
        {queued.map((t: ContractTask) => {
          const hue = defOf(t.agent)?.hue;
          return (
            <button
              key={t.id}
              className="taskitem is-queued"
              onClick={() => openDoc({ type: "agent", agent: t.agent })}
            >
              <span className="qdot" />
              <span className="task-owner" style={{ color: hue }}>
                {t.owner}
              </span>
              <span className="task-title">{t.title}</span>
              <span className="task-prog task-queuedlbl">queued</span>
            </button>
          );
        })}
      </div>
    </Panel>
  );
}

/* ---- live stream ------------------------------------------------------ */

export interface LiveStreamProps {
  events: ContractEvent[];
  max?: number;
  openDoc?: OpenDoc;
}

/** Auto-scrolling activity feed. COMPLETE/complete verbs render green. */
export function LiveStream({ events, max = 40, openDoc }: LiveStreamProps) {
  const ref = useRef<HTMLDivElement>(null);
  const recent = events.slice(-max);
  useEffect(() => {
    if (ref.current) ref.current.scrollTop = ref.current.scrollHeight;
  }, [events.length]);
  return (
    <Panel title="LIVE · STREAM" right="tail -f" className="streampanel" flush>
      <div className="stream" ref={ref}>
        {recent.map((e, i) => {
          const a = defOf(e.agent);
          const isLast = i === recent.length - 1;
          const complete = e.verb === "COMPLETE" || e.verb === "complete";
          return (
            <button
              key={e.id}
              className={"streamline" + (isLast ? " is-new" : "")}
              onClick={() => openDoc && e.agent && openDoc({ type: "agent", agent: e.agent })}
            >
              <span className="sl-time">{e.at == null ? "—" : fmt.time(new Date(e.at))}</span>
              <span className="sl-agent" style={{ color: a?.hue }}>
                {a?.name}
              </span>
              <span className="sl-worker">{e.worker}</span>
              <span className={"sl-msg" + (complete ? " sl-done" : "")}>
                {e.verb} <span className="sl-obj">`{e.obj}`</span>
              </span>
            </button>
          );
        })}
      </div>
    </Panel>
  );
}

/* ---- alert rail ------------------------------------------------------- */

export interface AlertRailProps {
  alerts: ContractAlert[];
  now: number;
  openDoc?: OpenDoc;
}

/** ATTENTION · IN-LOOP — synthesized stale/attention alerts; null when empty. */
export function AlertRail({ alerts, now, openDoc }: AlertRailProps) {
  if (!alerts.length) return null;
  return (
    <Panel title="ATTENTION · IN-LOOP" right={alerts.length} className="alertpanel">
      <div className="alertlist">
        {alerts.map((al) => {
          const a = defOf(al.agent);
          return (
            <button
              key={al.id}
              className={"alertitem lvl-" + al.level}
              onClick={() => openDoc && openDoc({ type: "agent", agent: al.agent })}
            >
              <div
                className="alert-bar"
                style={{ background: al.level === "stale" ? "#f0a23b" : "#f0506b" }}
              />
              <div className="alert-body">
                <div className="alert-top">
                  <span className="alert-agent" style={{ color: a?.hue }}>
                    {a?.name}
                  </span>
                  <span className="alert-lvl">{al.level}</span>
                  <span className="alert-age">{al.at == null ? "—" : fmt.ago(now - al.at)}</span>
                </div>
                <div className="alert-msg">{al.msg}</div>
              </div>
            </button>
          );
        })}
      </div>
    </Panel>
  );
}

/* ---- the COMMAND view ------------------------------------------------- */

export interface GridViewProps {
  s: ContractState;
  /** Tweak: card grid vs. list table. Defaults to "card". */
  layout?: AgentLayout;
  openDoc: OpenDoc;
}

export function GridView({ s, layout = "card", openDoc }: GridViewProps) {
  const list = layout === "list";
  const wkOf = (id: AgentRole): ContractWorker[] => s.workers.filter((w) => w.agent === id);
  return (
    <div className="gridview">
      <HealthStrip s={s} />
      <Cadence cadence={s.cadence} />
      <div className="gridview-body">
        <div className="gridview-main">
          <Label right={s.agents.filter((a) => a.loop === "running").length + " alive"}>
            AGENTS · ALIVE NOW
          </Label>
          {list ? (
            <div className="arows">
              <div className="arows-head">
                <span>agent</span>
                <span>status</span>
                <span>loop</span>
                <span>current work</span>
                <span>wk</span>
                <span>td</span>
                <span>last</span>
                <span>24h</span>
              </div>
              {s.agents.map((a) => (
                <AgentRow key={a.id} a={a} now={s.now} workers={wkOf(a.id)} openDoc={openDoc} />
              ))}
            </div>
          ) : (
            <div className="acards">
              {s.agents.map((a) => (
                <AgentCard key={a.id} a={a} now={s.now} workers={wkOf(a.id)} openDoc={openDoc} />
              ))}
            </div>
          )}
          <TaskRail s={s} openDoc={openDoc} />
        </div>
        <div className="gridview-rail">
          <AlertRail alerts={s.alerts} now={s.now} openDoc={openDoc} />
          <LiveStream events={s.events} openDoc={openDoc} />
        </div>
      </div>
    </div>
  );
}
