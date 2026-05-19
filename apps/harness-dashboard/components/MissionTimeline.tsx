"use client";
import type { MissionDoc } from "@/lib/types";

interface Props {
  missions: MissionDoc[];
  activeMissionId: string | null;
  onMissionClick: (mission: MissionDoc) => void;
}

type ChipRole =
  | "owner"
  | "ceo"
  | "coo"
  | "cdo"
  | "cto"
  | "cqo"
  | "ops"
  | "worker";

function chipColor(role: ChipRole): string {
  switch (role) {
    case "owner":
      return "bg-amber-500/15 text-amber-300 border-amber-500/30";
    case "ceo":
      return "bg-cyan-400/15 text-cyan-300 border-cyan-400/30";
    case "coo":
      return "bg-emerald-500/15 text-emerald-300 border-emerald-500/30";
    case "cdo":
      return "bg-purple-500/15 text-purple-300 border-purple-500/30";
    case "cto":
      return "bg-blue-400/15 text-blue-300 border-blue-400/30";
    case "cqo":
      return "bg-amber-400/15 text-amber-300 border-amber-400/30";
    case "ops":
      return "bg-rose-400/15 text-rose-300 border-rose-400/30";
    case "worker":
      return "bg-gray-500/15 text-gray-300 border-gray-500/30";
    default:
      return "bg-gray-500/15 text-gray-400 border-gray-600/30";
  }
}

function Chip({
  role,
  label,
  badge,
}: {
  role: ChipRole;
  label: string;
  badge?: string;
}) {
  return (
    <span
      className={`inline-flex items-center gap-1 rounded border px-1.5 py-0.5 font-mono text-[9px] ${chipColor(role)}`}
    >
      {label}
      {badge && <span className="opacity-80">{badge}</span>}
    </span>
  );
}

function Arrow() {
  return <span className="text-[10px] text-gray-600 shrink-0">→</span>;
}

function buildFlowChain(mission: MissionDoc): React.ReactNode {
  // Pre-worker CXX: planning phase (before implementation)
  const preWorker: Array<{ key: "coo" | "cdo" | "cto"; role: ChipRole }> = [
    { key: "coo", role: "coo" },
    { key: "cdo", role: "cdo" },
    { key: "cto", role: "cto" },
  ];
  // Post-worker CXX: verification phase (after implementation)
  const postWorker: Array<{ key: "cqo" | "ops"; role: ChipRole }> = [
    { key: "cqo", role: "cqo" },
    { key: "ops", role: "ops" },
  ];

  const isCqoAccepted =
    typeof mission.cqo === "string" && mission.cqo.includes("ACCEPTED");

  const chips: React.ReactNode[] = [];
  let key = 0;

  chips.push(<Chip key={key++} role="owner" label="Owner" />);
  chips.push(<Arrow key={key++} />);
  chips.push(<Chip key={key++} role="ceo" label="CEO" />);

  // Planning phase: COO, CDO, CTO
  for (const { key: roleKey, role } of preWorker) {
    if (mission.cxxPresent.includes(roleKey)) {
      chips.push(<Arrow key={key++} />);
      chips.push(<Chip key={key++} role={role} label={roleKey.toUpperCase()} />);
    }
  }

  // CTO-owned implementation workers. Legacy flat workers remain visible here
  // with owner=unknown so protocol bypasses are not hidden.
  for (const worker of mission.workers.filter((w) => w.owner === "cto" || w.owner === "unknown")) {
    chips.push(<Arrow key={key++} />);
    const badge = worker.status === "COMPLETE" ? "✅" : "⏳";
    const shortName =
      worker.name.length > 12 ? worker.name.slice(0, 12) + "…" : worker.name;
    chips.push(
      <Chip key={key++} role="worker" label={shortName} badge={badge} />
    );
  }

  // Verification phase: CQO, OPS
  for (const { key: roleKey, role } of postWorker) {
    if (mission.cxxPresent.includes(roleKey)) {
      chips.push(<Arrow key={key++} />);
      const badge = roleKey === "cqo" && isCqoAccepted ? "✅" : undefined;
      chips.push(
        <Chip key={key++} role={role} label={roleKey.toUpperCase()} badge={badge} />
      );
      if (roleKey === "cqo") {
        for (const worker of mission.workers.filter((w) => w.owner === "cqo")) {
          chips.push(<Arrow key={key++} />);
          const workerBadge = worker.status === "COMPLETE" ? "✅" : "⏳";
          const shortName =
            worker.name.length > 12 ? worker.name.slice(0, 12) + "…" : worker.name;
          chips.push(
            <Chip key={key++} role="worker" label={shortName} badge={workerBadge} />
          );
        }
      }
    }
  }

  return (
    <div className="flex flex-wrap items-center gap-1 min-w-0">{chips}</div>
  );
}

export function MissionTimeline({
  missions,
  activeMissionId,
  onMissionClick,
}: Props) {
  if (!missions.length) {
    return (
      <div className="rounded border border-dashed border-gray-700 px-3 py-4 text-center text-[11px] text-gray-500">
        No missions found in .harness/documents/
      </div>
    );
  }

  return (
    <div className="space-y-1.5">
      {missions.map((mission) => {
        const isActive = mission.missionId === activeMissionId;
        const typeBadge =
          mission.type === "hotfix"
            ? "[🔥 hot-fix]"
            : mission.type === "submission"
            ? "[+ submission]"
            : mission.type === "goal" || mission.type === "feature"
            ? "[✦ goal]"
            : "[— unknown]";
        const shortId =
          mission.missionId.length > 28
            ? mission.missionId.slice(0, 28) + "…"
            : mission.missionId;

        let dateStr = "—";
        try {
          dateStr = new Date(mission.ts).toLocaleDateString(undefined, {
            month: "short",
            day: "numeric",
          });
        } catch {
          // ignore invalid date
        }

        return (
          <button
            key={mission.missionId}
            type="button"
            onClick={() => onMissionClick(mission)}
            className={`w-full rounded border px-3 py-2.5 text-left transition-colors ${
              isActive
                ? "border-cyan-400/40 bg-cyan-400/5"
                : "border-gray-700/40 bg-black/10 hover:border-gray-600/50"
            }`}
          >
            <div className="flex items-start justify-between gap-2 mb-1.5">
              <div className="flex items-center gap-2 min-w-0">
                <span
                  className={`shrink-0 font-mono text-[9px] rounded px-1.5 py-0.5 border ${
                    mission.type === "hotfix"
                      ? "bg-rose-500/15 text-rose-300 border-rose-500/30"
                      : mission.type === "submission"
                      ? "bg-sky-500/15 text-sky-300 border-sky-500/30"
                      : "bg-emerald-500/15 text-emerald-300 border-emerald-500/30"
                  }`}
                >
                  {typeBadge}
                </span>
                <span className="font-mono text-[10px] text-gray-200 truncate">
                  {shortId}
                </span>
              </div>
              <span className="shrink-0 font-mono text-[9px] text-gray-500">
                {dateStr}
              </span>
            </div>
            {buildFlowChain(mission)}
          </button>
        );
      })}
    </div>
  );
}
