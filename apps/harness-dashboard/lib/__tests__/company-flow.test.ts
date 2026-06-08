import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { execFileSync } from "node:child_process";
import { existsSync, mkdtempSync, mkdirSync, readFileSync, rmSync, utimesSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const repoRoot = path.resolve(__dirname, "../../../../");
const hasHarnessShellFixtures =
  existsSync(path.join(repoRoot, "scripts", "lib", "harness-progress-migrate.sh")) &&
  existsSync(path.join(repoRoot, "assets", "templates", "config.json"));
const describeHarnessShell = hasHarnessShellFixtures ? describe : describe.skip;

function runBash(script: string, projectRoot: string, args: string[] = []) {
  return execFileSync("bash", [path.join(repoRoot, script), projectRoot, ...args], {
    cwd: repoRoot,
    encoding: "utf8",
  });
}

function writeState(projectRoot: string, progress: unknown, configOverrides: Record<string, unknown> = {}) {
  mkdirSync(path.join(projectRoot, ".harness", "actions", "meetings"), { recursive: true });

  const config = JSON.parse(
    readFileSync(path.join(repoRoot, "assets", "templates", "config.json"), "utf8")
  ) as Record<string, unknown>;
  Object.assign(config, configOverrides);

  writeFileSync(path.join(projectRoot, ".harness", "config.json"), JSON.stringify(config, null, 2));
  writeFileSync(path.join(projectRoot, ".harness", "progress.json"), JSON.stringify(progress, null, 2));
}

describeHarnessShell("company-loop shell flows", () => {
  let dir: string;

  beforeEach(() => {
    dir = mkdtempSync(path.join(tmpdir(), "walwal-company-"));
  });

  afterEach(() => {
    rmSync(dir, { recursive: true, force: true });
  });

  it("migrate_progress_schema normalizes legacy runtime mode while removing meeting decision mode", () => {
    mkdirSync(path.join(dir, ".harness"), { recursive: true });
    writeFileSync(
      path.join(dir, ".harness", "progress.json"),
      JSON.stringify(
        {
          mode: "team",
          meetings: {
            requested_mode: "hypothesis",
            decision: {
              mode: "legacy",
              owner: "planner",
              action_type: "hypothesis-validation",
              tracks: [],
              rendezvous: null,
            },
          },
        },
        null,
        2
      )
    );

    runBash("scripts/lib/harness-progress-migrate.sh", path.join(dir, ".harness", "progress.json"));

    const migrated = JSON.parse(readFileSync(path.join(dir, ".harness", "progress.json"), "utf8"));
    expect(migrated.mode).toBe("company");
    expect(migrated.meetings.requested_mode).toBeUndefined();
    expect(migrated.meetings.decision.mode).toBeUndefined();
    expect(Array.isArray(migrated.meetings.decision.tracks)).toBe(true);
  });

  it("read-tracks falls back to conductor.tracks when fork_context is missing", () => {
    writeState(dir, {
      current_agent: "meeting-manager",
      agent_status: "completed",
      next_agent: "meeting-manager",
      mode: "auto",
      pipeline: "FULLSTACK",
      workflow: { stage: "followup-review" },
      meetings: {
        requested_type: "followup-review",
        requested_reason: "rendezvous",
        active: ["meeting-manager"],
        decision: {
          owner: "cto",
          action_type: "bugfix",
          rationale: "test",
          evidence: [],
          drift_classification: "implementation_drift",
          source_path: null,
          tracks: [],
          rendezvous: null,
        },
        fork_context: null,
        fork_meeting_id: null,
      },
      conductor: {
        tracks: [
          {
            id: "track-1",
            owner: "cto",
            action_type: "bugfix",
            deliverable: "hotfix-result",
            deliverable_path: "/tmp/hotfix.md",
            status: "completed",
          },
          {
            id: "track-2",
            owner: "planner",
            action_type: "hypothesis-validation",
            deliverable: "validation-report",
            deliverable_path: "/tmp/report.md",
            status: "completed",
          },
        ],
        rendezvous: { type: "followup-review", when: "next_cadence" },
        fork_meeting_id: "M-20260508T080000Z",
      },
      planner: { requested_mode: null, last_brief: "hypothesis:done" },
      service_ops: { auto_retro: { last_report: null, open_recommendations: 0 }, monitor: { alerts_this_sprint: 0 }, incident: { open: [] }, drift_classification: null },
      goals: { current_adherence: null },
      cqo: { sprint_verdict: "pending", open_regressions: 0, axes_below_threshold: [] },
      cto: { open_hotfixes: 0 },
      artifacts: { "plan.md": { status: "pending" }, "feature-list.json": { status: "pending" }, "api-contract.json": { status: "pending" } },
    });

    const tracks = JSON.parse(runBash("scripts/harness-meeting-doc.sh", dir, ["read-tracks"]));
    expect(tracks).toHaveLength(2);
    expect(tracks[0].owner).toBe("cto");
    expect(tracks[1].owner).toBe("planner");
  });

  it("followup-review prepare preserves fork context and persists the fallback context", () => {
    writeState(dir, {
      current_agent: "meeting-manager",
      agent_status: "completed",
      next_agent: "meeting-manager",
      mode: "auto",
      pipeline: "FULLSTACK",
      workflow: { stage: "followup-review" },
      meetings: {
        requested_type: "followup-review",
        requested_reason: "rendezvous",
        active: ["meeting-manager"],
        decision: {
          owner: "cto",
          action_type: "bugfix",
          rationale: "test",
          evidence: [],
          drift_classification: "implementation_drift",
          source_path: null,
          tracks: [],
          rendezvous: null,
        },
        requested_tracks: [],
        requested_rendezvous: null,
        fork_context: null,
        fork_meeting_id: null,
      },
      conductor: {
        tracks: [
          {
            id: "track-1",
            owner: "cto",
            action_type: "bugfix",
            deliverable: "hotfix-result",
            deliverable_path: "/tmp/hotfix.md",
            status: "completed",
          },
          {
            id: "track-2",
            owner: "planner",
            action_type: "hypothesis-validation",
            deliverable: "validation-report",
            deliverable_path: "/tmp/report.md",
            status: "completed",
          },
        ],
        rendezvous: { type: "followup-review", when: "next_cadence" },
        fork_meeting_id: "M-20260508T080000Z",
      },
      planner: { requested_mode: null, last_brief: "hypothesis:done" },
      service_ops: { auto_retro: { last_report: null, open_recommendations: 0 }, monitor: { alerts_this_sprint: 0 }, incident: { open: [] }, drift_classification: null },
      goals: { current_adherence: null },
      cqo: { sprint_verdict: "pending", open_regressions: 0, axes_below_threshold: [] },
      cto: { open_hotfixes: 0 },
      artifacts: { "plan.md": { status: "pending" }, "feature-list.json": { status: "pending" }, "api-contract.json": { status: "pending" } },
    });

    const recordPath = runBash("scripts/harness-meeting-doc.sh", dir, ["prepare"]).trim();
    const record = readFileSync(path.join(dir, recordPath), "utf8");
    expect(record).toContain("## Fork Context (v6.2)");
    expect(record).toContain("hotfix-result");
    expect(record).toContain("validation-report");

    const progress = JSON.parse(readFileSync(path.join(dir, ".harness", "progress.json"), "utf8"));
    expect(progress.meetings.fork_context.prior_tracks).toHaveLength(2);
    expect(progress.meetings.fork_context.fork_meeting_id).toBe("M-20260508T080000Z");
  });

  it("planner hypothesis-verdict completes by returning to meeting-manager and clearing the stale request", () => {
    writeState(dir, {
      current_agent: "planner",
      agent_status: "completed",
      next_agent: "planner",
      mode: "auto",
      pipeline: "FULLSTACK",
      workflow: { stage: "coo-hypothesis-verdict" },
      meetings: {
        requested_type: "followup-review",
        requested_reason: "rendezvous",
        active: ["meeting-manager"],
        decision: {
          owner: "cto",
          action_type: "bugfix",
          rationale: "test",
          evidence: [],
          drift_classification: "implementation_drift",
          source_path: null,
          tracks: [],
          rendezvous: null,
        },
        fork_context: null,
        fork_meeting_id: "M-20260508T080000Z",
      },
      conductor: {
        tracks: [
          {
            id: "track-1",
            owner: "cto",
            action_type: "bugfix",
            deliverable: "hotfix-result",
            deliverable_path: "/tmp/hotfix.md",
            status: "completed",
          },
          {
            id: "track-2",
            owner: "planner",
            action_type: "hypothesis-validation",
            deliverable: "validation-report",
            deliverable_path: "/tmp/report.md",
            status: "completed",
          },
        ],
        rendezvous: { type: "followup-review", when: "next_cadence" },
        fork_meeting_id: "M-20260508T080000Z",
      },
      planner: { requested_mode: "hypothesis-verdict", last_brief: "hypothesis:done" },
      service_ops: { auto_retro: { last_report: null, open_recommendations: 0 }, monitor: { alerts_this_sprint: 0 }, incident: { open: [] }, drift_classification: null },
      goals: { current_adherence: null },
      cqo: { sprint_verdict: "pending", open_regressions: 0, axes_below_threshold: [] },
      cto: { open_hotfixes: 0 },
      artifacts: { "plan.md": { status: "pending" }, "feature-list.json": { status: "pending" }, "api-contract.json": { status: "pending" } },
    });

    runBash("scripts/conductor-tick.sh", dir);

    const progress = JSON.parse(readFileSync(path.join(dir, ".harness", "progress.json"), "utf8"));
    expect(progress.next_agent).toBe("meeting-manager");
    expect(progress.workflow.stage).toBe("followup-review");
    expect(progress.planner.requested_mode).toBeNull();
    expect(progress.meetings.requested_type).toBe("followup-review");
  });

  it("company terminal transitions only update the newest current mission state", () => {
    writeState(dir, {
      current_agent: "ceo",
      agent_status: "running",
      next_agent: "none",
      owner_prompt: { status: "routing" },
      company_state: { state: "running", active_workers: 0 },
      conductor: { state: "running", tracks: [] },
    });
    const docs = path.join(dir, ".harness", "documents");
    const oldMission = path.join(docs, "goal-1-old");
    const newMission = path.join(docs, "goal-2-new");
    mkdirSync(oldMission, { recursive: true });
    mkdirSync(newMission, { recursive: true });
    const oldState = path.join(oldMission, "mission-state.json");
    const newState = path.join(newMission, "mission-state.json");
    writeFileSync(oldState, JSON.stringify({ lifecycle: "active", active: true }));
    writeFileSync(newState, JSON.stringify({ lifecycle: "active", active: true }));
    const oldDate = new Date("2026-05-01T00:00:00Z");
    const newDate = new Date("2026-05-02T00:00:00Z");
    utimesSync(oldState, oldDate, oldDate);
    utimesSync(newState, newDate, newDate);

    runBash("scripts/harness-company-block.sh", dir, ["needs-key"]);
    expect(JSON.parse(readFileSync(oldState, "utf8")).lifecycle).toBe("active");
    expect(JSON.parse(readFileSync(newState, "utf8")).lifecycle).toBe("blocked");

    runBash("scripts/harness-company-complete.sh", dir, ["provided-key"]);
    expect(JSON.parse(readFileSync(oldState, "utf8")).lifecycle).toBe("active");
    expect(JSON.parse(readFileSync(newState, "utf8")).lifecycle).toBe("complete");
  });
});
