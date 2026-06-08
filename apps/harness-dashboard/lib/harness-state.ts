import { existsSync, readdirSync, statSync, readFileSync, type Dirent } from "node:fs";
import path from "node:path";
import { readJsonSafe } from "./safe-json";
import type {
  AgentId,
  ErrorBanner,
  EvalScores,
  HarnessSnapshot,
  HarnessEvent,
  IncidentEntry,
  MeetingCadence,
  GotchaEntry,
  ConventionEntry,
  MissionDoc,
  OwnerPromptEntry,
  Pipeline,
  RoomId,
  RuntimeSnapshot,
  TrackStatus,
  WorkerDocEntry,
  CxxTodo,
  ActivitySample,
  HarnessFileEntry,
} from "./types";

const SNAPSHOT_VERSION = "1.2.0";
const GOAL_DESC_TRUNCATE = 200;
const ACTIVITY_RETENTION_MS = 7 * 24 * 60 * 60 * 1000;

interface RawProgress {
  goals?: {
    active_id?: string | null;
    list?: Array<{ id: string; title?: string; description?: string }>;
    current_adherence?: number | null;
  };
  current_agent?: AgentId | null;
  next_agent?: AgentId | null;
  agent_status?: string;
  updated_at?: string | null;
  owner_prompt?: {
    command?: string;
    summary?: string;
    received_at?: string | null;
    status?: string;
  } | null;
  pipeline?: Pipeline;
  failure?: { agent?: AgentId | null; message?: string | null; location?: string | null; retry_target?: AgentId | null } | null;
  meetings?: {
    active?: AgentId[];
    cadence?: MeetingCadence | string;
    next_scheduled?: string | null;
    current?: { type?: string; topic?: string; convened_at?: string | null } | null;
    // Real-harness schema (v6 NEXUS) — used as fallback when `current` is absent.
    requested_type?: string | null;
    requested_reason?: string | null;
    last_type?: string | null;
    last_reason?: string | null;
    decision?: { owner?: string; action_type?: string; tracks?: unknown[] } | null;
  };
  cto?: {
    last_review?: string | null;
    open_arch_risks?: number;
    contract_signed?: { be?: boolean; fe?: boolean };
  };
  cqo?: {
    last_audit?: string | null;
    sprint_verdict?: "pending" | "PASS" | "FAIL";
    open_regressions?: number;
    last_scores?: EvalScores | null;
  };
  service_ops?: {
    monitor?: {
      last_check?: string | null;
      alerts_this_sprint?: number;
      // G-006: when generator/eval co-spawns service-ops in monitor mode,
      // these fields toggle while the streamed child runs.
      stream_active?: boolean;
      stream_target?: string | null;
    };
    incident?: { open?: Array<{ id: string; dept?: string; severity?: string; message?: string; ts?: string | null }> };
    requested_mode?: string | null;
    health?: Array<{
      name?: string;
      host?: string;
      port?: number;
      status?: string;
      port_state?: string | null;
      health_status?: number | null;
      health_path?: string | null;
      log?: { recent_errors?: number | null };
    }>;
  };
  sprint?: { number?: number };
  parallel_tracks?: Array<{
    id: string;
    from_meeting?: string;
    to_dept?: string;
    to_room?: RoomId;
    status?: TrackStatus | string;
    label?: string;
  }>;
  // Real-harness conductor track shape (CLAUDE.md §parallel-tracks). Used when
  // top-level `parallel_tracks` is absent.
  conductor?: {
    state?: string | null;
    current_action?: string | null;
    stop_chain_count?: number | null;
    last_stop_chain_at?: string | null;
    tracks?: Array<{
      id: string;
      owner?: string;
      action_type?: string;
      deliverable?: string;
      deliverable_path?: string | null;
      status?: string;
      started_at?: string | null;
    }>;
    rendezvous?: { type?: string; when?: string } | null;
    fork_meeting_id?: string | null;
  };
  hypothesis?: {
    active?: Array<{ id: string; brief?: string; verdict?: string; ts?: string | null }>;
  };
  escalations?: {
    open?: Array<{ id: string; reason?: string; message?: string; ts?: string | null }>;
  };
  contracts?: {
    api?: { version?: string | null };
    feature_list?: { total?: number; passed?: number; failed?: number };
  };
  company_state?: {
    state?: string | null;
    active_workers?: number;
    workers?: Array<{
      name?: string;
      team?: number | string;
      feature?: string;
      agent?: string;
      phase?: string;
      prompt?: string | null;
      log?: string | null;
      report?: string | null;
      report_path?: string | null;
      progress?: string | number | null;
      eta?: string | null;
      spawn_status?: string;
      status?: string;
      pid?: number | null;
    }> | Record<string, {
      name?: string;
      team?: number | string;
      feature?: string;
      agent?: string;
      phase?: string;
      prompt?: string | null;
      log?: string | null;
      report_path?: string | null;
      progress?: string | number | null;
      eta?: string | null;
      spawn_status?: string;
      status?: string;
      pid?: number | null;
      owner?: string;
      report?: string | null;
    }>;
    last_dispatch?: Array<{
      team?: number | string;
      feature?: string;
      agent?: string;
      phase?: string;
      prompt?: string | null;
      log?: string | null;
      status?: string;
      spawn_status?: string;
      pid?: number | null;
    }>;
    last_dispatch_at?: string | null;
  };
}

function emptySnapshot(banner: ErrorBanner | null = null, rootDir?: string): HarnessSnapshot {
  return {
    version: SNAPSHOT_VERSION,
    ts: new Date().toISOString(),
    projectName: rootDir ? path.basename(rootDir) : "(unknown)",
    projectPath: rootDir ?? "",
    errorBanner: banner,
    runtime: {
      currentAgent: null,
      agentStatus: "unknown",
      nextAgent: null,
      updatedAt: null,
      ownerPrompt: null,
    },
    incidents: [],
    missions: [],
    ownerHistory: [],
    gotchas: [],
    conventions: [],
    todos: [],
    events: [],
    activitySamples: [],
    files: [],
  };
}

function readTextSafe(filePath: string): string | null {
  try {
    return readFileSync(filePath, "utf-8");
  } catch {
    return null;
  }
}

function firstLine(text: string | null): string {
  if (!text) return "";
  return text
    .split("\n")
    .map((line) => line.trim())
    .find((line) => line.length > 0 && !line.startsWith("---")) ?? "";
}

function truncateText(text: string, max = 150): string {
  const cleaned = text.replace(/\s+/g, " ").trim();
  if (cleaned.length <= max) return cleaned;
  return `${cleaned.slice(0, max - 1)}…`;
}

function buildIncidents(progress: RawProgress | null): IncidentEntry[] {
  const list = progress?.service_ops?.incident?.open ?? [];
  return list.map((it) => {
    const sev = (it.severity ?? "medium").toLowerCase();
    const severity =
      sev === "low" || sev === "medium" || sev === "high" || sev === "critical"
        ? (sev as IncidentEntry["severity"])
        : "medium";
    return {
      id: it.id,
      dept: it.dept ?? "Operations",
      severity,
      message: it.message,
      ts: it.ts ?? null,
    };
  });
}

interface RawWorker {
  name?: string;
  team?: number | string;
  feature?: string;
  agent?: string;
  phase?: string;
  prompt?: string | null;
  log?: string | null;
  spawn_status?: string;
  status?: string;
  pid?: number | null;
  owner?: string;
  report?: string | null;
  report_path?: string | null;
  progress?: string | number | null;
  eta?: string | null;
}
type WorkerOwner = WorkerDocEntry["owner"];

interface HiredWorkerEntry {
  name: string;
  owner: Exclude<WorkerOwner, "unknown">;
  sourcePath: string | null;
  mission: string | null;
  task: string | null;
  capability: string | null;
}

type MissionLifecycle = MissionDoc["lifecycle"];

function normalizeMissionLifecycle(raw: unknown): MissionLifecycle {
  const value = String(raw ?? "").toLowerCase().replace(/[_\s-]+/g, "-");
  if (
    value === "active" ||
    value === "operating" ||
    value === "closed" ||
    value === "cancelled" ||
    value === "superseded" ||
    value === "complete" ||
    value === "blocked"
  ) {
    return value;
  }
  if (value === "done" || value === "completed") return "complete";
  if (value === "canceled") return "cancelled";
  if (value === "monitoring" || value === "perpetual") return "operating";
  return "unknown";
}

function readMissionState(missionPath: string): {
  lifecycle: MissionLifecycle;
  active: boolean | null;
} {
  const statePath = path.join(missionPath, "mission-state.json");
  const state = readJsonSafe<{
    lifecycle?: unknown;
    status?: unknown;
    active?: boolean;
  }>(statePath);
  if (!state.ok) return { lifecycle: "unknown", active: null };

  const lifecycle = normalizeMissionLifecycle(state.value.lifecycle ?? state.value.status);
  return {
    lifecycle,
    active: typeof state.value.active === "boolean" ? state.value.active : null,
  };
}

function deriveWorkerProgress(worker: RawWorker): number | null {
  const explicit = worker?.progress;
  if (typeof explicit === "number" && Number.isFinite(explicit)) {
    return explicit > 1 ? Math.max(0, Math.min(1, explicit / 100)) : Math.max(0, Math.min(1, explicit));
  }
  if (typeof explicit === "string") {
    const match = explicit.match(/(\d+(?:\.\d+)?)/);
    if (match) return Math.max(0, Math.min(1, Number(match[1]) / 100));
  }
  const status = (worker?.status ?? worker?.spawn_status ?? "").toLowerCase();
  if (status === "blocked" || status === "failed") return 0.35;
  if (status === "recorded") return 0.15;
  if (status === "spawned" || status === "running") return 0.55;
  if (status === "complete" || status === "completed" || status === "done") return 1;
  return null;
}

function normalizeRawWorkers(value: RawWorker[] | Record<string, RawWorker> | null | undefined): RawWorker[] {
  const normalizeOne = (worker: RawWorker, fallbackName: string | null = null, idx = 0): RawWorker => {
    const name = worker.name ?? worker.agent ?? worker.feature ?? fallbackName ?? `worker-${idx + 1}`;
    const report = worker.report ?? worker.report_path ?? null;
    return {
      ...worker,
      name,
      team: worker.team ?? idx + 1,
      agent: worker.agent ?? name,
      feature: worker.feature ?? name,
      log: worker.log ?? report,
      report,
    };
  };
  if (Array.isArray(value)) return value.map((worker, idx) => normalizeOne(worker, null, idx));
  if (!value || typeof value !== "object") return [];
  return Object.entries(value).map(([name, worker], idx) => {
    const w = worker && typeof worker === "object" ? worker : {};
    return normalizeOne(w as RawWorker, name, idx);
  });
}

function normalizeWorkerName(value: string | null | undefined): string {
  return (value ?? "")
    .toLowerCase()
    .replace(/^harness-/, "")
    .replace(/\.md$/, "")
    .trim();
}

function normalizeWorkerOwner(value: string | null | undefined): HiredWorkerEntry["owner"] | null {
  const owner = (value ?? "").toLowerCase().replace(/^harness-/, "");
  if (owner === "coo" || owner === "cdo" || owner === "cto" || owner === "cqo" || owner === "ops") {
    return owner;
  }
  return null;
}

function readHiredWorkers(rootDir: string): HiredWorkerEntry[] {
  const rosterPath = path.join(rootDir, ".harness", "shared", "hr-roster.json");
  const roster = readJsonSafe<{
    hired?: Array<{
      worker?: string;
      name?: string;
      owner?: string;
      owningCxx?: string;
      mission?: string;
      task?: string;
      capability?: string;
      skillPath?: string;
      skillPaths?: { source?: string };
    }>;
  }>(rosterPath);
  if (!roster.ok) return [];

  const seen = new Set<string>();
  const hired: HiredWorkerEntry[] = [];
  for (const entry of roster.value.hired ?? []) {
    const name = normalizeWorkerName(entry.worker ?? entry.name);
    const owner = normalizeWorkerOwner(entry.owner ?? entry.owningCxx);
    if (!name || !owner) continue;

    const sourcePath = entry.skillPaths?.source ?? entry.skillPath ?? `.harness/shared/HR-Resource/${name}/SKILL.md`;
    const sourceAbs = path.join(rootDir, sourcePath);
    if (!existsSync(sourceAbs)) continue;

    const key = `${owner}:${name}`;
    if (seen.has(key)) continue;
    seen.add(key);
    hired.push({
      name,
      owner,
      sourcePath,
      mission: entry.mission ?? null,
      task: entry.task ?? null,
      capability: entry.capability ?? null,
    });
  }
  return hired;
}

function hiredForMission(
  hiredWorkers: HiredWorkerEntry[],
  name: string,
  owner: WorkerOwner,
  missionId: string,
): HiredWorkerEntry | undefined {
  const candidates = hiredWorkers.filter(
    (w) => w.name === name && (w.owner === owner || owner === "unknown")
  );
  return candidates.find((w) => w.mission === missionId) ?? candidates[0];
}

function workerDisplayName(content: string, hired: HiredWorkerEntry | undefined, fallback: string): string {
  const title = content.match(/^\s*title:\s*["']?(.+?)["']?\s*$/m)?.[1]?.trim();
  if (title) return truncateText(title.replace(/\s+—\s+Worker Report$/i, ""), 42);

  const heading = content.match(/^#\s+(.+)$/m)?.[1]?.trim();
  if (heading) return truncateText(heading.replace(/\s+—\s+.*$/i, ""), 42);

  if (hired?.task) {
    const capability = hired.capability ? ` · ${hired.capability}` : "";
    return truncateText(`${hired.task}${capability}`, 42);
  }

  return fallback;
}

function isHarnessRuntimeIdle(progress: RawProgress | null): boolean {
  const status = (progress?.agent_status ?? "").toLowerCase();
  const current = progress?.current_agent ?? null;
  const next = progress?.next_agent ?? null;
  return (
    status === "completed" ||
    status === "complete" ||
    (status === "idle" && current === null && (next === null || String(next) === "none"))
  );
}

function activeWorkerNames(progress: RawProgress | null): Set<string> {
  const active = new Set<string>();
  if (isHarnessRuntimeIdle(progress)) return active;
  const workers = [
    ...normalizeRawWorkers(progress?.company_state?.workers),
    ...normalizeRawWorkers(progress?.company_state?.last_dispatch),
  ];
  for (const worker of workers) {
    const rawStatus = (worker.status ?? worker.spawn_status ?? "").toLowerCase();
    if (["complete", "completed", "done", "idle"].includes(rawStatus)) continue;
    for (const value of [worker.name, worker.agent, worker.feature, worker.report, worker.report_path, worker.log]) {
      const normalized = normalizeWorkerName(value && /[\\/]/.test(value) ? path.basename(value) : value);
      if (normalized) active.add(normalized);
    }
  }
  return active;
}

function buildRuntime(progress: RawProgress | null): RuntimeSnapshot {
  const ownerPrompt = progress?.owner_prompt
    ? {
        command: progress.owner_prompt.command ?? "input",
        summary: progress.owner_prompt.summary ?? "",
        receivedAt: progress.owner_prompt.received_at ?? null,
        status: progress.owner_prompt.status ?? "unknown",
      }
    : null;
  return {
    currentAgent: progress?.current_agent ?? null,
    agentStatus: progress?.agent_status ?? "unknown",
    nextAgent: progress?.next_agent ?? null,
    updatedAt: progress?.updated_at ?? null,
    conductorState: progress?.conductor?.state ?? null,
    currentAction: progress?.conductor?.current_action ?? null,
    companyState: progress?.company_state?.state ?? null,
    activeWorkers: progress?.company_state?.active_workers ?? 0,
    lastDispatchAt: progress?.company_state?.last_dispatch_at ?? null,
    ownerPrompt,
  };
}

function readMissions(rootDir: string, progress: RawProgress | null = null, limit = 15): MissionDoc[] {
  const docsDir = path.join(rootDir, ".harness", "documents");
  if (!existsSync(docsDir)) return [];
  const hiredWorkers = readHiredWorkers(rootDir);
  const activeWorkers = activeWorkerNames(progress);
  const runtimeIdle = isHarnessRuntimeIdle(progress);

  const missionDirs: Array<{ rel: string; abs: string }> = [];
  const cxxDocNames = new Set(["ceo.md", "cto.md", "cqo.md", "coo.md", "cdo.md", "ops.md"]);

  const collectMissionDirs = (baseDir: string, relPrefix = "") => {
    let entries: Dirent[];
    try {
      entries = readdirSync(baseDir, { withFileTypes: true });
    } catch { return; }

    const hasMissionDoc = entries.some((entry) => entry.isFile() && cxxDocNames.has(entry.name));
    if (hasMissionDoc && relPrefix) {
      missionDirs.push({ rel: relPrefix, abs: baseDir });
    }

    for (const entry of entries) {
      if (!entry.isDirectory() || entry.name.startsWith(".")) continue;
      if (["workers", "coo", "cdo", "cto", "cqo", "ops"].includes(entry.name)) continue;
      const childRel = relPrefix ? `${relPrefix}/${entry.name}` : entry.name;
      collectMissionDirs(path.join(baseDir, entry.name), childRel);
    }
  };

  collectMissionDirs(docsDir);

  const typeFromId = (id: string): MissionDoc["type"] => {
    const base = id.split("/").pop() ?? id;
    if (/^goal[-_]/i.test(base)) return "goal";
    if (/^submission[-_]/i.test(base)) return "submission";
    if (/^hot[-_]?fix[-_]/i.test(base) || /^hotfix[-_]/i.test(base)) return "hotfix";
    if (/^F\d+/i.test(base)) return "feature";
    return "unknown";
  };

  let missions = missionDirs
    .map(({ rel, abs: missionPath }) => {
      let mtime: Date;
      try { mtime = statSync(missionPath).mtime; } catch { mtime = new Date(0); }

      const readMd = (name: string): string | null => {
        const p = path.join(missionPath, name);
        if (!existsSync(p)) return null;
        try { return readFileSync(p, "utf8"); } catch { return null; }
      };

      const workers: WorkerDocEntry[] = [];
      const workersByKey = new Map<string, WorkerDocEntry>();
      const addWorkersFromDir = (owner: WorkerOwner, relDir: string) => {
        const workersDir = path.join(missionPath, relDir);
        if (!existsSync(workersDir)) return;
        try {
          for (const f of readdirSync(workersDir)) {
            if (!f.endsWith(".md")) continue;
            const reportAbs = path.join(missionPath, relDir, f);
            const content = readMd(`${relDir}/${f}`) ?? "";
            const name = normalizeWorkerName(f);
            const hired = hiredForMission(hiredWorkers, name, owner, rel);
            let updatedAt: string | null = null;
            try {
              const mtime = statSync(reportAbs).mtime;
              updatedAt = mtime.toISOString();
            } catch { /* ignore */ }
            const statusMatch = content.match(/##\s*Status\s*\n+([A-Z_]+)/);
            // Runtime state is the source of truth for live activity. A
            // recently touched docmeta-only draft is not enough to prove that a
            // detached worker session is still running, nor that it has
            // completed — leave it "unknown" unless the doc has an explicit
            // ## Status section.
            const status: WorkerDocEntry["status"] = statusMatch
              ? (statusMatch[1] as WorkerDocEntry["status"])
              : "unknown";
            const entry: WorkerDocEntry = {
              name,
              displayName: workerDisplayName(content, hired, name),
              content,
              status,
              owner: hired?.owner ?? owner,
              hired: !!hired,
              active: !runtimeIdle && (activeWorkers.has(name) || status === "IN_PROGRESS"),
              sourcePath: hired?.sourcePath ?? null,
              reportPath: path.relative(rootDir, reportAbs),
              updatedAt,
            };
            workersByKey.set(`${entry.owner}:${entry.name}`, entry);
          }
        } catch { /* ignore */ }
      };

      addWorkersFromDir("cto", "cto/workers");
      addWorkersFromDir("cqo", "cqo/workers");
      addWorkersFromDir("coo", "coo/workers");
      addWorkersFromDir("cdo", "cdo/workers");
      addWorkersFromDir("ops", "ops/workers");
      addWorkersFromDir("unknown", "workers");

      for (const hired of hiredWorkers) {
        const key = `${hired.owner}:${hired.name}`;
        if (workersByKey.has(key)) continue;
        workersByKey.set(key, {
          name: hired.name,
          displayName: workerDisplayName("", hired, hired.name),
          content: "",
          status: !runtimeIdle && activeWorkers.has(hired.name) ? "IN_PROGRESS" : "unknown",
          owner: hired.owner,
          hired: true,
          active: !runtimeIdle && activeWorkers.has(hired.name),
          sourcePath: hired.sourcePath,
          reportPath: null,
          updatedAt: null,
        });
      }

      workers.push(...workersByKey.values());

      const cxxRoles = ["ceo", "cto", "cqo", "coo", "cdo", "ops"] as const;
      const cxxPresent = cxxRoles.filter(role => existsSync(path.join(missionPath, `${role}.md`)));
      const state = readMissionState(missionPath);
      const protocolViolations: string[] = [];
      for (const role of cxxPresent) {
        if (role === "ceo") continue;
        const roleWorkers = workers.filter((w) => w.owner === role && w.reportPath);
        const roleDoc = readMd(`${role}.md`) ?? "";
        const hasManifest = /Worker Evidence Manifest/i.test(roleDoc);
        const mentionsWorkerReport = new RegExp(`${role}/workers/`, "i").test(roleDoc);
        if (roleWorkers.length === 0 || !hasManifest || !mentionsWorkerReport) {
          protocolViolations.push(`${role}:missing-worker-evidence`);
        }
      }
      for (const w of workers) {
        if (w.owner === "unknown" || !w.hired) {
          protocolViolations.push(`${w.owner}:${w.name}:not-hired-or-unowned`);
        }
      }

      // Perpetual (operating) goals carry an agenda.json the CXX co-write.
      const agenda = readJsonSafe<{
        items?: Array<{ status?: string }>;
        cycles?: number;
      }>(path.join(missionPath, "agenda.json"));
      const agendaOpen = agenda.ok
        ? (agenda.value.items ?? []).filter((it) => (it.status ?? "") !== "done").length
        : undefined;
      const operatingCycles = agenda.ok ? agenda.value.cycles ?? undefined : undefined;

      const id = rel;
      const label = rel.split("/").pop() ?? rel;
      return {
        missionId: id,
        ts: mtime.toISOString(),
        type: typeFromId(id),
        lifecycle: state.lifecycle,
        active: state.active ?? false,
        protocolViolations,
        label,
        ceo: readMd("ceo.md"),
        cto: readMd("cto.md"),
        cqo: readMd("cqo.md"),
        coo: readMd("coo.md"),
        cdo: readMd("cdo.md"),
        cdoPreview: readMd("cdo/preview.html"),
        ops: readMd("ops.md"),
        workers,
        cxxPresent: [...cxxPresent],
        agendaOpen,
        operatingCycles,
      } satisfies MissionDoc;
    })
    .sort((a, b) => new Date(b.ts).getTime() - new Date(a.ts).getTime());

  const explicitActive = missions.some((m) => m.active);
  if (!explicitActive) {
    const latestOpen = missions.find(
      (m) => m.lifecycle === "active" || m.lifecycle === "unknown"
    );
    if (latestOpen) {
      missions = missions.map((m) => ({
        ...m,
        active: m.missionId === latestOpen.missionId,
      }));
    }
  }

  const activePinned = missions.filter((m) => m.active);
  const limited = missions.slice(0, limit);
  if (activePinned.length) {
    const seen = new Set(limited.map((m) => m.missionId));
    for (const mission of activePinned) {
      if (!seen.has(mission.missionId)) limited.push(mission);
    }
    missions = limited;
  } else {
    missions = limited;
  }

  // When the CEO updates a goal directory in-place for a submission or hot-fix
  // (instead of creating a submission-* or hotfix-* subdirectory), the most
  // recently modified mission still has type "goal" from its directory name.
  // Override it using owner_prompt.command so the display reflects the actual
  // command the Owner issued, not just the directory prefix.
  const cmd = progress?.owner_prompt?.command;
  if (missions.length > 0 && (cmd === "submission" || cmd === "hot-fix")) {
    const top = missions[0];
    const ownerPromptReceivedAt = progress?.owner_prompt?.received_at
      ? new Date(progress.owner_prompt.received_at).getTime()
      : null;
    const missionUpdatedAt = new Date(top.ts).getTime();
    const missionUpdatedAfterPrompt =
      ownerPromptReceivedAt === null ||
      Number.isNaN(ownerPromptReceivedAt) ||
      missionUpdatedAt >= ownerPromptReceivedAt;
    if (top.type === "goal" && missionUpdatedAfterPrompt) {
      missions[0] = { ...top, type: cmd === "hot-fix" ? "hotfix" : "submission" };
    }
  }

  return missions;
}

function readOwnerHistory(rootDir: string, limit = 30): OwnerPromptEntry[] {
  const logFile = path.join(rootDir, ".harness", "progress.log");
  if (!existsSync(logFile)) return [];
  let raw: string;
  try { raw = readFileSync(logFile, "utf8"); } catch { return []; }

  const entries: OwnerPromptEntry[] = [];
  for (const line of raw.split("\n")) {
    if (!line.includes("user-prompt") && !line.includes("input")) continue;
    if (line.trim().startsWith("#")) continue;
    const parts = line.split(" | ");
    if (parts.length < 4) continue;
    const ts = parts[0]?.trim() ?? "";
    const eventType = parts[2]?.trim() ?? "input";
    const content = parts.slice(3).join(" | ").trim();
    if (!content) continue;
    const lc = content.toLowerCase();
    const type =
      eventType === "goal" || content.startsWith("/goal") ? "goal" :
      eventType === "submission" || content.startsWith("/submission") || lc.includes("/submission") ? "submission" :
      eventType === "hot-fix" || content.startsWith("/hot-fix") || lc.includes("/hot-fix") ? "hot-fix" :
      "other";
    entries.push({ ts, content, type });
  }
  return entries.reverse().slice(0, limit);
}

function readKnowledgeDir<T extends GotchaEntry | ConventionEntry>(
  rootDir: string,
  relDir: string
): T[] {
  const dir = path.join(rootDir, ".harness", relDir);
  if (!existsSync(dir)) return [];
  let entries: Dirent[];
  try { entries = readdirSync(dir, { withFileTypes: true }); } catch { return []; }
  const results: T[] = [];
  for (const entry of entries) {
    if (!entry.isFile() || !entry.name.endsWith(".md")) continue;
    if (entry.name === "README.md") continue;
    const id = entry.name.replace(/\.md$/, "");
    const abs = path.join(dir, entry.name);
    let content: string;
    try { content = readFileSync(abs, "utf8"); } catch { continue; }
    const body = content.replace(/^---[\s\S]*?---\n+/, "");
    const h1 = body.match(/^#\s+(.+)/m);
    const title = h1 ? h1[1].trim() : id;
    const tagsMatch = content.match(/^\s*tags:\s*\[([^\]]*)\]/m);
    const tags = tagsMatch
      ? tagsMatch[1].split(",").map((t) => t.trim().replace(/^['"]|['"]$/g, "")).filter(Boolean)
      : [];
    let updatedAt: string | null = null;
    try { updatedAt = statSync(abs).mtime.toISOString(); } catch { /* ignore */ }
    results.push({
      id,
      title,
      content,
      tags,
      sourcePath: path.relative(rootDir, abs),
      updatedAt,
    } as T);
  }
  return results.sort((a, b) => a.id.localeCompare(b.id));
}

function readGotchas(rootDir: string): GotchaEntry[] {
  return readKnowledgeDir<GotchaEntry>(rootDir, "gotchas");
}

function readConventions(rootDir: string): ConventionEntry[] {
  return readKnowledgeDir<ConventionEntry>(rootDir, "conventions");
}

function normalizeTodoStatus(raw: unknown): CxxTodo["status"] {
  const value = String(raw ?? "pending").toLowerCase();
  if (["pending", "active", "paused", "blocked", "done"].includes(value)) return value;
  return value;
}

function readTodos(rootDir: string): CxxTodo[] {
  const todoPath = path.join(rootDir, ".harness", "todos", "state.json");
  const result = readJsonSafe<{
    owners?: Record<string, Array<{
      id?: string;
      owner?: string;
      title?: string;
      status?: string;
      priority?: number;
      kind?: string;
      mission_path?: string | null;
      missionPath?: string | null;
      required_artifacts?: string[];
      requiredArtifacts?: string[];
      created_at?: string | null;
      createdAt?: string | null;
      updated_at?: string | null;
      updatedAt?: string | null;
      last_heartbeat_at?: string | null;
      lastHeartbeatAt?: string | null;
      blocked_reason?: string | null;
      blockedReason?: string | null;
    }>>;
  }>(todoPath);
  if (!result.ok) return [];
  const todos: CxxTodo[] = [];
  for (const [owner, list] of Object.entries(result.value.owners ?? {})) {
    for (const item of list ?? []) {
      const id = item.id ?? `${owner}-${todos.length + 1}`;
      todos.push({
        id,
        owner: item.owner ?? owner,
        title: item.title ?? id,
        status: normalizeTodoStatus(item.status),
        priority: item.priority ?? 0,
        kind: item.kind ?? "task",
        missionPath: item.mission_path ?? item.missionPath ?? null,
        requiredArtifacts: item.required_artifacts ?? item.requiredArtifacts ?? [],
        createdAt: item.created_at ?? item.createdAt ?? null,
        updatedAt: item.updated_at ?? item.updatedAt ?? null,
        lastHeartbeatAt: item.last_heartbeat_at ?? item.lastHeartbeatAt ?? null,
        blockedReason: item.blocked_reason ?? item.blockedReason ?? null,
      });
    }
  }
  return todos.sort((a, b) => (b.priority - a.priority) || ((b.updatedAt ?? "").localeCompare(a.updatedAt ?? "")));
}

function readJsonlTail<T extends Record<string, unknown>>(filePath: string, limit: number): T[] {
  if (!existsSync(filePath)) return [];
  let raw = "";
  try { raw = readFileSync(filePath, "utf8"); } catch { return []; }
  const rows: T[] = [];
  for (const line of raw.split("\n")) {
    const trimmed = line.trim();
    if (!trimmed) continue;
    try {
      rows.push(JSON.parse(trimmed) as T);
    } catch {
      // Ignore malformed legacy/manual lines in append-only logs.
    }
  }
  return rows.slice(-limit).reverse();
}

function readEvents(rootDir: string, limit = 40): HarnessEvent[] {
  return readJsonlTail<Record<string, unknown>>(path.join(rootDir, ".harness", "events.jsonl"), limit).map((e) => ({
    ts: typeof e.ts === "string" ? e.ts : null,
    type: typeof e.type === "string" ? e.type : "event",
    owner: typeof e.owner === "string" ? e.owner : null,
    command: typeof e.command === "string" ? e.command : null,
    summary: typeof e.summary === "string" ? e.summary : null,
    title: typeof e.title === "string" ? e.title : null,
    status: typeof e.status === "string" ? e.status : null,
  }));
}

function readActivitySamples(rootDir: string): ActivitySample[] {
  const activityDir = path.join(rootDir, ".harness", "activity");
  if (!existsSync(activityDir)) return [];
  const cutoff = Date.now() - ACTIVITY_RETENTION_MS;
  const files = readdirSync(activityDir)
    .filter((name) => /^\d{4}-\d{2}-\d{2}\.jsonl$/.test(name))
    .sort()
    .slice(-8);
  const rows: ActivitySample[] = [];
  for (const file of files) {
    for (const raw of readJsonlTail<Record<string, unknown>>(path.join(activityDir, file), 100_000).reverse()) {
      const ts = typeof raw.ts === "string" ? raw.ts : null;
      const time = ts ? Date.parse(ts) : NaN;
      if (!ts || !Number.isFinite(time) || time < cutoff) continue;
      const laneId = typeof raw.laneId === "string" ? raw.laneId : null;
      if (!laneId) continue;
      const count = Math.max(0, Math.min(2, Number(raw.count ?? 0)));
      if (count <= 0) continue;
      rows.push({
        ts,
        laneId,
        count,
        hotfix: raw.hotfix === true,
        missionId: typeof raw.missionId === "string" ? raw.missionId : null,
      });
    }
  }
  return rows.sort((a, b) => Date.parse(a.ts) - Date.parse(b.ts));
}

function fileCategory(relPath: string): HarnessFileEntry["category"] {
  if (relPath.startsWith(".harness/documents/")) return "documents";
  if (relPath.startsWith(".harness/todos/")) return "todos";
  if (relPath.startsWith(".harness/activity/")) return "activity";
  if (relPath.startsWith(".harness/gotchas/") || relPath.startsWith(".harness/conventions/")) return "knowledge";
  if (relPath.startsWith(".harness/runtime/")) return "runtime";
  if (relPath === ".harness/progress.json" || relPath === ".harness/config.json") return "config";
  return "other";
}

function shouldSkipHarnessDir(relPath: string): boolean {
  return (
    relPath === ".harness/dashboard" ||
    relPath.startsWith(".harness/dashboard/") ||
    relPath === ".harness/shared/HR-Resource" ||
    relPath.startsWith(".harness/shared/HR-Resource/")
  );
}

function readHarnessFiles(rootDir: string, limit = 180): HarnessFileEntry[] {
  const harnessDir = path.join(rootDir, ".harness");
  if (!existsSync(harnessDir)) return [];

  const entries: HarnessFileEntry[] = [];
  const visit = (absDir: string, relDir: string, depth: number) => {
    if (entries.length >= limit || depth > 5 || shouldSkipHarnessDir(relDir)) return;
    let dirents: Dirent[];
    try {
      dirents = readdirSync(absDir, { withFileTypes: true });
    } catch {
      return;
    }
    dirents.sort((a, b) => {
      if (a.isDirectory() !== b.isDirectory()) return a.isDirectory() ? -1 : 1;
      return a.name.localeCompare(b.name);
    });
    for (const entry of dirents) {
      if (entries.length >= limit || entry.name === ".DS_Store") break;
      const abs = path.join(absDir, entry.name);
      const rel = `${relDir}/${entry.name}`;
      if (shouldSkipHarnessDir(rel)) continue;
      let stat = null as ReturnType<typeof statSync> | null;
      try {
        stat = statSync(abs);
      } catch {
        continue;
      }
      entries.push({
        path: rel,
        name: entry.name,
        kind: entry.isDirectory() ? "dir" : "file",
        depth,
        size: entry.isDirectory() ? null : stat.size,
        updatedAt: stat.mtime.toISOString(),
        category: fileCategory(rel),
      });
      if (entry.isDirectory()) visit(abs, rel, depth + 1);
    }
  };

  entries.push({
    path: ".harness",
    name: ".harness",
    kind: "dir",
    depth: 0,
    size: null,
    updatedAt: null,
    category: "runtime",
  });
  visit(harnessDir, ".harness", 1);

  return entries;
}

export function readHarnessState(rootDir: string): HarnessSnapshot {
  const harnessDir = path.join(rootDir, ".harness");
  if (!existsSync(harnessDir)) {
    return emptySnapshot({
      level: "error",
      message_ko: "하네스 상태가 없습니다 — Dispatcher를 먼저 실행하세요.",
      message_en: "Harness state not found — run Dispatcher first.",
    }, rootDir);
  }
  const progressPath = path.join(harnessDir, "progress.json");
  const result = readJsonSafe<RawProgress>(progressPath);
  if (!result.ok) {
    const banner: ErrorBanner =
      result.reason === "missing"
        ? {
            level: "error",
            message_ko: "progress.json을 찾을 수 없습니다 — Dispatcher를 먼저 실행하세요.",
            message_en: "progress.json not found — run Dispatcher first.",
          }
        : {
            level: "error",
            message_ko: "progress.json이 손상되었습니다 — 파일을 확인하세요.",
            message_en: "progress.json is corrupt — check the file.",
          };
    const snapshot = emptySnapshot(banner, rootDir);
    snapshot.missions = readMissions(rootDir, null);
    snapshot.ownerHistory = readOwnerHistory(rootDir);
    snapshot.gotchas = readGotchas(rootDir);
    snapshot.conventions = readConventions(rootDir);
    snapshot.todos = readTodos(rootDir);
    snapshot.events = readEvents(rootDir);
    snapshot.activitySamples = readActivitySamples(rootDir);
    snapshot.files = readHarnessFiles(rootDir);
    return snapshot;
  }

  const progress = result.value;
  const incidents = buildIncidents(progress);

  return {
    version: SNAPSHOT_VERSION,
    ts: new Date().toISOString(),
    projectName: path.basename(rootDir),
    projectPath: rootDir,
    errorBanner: null,
    runtime: buildRuntime(progress),
    incidents,
    missions: readMissions(rootDir, progress),
    ownerHistory: readOwnerHistory(rootDir),
    gotchas: readGotchas(rootDir),
    conventions: readConventions(rootDir),
    todos: readTodos(rootDir),
    events: readEvents(rootDir),
    activitySamples: readActivitySamples(rootDir),
    files: readHarnessFiles(rootDir),
  };
}
