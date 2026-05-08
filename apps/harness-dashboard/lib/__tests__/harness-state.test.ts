import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { readHarnessState } from "../harness-state";
import { AGENT_ROSTER } from "../agent-roster";

describe("readHarnessState", () => {
  let dir: string;

  beforeEach(() => {
    dir = mkdtempSync(path.join(tmpdir(), "harness-state-"));
  });

  afterEach(() => {
    rmSync(dir, { recursive: true, force: true });
  });

  it("valid progress.json: derives typing for current_agent, talking for meetings.active, idle for the rest", () => {
    mkdirSync(path.join(dir, ".harness"), { recursive: true });
    writeFileSync(
      path.join(dir, ".harness", "progress.json"),
      JSON.stringify({
        sprint: { number: 1 },
        current_agent: "generator-backend",
        agent_status: "running",
        meetings: { active: ["planner"], cadence: "normal", next_scheduled: null },
        cto: { last_review: "2026-05-07", open_arch_risks: 0 },
        cqo: { last_audit: null, sprint_verdict: "pending", open_regressions: 0 },
        service_ops: { monitor: { last_check: "2026-05-07", alerts_this_sprint: 0 } },
        goals: {
          active_id: "g1",
          list: [{ id: "g1", title: "Brick Office MVP", description: "Phase C launch" }],
          current_adherence: 0.6,
        },
      })
    );

    const snap = readHarnessState(dir);
    expect(snap.errorBanner).toBeNull();
    expect(snap.agents.length).toBe(AGENT_ROSTER.length);
    expect(snap.agents.map((a) => a.id).sort()).toEqual(
      AGENT_ROSTER.map((a) => a.id).sort()
    );
    const stateOf = (id: string) => snap.agents.find((a) => a.id === id)!.minifigState;
    expect(stateOf("generator-backend")).toBe("typing");
    expect(stateOf("planner")).toBe("talking");
    expect(stateOf("dispatcher")).toBe("idle");
    expect(snap.rooms.length).toBe(7);

    const planner = snap.agents.find((a) => a.id === "planner")!;
    expect(planner.room).toBe("meeting");
    expect(planner.homeRoom).toBe("coo");

    const meetingRoom = snap.rooms.find((r) => r.id === "meeting")!;
    expect(meetingRoom.seatLayout).toBeDefined();
    expect(meetingRoom.seatLayout!.occupants).toContain("planner");

    expect(snap.goal).not.toBeNull();
    expect(snap.goal!.title).toBe("Brick Office MVP");
  });

  it("missing .harness: returns error banner, no crash", () => {
    const snap = readHarnessState(dir);
    expect(snap.errorBanner?.level).toBe("error");
    expect(snap.agents.length).toBe(AGENT_ROSTER.length);
  });

  it("corrupt progress.json: returns error banner, no crash", () => {
    mkdirSync(path.join(dir, ".harness"), { recursive: true });
    writeFileSync(path.join(dir, ".harness", "progress.json"), "{ not json");
    const snap = readHarnessState(dir);
    expect(snap.errorBanner?.level).toBe("error");
    expect(snap.errorBanner?.message_en).toContain("corrupt");
    expect(snap.agents.length).toBe(AGENT_ROSTER.length);
  });
});
