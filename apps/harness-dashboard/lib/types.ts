export type AgentId =
  | "dispatcher"
  | "conductor"
  | "meeting-manager"
  | "planner"
  | "generator-backend"
  | "generator-frontend"
  | "generator-designer"
  | "generator-devops"
  | "cqo"
  | "evaluator-functional"
  | "evaluator-visual"
  | "evaluator-code-quality"
  | "evaluator-architecture"
  | "evaluator-security"
  | "service-ops";

export type RoomId =
  | "ceo"
  | "meeting"
  | "coo"
  | "cto-team"
  | "cqo-team"
  | "service-ops"
  | "archive";

export type Dept = "CEO" | "Meeting" | "Planner" | "CTO" | "CQO" | "Operations";

export type MinifigState = "idle" | "typing" | "talking" | "red-alert";

export interface AgentState {
  id: AgentId;
  name: string;
  dept: Dept;
  /** The agent's *current* room (after meeting teleport). */
  room: RoomId;
  /** The agent's home room — never changes. */
  homeRoom: RoomId;
  minifigState: MinifigState;
  lastActivity: string | null;
  talkingPreview?: string;
  alertReason?: string;
}

export interface RoomMetrics {
  sprint_number?: number;
  last_review?: string | null;
  last_audit?: string | null;
  last_check?: string | null;
  sprint_verdict?: "pending" | "PASS" | "FAIL";
  open_alerts?: number;
  open_arch_risks?: number;
  open_regressions?: number;
}

export interface SeatLayout {
  seats: number;
  occupants: AgentId[];
  overflow: number;
}

export interface RoomState {
  id: RoomId;
  label_ko: string;
  label_en: string;
  dept: Dept | "Archive";
  metrics?: RoomMetrics;
  seatLayout?: SeatLayout;
}

export interface GoalCard {
  id: string;
  title: string;
  description_truncated?: string;
  adherence: number | null;
}

export interface ArchiveEntry {
  dir: string;
  label: string;
  result: "PASS" | "FAIL" | "unknown";
  ts: string | null;
}

export interface ArchiveStat {
  sprintCount: number;
  recent: ArchiveEntry[];
  all: ArchiveEntry[];
}

export interface MeetingsState {
  active: AgentId[];
  cadence: string;
  next_scheduled: string | null;
}

export interface ErrorBanner {
  level: "info" | "warn" | "error";
  message_ko: string;
  message_en: string;
}

export interface HarnessSnapshot {
  version: string;
  ts: string;
  agents: AgentState[];
  rooms: RoomState[];
  goal: GoalCard | null;
  archive: ArchiveStat;
  meetings: MeetingsState;
  errorBanner: ErrorBanner | null;
}
