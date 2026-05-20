"use client";
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
      className={`relative rounded-lg border p-3 text-left transition-all cursor-pointer ${roleColor} ${widths[size]} ${active ? "ring-2 ring-cyan-300 border-cyan-300/60" : "hover:border-white/30"}`}
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

function BranchConnector({ count }: { count: number }) {
  const h = 44;
  const stepPct = 100 / count;
  const midY = h * 0.5;
  const centers = Array.from({ length: count }, (_, i) => stepPct * i + stepPct / 2);
  return (
    <svg width="100%" height={h} className="overflow-visible pointer-events-none">
      <line x1="50%" y1="0" x2="50%" y2={midY} stroke="#374151" strokeWidth="1.5" />
      <line
        x1={`${centers[0]}%`}
        y1={midY}
        x2={`${centers[centers.length - 1]}%`}
        y2={midY}
        stroke="#374151"
        strokeWidth="1.5"
      />
      {centers.map((x, i) => (
        <line
          key={i}
          x1={`${x}%`}
          y1={midY}
          x2={`${x}%`}
          y2={h}
          stroke="#374151"
          strokeWidth="1.5"
        />
      ))}
    </svg>
  );
}

export function OrgTree({ snapshot, activeNodeId, onNodeClick }: OrgTreeProps) {
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

  return (
    <div className="w-full px-4 py-6 select-none">
      {/* Mission label */}
      {currentMission && (
        <div className="mb-4 text-center">
          <span className="font-mono text-[10px] uppercase tracking-[0.2em] text-cyan-300/60">
            current mission
          </span>
          <div className="mt-0.5 font-mono text-xs text-gray-400">{currentMission.missionId}</div>
        </div>
      )}

      {/* Row 1: Owner */}
      <div className="flex justify-center">
        <OrgCard
          node={ownerNode}
          size="lg"
          active={activeNodeId === "owner"}
          onClick={onNodeClick}
        />
      </div>

      {/* Connector: Owner → CEO */}
      <div className="flex justify-center">
        <div className="w-px h-6 bg-gray-700" />
      </div>

      {/* Row 2: CEO */}
      <div className="flex justify-center">
        <OrgCard
          node={ceoNode}
          size="lg"
          active={activeNodeId === "ceo"}
          onClick={onNodeClick}
        />
      </div>

      {/* Branch connector: CEO → CXX */}
      <BranchConnector count={cxxNodes.length} />

      {/* Row 3: CXX nodes with workers below */}
      <div className="flex gap-3 justify-center">
        {cxxNodes.map((node) => {
          const nodeWorkers = workers.filter((w) => w.owner === node.role);
          const hasActiveWorker = nodeWorkers.some((w) => w.active);
          const displayNode = hasActiveWorker
            ? { ...node, status: "typing" as const, activity: "Worker active" }
            : node;

          return (
            <div key={node.id} className="flex flex-col items-center gap-2">
              <OrgCard
                node={displayNode}
                size="md"
                active={activeNodeId === node.id}
                onClick={onNodeClick}
              />
              {/* Worker mini-cards under CTO */}
              {nodeWorkers.length > 0 && (
                <>
                  <div className="w-px h-3 bg-gray-700/60" />
                  <div className="flex flex-col gap-1.5 w-full">
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
                        className={`relative rounded border px-2 py-1.5 text-left min-w-[130px] max-w-[160px] transition-all hover:border-white/20 ${
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
                </>
              )}
            </div>
          );
        })}
      </div>
    </div>
  );
}
