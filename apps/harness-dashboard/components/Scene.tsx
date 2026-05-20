"use client";
import { useEffect, useState } from "react";
import type {
  AgentState,
  EnvFileSummary,
  EscalationEntry,
  HarnessSnapshot,
  MissionDoc,
  OpsServiceHealth,
  OrgNodeDef,
  WorkerSnapshot,
} from "@/lib/types";
import { useHarnessStream, type ConnectionState } from "@/hooks/useHarnessStream";
import { Drawer, type DrawerTab } from "./Drawer";
import { AgentLogTab } from "./drawer/AgentLogTab";
import { OwnerHistoryTab } from "./drawer/OwnerHistoryTab";
import { MissionDocTab } from "./drawer/MissionDocTab";
import { MissionFlowTab } from "./drawer/MissionFlowTab";
import { GotchasTab } from "./drawer/GotchasTab";
import { MissionTimeline } from "./MissionTimeline";
import { OrgTree } from "./OrgTree";

interface SceneProps {
  snapshot: HarnessSnapshot;
  lang?: "ko" | "en";
}

export function Scene({ snapshot: initial, lang = "ko" }: SceneProps) {
  const { snapshot, connectionState } = useHarnessStream(initial);
  const [drawerTab, setDrawerTab] = useState<DrawerTab>("mission-flow");
  const [selectedAgent, setSelectedAgent] = useState<AgentState | null>(null);
  const [selectedNode, setSelectedNode] = useState<OrgNodeDef | null>(null);
  const [selectedMission, setSelectedMission] = useState<MissionDoc | null>(null);

  const handleAgentClick = (id: string) => {
    const a = snapshot.agents.find((x) => x.id === id) ?? null;
    setSelectedAgent(a);
    setSelectedNode(null);
    setDrawerTab("logs");
  };

  const handleNodeClick = (node: OrgNodeDef) => {
    const currentMission = snapshot.missions?.[0] ?? null;
    setSelectedNode(node);
    setSelectedAgent(null);
    if (currentMission) {
      setSelectedMission(currentMission);
    }
    if (node.id === "owner") {
      setDrawerTab("history");
    } else if (node.id.startsWith("worker-")) {
      setDrawerTab("mission-doc");
    } else {
      setDrawerTab("mission-doc");
    }
  };

  const handleMissionClick = (mission: MissionDoc) => {
    setSelectedMission(mission);
    setSelectedNode(null);
    setSelectedAgent(null);
    setDrawerTab("mission-flow");
  };

  const drawerTitle =
    selectedMission && drawerTab === "mission-flow"
      ? selectedMission.missionId
      : selectedNode?.id === "owner"
      ? "Owner · History"
      : selectedNode
      ? selectedNode.label
      : "Mission Flow";
  const drawerScrollResetKey = [
    drawerTab,
    selectedMission?.missionId ?? "",
    selectedNode?.id ?? "",
    selectedAgent?.id ?? "",
  ].join(":");
  const selectedWorkerName = selectedNode?.id.startsWith("worker-")
    ? selectedNode.label
    : undefined;
  const selectedDocumentRole = selectedWorkerName
    ? "worker"
    : selectedNode?.role === "owner"
    ? "ceo"
    : selectedNode?.role;

  // Suppress unused lang warning — kept for future i18n
  void lang;

  return (
    <div className="flex h-[100dvh] w-full flex-col overflow-hidden px-4 py-5">
      {snapshot.escalations.length > 0 && (
        <EscalationStrip escalations={snapshot.escalations} />
      )}
      <div className="grid min-h-0 flex-1 min-w-0 gap-4 lg:grid-cols-2">
        <div className="scrollbar-hidden min-h-0 min-w-0 overflow-y-auto pr-1">
          <section className="min-w-0">
            <div className="mb-3 flex flex-wrap items-end justify-between gap-3">
              <div>
                <p className="text-[11px] font-mono uppercase tracking-[0.24em] text-cyan-300/80">
                  Company Structure
                </p>
                <h1 className="mt-1 text-2xl font-semibold text-gray-100">
                  {snapshot.projectName || "walwal-harness"} · Organization
                </h1>
              </div>
              <ActivityIndicator snapshot={snapshot} connectionState={connectionState} />
            </div>
            <div
              data-testid="brick-office-stage"
              className="w-full overflow-x-auto rounded-md border border-gray-700/80 bg-[#12151b] shadow-2xl"
            >
              <div className="pointer-events-none flex items-center justify-between gap-3 border-b border-white/10 bg-black/30 px-4 py-2 font-mono text-[10px] text-gray-300 backdrop-blur">
                <span>Owner → CEO → CXX → Workers</span>
                <span className="truncate">
                  {snapshot.missions?.[0]?.missionId ?? "no active mission"}
                  {snapshot.missions?.[0]?.cxxPresent.length
                    ? ` · ${snapshot.missions[0].cxxPresent.join(" / ")}`
                    : ""}
                </span>
              </div>
              <OrgTree
                snapshot={snapshot}
                activeNodeId={selectedNode?.id ?? null}
                onNodeClick={handleNodeClick}
              />
            </div>
          </section>

          <section className="mt-4">
            <div className="mb-2">
              <p className="font-mono text-[10px] uppercase tracking-[0.2em] text-cyan-300/60">Mission History</p>
              <p className="text-[11px] text-gray-500 mt-0.5">goal · submission · hot-fix 명령별 파생 작업 흐름</p>
            </div>
            <MissionTimeline
              missions={snapshot.missions ?? []}
              activeMissionId={selectedMission?.missionId ?? null}
              onMissionClick={handleMissionClick}
            />
          </section>
        </div>

        <div className="min-h-0 min-w-0">
          <Drawer
            mode="inline"
            open={true}
            tab={drawerTab}
            title={drawerTitle}
            onClose={() => undefined}
            onTabChange={setDrawerTab}
            scrollResetKey={drawerScrollResetKey}
          >
            {drawerTab === "mission-flow" && (
              <MissionFlowTab
                mission={selectedMission ?? snapshot.missions?.[0] ?? null}
                ownerHistory={snapshot.ownerHistory ?? []}
              />
            )}
            {drawerTab === "history" && (
              <OwnerHistoryTab
                ownerHistory={snapshot.ownerHistory ?? []}
                mission={selectedMission ?? snapshot.missions?.[0] ?? null}
              />
            )}
            {drawerTab === "gotchas" && (
              <GotchasTab gotchas={snapshot.gotchas ?? []} />
            )}
            {drawerTab === "mission-doc" && selectedNode && (
              <MissionDocTab
                missions={snapshot.missions ?? []}
                role={selectedDocumentRole as "ceo" | "cto" | "cqo" | "coo" | "cdo" | "ops" | "worker"}
                workerName={selectedWorkerName}
                fromLabel={
                  selectedWorkerName
                    ? selectedNode.role.toUpperCase()
                    : selectedNode.role === "ceo"
                    ? "Owner"
                    : "CEO"
                }
                toLabel={
                  selectedWorkerName
                    ? "Evidence"
                    : selectedNode.role === "cto"
                    ? "Workers"
                    : selectedNode.role === "cqo"
                    ? "Owner Report"
                    : "—"
                }
              />
            )}
            {drawerTab === "logs" && selectedNode && (
              <AgentLogTab agentId={selectedNode.agentIds[0] ?? selectedNode.id} />
            )}
            {drawerTab === "logs" && selectedAgent && !selectedNode && (
              <AgentLogTab agentId={selectedAgent.id} />
            )}
            {drawerTab === "logs" && !selectedNode && !selectedAgent && (
              <div className="text-gray-500 text-xs">Select a node to view logs.</div>
            )}
            {drawerTab === "mission-flow" && !selectedMission && !snapshot.missions?.length && (
              <div className="text-gray-500 text-xs">No missions found in .harness/documents/</div>
            )}
          </Drawer>
        </div>
      </div>

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

function featureTone(status: string): string {
  if (status === "passed") return "text-emerald-300";
  if (status === "failed" || status === "blocked") return "text-rose-300";
  if (status === "in_progress" || status === "ready") return "text-cyan-300";
  return "text-gray-500";
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

// Keep unused helper functions to avoid breaking other panels if needed later
void Panel;
void Metric;
void StatusLine;
void EmptyLine;
void statusTone;
void featureTone;
void serviceTone;

function OpsPanel({ services }: { services: OpsServiceHealth[] }) {
  return (
    <section className="rounded-md border border-gray-700/80 bg-[#171a20]/95 p-3 shadow-xl">
      <div className="mb-3">
        <p className="font-mono text-[10px] uppercase tracking-[0.2em] text-cyan-300/70">production monitor</p>
        <h2 className="text-sm font-semibold text-gray-100">Service-Ops</h2>
      </div>
      {services.length === 0 ? (
        <div className="rounded border border-dashed border-gray-700 px-3 py-6 text-center text-xs text-gray-500">No production services configured.</div>
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
    </section>
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
    <section className="rounded-md border border-gray-700/80 bg-[#171a20]/95 p-3 shadow-xl">
      <div className="mb-3">
        <p className="font-mono text-[10px] uppercase tracking-[0.2em] text-cyan-300/70">masked .env overview</p>
        <h2 className="text-sm font-semibold text-gray-100">Environment Control</h2>
      </div>
      {envFiles.length === 0 ? (
        <div className="rounded border border-dashed border-gray-700 px-3 py-6 text-center text-xs text-gray-500">No .env files found at project root.</div>
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
    </section>
  );
}

// Keep OpsPanel and EnvPanel available for future reuse
void OpsPanel;
void EnvPanel;

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

// Keep ArchiveList available for future reuse
void ArchiveList;
