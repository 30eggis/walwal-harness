"use client";

import { useEffect, useLayoutEffect, useMemo, useRef, useState } from "react";
import ReactMarkdown, { type Components } from "react-markdown";
import remarkGfm from "remark-gfm";
import type {
  ConventionEntry,
  CxxTodo,
  GotchaEntry,
  HarnessSnapshot,
  MissionDoc,
  OwnerPromptEntry,
  WorkerDocEntry,
} from "@/lib/types";
import { useHarnessStream } from "@/hooks/useHarnessStream";
import { Wordmark } from "./Wordmark";

interface SceneProps {
  snapshot: HarnessSnapshot;
  lang?: "ko" | "en";
}

type AgentLane = {
  id: string;
  label: string;
  role: string;
  group: string;
  kind: "cxx" | "worker";
  status: "normal" | "waiting" | "error";
  todos: number;
  workers: WorkerDocEntry[];
  worker?: WorkerDocEntry;
  mission: MissionDoc | null;
};

type HeatCell = {
  x: number;
  y: number;
  laneId: string;
  laneLabel: string;
  bucketLabel: string;
  count: number;
  hotfix: boolean;
  mission: MissionDoc | null;
};

type HeatSample = {
  ts: number;
  laneId: string;
  count: number;
  hotfix: boolean;
  missionId: string | null;
};

type GoalGroup = { goal: MissionDoc; children: MissionDoc[] };

const CXX_ROLES = ["ceo", "coo", "cdo", "cto", "cqo", "ops"] as const;
type CxxRole = typeof CXX_ROLES[number];
// Workers always sit under a non-CEO CXX (CEO delegates, never owns workers).
const WORKER_OWNERS = ["coo", "cdo", "cto", "cqo", "ops"] as const;
type WorkerOwnerRole = typeof WORKER_OWNERS[number];
const BUCKET_MS = 10 * 60_000;
const VISIBLE_BUCKETS = 24 * 6;
const LANE_LABEL_WIDTH = 110;
const TIME_LABEL_HEIGHT = 18;
const LANE_ROW_HEIGHT = 18;
const MIN_BUCKET_PX = 8;

const CXX_COLOR: Record<CxxRole, string> = {
  ceo: "bg-cyan-500",
  coo: "bg-emerald-500",
  cdo: "bg-violet-500",
  cto: "bg-orange-500",
  cqo: "bg-fuchsia-500",
  ops: "bg-amber-500",
};

const CXX_TEXT: Record<CxxRole, string> = {
  ceo: "text-cyan-200",
  coo: "text-emerald-300",
  cdo: "text-violet-300",
  cto: "text-orange-300",
  cqo: "text-fuchsia-300",
  ops: "text-amber-300",
};

export function Scene({ snapshot: initial, lang = "ko" }: SceneProps) {
  const { snapshot, connectionState } = useHarnessStream(initial);
  const initialActiveMission = snapshot.missions.find((mission) => mission.active) ?? snapshot.missions[0] ?? null;
  const [selectedMissionId, setSelectedMissionId] = useState(initialActiveMission?.missionId ?? null);
  const selectedMission =
    snapshot.missions.find((mission) => mission.missionId === selectedMissionId) ??
    snapshot.missions.find((mission) => mission.active) ??
    snapshot.missions[0] ??
    null;
  // Owner-direct prompts only — strip auto-generated <task-notification> pings
  // (used by the autonomous wake-up loop, not by the owner).
  const ownerPrompts = useMemo(
    () =>
      snapshot.ownerHistory.filter(
        (entry) => !(entry.content ?? "").trimStart().startsWith("<task-notification")
      ),
    [snapshot.ownerHistory]
  );
  const goalGroups = useMemo(() => groupMissions(snapshot.missions), [snapshot.missions]);
  const selectedGoal = useMemo(() => {
    if (!selectedMission) return goalGroups[0]?.goal ?? null;
    const parentId = selectedMission.missionId.split("/")[0];
    return goalGroups.find((g) => g.goal.missionId === parentId)?.goal ?? selectedMission;
  }, [goalGroups, selectedMission]);
  const goalScopeMissions = useMemo(() => {
    if (!selectedGoal) return snapshot.missions;
    const parentId = selectedGoal.missionId.split("/")[0];
    return snapshot.missions.filter(
      (m) => m.missionId === parentId || m.missionId.startsWith(`${parentId}/`)
    );
  }, [snapshot.missions, selectedGoal]);

  const lanes = useMemo(() => buildLanes(snapshot), [snapshot]);
  const heatmapStartedAt = useMemo(() => Date.now() - VISIBLE_BUCKETS * BUCKET_MS, [snapshot.ts]);
  const persistedHeatSamples = useMemo<HeatSample[]>(
    () =>
      snapshot.activitySamples.map((sample) => ({
        ts: Date.parse(sample.ts),
        laneId: sample.laneId,
        count: sample.count,
        hotfix: sample.hotfix,
        missionId: sample.missionId,
      })).filter((sample) => Number.isFinite(sample.ts)),
    [snapshot.activitySamples]
  );
  const [heatSamples, setHeatSamples] = useState<HeatSample[]>([]);
  const sampleSourceRef = useRef({ lanes, snapshot });
  useEffect(() => {
    sampleSourceRef.current = { lanes, snapshot };
  }, [lanes, snapshot]);
  useEffect(() => {
    const tick = () => {
      const { lanes, snapshot } = sampleSourceRef.current;
      // Gate live samples on the harness runtime — once the session reports
      // completion (or there's no current/next agent), every "active" signal
      // is stale (todos stay status="active", worker mtimes stay recent), so
      // we stop emitting in-progress samples until something resumes.
      const rt = snapshot.runtime;
      const harnessIdle =
        rt?.agentStatus === "completed" ||
        rt?.agentStatus === "complete" ||
        ((rt?.currentAgent ?? null) === null &&
          (rt?.nextAgent === null || rt?.nextAgent === "none"));
      if (harnessIdle) {
        const nowMinute = Math.floor(Date.now() / BUCKET_MS);
        setHeatSamples((prev) =>
          prev.filter((sample) => Math.floor(sample.ts / BUCKET_MS) < nowMinute)
        );
        return;
      }
      setHeatSamples((prev) => {
        const now = Date.now();
        const activeMission = snapshot.missions.find((mission) => mission.active) ?? snapshot.missions[0] ?? null;
        const next: HeatSample[] = [];
        for (const lane of lanes) {
          // Live overlay records active work only. Historical participation is
          // backfilled from persisted activity logs; completed reports must not
          // keep repainting the current minute forever.
          let activity = 0;
          if (lane.kind === "worker") {
            const w = lane.worker;
            if (w) {
              if (w.active || w.status === "IN_PROGRESS") activity = 2;
            }
          } else {
            const liveTodos = snapshot.todos.filter(
              (t) =>
                t.owner === lane.role &&
                t.status !== "done" &&
                t.status !== "completed"
            ).length;
            const runningWorkers = lane.workers.filter(
              (w) => w.active || w.status === "IN_PROGRESS"
            ).length;
            if (liveTodos > 0 && runningWorkers === 0) activity = 2;
            else if (runningWorkers > 0) activity = 2;
          }
          if (activity <= 0) continue;
          next.push({
            ts: now,
            laneId: lane.id,
            count: activity,
            hotfix: activeMission?.type === "hotfix" || lane.status === "error",
            missionId: activeMission?.missionId ?? null,
          });
        }
        if (next.length === 0) return prev;
        return [...prev, ...next]
          .filter((sample) => now - sample.ts < 30 * 60 * 1000)
          .slice(-1500);
      });
    };
    tick();
    const id = setInterval(tick, 1000);
    return () => clearInterval(id);
  }, []);
  const { cells: heatmap, totalBuckets } = useMemo(
    () => buildHeatmap(
      snapshot,
      lanes,
      [...persistedHeatSamples, ...heatSamples],
      heatmapStartedAt
    ),
    [heatSamples, heatmapStartedAt, lanes, persistedHeatSamples, snapshot]
  );
  const [selectedLaneId, setSelectedLaneId] = useState(lanes[0]?.id ?? "ceo");
  const [dragStart, setDragStart] = useState<{ x: number; y: number } | null>(null);
  const [dragEnd, setDragEnd] = useState<{ x: number; y: number } | null>(null);
  const [tooltip, setTooltip] = useState<{ mission: MissionDoc; x: number; y: number } | null>(null);
  const [commandLogOpen, setCommandLogOpen] = useState(false);
  const [docExpanded, setDocExpanded] = useState(false);
  const [customDoc, setCustomDoc] = useState<{
    source: string;
    title: string;
    content: string;
  } | null>(null);

  // Selecting a mission or lane returns the viewer to mission-context mode.
  useEffect(() => {
    setCustomDoc(null);
  }, [selectedMissionId, selectedLaneId]);

  void lang;

  const selectedLane = lanes.find((lane) => lane.id === selectedLaneId) ?? lanes[0] ?? null;
  const selectedCells = getSelectedCells(heatmap, dragStart, dragEnd);
  const activeWorkers =
    (snapshot.missions.find((mission) => mission.active) ?? snapshot.missions[0])?.workers.filter((w) => w.active).length ?? 0;
  const hotfixCount = snapshot.missions.filter((m) => m.type === "hotfix").length;

  const handleSelectWorker = (mission: MissionDoc, worker: WorkerDocEntry) => {
    setSelectedMissionId(mission.missionId);
    setSelectedLaneId(`${worker.owner}:${worker.name}`);
  };

  return (
    <div className="flex h-[100dvh] flex-col overflow-hidden bg-[#070d1d] text-slate-200">
      <TopHeader
        projectName={snapshot.projectName}
        missionId={selectedMission?.missionId ?? null}
        connectionState={connectionState}
        activeWorkers={activeWorkers}
        hotfixCount={hotfixCount}
      />

      <div className="flex min-h-0 flex-1">
        <HistoryNavigator
          missions={snapshot.missions}
          ownerHistory={ownerPrompts}
          activeMissionId={selectedMission?.missionId ?? null}
          onSelect={setSelectedMissionId}
          commandLogOpen={commandLogOpen}
          onToggleCommandLog={() => setCommandLogOpen((v) => !v)}
          onCloseCommandLog={() => setCommandLogOpen(false)}
        />

        <main className="flex min-w-0 flex-1 flex-col gap-2 p-2">
          {/* Top row: Knowledge | Layer Activity | Recent Report */}
          <section className="grid shrink-0 grid-cols-3 gap-2" style={{ height: 280 }}>
            <KnowledgeBasePanel
              gotchas={snapshot.gotchas}
              conventions={snapshot.conventions}
              baselineTs={selectedGoal?.ts ?? null}
              onSelect={(entry, kind) =>
                setCustomDoc({
                  source: kind,
                  title: `${entry.id}.md`,
                  content: entry.content,
                })
              }
            />
            <LayerActivityPanel
              goalScope={goalScopeMissions}
              todos={snapshot.todos}
              label={selectedGoal?.missionId ?? "no goal"}
            />
            <RecentReportPanel
              missions={snapshot.missions}
              onSelectWorker={handleSelectWorker}
            />
          </section>

          {/* Heatmap section with cadence strip + main grid + click tooltip */}
          <section className="panel-shell relative flex min-h-0 flex-1 flex-col gap-2 p-2">
            <CadenceStrip ownerHistory={ownerPrompts} />
            <WorkflowHeatmap
              lanes={lanes}
              cells={heatmap}
              totalBuckets={totalBuckets}
              selectedCells={selectedCells}
              dragStart={dragStart}
              dragEnd={dragEnd}
              onDragStart={setDragStart}
              onDragMove={setDragEnd}
              onDragEnd={(missionId) => {
                if (missionId) setSelectedMissionId(missionId);
              }}
              onSelectLane={setSelectedLaneId}
              onCellClick={(cell, event) => {
                if (!cell.mission) {
                  setTooltip(null);
                  return;
                }
                const rect = (event.currentTarget as HTMLElement).getBoundingClientRect();
                setTooltip({
                  mission: cell.mission,
                  x: rect.left + rect.width / 2,
                  y: rect.top,
                });
                setSelectedMissionId(cell.mission.missionId);
              }}
            />
            {tooltip && (
              <ApprovalTooltip
                mission={tooltip.mission}
                x={tooltip.x}
                y={tooltip.y}
                onClose={() => setTooltip(null)}
              />
            )}
          </section>
        </main>

        <aside
          id="doc-aside"
          className={`doc-aside flex shrink-0 flex-col gap-2 overflow-hidden border-l border-slate-800 bg-[#081124] p-2 ${
            docExpanded ? "expanded" : ""
          }`}
        >
          <DocumentViewer
            mission={selectedMission}
            lane={selectedLane}
            customDoc={customDoc}
            expanded={docExpanded}
            onToggle={() => setDocExpanded((v) => !v)}
          />
        </aside>
      </div>
    </div>
  );
}

// ===== Top header =====

function TopHeader({
  projectName,
  missionId,
  connectionState,
  activeWorkers,
  hotfixCount,
}: {
  projectName: string;
  missionId: string | null;
  connectionState: string;
  activeWorkers: number;
  hotfixCount: number;
}) {
  return (
    <header className="flex shrink-0 items-center gap-4 border-b border-slate-700/60 bg-[#0b1328]/90 px-4 py-2 backdrop-blur">
      <Wordmark className="text-base" />
      <span
        className="rounded bg-slate-800/60 px-2 py-0.5 font-mono text-[10px] font-semibold text-amber-300"
        title={projectName}
      >
        {projectName}
      </span>
      <span className="hidden text-[11px] text-slate-400 sm:inline">
        walwal-harness 라이브 운영 대시보드
      </span>
      <span className="min-w-0 flex-1 truncate font-mono text-[11px] text-cyan-200/80">
        {missionId ?? "no active transaction"}
      </span>
      <div className="flex shrink-0 items-center gap-2">
        <HeaderBadge
          label="SSE"
          value={connectionState}
          tone={connectionState === "open" ? "green" : "orange"}
        />
        <HeaderBadge label="Workers" value={String(activeWorkers)} tone="cyan" />
        <HeaderBadge label="Hot-fix" value={String(hotfixCount)} tone="red" />
        <PresenceLegend />
      </div>
    </header>
  );
}

function HeaderBadge({
  label,
  value,
  tone,
}: {
  label: string;
  value: string;
  tone: "green" | "orange" | "red" | "cyan";
}) {
  const color = {
    green: "border-emerald-400/30 bg-emerald-400/10 text-emerald-200",
    orange: "border-orange-400/30 bg-orange-400/10 text-orange-200",
    red: "border-rose-400/30 bg-rose-400/10 text-rose-200",
    cyan: "border-cyan-400/30 bg-cyan-400/10 text-cyan-200",
  }[tone];
  return (
    <div className={`rounded-full border px-2.5 py-1 font-mono text-[10px] ${color}`}>
      <span className="text-slate-500">{label}</span>
      <span className="ml-1.5">{value}</span>
    </div>
  );
}

function PresenceLegend() {
  return (
    <div className="ml-2 hidden items-center gap-2 border-l border-slate-700/50 pl-3 font-mono text-[10px] text-gray-400 lg:flex">
      <span className="inline-flex items-center gap-1">
        <span className="size-1.5 rounded-full bg-aura-idle" /> idle
      </span>
      <span className="inline-flex items-center gap-1">
        <span className="size-1.5 rounded-full bg-aura-typing" /> typing
      </span>
      <span className="inline-flex items-center gap-1">
        <span className="size-1.5 rounded-full bg-aura-talking" /> talking
      </span>
      <span className="inline-flex items-center gap-1">
        <span className="size-1.5 rounded-full bg-aura-alert" /> alert
      </span>
    </div>
  );
}

// ===== History Navigator =====

function groupMissions(missions: MissionDoc[]): GoalGroup[] {
  const parentSegment = (id: string) => id.split("/")[0] ?? id;
  const groups: GoalGroup[] = [];
  const groupById = new Map<string, GoalGroup>();

  const ensureGroupFor = (mission: MissionDoc): GoalGroup => {
    const key = parentSegment(mission.missionId);
    const existing = groupById.get(key);
    if (existing) return existing;
    const group: GoalGroup = { goal: mission, children: [] };
    groups.push(group);
    groupById.set(key, group);
    return group;
  };

  for (const mission of missions) {
    if (mission.missionId.includes("/")) continue;
    if (mission.type === "goal" || mission.type === "feature") ensureGroupFor(mission);
  }
  for (const mission of missions) {
    if (mission.missionId.includes("/")) continue;
    if (mission.type === "goal" || mission.type === "feature") continue;
    ensureGroupFor(mission);
  }
  for (const mission of missions) {
    if (!mission.missionId.includes("/")) continue;
    const key = parentSegment(mission.missionId);
    const group = groupById.get(key);
    if (group) group.children.push(mission);
    else ensureGroupFor(mission);
  }

  for (const g of groups) {
    g.children.sort((a, b) => (a.ts ?? "").localeCompare(b.ts ?? ""));
  }
  groups.sort((a, b) => (b.goal.ts ?? "").localeCompare(a.goal.ts ?? ""));
  return groups;
}

function HistoryNavigator({
  missions,
  ownerHistory,
  activeMissionId,
  onSelect,
  commandLogOpen,
  onToggleCommandLog,
  onCloseCommandLog,
}: {
  missions: MissionDoc[];
  ownerHistory: OwnerPromptEntry[];
  activeMissionId: string | null;
  onSelect: (missionId: string) => void;
  commandLogOpen: boolean;
  onToggleCommandLog: () => void;
  onCloseCommandLog: () => void;
}) {
  const groups = useMemo(() => groupMissions(missions), [missions]);
  const popoverRef = useRef<HTMLDivElement>(null);
  const buttonRef = useRef<HTMLButtonElement>(null);

  useEffect(() => {
    if (!commandLogOpen) return;
    const onDocClick = (event: MouseEvent) => {
      const target = event.target as Node;
      if (popoverRef.current?.contains(target) || buttonRef.current?.contains(target)) return;
      onCloseCommandLog();
    };
    document.addEventListener("mousedown", onDocClick);
    return () => document.removeEventListener("mousedown", onDocClick);
  }, [commandLogOpen, onCloseCommandLog]);

  return (
    <aside className="flex w-[230px] shrink-0 flex-col border-r border-slate-800 bg-[#081124] px-3 py-3">
      <div className="relative mb-3 flex items-center justify-between gap-2">
        <div className="flex min-w-0 items-center gap-2">
          <div className="grid h-7 w-7 shrink-0 place-items-center rounded bg-slate-700/70 text-xs">
            AI
          </div>
          <div className="min-w-0">
            <div className="text-xs font-semibold text-slate-100">Administrator</div>
            <div className="font-mono text-[9px] text-slate-500">workflow history</div>
          </div>
        </div>
        <button
          ref={buttonRef}
          type="button"
          onClick={onToggleCommandLog}
          className="relative grid h-7 w-7 shrink-0 place-items-center rounded text-slate-400 hover:bg-white/10 hover:text-cyan-200"
          title={`Command Log (${ownerHistory.length})`}
          aria-label="Open command log"
        >
          <svg
            width="14"
            height="14"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth="2"
            strokeLinejoin="round"
          >
            <path d="M21 11.5a8.38 8.38 0 0 1-.9 3.8 8.5 8.5 0 0 1-7.6 4.7 8.38 8.38 0 0 1-3.8-.9L3 21l1.9-5.7a8.38 8.38 0 0 1-.9-3.8 8.5 8.5 0 0 1 4.7-7.6 8.38 8.38 0 0 1 3.8-.9h.5a8.48 8.48 0 0 1 8 8v.5z" />
          </svg>
          {ownerHistory.length > 0 && (
            <span className="absolute -right-0.5 -top-0.5 grid h-3.5 min-w-[14px] place-items-center rounded-full bg-cyan-500 px-1 font-mono text-[8px] font-bold text-slate-900 animate-pulse">
              {ownerHistory.length}
            </span>
          )}
        </button>

        {commandLogOpen && (
          <CommandLogPopover
            ref={popoverRef}
            entries={ownerHistory}
            onClose={onCloseCommandLog}
          />
        )}
      </div>

      <nav className="min-h-0 flex-1 space-y-2 overflow-auto pr-1 text-xs">
        <div className="font-mono text-[10px] uppercase tracking-[0.18em] text-slate-500">
          /goal
        </div>
        {groups.length ? (
          groups.map(({ goal, children }) => (
            <div
              key={goal.missionId}
              className="rounded border border-slate-800/80 bg-slate-950/35"
            >
              <button
                type="button"
                onClick={() => onSelect(goal.missionId)}
                className={`w-full truncate px-2 py-2 text-left ${
                  activeMissionId === goal.missionId
                    ? "bg-cyan-400/[0.12] text-cyan-100"
                    : "text-slate-300 hover:bg-white/[0.04]"
                }`}
                title={goal.label || goal.missionId}
              >
                {goal.label || goal.missionId}
              </button>
              {children.length > 0 && (
                <div className="border-t border-slate-800/70 py-1 pl-3">
                  {children.map((child) => (
                    <button
                      key={child.missionId}
                      type="button"
                      onClick={() => onSelect(child.missionId)}
                      className={`block w-full truncate rounded px-2 py-1.5 text-left ${
                        activeMissionId === child.missionId
                          ? "bg-cyan-400/[0.12] text-cyan-100"
                          : child.type === "hotfix"
                          ? "text-rose-300 hover:bg-rose-400/10"
                          : "text-slate-400 hover:bg-white/[0.04]"
                      }`}
                      title={child.label || child.missionId}
                    >
                      <span className="font-mono text-[9px] text-slate-500">
                        {child.type === "hotfix" ? "/hot-fix" : "/submission"}
                      </span>{" "}
                      {child.label || child.missionId}
                    </button>
                  ))}
                </div>
              )}
            </div>
          ))
        ) : (
          <div className="rounded border border-slate-800 px-2 py-2 text-slate-500">
            No goal history
          </div>
        )}
      </nav>
    </aside>
  );
}

const CommandLogPopover = (() => {
  const Inner = (
    {
      entries,
      onClose,
    }: { entries: OwnerPromptEntry[]; onClose: () => void },
    ref: React.Ref<HTMLDivElement>
  ) => {
    const colorFor = (type: string) =>
      type === "hot-fix"
        ? "border-rose-500/40 bg-rose-950/30"
        : type === "submission"
        ? "border-emerald-500/30 bg-emerald-950/30"
        : "bg-slate-950/60";
    const labelFor = (type: string) =>
      type === "hot-fix"
        ? "text-rose-300"
        : type === "submission"
        ? "text-emerald-300"
        : "text-cyan-300";
    return (
      <div
        ref={ref}
        className="pop-in absolute left-full top-0 z-40 ml-3 rounded border border-cyan-400/60 bg-[#0b1328] px-3 py-2 shadow-[0_10px_30px_rgba(0,0,0,0.6)]"
        style={{ width: 340 }}
      >
        <div className="flex items-center justify-between">
          <div className="font-mono text-[9px] uppercase tracking-[0.2em] text-slate-500">
            Command Log
          </div>
          <button
            type="button"
            onClick={onClose}
            className="text-sm leading-none text-slate-400 hover:text-slate-100"
            aria-label="Close"
          >
            ×
          </button>
        </div>
        <div className="mt-1.5 max-h-[320px] space-y-1 overflow-auto pr-1">
          {entries.length === 0 ? (
            <div className="rounded bg-slate-950/50 px-2 py-2 text-[10px] text-slate-500">
              No owner prompts yet.
            </div>
          ) : (
            entries.map((entry, idx) => (
              <div
                key={`${entry.ts}-${idx}`}
                className={`rounded border border-transparent px-2 py-1.5 ${colorFor(entry.type)}`}
              >
                <div className="flex items-center justify-between text-[9px]">
                  <span className={`font-mono ${labelFor(entry.type)}`}>/{entry.type}</span>
                  <span className="text-slate-500">{formatTime(entry.ts)}</span>
                </div>
                <div className="mt-0.5 line-clamp-2 text-[10px] text-slate-300">
                  {entry.content}
                </div>
              </div>
            ))
          )}
        </div>
        <div className="absolute -left-[6px] top-3 size-3 rotate-45 border-b border-l border-cyan-400/60 bg-[#0b1328]" />
      </div>
    );
  };
  return Object.assign(
    // eslint-disable-next-line react/display-name
    (
      props: { entries: OwnerPromptEntry[]; onClose: () => void } & {
        ref?: React.Ref<HTMLDivElement>;
      }
    ) => Inner(props, props.ref ?? null),
    {}
  );
})() as React.ForwardRefExoticComponent<
  { entries: OwnerPromptEntry[]; onClose: () => void } & React.RefAttributes<HTMLDivElement>
>;

function formatTime(iso: string | null | undefined) {
  if (!iso) return "";
  try {
    const d = new Date(iso);
    if (isNaN(d.getTime())) return "";
    // Always render in the browser's local timezone — never UTC.
    const pad = (n: number) => String(n).padStart(2, "0");
    return `${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
  } catch {
    return "";
  }
}

// ===== Knowledge base panel =====

type KnowledgeKind = "Gotcha" | "Convention";

function KnowledgeBasePanel({
  gotchas,
  conventions,
  baselineTs,
  onSelect,
}: {
  gotchas: GotchaEntry[];
  conventions: ConventionEntry[];
  baselineTs: string | null;
  onSelect: (entry: GotchaEntry | ConventionEntry, kind: KnowledgeKind) => void;
}) {
  const baseline = baselineTs ? new Date(baselineTs).getTime() : 0;
  const isNew = (updatedAt?: string | null) => {
    if (!updatedAt || !baseline) return false;
    const t = new Date(updatedAt).getTime();
    return Number.isFinite(t) && t >= baseline;
  };
  const newGotchas = gotchas.filter((g) => isNew(g.updatedAt)).length;
  const newConventions = conventions.filter((c) => isNew(c.updatedAt)).length;

  return (
    <div className="panel-shell fade-in flex min-h-0 flex-col p-2">
      <SectionLabel>Info · Knowledge Base</SectionLabel>
      <div className="mt-2 grid min-h-0 flex-1 grid-cols-2 gap-2">
        <KnowledgeList
          title="Gotchas"
          kind="Gotcha"
          total={gotchas.length}
          added={newGotchas}
          entries={gotchas}
          isNew={isNew}
          dirRel=".harness/gotchas"
          onSelect={onSelect}
        />
        <KnowledgeList
          title="Conventions"
          kind="Convention"
          total={conventions.length}
          added={newConventions}
          entries={conventions}
          isNew={isNew}
          dirRel=".harness/conventions"
          onSelect={onSelect}
        />
      </div>
    </div>
  );
}

function KnowledgeList({
  title,
  kind,
  total,
  added,
  entries,
  isNew,
  dirRel,
  onSelect,
}: {
  title: string;
  kind: KnowledgeKind;
  total: number;
  added: number;
  entries: Array<GotchaEntry | ConventionEntry>;
  isNew: (ts?: string | null) => boolean;
  dirRel: string;
  onSelect: (entry: GotchaEntry | ConventionEntry, kind: KnowledgeKind) => void;
}) {
  return (
    <div className="inset-shell flex min-h-0 flex-col p-2">
      <div className="flex items-center justify-between">
        <span className="text-[11px] text-cyan-200">{title}</span>
        <span className="text-[10px] text-slate-400">
          {total}
          {added > 0 && (
            <>
              {" "}
              <span className="font-semibold text-emerald-300">+{added}</span>
            </>
          )}
        </span>
      </div>
      <div className="mt-1.5 min-h-0 flex-1 space-y-0.5 overflow-auto pr-1 text-[10px]">
        {entries.length === 0 ? (
          <div className="text-slate-500">(empty)</div>
        ) : (
          entries.map((entry) => (
            <button
              key={entry.id}
              type="button"
              onClick={() => onSelect(entry, kind)}
              className="block w-full cursor-pointer truncate rounded px-1 py-0.5 text-left text-slate-300 transition-colors hover:bg-cyan-400/5 hover:text-cyan-200"
              title={`${dirRel}/${entry.id}.md`}
            >
              → {entry.id}.md
              {isNew(entry.updatedAt) && <span className="text-emerald-300"> ●</span>}
            </button>
          ))
        )}
      </div>
    </div>
  );
}

// ===== Layer activity panel =====

function LayerActivityPanel({
  goalScope,
  todos,
  label,
}: {
  goalScope: MissionDoc[];
  todos: CxxTodo[];
  label: string;
}) {
  // Sum workers across every mission in the selected goal sub-tree so the
  // participation bar reflects the whole goal, not a single sub-mission.
  const allWorkers = useMemo(
    () => goalScope.flatMap((m) => m.workers),
    [goalScope]
  );
  const workerByCxx = useMemo(() => {
    const map = new Map<WorkerOwnerRole, number>();
    for (const role of WORKER_OWNERS) map.set(role, 0);
    for (const w of allWorkers) {
      const r = w.owner;
      if ((WORKER_OWNERS as readonly string[]).includes(r)) {
        const role = r as WorkerOwnerRole;
        map.set(role, (map.get(role) ?? 0) + 1);
      }
    }
    return map;
  }, [allWorkers]);

  const layer = useMemo(
    () => computeGoalScopeLayers(goalScope, todos),
    [goalScope, todos]
  );
  const visibleTotals = useMemo(() => {
    const total = layer.ceo.total + layer.agents.reduce((sum, agent) => sum + agent.total, 0);
    const done = layer.ceo.done + layer.agents.reduce((sum, agent) => sum + agent.done, 0);
    return { total, done, remain: total - done };
  }, [layer]);

  const activeCxxCount = Array.from(workerByCxx.values()).filter((v) => v > 0).length;

  return (
    <div className="panel-shell fade-in flex h-full min-h-0 flex-col overflow-hidden p-2">
      <SectionLabel>Layer · {label}</SectionLabel>

      <div className="inset-shell mt-2 shrink-0 p-2">
        <div className="flex items-center justify-between font-mono text-[9px] text-slate-500">
          <span>실무자 비중 (worker by CXX, CEO 제외)</span>
          <span>
            {allWorkers.length}w · {activeCxxCount} CXX
          </span>
        </div>
        <div className="mt-1.5 flex h-3 overflow-hidden rounded">
          {WORKER_OWNERS.map((role) => {
            const count = workerByCxx.get(role) ?? 0;
            return (
              <div
                key={role}
                className={`stack-seg transition-[flex] duration-500 ease-out ${
                  count > 0 ? CXX_COLOR[role] : `${CXX_COLOR[role]}/30`
                }`}
                style={{ flex: Math.max(0.1, count) }}
                title={`${role.toUpperCase()} · ${count}`}
              />
            );
          })}
        </div>
        <div className="mt-1.5 flex flex-wrap gap-x-2 gap-y-1 font-mono text-[9px] text-slate-400">
          {WORKER_OWNERS.map((role) => (
            <span key={role} className="inline-flex items-center gap-1">
              <span
                className={`inline-block size-2 rounded-sm ${
                  (workerByCxx.get(role) ?? 0) > 0 ? CXX_COLOR[role] : `${CXX_COLOR[role]}/30`
                }`}
              />
              {role.toUpperCase()} {workerByCxx.get(role) ?? 0}
            </span>
          ))}
        </div>
      </div>

      <div className="inset-shell mt-2 h-0 min-h-[96px] flex-1 overflow-y-auto overflow-x-hidden">
        <table className="w-full text-[10px]">
          <thead className="sticky top-0 bg-slate-900/60 font-mono text-[9px] uppercase tracking-wider">
            <tr>
              <th className="px-2 py-1 text-left text-slate-500">Layer</th>
              <th className="px-2 py-1 text-right text-slate-500">TODO</th>
              <th className="px-2 py-1 text-right text-emerald-400/80">DONE</th>
              <th className="px-2 py-1 text-right text-orange-300/80">Remain</th>
            </tr>
          </thead>
          <tbody>
            <LayerRow label="CEO" stats={layer.ceo} />
            {layer.agents.map((agent) => (
              <tr key={agent.id} className="border-t border-slate-800/70 bg-slate-950/30">
                <td
                  className={`max-w-0 truncate px-2 py-1 ${
                    agent.kind === "cxx" ? "font-semibold text-cyan-200" : "pl-5 text-slate-400"
                  }`}
                  title={agent.id}
                >
                  {agent.kind === "worker" ? "└ " : ""}
                  {agent.label}
                </td>
                <td className="px-2 py-1 text-right text-slate-300">
                  {agent.total}
                </td>
                <td className="px-2 py-1 text-right text-emerald-300">
                  {agent.done}
                </td>
                <td className={`px-2 py-1 text-right ${agent.remain > 0 ? "text-orange-300" : "text-slate-600"}`}>
                  {agent.remain}
                </td>
              </tr>
            ))}
            <tr className="border-t border-slate-800 bg-slate-900/40">
              <td className="px-2 py-1 font-semibold text-slate-300">∑</td>
              <td className="px-2 py-1 text-right font-semibold text-slate-100">
                {visibleTotals.total}
              </td>
              <td className="px-2 py-1 text-right font-semibold text-emerald-300">
                {visibleTotals.done}
              </td>
              <td className="px-2 py-1 text-right font-semibold text-orange-300">
                {visibleTotals.remain}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
  );
}

function LayerRow({ label, stats }: { label: string; stats: LayerStats }) {
  return (
    <tr className="border-t border-slate-800">
      <td className="px-2 py-1 text-cyan-200">{label}</td>
      <td className="px-2 py-1 text-right text-slate-200">{stats.total}</td>
      <td className="px-2 py-1 text-right text-emerald-300">{stats.done}</td>
      <td
        className={`px-2 py-1 text-right ${stats.remain > 0 ? "text-orange-300" : "text-slate-500"}`}
      >
        {stats.remain}
      </td>
    </tr>
  );
}

type LayerStats = { total: number; done: number; remain: number };

function normalizeKind(s: string) {
  return s.replace(/[_-]/g, "").toLowerCase();
}

function isTerminalLifecycle(lifecycle: MissionDoc["lifecycle"]) {
  return (
    lifecycle === "closed" ||
    lifecycle === "cancelled" ||
    lifecycle === "superseded" ||
    lifecycle === "complete"
  );
}

function computeGoalScopeLayers(
  goalScope: MissionDoc[],
  todos: CxxTodo[]
): {
  ceo: LayerStats;
  cxx: LayerStats;
  worker: LayerStats;
  agents: Array<{
    id: string;
    label: string;
    kind: "cxx" | "worker";
    total: number;
    done: number;
    remain: number;
  }>;
} {
  // === CEO layer: ceo todos (status.json) ↔ mission directories of matching kind ===
  // Runtime rarely flips status to "done", so infer completion from how many
  // mission directories of each kind already exist under the goal scope.
  const ceoTodos = todos.filter((t) => t.owner.toLowerCase() === "ceo");
  const todoByKind = new Map<string, number>();
  for (const t of ceoTodos) {
    const k = normalizeKind(t.kind || "unknown");
    todoByKind.set(k, (todoByKind.get(k) ?? 0) + 1);
  }
  const missionByKind = new Map<string, number>();
  for (const m of goalScope) {
    const k = normalizeKind(m.type);
    missionByKind.set(k, (missionByKind.get(k) ?? 0) + 1);
  }
  const ceo: LayerStats = { total: ceoTodos.length, done: 0, remain: 0 };
  for (const [kind, count] of todoByKind) {
    const matched = missionByKind.get(kind) ?? 0;
    ceo.done += Math.min(count, matched);
  }
  ceo.remain = ceo.total - ceo.done;

  // === CXX layer: a CXX is "done" on a mission once its <role>.md exists ===
  // cxxPresent already encodes that signal. CEO is excluded — CEO is its own layer.
  let cxxTotal = 0;
  let cxxDone = 0;
  for (const m of goalScope) {
    const presentNonCeo = m.cxxPresent.filter(
      (r) => (WORKER_OWNERS as readonly string[]).includes(r)
    );
    cxxTotal += presentNonCeo.length;
    cxxDone += presentNonCeo.length;
  }
  const cxx: LayerStats = { total: cxxTotal, done: cxxDone, remain: cxxTotal - cxxDone };

  // === Worker layer: every worker doc that submitted output (status COMPLETE) ===
  let wTotal = 0;
  let wDone = 0;
  for (const m of goalScope) {
    wTotal += m.workers.length;
    wDone += isTerminalLifecycle(m.lifecycle)
      ? m.workers.length
      : m.workers.filter((w) => w.status === "COMPLETE").length;
  }
  const worker: LayerStats = { total: wTotal, done: wDone, remain: wTotal - wDone };

  const agentRows: Array<{
    id: string;
    label: string;
    kind: "cxx" | "worker";
    total: number;
    done: number;
    remain: number;
  }> = [];
  const groupedRows = WORKER_OWNERS.map((role, index) => {
    const roleMissions = goalScope.filter(
      (m) => m.cxxPresent.includes(role) || m.workers.some((w) => w.owner === role)
    );
    const roleTotal = roleMissions.length;
    const roleIncomplete = roleMissions.filter(
      (m) =>
        !isTerminalLifecycle(m.lifecycle) &&
        m.workers.some((w) => w.owner === role && w.status !== "COMPLETE")
    ).length;
    const rows: typeof agentRows = [];
    rows.push({
      id: role,
      label: role.toUpperCase(),
      kind: "cxx",
      total: roleTotal,
      done: Math.max(0, roleTotal - roleIncomplete),
      remain: roleIncomplete,
    });

    const workersByName = new Map<string, { label: string; total: number; done: number }>();
    for (const mission of goalScope) {
      for (const worker of mission.workers.filter((w) => w.owner === role)) {
        const entry =
          workersByName.get(worker.name) ??
          { label: worker.displayName || worker.name, total: 0, done: 0 };
        entry.total += 1;
        if (isTerminalLifecycle(mission.lifecycle) || worker.status === "COMPLETE") {
          entry.done += 1;
        }
        workersByName.set(worker.name, entry);
      }
    }
    for (const [name, entry] of workersByName) {
      rows.push({
        id: `${role}:${name}`,
        label: entry.label,
        kind: "worker",
        total: entry.total,
        done: entry.done,
        remain: Math.max(0, entry.total - entry.done),
      });
    }
    const priority = roleTotal === 0 ? 2 : roleIncomplete > 0 ? 0 : 1;
    return { priority, index, rows };
  });
  groupedRows
    .sort((a, b) => a.priority - b.priority || a.index - b.index)
    .forEach((group) => agentRows.push(...group.rows));

  return { ceo, cxx, worker, agents: agentRows };
}

// ===== Recent report panel =====

function RecentReportPanel({
  missions,
  onSelectWorker,
}: {
  missions: MissionDoc[];
  onSelectWorker: (mission: MissionDoc, worker: WorkerDocEntry) => void;
}) {
  const reports = useMemo(() => {
    const list: Array<{ mission: MissionDoc; worker: WorkerDocEntry; ts: number }> = [];
    for (const mission of missions) {
      for (const worker of mission.workers) {
        if (!worker.updatedAt) continue;
        const ts = new Date(worker.updatedAt).getTime();
        if (!Number.isFinite(ts)) continue;
        list.push({ mission, worker, ts });
      }
    }
    list.sort((a, b) => b.ts - a.ts);
    return list;
  }, [missions]);

  return (
    <div className="panel-shell fade-in flex min-h-0 flex-col p-2">
      <div className="flex items-center justify-between">
        <SectionLabel>Recent Report (from CXX)</SectionLabel>
        <span className="font-mono text-[9px] text-slate-500">latest on top</span>
      </div>
      <div className="mt-2 min-h-0 flex-1 space-y-1.5 overflow-auto pr-1 text-[10px]">
        {reports.length === 0 ? (
          <div className="text-slate-500">No worker reports yet.</div>
        ) : (
          reports.map(({ mission, worker, ts }) => {
            const role = worker.owner;
            const colorClass =
              role in CXX_TEXT ? CXX_TEXT[role as CxxRole] : "text-slate-300";
            // Strip leading YAML frontmatter (docmeta block) before scanning
            // for the first content line, otherwise we'd show "docmeta:" etc.
            const stripped = (worker.content || "").replace(/^---[\s\S]*?---\n+/, "");
            const firstLine = stripped
              .split("\n")
              .map((line) => line.trim())
              .find((line) => line && !line.startsWith("#"));
            return (
              <button
                key={`${mission.missionId}:${worker.name}`}
                type="button"
                onClick={() => onSelectWorker(mission, worker)}
                className="inset-shell slide-in block w-full cursor-pointer px-2 py-1.5 text-left transition-transform hover:-translate-y-0.5 hover:border-cyan-400/40"
              >
                <div className="flex items-center justify-between text-[9px]">
                  <span className={colorClass}>
                    {role.toUpperCase()} / {worker.displayName}
                  </span>
                  <span className="text-slate-500">{formatTime(new Date(ts).toISOString())}</span>
                </div>
                <div className="mt-0.5 truncate text-[10px] text-slate-200">
                  {firstLine || `${mission.missionId} — report`}
                </div>
              </button>
            );
          })
        )}
      </div>
    </div>
  );
}

// ===== Cadence strip =====

function CadenceStrip({ ownerHistory }: { ownerHistory: OwnerPromptEntry[] }) {
  const bucketEntries = useMemo(() => {
    const now = Date.now();
    const arr: OwnerPromptEntry[][] = Array.from({ length: 24 }, () => []);
    for (const entry of ownerHistory) {
      if (!entry.ts) continue;
      const t = new Date(entry.ts).getTime();
      if (!Number.isFinite(t)) continue;
      const hoursAgo = Math.floor((now - t) / (60 * 60 * 1000));
      if (hoursAgo < 0 || hoursAgo >= 24) continue;
      arr[hoursAgo].push(entry);
    }
    // newest-first within each bucket
    for (const list of arr) {
      list.sort((a, b) => (b.ts ?? "").localeCompare(a.ts ?? ""));
    }
    return arr;
  }, [ownerHistory]);
  const buckets = useMemo(() => bucketEntries.map((b) => b.length), [bucketEntries]);

  const max = Math.max(1, ...buckets);
  const cellColor = (n: number) => {
    if (n === 0) return "bg-slate-900";
    const ratio = n / max;
    if (ratio > 0.75) return "bg-rose-500/80 ring-1 ring-rose-400";
    if (ratio > 0.5) return "bg-orange-500/70";
    if (ratio > 0.25) return "bg-emerald-500/60";
    return "bg-emerald-500/30";
  };

  const [tooltip, setTooltip] = useState<{
    idx: number;
    entries: OwnerPromptEntry[];
    x: number;
    y: number;
  } | null>(null);

  const tooltipRef = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (!tooltip) return;
    const handler = (event: MouseEvent) => {
      const target = event.target as Node;
      if (tooltipRef.current?.contains(target)) return;
      const el = target as HTMLElement;
      if (el.closest?.("[data-cadence-cell]")) return;
      setTooltip(null);
    };
    document.addEventListener("mousedown", handler);
    return () => document.removeEventListener("mousedown", handler);
  }, [tooltip]);

  const handleCellClick = (idx: number, event: React.MouseEvent<HTMLButtonElement>) => {
    const entries = bucketEntries[idx];
    if (entries.length === 0) {
      setTooltip(null);
      return;
    }
    const rect = event.currentTarget.getBoundingClientRect();
    setTooltip({
      idx,
      entries,
      x: rect.left + rect.width / 2,
      y: rect.bottom,
    });
  };

  return (
    <div className="inset-shell relative shrink-0 px-2 pb-1.5 pt-1.5">
      <div className="flex items-center justify-between font-mono text-[9px] text-slate-500">
        <span>Cadence · last 24h (owner prompts/h) · click cell for detail</span>
        <span className="text-emerald-300">max {max}</span>
      </div>
      <div
        className="mt-1 grid gap-px"
        style={{ gridTemplateColumns: "repeat(24, minmax(0, 1fr))" }}
      >
        {buckets.map((count, idx) => {
          const interactive = count > 0;
          const isPeak = count > 0 && count === max;
          return (
            <button
              key={idx}
              data-cadence-cell
              type="button"
              disabled={!interactive}
              onClick={(event) => handleCellClick(idx, event)}
              className={`h-4 transition-all duration-300 ${cellColor(count)} ${
                isPeak ? "cad-peak" : ""
              } ${
                interactive
                  ? "cursor-pointer hover:scale-y-150 hover:brightness-125"
                  : "cursor-default"
              } ${tooltip?.idx === idx ? "ring-2 ring-cyan-300" : ""}`}
              title={interactive ? `-${idx}h · ${count} prompts` : ""}
            />
          );
        })}
      </div>
      <div className="mt-0.5 flex justify-between font-mono text-[8px] text-slate-600">
        <span>now</span>
        <span>-12h</span>
        <span>-24h</span>
      </div>
      {tooltip && (
        <CadencePromptTooltip
          ref={tooltipRef}
          entries={tooltip.entries}
          hourIdx={tooltip.idx}
          x={tooltip.x}
          y={tooltip.y}
          onClose={() => setTooltip(null)}
        />
      )}
    </div>
  );
}

const CadencePromptTooltip = (() => {
  const Inner = (
    {
      entries,
      hourIdx,
      x,
      y,
      onClose,
    }: {
      entries: OwnerPromptEntry[];
      hourIdx: number;
      x: number;
      y: number;
      onClose: () => void;
    },
    ref: React.Ref<HTMLDivElement>
  ) => {
    const colorFor = (type: string) =>
      type === "hot-fix"
        ? "border-rose-500/40 bg-rose-950/30"
        : type === "submission"
        ? "border-emerald-500/30 bg-emerald-950/30"
        : "bg-slate-950/60";
    const labelFor = (type: string) =>
      type === "hot-fix"
        ? "text-rose-300"
        : type === "submission"
        ? "text-emerald-300"
        : "text-cyan-300";
    return (
      <div
        ref={ref}
        className="pop-in pointer-events-auto fixed z-40 rounded border border-cyan-400/60 bg-[#0b1328] px-3 py-2 shadow-[0_10px_30px_rgba(0,0,0,0.6)]"
        style={{
          left: Math.max(8, x - 200),
          top: Math.min(window.innerHeight - 320, y + 8),
          width: 400,
        }}
      >
        <div className="flex items-center justify-between">
          <div className="font-mono text-[9px] uppercase tracking-[0.2em] text-slate-500">
            Owner Prompts · {hourIdx === 0 ? "this hour" : `-${hourIdx}h`} ({entries.length})
          </div>
          <button
            type="button"
            onClick={onClose}
            className="text-sm leading-none text-slate-400 hover:text-slate-100"
            aria-label="Close"
          >
            ×
          </button>
        </div>
        <div className="mt-1.5 max-h-[280px] space-y-1 overflow-auto pr-1">
          {entries.map((entry, idx) => (
            <div
              key={`${entry.ts}-${idx}`}
              className={`rounded border border-transparent px-2 py-1.5 ${colorFor(entry.type)}`}
            >
              <div className="flex items-center justify-between text-[9px]">
                <span className={`font-mono ${labelFor(entry.type)}`}>/{entry.type}</span>
                <span className="text-slate-500">{formatTime(entry.ts)}</span>
              </div>
              <div className="mt-0.5 line-clamp-3 text-[10px] text-slate-300">
                {entry.content}
              </div>
            </div>
          ))}
        </div>
      </div>
    );
  };
  return Object.assign(
    (
      props: {
        entries: OwnerPromptEntry[];
        hourIdx: number;
        x: number;
        y: number;
        onClose: () => void;
      } & { ref?: React.Ref<HTMLDivElement> }
    ) => Inner(props, props.ref ?? null),
    {}
  );
})() as React.ForwardRefExoticComponent<
  {
    entries: OwnerPromptEntry[];
    hourIdx: number;
    x: number;
    y: number;
    onClose: () => void;
  } & React.RefAttributes<HTMLDivElement>
>;

// ===== Heatmap =====

function formatBucketOffset(bucket: number) {
  const minutes = bucket * (BUCKET_MS / 60_000);
  if (minutes === 0) return "now";
  if (minutes < 60) return `-${minutes}m`;
  const h = Math.floor(minutes / 60);
  const m = minutes % 60;
  return m === 0 ? `-${h}h` : `-${h}h${m}m`;
}

function WorkflowHeatmap({
  lanes,
  cells,
  totalBuckets,
  selectedCells,
  dragStart,
  dragEnd,
  onDragStart,
  onDragMove,
  onDragEnd,
  onSelectLane,
  onCellClick,
}: {
  lanes: AgentLane[];
  cells: HeatCell[];
  totalBuckets: number;
  selectedCells: HeatCell[];
  dragStart: { x: number; y: number } | null;
  dragEnd: { x: number; y: number } | null;
  onDragStart: (point: { x: number; y: number }) => void;
  onDragMove: (point: { x: number; y: number }) => void;
  onDragEnd: (missionId: string | null) => void;
  onSelectLane: (id: string) => void;
  onCellClick: (cell: HeatCell, event: React.PointerEvent) => void;
}) {
  const scrollRef = useRef<HTMLDivElement>(null);
  const measureRef = useRef<HTMLDivElement>(null);
  const [containerWidth, setContainerWidth] = useState(0);
  const prevBucketCountRef = useRef(totalBuckets);

  useEffect(() => {
    const el = measureRef.current;
    if (!el) return;
    setContainerWidth(el.clientWidth);
    const ro = new ResizeObserver((entries) => {
      const entry = entries[0];
      if (entry) setContainerWidth(entry.contentRect.width);
    });
    ro.observe(el);
    return () => ro.disconnect();
  }, []);

  const availableWidth = Math.max(360, containerWidth - LANE_LABEL_WIDTH);
  const bucketPx = Math.max(MIN_BUCKET_PX, availableWidth / VISIBLE_BUCKETS);

  useLayoutEffect(() => {
    const el = scrollRef.current;
    if (!el) {
      prevBucketCountRef.current = totalBuckets;
      return;
    }
    const diff = totalBuckets - prevBucketCountRef.current;
    if (diff > 0 && el.scrollLeft > 0) {
      el.scrollLeft += diff * bucketPx;
    }
    prevBucketCountRef.current = totalBuckets;
  }, [totalBuckets, bucketPx]);

  const selectedSet = useMemo(
    () => new Set(selectedCells.map((cell) => `${cell.x}:${cell.y}`)),
    [selectedCells]
  );
  const cellByXY = useMemo(() => {
    const map = new Map<string, HeatCell>();
    for (const cell of cells) map.set(`${cell.x}:${cell.y}`, cell);
    return map;
  }, [cells]);

  const handlePointerUp = () => {
    if (!dragStart || !dragEnd) {
      onDragEnd(null);
      return;
    }
    const cell = cellByXY.get(`${dragEnd.x}:${dragEnd.y}`);
    onDragEnd(cell?.mission?.missionId ?? null);
  };

  const totalWidth = LANE_LABEL_WIDTH + totalBuckets * bucketPx;

  return (
    <div ref={measureRef} className="inset-shell relative min-h-0 flex-1 p-2">
      <div ref={scrollRef} className="h-full overflow-auto">
        <div
          className="grid select-none gap-px"
          style={{
            gridTemplateColumns: `${LANE_LABEL_WIDTH}px repeat(${totalBuckets}, ${bucketPx}px)`,
            gridTemplateRows: `${TIME_LABEL_HEIGHT}px repeat(${lanes.length}, ${LANE_ROW_HEIGHT}px)`,
            width: `${totalWidth}px`,
          }}
          onPointerLeave={handlePointerUp}
          onPointerUp={handlePointerUp}
        >
          <div
            className="sticky left-0 z-20 bg-[#071022]"
            style={{ gridColumn: 1, gridRow: 1 }}
          />
          {Array.from({ length: totalBuckets }).map((_, idx) => {
            const showLabel = idx === 0 || idx % 10 === 0;
            return (
              <div
                key={`t-${idx}`}
                className="grid place-items-center font-mono text-[9px] leading-none text-slate-500"
                style={{ gridColumn: idx + 2, gridRow: 1 }}
              >
                {showLabel ? formatBucketOffset(idx) : ""}
              </div>
            );
          })}
          {lanes.map((lane, idx) => (
            <button
              key={`lane-${lane.id}`}
              type="button"
              onClick={() => onSelectLane(lane.id)}
              className={`sticky left-0 z-10 truncate rounded bg-[#071022] px-2 text-left font-mono text-[10px] leading-[18px] ${
                lane.kind === "worker" ? "text-slate-500" : "text-slate-300"
              } hover:text-cyan-200`}
              style={{ gridColumn: 1, gridRow: idx + 2 }}
              title={`${lane.label} · ${lane.group}`}
            >
              {lane.label}
            </button>
          ))}
          {cells.map((cell) => {
            const selected = selectedSet.has(`${cell.x}:${cell.y}`);
            const interactive = cell.mission !== null;
            return (
              <button
                key={`${cell.x}-${cell.y}-${cell.laneId}`}
                type="button"
                disabled={!interactive}
                onPointerDown={(event) => {
                  if (!interactive) return;
                  event.preventDefault();
                  onDragStart({ x: cell.x, y: cell.y });
                  onDragMove({ x: cell.x, y: cell.y });
                }}
                onPointerEnter={(event) => {
                  if (!interactive) return;
                  if (event.buttons === 1) {
                    onDragMove({ x: cell.x, y: cell.y });
                  }
                }}
                onClick={(event) => {
                  if (!interactive) return;
                  onCellClick(cell, event as unknown as React.PointerEvent);
                }}
                className={`heat-cell min-h-0 rounded-sm border transition-transform ${
                  interactive ? "cursor-pointer hover:scale-[1.4] hover:z-10 hover:relative" : "cursor-default"
                } ${
                  cell.hotfix
                    ? "border-rose-500"
                    : selected
                    ? "border-cyan-300"
                    : "border-transparent"
                } ${heatColor(cell.count)}`}
                style={{ gridColumn: cell.x + 2, gridRow: cell.y + 2 }}
                title={
                  interactive
                    ? `${cell.bucketLabel} · ${cell.laneLabel} · ${cell.mission?.missionId}`
                    : ""
                }
              />
            );
          })}
        </div>
      </div>
      {dragStart && dragEnd && (
        <div className="pointer-events-none absolute bottom-2 right-3 rounded bg-cyan-950/90 px-2 py-1 font-mono text-[10px] text-cyan-100">
          selected {selectedCells.length} cells
        </div>
      )}
    </div>
  );
}

function ApprovalTooltip({
  mission,
  x,
  y,
  onClose,
}: {
  mission: MissionDoc;
  x: number;
  y: number;
  onClose: () => void;
}) {
  const tone =
    mission.type === "hotfix"
      ? "border-rose-500/50"
      : mission.type === "submission"
      ? "border-emerald-500/40"
      : "border-cyan-400/60";
  return (
    <div
      className={`pop-in pointer-events-auto fixed z-40 rounded border bg-[#0b1328] px-3 py-2 shadow-[0_10px_30px_rgba(0,0,0,0.6)] ${tone}`}
      style={{
        left: Math.max(8, x - 180),
        top: Math.max(8, y - 110),
        minWidth: 360,
        maxWidth: 460,
      }}
    >
      <div className="flex items-center justify-between gap-3">
        <div className="truncate font-mono text-[10px] text-cyan-300">
          {mission.type.toUpperCase()} · {mission.missionId}
        </div>
        <button
          type="button"
          onClick={onClose}
          className="text-sm leading-none text-slate-400 hover:text-slate-100"
          aria-label="Close"
        >
          ×
        </button>
      </div>
      <div className="mt-1.5 flex flex-wrap items-center gap-1 text-[10px]">
        <FlowChip label="Owner" />
        <Arrow />
        <FlowChip label="CEO" />
        {mission.cxxPresent.map((role) => (
          <span key={role} className="inline-flex items-center gap-1">
            <Arrow />
            <FlowChip label={role.toUpperCase()} />
            {mission.workers
              .filter((worker) => worker.owner === role)
              .slice(0, 3)
              .map((worker) => (
                <span key={worker.name} className="inline-flex items-center gap-1">
                  <Arrow />
                  <FlowChip label={worker.displayName} muted />
                </span>
              ))}
          </span>
        ))}
      </div>
    </div>
  );
}

// ===== Document Viewer (expandable) =====

const MARKDOWN_COMPONENTS: Components = {
  h1: ({ children }) => (
    <h1 className="mb-2 mt-3 text-base font-semibold text-slate-100">{children}</h1>
  ),
  h2: ({ children }) => (
    <h2 className="mb-2 mt-3 text-sm font-semibold text-cyan-200">{children}</h2>
  ),
  h3: ({ children }) => (
    <h3 className="mb-1 mt-2 font-mono text-[11px] uppercase tracking-wider text-cyan-300">
      {children}
    </h3>
  ),
  h4: ({ children }) => (
    <h4 className="mb-1 mt-2 text-[11px] font-semibold text-slate-200">{children}</h4>
  ),
  p: ({ children }) => (
    <p className="my-1.5 text-[11px] leading-5 text-slate-300">{children}</p>
  ),
  ul: ({ children }) => (
    <ul className="my-1.5 ml-4 list-disc space-y-0.5 text-[11px] text-slate-300">
      {children}
    </ul>
  ),
  ol: ({ children }) => (
    <ol className="my-1.5 ml-5 list-decimal space-y-0.5 text-[11px] text-slate-300">
      {children}
    </ol>
  ),
  li: ({ children }) => <li className="leading-5">{children}</li>,
  a: ({ children, href }) => (
    <a
      href={href}
      target="_blank"
      rel="noreferrer"
      className="text-cyan-300 underline decoration-cyan-300/40 hover:text-cyan-200"
    >
      {children}
    </a>
  ),
  blockquote: ({ children }) => (
    <blockquote className="my-2 border-l-2 border-cyan-500/40 pl-3 text-[11px] italic text-slate-400">
      {children}
    </blockquote>
  ),
  hr: () => <hr className="my-3 border-slate-800" />,
  strong: ({ children }) => (
    <strong className="font-semibold text-slate-100">{children}</strong>
  ),
  em: ({ children }) => <em className="italic text-slate-300">{children}</em>,
  table: ({ children }) => (
    <div className="my-2 overflow-x-auto">
      <table className="w-full border-collapse text-[10px]">{children}</table>
    </div>
  ),
  thead: ({ children }) => <thead className="bg-slate-900/70">{children}</thead>,
  th: ({ children }) => (
    <th className="border border-slate-800 px-2 py-1 text-left font-mono text-[10px] text-cyan-300">
      {children}
    </th>
  ),
  td: ({ children }) => (
    <td className="border border-slate-800 px-2 py-1 text-slate-300">{children}</td>
  ),
  pre: ({ children }) => (
    <pre className="my-2 overflow-auto rounded border border-slate-800 bg-[#040a18] p-2 font-mono text-[10px] leading-4 text-slate-200">
      {children}
    </pre>
  ),
  code: ({ className, children, ...props }) => {
    const isBlock = typeof className === "string" && className.startsWith("language-");
    if (isBlock) {
      return (
        <code className={`${className} text-slate-200`} {...props}>
          {children}
        </code>
      );
    }
    return (
      <code className="rounded bg-slate-800/80 px-1 py-0.5 font-mono text-[10px] text-cyan-200">
        {children}
      </code>
    );
  },
};

function DocumentViewer({
  mission,
  lane,
  customDoc,
  expanded,
  onToggle,
}: {
  mission: MissionDoc | null;
  lane: AgentLane | null;
  customDoc: { source: string; title: string; content: string } | null;
  expanded: boolean;
  onToggle: () => void;
}) {
  const role = lane?.role as
    | keyof Pick<MissionDoc, "ceo" | "coo" | "cdo" | "cto" | "cqo" | "ops">
    | undefined;
  const roleDoc = role ? mission?.[role] : null;
  const workerDoc = lane?.worker?.content ?? null;
  const rawContent = customDoc
    ? customDoc.content
    : workerDoc ?? roleDoc ?? mission?.ceo ?? "_No document selected._";
  // Hide the leading YAML frontmatter (docmeta block) — keep only the body.
  const content = rawContent.replace(/^---[\s\S]*?---\n+/, "");
  const subtitle = customDoc
    ? `${customDoc.source} · ${customDoc.title}`
    : `${mission?.missionId ?? "select /goal or /submission"} · ${
        workerDoc
          ? lane?.worker?.displayName ?? "worker"
          : role
          ? role.toUpperCase()
          : "CEO"
      }`;
  return (
    <section className="panel-shell flex min-h-0 flex-1 flex-col p-2">
      <div className="flex items-center justify-between gap-2">
        <SectionLabel>Document Viewer · {subtitle}</SectionLabel>
        <button
          type="button"
          onClick={onToggle}
          className="grid h-6 w-6 shrink-0 place-items-center rounded text-[11px] text-slate-400 hover:bg-white/10 hover:text-cyan-200"
          title={expanded ? "Minimize viewer" : "Expand to 50%"}
          aria-label={expanded ? "Minimize viewer" : "Expand viewer"}
        >
          <span className={`doc-toggle-icon ${expanded ? "rotate-180" : ""}`}>↗</span>
        </button>
      </div>
      <div className="inset-shell mt-2 min-h-0 flex-1 overflow-auto p-3">
        <article className="markdown-doc text-[11px] leading-5 text-slate-300">
          <ReactMarkdown remarkPlugins={[remarkGfm]} components={MARKDOWN_COMPONENTS}>
            {content}
          </ReactMarkdown>
        </article>
      </div>
    </section>
  );
}

// ===== Shared bits =====

function SectionLabel({ children }: { children: React.ReactNode }) {
  return (
    <div className="font-mono text-[9px] uppercase tracking-[0.2em] text-slate-500 truncate">
      {children}
    </div>
  );
}

function FlowChip({ label, muted = false }: { label: string; muted?: boolean }) {
  return (
    <span
      className={`rounded border px-1.5 py-0.5 font-mono ${
        muted ? "border-slate-700 text-slate-400" : "border-cyan-400/30 text-cyan-200"
      }`}
    >
      {label}
    </span>
  );
}

function Arrow() {
  return <span className="text-slate-600">→</span>;
}

function heatColor(count: number) {
  // 3-state activity from sample.count: 0 idle / 1 standby / 2 in-progress.
  if (count >= 2) return "bg-emerald-500/80";
  if (count >= 1) return "bg-emerald-500/30";
  return "bg-slate-900";
}

// ===== Lane / Heatmap builders =====

function buildLanes(snapshot: HarnessSnapshot): AgentLane[] {
  const activeMission = snapshot.missions.find((mission) => mission.active) ?? snapshot.missions[0] ?? null;
  const workersByRole = new Map<CxxRole, Array<{ worker: WorkerDocEntry; mission: MissionDoc }>>();
  for (const role of CXX_ROLES) workersByRole.set(role, []);

  const workerIndex = new Map<string, { worker: WorkerDocEntry; mission: MissionDoc }>();
  for (const mission of snapshot.missions) {
    for (const worker of mission.workers) {
      if (!CXX_ROLES.includes(worker.owner as CxxRole)) continue;
      const role = worker.owner as CxxRole;
      const key = `${role}:${worker.name}`;
      const existing = workerIndex.get(key);
      if (
        !existing ||
        (!existing.worker.active && worker.active) ||
        (existing.worker.status === "COMPLETE" && worker.status !== "COMPLETE")
      ) {
        workerIndex.set(key, { worker, mission });
      }
    }
  }

  for (const entry of workerIndex.values()) {
    workersByRole.get(entry.worker.owner as CxxRole)?.push(entry);
  }

  // CXX → its workers, then next CXX → its workers (proper hierarchy).
  // No cap: heatmap container scrolls vertically so OPS at the bottom is always
  // reachable even when upstream CXX bring many workers.
  const lanes: AgentLane[] = [];
  for (const role of CXX_ROLES) {
    const workerEntries = workersByRole.get(role) ?? [];
    const workers = workerEntries.map((entry) => entry.worker);
    const todos = snapshot.todos.filter((t) => t.owner === role);
    const hasError =
      (role === "ops" && snapshot.incidents.length > 0) ||
      todos.some((t) => t.status === "blocked");
    const waiting =
      todos.some((t) => t.status === "pending" || t.status === "paused") ||
      workers.some((w) => !w.active && w.status !== "COMPLETE");
    lanes.push({
      id: role,
      label: role.toUpperCase(),
      role,
      group: `${role.toUpperCase()} group · ${workers.length} workers`,
      kind: "cxx",
      status: hasError ? "error" : waiting ? "waiting" : "normal",
      todos: todos.length,
      workers,
      mission: activeMission,
    });
    for (const { worker, mission } of workerEntries) {
      lanes.push({
        id: `${role}:${worker.name}`,
        label: `└ ${worker.displayName.slice(0, 16)}`,
        role,
        group: `${role.toUpperCase()} worker`,
        kind: "worker",
        status: worker.active ? "normal" : worker.status === "COMPLETE" ? "normal" : "waiting",
        todos: 0,
        workers: [],
        worker,
        mission,
      });
    }
  }
  return lanes;
}

function buildHeatmap(
  snapshot: HarnessSnapshot,
  lanes: AgentLane[],
  samples: HeatSample[],
  startedAt: number
): { cells: HeatCell[]; totalBuckets: number } {
  const cells: HeatCell[] = [];
  const now = Date.now();
  const nowMinute = Math.floor(now / BUCKET_MS);
  const startMinute = Math.floor(startedAt / BUCKET_MS);
  const elapsedMinutes = Math.max(0, nowMinute - startMinute);
  const totalBuckets = Math.max(VISIBLE_BUCKETS, elapsedMinutes + 1);
  const missionById = new Map(snapshot.missions.map((m) => [m.missionId, m]));

  type Agg = { count: number; hotfix: boolean; missionId: string | null };
  const aggregated = new Map<string, Agg>();
  for (const sample of samples) {
    const sampleMinute = Math.floor(sample.ts / BUCKET_MS);
    const x = nowMinute - sampleMinute;
    if (x < 0 || x >= totalBuckets) continue;
    const key = `${x}:${sample.laneId}`;
    const prev = aggregated.get(key);
    if (prev) {
      // Keep the strongest observed state in this bucket (0 < 1 < 2),
      // never sum — the cell should reflect "what was happening" not "how
      // many polling ticks happened".
      prev.count = Math.max(prev.count, sample.count);
      prev.hotfix = prev.hotfix || sample.hotfix;
      if (sample.missionId) prev.missionId = sample.missionId;
    } else {
      aggregated.set(key, {
        count: sample.count,
        hotfix: sample.hotfix,
        missionId: sample.missionId ?? null,
      });
    }
  }

  for (let y = 0; y < lanes.length; y++) {
    const lane = lanes[y];
    for (let x = 0; x < totalBuckets; x++) {
      const agg = aggregated.get(`${x}:${lane.id}`);
      // Only assign mission when the cell actually carries activity.
      // Empty cells (count=0, no sample) must stay missionless so clicks no-op.
      const hasData = !!agg && agg.count > 0;
      const missionId = hasData ? agg!.missionId : null;
      cells.push({
        x,
        y,
        laneId: lane.id,
        laneLabel: lane.label,
        bucketLabel: formatBucketOffset(x),
        count: agg?.count ?? 0,
        hotfix: agg?.hotfix ?? false,
        mission: missionId ? missionById.get(missionId) ?? null : null,
      });
    }
  }
  return { cells, totalBuckets };
}

function getSelectedCells(
  cells: HeatCell[],
  start: { x: number; y: number } | null,
  end: { x: number; y: number } | null
) {
  if (!start || !end) return [];
  const minX = Math.min(start.x, end.x);
  const maxX = Math.max(start.x, end.x);
  const minY = Math.min(start.y, end.y);
  const maxY = Math.max(start.y, end.y);
  return cells.filter(
    (cell) => cell.x >= minX && cell.x <= maxX && cell.y >= minY && cell.y <= maxY
  );
}
