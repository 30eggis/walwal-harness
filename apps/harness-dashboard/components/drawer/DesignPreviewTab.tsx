"use client";
import type { MissionDoc } from "@/lib/types";

interface DesignPreviewTabProps {
  mission: MissionDoc | null;
}

function escapeHtml(value: string) {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

function extractFirstBullet(markdown: string | null | undefined) {
  if (!markdown) return null;
  return (
    markdown
      .split("\n")
      .map((line) => line.trim())
      .find((line) => /^[-*]\s+\S/.test(line))
      ?.replace(/^[-*]\s+/, "")
      .slice(0, 140) ?? null
  );
}

function buildPreviewDoc(mission: MissionDoc | null) {
  if (mission?.cdoPreview?.trim()) {
    return mission.cdoPreview;
  }

  const missionId = mission?.missionId ?? "No active mission";
  const brief =
    extractFirstBullet(mission?.cdo) ??
    extractFirstBullet(mission?.ceo) ??
    "Design direction will appear here after harness-cdo writes cdo.md.";

  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <style>
    :root {
      color-scheme: dark;
      --bg: #101216;
      --panel: #171b22;
      --line: #2d3543;
      --text: #eef2f7;
      --muted: #8a94a6;
      --cyan: #22d3ee;
      --amber: #fbbf24;
      --rose: #fb7185;
      font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      min-height: 100vh;
      background: radial-gradient(circle at 18% 0%, rgba(34, 211, 238, .12), transparent 26rem), var(--bg);
      color: var(--text);
    }
    .shell { min-height: 100vh; display: grid; grid-template-rows: auto 1fr; }
    header {
      display: flex; align-items: center; justify-content: space-between; gap: 16px;
      padding: 18px 22px; border-bottom: 1px solid var(--line); background: rgba(10, 12, 16, .72);
    }
    .brand { font-size: 12px; letter-spacing: .22em; text-transform: uppercase; color: var(--cyan); }
    .mission { max-width: 54ch; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; color: var(--muted); font-size: 12px; }
    main { display: grid; grid-template-columns: 280px 1fr; min-height: 0; }
    aside { border-right: 1px solid var(--line); padding: 18px; background: rgba(255,255,255,.02); }
    .nav { display: grid; gap: 8px; }
    .nav div { padding: 10px 12px; border: 1px solid var(--line); border-radius: 8px; color: var(--muted); font-size: 12px; }
    .nav div:first-child { color: var(--text); border-color: rgba(34,211,238,.55); background: rgba(34,211,238,.08); }
    section { padding: 22px; min-width: 0; }
    .hero {
      border: 1px solid var(--line); border-radius: 10px; overflow: hidden; background: var(--panel);
      display: grid; grid-template-columns: minmax(260px, 1fr) 280px;
    }
    .hero-copy { padding: 28px; }
    h1 { margin: 0; font-size: 34px; line-height: 1.08; letter-spacing: 0; }
    p { color: var(--muted); line-height: 1.55; }
    .actions { display: flex; gap: 10px; margin-top: 22px; }
    button { border: 0; border-radius: 8px; padding: 10px 14px; font-weight: 700; }
    .primary { background: var(--cyan); color: #061014; }
    .secondary { background: #242a35; color: var(--text); }
    .visual { padding: 20px; background: linear-gradient(135deg, rgba(34,211,238,.18), rgba(251,191,36,.12)); display: grid; align-content: center; gap: 12px; }
    .card { border: 1px solid rgba(255,255,255,.16); border-radius: 8px; padding: 14px; background: rgba(16,18,22,.72); box-shadow: 0 18px 40px rgba(0,0,0,.22); }
    .metric { font-size: 26px; font-weight: 800; }
    .grid { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 12px; margin-top: 16px; }
    .tile { border: 1px solid var(--line); border-radius: 8px; padding: 14px; background: rgba(255,255,255,.03); min-height: 112px; }
    .tile b { display: block; margin-bottom: 8px; }
    @media (max-width: 760px) {
      main, .hero { grid-template-columns: 1fr; }
      aside { display: none; }
      h1 { font-size: 28px; }
      .grid { grid-template-columns: 1fr; }
    }
  </style>
</head>
<body>
  <div class="shell">
    <header>
      <div class="brand">CDO Visual Sample</div>
      <div class="mission">${escapeHtml(missionId)}</div>
    </header>
    <main>
      <aside>
        <div class="nav">
          <div>Overview</div>
          <div>Interaction</div>
          <div>Accessibility</div>
          <div>Review</div>
        </div>
      </aside>
      <section>
        <div class="hero">
          <div class="hero-copy">
            <h1>${escapeHtml(brief)}</h1>
            <p>Structured sample generated from the active CDO/CEO mission context. Replace this with a richer cdo.md mockup artifact when available.</p>
            <div class="actions">
              <button class="primary">Primary action</button>
              <button class="secondary">Secondary</button>
            </div>
          </div>
          <div class="visual">
            <div class="card"><div class="metric">92%</div><p>Readiness score</p></div>
            <div class="card"><b>State</b><p>Focused, scannable, worker-backed.</p></div>
          </div>
        </div>
        <div class="grid">
          <div class="tile"><b>Layout</b><p>Quiet hierarchy, constrained content, no nested cards.</p></div>
          <div class="tile"><b>Flow</b><p>Primary workflow remains visible without explanation copy.</p></div>
          <div class="tile"><b>Quality</b><p>Designed for CDO review before CQO evidence collection.</p></div>
        </div>
      </section>
    </main>
  </div>
</body>
</html>`;
}

export function DesignPreviewTab({ mission }: DesignPreviewTabProps) {
  const srcDoc = buildPreviewDoc(mission);

  return (
    <div className="flex h-full min-h-[620px] flex-col gap-3">
      <div className="rounded border border-purple-400/30 bg-purple-500/10 px-3 py-2 text-[11px] text-purple-200">
        harness-cdo visual preview
      </div>
      <iframe
        title="CDO visual sample"
        sandbox=""
        srcDoc={srcDoc}
        className="min-h-0 flex-1 rounded-md border border-gray-700 bg-[#101216]"
      />
    </div>
  );
}
