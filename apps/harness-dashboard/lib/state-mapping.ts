import type { AgentId, Dept, MinifigState } from "./types";

const AGENT_ALIASES: Record<string, AgentId[]> = {
  ceo: ["dispatcher", "brainstormer"],
  dispatcher: ["dispatcher"],
  brainstormer: ["brainstormer"],
  coo: ["planner", "coo-developer", "documentationer"],
  planner: ["planner"],
  cdo: ["generator-designer"],
  cto: ["cto", "conductor", "generator-backend", "generator-frontend", "generator-designer", "generator-devops"],
  cqo: ["cqo", "evaluator-functional", "evaluator-visual", "evaluator-code-quality", "evaluator-architecture", "evaluator-security"],
  ops: ["service-ops"],
  "service-ops": ["service-ops"],
};

export interface ProgressSlice {
  current_agent?: string | null;
  next_agent?: string | null;
  agent_status?: string;
  failure?: { agent?: string | null; message?: string | null } | null;
  meetings?: { active?: string[] };
  service_ops?: {
    incident?: { open?: Array<{ id: string; dept?: string }> };
    monitor?: { stream_active?: boolean; stream_target?: string | null };
    requested_mode?: string | null;
  };
  // v6 NEXUS parallel mode (CLAUDE.md §Parallel Tracks). When tracks have
  // owners with status=running, those agents are concurrently working —
  // not just current_agent. The dashboard treats every running owner as
  // typing so the parallel reality is visible.
  conductor?: {
    state?: string;
    current_action?: string | null;
    tracks?: Array<{ owner?: string; status?: string }>;
  };
}

export interface DeriveContext {
  // Distinct departments with at least one open incident — pre-computed by
  // harness-state.ts so the mapping doesn't iterate the array per agent.
  incidentDepts?: Set<string>;
  // The agent's own department (passed in because we map by department, not
  // by the bare AgentId).
  dept?: Dept | "Operations";
}

// `conductor.current_action` carries strings like:
//   "spawn:generator-frontend"
//   "spawn:coo-developer:F12-006"
//   "spawn:generator-backend (foundation F-101)"
// Pull out the agent id from the head.
export function parseSpawnAgent(action: string | null | undefined): string | null {
  if (!action) return null;
  const m = /^spawn:([a-z][a-z0-9-]*)/i.exec(action);
  return m ? m[1].toLowerCase() : null;
}

function agentMatches(agentId: string, raw: string | null | undefined): boolean {
  if (!raw) return false;
  const key = raw.toLowerCase();
  if (key === agentId) return true;
  return AGENT_ALIASES[key]?.includes(agentId as AgentId) ?? false;
}

function isAgentRunningTrack(
  agentId: string,
  conductor: ProgressSlice["conductor"]
): boolean {
  const tracks = conductor?.tracks ?? [];
  return tracks.some(
    (t) =>
      agentMatches(agentId, t.owner) &&
      (t.status === "running" || t.status === "in_progress" || t.status === "active")
  );
}

function isAgentQueuedTrack(
  agentId: string,
  conductor: ProgressSlice["conductor"]
): boolean {
  const tracks = conductor?.tracks ?? [];
  return tracks.some((t) => agentMatches(agentId, t.owner) && t.status === "pending");
}

// Priority: red-alert > talking > typing > queued > idle.
// red-alert wins because incidents/failures must dominate the visual field.
// talking wins over typing because meetings teleport overrides desk presence.
// typing now reflects v6 NEXUS *parallel* mode — multiple agents can be
// concurrently working, all of them get the typing aura.
// queued makes autonomous handoff visible: when the company already assigned
// a next department, that department sits at its desk even before the worker
// process emits its first log line.
export function deriveMinifigState(
  agentId: AgentId,
  progress: ProgressSlice | null,
  ctx: DeriveContext = {}
): MinifigState {
  if (!progress) return "idle";
  if (agentMatches(agentId, progress.failure?.agent)) return "red-alert";
  if (ctx.dept && ctx.incidentDepts && ctx.incidentDepts.size > 0) {
    if (ctx.dept === "Operations" || ctx.incidentDepts.has(ctx.dept)) {
      return "red-alert";
    }
  }
  const inMeeting = progress.meetings?.active?.some((id) => agentMatches(agentId, id)) ?? false;
  if (inMeeting) return "talking";

  // Parallel-typing signals (any one of these means the agent is working).
  if (
    agentMatches(agentId, progress.current_agent) &&
    progress.agent_status === "running"
  ) {
    return "typing";
  }
  if (isAgentRunningTrack(agentId, progress.conductor)) {
    return "typing";
  }
  if (agentMatches(agentId, parseSpawnAgent(progress.conductor?.current_action))) {
    return "typing";
  }
  // G-006: service-ops co-spawned in monitor mode is actively streaming.
  if (
    agentId === "service-ops" &&
    progress.service_ops?.monitor?.stream_active === true
  ) {
    return "typing";
  }
  if (
    agentMatches(agentId, progress.next_agent) &&
    progress.agent_status !== "blocked" &&
    progress.agent_status !== "failed"
  ) {
    return "queued";
  }
  if (isAgentQueuedTrack(agentId, progress.conductor)) {
    return "queued";
  }

  return "idle";
}

export function pickTalkingPreview(agentId: AgentId): string {
  // Sprint 2 will pull this from progress.log; for Sprint 1 we surface a stub
  // so the speech-bubble component has a sensible default.
  return `${agentId}…`;
}
