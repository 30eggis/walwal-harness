"use client";

/* =============================================================
   walwal-harness · BRICK OFFICE — App shell
   Ported from design_handoff_harness_dashboard/Harness Dashboard.html
   App() (lines ~395-437) + the view switch.

   The mockup drove its state from a `useHarness(motion)` simulation;
   here we drive it from the REAL SSE feed (useHarnessStream) mapped
   through toContractState(snapshot, connected, nowMs). The shell ticks
   a `nowMs` clock ~1/s so "ago"/heartbeat/stale read live.

   The mockup set data-tone / data-density on <body>; in the Next app the
   shell is a component, so those attributes (and the .brick scope class)
   live on the shell root <div>.

   brick.css is imported at app/layout level (see app/layout.tsx), matching
   how Scene's CSS is loaded via globals.css.
   ============================================================= */

import React, { useEffect, useState } from "react";

import type { HarnessSnapshot } from "../../lib/types";
import { useHarnessStream } from "../../hooks/useHarnessStream";
import { toContractState } from "../../lib/brick/adapter";
import type { AgentRole, DocTarget } from "../../lib/brick/contract";
import type { MetricsSample } from "../../lib/metrics/sampler";

import { Header, Sidebar, type BrickView } from "./ui";
import { GridView } from "./views-grid";
import { GraphView } from "./views-graph";
import { TimelineView } from "./views-timeline";
import { DocViewer } from "./reports";
import { BrickTweaks, useTweaks } from "./tweaks";

export interface BrickDashboardProps {
  /** Server-rendered initial snapshot, hydrated then kept fresh over SSE. */
  initialSnapshot: HarnessSnapshot;
}

export function BrickDashboard({
  initialSnapshot,
}: BrickDashboardProps): React.JSX.Element {
  const { snapshot, connectionState } = useHarnessStream(initialSnapshot);

  // tweaks (agent layout / density / live motion / surface) — persisted.
  const [t, setTweak] = useTweaks();

  // top-level view + chrome state (mirrors the mockup App() useState block).
  const [view, setView] = useState<BrickView>("grid");
  const [collapsed, setCollapsed] = useState(false);
  const [sel, setSel] = useState<AgentRole>("cto");
  const [doc, setDoc] = useState<DocTarget | null>(null);

  // ~1/s clock so "ago"/heartbeat/stale derive against a live `now`.
  const [nowMs, setNowMs] = useState<number>(() => Date.now());
  useEffect(() => {
    const id = window.setInterval(() => setNowMs(Date.now()), 1000);
    return () => window.clearInterval(id);
  }, []);

  // REAL telemetry poll (read-only): /api/metrics every ~5s. On any failure we
  // keep the last good sample (or null), and the honest "—" placeholders stand.
  const [metrics, setMetrics] = useState<MetricsSample | null>(null);
  useEffect(() => {
    let cancelled = false;
    const poll = async (): Promise<void> => {
      try {
        const res = await fetch("/api/metrics", { cache: "no-store" });
        if (!res.ok) return;
        const sample = (await res.json()) as MetricsSample;
        if (!cancelled && sample && typeof sample === "object") {
          setMetrics(sample);
        }
      } catch {
        /* network/parse error — keep last sample; never fabricate */
      }
    };
    void poll();
    const id = window.setInterval(() => void poll(), 5000);
    return () => {
      cancelled = true;
      window.clearInterval(id);
    };
  }, []);

  // build the single Contract state object every view renders from.
  const connected = connectionState === "open";
  const s = toContractState(snapshot, connected, nowMs);

  // Override the adapter's honest nulls with REAL sampled telemetry where it
  // exists. Anything still null stays null -> the views render "—".
  if (metrics) {
    s.metrics.tokensPerMin = metrics.tokensPerMin;
    s.metrics.costToday = metrics.costToday;
    s.metrics.cpu = metrics.cpu;
    s.metrics.contextPct = metrics.contextPct;
    s.metrics.costEstimated = metrics.costEstimated;
    s.mtrend = metrics.mtrend ?? [];
    s.ctrend = metrics.ctrend ?? [];
  }

  // All three views render on one screen; the header buttons jump to a section.
  useEffect(() => {
    const id =
      view === "grid" ? "view-command" : view === "graph" ? "view-orchestration" : "view-timeline";
    document.getElementById(id)?.scrollIntoView({ behavior: "smooth", block: "start" });
  }, [view]);

  const openDoc = (target: DocTarget): void => setDoc(target);
  const closeDoc = (): void => setDoc(null);

  return (
    <div className="brick" data-tone={t.surface} data-density={t.density}>
      <div className="app">
        <Header metrics={s.metrics} view={view} setView={setView} alerts={s.alerts} />
        <div className="app-body">
          <Sidebar
            collapsed={collapsed}
            onToggle={() => setCollapsed((c) => !c)}
            missions={snapshot.missions}
            ownerHistory={snapshot.ownerHistory}
          />
          <div className="app-main">
            {/* All three views consolidated on one scrolling screen — no
                switching. The header COMMAND/ORCHESTRATION/TIMELINE buttons
                jump to the matching section. */}
            <div className="viewstack">
              <section className="viewsection viewsection-command" id="view-command">
                <div className="viewsection-head"><b>Command</b><span>agents · work in flight · live stream</span></div>
                <div className="viewsection-body">
                  <GridView s={s} layout={t.agentLayout} openDoc={openDoc} />
                </div>
              </section>
              <section className="viewsection viewsection-graph" id="view-orchestration">
                <div className="viewsection-head"><b>Orchestration</b><span>CEO → CXX → workers</span></div>
                <div className="viewsection-body">
                  <GraphView s={s} sel={sel} setSel={setSel} openDoc={openDoc} />
                </div>
              </section>
              <section className="viewsection viewsection-timeline" id="view-timeline">
                <div className="viewsection-head"><b>Timeline</b><span>swimlanes · last 12h</span></div>
                <div className="viewsection-body">
                  <TimelineView s={s} openDoc={openDoc} />
                </div>
              </section>
            </div>
          </div>
        </div>

        <DocViewer
          target={doc}
          state={s}
          onClose={closeDoc}
          onRetarget={openDoc}
        />

        <BrickTweaks values={t} setTweak={setTweak} />
      </div>
    </div>
  );
}

export default BrickDashboard;
