import { describe, it, expect } from "vitest";
import { deriveMinifigState } from "../state-mapping";

describe("deriveMinifigState", () => {
  it("returns idle when there is no progress data", () => {
    expect(deriveMinifigState("planner", null)).toBe("idle");
  });

  it("returns typing when agent is current and running", () => {
    expect(
      deriveMinifigState("generator-backend", {
        current_agent: "generator-backend",
        agent_status: "running",
      })
    ).toBe("typing");
  });

  it("maps v7 CEO alias to dispatcher and brainstormer", () => {
    const progress = {
      current_agent: "ceo",
      agent_status: "running",
    };
    expect(deriveMinifigState("dispatcher", progress)).toBe("typing");
    expect(deriveMinifigState("brainstormer", progress)).toBe("typing");
  });

  it("maps v7 CXX aliases to their dashboard departments", () => {
    expect(
      deriveMinifigState("generator-designer", {
        current_agent: "cdo",
        agent_status: "running",
      })
    ).toBe("typing");
    expect(
      deriveMinifigState("service-ops", {
        next_agent: "ops",
        agent_status: "pending",
      })
    ).toBe("queued");
  });

  it("does not return typing when agent_status is not running", () => {
    expect(
      deriveMinifigState("generator-backend", {
        current_agent: "generator-backend",
        agent_status: "completed",
      })
    ).toBe("idle");
  });

  it("returns queued when agent is assigned as next_agent", () => {
    expect(
      deriveMinifigState("cto", {
        current_agent: "planner",
        next_agent: "cto",
        agent_status: "completed",
      })
    ).toBe("queued");
  });

  it("returns talking when agent is in meetings.active", () => {
    expect(
      deriveMinifigState("planner", {
        meetings: { active: ["planner", "dispatcher"] },
      })
    ).toBe("talking");
  });

  it("talking wins over typing when both apply", () => {
    expect(
      deriveMinifigState("planner", {
        current_agent: "planner",
        agent_status: "running",
        meetings: { active: ["planner"] },
      })
    ).toBe("talking");
  });

  it("red-alert wins over everything", () => {
    expect(
      deriveMinifigState("evaluator-functional", {
        current_agent: "evaluator-functional",
        agent_status: "running",
        meetings: { active: ["evaluator-functional"] },
        failure: { agent: "evaluator-functional", message: "regression" },
      })
    ).toBe("red-alert");
  });

  it("Service-Ops always goes red-alert when any incident is open", () => {
    // Even if the incident's dept is unknown, Service-Ops is the on-call
    // department and should reflect the alert state.
    expect(
      deriveMinifigState(
        "service-ops",
        { current_agent: null, agent_status: "idle" },
        { dept: "Operations", incidentDepts: new Set(["CTO"]) }
      )
    ).toBe("red-alert");
  });

  it("dept-matching incident lights up the dept's agents", () => {
    expect(
      deriveMinifigState(
        "generator-backend",
        { current_agent: null },
        { dept: "CTO", incidentDepts: new Set(["CTO"]) }
      )
    ).toBe("red-alert");
  });

  it("agents in unrelated dept stay idle when incident is elsewhere", () => {
    expect(
      deriveMinifigState(
        "evaluator-visual",
        { current_agent: null },
        { dept: "CQO", incidentDepts: new Set(["CTO"]) }
      )
    ).toBe("idle");
  });

  it("v6 parallel: conductor.tracks running owners are typing", () => {
    expect(
      deriveMinifigState("planner", {
        current_agent: "coo-developer",
        agent_status: "running",
        conductor: {
          tracks: [
            { owner: "planner", status: "running" },
            { owner: "documentationer", status: "completed" },
          ],
        },
      })
    ).toBe("typing");
  });

  it("v6 parallel: conductor.tracks pending owners are queued", () => {
    expect(
      deriveMinifigState("documentationer", {
        current_agent: "planner",
        agent_status: "running",
        conductor: {
          tracks: [
            { owner: "planner", status: "running" },
            { owner: "documentationer", status: "pending" },
          ],
        },
      })
    ).toBe("queued");
  });

  it("v6 parallel: conductor.current_action spawn target is typing", () => {
    // current_agent has finished the previous tick; the next agent appears in
    // current_action and must already light up so the office never goes dark.
    expect(
      deriveMinifigState("generator-backend", {
        current_agent: "cto",
        agent_status: "completed",
        conductor: { current_action: "spawn:generator-backend (foundation F-101)" },
      })
    ).toBe("typing");
  });

  it("G-006: service-ops with stream_active=true is typing", () => {
    expect(
      deriveMinifigState("service-ops", {
        current_agent: "generator-frontend",
        agent_status: "running",
        service_ops: { monitor: { stream_active: true, stream_target: "generator-frontend" } },
      })
    ).toBe("typing");
  });

  it("agents not involved stay idle (default-to-desk handled in 3D)", () => {
    expect(
      deriveMinifigState("evaluator-architecture", {
        current_agent: "generator-backend",
        agent_status: "running",
        conductor: { tracks: [{ owner: "planner", status: "running" }] },
      })
    ).toBe("idle");
  });
});
