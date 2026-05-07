import { existsSync, readdirSync, statSync } from "node:fs";
import path from "node:path";
import { readJsonSafe } from "./safe-json";
import { AGENT_ROSTER, ROOM_LABELS } from "./agent-roster";
import { deriveMinifigState, pickTalkingPreview } from "./state-mapping";
import type {
  AgentId,
  AgentState,
  ArchiveEntry,
  ArchiveStat,
  ErrorBanner,
  GoalCard,
  HarnessSnapshot,
  MeetingsState,
  RoomId,
  RoomMetrics,
  RoomState,
} from "./types";

const SNAPSHOT_VERSION = "1.1.0";
const GOAL_DESC_TRUNCATE = 200;

interface RawProgress {
  goals?: {
    active_id?: string | null;
    list?: Array<{ id: string; title?: string; description?: string }>;
    current_adherence?: number | null;
  };
  current_agent?: AgentId | null;
  agent_status?: string;
  failure?: { agent?: AgentId | null; message?: string | null; location?: string | null; retry_target?: AgentId | null } | null;
  meetings?: {
    active?: AgentId[];
    cadence?: string;
    next_scheduled?: string | null;
  };
  cto?: { last_review?: string | null; open_arch_risks?: number };
  cqo?: {
    last_audit?: string | null;
    sprint_verdict?: "pending" | "PASS" | "FAIL";
    open_regressions?: number;
  };
  service_ops?: {
    monitor?: { last_check?: string | null; alerts_this_sprint?: number };
    incident?: { open?: Array<{ id: string; dept?: string }> };
  };
  sprint?: { number?: number };
}

function emptySnapshot(banner: ErrorBanner | null = null): HarnessSnapshot {
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
    agents,
    rooms,
    goal: null,
    archive: { sprintCount: 0, recent: [], all: [] },
    meetings: { active: [], cadence: "normal", next_scheduled: null },
    errorBanner: banner,
  };
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
    let ts: string | null = null;
    try {
      ts = statSync(path.join(archiveDir, name)).mtime.toISOString();
    } catch {
      ts = null;
    }
    return { dir: name, label: name, result: "unknown", ts };
  });
  all.sort((a, b) => (b.ts ?? "").localeCompare(a.ts ?? ""));
  return { sprintCount: all.length, recent: all.slice(0, 3), all };
}

function buildRooms(progress: RawProgress | null, meetingActive: AgentId[]): RoomState[] {
  const cto = progress?.cto;
  const cqo = progress?.cqo;
  const ops = progress?.service_ops;
  const sprintNumber = progress?.sprint?.number;

  const metrics: Partial<Record<RoomId, RoomMetrics>> = {
    "cto-team": {
      sprint_number: sprintNumber,
      last_review: cto?.last_review ?? null,
      open_arch_risks: cto?.open_arch_risks ?? 0,
    },
    "cqo-team": {
      sprint_number: sprintNumber,
      last_audit: cqo?.last_audit ?? null,
      sprint_verdict: cqo?.sprint_verdict ?? "pending",
      open_regressions: cqo?.open_regressions ?? 0,
    },
    "service-ops": {
      sprint_number: sprintNumber,
      last_check: ops?.monitor?.last_check ?? null,
      open_alerts: ops?.monitor?.alerts_this_sprint ?? 0,
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

function buildAgents(progress: RawProgress | null, meetingActive: AgentId[]): AgentState[] {
  // C-2 spike (pulled forward by user request): derive minifigState from
  // progress.json. Talking agents teleport into the meeting room.
  const meetingSet = new Set<AgentId>(meetingActive);
  return AGENT_ROSTER.map((entry) => {
    const minifigState = deriveMinifigState(entry.id, progress ?? null);
    const inMeeting = meetingSet.has(entry.id);
    const room = inMeeting ? "meeting" : entry.room;
    const lastActivity =
      progress?.current_agent === entry.id
        ? `current_agent (${progress.agent_status ?? "unknown"})`
        : null;
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
          ? progress?.failure?.message ?? "incident"
          : undefined,
    };
  });
}

export function readHarnessState(rootDir: string): HarnessSnapshot {
  const harnessDir = path.join(rootDir, ".harness");
  if (!existsSync(harnessDir)) {
    return emptySnapshot({
      level: "error",
      message_ko: "하네스 상태가 없습니다 — Dispatcher를 먼저 실행하세요.",
      message_en: "Harness state not found — run Dispatcher first.",
    });
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
    const snapshot = emptySnapshot(banner);
    snapshot.archive = buildArchive(rootDir);
    return snapshot;
  }

  const progress = result.value;
  const meetingActive = progress.meetings?.active ?? [];
  const meetings: MeetingsState = {
    active: meetingActive,
    cadence: progress.meetings?.cadence ?? "normal",
    next_scheduled: progress.meetings?.next_scheduled ?? null,
  };

  return {
    version: SNAPSHOT_VERSION,
    ts: new Date().toISOString(),
    agents: buildAgents(progress, meetingActive),
    rooms: buildRooms(progress, meetingActive),
    goal: buildGoal(progress),
    archive: buildArchive(rootDir),
    meetings,
    errorBanner: null,
  };
}
