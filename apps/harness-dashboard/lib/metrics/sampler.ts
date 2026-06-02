/* =============================================================
   walwal-harness · METRICS SAMPLER (server-only, READ-ONLY)

   sampleMetrics(harnessRoot) produces REAL telemetry for the
   dashboard's previously-honest "—" placeholders:
     - tokensPerMin   real   (delta of cumulative tokens / delta min)
     - costToday      ESTIMATE (tokens × per-model price; costEstimated:true)
     - contextPct     real   (most-active session's last-line occupancy)
     - cpu            real   (ps %cpu of discovered company PIDs)
     - mtrend/ctrend  real   (persisted ring buffer of recent samples)
     - perAgent       best-effort attribution by session name

   It NEVER touches the runtime loop. It only:
     - reads ~/.claude/projects/<slug>/*.jsonl transcripts (tail, capped)
     - reads <root>/.harness queue*.json + team*.json (recursive) for PIDs
     - shells out to `ps` / `tmux list-panes` (both guarded; may be absent)
     - persists a ring buffer to <root>/.harness/dashboard/metrics-ring.json

   HONESTY RULE: anything that cannot be sourced stays null. Every fs/exec
   call is guarded; the module never throws (returns nulls on failure).
   ============================================================= */

import {
  existsSync,
  mkdirSync,
  openSync,
  readSync,
  closeSync,
  fstatSync,
  readFileSync,
  writeFileSync,
  readdirSync,
  statSync,
} from "node:fs";
import path from "node:path";
import os from "node:os";
import { execFileSync } from "node:child_process";

/* ---- public types ----------------------------------------------------- */

export interface PerAgentMetric {
  cpu?: number;
  tokens?: number;
  contextPct?: number;
}

export interface MetricsSample {
  /** tokens/min between the two most recent ring samples; null until 2 exist. */
  tokensPerMin: number | null;
  /** USD estimate of recent-session token spend; null when no tokens seen. */
  costToday: number | null;
  /** costToday is always a price-table ESTIMATE, never a billed number. */
  costEstimated: boolean;
  /** 0..100 occupancy of the most-recently-active session; null when unknown. */
  contextPct: number | null;
  /** Summed %cpu of discovered company PIDs; null when none discoverable. */
  cpu: number | null;
  /** cumulative-tokens sparkline samples (oldest→newest); [] when no source. */
  mtrend: number[];
  /** cost-estimate sparkline samples (oldest→newest); [] when no source. */
  ctrend: number[];
  /** best-effort per-agent attribution; omitted when nothing attributable. */
  perAgent?: Record<string, PerAgentMetric>;
  /** epoch ms this sample was taken. */
  sampledAt: number;
}

/* ---- tables (chosen; documented for the caller) ----------------------- */

/**
 * Per-model context window (tokens). Keyed by lowercase substring of the
 * model id; first match wins. "1m" → the 1,000,000-token window.
 */
const CONTEXT_LIMITS: Array<{ match: string; limit: number }> = [
  { match: "1m", limit: 1_000_000 },
];
const DEFAULT_CONTEXT_LIMIT = 200_000;

/**
 * Approximate USD price per MILLION tokens, by model family substring.
 * cache_read is billed far cheaper than fresh input (~0.1× input here);
 * cache_creation is treated as input-priced. These are PUBLIC-LIST
 * approximations — costToday is explicitly an estimate (costEstimated:true).
 */
interface Price {
  in: number;
  out: number;
  cacheRead: number;
  cacheWrite: number;
}
const PRICES: Array<{ match: string; price: Price }> = [
  { match: "opus", price: { in: 15, out: 75, cacheRead: 1.5, cacheWrite: 18.75 } },
  { match: "sonnet", price: { in: 3, out: 15, cacheRead: 0.3, cacheWrite: 3.75 } },
  { match: "haiku", price: { in: 0.8, out: 4, cacheRead: 0.08, cacheWrite: 1.0 } },
];
const DEFAULT_PRICE: Price = { in: 3, out: 15, cacheRead: 0.3, cacheWrite: 3.75 };

const RECENT_WINDOW_MS = 30 * 60_000; // sessions touched in last ~30 min = "live"
const RING_CAP = 60; // ring buffer entries
const TRANSCRIPT_TAIL_BYTES = 512 * 1024; // read at most the last 512KB of a jsonl
const MAX_SESSIONS = 40; // hard cap on transcripts scanned per sample

/* ---- transcript line shape (only fields we read) ---------------------- */

interface Usage {
  input_tokens?: number;
  output_tokens?: number;
  cache_creation_input_tokens?: number;
  cache_read_input_tokens?: number;
}
interface TranscriptLine {
  type?: string;
  cwd?: string;
  message?: { model?: string; usage?: Usage };
}

interface RingEntry {
  at: number;
  cumTokens: number;
  costToday: number;
  cpu: number | null;
}

/* ---- small guarded helpers -------------------------------------------- */

function priceFor(model: string): Price {
  const m = model.toLowerCase();
  for (const p of PRICES) if (m.includes(p.match)) return p.price;
  return DEFAULT_PRICE;
}

function contextLimitFor(model: string): number {
  const m = model.toLowerCase();
  for (const c of CONTEXT_LIMITS) if (m.includes(c.match)) return c.limit;
  return DEFAULT_CONTEXT_LIMIT;
}

/** Map a project root path to the Claude transcript slug dir name. */
function slugForRoot(harnessRoot: string): string {
  // Rule (verified): the absolute project path with every '/' and '_' → '-'.
  return path.resolve(harnessRoot).replace(/[/_]/g, "-");
}

/** Read at most the last `maxBytes` of a file as utf8; "" on any failure. */
function tailRead(filePath: string, maxBytes: number): string {
  let fd = -1;
  try {
    fd = openSync(filePath, "r");
    const size = fstatSync(fd).size;
    const start = size > maxBytes ? size - maxBytes : 0;
    const len = size - start;
    if (len <= 0) return "";
    const buf = Buffer.allocUnsafe(len);
    const read = readSync(fd, buf, 0, len, start);
    return buf.toString("utf8", 0, read);
  } catch {
    return "";
  } finally {
    if (fd >= 0) {
      try {
        closeSync(fd);
      } catch {
        /* ignore */
      }
    }
  }
}

/** Parse one JSONL line into a TranscriptLine, or null. */
function parseLine(line: string): TranscriptLine | null {
  const s = line.trim();
  if (!s || s[0] !== "{") return null;
  try {
    return JSON.parse(s) as TranscriptLine;
  } catch {
    return null;
  }
}

function usageTokens(u: Usage | undefined): number {
  if (!u) return 0;
  return (
    (u.input_tokens ?? 0) +
    (u.output_tokens ?? 0) +
    (u.cache_creation_input_tokens ?? 0) +
    (u.cache_read_input_tokens ?? 0)
  );
}

function usageCost(u: Usage | undefined, price: Price): number {
  if (!u) return 0;
  const inTok = u.input_tokens ?? 0;
  const outTok = u.output_tokens ?? 0;
  const cw = u.cache_creation_input_tokens ?? 0;
  const cr = u.cache_read_input_tokens ?? 0;
  return (
    (inTok * price.in +
      outTok * price.out +
      cw * price.cacheWrite +
      cr * price.cacheRead) /
    1_000_000
  );
}

/** Occupancy of a single usage line (context tokens currently resident). */
function contextTokens(u: Usage | undefined): number {
  if (!u) return 0;
  return (
    (u.input_tokens ?? 0) +
    (u.cache_read_input_tokens ?? 0) +
    (u.cache_creation_input_tokens ?? 0)
  );
}

/* ---- transcript aggregation ------------------------------------------- */

interface SessionStat {
  file: string;
  mtimeMs: number;
  tokens: number;
  cost: number;
  /** last assistant line's model + usage — drives contextPct. */
  lastModel: string | null;
  lastUsage: Usage | undefined;
}

function scanSession(file: string, mtimeMs: number): SessionStat {
  const stat: SessionStat = {
    file,
    mtimeMs,
    tokens: 0,
    cost: 0,
    lastModel: null,
    lastUsage: undefined,
  };
  const text = tailRead(file, TRANSCRIPT_TAIL_BYTES);
  if (!text) return stat;
  // If we tailed mid-file the first fragment may be a partial line — drop it.
  const lines = text.split("\n");
  for (const raw of lines) {
    const obj = parseLine(raw);
    if (!obj || obj.type !== "assistant") continue;
    const msg = obj.message;
    if (!msg) continue;
    const model = msg.model ?? "";
    const u = msg.usage;
    stat.tokens += usageTokens(u);
    stat.cost += usageCost(u, priceFor(model));
    // assistant lines are append-ordered; the final one is the live frontier.
    stat.lastModel = model || stat.lastModel;
    stat.lastUsage = u ?? stat.lastUsage;
  }
  return stat;
}

/* ---- PID discovery + cpu ---------------------------------------------- */

/** Recursively collect queue*.json / team*.json under <root>/.harness. */
function findQueueFiles(harnessDir: string): string[] {
  const out: string[] = [];
  const walk = (dir: string, depth: number): void => {
    if (depth > 6) return;
    let entries: import("node:fs").Dirent[];
    try {
      entries = readdirSync(dir, { withFileTypes: true });
    } catch {
      return;
    }
    for (const e of entries) {
      const full = path.join(dir, e.name);
      if (e.isDirectory()) {
        if (e.name === "node_modules" || e.name.startsWith(".git")) continue;
        walk(full, depth + 1);
      } else if (e.isFile()) {
        const n = e.name.toLowerCase();
        if (
          n.endsWith(".json") &&
          (n.startsWith("queue") ||
            n.startsWith("team") ||
            n.includes("queue") ||
            n.includes("team"))
        ) {
          out.push(full);
        }
      }
    }
  };
  walk(harnessDir, 0);
  return out;
}

/** Deep-scan a parsed JSON value for `pid` fields holding positive ints. */
function collectPids(value: unknown, into: Set<number>): void {
  if (value == null) return;
  if (Array.isArray(value)) {
    for (const v of value) collectPids(v, into);
    return;
  }
  if (typeof value === "object") {
    for (const [k, v] of Object.entries(value as Record<string, unknown>)) {
      if (k.toLowerCase() === "pid") {
        const n = typeof v === "number" ? v : typeof v === "string" ? Number(v) : NaN;
        if (Number.isInteger(n) && n > 1) into.add(n);
      } else {
        collectPids(v, into);
      }
    }
  }
}

/** %cpu for a single pid via `ps -o %cpu= -p <pid>`; null if dead/guarded. */
function cpuForPid(pid: number): number | null {
  try {
    const out = execFileSync("ps", ["-o", "%cpu=", "-p", String(pid)], {
      encoding: "utf8",
      timeout: 4000,
      stdio: ["ignore", "pipe", "ignore"],
    });
    const v = parseFloat(out.trim());
    return Number.isFinite(v) ? v : null;
  } catch {
    return null;
  }
}

/**
 * Discover tmux company panes: pane_pid keyed by session name, for sessions
 * matching `walwal_<projbasename>_*`. tmux may be absent → returns {}.
 */
function tmuxCompanyPanes(projBase: string): Array<{ session: string; pid: number }> {
  const panes: Array<{ session: string; pid: number }> = [];
  const prefix = `walwal_${projBase}_`;
  try {
    const out = execFileSync(
      "tmux",
      ["list-panes", "-a", "-F", "#{session_name} #{pane_pid}"],
      // stdio: silence tmux's "no server"/connect stderr; we read stdout only.
      { encoding: "utf8", timeout: 4000, stdio: ["ignore", "pipe", "ignore"] }
    );
    for (const line of out.split("\n")) {
      const sp = line.trim().split(/\s+/);
      if (sp.length < 2) continue;
      const session = sp[0];
      const pid = Number(sp[1]);
      if (!session.startsWith(prefix)) continue;
      if (Number.isInteger(pid) && pid > 1) panes.push({ session, pid });
    }
  } catch {
    /* tmux absent or no server — guarded, return whatever we have ([]) */
  }
  return panes;
}

/* ---- ring buffer persistence ------------------------------------------ */

function ringPath(harnessRoot: string): string {
  return path.join(harnessRoot, ".harness", "dashboard", "metrics-ring.json");
}

function readRing(harnessRoot: string): RingEntry[] {
  const file = ringPath(harnessRoot);
  try {
    if (!existsSync(file)) return [];
    const raw = readFileSync(file, "utf8");
    const parsed = JSON.parse(raw);
    if (!Array.isArray(parsed)) return [];
    return parsed.filter(
      (e): e is RingEntry =>
        e != null &&
        typeof e === "object" &&
        typeof (e as RingEntry).at === "number" &&
        typeof (e as RingEntry).cumTokens === "number"
    );
  } catch {
    return [];
  }
}

function writeRing(harnessRoot: string, ring: RingEntry[]): void {
  const file = ringPath(harnessRoot);
  try {
    mkdirSync(path.dirname(file), { recursive: true });
    writeFileSync(file, JSON.stringify(ring), "utf8");
  } catch {
    /* persistence is best-effort; sampling must still succeed */
  }
}

/* ---- the sampler ------------------------------------------------------ */

/** An empty/safe sample (used on any unrecoverable failure path). */
function emptySample(now: number): MetricsSample {
  return {
    tokensPerMin: null,
    costToday: null,
    costEstimated: true,
    contextPct: null,
    cpu: null,
    mtrend: [],
    ctrend: [],
    sampledAt: now,
  };
}

export async function sampleMetrics(harnessRoot: string): Promise<MetricsSample> {
  const now = Date.now();
  try {
    /* ---- 1. transcripts: tokens + cost + contextPct ------------------ */
    const slugDir = path.join(os.homedir(), ".claude", "projects", slugForRoot(harnessRoot));
    const sessions: SessionStat[] = [];
    let recentFiles: Array<{ file: string; mtimeMs: number }> = [];
    try {
      if (existsSync(slugDir)) {
        const names = readdirSync(slugDir).filter((n) => n.endsWith(".jsonl"));
        for (const name of names) {
          const full = path.join(slugDir, name);
          try {
            const st = statSync(full);
            if (now - st.mtimeMs <= RECENT_WINDOW_MS) {
              recentFiles.push({ file: full, mtimeMs: st.mtimeMs });
            }
          } catch {
            /* skip unstattable file */
          }
        }
      }
    } catch {
      recentFiles = [];
    }
    // newest first, cap the number of transcripts we open per sample.
    recentFiles.sort((a, b) => b.mtimeMs - a.mtimeMs);
    recentFiles = recentFiles.slice(0, MAX_SESSIONS);
    for (const { file, mtimeMs } of recentFiles) {
      sessions.push(scanSession(file, mtimeMs));
    }

    let cumTokens = 0;
    let costToday = 0;
    let sawTokens = false;
    for (const s of sessions) {
      cumTokens += s.tokens;
      costToday += s.cost;
      if (s.tokens > 0) sawTokens = true;
    }

    // contextPct from the most-recently-active session's last assistant line.
    let contextPct: number | null = null;
    const mostRecent = sessions.length > 0 ? sessions[0] : null; // already newest-first
    if (mostRecent && mostRecent.lastUsage) {
      const limit = contextLimitFor(mostRecent.lastModel ?? "");
      const occ = contextTokens(mostRecent.lastUsage);
      if (limit > 0 && occ >= 0) {
        contextPct = Math.min(100, Math.round((occ / limit) * 1000) / 10);
      }
    }

    /* ---- 2. cpu: queue PIDs + tmux panes ----------------------------- */
    const harnessDir = path.join(harnessRoot, ".harness");
    const projBase = path
      .basename(path.resolve(harnessRoot))
      .replace(/[^A-Za-z0-9_]/g, "_");
    const pidSet = new Set<number>();
    if (existsSync(harnessDir)) {
      for (const qf of findQueueFiles(harnessDir)) {
        try {
          const raw = readFileSync(qf, "utf8");
          collectPids(JSON.parse(raw), pidSet);
        } catch {
          /* skip unreadable/corrupt queue file */
        }
      }
    }
    const panes = tmuxCompanyPanes(projBase);
    for (const p of panes) pidSet.add(p.pid);

    let cpu: number | null = null;
    if (pidSet.size > 0) {
      let total = 0;
      let any = false;
      for (const pid of pidSet) {
        const c = cpuForPid(pid);
        if (c != null) {
          total += c;
          any = true;
        }
      }
      cpu = any ? Math.round(total * 10) / 10 : null;
    }

    /* ---- 3. perAgent: attribute via tmux session name ---------------- */
    let perAgent: Record<string, PerAgentMetric> | undefined;
    if (panes.length > 0) {
      const acc: Record<string, PerAgentMetric> = {};
      const prefix = `walwal_${projBase}_`;
      for (const p of panes) {
        // session name: walwal_<projBase>_<stamp> — stamp is the agent tag.
        const tag = p.session.slice(prefix.length) || p.session;
        const c = cpuForPid(p.pid);
        const cur = acc[tag] ?? {};
        if (c != null) cur.cpu = Math.round(((cur.cpu ?? 0) + c) * 10) / 10;
        acc[tag] = cur;
      }
      if (Object.keys(acc).length > 0) perAgent = acc;
    }

    /* ---- 4. ring buffer: tokensPerMin + mtrend/ctrend ---------------- */
    const ring = readRing(harnessRoot);
    const entry: RingEntry = {
      at: now,
      cumTokens,
      costToday: Math.round(costToday * 10000) / 10000,
      cpu,
    };
    ring.push(entry);
    while (ring.length > RING_CAP) ring.shift();
    writeRing(harnessRoot, ring);

    let tokensPerMin: number | null = null;
    if (ring.length >= 2) {
      const prev = ring[ring.length - 2];
      const last = ring[ring.length - 1];
      const dMin = (last.at - prev.at) / 60_000;
      const dTok = last.cumTokens - prev.cumTokens;
      if (dMin > 0 && dTok >= 0) tokensPerMin = Math.round(dTok / dMin);
    }

    const mtrend = ring.map((e) => e.cumTokens);
    const ctrend = ring.map((e) => Math.round(e.costToday * 100) / 100);

    return {
      tokensPerMin,
      costToday: sawTokens ? Math.round(costToday * 100) / 100 : null,
      costEstimated: true,
      contextPct,
      cpu,
      mtrend,
      ctrend,
      perAgent,
      sampledAt: now,
    };
  } catch {
    // Absolute backstop — sampling must never throw into the route handler.
    return emptySample(now);
  }
}
