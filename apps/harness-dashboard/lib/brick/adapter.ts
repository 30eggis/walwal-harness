/* =============================================================
   walwal-harness · BRICK OFFICE real-data adapter
   Maps a real HarnessSnapshot onto the design's Contract shape.

   Honesty over fake values: where the real feed has no granular
   source (token/min, cost, cpu, per-task %, per-worker %), the
   field is `null` and the UI renders "—". Nothing is fabricated.

   This module is pure (no React, no DOM).
   ============================================================= */

import type {
  HarnessSnapshot,
  WorkerDocEntry,
  MissionDoc,
  CxxTodo,
  HarnessEvent,
  ActivitySample,
  OwnerPromptEntry,
} from "../types";
import {
  AGENT_DEFS,
  AGENT_ROLES,
  type AgentRole,
  type AgentStatus,
  type ContractState,
  type ContractAgent,
  type ContractWorker,
  type ContractTask,
  type ContractTasks,
  type ContractEvent,
  type ContractAlert,
  type ContractMetrics,
} from "./contract";

/* ---- constants mirrored from Scene.tsx bucketing ---------------------- */
const BUCKET_MS = 10 * 60_000; // 10-minute heat buckets (matches Scene heatmap)
const SPARK_BUCKETS = 24; // 24 buckets of recent activity -> the bar sparkline
const HOUR_MS = 60 * 60 * 1000;
const CADENCE_BUCKETS = 24; // 24 hourly buckets of owner prompts
const STALE_MS = 120_000; // running but no visible movement > 120s -> stale
const THROUGHPUT_WINDOW_MS = 60_000; // events in the last 60s

const ROLE_SET = new Set<string>(AGENT_ROLES);

/* ---- helpers ---------------------------------------------------------- */

/** Strip the `harness-` prefix and lowercase, returning a role or null. */
function toRole(value: string | null | undefined): AgentRole | null {
  const r = (value ?? "").toLowerCase().replace(/^harness-/, "").trim();
  return ROLE_SET.has(r) ? (r as AgentRole) : null;
}

/** Parse an ISO timestamp to epoch ms, or null when unparseable. */
function parseTs(ts: string | null | undefined): number | null {
  if (!ts) return null;
  const t = Date.parse(ts);
  return Number.isFinite(t) ? t : null;
}

/** Strip leading YAML frontmatter from a markdown string. */
export function stripFrontmatter(md: string | null | undefined): string {
  if (!md) return "";
  return md.replace(/^---[\s\S]*?---\n+/, "");
}

/** The active mission (active flag), else the first mission, else null. */
function pickActiveMission(snapshot: HarnessSnapshot): MissionDoc | null {
  return snapshot.missions.find((m) => m.active) ?? snapshot.missions[0] ?? null;
}

/** Read a role's report markdown off a mission doc. */
function missionReportFor(
  mission: MissionDoc | null,
  role: AgentRole
): string | undefined {
  if (!mission) return undefined;
  const raw = mission[role];
  return typeof raw === "string" && raw.length > 0 ? raw : undefined;
}

/**
 * Build a per-role spark array: SPARK_BUCKETS buckets of activitySamples,
 * newest bucket last (mirrors Scene.tsx heat bucketing — x = nowMinute -
 * sampleMinute, keep the strongest count seen in each bucket).
 */
function buildSpark(samples: ActivitySample[], role: AgentRole, nowMs: number): number[] {
  const nowBucket = Math.floor(nowMs / BUCKET_MS);
  const buckets = new Array<number>(SPARK_BUCKETS).fill(0);
  for (const sample of samples) {
    // A role owns its own lane (id === role) and all of its worker lanes
    // (id === `${role}:...`). Both contribute to the role's activity spark.
    const lane = sample.laneId;
    if (lane !== role && !lane.startsWith(role + ":")) continue;
    const t = parseTs(sample.ts);
    if (t == null) continue;
    const x = nowBucket - Math.floor(t / BUCKET_MS);
    if (x < 0 || x >= SPARK_BUCKETS) continue;
    // index SPARK_BUCKETS-1 = now (newest), index 0 = oldest visible bucket
    const idx = SPARK_BUCKETS - 1 - x;
    buckets[idx] = Math.max(buckets[idx], sample.count);
  }
  return buckets;
}

/** Newest activity epoch across a role's lanes + its workers + events. */
function heartbeatFor(
  snapshot: HarnessSnapshot,
  role: AgentRole,
  workers: WorkerDocEntry[],
  eventEpochByRole: Map<AgentRole, number>
): number | null {
  let hb: number | null = null;
  const bump = (t: number | null) => {
    if (t != null && (hb == null || t > hb)) hb = t;
  };
  for (const sample of snapshot.activitySamples) {
    const lane = sample.laneId;
    if (lane === role || lane.startsWith(role + ":")) bump(parseTs(sample.ts));
  }
  for (const w of workers) bump(parseTs(w.updatedAt));
  bump(eventEpochByRole.get(role) ?? null);
  return hb;
}

/** Determine if the company loop is active for status/loop derivation. */
function loopIsActive(snapshot: HarnessSnapshot): boolean {
  const rt = snapshot.runtime;
  const agentStatus = (rt.agentStatus ?? "").toLowerCase();
  const conductor = (rt.conductorState ?? "").toLowerCase();
  const agentDone = agentStatus === "completed" || agentStatus === "complete";
  const conductorDone =
    conductor === "completed" || conductor === "complete" || conductor === "blocked";
  return !agentDone && !conductorDone;
}

/* ---- the adapter ------------------------------------------------------ */

/**
 * Map a real HarnessSnapshot onto the design Contract shape.
 *
 * @param snapshot  the real harness feed snapshot
 * @param connected whether the SSE stream is currently open
 * @param nowMs     the shell's ~1/s clock value (epoch ms)
 */
export function toContractState(
  snapshot: HarnessSnapshot,
  connected: boolean,
  nowMs: number
): ContractState {
  const rt = snapshot.runtime;
  const currentRole = toRole(rt.currentAgent);
  const loopActive = loopIsActive(snapshot);
  const activeMission = pickActiveMission(snapshot);

  // Workers from the active mission(s) — index by role.
  const activeMissions = snapshot.missions.filter((m) => m.active);
  const missionsForWorkers = activeMissions.length > 0 ? activeMissions : snapshot.missions;
  const workerEntries: Array<{ worker: WorkerDocEntry; mission: MissionDoc }> = [];
  const workersByRole = new Map<AgentRole, WorkerDocEntry[]>();
  for (const role of AGENT_ROLES) workersByRole.set(role, []);
  for (const mission of missionsForWorkers) {
    for (const worker of mission.workers) {
      const role = toRole(worker.owner);
      if (!role) continue;
      workerEntries.push({ worker, mission });
      workersByRole.get(role)!.push(worker);
    }
  }

  // Events newest-first; capture per-role newest epoch for heartbeats.
  const eventEpochByRole = new Map<AgentRole, number>();
  const firstLaneRole = (): AgentRole | null => {
    const s = snapshot.activitySamples[snapshot.activitySamples.length - 1];
    return s ? toRole(s.laneId.split(":")[0]) : null;
  };
  for (const ev of snapshot.events) {
    const role = toRole(ev.owner);
    const t = parseTs(ev.ts);
    if (role && t != null) {
      const prev = eventEpochByRole.get(role);
      if (prev == null || t > prev) eventEpochByRole.set(role, t);
    }
  }

  // ---- agents --------------------------------------------------------
  const hasRecentSample = (role: AgentRole): boolean =>
    snapshot.activitySamples.some(
      (s) => {
        if ((s.laneId !== role && !s.laneId.startsWith(role + ":")) || s.count <= 0) return false;
        const t = parseTs(s.ts);
        return t != null && nowMs - t <= STALE_MS;
      }
    );
  const runtimeBlocked =
    (rt.agentStatus ?? "").toLowerCase() === "blocked" ||
    (rt.conductorState ?? "").toLowerCase() === "blocked";

  const agents: ContractAgent[] = AGENT_DEFS.map((def) => {
    const role = def.id;
    const isCurrent = role === currentRole;
    const roleWorkers = workersByRole.get(role) ?? [];
    const openTodos = snapshot.todos.filter(
      (t) => toRole(t.owner) === role && !isTerminalTodo(t)
    ).length;
    const liveWorkers = roleWorkers.filter(
      (w) => w.active || w.status === "IN_PROGRESS"
    ).length;

    let status: AgentStatus;
    if (isCurrent && loopActive) status = "live";
    else if (hasRecentSample(role)) status = "active";
    else if (runtimeBlocked && isCurrent) status = "alert";
    else status = "idle";

    const loop = (isCurrent && loopActive) || openTodos > 0 ? "running" : "idle";
    const work = isCurrent ? rt.currentAction ?? "—" : "—";

    return {
      id: role,
      name: def.name,
      role: def.role,
      hue: def.hue,
      status,
      loop,
      work,
      todos: openTodos,
      workers: liveWorkers,
      spark: buildSpark(snapshot.activitySamples, role, nowMs),
      heartbeat: heartbeatFor(snapshot, role, roleWorkers, eventEpochByRole),
      report: missionReportFor(activeMission, role),
    };
  });

  // ---- workers -------------------------------------------------------
  const workers: ContractWorker[] = workerEntries.map(({ worker }) => {
    const role = toRole(worker.owner)!;
    const status: AgentStatus =
      worker.status === "IN_PROGRESS" ? "active" : "idle";
    return {
      id: `${worker.owner}:${worker.name}`,
      agent: role,
      name: worker.displayName,
      status,
      started: parseTs(worker.updatedAt),
      progress: worker.status === "COMPLETE" ? 100 : null,
      report: stripFrontmatter(worker.content) || undefined,
    };
  });

  // ---- tasks ---------------------------------------------------------
  const tasks = buildTasks(snapshot.todos);

  // ---- events --------------------------------------------------------
  const events: ContractEvent[] = snapshot.events
    .slice(-60)
    .map((ev, i): ContractEvent => {
      const role = toRole(ev.owner) ?? firstLaneRole() ?? "";
      return {
        id: eventId(ev, i),
        at: parseTs(ev.ts),
        agent: role,
        worker: "",
        verb: ev.type || ev.status || "",
        obj: ev.title || ev.summary || ev.command || "",
      };
    });

  // ---- cadence -------------------------------------------------------
  const cadence = buildCadence(snapshot.ownerHistory, nowMs);

  // ---- alerts (synthesized) -----------------------------------------
  const alerts = buildAlerts(snapshot, agents, currentRole, runtimeBlocked, nowMs);

  // ---- metrics -------------------------------------------------------
  const throughput = snapshot.events.filter((ev) => {
    const t = parseTs(ev.ts);
    return t != null && nowMs - t <= THROUGHPUT_WINDOW_MS;
  }).length;

  const metrics: ContractMetrics = {
    sse: connected ? "open" : "closed",
    tokensPerMin: null,
    costToday: null,
    throughput,
    cpu: null,
    hotfix: snapshot.missions.filter((m) => m.type === "hotfix").length,
    eventsTotal: snapshot.events.length,
  };

  // ---- timeline marks: real per-lane activity (epoch + mission) ----------
  const marks: Record<string, Array<{ at: number; mission: string | null }>> = {};
  for (const sample of snapshot.activitySamples) {
    const at = parseTs(sample.ts);
    if (at == null) continue;
    (marks[sample.laneId] = marks[sample.laneId] ?? []).push({
      at,
      mission: sample.missionId ?? null,
    });
  }

  return {
    now: nowMs,
    agents,
    workers,
    tasks,
    events,
    cadence,
    alerts,
    metrics,
    mtrend: [],
    ctrend: [],
    marks,
  };
}

/* ---- task building ---------------------------------------------------- */

function isTerminalTodo(t: CxxTodo): boolean {
  const s = (t.status ?? "").toLowerCase();
  return s === "done" || s === "completed";
}

function buildTasks(todos: CxxTodo[]): ContractTasks {
  const running: ContractTask[] = [];
  const queued: ContractTask[] = [];
  const done: ContractTask[] = [];

  for (const t of todos) {
    const role = ((t.owner ?? "").toLowerCase().replace(/^harness-/, "")) as AgentRole;
    const status = (t.status ?? "").toLowerCase();
    const at = parseTs(t.updatedAt);
    const base: ContractTask = {
      id: t.id,
      owner: (t.owner ?? "").toUpperCase(),
      title: t.title,
      agent: role,
      status: "queued",
      progress: null,
      started: at,
      at,
    };
    if (status === "active") {
      running.push({ ...base, status: "running" });
    } else if (status === "pending" || status === "paused") {
      queued.push({ ...base, status: "queued" });
    } else if (status === "done" || status === "completed") {
      done.push({ ...base, status: "done" });
    }
  }

  // done: newest first, cap ~14
  done.sort((a, b) => (b.at ?? 0) - (a.at ?? 0));
  return { running, queued, done: done.slice(0, 14) };
}

/* ---- cadence building (mirrors Scene.tsx CadenceStrip) ---------------- */

function buildCadence(ownerHistory: OwnerPromptEntry[], nowMs: number): number[] {
  const buckets = new Array<number>(CADENCE_BUCKETS).fill(0);
  for (const entry of ownerHistory) {
    const t = parseTs(entry.ts);
    if (t == null) continue;
    const hoursAgo = Math.floor((nowMs - t) / HOUR_MS);
    if (hoursAgo < 0 || hoursAgo >= CADENCE_BUCKETS) continue;
    buckets[hoursAgo] += 1;
  }
  return buckets;
}

/* ---- alert synthesis -------------------------------------------------- */

function buildAlerts(
  snapshot: HarnessSnapshot,
  agents: ContractAgent[],
  currentRole: AgentRole | null,
  runtimeBlocked: boolean,
  nowMs: number
): ContractAlert[] {
  const alerts: ContractAlert[] = [];
  const rt = snapshot.runtime;
  let seq = 0;
  const nextId = (k: string) => `alert-${k}-${seq++}`;

  // runtime blocked OR ownerPrompt awaiting-authority -> attention
  const awaiting = (rt.ownerPrompt?.status ?? "").toLowerCase() === "awaiting-authority";
  if (runtimeBlocked || awaiting) {
    const agent = currentRole ?? "ceo";
    const msg =
      rt.currentAction ?? rt.ownerPrompt?.summary ?? (runtimeBlocked ? "runtime blocked" : "awaiting authority");
    alerts.push({
      id: nextId("rt"),
      level: "attention",
      agent,
      msg,
      at: parseTs(rt.updatedAt) ?? nowMs,
    });
  }

  // running-but-stale heartbeat -> stale
  for (const a of agents) {
    if (a.loop !== "running") continue;
    if (a.heartbeat == null) continue;
    if (nowMs - a.heartbeat > STALE_MS) {
      alerts.push({
        id: nextId("stale-" + a.id),
        level: "stale",
        agent: a.id,
        msg: "running, but no recent visible movement",
        at: a.heartbeat,
      });
    }
  }

  // protocolViolations -> attention
  for (const mission of snapshot.missions) {
    for (const v of mission.protocolViolations) {
      const agent = currentRole ?? "ceo";
      alerts.push({
        id: nextId("pv"),
        level: "attention",
        agent,
        msg: v,
        at: parseTs(mission.ts) ?? nowMs,
      });
    }
  }

  return alerts;
}

/* ---- misc ------------------------------------------------------------- */

function eventId(ev: HarnessEvent, i: number): string {
  const t = ev.ts ?? "";
  const owner = ev.owner ?? "";
  const kind = ev.type ?? ev.status ?? "";
  return `ev-${i}-${t}-${owner}-${kind}`;
}
