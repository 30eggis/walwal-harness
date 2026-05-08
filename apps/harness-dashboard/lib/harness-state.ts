import { existsSync, readdirSync, statSync, readFileSync } from "node:fs";
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
  GoalCard,
  HarnessSnapshot,
  HypothesisEntry,
  IncidentEntry,
  MeetingCadence,
  MeetingRecord,
  MeetingsState,
  OperationsDashboard,
  OpsServiceHealth,
  ParallelTrack,
  Pipeline,
  RoomId,
  RoomMetrics,
  RoomState,
  TrackStatus,
  WorkerSnapshot,
} from "./types";

const SNAPSHOT_VERSION = "1.2.0";
const GOAL_DESC_TRUNCATE = 200;

interface RawProgress {
  goals?: {
    active_id?: string | null;
    list?: Array<{ id: string; title?: string; description?: string }>;
    current_adherence?: number | null;
  };
  current_agent?: AgentId | null;
  next_agent?: AgentId | null;
  agent_status?: string;
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
      team?: number | string;
      feature?: string;
      agent?: string;
      phase?: string;
      prompt?: string | null;
      log?: string | null;
      spawn_status?: string;
      status?: string;
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
    dashboard: { workers: [], recentMeetings: [], opsHealth: [], envFiles: [] },
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

function buildGoal(progress: RawProgress | null): GoalCard | null {
  const list = progress?.goals?.list ?? [];
  const activeId = progress?.goals?.active_id;
  if (!activeId) return null;
  const found = list.find((g) => g.id === activeId);
  if (!found) return null;
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

function buildContract(progress: RawProgress | null): ContractSnapshot {
  const total = progress?.contracts?.feature_list?.total ?? 0;
  const passed = progress?.contracts?.feature_list?.passed ?? 0;
  const failed = progress?.contracts?.feature_list?.failed ?? 0;
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

type RawWorker = NonNullable<NonNullable<RawProgress["company_state"]>["workers"]>[number];

function deriveWorkerProgress(worker: RawWorker): number | null {
  const status = (worker?.status ?? worker?.spawn_status ?? "").toLowerCase();
  if (status === "blocked" || status === "failed") return 0.35;
  if (status === "recorded") return 0.15;
  if (status === "spawned" || status === "running") return 0.55;
  if (status === "completed" || status === "done") return 1;
  return null;
}

function buildWorkers(rootDir: string, progress: RawProgress | null): WorkerSnapshot[] {
  const titles = readFeatureTitles(rootDir);
  const workers = progress?.company_state?.workers ?? [];
  return workers.map((w, idx) => {
    const feature = w.feature ?? `worker-${idx + 1}`;
    const promptText = w.prompt ? readTextSafe(path.join(rootDir, w.prompt)) : null;
    const logText = w.log ? readTextSafe(path.join(rootDir, w.log)) : null;
    const summarySource = firstLine(logText) || firstLine(promptText) || `${w.agent ?? "worker"} assigned`;
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
  return {
    workers: buildWorkers(rootDir, progress),
    recentMeetings: buildRecentMeetings(rootDir),
    opsHealth: buildOpsHealth(progress),
    envFiles: buildEnvFiles(rootDir),
  };
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
  const contract = buildContract(progress);
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
    goal: buildGoal(progress),
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
  };
}

// Exported for tests — silences the unused warning when only the type is used.
export type { Dept };
