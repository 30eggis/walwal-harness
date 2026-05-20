import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { mkdtempSync, mkdirSync, rmSync, utimesSync, writeFileSync } from "node:fs";
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

  it("v6 NEXUS: roster includes CTO, CQO, Brainstormer", () => {
    const ids = AGENT_ROSTER.map((a) => a.id);
    expect(ids).toContain("cto");
    expect(ids).toContain("cqo");
    expect(ids).toContain("brainstormer");
  });

  it("parallel tracks, hypothesis, escalations, incidents land in the snapshot", () => {
    mkdirSync(path.join(dir, ".harness"), { recursive: true });
    writeFileSync(
      path.join(dir, ".harness", "progress.json"),
      JSON.stringify({
        sprint: { number: 3 },
        pipeline: "FULLSTACK",
        current_agent: "conductor",
        agent_status: "running",
        meetings: {
          active: [],
          cadence: "heavy",
          next_scheduled: "2026-05-08T10:00Z",
          current: { type: "incident-war-room", topic: "P0 prod outage" },
        },
        cto: {
          last_review: "2026-05-07",
          open_arch_risks: 1,
          contract_signed: { be: true, fe: false },
        },
        cqo: {
          last_audit: "2026-05-07",
          sprint_verdict: "pending",
          open_regressions: 2,
          last_scores: {
            functional: 2.9,
            visual: 2.8,
            code_quality: 2.5,
            architecture: 2.95,
            security: 3.0,
          },
        },
        service_ops: {
          monitor: { last_check: "2026-05-07", alerts_this_sprint: 4 },
          incident: {
            open: [
              { id: "INC-1", dept: "CTO", severity: "critical", message: "DB down" },
              { id: "INC-2", dept: "Operations", severity: "medium" },
            ],
          },
        },
        parallel_tracks: [
          {
            id: "T-1",
            from_meeting: "spec-review",
            to_dept: "CTO",
            to_room: "cto-team",
            status: "in_progress",
          },
          {
            id: "T-2",
            from_meeting: "spec-review",
            to_dept: "Planner",
            to_room: "coo",
            status: "dispatched",
          },
        ],
        hypothesis: {
          active: [
            { id: "H-1", brief: "Cache hit > 80%", verdict: "pending" },
            { id: "H-2", brief: "p95 < 200ms", verdict: "valid" },
          ],
        },
        escalations: {
          open: [{ id: "E-1", reason: "three-fail", message: "regression x3" }],
        },
        contracts: {
          api: { version: "v2.1.0" },
          feature_list: { total: 16, passed: 12, failed: 1 },
        },
      })
    );

    const snap = readHarnessState(dir);
    expect(snap.errorBanner).toBeNull();

    expect(snap.tracks.map((t) => t.id)).toEqual(["T-1", "T-2"]);
    expect(snap.incidents.length).toBe(2);
    expect(snap.hypothesis.length).toBe(2);
    expect(snap.escalations.length).toBe(1);
    expect(snap.contract.pipeline).toBe("FULLSTACK");
    expect(snap.contract.sprint_number).toBe(3);
    expect(snap.contract.feature_total).toBe(16);
    expect(snap.contract.contract_signed).toEqual({ be: true, fe: false });
    expect(snap.evalScores?.code_quality).toBe(2.5);
    expect(snap.meetings.cadence).toBe("heavy");
    expect(snap.meetings.current?.type).toBe("incident-war-room");

    // CTO has an open incident → CTO-dept agents go red-alert; Service-Ops
    // is on-call and is *always* red when any incident is open.
    const stateOf = (id: string) => snap.agents.find((a) => a.id === id)!.minifigState;
    expect(stateOf("cto")).toBe("red-alert");
    expect(stateOf("service-ops")).toBe("red-alert");
    expect(stateOf("evaluator-visual")).toBe("idle"); // CQO dept untouched
  });

  it("buildArchive reads verdict.json when present", () => {
    const sprintDir = path.join(dir, ".harness", "archive", "sprint-1");
    mkdirSync(sprintDir, { recursive: true });
    writeFileSync(path.join(sprintDir, "verdict.json"), JSON.stringify({ result: "PASS" }));
    mkdirSync(path.join(dir, ".harness"), { recursive: true });
    writeFileSync(
      path.join(dir, ".harness", "progress.json"),
      JSON.stringify({ sprint: { number: 1 } })
    );

    const snap = readHarnessState(dir);
    expect(snap.archive.all.find((e) => e.dir === "sprint-1")?.result).toBe("PASS");
  });

  it("marks in-place goal document updates as submission only after the owner prompt", () => {
    const harnessDir = path.join(dir, ".harness");
    const missionDir = path.join(harnessDir, "documents", "goal-1-auth-system");
    mkdirSync(missionDir, { recursive: true });
    writeFileSync(path.join(missionDir, "ceo.md"), "# Auth system\n");
    const beforePrompt = new Date("2026-05-20T01:00:00Z");
    utimesSync(missionDir, beforePrompt, beforePrompt);

    writeFileSync(
      path.join(harnessDir, "progress.json"),
      JSON.stringify({
        owner_prompt: {
          command: "submission",
          summary: "/submission add SSO",
          received_at: "2026-05-20T01:05:00Z",
          status: "routing",
        },
      })
    );

    expect(readHarnessState(dir).missions[0].type).toBe("goal");

    const afterPrompt = new Date("2026-05-20T01:06:00Z");
    utimesSync(missionDir, afterPrompt, afterPrompt);

    expect(readHarnessState(dir).missions[0].type).toBe("submission");
  });

  it("keeps explicit submission subdirectories as submission without relabeling the parent goal", () => {
    const harnessDir = path.join(dir, ".harness");
    const goalDir = path.join(harnessDir, "documents", "goal-1-auth-system");
    const submissionDir = path.join(goalDir, "submission-1-add-sso");
    mkdirSync(submissionDir, { recursive: true });
    writeFileSync(path.join(goalDir, "ceo.md"), "# Auth system\n");
    writeFileSync(path.join(submissionDir, "ceo.md"), "# Add SSO\n");
    utimesSync(goalDir, new Date("2026-05-20T01:00:00Z"), new Date("2026-05-20T01:00:00Z"));
    utimesSync(submissionDir, new Date("2026-05-20T01:06:00Z"), new Date("2026-05-20T01:06:00Z"));

    writeFileSync(
      path.join(harnessDir, "progress.json"),
      JSON.stringify({
        owner_prompt: {
          command: "submission",
          summary: "/submission add SSO",
          received_at: "2026-05-20T01:05:00Z",
          status: "routing",
        },
      })
    );

    const missions = readHarnessState(dir).missions;
    expect(missions[0].missionId).toBe("goal-1-auth-system/submission-1-add-sso");
    expect(missions[0].type).toBe("submission");
    expect(missions.find((mission) => mission.missionId === "goal-1-auth-system")?.type).toBe("goal");
  });

  it("positions only hired HR-Resource workers and marks active workers", () => {
    const harnessDir = path.join(dir, ".harness");
    const missionDir = path.join(harnessDir, "documents", "goal-1-dashboard");
    mkdirSync(path.join(missionDir, "cto", "workers"), { recursive: true });
    mkdirSync(path.join(harnessDir, "shared", "HR-Resource", "react-ui-worker"), { recursive: true });
    writeFileSync(path.join(missionDir, "ceo.md"), "# Dashboard\n");
    writeFileSync(
      path.join(missionDir, "cto", "workers", "react-ui-worker.md"),
      "## Status\nIN_PROGRESS\n"
    );
    writeFileSync(
      path.join(harnessDir, "shared", "HR-Resource", "react-ui-worker", "SKILL.md"),
      "# React UI Worker\n"
    );
    writeFileSync(
      path.join(harnessDir, "shared", "hr-roster.json"),
      JSON.stringify({
        hired: [
          {
            worker: "react-ui-worker",
            owner: "cto",
            skillPath: ".harness/shared/HR-Resource/react-ui-worker/SKILL.md",
          },
          {
            worker: "missing-worker",
            owner: "cto",
            skillPath: ".harness/shared/HR-Resource/missing-worker/SKILL.md",
          },
        ],
      })
    );
    writeFileSync(
      path.join(harnessDir, "progress.json"),
      JSON.stringify({
        company_state: {
          workers: [{ agent: "react-ui-worker", status: "running", feature: "F1" }],
        },
      })
    );

    const workers = readHarnessState(dir).missions[0].workers;
    expect(workers.map((w) => w.name)).toEqual(["react-ui-worker"]);
    expect(workers[0]).toMatchObject({
      owner: "cto",
      hired: true,
      active: true,
      sourcePath: ".harness/shared/HR-Resource/react-ui-worker/SKILL.md",
    });
  });
});
