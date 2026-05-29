#!/usr/bin/env node
const fs = require("fs");
const path = require("path");

const DAY_MS = 24 * 60 * 60 * 1000;
const RETENTION_MS = 7 * DAY_MS;
const RECENT_MS = 10 * 60 * 1000;
const CXX_ROLES = ["ceo", "coo", "cdo", "cto", "cqo", "ops"];
const WORKER_OWNERS = ["coo", "cdo", "cto", "cqo", "ops"];
const TERMINAL_LIFECYCLES = new Set(["closed", "cancelled", "superseded", "complete"]);

function readJson(filePath, fallback = null) {
  try {
    return JSON.parse(fs.readFileSync(filePath, "utf8"));
  } catch {
    return fallback;
  }
}

function readText(filePath) {
  try {
    return fs.readFileSync(filePath, "utf8");
  } catch {
    return "";
  }
}

function walk(dir) {
  const out = [];
  if (!fs.existsSync(dir)) return out;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, entry.name);
    if (entry.isDirectory()) out.push(...walk(p));
    else out.push(p);
  }
  return out;
}

function isoDay(ts) {
  return new Date(ts).toISOString().slice(0, 10);
}

function ensureDir(dir) {
  fs.mkdirSync(dir, { recursive: true });
}

function pruneActivity(activityDir, now = Date.now()) {
  if (!fs.existsSync(activityDir)) return;
  for (const entry of fs.readdirSync(activityDir)) {
    if (!/^\d{4}-\d{2}-\d{2}\.jsonl$/.test(entry)) continue;
    const day = entry.slice(0, 10);
    const cutoff = Date.parse(`${day}T23:59:59.999Z`);
    if (Number.isFinite(cutoff) && now - cutoff > RETENTION_MS) {
      fs.rmSync(path.join(activityDir, entry), { force: true });
    }
  }
}

function parseLifecycle(missionDir) {
  const state = readJson(path.join(missionDir, "mission-state.json"), null);
  const lifecycle = typeof state?.lifecycle === "string" ? state.lifecycle : "unknown";
  return { lifecycle, active: state?.active === true || lifecycle === "active" };
}

function collectMissions(root) {
  const docsDir = path.join(root, ".harness", "documents");
  if (!fs.existsSync(docsDir)) return [];
  const dirs = [];
  const visit = (dir) => {
    if (fs.existsSync(path.join(dir, "ceo.md")) || fs.existsSync(path.join(dir, "mission-state.json"))) {
      dirs.push(dir);
    }
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      if (entry.isDirectory() && !["workers", "archive"].includes(entry.name)) visit(path.join(dir, entry.name));
    }
  };
  visit(docsDir);
  return dirs.map((dir) => {
    const rel = path.relative(docsDir, dir);
    const state = parseLifecycle(dir);
    const cxxPresent = CXX_ROLES.filter((role) => fs.existsSync(path.join(dir, `${role}.md`)));
    const workers = [];
    for (const owner of WORKER_OWNERS) {
      const workerDir = path.join(dir, owner, "workers");
      for (const file of walk(workerDir).filter((p) => p.endsWith(".md"))) {
        const content = readText(file);
        const stat = fs.statSync(file);
        const name = path.basename(file, ".md");
        const complete = /(^|\n)(status:\s*COMPLETE|##\s*Status\s*\n\s*COMPLETE)\b/i.test(content);
        workers.push({
          owner,
          name,
          laneId: `${owner}:${name}`,
          content,
          complete,
          updatedAt: stat.mtimeMs,
        });
      }
    }
    return {
      missionId: rel,
      dir,
      lifecycle: state.lifecycle,
      active: state.active,
      cxxPresent,
      workers,
      mtimeMs: fs.statSync(dir).mtimeMs,
    };
  });
}

function readTodos(root) {
  const state = readJson(path.join(root, ".harness", "todos", "state.json"), {});
  const owners = state?.owners && typeof state.owners === "object" ? state.owners : {};
  return Object.entries(owners).flatMap(([owner, items]) =>
    Array.isArray(items)
      ? items.map((item) => ({ ...item, owner }))
      : []
  );
}

function runtimeIdle(root) {
  const p = readJson(path.join(root, ".harness", "progress.json"), {});
  return (
    p?.agent_status === "completed" ||
    p?.agent_status === "complete" ||
    ((p?.current_agent ?? null) === null && (p?.next_agent === null || p?.next_agent === "none"))
  );
}

function currentSamples(root, now = Date.now()) {
  const missions = collectMissions(root);
  const active = missions.find((m) => m.active) ?? missions.sort((a, b) => b.mtimeMs - a.mtimeMs)[0] ?? null;
  if (!active) return [];
  const todos = readTodos(root);
  const idle = runtimeIdle(root);
  const samples = [];
  for (const role of CXX_ROLES) {
    const workers = active.workers.filter((w) => w.owner === role);
    const runningWorkers = workers.filter((w) => !idle && !w.complete && now - w.updatedAt < RECENT_MS);
    const liveTodos = todos.filter((t) => t.owner === role && !["done", "completed"].includes(String(t.status)));
    let count = 0;
    if (!idle && liveTodos.length > 0 && runningWorkers.length === 0) count = 2;
    else if (active.cxxPresent.includes(role) || workers.length > 0 || runningWorkers.length > 0) count = 1;
    if (count > 0) samples.push({ ts: new Date(now).toISOString(), laneId: role, count, hotfix: active.missionId.includes("hotfix"), missionId: active.missionId });
  }
  for (const worker of active.workers) {
    const count = !idle && !worker.complete && now - worker.updatedAt < RECENT_MS ? 2 : worker.complete || worker.content ? 1 : 0;
    if (count > 0) samples.push({ ts: new Date(now).toISOString(), laneId: worker.laneId, count, hotfix: active.missionId.includes("hotfix"), missionId: active.missionId });
  }
  return samples;
}

function legacySamples(root) {
  const now = Date.now();
  const samples = [];
  for (const mission of collectMissions(root)) {
    const terminal = TERMINAL_LIFECYCLES.has(mission.lifecycle);
    for (const role of mission.cxxPresent.filter((r) => CXX_ROLES.includes(r))) {
      const file = path.join(mission.dir, `${role}.md`);
      const ts = fs.existsSync(file) ? fs.statSync(file).mtimeMs : mission.mtimeMs;
      if (now - ts <= RETENTION_MS) {
        samples.push({ ts: new Date(ts).toISOString(), laneId: role, count: terminal ? 1 : 2, hotfix: mission.missionId.includes("hotfix"), missionId: mission.missionId });
      }
    }
    for (const worker of mission.workers) {
      if (now - worker.updatedAt <= RETENTION_MS) {
        samples.push({ ts: new Date(worker.updatedAt).toISOString(), laneId: worker.laneId, count: worker.complete || terminal ? 1 : 2, hotfix: mission.missionId.includes("hotfix"), missionId: mission.missionId });
      }
    }
  }
  const progressLog = path.join(root, ".harness", "progress.log");
  for (const line of readText(progressLog).split("\n")) {
    const m = line.match(/^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z).*\b(ceo|coo|cdo|cto|cqo|ops)\b/i);
    if (!m) continue;
    const ts = Date.parse(m[1]);
    if (Number.isFinite(ts) && now - ts <= RETENTION_MS) {
      samples.push({ ts: new Date(ts).toISOString(), laneId: m[2].toLowerCase(), count: 1, hotfix: /hot-?fix/i.test(line), missionId: null });
    }
  }
  return samples;
}

function appendSamples(root, samples) {
  if (samples.length === 0) return;
  const activityDir = path.join(root, ".harness", "activity");
  ensureDir(activityDir);
  const byDay = new Map();
  for (const sample of samples) {
    const day = isoDay(Date.parse(sample.ts));
    if (!byDay.has(day)) byDay.set(day, []);
    byDay.get(day).push(sample);
  }
  for (const [day, rows] of byDay) {
    fs.appendFileSync(path.join(activityDir, `${day}.jsonl`), rows.map((r) => JSON.stringify(r)).join("\n") + "\n");
  }
  pruneActivity(activityDir);
}

function main() {
  const root = path.resolve(process.argv[2] || ".");
  const mode = process.argv.includes("--migrate") ? "migrate" : "sample";
  if (!fs.existsSync(path.join(root, ".harness"))) return;
  appendSamples(root, mode === "migrate" ? legacySamples(root) : currentSamples(root));
}

main();
