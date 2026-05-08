import type { AgentId, Dept, MinifigState } from "./types";

export interface ProgressSlice {
  current_agent?: AgentId | null;
  next_agent?: AgentId | null;
  agent_status?: string;
  failure?: { agent?: AgentId | null; message?: string | null } | null;
  meetings?: { active?: AgentId[] };
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

function isAgentRunningTrack(
  agentId: string,
  conductor: ProgressSlice["conductor"]
): boolean {
  const tracks = conductor?.tracks ?? [];
  return tracks.some(
    (t) =>
      t.owner === agentId &&
      (t.status === "running" || t.status === "in_progress" || t.status === "active")
  );
}

function isAgentQueuedTrack(
  agentId: string,
  conductor: ProgressSlice["conductor"]
): boolean {
  const tracks = conductor?.tracks ?? [];
  return tracks.some((t) => t.owner === agentId && t.status === "pending");
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
  if (progress.failure?.agent === agentId) return "red-alert";
  if (ctx.dept && ctx.incidentDepts && ctx.incidentDepts.size > 0) {
    if (ctx.dept === "Operations" || ctx.incidentDepts.has(ctx.dept)) {
      return "red-alert";
    }
  }
  const inMeeting = progress.meetings?.active?.includes(agentId) ?? false;
  if (inMeeting) return "talking";

  // Parallel-typing signals (any one of these means the agent is working).
  if (
    progress.current_agent === agentId &&
    progress.agent_status === "running"
  ) {
    return "typing";
  }
  if (isAgentRunningTrack(agentId, progress.conductor)) {
    return "typing";
  }
  if (parseSpawnAgent(progress.conductor?.current_action) === agentId) {
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
    progress.next_agent === agentId &&
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
