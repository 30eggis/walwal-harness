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

  it("does not return typing when agent_status is not running", () => {
    expect(
      deriveMinifigState("generator-backend", {
        current_agent: "generator-backend",
        agent_status: "completed",
      })
    ).toBe("idle");
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
});
