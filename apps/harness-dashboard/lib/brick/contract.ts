/* =============================================================
   walwal-harness · BRICK OFFICE Data Contract
   The single state shape every view renders from. Ported from the
   design-handoff simulation (harness/sim.jsx, harness/ui.jsx) — but
   here it is produced from REAL harness data by lib/brick/adapter.ts.

   This module is pure (no React, no DOM). It exports:
   - the Contract TypeScript interfaces
   - AGENT_DEFS (the 6 CXX roles with id/name/role/hue)
   - fmt utils (time, hm, ago, k, money)
   - statusColor + STATUS_COLOR
   ============================================================= */

/** The role ids of the 6 exec agents, in canonical display order. */
export type AgentRole = "ceo" | "coo" | "cdo" | "cto" | "cqo" | "ops";

/**
 * Status enum shared by agents and workers. The simulation used the full set
 * (idle | typing | talking | active | alert | live); the real adapter only
 * emits the subset {live, active, alert, idle}, but the renderer/statusColor
 * still understands every value so the design's legend stays faithful.
 */
export type AgentStatus =
  | "idle"
  | "typing"
  | "talking"
  | "active"
  | "alert"
  | "live";

/** The agent's autonomous loop state. */
export type LoopState = "running" | "idle";

/** Task lifecycle, as rendered by the task panel. */
export type TaskStatus = "running" | "queued" | "done";

/** Attention-queue severity. */
export type AlertLevel = "stale" | "attention";

/** A reference to a document the DocViewer can render. */
export type DocTarget =
  | { type: "agent"; agent: AgentRole }
  | { type: "worker"; agent: AgentRole; worker: ContractWorker };

/** Static, design-fixed definition of one exec agent. */
export interface AgentDef {
  id: AgentRole;
  name: string;
  role: string;
  hue: string;
}

/** One exec agent row in the live state. */
export interface ContractAgent {
  id: AgentRole;
  name: string;
  role: string;
  hue: string;
  status: AgentStatus;
  loop: LoopState;
  /** One-line "current work" string. "—" when there is no live work string. */
  work: string;
  /** Open todo count. */
  todos: number;
  /** Count of live workers (derived from `workers` below). */
  workers: number;
  /** ~24 ints, recent activity, drives the bar sparkline. */
  spark: number[];
  /** epoch ms of last visible movement -> drives "stale"; null when unknown. */
  heartbeat: number | null;
  /** Full report markdown for this agent (mission[role]); undefined when none. */
  report?: string;
}

/** One spawned worker across all agents. */
export interface ContractWorker {
  id: string;
  agent: AgentRole;
  name: string;
  status: AgentStatus;
  /** epoch ms; null when unknown. */
  started: number | null;
  /** 0..100, or null when there is no real granular progress source. */
  progress: number | null;
  /** Full worker report/brief markdown (worker.content); undefined when none. */
  report?: string;
}

/** One task in the running/queued/done lanes. */
export interface ContractTask {
  id: string;
  /** Owner display label, e.g. "CTO". */
  owner: string;
  title: string;
  agent: AgentRole;
  status: TaskStatus;
  /** 0..100, or null — there is no real granular progress source. */
  progress: number | null;
  /** epoch ms the task started, or null. */
  started?: number | null;
  /** epoch ms the task completed (done lane only), or null. */
  at?: number | null;
}

/** The three task lanes. */
export interface ContractTasks {
  running: ContractTask[];
  queued: ContractTask[];
  done: ContractTask[];
}

/** One activity-stream event. */
export interface ContractEvent {
  id: string;
  /** epoch ms; null when unknown. */
  at: number | null;
  agent: AgentRole | "";
  worker: string;
  /** The verb; "COMPLETE"/"complete" renders green. */
  verb: string;
  /** The object the verb acted on. */
  obj: string;
}

/** One attention-queue alert. */
export interface ContractAlert {
  id: string;
  level: AlertLevel;
  agent: AgentRole;
  msg: string;
  /** epoch ms; null when unknown. */
  at: number | null;
}

/**
 * System-health metrics. Values with no real telemetry source are `null`
 * and MUST render as "—" (never a fabricated number).
 */
export interface ContractMetrics {
  /** "open" when the SSE stream is connected, else "closed". */
  sse: "open" | "closed";
  /** No real source -> null. */
  tokensPerMin: number | null;
  /** No real source -> null. */
  costToday: number | null;
  /** Count of events in the last 60s (derived). */
  throughput: number | null;
  /** No real source -> null. */
  cpu: number | null;
  /** Count of missions of type 'hotfix'. */
  hotfix: number;
  /** Total events in the snapshot. */
  eventsTotal: number;
}

/** The single source-of-truth state every view renders from. */
export interface ContractState {
  /** epoch ms, ticked ~1/s by the shell. */
  now: number;
  agents: ContractAgent[];
  workers: ContractWorker[];
  tasks: ContractTasks;
  events: ContractEvent[];
  /** 24 hourly buckets = owner prompts/hour -> heatmap. */
  cadence: number[];
  alerts: ContractAlert[];
  metrics: ContractMetrics;
  /** tokens/min sparkline samples; [] when no source. */
  mtrend: number[];
  /** cost sparkline samples; [] when no source. */
  ctrend: number[];
}

/* ---- agent (exec) definitions -----------------------------------------
   The 6 CXX roles in canonical order, with per-role accent hue.
   Ported from sim.jsx AGENTS, with hues per the adapter spec. */
export const AGENT_DEFS: readonly AgentDef[] = [
  { id: "ceo", name: "CEO", role: "Chief Executive", hue: "#4cc2ff" },
  { id: "coo", name: "COO", role: "Operations", hue: "#3fd17a" },
  { id: "cdo", name: "CDO", role: "Design", hue: "#8b95a4" },
  { id: "cto", name: "CTO", role: "Technology", hue: "#f0a23b" },
  { id: "cqo", name: "CQO", role: "Quality", hue: "#c084fc" },
  { id: "ops", name: "OPS", role: "Runtime Watch", hue: "#f97e4d" },
] as const;

/** The 6 role ids in canonical order. */
export const AGENT_ROLES: readonly AgentRole[] = AGENT_DEFS.map((a) => a.id);

/** Quick lookup by role id. */
export const AGENT_DEF_BY_ID: Record<AgentRole, AgentDef> = AGENT_DEFS.reduce(
  (acc, def) => {
    acc[def.id] = def;
    return acc;
  },
  {} as Record<AgentRole, AgentDef>
);

/* ---- status colors (ported from ui.jsx) ------------------------------- */
export const STATUS_COLOR: Record<string, string> = {
  live: "#3fd17a",
  active: "#3fd17a",
  typing: "#4cc2ff",
  talking: "#c084fc",
  idle: "#5a6472",
  alert: "#f0506b",
  running: "#3fd17a",
  stale: "#f0a23b",
};

export const statusColor = (s: string): string => STATUS_COLOR[s] ?? "#5a6472";

/* ---- fmt utils (ported from sim.jsx) ----------------------------------
   Pure formatting helpers. `time`/`hm` take a Date; `ago` takes a ms delta;
   `k`/`money` take numbers (and tolerate null -> "—" for honest blanks). */
export const fmt = {
  /** "HH:MM:SS" */
  time: (d: Date): string => d.toTimeString().slice(0, 8),
  /** "HH:MM" */
  hm: (d: Date): string => d.toTimeString().slice(0, 5),
  /** humanize a ms delta -> "Ns ago" / "Nm ago" / "Nh ago" */
  ago: (ms: number): string => {
    const s = Math.floor(ms / 1000);
    if (s < 60) return s + "s ago";
    const m = Math.floor(s / 60);
    if (m < 60) return m + "m ago";
    const h = Math.floor(m / 60);
    return h + "h ago";
  },
  /** compact thousands: 11200 -> "11.2k"; null -> "—" */
  k: (n: number | null | undefined): string => {
    if (n == null || !Number.isFinite(n)) return "—";
    return n >= 1000 ? (n / 1000).toFixed(1) + "k" : String(Math.round(n));
  },
  /** "$42.18"; null -> "—" */
  money: (n: number | null | undefined): string => {
    if (n == null || !Number.isFinite(n)) return "—";
    return "$" + n.toFixed(2);
  },
};

/** Render a possibly-null number as the design's em-dash blank. */
export const dashIfNull = (n: number | null | undefined): string =>
  n == null || !Number.isFinite(n) ? "—" : String(n);
