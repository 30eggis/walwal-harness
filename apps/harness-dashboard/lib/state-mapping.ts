import type { AgentId, MinifigState } from "./types";

export interface ProgressSlice {
  current_agent?: AgentId | null;
  agent_status?: string;
  failure?: { agent?: AgentId | null; message?: string | null } | null;
  meetings?: { active?: AgentId[] };
  service_ops?: { incident?: { open?: Array<{ id: string; dept?: string }> } };
}

// Priority: red-alert > talking > typing > idle.
// red-alert wins because incidents/failures must dominate the visual field.
// talking wins over typing because meetings teleport overrides desk presence.
export function deriveMinifigState(
  agentId: AgentId,
  progress: ProgressSlice | null
): MinifigState {
  if (!progress) return "idle";
  if (progress.failure?.agent === agentId) return "red-alert";
  const inMeeting = progress.meetings?.active?.includes(agentId) ?? false;
  if (inMeeting) return "talking";
  const isCurrent =
    progress.current_agent === agentId &&
    progress.agent_status === "running";
  if (isCurrent) return "typing";
  return "idle";
}

export function pickTalkingPreview(agentId: AgentId): string {
  // Sprint 2 will pull this from progress.log; for Sprint 1 we surface a stub
  // so the speech-bubble component has a sensible default.
  return `${agentId}…`;
}
