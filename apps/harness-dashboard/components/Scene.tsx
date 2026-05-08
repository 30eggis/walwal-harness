"use client";
import dynamic from "next/dynamic";
import { useEffect, useState } from "react";
import type {
  AgentId,
  AgentState,
  EnvFileSummary,
  EscalationEntry,
  HarnessSnapshot,
  MeetingRecord,
  OpsServiceHealth,
  RoomId,
  RoomState,
  WorkerSnapshot,
} from "@/lib/types";
import { useHarnessStream, type ConnectionState } from "@/hooks/useHarnessStream";
import { Drawer, type DrawerTab } from "./Drawer";
import { AgentLogTab } from "./drawer/AgentLogTab";
import { RoomMetricsTab } from "./drawer/RoomMetricsTab";
import { IncidentsTab } from "./drawer/IncidentsTab";
import { HypothesisTab } from "./drawer/HypothesisTab";
import { TracksTab } from "./drawer/TracksTab";

const Stage3D = dynamic(
  () =>
    import("./three/Stage3D").then((m) => ({
      default: m.Stage3D as unknown as React.ComponentType<{
        snapshot: HarnessSnapshot;
        lang?: "ko" | "en";
        onAgentClick?: (id: AgentId) => void;
        onRoomClick?: (id: RoomId) => void;
      }>,
    })),
  { ssr: false, loading: () => <SceneFallback /> }
);

function SceneFallback() {
  return (
    <div className="flex h-full w-full items-center justify-center bg-brick-floor text-xs font-mono text-gray-400">
      Loading 3D scene…
    </div>
  );
}

interface SceneProps {
  snapshot: HarnessSnapshot;
  lang?: "ko" | "en";
}

export function Scene({ snapshot: initial, lang = "ko" }: SceneProps) {
  const { snapshot, connectionState } = useHarnessStream(initial);
  const [drawerOpen, setDrawerOpen] = useState(false);
  const [drawerTab, setDrawerTab] = useState<DrawerTab>("agent-log");
  const [selectedAgent, setSelectedAgent] = useState<AgentState | null>(null);
  const [selectedRoom, setSelectedRoom] = useState<RoomState | null>(null);

  const handleAgentClick = (id: AgentId) => {
    const a = snapshot.agents.find((x) => x.id === id) ?? null;
    setSelectedAgent(a);
    setSelectedRoom(null);
    setDrawerTab("agent-log");
    setDrawerOpen(true);
  };

  const handleRoomClick = (id: RoomId) => {
    const r = snapshot.rooms.find((x) => x.id === id) ?? null;
    setSelectedRoom(r);
    setSelectedAgent(null);
    // Route the click to the most relevant tab for that room. This way one
    // click on Service-Ops opens the incident list, one click on COO opens
    // the hypothesis list, etc., matching what the wall art is showing.
    let nextTab: DrawerTab = "room-metrics";
    if (id === "archive") nextTab = "archive-list";
    else if (id === "service-ops" && snapshot.incidents.length > 0) nextTab = "incidents";
    else if (id === "coo" && snapshot.hypothesis.length > 0) nextTab = "hypothesis";
    else if (id === "meeting" && snapshot.tracks.length > 0) nextTab = "tracks";
    setDrawerTab(nextTab);
    setDrawerOpen(true);
  };

  const drawerTitle = selectedAgent
    ? selectedAgent.name
    : selectedRoom
    ? `${selectedRoom.label_ko}`
    : "Detail";

  return (
    <div className="mx-auto max-w-[1920px] px-4 py-5">
      {snapshot.escalations.length > 0 && (
        <EscalationStrip escalations={snapshot.escalations} />
      )}
      <div className="grid gap-4 xl:grid-cols-[minmax(0,1.45fr)_minmax(360px,0.55fr)]">
        <section className="min-w-0">
          <div className="mb-3 flex flex-wrap items-end justify-between gap-3">
            <div>
              <p className="text-[11px] font-mono uppercase tracking-[0.24em] text-cyan-300/80">
                Operations Control Room
              </p>
              <h1 className="mt-1 text-2xl font-semibold text-gray-100">
                {snapshot.projectName} Mission Floor
              </h1>
            </div>
            <ActivityIndicator snapshot={snapshot} connectionState={connectionState} />
          </div>
          <div
            data-testid="brick-office-stage"
            className="relative aspect-[16/9] w-full overflow-hidden rounded-md border border-gray-700/80 bg-[#12151b] shadow-2xl"
          >
            <div className="pointer-events-none absolute inset-x-0 top-0 z-10 flex items-center justify-between border-b border-white/10 bg-black/30 px-4 py-2 font-mono text-[10px] text-gray-300 backdrop-blur">
              <span>2.5D service map</span>
              <span>{snapshot.dashboard.opsHealth.filter((s) => s.status === "ok").length}/{snapshot.dashboard.opsHealth.length || 0} services ok</span>
            </div>
            <Stage3D
              snapshot={snapshot}
              lang={lang}
              onAgentClick={handleAgentClick}
              onRoomClick={handleRoomClick}
            />
          </div>
        </section>

        <aside className="grid min-h-full gap-3">
          <MissionPanel snapshot={snapshot} />
          <WorkerPanel workers={snapshot.dashboard.workers} />
        </aside>
      </div>

      <section className="mt-4 grid gap-4 xl:grid-cols-[1.1fr_0.9fr_0.8fr]">
        <MeetingPanel meetings={snapshot.dashboard.recentMeetings} />
        <OpsPanel services={snapshot.dashboard.opsHealth} />
        <EnvPanel envFiles={snapshot.dashboard.envFiles} />
      </section>


      {/* Hidden DOM index for E2E + a11y */}
      <ul className="sr-only" data-testid="scene-index">
        {snapshot.rooms.map((r) => (
          <li
            key={r.id}
            data-testid={`room-${r.id}`}
            data-room-id={r.id}
          >
            {r.label_ko}
          </li>
        ))}
        {snapshot.agents.map((a) => (
          <li
            key={a.id}
            data-testid={`minifig-${a.id}`}
            data-agent-id={a.id}
            data-minifig-state={a.minifigState}
            data-room={a.room}
          >
            {a.name}
          </li>
        ))}
      </ul>

      <Drawer
        open={drawerOpen}
        tab={drawerTab}
        title={drawerTitle}
        onClose={() => setDrawerOpen(false)}
        onTabChange={setDrawerTab}
      >
        {drawerTab === "agent-log" && selectedAgent && (
          <AgentLogTab agentId={selectedAgent.id} />
        )}
        {drawerTab === "room-metrics" && selectedRoom && (
          <RoomMetricsTab room={selectedRoom} />
        )}
        {drawerTab === "agent-log" && !selectedAgent && (
          <div className="text-gray-500">
            Click a minifigure to view its log.
          </div>
        )}
        {drawerTab === "room-metrics" && !selectedRoom && (
          <div className="text-gray-500">Click a room to view its metrics.</div>
        )}
        {drawerTab === "archive-list" && (
          <ArchiveList snapshot={snapshot} />
        )}
        {drawerTab === "incidents" && (
          <IncidentsTab incidents={snapshot.incidents} />
        )}
        {drawerTab === "hypothesis" && (
          <HypothesisTab hypothesis={snapshot.hypothesis} />
        )}
        {drawerTab === "tracks" && (
          <TracksTab tracks={snapshot.tracks} />
        )}
      </Drawer>
    </div>
  );
}

function ActivityIndicator({
  snapshot,
  connectionState,
}: {
  snapshot: HarnessSnapshot;
  connectionState: ConnectionState;
}) {
  const [now, setNow] = useState(Date.now());
  useEffect(() => {
    const id = setInterval(() => setNow(Date.now()), 5000);
    return () => clearInterval(id);
  }, []);
  const ts = Date.parse(snapshot.ts);
  const ageSec = Number.isFinite(ts) ? Math.max(0, Math.floor((now - ts) / 1000)) : null;
  const isStale = ageSec !== null && ageSec > 30;
  return (
    <div className="flex items-center gap-2 text-[10px] font-mono">
      <span
        data-testid="connection-state"
        data-state={connectionState}
        className={`inline-block rounded px-2 py-0.5 ${
          connectionState === "open"
            ? "bg-aura-typing/20 text-aura-typing"
            : connectionState === "stale"
            ? "bg-aura-talking/20 text-aura-talking"
            : connectionState === "failed"
            ? "bg-aura-alert/20 text-aura-alert"
            : "bg-gray-500/20 text-gray-400"
        }`}
      >
        SSE: {connectionState}
      </span>
      <span
        data-testid="activity-age"
        data-stale={isStale}
        className={`inline-block rounded px-2 py-0.5 ${
          isStale
            ? "bg-aura-alert/20 text-aura-alert"
            : "bg-aura-typing/20 text-aura-typing"
        }`}
      >
        {ageSec === null
          ? "—"
          : isStale
          ? `stale ${ageSec}s — 회사가 멈춰 보입니다`
          : `live ${ageSec}s ago`}
      </span>
      {snapshot.errorBanner && (
        <span className="inline-block rounded bg-aura-alert/20 px-2 py-0.5 text-aura-alert">
          banner: {snapshot.errorBanner.level}
        </span>
      )}
    </div>
  );
}

function Panel({
  title,
  eyebrow,
  children,
}: {
  title: string;
  eyebrow?: string;
  children: React.ReactNode;
}) {
  return (
    <section className="rounded-md border border-gray-700/80 bg-[#171a20]/95 p-3 shadow-xl">
      <div className="mb-3 flex items-center justify-between gap-3">
        <div>
          {eyebrow && (
            <p className="font-mono text-[10px] uppercase tracking-[0.2em] text-cyan-300/70">
              {eyebrow}
            </p>
          )}
          <h2 className="text-sm font-semibold text-gray-100">{title}</h2>
        </div>
      </div>
      {children}
    </section>
  );
}

function MissionPanel({ snapshot }: { snapshot: HarnessSnapshot }) {
  const total = snapshot.contract.feature_total;
  const done = snapshot.contract.feature_passed;
  const progress = total > 0 ? Math.round((done / total) * 100) : null;
  return (
    <Panel title="Current Mission" eyebrow="goal / contract">
      <div className="space-y-3">
        <div>
          <div className="font-mono text-[10px] text-gray-500">
            {snapshot.goal?.id ?? "goal"}
          </div>
          <div className="mt-1 text-base font-semibold leading-snug text-gray-100">
            {snapshot.goal?.title ?? "No active goal registered"}
          </div>
          {snapshot.goal?.description_truncated && (
            <p className="mt-2 text-xs leading-relaxed text-gray-400">
              {snapshot.goal.description_truncated}
            </p>
          )}
        </div>
        <div className="grid grid-cols-3 gap-2">
          <Metric label="Cycle" value={snapshot.contract.sprint_number ?? "—"} tone="neutral" />
          <Metric label="Features" value={`${done}/${total || 0}`} tone="cyan" />
          <Metric label="Pass" value={progress === null ? "—" : `${progress}%`} tone="green" />
        </div>
        <div className="h-2 overflow-hidden rounded bg-gray-800">
          <div
            className="h-full bg-gradient-to-r from-cyan-400 via-emerald-400 to-amber-300"
            style={{ width: `${progress ?? 0}%` }}
          />
        </div>
        <div className="grid grid-cols-2 gap-2 text-[11px]">
          <StatusLine label="Meeting cadence" value={snapshot.meetings.cadence} />
          <StatusLine label="Next agent" value={snapshot.agents.find((a) => a.lastActivity?.includes("next_agent"))?.name ?? "—"} />
        </div>
      </div>
    </Panel>
  );
}

function WorkerPanel({ workers }: { workers: WorkerSnapshot[] }) {
  return (
    <Panel title="Active Workstreams" eyebrow="friends working now">
      {workers.length === 0 ? (
        <EmptyLine text="No active workers. Conductor will dispatch when queue is ready." />
      ) : (
        <div className="space-y-2">
          {workers.slice(0, 5).map((w) => (
            <div key={`${w.team}-${w.feature}`} className="rounded border border-gray-700/70 bg-black/20 p-2">
              <div className="flex items-start justify-between gap-2">
                <div className="min-w-0">
                  <div className="font-mono text-[10px] uppercase text-cyan-300">
                    T{w.team} · {w.agent}
                  </div>
                  <div className="mt-0.5 truncate text-sm font-medium text-gray-100">
                    {w.feature} · {w.title ?? w.feature}
                  </div>
                </div>
                <span className={`shrink-0 rounded px-2 py-0.5 font-mono text-[10px] ${statusTone(w.status)}`}>
                  {w.status}
                </span>
              </div>
              <p className="mt-2 line-clamp-2 text-[11px] leading-relaxed text-gray-400">
                {w.summary}
              </p>
              <div className="mt-2 h-1.5 overflow-hidden rounded bg-gray-800">
                <div className="h-full bg-cyan-300" style={{ width: `${Math.round((w.progress ?? 0.25) * 100)}%` }} />
              </div>
              {w.next_material && (
                <div className="mt-2 truncate font-mono text-[10px] text-amber-300/80">
                  next material: {w.next_material}
                </div>
              )}
            </div>
          ))}
        </div>
      )}
    </Panel>
  );
}

function MeetingPanel({ meetings }: { meetings: MeetingRecord[] }) {
  return (
    <Panel title="Recent Meetings" eyebrow="minutes / decisions">
      {meetings.length === 0 ? (
        <EmptyLine text="No meeting minutes yet." />
      ) : (
        <div className="space-y-2">
          {meetings.slice(0, 4).map((m) => (
            <div key={m.path} className="grid gap-2 rounded border border-gray-700/70 bg-black/20 p-2 md:grid-cols-[150px_1fr]">
              <div className="font-mono text-[10px] text-gray-500">
                <div className="truncate text-gray-300">{m.id}</div>
                <div>{m.ts ? new Date(m.ts).toLocaleString() : "—"}</div>
                {m.verdict && <div className="mt-1 text-amber-300">{m.verdict}</div>}
              </div>
              <div className="min-w-0">
                <div className="truncate text-sm font-medium text-gray-100">{m.title}</div>
                <p className="mt-1 line-clamp-2 text-[11px] leading-relaxed text-gray-400">{m.summary}</p>
                <div className="mt-1 truncate font-mono text-[10px] text-cyan-300/70">{m.path}</div>
              </div>
            </div>
          ))}
        </div>
      )}
    </Panel>
  );
}

function OpsPanel({ services }: { services: OpsServiceHealth[] }) {
  return (
    <Panel title="Service-Ops" eyebrow="production monitor">
      {services.length === 0 ? (
        <EmptyLine text="No production services configured." />
      ) : (
        <div className="space-y-1.5">
          {services.map((s) => (
            <div key={`${s.name}-${s.port}`} className="flex items-center justify-between gap-2 rounded border border-gray-700/60 bg-black/20 px-2 py-1.5">
              <div className="min-w-0">
                <div className="truncate text-xs font-medium text-gray-100">{s.name}</div>
                <div className="font-mono text-[10px] text-gray-500">
                  {s.host}:{s.port}{s.health_path ? ` · ${s.health_path}` : ""}
                </div>
              </div>
              <div className="text-right">
                <span className={`rounded px-2 py-0.5 font-mono text-[10px] ${serviceTone(s.status)}`}>
                  {s.status}
                </span>
                <div className="mt-1 font-mono text-[10px] text-gray-500">
                  {s.health_status ?? s.port_state ?? "—"}
                </div>
              </div>
            </div>
          ))}
        </div>
      )}
    </Panel>
  );
}

function EnvPanel({ envFiles }: { envFiles: EnvFileSummary[] }) {
  const first = envFiles[0];
  const firstKey = first?.keys[0]?.key ?? "";
  const [file, setFile] = useState(first?.path ?? ".env");
  const [key, setKey] = useState(firstKey);
  const [value, setValue] = useState("");
  const [status, setStatus] = useState<string | null>(null);

  const submitEnv = async () => {
    setStatus("saving");
    try {
      const res = await fetch("/api/env", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ file, key, value }),
      });
      const body = await res.json().catch(() => ({}));
      if (!res.ok || !body.ok) {
        setStatus(body.error ?? "failed");
        return;
      }
      setValue("");
      setStatus(body.replaced ? "updated" : "added");
    } catch {
      setStatus("failed");
    }
  };

  return (
    <Panel title="Environment Control" eyebrow="masked .env overview">
      {envFiles.length === 0 ? (
        <EmptyLine text="No .env files found at project root." />
      ) : (
        <div className="space-y-2">
          <div className="rounded border border-cyan-400/30 bg-cyan-400/5 p-2">
            <div className="grid gap-2 sm:grid-cols-[1fr_1fr]">
              <label className="grid gap-1 font-mono text-[10px] text-gray-400">
                file
                <select
                  value={file}
                  onChange={(e) => {
                    setFile(e.target.value);
                    const nextFile = envFiles.find((item) => item.path === e.target.value);
                    setKey(nextFile?.keys[0]?.key ?? "");
                  }}
                  className="rounded border border-gray-700 bg-[#11151a] px-2 py-1 text-xs text-gray-100"
                >
                  {envFiles.map((item) => (
                    <option key={item.path} value={item.path}>
                      {item.path}
                    </option>
                  ))}
                </select>
              </label>
              <label className="grid gap-1 font-mono text-[10px] text-gray-400">
                key
                <select
                  value={key}
                  onChange={(e) => setKey(e.target.value)}
                  className="rounded border border-gray-700 bg-[#11151a] px-2 py-1 text-xs text-gray-100"
                >
                  {(envFiles.find((item) => item.path === file)?.keys ?? []).map((item) => (
                    <option key={item.key} value={item.key}>
                      {item.key}
                    </option>
                  ))}
                </select>
              </label>
            </div>
            <div className="mt-2 flex gap-2">
              <input
                value={value}
                onChange={(e) => setValue(e.target.value)}
                placeholder="new value, never stored in browser"
                className="min-w-0 flex-1 rounded border border-gray-700 bg-[#11151a] px-2 py-1 text-xs text-gray-100 placeholder:text-gray-600"
              />
              <button
                type="button"
                onClick={submitEnv}
                disabled={!file || !key}
                className="rounded border border-cyan-400/50 px-3 py-1 font-mono text-[10px] uppercase text-cyan-200 hover:bg-cyan-400/10 disabled:cursor-not-allowed disabled:opacity-40"
              >
                Apply
              </button>
            </div>
            {status && <div className="mt-1 font-mono text-[10px] text-amber-300">{status}</div>}
          </div>
          {envFiles.map((file) => (
            <div key={file.path} className="rounded border border-gray-700/70 bg-black/20 p-2">
              <div className="flex items-center justify-between gap-2">
                <div className="font-mono text-xs text-gray-100">{file.path}</div>
                <div className="font-mono text-[10px] text-gray-500">{file.key_count} keys</div>
              </div>
              <div className="mt-2 grid gap-1">
                {file.keys.slice(0, 5).map((k) => (
                  <div key={k.key} className="flex items-center justify-between gap-2 font-mono text-[10px]">
                    <span className="truncate text-gray-400">{k.key}</span>
                    <span className={k.category === "secret" ? "text-rose-300" : "text-cyan-300/80"}>
                      {k.masked}
                    </span>
                  </div>
                ))}
              </div>
              <p className="mt-2 text-[10px] leading-relaxed text-gray-500">
                Server-side editor target. Values stay masked until an explicit edit flow is opened.
              </p>
            </div>
          ))}
        </div>
      )}
    </Panel>
  );
}

function Metric({ label, value, tone }: { label: string; value: React.ReactNode; tone: "neutral" | "cyan" | "green" }) {
  const color = tone === "cyan" ? "text-cyan-300" : tone === "green" ? "text-emerald-300" : "text-gray-200";
  return (
    <div className="rounded border border-gray-700/70 bg-black/20 px-2 py-2">
      <div className="font-mono text-[10px] uppercase text-gray-500">{label}</div>
      <div className={`mt-1 text-lg font-semibold ${color}`}>{value}</div>
    </div>
  );
}

function StatusLine({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <div className="flex items-center justify-between gap-2 rounded bg-black/20 px-2 py-1 font-mono">
      <span className="text-gray-500">{label}</span>
      <span className="truncate text-gray-200">{value}</span>
    </div>
  );
}

function EmptyLine({ text }: { text: string }) {
  return <div className="rounded border border-dashed border-gray-700 px-3 py-6 text-center text-xs text-gray-500">{text}</div>;
}

function statusTone(status: WorkerSnapshot["status"]): string {
  if (status === "spawned" || status === "running") return "bg-cyan-400/15 text-cyan-300";
  if (status === "recorded") return "bg-amber-400/15 text-amber-300";
  if (status === "blocked") return "bg-rose-500/15 text-rose-300";
  return "bg-gray-500/15 text-gray-300";
}

function serviceTone(status: OpsServiceHealth["status"]): string {
  if (status === "ok") return "bg-emerald-400/15 text-emerald-300";
  if (status === "degraded") return "bg-amber-400/15 text-amber-300";
  if (status === "down") return "bg-rose-500/15 text-rose-300";
  return "bg-gray-500/15 text-gray-300";
}

function EscalationStrip({ escalations }: { escalations: EscalationEntry[] }) {
  return (
    <div
      data-testid="escalation-strip"
      role="alert"
      className="mb-3 flex flex-wrap items-center gap-2 rounded border border-aura-alert/60 bg-aura-alert/10 px-3 py-2 text-xs font-mono text-aura-alert"
    >
      <span className="font-semibold uppercase tracking-widest">
        ↑ {escalations.length} escalation{escalations.length === 1 ? "" : "s"}
      </span>
      {escalations.slice(0, 3).map((e) => (
        <span
          key={e.id}
          data-testid={`escalation-${e.id}`}
          className="rounded bg-aura-alert/20 px-2 py-0.5 text-[10px]"
        >
          {e.id} · {e.reason}
        </span>
      ))}
      {escalations.length > 3 && (
        <span className="text-[10px] opacity-70">+{escalations.length - 3} more</span>
      )}
    </div>
  );
}

function ArchiveList({ snapshot }: { snapshot: HarnessSnapshot }) {
  const list = snapshot.archive.all ?? snapshot.archive.recent ?? [];
  if (list.length === 0) {
    return <div className="text-gray-500">No archived sprints yet.</div>;
  }
  return (
    <ul className="space-y-1">
      {list.map((entry) => (
        <li
          key={entry.dir}
          className="flex justify-between rounded border border-brick-wall bg-brick-wall/30 px-2 py-1"
        >
          <span>{entry.label}</span>
          <span
            className={
              entry.result === "PASS"
                ? "text-aura-typing"
                : entry.result === "FAIL"
                ? "text-aura-alert"
                : "text-gray-500"
            }
          >
            {entry.result}
          </span>
        </li>
      ))}
    </ul>
  );
}
