"use client";
import dynamic from "next/dynamic";
import { useEffect, useState } from "react";
import type { AgentId, AgentState, HarnessSnapshot, RoomId, RoomState } from "@/lib/types";
import { useHarnessStream, type ConnectionState } from "@/hooks/useHarnessStream";
import { Drawer, type DrawerTab } from "./Drawer";
import { AgentLogTab } from "./drawer/AgentLogTab";
import { RoomMetricsTab } from "./drawer/RoomMetricsTab";

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
    setDrawerTab(id === "archive" ? "archive-list" : "room-metrics");
    setDrawerOpen(true);
  };

  const drawerTitle = selectedAgent
    ? selectedAgent.name
    : selectedRoom
    ? `${selectedRoom.label_ko}`
    : "Detail";

  return (
    <div className="mx-auto max-w-[1920px] px-4 py-6">
      <div
        data-testid="brick-office-stage"
        className="aspect-[16/9] w-full overflow-hidden rounded-lg border border-brick-wall bg-brick-floor shadow-xl"
      >
        <Stage3D
          snapshot={snapshot}
          lang={lang}
          onAgentClick={handleAgentClick}
          onRoomClick={handleRoomClick}
        />
      </div>

      {/* Connection state pill + last_activity freshness */}
      <ActivityIndicator snapshot={snapshot} connectionState={connectionState} />


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
    <div className="mt-2 flex items-center gap-2 text-[10px] font-mono">
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
