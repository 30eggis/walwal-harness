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

export type MeetingCadence = "light" | "normal" | "heavy";

export type TrackStatus = "dispatched" | "in_progress" | "joined" | "blocked";

export type IncidentSeverity = "low" | "medium" | "high" | "critical";

export interface IncidentEntry {
  id: string;
  dept: Dept | "Operations" | "Multi" | string;
  severity: IncidentSeverity;
  message?: string;
  ts?: string | null;
}

export type Pipeline = "FULLSTACK" | "FE-ONLY" | "BE-ONLY" | "META_REFACTOR" | null;

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

export interface RuntimeSnapshot {
  currentAgent: string | null;
  agentStatus: string;
  nextAgent: string | null;
  updatedAt: string | null;
  ownerPrompt: {
    command: string;
    summary: string;
    receivedAt: string | null;
    status: string;
  } | null;
}

export interface HarnessSnapshot {
  version: string;
  ts: string;
  projectName: string;
  projectPath: string;
  errorBanner: ErrorBanner | null;
  runtime: RuntimeSnapshot;
  incidents: IncidentEntry[];
  missions: MissionDoc[];
  ownerHistory: OwnerPromptEntry[];
  gotchas: GotchaEntry[];
  conventions: ConventionEntry[];
  todos: CxxTodo[];
  events: HarnessEvent[];
  activitySamples: ActivitySample[];
}

export interface ActivitySample {
  ts: string;
  laneId: string;
  count: number;
  hotfix: boolean;
  missionId: string | null;
}

export interface CxxTodo {
  id: string;
  owner: "ceo" | "coo" | "cdo" | "cto" | "cqo" | "ops" | string;
  title: string;
  status: "pending" | "active" | "paused" | "blocked" | "done" | string;
  priority: number;
  kind: string;
  missionPath?: string | null;
  requiredArtifacts: string[];
  createdAt: string | null;
  updatedAt: string | null;
  lastHeartbeatAt?: string | null;
  blockedReason?: string | null;
}

export interface HarnessEvent {
  ts: string | null;
  type: string;
  owner?: string | null;
  command?: string | null;
  summary?: string | null;
  title?: string | null;
  status?: string | null;
}

// Real harness mission documents
export interface WorkerDocEntry {
  name: string;
  displayName: string;
  content: string;
  status: "COMPLETE" | "IN_PROGRESS" | "unknown";
  owner: "cto" | "cqo" | "coo" | "cdo" | "ops" | "unknown";
  hired: boolean;
  active: boolean;
  sourcePath?: string | null;
  reportPath?: string | null;
  updatedAt?: string | null;
}

export interface MissionDoc {
  missionId: string;
  ts: string;
  type: "goal" | "submission" | "hotfix" | "feature" | "unknown";
  lifecycle: "active" | "operating" | "closed" | "cancelled" | "superseded" | "complete" | "blocked" | "unknown";
  active: boolean;
  protocolViolations: string[];
  label: string;
  ceo: string | null;
  cto: string | null;
  cqo: string | null;
  coo: string | null;
  cdo: string | null;
  cdoPreview: string | null;
  ops: string | null;
  workers: WorkerDocEntry[];
  cxxPresent: string[];
  /** Perpetual (operating) goals: count of agenda items not yet done. */
  agendaOpen?: number;
  /** Perpetual (operating) goals: completed operating cycles. */
  operatingCycles?: number;
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
  sourcePath?: string | null;
  updatedAt?: string | null;
}

export interface ConventionEntry {
  id: string;
  title: string;
  content: string;
  tags: string[];
  sourcePath?: string | null;
  updatedAt?: string | null;
}
