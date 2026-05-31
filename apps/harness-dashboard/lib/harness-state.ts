import { existsSync, readdirSync, statSync, readFileSync, type Dirent } from "node:fs";
import path from "node:path";
import { readJsonSafe } from "./safe-json";
import { AGENT_ROSTER, ROOM_LABELS } from "./agent-roster";
import { deriveMinifigState, pickTalkingPreview } from "./state-mapping";
import type {
  AgentId,
  AgentState,
  ArchiveEntry,
  ArchiveStat,
  ContractSnapshot,
  CurrentMeeting,
  Dept,
  ErrorBanner,
  EnvFileSummary,
  EscalationEntry,
  EvalScores,
  FeatureSummary,
  GoalCard,
  HarnessSnapshot,
  HarnessEvent,
  HypothesisEntry,
  IncidentEntry,
  MeetingCadence,
  MeetingRecord,
  MeetingsState,
  GotchaEntry,
  ConventionEntry,
  MissionDoc,
  OperationsDashboard,
  OpsServiceHealth,
  OwnerPromptEntry,
  ParallelTrack,
  Pipeline,
  RoomId,
  RoomMetrics,
  RoomState,
  RuntimeSnapshot,
  TrackStatus,
  WorkerDocEntry,
  WorkerSnapshot,
  CxxTodo,
  ActivitySample,
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

function emptyContract(): ContractSnapshot {
  return {
    sprint_number: null,
    pipeline: null,
    api_version: null,
    feature_total: 0,
    feature_passed: 0,
    feature_failed: 0,
    contract_signed: { be: false, fe: false },
  };
}

function emptySnapshot(banner: ErrorBanner | null = null, rootDir?: string): HarnessSnapshot {
  const agents: AgentState[] = AGENT_ROSTER.map((entry) => ({
    id: entry.id,
    name: entry.name,
    dept: entry.dept,
    room: entry.room,
    homeRoom: entry.room,
    minifigState: "idle",
    lastActivity: null,
  }));
  const rooms: RoomState[] = (Object.keys(ROOM_LABELS) as RoomId[]).map((id) => ({
    id,
    label_ko: ROOM_LABELS[id].ko,
    label_en: ROOM_LABELS[id].en,
    dept: ROOM_LABELS[id].dept,
  }));
  return {
    version: SNAPSHOT_VERSION,
    ts: new Date().toISOString(),
    projectName: rootDir ? path.basename(rootDir) : "(unknown)",
    projectPath: rootDir ?? "",
    agents,
    rooms,
    goal: null,
    archive: { sprintCount: 0, recent: [], all: [] },
    meetings: { active: [], cadence: "normal", next_scheduled: null, current: null },
    tracks: [],
    incidents: [],
    hypothesis: [],
    escalations: [],
    contract: emptyContract(),
    evalScores: null,
    errorBanner: banner,
    dashboard: { workers: [], features: [], recentMeetings: [], opsHealth: [], envFiles: [] },
    runtime: {
      currentAgent: null,
      agentStatus: "unknown",
      nextAgent: null,
      updatedAt: null,
      ownerPrompt: null,
    },
    missions: [],
    ownerHistory: [],
    gotchas: [],
    conventions: [],
    todos: [],
    events: [],
    activitySamples: [],
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

function titleFromMarkdown(text: string | null): string | null {
  if (!text) return null;
  const h1 = text.match(/^#\s+(.+)$/m)?.[1]?.trim();
  if (h1) return h1;
  const mission = text.match(/(?:mission|goal|title)\s*[:=]\s*(.+)$/im)?.[1]?.trim();
  return mission || null;
}

function buildGoal(rootDir: string, progress: RawProgress | null): GoalCard | null {
  const list = progress?.goals?.list ?? [];
  const activeId = progress?.goals?.active_id;
  const goalFile = readTextSafe(path.join(rootDir, ".harness", "actions", "goals.md"));
  const mission = (progress?.goals as { mission?: string; title?: string; description?: string } | undefined)?.mission;
  const topLevelTitle = (progress?.goals as { title?: string } | undefined)?.title;
  if (!activeId && !mission && !topLevelTitle && !goalFile) return null;
  if (!activeId) {
    const title = mission ?? topLevelTitle ?? titleFromMarkdown(goalFile) ?? "Active autonomous company goal";
    return {
      id: "goal",
      title,
      description_truncated: truncateText(
        (progress?.goals as { description?: string } | undefined)?.description ?? goalFile ?? "",
        GOAL_DESC_TRUNCATE,
      ),
      adherence: progress?.goals?.current_adherence ?? null,
    };
  }
  const found = list.find((g) => g.id === activeId);
  if (!found) {
    const title = mission ?? topLevelTitle ?? titleFromMarkdown(goalFile) ?? activeId;
    return {
      id: activeId,
      title,
      description_truncated: truncateText(
        (progress?.goals as { description?: string } | undefined)?.description ?? goalFile ?? "",
        GOAL_DESC_TRUNCATE,
      ),
      adherence: progress?.goals?.current_adherence ?? null,
    };
  }
  const desc = found.description ?? "";
  const truncated =
    desc.length > GOAL_DESC_TRUNCATE
      ? desc.slice(0, GOAL_DESC_TRUNCATE) + "…"
      : desc;
  return {
    id: found.id,
    title: found.title ?? found.id,
    description_truncated: truncated,
    adherence: progress?.goals?.current_adherence ?? null,
  };
}

function readArchiveVerdict(sprintDir: string): "PASS" | "FAIL" | "unknown" {
  // Sprint verdict can live in a handful of well-known spots. Try them in
  // order; first hit wins. Returns "unknown" if nothing definitive is found.
  const verdictJson = path.join(sprintDir, "verdict.json");
  if (existsSync(verdictJson)) {
    const r = readJsonSafe<{ result?: string; verdict?: string }>(verdictJson);
    if (r.ok) {
      const v = (r.value.result ?? r.value.verdict ?? "").toUpperCase();
      if (v === "PASS" || v === "FAIL") return v;
    }
  }
  // CQO sprint summary is the canonical source if verdict.json is absent.
  try {
    const candidates = readdirSync(sprintDir).filter(
      (n) => n.startsWith("cqo-audit-") || n === "evaluation-summary.md"
    );
    for (const name of candidates) {
      const text = readFileSync(path.join(sprintDir, name), "utf-8");
      if (/sprint[_\s-]*verdict\s*[:=]\s*PASS/i.test(text)) return "PASS";
      if (/sprint[_\s-]*verdict\s*[:=]\s*FAIL/i.test(text)) return "FAIL";
    }
  } catch {
    // ignore
  }
  return "unknown";
}

function buildArchive(harnessRoot: string): ArchiveStat {
  const archiveDir = path.join(harnessRoot, ".harness", "archive");
  if (!existsSync(archiveDir)) {
    return { sprintCount: 0, recent: [], all: [] };
  }
  let entries: string[] = [];
  try {
    entries = readdirSync(archiveDir).filter((name) => name.startsWith("sprint-"));
  } catch {
    return { sprintCount: 0, recent: [], all: [] };
  }
  const all: ArchiveEntry[] = entries.map((name) => {
    const sprintDir = path.join(archiveDir, name);
    let ts: string | null = null;
    try {
      ts = statSync(sprintDir).mtime.toISOString();
    } catch {
      ts = null;
    }
    const result = readArchiveVerdict(sprintDir);
    return { dir: name, label: name, result, ts };
  });
  all.sort((a, b) => (b.ts ?? "").localeCompare(a.ts ?? ""));
  return { sprintCount: all.length, recent: all.slice(0, 3), all };
}

function passAxis(pass: unknown): string | null {
  if (typeof pass === "string") return pass;
  if (pass && typeof pass === "object") {
    const p = pass as { axis?: string; by?: string; status?: string };
    if (p.status && p.status.toUpperCase() !== "PASS") return null;
    return p.axis ?? p.by ?? null;
  }
  return null;
}

function buildFeatureSummaries(rootDir: string): FeatureSummary[] {
  const featurePath = path.join(rootDir, ".harness", "actions", "feature-list.json");
  const queuePath = path.join(rootDir, ".harness", "actions", "feature-queue.json");
  const featureResult = readJsonSafe<{
    features?: Array<{
      id?: string;
      title?: string;
      name?: string;
      description?: string;
      status?: string;
      passes?: unknown[];
    }>;
  }>(featurePath);
  const queueResult = readJsonSafe<{
    queue?: {
      ready?: string[];
      blocked?: Record<string, unknown>;
      in_progress?: Record<string, unknown>;
      passed?: string[];
      failed?: string[];
    };
  }>(queuePath);
  const queue = queueResult.ok ? queueResult.value.queue : undefined;
  const statusById = new Map<string, FeatureSummary["status"]>();
  for (const id of queue?.ready ?? []) statusById.set(id, "ready");
  for (const id of Object.keys(queue?.blocked ?? {})) statusById.set(id, "blocked");
  for (const id of Object.keys(queue?.in_progress ?? {})) statusById.set(id, "in_progress");
  for (const id of queue?.passed ?? []) statusById.set(id, "passed");
  for (const id of queue?.failed ?? []) statusById.set(id, "failed");

  if (!featureResult.ok) {
    return [...statusById.entries()].map(([id, status]) => ({
      id,
      title: id,
      status,
      passes: [],
    }));
  }
  return (featureResult.value.features ?? [])
    .filter((f) => !!f.id)
    .map((f) => {
      const passes = (f.passes ?? []).map(passAxis).filter((x): x is string => !!x);
      const explicitStatus = (f.status ?? "").toLowerCase();
      const status =
        explicitStatus === "pass" || explicitStatus === "passed" || explicitStatus === "done"
          ? "passed"
          : explicitStatus === "fail" || explicitStatus === "failed"
          ? "failed"
          : statusById.get(f.id!) ?? (passes.length > 0 ? "passed" : "unknown");
      return {
        id: f.id!,
        title: f.title ?? f.name ?? f.description ?? f.id!,
        status,
        passes,
      };
    });
}

function buildContract(rootDir: string, progress: RawProgress | null, features: FeatureSummary[]): ContractSnapshot {
  const total = progress?.contracts?.feature_list?.total ?? features.length;
  const passed =
    progress?.contracts?.feature_list?.passed ??
    features.filter((f) => f.status === "passed" || f.passes.length > 0).length;
  const failed =
    progress?.contracts?.feature_list?.failed ??
    features.filter((f) => f.status === "failed").length;
  return {
    sprint_number: progress?.sprint?.number ?? null,
    pipeline: (progress?.pipeline ?? null) as Pipeline,
    api_version: progress?.contracts?.api?.version ?? null,
    feature_total: total,
    feature_passed: passed,
    feature_failed: failed,
    contract_signed: {
      be: !!progress?.cto?.contract_signed?.be,
      fe: !!progress?.cto?.contract_signed?.fe,
    },
  };
}

// Map a conductor-track owner (real-harness schema) to a dashboard room.
// Owners are agent IDs / dept names; we collapse them to the room their
// minifig sits in.
function ownerToRoom(owner: string | undefined): RoomId {
  if (!owner) return "cto-team";
  const o = owner.toLowerCase();
  if (o === "planner" || o === "coo" || o.includes("documentation")) return "coo";
  if (o === "cto" || o.startsWith("generator-") || o === "conductor") return "cto-team";
  if (o === "cqo" || o.startsWith("evaluator-")) return "cqo-team";
  if (o === "service-ops" || o === "ops") return "service-ops";
  if (o === "meeting-manager") return "meeting";
  if (o === "dispatcher" || o === "ceo") return "ceo";
  return "cto-team";
}

function ownerToDept(owner: string | undefined): ParallelTrack["to_dept"] {
  if (!owner) return "Multi";
  const o = owner.toLowerCase();
  if (o === "planner" || o === "coo") return "Planner";
  if (o === "cto" || o.startsWith("generator-")) return "CTO";
  if (o === "cqo" || o.startsWith("evaluator-")) return "CQO";
  if (o === "service-ops" || o === "ops") return "Operations";
  if (o === "meeting-manager") return "Meeting";
  if (o === "dispatcher" || o === "ceo") return "CEO";
  return "Multi";
}

// Real-harness track status values use a different vocabulary. Normalize so
// the visualization and tests stay on the same enum.
function normalizeTrackStatus(raw: string | undefined): TrackStatus {
  const allowed: TrackStatus[] = ["dispatched", "in_progress", "joined", "blocked"];
  if (raw && allowed.includes(raw as TrackStatus)) return raw as TrackStatus;
  switch ((raw ?? "").toLowerCase()) {
    case "running":
    case "active":
      return "in_progress";
    case "completed":
    case "done":
    case "succeeded":
      return "joined";
    case "blocked":
    case "failed":
    case "error":
      return "blocked";
    case "pending":
    case "queued":
    case "scheduled":
    default:
      return "dispatched";
  }
}

function buildTracks(progress: RawProgress | null): ParallelTrack[] {
  // Prefer the explicit dashboard schema if the harness opts in; otherwise
  // fall back to the real-harness `conductor.tracks[]` shape.
  const explicit = progress?.parallel_tracks;
  if (explicit && explicit.length > 0) {
    return explicit.map((t) => ({
      id: t.id,
      from_meeting: t.from_meeting ?? "meeting",
      to_dept: (t.to_dept ?? "Multi") as ParallelTrack["to_dept"],
      to_room: t.to_room ?? "cto-team",
      status: normalizeTrackStatus(t.status as string | undefined),
      label: t.label,
    }));
  }
  const conductorTracks = progress?.conductor?.tracks ?? [];
  return conductorTracks.map((t) => ({
    id: t.id,
    from_meeting: progress?.conductor?.fork_meeting_id ?? "meeting",
    to_dept: ownerToDept(t.owner),
    to_room: ownerToRoom(t.owner),
    status: normalizeTrackStatus(t.status),
    label: t.action_type ?? t.deliverable,
  }));
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

function buildHypothesis(progress: RawProgress | null): HypothesisEntry[] {
  const list = progress?.hypothesis?.active ?? [];
  return list.map((h) => {
    const v = (h.verdict ?? "pending").toLowerCase();
    const verdict =
      v === "valid" || v === "invalid" ? (v as HypothesisEntry["verdict"]) : "pending";
    return {
      id: h.id,
      brief: h.brief ?? h.id,
      verdict,
      ts: h.ts ?? null,
    };
  });
}

function buildEscalations(progress: RawProgress | null): EscalationEntry[] {
  return (progress?.escalations?.open ?? []).map((e) => ({
    id: e.id,
    reason: e.reason ?? "other",
    message: e.message,
    ts: e.ts ?? null,
  }));
}

function buildCurrentMeeting(progress: RawProgress | null): CurrentMeeting | null {
  const m = progress?.meetings;
  if (!m) return null;
  // Prefer explicit `current` (dashboard schema), then real-harness
  // `requested_type` (currently being convened), then `last_type` (most-recent).
  const rawType =
    (m.current && m.current.type) ||
    m.requested_type ||
    m.last_type ||
    null;
  if (!rawType) return null;
  const allowed: CurrentMeeting["type"][] = [
    "standup",
    "sprint-review",
    "spec-review",
    "incident-war-room",
    "all-hands",
    "followup-review",
  ];
  const type = allowed.includes(rawType as CurrentMeeting["type"])
    ? (rawType as CurrentMeeting["type"])
    : "standup";
  // Topic falls back to the decision summary when the harness hasn't written
  // a free-text topic yet.
  const decisionTopic = m.decision?.owner
    ? `${m.decision.owner}${m.decision.action_type ? ` · ${m.decision.action_type}` : ""}`
    : undefined;
  return {
    type,
    topic: m.current?.topic ?? m.requested_reason ?? m.last_reason ?? decisionTopic,
    convened_at: m.current?.convened_at ?? null,
  };
}

function deriveCadence(raw: string | undefined): MeetingCadence {
  if (raw === "light" || raw === "normal" || raw === "heavy") return raw;
  return "normal";
}

function deptToRoom(dept: string): RoomId | null {
  const map: Record<string, RoomId> = {
    CEO: "ceo",
    Meeting: "meeting",
    Planner: "coo",
    COO: "coo",
    CTO: "cto-team",
    CQO: "cqo-team",
    Operations: "service-ops",
  };
  return map[dept] ?? null;
}

function buildRooms(
  progress: RawProgress | null,
  meetingActive: AgentId[],
  meetings: MeetingsState,
  tracks: ParallelTrack[],
  incidents: IncidentEntry[],
  hypothesisList: HypothesisEntry[],
  contract: ContractSnapshot,
  evalScores: EvalScores | null,
): RoomState[] {
  const cto = progress?.cto;
  const cqo = progress?.cqo;
  const ops = progress?.service_ops;
  const sprintNumber = progress?.sprint?.number;

  const passRate =
    contract.feature_total > 0
      ? contract.feature_passed / contract.feature_total
      : null;

  const tracksByRoom = new Map<RoomId, number>();
  for (const t of tracks) {
    tracksByRoom.set(t.to_room, (tracksByRoom.get(t.to_room) ?? 0) + 1);
  }

  const incidentByDept = new Map<string, number>();
  for (const it of incidents) {
    incidentByDept.set(it.dept, (incidentByDept.get(it.dept) ?? 0) + 1);
  }

  const metrics: Partial<Record<RoomId, RoomMetrics>> = {
    ceo: {
      sprint_number: sprintNumber,
    },
    meeting: {
      cadence: meetings.cadence,
      next_scheduled: meetings.next_scheduled,
      active_tracks: tracks.length,
    },
    coo: {
      sprint_number: sprintNumber,
      active_hypothesis: hypothesisList.length,
    },
    "cto-team": {
      sprint_number: sprintNumber,
      last_review: cto?.last_review ?? null,
      open_arch_risks: cto?.open_arch_risks ?? 0,
      active_workers: progress?.company_state?.active_workers ?? 0,
      contract_signed: {
        be: !!cto?.contract_signed?.be,
        fe: !!cto?.contract_signed?.fe,
      },
      pass_rate: passRate,
    },
    "cqo-team": {
      sprint_number: sprintNumber,
      last_audit: cqo?.last_audit ?? null,
      sprint_verdict: cqo?.sprint_verdict ?? "pending",
      open_regressions: cqo?.open_regressions ?? 0,
      pass_rate: passRate,
      eval_scores: evalScores,
    },
    "service-ops": {
      sprint_number: sprintNumber,
      last_check: ops?.monitor?.last_check ?? null,
      open_alerts: ops?.monitor?.alerts_this_sprint ?? 0,
      open_incidents: incidents.length,
    },
  };

  return (Object.keys(ROOM_LABELS) as RoomId[]).map((id) => {
    const base: RoomState = {
      id,
      label_ko: ROOM_LABELS[id].ko,
      label_en: ROOM_LABELS[id].en,
      dept: ROOM_LABELS[id].dept,
    };
    if (metrics[id]) base.metrics = metrics[id];
    if (id === "meeting") {
      const seats = 7;
      const occupants = meetingActive.slice(0, seats);
      const overflow = Math.max(0, meetingActive.length - seats);
      base.seatLayout = { seats, occupants, overflow };
    }
    return base;
  });
}

function buildAgents(
  progress: RawProgress | null,
  meetingActive: AgentId[],
  incidents: IncidentEntry[],
): AgentState[] {
  const meetingSet = new Set<AgentId>(meetingActive);
  const incidentDepts = new Set(incidents.map((i) => i.dept));
  return AGENT_ROSTER.map((entry) => {
    const minifigState = deriveMinifigState(entry.id, progress ?? null, {
      incidentDepts,
      dept: entry.dept,
    });
    const inMeeting = meetingSet.has(entry.id);
    const room = inMeeting ? "meeting" : entry.room;
    const lastActivity =
      progress?.current_agent === entry.id
        ? `current_agent (${progress.agent_status ?? "unknown"})`
        : progress?.next_agent === entry.id
        ? "next_agent queued"
        : null;
    const matchedIncident = incidents.find((i) => i.dept === entry.dept);
    return {
      id: entry.id,
      name: entry.name,
      dept: entry.dept,
      room,
      homeRoom: entry.room,
      minifigState,
      lastActivity,
      talkingPreview: minifigState === "talking" ? pickTalkingPreview(entry.id) : undefined,
      alertReason:
        minifigState === "red-alert"
          ? matchedIncident?.message ??
            progress?.failure?.message ??
            "incident"
          : undefined,
    };
  });
}

function readFeatureTitles(rootDir: string): Map<string, string> {
  const map = new Map<string, string>();
  const candidates = [
    path.join(rootDir, ".harness", "actions", "feature-list.json"),
    path.join(rootDir, ".harness", "actions", "feature-queue.json"),
  ];
  for (const file of candidates) {
    const result = readJsonSafe<{
      features?: Array<{ id?: string; title?: string; summary?: string }>;
      queue?: {
        ready?: Array<{ id?: string; title?: string; summary?: string }>;
        in_progress?: Array<{ id?: string; title?: string; summary?: string }>;
        passed?: Array<{ id?: string; title?: string; summary?: string }>;
        failed?: Array<{ id?: string; title?: string; summary?: string }>;
      };
    }>(file);
    if (!result.ok) continue;
    for (const f of result.value.features ?? []) {
      if (f.id) map.set(f.id, f.title ?? f.summary ?? f.id);
    }
    const q = result.value.queue;
    for (const list of [q?.ready, q?.in_progress, q?.passed, q?.failed]) {
      if (!Array.isArray(list)) continue;
      for (const f of list) {
        if (f.id) map.set(f.id, f.title ?? f.summary ?? f.id);
      }
    }
  }
  return map;
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

function buildWorkers(rootDir: string, progress: RawProgress | null): WorkerSnapshot[] {
  const titles = readFeatureTitles(rootDir);
  let workers = normalizeRawWorkers(progress?.company_state?.workers);
  if (workers.length === 0) {
    const queue = readJsonSafe<{
      teams?: Record<string, {
        status?: string;
        feature?: string | null;
        pid?: number | null;
        agent?: string;
        phase?: string;
        prompt?: string | null;
        log?: string | null;
        spawn_status?: string;
      }>;
    }>(path.join(rootDir, ".harness", "actions", "feature-queue.json"));
    if (queue.ok) {
      workers = Object.entries(queue.value.teams ?? {})
        .filter(([, t]) => t.status === "busy" && !!t.feature)
        .map(([team, t]) => ({ ...t, team, feature: t.feature ?? undefined }));
    }
  }
  if (workers.length === 0) {
    workers = progress?.company_state?.last_dispatch ?? [];
  }
  return workers.map((w, idx) => {
    const feature = w.feature ?? `worker-${idx + 1}`;
    const promptText = w.prompt ? readTextSafe(path.join(rootDir, w.prompt)) : null;
    const logText = w.log ? readTextSafe(path.join(rootDir, w.log)) : null;
    const eta = w.eta ? ` ETA ${w.eta}` : "";
    const summarySource = firstLine(logText) || firstLine(promptText) || `${w.agent ?? w.name ?? "worker"} ${w.status ?? "assigned"}${eta}`;
    const material = w.prompt ?? w.log ?? null;
    const rawStatus = (w.status ?? w.spawn_status ?? "unknown").toLowerCase();
    const status = ["spawned", "recorded", "running", "idle", "blocked"].includes(rawStatus)
      ? (rawStatus as WorkerSnapshot["status"])
      : "unknown";
    return {
      team: w.team ?? idx + 1,
      feature,
      title: titles.get(feature) ?? feature,
      agent: w.agent ?? "unknown",
      phase: w.phase,
      status,
      pid: w.pid ?? null,
      prompt: w.prompt ?? null,
      log: w.log ?? null,
      progress: deriveWorkerProgress(w),
      summary: truncateText(summarySource, 140),
      next_material: material,
    };
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

function meetingTitleFromMarkdown(text: string, fallback: string): string {
  const heading = text.match(/^#\s+(.+)$/m)?.[1]?.trim();
  return heading || fallback;
}

function meetingVerdict(text: string): string | null {
  const explicit = text.match(/verdict:\s*([^\n]+)/i)?.[1]?.trim();
  if (explicit) return explicit;
  if (/incident/i.test(text)) return "incident";
  if (/PASS|passed|working|continue autonomous/i.test(text)) return "working";
  return null;
}

function buildRecentMeetings(rootDir: string): MeetingRecord[] {
  const meetingsDir = path.join(rootDir, ".harness", "actions", "meetings");
  if (!existsSync(meetingsDir)) return [];
  const records: MeetingRecord[] = [];
  for (const dir of readdirSync(meetingsDir)) {
    const fullDir = path.join(meetingsDir, dir);
    try {
      if (!statSync(fullDir).isDirectory()) continue;
    } catch {
      continue;
    }
    const md = readdirSync(fullDir).find((name) => name.startsWith("meeting-") && name.endsWith(".md"));
    if (!md) continue;
    const fullPath = path.join(fullDir, md);
    const text = readTextSafe(fullPath) ?? "";
    let ts: string | null = null;
    try {
      ts = statSync(fullPath).mtime.toISOString();
    } catch {
      ts = null;
    }
    const summary =
      text.match(/## Decision\s+([\s\S]*?)(?=\n## |\n# |$)/i)?.[1] ??
      text.match(/## Summary\s+([\s\S]*?)(?=\n## |\n# |$)/i)?.[1] ??
      text.split("\n").slice(0, 12).join(" ");
    records.push({
      id: dir,
      path: path.relative(rootDir, fullPath),
      ts,
      title: meetingTitleFromMarkdown(text, dir),
      verdict: meetingVerdict(text),
      summary: truncateText(summary, 220),
      content: text,
    });
  }
  records.sort((a, b) => (b.ts ?? "").localeCompare(a.ts ?? ""));
  return records.slice(0, 6);
}

function buildOpsHealth(progress: RawProgress | null): OpsServiceHealth[] {
  return (progress?.service_ops?.health ?? []).map((h) => {
    const statusRaw = (h.status ?? "unknown").toLowerCase();
    const status = statusRaw === "ok" || statusRaw === "degraded" || statusRaw === "down"
      ? statusRaw
      : "unknown";
    return {
      name: h.name ?? "service",
      host: h.host ?? "127.0.0.1",
      port: h.port ?? 0,
      status,
      port_state: h.port_state ?? null,
      health_status: h.health_status ?? null,
      health_path: h.health_path ?? null,
      recent_errors: h.log?.recent_errors ?? null,
    };
  });
}

function categorizeEnvKey(key: string): EnvFileSummary["keys"][number]["category"] {
  if (/TOKEN|SECRET|KEY|PASSWORD|PASS|COOKIE|JWT/i.test(key)) return "secret";
  if (/URL|HOST|ORIGIN|ENDPOINT/i.test(key)) return "endpoint";
  if (/PORT/i.test(key)) return "port";
  if (/MODE|ENV|NODE_ENV|LIVE|PAPER/i.test(key)) return "mode";
  return "other";
}

function maskEnvValue(value: string, category: EnvFileSummary["keys"][number]["category"]): string {
  if (!value) return "(empty)";
  if (category === "secret") return value.length <= 4 ? "••••" : `${value.slice(0, 2)}••••${value.slice(-2)}`;
  if (value.length <= 18) return value;
  return `${value.slice(0, 10)}…${value.slice(-5)}`;
}

function buildEnvFiles(rootDir: string): EnvFileSummary[] {
  const names = [".env", ".env.local", ".env.production", ".env.development", ".env.example"];
  return names
    .map((name) => {
      const fullPath = path.join(rootDir, name);
      if (!existsSync(fullPath)) return null;
      const text = readTextSafe(fullPath) ?? "";
      const keys = text
        .split("\n")
        .map((line) => line.trim())
        .filter((line) => line && !line.startsWith("#") && line.includes("="))
        .map((line) => {
          const idx = line.indexOf("=");
          const key = line.slice(0, idx).trim();
          const value = line.slice(idx + 1).trim().replace(/^['"]|['"]$/g, "");
          const category = categorizeEnvKey(key);
          return { key, category, masked: maskEnvValue(value, category) };
        });
      let updated_at: string | null = null;
      try {
        updated_at = statSync(fullPath).mtime.toISOString();
      } catch {
        updated_at = null;
      }
      return {
        path: name,
        updated_at,
        key_count: keys.length,
        keys: keys.slice(0, 12),
      };
    })
    .filter((x): x is EnvFileSummary => x !== null);
}

function buildDashboard(rootDir: string, progress: RawProgress | null): OperationsDashboard {
  const features = buildFeatureSummaries(rootDir);
  return {
    workers: buildWorkers(rootDir, progress),
    features,
    recentMeetings: buildRecentMeetings(rootDir),
    opsHealth: buildOpsHealth(progress),
    envFiles: buildEnvFiles(rootDir),
  };
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
            const hasDocmeta = /^---[\s\S]*?docmeta:[\s\S]*?---/.test(content);
            // Runtime state is the source of truth for live activity. A
            // recently touched docmeta-only draft is not enough to prove that a
            // detached worker session is still running.
            const status: WorkerDocEntry["status"] = statusMatch
              ? (statusMatch[1] as WorkerDocEntry["status"])
              : hasDocmeta
              ? "COMPLETE"
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
        const roleWorkers = workers.filter((w) => w.owner === role);
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

  missions = missions.slice(0, limit);

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
    snapshot.archive = buildArchive(rootDir);
    snapshot.missions = readMissions(rootDir, null);
    snapshot.ownerHistory = readOwnerHistory(rootDir);
    snapshot.gotchas = readGotchas(rootDir);
    snapshot.conventions = readConventions(rootDir);
    snapshot.todos = readTodos(rootDir);
    snapshot.events = readEvents(rootDir);
    snapshot.activitySamples = readActivitySamples(rootDir);
    return snapshot;
  }

  const progress = result.value;
  const meetingActive = progress.meetings?.active ?? [];
  const meetings: MeetingsState = {
    active: meetingActive,
    cadence: deriveCadence(progress.meetings?.cadence as string | undefined),
    next_scheduled: progress.meetings?.next_scheduled ?? null,
    current: buildCurrentMeeting(progress),
  };

  const tracks = buildTracks(progress);
  const incidents = buildIncidents(progress);
  const hypothesisList = buildHypothesis(progress);
  const escalations = buildEscalations(progress);
  const features = buildFeatureSummaries(rootDir);
  const contract = buildContract(rootDir, progress, features);
  const evalScores = progress.cqo?.last_scores ?? null;
  const dashboard = buildDashboard(rootDir, progress);

  return {
    version: SNAPSHOT_VERSION,
    ts: new Date().toISOString(),
    projectName: path.basename(rootDir),
    projectPath: rootDir,
    agents: buildAgents(progress, meetingActive, incidents),
    rooms: buildRooms(
      progress,
      meetingActive,
      meetings,
      tracks,
      incidents,
      hypothesisList,
      contract,
      evalScores,
    ),
    goal: buildGoal(rootDir, progress),
    archive: buildArchive(rootDir),
    meetings,
    tracks,
    incidents,
    hypothesis: hypothesisList,
    escalations,
    contract,
    evalScores,
    errorBanner: null,
    dashboard,
    runtime: buildRuntime(progress),
    missions: readMissions(rootDir, progress),
    ownerHistory: readOwnerHistory(rootDir),
    gotchas: readGotchas(rootDir),
    conventions: readConventions(rootDir),
    todos: readTodos(rootDir),
    events: readEvents(rootDir),
    activitySamples: readActivitySamples(rootDir),
  };
}

// Exported for tests — silences the unused warning when only the type is used.
export type { Dept };
