/**
 * Sandbox end-to-end test for the two harness usage modes.
 *
 * Creates two real sample projects under ~/tmp via the actual installer
 * (bin/init.js), then drives the INSTALLED hooks/scripts and simulates a
 * faithful v7 CEO/CXX document flow. After each milestone it computes the
 * dashboard snapshot through the dashboard's own readHarnessState() and asserts
 * the values the live Scene.tsx renders, plus the Stop-hook autonomy behavior.
 *
 * Gated behind WALWAL_E2E=1 so it stays out of the fast unit suite and only
 * runs (and writes to the OS temp dir, or WALWAL_E2E_ROOT when set) when explicitly requested:
 *   WALWAL_E2E=1 npx vitest run sandbox-e2e
 */
import { describe, it, expect, beforeAll } from "vitest";
import { execFileSync } from "node:child_process";
import {
  existsSync,
  mkdirSync,
  readFileSync,
  writeFileSync,
  appendFileSync,
  rmSync,
  lstatSync,
} from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { readHarnessState } from "../harness-state";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const repoRoot = path.resolve(__dirname, "../../../../");

const gate = process.env.WALWAL_E2E === "1" ? describe : describe.skip;

const NOTES = `\n\n## Implementation Notes\n\n### Design Decisions\n- None\n\n### Deviations\n- None\n\n### Tradeoffs\n- None\n\n### Open Questions\n- None\n`;

function init(sbx: string) {
  rmSync(sbx, { recursive: true, force: true });
  mkdirSync(sbx, { recursive: true });
  execFileSync("node", [path.join(repoRoot, "bin", "init.js"), "init", "--force", "--project-root", sbx], {
    cwd: repoRoot,
    encoding: "utf8",
    stdio: "pipe",
  });
}

/** Run an installed hook script, feeding hook JSON on stdin. Returns stdout. */
function runHook(sbx: string, script: string, input: Record<string, unknown>): string {
  try {
    return execFileSync("bash", [path.join(sbx, "scripts", script)], {
      input: JSON.stringify(input),
      encoding: "utf8",
      stdio: ["pipe", "pipe", "pipe"],
    });
  } catch (e: unknown) {
    // hooks exit 0 normally; capture stdout even on nonzero just in case
    const err = e as { stdout?: string };
    return err.stdout ?? "";
  }
}

/** Run an installed runtime script with positional args. */
function runScript(sbx: string, script: string, args: string[] = []): string {
  return execFileSync("bash", [path.join(sbx, "scripts", script), ...args], {
    cwd: sbx,
    encoding: "utf8",
    stdio: ["pipe", "pipe", "pipe"],
  });
}

function progress(sbx: string): Record<string, any> {
  return JSON.parse(readFileSync(path.join(sbx, ".harness", "progress.json"), "utf8"));
}

function snap(sbx: string, label: string) {
  const s = readHarnessState(sbx);
  // leave an inspectable snapshot next to the sandbox for the Owner
  writeFileSync(path.join(sbx, ".harness", `snapshot-${label}.json`), JSON.stringify(s, null, 2));
  return s;
}

function writeDoc(sbx: string, rel: string, body: string) {
  const p = path.join(sbx, ".harness", "documents", rel);
  mkdirSync(path.dirname(p), { recursive: true });
  writeFileSync(p, body);
}

function writeMissionState(sbx: string, missionRel: string, lifecycle: string, active: boolean) {
  const p = path.join(sbx, ".harness", "documents", missionRel, "mission-state.json");
  mkdirSync(path.dirname(p), { recursive: true });
  writeFileSync(p, JSON.stringify({ lifecycle, active }, null, 2) + "\n");
}

/** Simulate the UserPromptSubmit hook for an Owner command. */
function ownerCommand(sbx: string, prompt: string) {
  return runHook(sbx, "harness-user-prompt-submit.sh", {
    cwd: sbx,
    prompt,
    hook_event_name: "UserPromptSubmit",
  });
}

/** Simulate the Stop hook one tick. Returns {blocked, raw}. */
function stopTick(sbx: string): { blocked: boolean; raw: string } {
  const raw = runHook(sbx, "harness-stop.sh", {
    cwd: sbx,
    hook_event_name: "Stop",
    stop_hook_active: false,
  });
  return { blocked: raw.includes('"decision"') && raw.includes('"block"'), raw };
}

const SBX_ROOT = process.env.WALWAL_E2E_ROOT ?? path.join(os.tmpdir(), "walwal-e2e");

gate("walwal-harness sandbox e2e — two usage modes", () => {
  beforeAll(() => {
    mkdirSync(SBX_ROOT, { recursive: true });
  });

  it("install contract: init produces commands, CXX skills, runtime scripts, CLAUDE.md symlink", () => {
    const sbx = path.join(SBX_ROOT, "walwal-sandbox-install");
    init(sbx);
    for (const f of ["goal.md", "submission.md", "hot-fix.md"]) {
      expect(existsSync(path.join(sbx, ".claude", "commands", f))).toBe(true);
    }
    for (const role of ["ceo", "coo", "cdo", "cto", "cqo", "ops"]) {
      expect(existsSync(path.join(sbx, ".claude", "skills", `harness-${role}`, "SKILL.md"))).toBe(true);
    }
    // the two completion/blocked transition scripts must be installed
    expect(existsSync(path.join(sbx, "scripts", "harness-company-complete.sh"))).toBe(true);
    expect(existsSync(path.join(sbx, "scripts", "harness-company-block.sh"))).toBe(true);
    expect(existsSync(path.join(sbx, ".harness", "shared", "HR-Resource"))).toBe(true);
    // CLAUDE.md is a symlink -> AGENTS.md
    expect(lstatSync(path.join(sbx, "CLAUDE.md")).isSymbolicLink()).toBe(true);
  });

  it("migrate preserves user AGENTS.md and hired roster while refreshing package-owned state", () => {
    const sbx = path.join(SBX_ROOT, "walwal-sandbox-migrate-preserve");
    init(sbx);
    appendFileSync(path.join(sbx, "AGENTS.md"), "\n## User Rule\n\nKeep this project-specific rule.\n");
    writeFileSync(path.join(sbx, ".harness", ".bundle-version"), "7.1.1\n");
    mkdirSync(path.join(sbx, ".harness", "shared", "HR-Resource", "react-ui-worker"), { recursive: true });
    writeFileSync(path.join(sbx, ".harness", "shared", "HR-Resource", "react-ui-worker", "SKILL.md"), "# React UI Worker\n");
    const rosterPath = path.join(sbx, ".harness", "shared", "hr-roster.json");
    writeFileSync(
      rosterPath,
      JSON.stringify(
        {
          hired: [
            {
              worker: "react-ui-worker",
              owner: "cto",
              skillPath: ".claude/skills/react-ui-worker/SKILL.md",
            },
          ],
        },
        null,
        2
      )
    );

    execFileSync("node", [path.join(repoRoot, "bin", "init.js"), "migrate", "--dry-run", "--project-root", sbx], {
      cwd: repoRoot,
      encoding: "utf8",
      stdio: "pipe",
    });
    expect(readFileSync(path.join(sbx, ".harness", ".bundle-version"), "utf8")).toBe("7.1.1\n");
    expect(JSON.parse(readFileSync(rosterPath, "utf8")).hired[0].skillPaths).toBeUndefined();

    execFileSync("node", [path.join(repoRoot, "bin", "init.js"), "migrate", "--project-root", sbx], {
      cwd: repoRoot,
      encoding: "utf8",
      stdio: "pipe",
    });
    const agents = readFileSync(path.join(sbx, "AGENTS.md"), "utf8");
    expect(agents).toContain("Keep this project-specific rule.");
    const roster = JSON.parse(readFileSync(rosterPath, "utf8"));
    expect(roster.hired[0].skillPaths.codex).toContain(".codex/skills/");
    expect(roster.hired[0].skillPaths.source).toBe(".harness/shared/HR-Resource/react-ui-worker/SKILL.md");
    expect(readFileSync(path.join(sbx, ".harness", ".bundle-version"), "utf8")).toBe("7.1.48\n");
  });

  it("gitignore management untracks runtime state without untracking shared harness files", () => {
    const sbx = path.join(SBX_ROOT, "walwal-sandbox-gitignore");
    init(sbx);
    execFileSync("git", ["init"], { cwd: sbx, encoding: "utf8", stdio: "pipe" });
    execFileSync("git", ["add", "-f", ".harness/progress.json"], { cwd: sbx, encoding: "utf8", stdio: "pipe" });
    execFileSync("git", ["add", ".harness/memory.md"], { cwd: sbx, encoding: "utf8", stdio: "pipe" });
    expect(execFileSync("git", ["ls-files", ".harness/progress.json"], { cwd: sbx, encoding: "utf8" }).trim()).toBe(".harness/progress.json");
    expect(execFileSync("git", ["ls-files", ".harness/memory.md"], { cwd: sbx, encoding: "utf8" }).trim()).toBe(".harness/memory.md");

    execFileSync("node", [path.join(repoRoot, "bin", "init.js"), "init", "--force", "--project-root", sbx], {
      cwd: repoRoot,
      encoding: "utf8",
      stdio: "pipe",
    });

    expect(execFileSync("git", ["ls-files", ".harness/progress.json"], { cwd: sbx, encoding: "utf8" }).trim()).toBe("");
    expect(execFileSync("git", ["ls-files", ".harness/memory.md"], { cwd: sbx, encoding: "utf8" }).trim()).toBe(".harness/memory.md");
  });

  // ───────────────────────────────────────────────────────────────────────
  // MODE 1 — AUTONOMY: Owner sets a broad goal, the company runs itself, and
  // the loop must (a) keep going while work remains and (b) stop CLEANLY at
  // genuine completion (dashboard goes idle). Also verifies the deterministic
  // Stop-hook backstop when the model forgets the explicit completion call.
  // ───────────────────────────────────────────────────────────────────────
  it("autonomy mode: loop runs, then completion idles runtime + dashboard", () => {
    const sbx = path.join(SBX_ROOT, "walwal-sandbox-autonomy");
    init(sbx);
    const goalDir = "goal-1-growth-autopilot";

    // (1) Owner issues a broad, self-directed goal.
    ownerCommand(
      sbx,
      "/goal Run an autonomous growth program: discover problems in our funnel, propose and validate experiments, and expand the business plan without waiting on me for routine decisions."
    );
    let p = progress(sbx);
    expect(p.current_agent).toBe("ceo");
    expect(p.conductor.state).toBe("running");
    expect(p.owner_prompt.status).toBe("routing");
    let s = snap(sbx, "01-after-goal");
    expect(s.runtime.currentAgent).toBe("ceo");
    // not idle while running
    expect(s.runtime.agentStatus).not.toBe("completed");

    // (2) Autonomy at the start: Stop must BLOCK (keep going), not wait on Owner.
    expect(stopTick(sbx).blocked).toBe(true);

    // (3) Simulate the CEO/CXX document flow producing real artifacts.
    writeDoc(sbx, `${goalDir}/ceo.md`, `# CEO — Growth Autopilot\n\nRouted COO for discovery + experiment validation.${NOTES}`);
    writeMissionState(sbx, goalDir, "active", true);
    // COO enters: dashboard should show the live handoff.
    runScript(sbx, "harness-progress-set.sh", [".", '.current_agent="coo" | .agent_status="running"']);
    writeDoc(sbx, `${goalDir}/coo.md`, `# COO — Discovery\n\nWorker Evidence Manifest: coo/workers/funnel-researcher.md${NOTES}`);
    writeDoc(
      sbx,
      `${goalDir}/coo/workers/funnel-researcher.md`,
      `# Funnel Researcher — Worker Report\n\n## Status\nCOMPLETE\n\nFound 3 drop-off points; proposed 2 experiments.${NOTES}`
    );
    // worker telemetry: mark a live worker
    runScript(sbx, "harness-progress-set.sh", [
      ".",
      '.company_state.workers = [{"name":"funnel-researcher","owner":"coo","status":"running","report_path":".harness/documents/' +
        goalDir +
        '/coo/workers/funnel-researcher.md"}] | .company_state.active_workers = 1 | .conductor.current_action="spawn:funnel-researcher"',
    ]);

    s = snap(sbx, "02-mid-work");
    const m = s.missions.find((x) => x.missionId === goalDir);
    expect(m).toBeTruthy();
    expect(m!.active).toBe(true);
    expect(m!.lifecycle).toBe("active");
    expect(m!.cxxPresent).toEqual(expect.arrayContaining(["ceo", "coo"]));
    const w = m!.workers.find((x) => x.name === "funnel-researcher");
    expect(w).toBeTruthy();
    expect(w!.owner).toBe("coo");
    // (4) Autonomy mid-work: Stop must still BLOCK (active mission exists).
    expect(stopTick(sbx).blocked).toBe(true);

    // (5) Genuine completion: final report + terminal mission-state + the
    // wired runtime transition (what the new CEO protocol mandates).
    writeDoc(sbx, `${goalDir}/ceo.md`, `# CEO — Growth Autopilot\n\nFINAL OWNER REPORT: 2 experiments validated, plan expanded.${NOTES}`);
    writeMissionState(sbx, goalDir, "complete", false);
    runScript(sbx, "harness-company-complete.sh", [".", "goal-complete"]);

    p = progress(sbx);
    expect(p.conductor.state).toBe("completed");
    expect(p.current_agent).toBeNull();
    expect(p.agent_status).toBe("completed");
    expect(p.owner_prompt.status).toBe("completed");

    s = snap(sbx, "03-after-complete");
    // dashboard idle gate resolves: runtime no longer "busy / stuck on ceo"
    expect(s.runtime.currentAgent).toBeNull();
    expect(s.runtime.agentStatus).toBe("completed");
    const mc = s.missions.find((x) => x.missionId === goalDir)!;
    expect(mc.lifecycle).toBe("complete");
    expect(mc.active).toBe(false);

    // (6) THE key autonomy assertion: after completion the Stop hook stops
    // cleanly instead of nagging "continue".
    expect(stopTick(sbx).blocked).toBe(false);
  });

  it("autonomy backstop: terminal mission-state stops the loop even if the explicit completion call is skipped", () => {
    const sbx = path.join(SBX_ROOT, "walwal-sandbox-autonomy-backstop");
    init(sbx);
    const goalDir = "goal-1-backstop";
    ownerCommand(sbx, "/goal Backstop check.");
    writeDoc(sbx, `${goalDir}/ceo.md`, `# CEO\n\nReport.${NOTES}`);
    writeMissionState(sbx, goalDir, "active", true);
    expect(progress(sbx).conductor.state).toBe("running");

    // CEO marks the mission terminal (existing behavior) but FORGETS to fire
    // harness-company-complete.sh — conductor.state stays "running".
    writeMissionState(sbx, goalDir, "complete", false);
    expect(progress(sbx).conductor.state).toBe("running");

    // Stop hook backstop: no active mission remains -> auto-completes + stops.
    const tick = stopTick(sbx);
    expect(tick.blocked).toBe(false);
    const p = progress(sbx);
    expect(p.conductor.state).toBe("completed");
    expect(p.current_agent).toBeNull();
  });

  // ───────────────────────────────────────────────────────────────────────
  // STALE-BLOCKER CONTRACT — block -> complete must leave NO stale blocker state
  // in ANY of the three layers block.sh writes: progress.json,
  // .harness/todos/state.json, and per-mission mission-state.json. Guards the
  // del()/status-reset fixes in harness-company-{block,complete}.sh.
  // ───────────────────────────────────────────────────────────────────────
  it("block -> complete clears blocker state across progress, todos, and mission-state", () => {
    const sbx = path.join(SBX_ROOT, "walwal-sandbox-block-complete");
    init(sbx);
    const goalDir = "goal-1-blocked-then-done";
    const reason = 'needs "STRIPE" key';
    const msPath = path.join(sbx, ".harness", "documents", goalDir, "mission-state.json");
    const todosPath = path.join(sbx, ".harness", "todos", "state.json");

    ownerCommand(sbx, "/goal Ship a feature that needs a third-party credential.");
    writeDoc(sbx, `${goalDir}/ceo.md`, `# CEO\n\nRouted; awaiting external credential.${NOTES}`);
    writeMissionState(sbx, goalDir, "active", true);
    // a live todo that block.sh will flip to "blocked"
    mkdirSync(path.dirname(todosPath), { recursive: true });
    writeFileSync(todosPath, JSON.stringify({ owners: { coo: [{ id: "t1", title: "integrate API", status: "active" }] } }, null, 2));

    // (1) BLOCK on external authority (quotes in the reason exercise quote-safety).
    runScript(sbx, "harness-company-block.sh", [".", reason]);
    let p = progress(sbx);
    expect(p.conductor.state).toBe("blocked");
    expect(p.owner_prompt.blocked_reason).toBe(reason);
    let todos = JSON.parse(readFileSync(todosPath, "utf8"));
    expect(todos.owners.coo[0].status).toBe("blocked");
    expect(todos.owners.coo[0].blocked_reason).toBe(reason);
    let ms = JSON.parse(readFileSync(msPath, "utf8"));
    expect(ms.lifecycle).toBe("blocked");
    expect(ms.blocked_reason).toBe(reason);

    // (2) Authority provided → COMPLETE. No stale blocker may survive in any layer.
    runScript(sbx, "harness-company-complete.sh", [".", "credential provided; shipped"]);
    p = progress(sbx);
    expect(p.conductor.state).toBe("completed");
    expect("blocked_reason" in p.owner_prompt).toBe(false);
    expect("blocked_at" in p.owner_prompt).toBe(false);
    expect("blocked_at" in p.conductor).toBe(false);

    todos = JSON.parse(readFileSync(todosPath, "utf8"));
    expect(todos.owners.coo[0].status).toBe("done");
    expect("blocked_reason" in todos.owners.coo[0]).toBe(false);

    ms = JSON.parse(readFileSync(msPath, "utf8"));
    expect(ms.lifecycle).toBe("complete");
    expect(ms.active).toBe(false);
    expect("blocked_reason" in ms).toBe(false);
    expect("blocked_at" in ms).toBe(false);

    // the dashboard must NOT paint a completed run as blocked
    const m = snap(sbx, "block-complete-final").missions.find((x) => x.missionId === goalDir)!;
    expect(m.lifecycle).toBe("complete");
    expect(m.active).toBe(false);
  });

  // ───────────────────────────────────────────────────────────────────────
  // WAKE CONTROL — the hourly launchd job that drives the perpetual loop across
  // sessions is toggleable from the dashboard and keyed to HARNESS_BASE_PORT.
  // (Read-only + dry-run only — never loads a real job into the tester's launchd.)
  // ───────────────────────────────────────────────────────────────────────
  it("wake control: launchd job is keyed to HARNESS_BASE_PORT and dashboard-toggleable (dry-run)", () => {
    const sbx = path.join(SBX_ROOT, "walwal-sandbox-wake");
    init(sbx);
    appendFileSync(path.join(sbx, ".env"), "\nHARNESS_BASE_PORT=51000\n");

    const label = runScript(sbx, "harness-wake-control.sh", ["label", sbx]).trim();
    expect(label).toBe("com.walwal.harness-wake.51000");

    const status = JSON.parse(
      runScript(sbx, "harness-wake-control.sh", ["status", sbx]).trim().split("\n").filter(Boolean).pop()!
    );
    expect(status.label).toBe("com.walwal.harness-wake.51000");
    expect(status.base_port).toBe(51000);
    expect(typeof status.enabled).toBe("boolean");
    expect(typeof status.supported).toBe("boolean");

    // dry-run on: writes the per-project plist preview WITHOUT touching launchd
    runScript(sbx, "harness-wake-control.sh", ["on", sbx, "--dry-run"]);
    const preview = path.join(sbx, ".harness", "runtime", "com.walwal.harness-wake.51000.plist.preview");
    expect(existsSync(preview)).toBe(true);
    const plist = readFileSync(preview, "utf8");
    expect(plist).toContain("<string>com.walwal.harness-wake.51000</string>");
    expect(plist).toContain("WALWAL_HARNESS_PROJECTS");
    expect(plist).toContain(sbx);

    const state = JSON.parse(readFileSync(path.join(sbx, ".harness", "runtime", "wake-control.json"), "utf8"));
    expect(state.base_port).toBe(51000);
    expect(state.label).toBe("com.walwal.harness-wake.51000");
  });

  // ───────────────────────────────────────────────────────────────────────
  // MODE 1 (PERPETUAL) — a never-completing operating goal (crypto trading).
  // The loop must: keep running while agenda items exist (forced CEO
  // adjudication), force a status-briefing when the agenda is empty, yield to
  // the hourly wake on an operating heartbeat, re-engage on a discovered loss,
  // and NEVER reach a terminal lifecycle / never call company-complete.
  // ───────────────────────────────────────────────────────────────────────
  it("perpetual operating mode: agenda-driven loop runs forever, never completes", () => {
    const sbx = path.join(SBX_ROOT, "walwal-sandbox-operating");
    init(sbx);
    const goalDir = "goal-1-trading-autopilot";
    const agenda = (...args: string[]) => runScript(sbx, "harness-agenda.sh", [".", goalDir, ...args]);

    // (1) Owner issues a perpetual operating goal.
    ownerCommand(
      sbx,
      "/goal Build a crypto auto-trading system and keep it profitable forever: COO continuously researches and backtests new strategies, CTO operates them stably, on loss apply a new strategy, monitor and run perpetually."
    );
    // CEO classifies it operating (lifecycle=operating, never terminal).
    writeDoc(sbx, `${goalDir}/ceo.md`, `# CEO — Trading Autopilot (operating)\n\nClassified perpetual; standing agenda loop.${NOTES}`);
    writeMissionState(sbx, goalDir, "operating", true);

    let s = snap(sbx, "01-operating-start");
    let m = s.missions.find((x) => x.missionId === goalDir)!;
    expect(m.lifecycle).toBe("operating");
    expect(m.active).toBe(true);

    // (2) Empty agenda → Stop hook must FORCE a status-briefing (block), not stop, not complete.
    runScript(sbx, "harness-progress-set.sh", [".", '.conductor.state="running" | .current_agent="ceo" | .agent_status="running"']);
    let tick = stopTick(sbx);
    expect(tick.blocked).toBe(true);
    expect(tick.raw).toMatch(/현황 보고|status-briefing|안건 없음/);

    // (3) Status-briefing surfaces a loss → OPS raises an agenda item.
    const id1 = agenda("raise", "ops", "loss", "BTC strategy drawdown -8% / 24h", `${goalDir}/ops/workers/monitor.md`).trim();
    expect(agenda("active-count").trim()).toBe("1");
    s = snap(sbx, "02-agenda-raised");
    m = s.missions.find((x) => x.missionId === goalDir)!;
    expect(m.lifecycle).toBe("operating");
    expect(m.agendaOpen).toBe(1);

    // (4) Open agenda → Stop hook FORCES CEO adjudication (block), still never completes.
    tick = stopTick(sbx);
    expect(tick.blocked).toBe(true);
    expect(tick.raw).toMatch(/활성 안건|agenda/);

    // (5) CEO adjudicates → routes COO to research+backtest a new strategy; work done → close.
    agenda("decide", id1, "COO: research + backtest a regime-aware strategy; CTO apply; CQO verify", "coo");
    writeDoc(sbx, `${goalDir}/coo.md`, `# COO\n\nNew strategy backtested. Worker Evidence Manifest: coo/workers/strategy.md${NOTES}`);
    writeDoc(sbx, `${goalDir}/coo/workers/strategy.md`, `# Strategy — Worker Report\n\n## Status\nCOMPLETE${NOTES}`);
    agenda("close", id1);
    expect(agenda("active-count").trim()).toBe("0");

    // (6) Agenda empty again + briefing surfaces nothing → operating heartbeat, yield to wake.
    runScript(sbx, "harness-company-cycle.sh", [".", goalDir]);
    let p = progress(sbx);
    expect(p.conductor.state).toBe("operating");
    expect(p.agent_status).toBe("operating");
    expect(p.operating.cycles).toBeGreaterThanOrEqual(1);
    // Stop hook now yields CLEANLY (no block) — but the goal stays operating/active.
    tick = stopTick(sbx);
    expect(tick.blocked).toBe(false);
    s = snap(sbx, "03-operating-heartbeat");
    m = s.missions.find((x) => x.missionId === goalDir)!;
    expect(m.lifecycle).toBe("operating");
    expect(m.active).toBe(true); // STILL active — never completed

    // (7) A new loss arrives later → re-engage the cycle (back to forced adjudication).
    const id2 = agenda("raise", "ops", "loss", "New regime: strategy stale, -5%", `${goalDir}/ops/workers/monitor2.md`).trim();
    expect(agenda("active-count").trim()).toBe("1");
    tick = stopTick(sbx);
    expect(tick.blocked).toBe(true); // operating loop resumes, never terminal

    // INVARIANT: across the whole perpetual run the goal never reached a terminal
    // lifecycle and company-complete was never appropriate.
    const finalProgress = progress(sbx);
    expect(["operating", "running"]).toContain(finalProgress.conductor.state);
    const finalMission = snap(sbx, "04-operating-final").missions.find((x) => x.missionId === goalDir)!;
    expect(["operating"]).toContain(finalMission.lifecycle);
    expect(finalMission.active).toBe(true);
    void id2;
  });

  // ───────────────────────────────────────────────────────────────────────
  // MODE 2 — COMMAND-DRIVEN: Owner walks goal -> submission (additional dev)
  // -> hot-fix (detail fix). The dashboard must show the goal tree with the
  // submission + hotfix children, correct types/lifecycles, gotcha growth, and
  // the owner command history.
  // ───────────────────────────────────────────────────────────────────────
  it("command mode: goal -> submission -> hot-fix builds the mission tree the dashboard renders", () => {
    const sbx = path.join(SBX_ROOT, "walwal-sandbox-command");
    init(sbx);
    const goalDir = "goal-1-checkout";

    // --- /goal ---
    ownerCommand(sbx, "/goal Build a checkout page.");
    writeDoc(sbx, `${goalDir}/ceo.md`, `# CEO — Checkout\n\nFINAL: checkout shipped.${NOTES}`);
    writeDoc(sbx, `${goalDir}/cto.md`, `# CTO\n\nWorker Evidence Manifest: cto/workers/fe-dev.md${NOTES}`);
    writeDoc(sbx, `${goalDir}/cto/workers/fe-dev.md`, `# FE Dev — Worker Report\n\n## Status\nCOMPLETE${NOTES}`);
    writeMissionState(sbx, goalDir, "complete", false);
    runScript(sbx, "harness-company-complete.sh", [".", "goal-complete"]);
    let s = snap(sbx, "01-after-goal");
    expect(s.missions.some((m) => m.missionId === goalDir && m.type === "goal")).toBe(true);
    expect(s.runtime.agentStatus).toBe("completed"); // idle after goal

    // --- /submission (additional development under the goal) ---
    ownerCommand(sbx, "/submission Add promo-code support to checkout.");
    const subDir = `${goalDir}/submission-1-promo-codes`;
    writeDoc(sbx, `${subDir}/ceo.md`, `# CEO — Promo Codes\n\nFINAL: promo codes shipped.${NOTES}`);
    writeDoc(sbx, `${subDir}/cto.md`, `# CTO\n\nWorker Evidence Manifest: cto/workers/promo-dev.md${NOTES}`);
    writeDoc(sbx, `${subDir}/cto/workers/promo-dev.md`, `# Promo Dev — Worker Report\n\n## Status\nCOMPLETE${NOTES}`);
    writeMissionState(sbx, subDir, "complete", false);
    runScript(sbx, "harness-company-complete.sh", [".", "submission-complete"]);
    s = snap(sbx, "02-after-submission");
    const sub = s.missions.find((m) => m.missionId === subDir);
    expect(sub).toBeTruthy();
    expect(sub!.type).toBe("submission");

    // --- /hot-fix (detail fix under the goal) + mandatory gotcha ---
    const gotchasBefore = s.gotchas.length;
    ownerCommand(sbx, "/hot-fix Promo code validation throws on empty input.");
    const hotDir = `${goalDir}/hotfix-1-empty-promo`;
    writeDoc(sbx, `${hotDir}/ceo.md`, `# CEO — Hotfix\n\nFINAL: guard added.${NOTES}`);
    writeDoc(sbx, `${hotDir}/cto.md`, `# CTO\n\nWorker Evidence Manifest: cto/workers/patch.md${NOTES}`);
    writeDoc(sbx, `${hotDir}/cto/workers/patch.md`, `# Patch — Worker Report\n\n## Status\nCOMPLETE${NOTES}`);
    writeDoc(sbx, `${hotDir}/cqo.md`, `# CQO\n\nVerdict: PASS. Worker Evidence Manifest: cqo/workers/regress.md${NOTES}`);
    writeDoc(sbx, `${hotDir}/cqo/workers/regress.md`, `# Regression — Worker Report\n\n## Status\nCOMPLETE${NOTES}`);
    // hot-fix mandatory durable lesson
    writeFileSync(
      path.join(sbx, ".harness", "gotchas", "promo-empty-input.md"),
      `# Promo code empty-input guard\n\nAlways guard promo validation against empty input.\n`
    );
    writeMissionState(sbx, hotDir, "complete", false);
    runScript(sbx, "harness-company-complete.sh", [".", "hotfix-complete"]);
    s = snap(sbx, "03-after-hotfix");
    const hot = s.missions.find((m) => m.missionId === hotDir);
    expect(hot).toBeTruthy();
    expect(hot!.type).toBe("hotfix");
    expect(s.gotchas.length).toBe(gotchasBefore + 1);

    // --- dashboard tree expectations (HistoryNavigator groups by goal) ---
    const goalScope = s.missions.filter(
      (m) => m.missionId === goalDir || m.missionId.startsWith(`${goalDir}/`)
    );
    const ids = goalScope.map((m) => m.missionId);
    expect(ids).toEqual(expect.arrayContaining([goalDir, subDir, hotDir]));

    // --- owner command history (CommandLog + Cadence read this) ---
    const cmds = s.ownerHistory.map((e) => e.type);
    expect(cmds).toEqual(expect.arrayContaining(["goal", "submission", "hot-fix"]));

    // runtime ends idle (loop cleanly closed)
    expect(s.runtime.agentStatus).toBe("completed");
  });
});
