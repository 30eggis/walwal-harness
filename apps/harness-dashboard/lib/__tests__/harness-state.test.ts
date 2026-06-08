import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { mkdtempSync, mkdirSync, rmSync, utimesSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { readHarnessState } from "../harness-state";

describe("readHarnessState", () => {
  let dir: string;

  beforeEach(() => {
    dir = mkdtempSync(path.join(tmpdir(), "harness-state-"));
  });

  afterEach(() => {
    rmSync(dir, { recursive: true, force: true });
  });

  it("missing .harness: returns error banner, no crash", () => {
    const snap = readHarnessState(dir);
    expect(snap.errorBanner?.level).toBe("error");
  });

  it("corrupt progress.json: returns error banner, no crash", () => {
    mkdirSync(path.join(dir, ".harness"), { recursive: true });
    writeFileSync(path.join(dir, ".harness", "progress.json"), "{ not json");
    const snap = readHarnessState(dir);
    expect(snap.errorBanner?.level).toBe("error");
    expect(snap.errorBanner?.message_en).toContain("corrupt");
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

  it("reads explicit mission lifecycle state and marks the active child mission", () => {
    const harnessDir = path.join(dir, ".harness");
    const goalDir = path.join(harnessDir, "documents", "goal-1-auth-system");
    const submission1Dir = path.join(goalDir, "submission-1-add-sso");
    const submission2Dir = path.join(goalDir, "submission-2-visualization");
    mkdirSync(submission1Dir, { recursive: true });
    mkdirSync(submission2Dir, { recursive: true });
    writeFileSync(path.join(goalDir, "ceo.md"), "# Auth system\n");
    writeFileSync(path.join(submission1Dir, "ceo.md"), "# Add SSO\n");
    writeFileSync(path.join(submission2Dir, "ceo.md"), "# Visualization\n");
    writeFileSync(
      path.join(submission1Dir, "mission-state.json"),
      JSON.stringify({ lifecycle: "closed", active: false })
    );
    writeFileSync(
      path.join(submission2Dir, "mission-state.json"),
      JSON.stringify({ lifecycle: "active", active: true })
    );

    const missions = readHarnessState(dir).missions;
    const s1 = missions.find((mission) => mission.missionId.endsWith("submission-1-add-sso"))!;
    const s2 = missions.find((mission) => mission.missionId.endsWith("submission-2-visualization"))!;
    expect(s1.lifecycle).toBe("closed");
    expect(s1.active).toBe(false);
    expect(s2.lifecycle).toBe("active");
    expect(s2.active).toBe(true);
  });

  it("flags CXX reports that lack hired worker evidence", () => {
    const harnessDir = path.join(dir, ".harness");
    const missionDir = path.join(harnessDir, "documents", "goal-1-dashboard");
    mkdirSync(missionDir, { recursive: true });
    writeFileSync(path.join(missionDir, "ceo.md"), "# Dashboard\n");
    writeFileSync(path.join(missionDir, "cto.md"), "# CTO\n\nImplemented directly.\n");

    const mission = readHarnessState(dir).missions[0];
    expect(mission.protocolViolations).toContain("cto:missing-worker-evidence");
  });

  it("does not count roster-only hired workers as CXX evidence without a report file", () => {
    const harnessDir = path.join(dir, ".harness");
    const missionDir = path.join(harnessDir, "documents", "goal-1-dashboard");
    mkdirSync(path.join(harnessDir, "shared", "HR-Resource", "react-ui-worker"), { recursive: true });
    mkdirSync(missionDir, { recursive: true });
    writeFileSync(path.join(missionDir, "ceo.md"), "# Dashboard\n");
    writeFileSync(
      path.join(missionDir, "cto.md"),
      "# CTO\n\nWorker Evidence Manifest: cto/workers/react-ui-worker.md\n"
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
        ],
      })
    );

    const mission = readHarnessState(dir).missions[0];
    expect(mission.workers[0]).toMatchObject({ name: "react-ui-worker", reportPath: null });
    expect(mission.protocolViolations).toContain("cto:missing-worker-evidence");
  });

  it("keeps an explicit active mission visible even when it is older than the latest page", () => {
    const harnessDir = path.join(dir, ".harness");
    const docsDir = path.join(harnessDir, "documents");
    const activeDir = path.join(docsDir, "goal-0-operating");
    mkdirSync(activeDir, { recursive: true });
    writeFileSync(path.join(activeDir, "ceo.md"), "# Operating\n");
    writeFileSync(path.join(activeDir, "mission-state.json"), JSON.stringify({ lifecycle: "operating", active: true }));
    const oldDate = new Date("2026-05-01T00:00:00Z");
    utimesSync(activeDir, oldDate, oldDate);

    for (let i = 1; i <= 16; i += 1) {
      const missionDir = path.join(docsDir, `goal-${i}-done`);
      mkdirSync(missionDir, { recursive: true });
      writeFileSync(path.join(missionDir, "ceo.md"), `# Done ${i}\n`);
      writeFileSync(path.join(missionDir, "mission-state.json"), JSON.stringify({ lifecycle: "complete", active: false }));
      const ts = new Date(`2026-05-${String(i + 1).padStart(2, "0")}T00:00:00Z`);
      utimesSync(missionDir, ts, ts);
    }

    const missions = readHarnessState(dir).missions;
    expect(missions.some((mission) => mission.missionId === "goal-0-operating" && mission.active)).toBe(true);
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

  it("does not revive recently touched workers after runtime completion", () => {
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
        ],
      })
    );
    writeFileSync(
      path.join(harnessDir, "progress.json"),
      JSON.stringify({
        current_agent: null,
        next_agent: "none",
        agent_status: "completed",
        company_state: {
          workers: [{ agent: "react-ui-worker", status: "running", feature: "F1" }],
        },
      })
    );

    const workers = readHarnessState(dir).missions[0].workers;
    expect(workers[0]).toMatchObject({
      name: "react-ui-worker",
      active: false,
    });
  });

  it("does not treat a recently written docmeta draft as live worker activity without runtime state", () => {
    const harnessDir = path.join(dir, ".harness");
    const missionDir = path.join(harnessDir, "documents", "goal-1-dashboard");
    mkdirSync(path.join(missionDir, "cto", "workers"), { recursive: true });
    writeFileSync(path.join(missionDir, "ceo.md"), "# Dashboard\n");
    writeFileSync(
      path.join(missionDir, "cto", "workers", "frontend-worker.md"),
      "---\ndocmeta:\n  id: frontend-worker\n---\n\n# Worker Report\n\nEvidence is still being appended.\n"
    );
    writeFileSync(
      path.join(harnessDir, "progress.json"),
      JSON.stringify({
        current_agent: "ceo",
        agent_status: "running",
        company_state: { active_workers: 0, workers: [] },
      })
    );

    const workers = readHarnessState(dir).missions[0].workers;
    expect(workers[0]).toMatchObject({
      name: "frontend-worker",
      status: "unknown",
      active: false,
    });
  });

  it("accepts keyed company_state.workers maps from manual CXX telemetry", () => {
    const harnessDir = path.join(dir, ".harness");
    const missionDir = path.join(harnessDir, "documents", "goal-1-dashboard");
    mkdirSync(path.join(missionDir, "cqo", "workers"), { recursive: true });
    writeFileSync(path.join(missionDir, "ceo.md"), "# Dashboard\n");
    writeFileSync(
      path.join(missionDir, "cqo", "workers", "evaluator.md"),
      "---\ndocmeta:\n  id: evaluator\n---\n\n# Worker Report\n"
    );
    writeFileSync(
      path.join(harnessDir, "progress.json"),
      JSON.stringify({
        agent_status: "running",
        company_state: {
          active_workers: 1,
          workers: {
            "engineering-engineering-code-reviewer": {
              owner: "cqo",
              report: ".harness/documents/goal-1-dashboard/cqo/workers/evaluator.md",
              status: "running",
            },
          },
        },
      })
    );

    const snap = readHarnessState(dir);
    expect(snap.missions[0].workers[0]).toMatchObject({
      owner: "cqo",
      active: true,
    });
  });
});
