export type AgentId =
  | "dispatcher"
  | "brainstormer"
  | "conductor"
  | "meeting-manager"
  | "planner"
  | "coo-developer"
  | "documentationer"
  | "cto"
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

export type MinifigState = "idle" | "queued" | "typing" | "talking" | "red-alert";

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
  cadence?: MeetingCadence;
  next_scheduled?: string | null;
  active_tracks?: number;
  active_hypothesis?: number;
  active_workers?: number;
  open_incidents?: number;
  pass_rate?: number | null;
  contract_signed?: { be?: boolean; fe?: boolean };
  eval_scores?: EvalScores | null;
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

export type MeetingCadence = "light" | "normal" | "heavy";
export type MeetingType =
  | "standup"
  | "sprint-review"
  | "spec-review"
  | "incident-war-room"
  | "all-hands"
  | "followup-review";

export interface CurrentMeeting {
  type: MeetingType;
  topic?: string;
  convened_at?: string | null;
}

export interface MeetingsState {
  active: AgentId[];
  cadence: MeetingCadence;
  next_scheduled: string | null;
  current: CurrentMeeting | null;
}

export type TrackStatus = "dispatched" | "in_progress" | "joined" | "blocked";

export interface ParallelTrack {
  id: string;
  from_meeting: string;
  to_dept: Dept | "Operations" | "Multi";
  to_room: RoomId;
  status: TrackStatus;
  label?: string;
}

export type IncidentSeverity = "low" | "medium" | "high" | "critical";

export interface IncidentEntry {
  id: string;
  dept: Dept | "Operations" | "Multi" | string;
  severity: IncidentSeverity;
  message?: string;
  ts?: string | null;
}

export type HypothesisVerdict = "pending" | "valid" | "invalid";

export interface HypothesisEntry {
  id: string;
  brief: string;
  verdict: HypothesisVerdict;
  ts?: string | null;
}

export type EscalationReason =
  | "three-fail"
  | "incident"
  | "goal-violation"
  | "budget"
  | "other";

export interface EscalationEntry {
  id: string;
  reason: EscalationReason | string;
  message?: string;
  ts?: string | null;
}

export type Pipeline = "FULLSTACK" | "FE-ONLY" | "BE-ONLY" | "META_REFACTOR" | null;

export interface ContractSnapshot {
  sprint_number: number | null;
  pipeline: Pipeline;
  api_version: string | null;
  feature_total: number;
  feature_passed: number;
  feature_failed: number;
  contract_signed: { be: boolean; fe: boolean };
}

export interface FeatureSummary {
  id: string;
  title: string;
  status: "ready" | "blocked" | "in_progress" | "passed" | "failed" | "unknown";
  passes: string[];
}

export interface EvalScores {
  functional?: number | null;
  visual?: number | null;
  code_quality?: number | null;
  architecture?: number | null;
  security?: number | null;
}

export interface ErrorBanner {
  level: "info" | "warn" | "error";
  message_ko: string;
  message_en: string;
}

export interface WorkerSnapshot {
  team: number | string;
  feature: string;
  title?: string;
  agent: AgentId | string;
  phase?: string;
  status: "spawned" | "recorded" | "running" | "idle" | "blocked" | "unknown";
  pid?: number | null;
  prompt?: string | null;
  log?: string | null;
  progress: number | null;
  summary: string;
  next_material?: string | null;
}

export interface MeetingRecord {
  id: string;
  path: string;
  ts: string | null;
  title: string;
  verdict?: string | null;
  summary: string;
  content: string;
}

export interface OpsServiceHealth {
  name: string;
  host: string;
  port: number;
  status: "ok" | "degraded" | "down" | "unknown";
  port_state?: string | null;
  health_status?: number | null;
  health_path?: string | null;
  recent_errors?: number | null;
}

export interface EnvKeySummary {
  key: string;
  category: "secret" | "endpoint" | "port" | "mode" | "other";
  masked: string;
}

export interface EnvFileSummary {
  path: string;
  updated_at: string | null;
  key_count: number;
  keys: EnvKeySummary[];
}

export interface OperationsDashboard {
  workers: WorkerSnapshot[];
  features: FeatureSummary[];
  recentMeetings: MeetingRecord[];
  opsHealth: OpsServiceHealth[];
  envFiles: EnvFileSummary[];
}

export interface HarnessSnapshot {
  version: string;
  ts: string;
  projectName: string;
  projectPath: string;
  agents: AgentState[];
  rooms: RoomState[];
  goal: GoalCard | null;
  archive: ArchiveStat;
  meetings: MeetingsState;
  tracks: ParallelTrack[];
  incidents: IncidentEntry[];
  hypothesis: HypothesisEntry[];
  escalations: EscalationEntry[];
  contract: ContractSnapshot;
  evalScores: EvalScores | null;
  errorBanner: ErrorBanner | null;
  dashboard: OperationsDashboard;
  missions: MissionDoc[];
  ownerHistory: OwnerPromptEntry[];
  gotchas: GotchaEntry[];
}

// Real harness mission documents
export interface WorkerDocEntry {
  name: string;
  content: string;
  status: "COMPLETE" | "IN_PROGRESS" | "unknown";
  owner: "cto" | "cqo" | "coo" | "cdo" | "ops" | "unknown";
}

export interface MissionDoc {
  missionId: string;
  ts: string;
  type: "goal" | "submission" | "hotfix" | "feature" | "unknown";
  label: string;
  ceo: string | null;
  cto: string | null;
  cqo: string | null;
  coo: string | null;
  cdo: string | null;
  ops: string | null;
  workers: WorkerDocEntry[];
  cxxPresent: string[];
}

export interface OwnerPromptEntry {
  ts: string;
  content: string;
  type: "goal" | "submission" | "hot-fix" | "other";
}

export interface GotchaEntry {
  id: string;
  title: string;
  content: string;
  tags: string[];
}

export type OrgRole = "owner" | "ceo" | "coo" | "cdo" | "cto" | "cqo" | "ops";

export interface OrgNodeDef {
  id: string;
  role: OrgRole;
  label: string;
  sublabel?: string;
  status: MinifigState;
  activity: string | null;
  agentIds: AgentId[];
}
