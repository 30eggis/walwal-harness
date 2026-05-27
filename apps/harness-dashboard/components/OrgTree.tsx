"use client";
import { useCallback, useMemo, useRef, useState } from "react";
import type { AgentId, HarnessSnapshot, MinifigState, OrgNodeDef } from "@/lib/types";

interface OrgTreeProps {
  snapshot: HarnessSnapshot;
  activeNodeId: string | null;
  onNodeClick: (node: OrgNodeDef) => void;
}

function StatusDot({ status }: { status: MinifigState }) {
  const cls = {
    "red-alert": "bg-rose-500 animate-ping",
    typing: "bg-cyan-400 animate-pulse",
    talking: "bg-emerald-400",
    queued: "bg-amber-400",
    idle: "bg-gray-600",
  }[status] ?? "bg-gray-600";
  return <span className={`absolute top-2 right-2 h-2 w-2 rounded-full ${cls}`} />;
}

function OrgCard({
  node,
  size = "md",
  active,
  onClick,
}: {
  node: OrgNodeDef;
  size?: "lg" | "md" | "sm";
  active: boolean;
  onClick: (n: OrgNodeDef) => void;
}) {
  const roleColor = {
    owner: "border-amber-500/50 bg-amber-500/5",
    ceo: "border-cyan-400/50 bg-cyan-400/5",
    coo: "border-emerald-400/40 bg-emerald-500/5",
    cdo: "border-purple-400/40 bg-purple-500/5",
    cto: "border-blue-400/40 bg-blue-500/5",
    cqo: "border-amber-400/40 bg-amber-500/5",
    ops: "border-rose-400/40 bg-rose-500/5",
  }[node.role] ?? "border-gray-600/40 bg-gray-800/30";

  const widths = {
    lg: "min-w-[220px] max-w-[260px]",
    md: "min-w-[150px] max-w-[190px]",
    sm: "min-w-[130px] max-w-[160px]",
  };

  return (
    <button
      type="button"
      onClick={() => onClick(node)}
      className={`brutal-tile relative rounded-md p-3 text-left transition-all cursor-pointer ${roleColor} ${widths[size]} ${active ? "ring-2 ring-cyan-300 border-cyan-300/80" : "hover:border-white/35"}`}
    >
      <StatusDot status={node.status} />
      <div className="font-mono text-[9px] uppercase tracking-[0.2em] text-gray-500 mb-0.5">{node.role}</div>
      <div className="text-sm font-semibold text-gray-100 leading-tight">{node.label}</div>
      {node.sublabel && (
        <div className="text-[10px] text-gray-500 mt-0.5">{node.sublabel}</div>
      )}
      {node.activity && (
        <div className="mt-2 text-[10px] text-gray-400 line-clamp-2 leading-relaxed">
          {node.activity}
        </div>
      )}
    </button>
  );
}

export function OrgTree({ snapshot, activeNodeId, onNodeClick }: OrgTreeProps) {
  const defaultZoom = 0.74;
  const [zoom, setZoom] = useState(defaultZoom);
  const scrollRef = useRef<HTMLDivElement | null>(null);
  const dragRef = useRef<{ x: number; y: number; left: number; top: number } | null>(null);

  const agentMap = new Map(snapshot.agents.map((a) => [a.id, a]));

  const getStatus = (ids: AgentId[]): MinifigState => {
    const states = ids.map((id) => agentMap.get(id)?.minifigState ?? "idle");
    if (states.includes("red-alert")) return "red-alert";
    if (states.includes("typing")) return "typing";
    if (states.includes("talking")) return "talking";
    if (states.includes("queued")) return "queued";
    return "idle";
  };

  const currentMission = snapshot.missions?.[0] ?? null;

  // Parse CEO activity from mission doc
  const ceoActivity = (() => {
    if (!currentMission?.ceo) return null;
    const match = currentMission.ceo.match(/##\s*Owner 요청 요약\s*\n([\s\S]*?)(?=\n##)/);
    return (
      match?.[1]
        ?.split("\n")
        .find((l) => l.trim().length > 0)
        ?.replace(/^[-*\d.]\s*/, "")
        .trim()
        .slice(0, 100) ?? null
    );
  })();

  const ownerNode: OrgNodeDef = {
    id: "owner",
    role: "owner",
    label: "Owner",
    sublabel: "/goal · /submission · /hot-fix",
    status: "idle",
    activity: snapshot.ownerHistory?.[0]?.content.slice(0, 80) ?? null,
    agentIds: [],
  };

  const ceoNode: OrgNodeDef = {
    id: "ceo",
    role: "ceo",
    label: "harness-ceo",
    sublabel: "Dispatcher · Brainstormer",
    status: getStatus(["dispatcher", "brainstormer"] as AgentId[]),
    activity: ceoActivity,
    agentIds: ["dispatcher", "brainstormer"] as AgentId[],
  };

  const cxxNodes: OrgNodeDef[] = [
    {
      id: "coo",
      role: "coo",
      label: "harness-coo",
      sublabel: "Planner · Research",
      status: getStatus(["planner", "coo-developer", "documentationer"] as AgentId[]),
      activity: null,
      agentIds: ["planner", "coo-developer", "documentationer"] as AgentId[],
    },
    {
      id: "cdo",
      role: "cdo",
      label: "harness-cdo",
      sublabel: "Design · Branding",
      status: "idle",
      activity: null,
      agentIds: [],
    },
    {
      id: "cto",
      role: "cto",
      label: "harness-cto",
      sublabel: "Conductor · Generators",
      status: getStatus([
        "cto",
        "conductor",
        "generator-backend",
        "generator-frontend",
        "generator-designer",
        "generator-devops",
      ] as AgentId[]),
      activity: currentMission?.cto ? "Architecture plan active" : null,
      agentIds: [
        "cto",
        "conductor",
        "generator-backend",
        "generator-frontend",
        "generator-designer",
        "generator-devops",
      ] as AgentId[],
    },
    {
      id: "cqo",
      role: "cqo",
      label: "harness-cqo",
      sublabel: "Evaluators",
      status: getStatus([
        "cqo",
        "evaluator-functional",
        "evaluator-visual",
        "evaluator-code-quality",
        "evaluator-architecture",
        "evaluator-security",
      ] as AgentId[]),
      activity: currentMission?.cqo?.includes("ACCEPTED")
        ? "ACCEPTED"
        : currentMission?.cqo
        ? "Report available"
        : null,
      agentIds: [
        "cqo",
        "evaluator-functional",
        "evaluator-visual",
        "evaluator-code-quality",
        "evaluator-architecture",
        "evaluator-security",
      ] as AgentId[],
    },
    {
      id: "ops",
      role: "ops",
      label: "harness-ops",
      sublabel: "Service Monitor",
      status: getStatus(["service-ops"] as AgentId[]),
      activity: null,
      agentIds: ["service-ops"] as AgentId[],
    },
  ];

  // Only hired HR-Resource workers are positioned in the org chart. Legacy
  // report-only workers remain visible in mission documents, but not as seats.
  const workers = (currentMission?.workers ?? []).filter((w) => w.hired);

  const setBoundedZoom = useCallback((next: number) => {
    setZoom(Math.min(1.35, Math.max(0.62, Number(next.toFixed(2)))));
  }, []);

  const handleWheel = useCallback(
    (event: React.WheelEvent<HTMLDivElement>) => {
      if (!event.ctrlKey && !event.metaKey) return;
      event.preventDefault();
      setBoundedZoom(zoom + (event.deltaY > 0 ? -0.06 : 0.06));
    },
    [setBoundedZoom, zoom],
  );

  const handlePointerDown = useCallback((event: React.PointerEvent<HTMLDivElement>) => {
    if (event.button !== 0 || (event.target as HTMLElement).closest("button")) return;
    const node = scrollRef.current;
    if (!node) return;
    dragRef.current = {
      x: event.clientX,
      y: event.clientY,
      left: node.scrollLeft,
      top: node.scrollTop,
    };
    node.setPointerCapture(event.pointerId);
  }, []);

  const handlePointerMove = useCallback((event: React.PointerEvent<HTMLDivElement>) => {
    const start = dragRef.current;
    const node = scrollRef.current;
    if (!start || !node) return;
    node.scrollLeft = start.left - (event.clientX - start.x);
    node.scrollTop = start.top - (event.clientY - start.y);
  }, []);

  const endDrag = useCallback((event: React.PointerEvent<HTMLDivElement>) => {
    scrollRef.current?.releasePointerCapture(event.pointerId);
    dragRef.current = null;
  }, []);

  const canvas = { width: 1280, height: 500 };
  const ownerPos = { x: 70, y: 196 };
  const ceoPos = { x: 320, y: 196 };
  const cxxX = 610;
  const workerX = 890;

  const layout = useMemo(() => {
    const startY = 50;
    const rowGap = 86;

    return cxxNodes.map((node, index) => {
      const nodeWorkers = workers.filter((w) => w.owner === node.role);
      const y = startY + index * rowGap;
      const workerHeight = Math.max(58, nodeWorkers.length * 54 + Math.max(0, nodeWorkers.length - 1) * 6);
      return { node, x: cxxX, y, workerX, workerY: y - workerHeight / 2 + 30, nodeWorkers };
    });
  }, [cxxNodes, workers]);

  return (
    <div className="select-none">
      <div className="flex items-center justify-between border-b border-white/10 bg-white/5 px-3 py-2 backdrop-blur">
        <div className="min-w-0">
          {currentMission && (
            <div className="truncate font-mono text-[10px] text-cyan-300/70">
              current mission · {currentMission.missionId}
            </div>
          )}
        </div>
        <div className="flex items-center gap-1">
          <button
            type="button"
            onClick={() => setBoundedZoom(zoom - 0.08)}
            className="h-7 w-7 rounded-md border border-white/15 bg-black/35 font-mono text-xs text-gray-200 hover:border-cyan-300/60"
            title="Zoom out"
          >
            -
          </button>
          <button
            type="button"
            onClick={() => setBoundedZoom(defaultZoom)}
            className="h-7 min-w-12 rounded-md border border-white/15 bg-black/35 px-2 font-mono text-[10px] text-gray-300 hover:border-cyan-300/60"
            title="Reset zoom"
          >
            {Math.round(zoom * 100)}%
          </button>
          <button
            type="button"
            onClick={() => setBoundedZoom(zoom + 0.08)}
            className="h-7 w-7 rounded-md border border-white/15 bg-black/35 font-mono text-xs text-gray-200 hover:border-cyan-300/60"
            title="Zoom in"
          >
            +
          </button>
        </div>
      </div>

      <div
        ref={scrollRef}
        onWheel={handleWheel}
        onPointerDown={handlePointerDown}
        onPointerMove={handlePointerMove}
        onPointerUp={endDrag}
        onPointerCancel={endDrag}
        className="scrollbar-hidden isometric-stage h-[390px] cursor-grab overflow-auto active:cursor-grabbing"
      >
        <div
          className="relative"
          style={{
            width: canvas.width * zoom,
            height: canvas.height * zoom,
          }}
        >
          <div
            className="absolute left-0 top-0 origin-top-left"
            style={{
              width: canvas.width,
              height: canvas.height,
              transform: `scale(${zoom})`,
            }}
          >
            <svg className="pointer-events-none absolute inset-0" width={canvas.width} height={canvas.height}>
              <path
                d={`M ${ownerPos.x + 235} ${ownerPos.y + 56} H ${ceoPos.x}`}
                stroke="#374151"
                strokeWidth="1.5"
                fill="none"
              />
              <path
                d={`M ${ceoPos.x + 235} ${ceoPos.y + 56} H ${cxxX - 54}`}
                stroke="#374151"
                strokeWidth="1.5"
                fill="none"
              />
              <path
                d={`M ${cxxX - 54} ${layout[0]?.y ?? 80} V ${layout[layout.length - 1]?.y ?? 420}`}
                stroke="#374151"
                strokeWidth="1.5"
                fill="none"
              />
              {layout.map(({ node, x, y, nodeWorkers }) => (
                <g key={node.id}>
                  <path
                    d={`M ${x - 54} ${y} H ${x - 10}`}
                    stroke="#374151"
                    strokeDasharray="4 5"
                    strokeWidth="1.5"
                    fill="none"
                  />
                  {nodeWorkers.length > 0 && (
                    <path
                      d={`M ${x + 166} ${y} H ${workerX - 16}`}
                      stroke="#374151"
                      strokeWidth="1.5"
                      fill="none"
                    />
                  )}
                </g>
              ))}
            </svg>

            <div className="absolute" style={{ left: ownerPos.x, top: ownerPos.y }}>
              <OrgCard node={ownerNode} size="lg" active={activeNodeId === "owner"} onClick={onNodeClick} />
            </div>

            <div className="absolute" style={{ left: ceoPos.x, top: ceoPos.y }}>
              <OrgCard
                node={ceoNode}
                size="lg"
                active={activeNodeId === "ceo"}
                onClick={onNodeClick}
              />
            </div>

            {layout.map(({ node, x, y, workerX, workerY, nodeWorkers }) => {
              const hasActiveWorker = nodeWorkers.some((w) => w.active);
              const displayNode = hasActiveWorker
                ? { ...node, status: "typing" as const, activity: "Worker active" }
                : node;

              return (
                <div
                  key={node.id}
                  className="absolute"
                  style={{ left: x, top: y - 38 }}
                >
                  <OrgCard
                    node={displayNode}
                    size="md"
                    active={activeNodeId === node.id}
                    onClick={onNodeClick}
                  />
                  {nodeWorkers.length > 0 && (
                  <div
                    className="absolute flex w-[170px] flex-col gap-1.5"
                    style={{ left: workerX - x, top: workerY - y }}
                  >
                    {nodeWorkers.map((w) => {
                      const workerNodeId = `worker-${node.role}-${w.name}`;
                      const workerActive = activeNodeId === workerNodeId || w.active;
                      return (
                      <button
                        key={`${node.role}-${w.name}`}
                        type="button"
                        onClick={() =>
                          onNodeClick({
                            id: workerNodeId,
                            role: node.role,
                            label: w.displayName,
                            sublabel: w.active ? `running · ${w.name}` : `${w.status} · ${w.name}`,
                            status: w.active ? "typing" : w.status === "COMPLETE" ? "idle" : "queued",
                            activity: w.sourcePath ?? null,
                            agentIds: [],
                          })
                        }
                        className={`brutal-tile relative rounded-md px-2 py-1.5 text-left min-w-[130px] max-w-[160px] transition-all hover:border-white/25 ${
                          workerActive
                            ? "border-cyan-300/70 bg-cyan-400/10 shadow-[0_0_18px_rgba(34,211,238,0.18)]"
                            : "border-gray-700/40 bg-gray-800/30"
                        } ${activeNodeId === workerNodeId ? "ring-1 ring-cyan-300" : ""}`}
                      >
                        {w.active && (
                          <span className="absolute right-2 top-2 h-1.5 w-1.5 rounded-full bg-cyan-300 animate-pulse" />
                        )}
                        <div className={`font-mono text-[9px] ${w.active ? "text-cyan-300/80" : "text-gray-500"}`}>
                          hired worker
                        </div>
                        <div className="text-[11px] font-medium text-gray-200 truncate pr-3">
                          {w.displayName}
                        </div>
                        <div
                          className={`text-[9px] font-mono mt-0.5 ${
                            w.active
                              ? "text-cyan-300"
                              : w.status === "COMPLETE"
                              ? "text-emerald-400"
                              : "text-amber-400"
                        }`}
                        >
                          {w.active ? "RUNNING" : w.status}
                        </div>
                      </button>
                      );
                    })}
                  </div>
                  )}
                </div>
              );
            })}
          </div>
        </div>
      </div>
    </div>
  );
}
