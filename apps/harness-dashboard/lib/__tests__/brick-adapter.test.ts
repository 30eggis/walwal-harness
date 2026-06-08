import { describe, expect, it } from "vitest";
import { toContractState } from "../brick/adapter";
import type { HarnessSnapshot } from "../types";

function snapshotWithActivity(ts: string): HarnessSnapshot {
  return {
    version: "test",
    ts: new Date().toISOString(),
    projectName: "demo",
    projectPath: "/tmp/demo",
    errorBanner: null,
    runtime: {
      currentAgent: null,
      agentStatus: "pending",
      nextAgent: null,
      updatedAt: null,
      conductorState: "running",
      ownerPrompt: null,
    },
    incidents: [],
    missions: [],
    ownerHistory: [],
    gotchas: [],
    conventions: [],
    todos: [],
    events: [],
    activitySamples: [{ ts, laneId: "cto", count: 1, hotfix: false, missionId: "goal-1" }],
    files: [],
  };
}

describe("toContractState", () => {
  it("does not mark a role active from stale historical activity samples", () => {
    const now = Date.parse("2026-06-05T00:10:00Z");
    const state = toContractState(snapshotWithActivity("2026-06-05T00:00:00Z"), true, now);
    expect(state.agents.find((agent) => agent.id === "cto")?.status).toBe("idle");
  });

  it("marks a role active from recent activity samples", () => {
    const now = Date.parse("2026-06-05T00:01:00Z");
    const state = toContractState(snapshotWithActivity("2026-06-05T00:00:30Z"), true, now);
    expect(state.agents.find((agent) => agent.id === "cto")?.status).toBe("active");
  });
});
