"use client";

/* =============================================================
   walwal-harness · BRICK OFFICE shared UI primitives + chrome
   Ported from design_handoff_harness_dashboard/harness/ui.jsx.

   Babel-inline globals -> ES modules. No window.* access.
   classNames/CSS preserved verbatim (CSS lives in app/brick.css).
   `statusColor` lives in lib/brick/contract — imported here.

   Exports: StatusDot, Pill, Label, Panel, Spark, Bars, AgentGlyph,
            Header, Sidebar.
   ============================================================= */

import React, { useState } from "react";
import {
  statusColor,
  type AgentDef,
  type ContractMetrics,
  type ContractAlert,
} from "../../lib/brick/contract";
import type { MissionDoc, OwnerPromptEntry } from "../../lib/types";

/* ---- the three top-level views (COMMAND / ORCHESTRATION / TIMELINE) --- */
export type BrickView = "grid" | "graph" | "timeline";

/* ---- StatusDot -------------------------------------------------------- */
export interface StatusDotProps {
  status: string;
  /** Optional override colour; defaults to `statusColor(status)`. */
  hue?: string;
  size?: number;
  pulse?: boolean;
}

export function StatusDot({
  status,
  hue,
  size = 8,
  pulse = true,
}: StatusDotProps): React.JSX.Element {
  const c = hue || statusColor(status);
  const animate =
    pulse &&
    (status === "live" ||
      status === "typing" ||
      status === "talking" ||
      status === "active" ||
      status === "alert");
  return (
    <span className="dot-wrap" style={{ width: size, height: size }}>
      {animate && <span className="dot-pulse" style={{ background: c }} />}
      <span
        className="dot-core"
        style={{ background: c, width: size, height: size }}
      />
    </span>
  );
}

/* ---- Pill ------------------------------------------------------------- */
export interface PillProps {
  children: React.ReactNode;
  tone?: "mute" | "ok" | "alert";
  glow?: string;
  onClick?: () => void;
  active?: boolean;
}

export function Pill({
  children,
  tone = "mute",
  glow,
  onClick,
  active,
}: PillProps): React.JSX.Element {
  return (
    <span
      className={"pill pill-" + tone + (active ? " is-active" : "")}
      onClick={onClick}
      style={onClick ? { cursor: "pointer" } : undefined}
    >
      {glow && <span className="pill-glow" style={{ background: glow }} />}
      {children}
    </span>
  );
}

/* ---- Label ------------------------------------------------------------ */
export interface LabelProps {
  children: React.ReactNode;
  right?: React.ReactNode;
}

export function Label({ children, right }: LabelProps): React.JSX.Element {
  return (
    <div className="seclabel">
      <span>{children}</span>
      {right != null && <span className="seclabel-right">{right}</span>}
    </div>
  );
}

/* ---- Panel ------------------------------------------------------------ */
export interface PanelProps {
  title?: React.ReactNode;
  right?: React.ReactNode;
  children: React.ReactNode;
  className?: string;
  flush?: boolean;
  scroll?: boolean;
}

export function Panel({
  title,
  right,
  children,
  className = "",
  flush,
  scroll,
}: PanelProps): React.JSX.Element {
  return (
    <section className={"panel " + className}>
      {title && <Label right={right}>{title}</Label>}
      <div
        className={
          "panel-body" + (flush ? " flush" : "") + (scroll ? " scroll" : "")
        }
      >
        {children}
      </div>
    </section>
  );
}

/* ---- Spark (SVG line/area sparkline) ---------------------------------- */
export interface SparkProps {
  data: number[];
  color?: string;
  w?: number;
  h?: number;
  fill?: boolean;
}

export function Spark({
  data,
  color = "#4cc2ff",
  w = 80,
  h = 22,
  fill = true,
}: SparkProps): React.JSX.Element | null {
  if (!data || !data.length) return null;
  const max = Math.max(...data, 1);
  const min = Math.min(...data, 0);
  const span = max - min || 1;
  const step = w / (data.length - 1);
  const pts = data.map(
    (v, i): [number, number] => [i * step, h - ((v - min) / span) * (h - 3) - 1.5]
  );
  const line = pts
    .map((p, i) => (i ? "L" : "M") + p[0].toFixed(1) + " " + p[1].toFixed(1))
    .join(" ");
  const area = line + ` L${w} ${h} L0 ${h} Z`;
  const gid = "sg" + color.replace("#", "");
  return (
    <svg
      width={w}
      height={h}
      className="spark"
      preserveAspectRatio="none"
      viewBox={`0 0 ${w} ${h}`}
    >
      <defs>
        <linearGradient id={gid} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor={color} stopOpacity="0.28" />
          <stop offset="1" stopColor={color} stopOpacity="0" />
        </linearGradient>
      </defs>
      {fill && <path d={area} fill={`url(#${gid})`} />}
      <path
        d={line}
        fill="none"
        stroke={color}
        strokeWidth="1.4"
        strokeLinejoin="round"
      />
    </svg>
  );
}

/* ---- Bars (bar-style sparkline, for spark counts) --------------------- */
export interface BarsProps {
  data: number[];
  color?: string;
  w?: number;
  h?: number;
}

export function Bars({
  data,
  color = "#4cc2ff",
  w = 80,
  h = 22,
}: BarsProps): React.JSX.Element {
  const max = Math.max(...data, 1);
  const bw = w / data.length;
  return (
    <svg width={w} height={h} className="spark" viewBox={`0 0 ${w} ${h}`}>
      {data.map((v, i) => {
        const bh = Math.max(1, (v / max) * (h - 2));
        return (
          <rect
            key={i}
            x={i * bw + 0.5}
            y={h - bh}
            width={Math.max(1, bw - 1)}
            height={bh}
            fill={color}
            opacity={0.35 + 0.65 * (i / data.length)}
            rx="0.5"
          />
        );
      })}
    </svg>
  );
}

/* ---- AgentGlyph ------------------------------------------------------- */
export interface AgentGlyphProps {
  agent: Pick<AgentDef, "name" | "hue">;
  size?: number;
}

export function AgentGlyph({
  agent,
  size = 26,
}: AgentGlyphProps): React.JSX.Element {
  return (
    <span
      className="glyph"
      style={{ width: size, height: size, color: agent.hue, borderColor: agent.hue + "55" }}
    >
      {agent.name}
    </span>
  );
}

/* ---- Header ----------------------------------------------------------- */
export interface HeaderProps {
  metrics: ContractMetrics;
  view: BrickView;
  setView: (v: BrickView) => void;
  alerts: ContractAlert[];
}

const HEADER_VIEWS: ReadonlyArray<{ id: BrickView; label: string }> = [
  { id: "grid", label: "COMMAND" },
  { id: "graph", label: "ORCHESTRATION" },
  { id: "timeline", label: "TIMELINE" },
];

const HEADER_LEGEND: ReadonlyArray<string> = [
  "idle",
  "typing",
  "talking",
  "alert",
];

export function Header({
  metrics,
  view,
  setView,
  alerts,
}: HeaderProps): React.JSX.Element {
  return (
    <header className="hdr">
      <div className="hdr-left">
        <div className="logo">
          WALWAL<span className="logo-dot">·</span>HARNESS
        </div>
        <span className="hdr-tag">ai_camera_web</span>
        <span className="hdr-crumb">live operations dashboard</span>
      </div>

      <nav className="viewswitch">
        {HEADER_VIEWS.map((v) => (
          <button
            key={v.id}
            className={"vs-btn" + (view === v.id ? " is-active" : "")}
            onClick={() => setView(v.id)}
          >
            {v.label}
          </button>
        ))}
      </nav>

      <div className="hdr-right">
        <Pill tone="ok" glow="#3fd17a">
          SSE <b>{metrics.sse}</b>
        </Pill>
        <Pill tone="mute">
          Hot-fix <b>{metrics.hotfix}</b>
        </Pill>
        {alerts.length > 0 && (
          <Pill tone="alert" glow="#f0506b">
            alerts <b>{alerts.length}</b>
          </Pill>
        )}
        <span className="legend">
          {HEADER_LEGEND.map((s) => (
            <span key={s} className="legend-item">
              <StatusDot status={s} size={6} pulse={false} />
              {s}
            </span>
          ))}
        </span>
      </div>
    </header>
  );
}

/* ---- Sidebar ---------------------------------------------------------- */

/** One row in the workflow-history list. */
export interface SidebarEntry {
  /** Stable id for selection / React key. */
  id: string;
  /** The displayed tag, e.g. "GOAL" | "HOT-FIX" | "SUBMIT" | "SESSION". */
  tag: string;
  /** The displayed workflow name. */
  name: string;
}

/** The mockup's static look (used when no real data is supplied). */
const GOAL_HISTORY_FALLBACK: ReadonlyArray<SidebarEntry> = [
  { id: "goal-3-test-coverage-scenario", tag: "GOAL", name: "goal-3-test-coverage-scenario" },
  { id: "ops-dev-session", tag: "SESSION", name: "ops-dev-session" },
  { id: "goal-2-rule-preset", tag: "GOAL", name: "goal-2-rule-preset" },
  { id: "hotfix-6-preset-apply", tag: "HOT-FIX", name: "hotfix-6-preset-apply" },
  { id: "hotfix-5-preset-save", tag: "HOT-FIX", name: "hotfix-5-preset-save" },
  { id: "hotfix-4-preset-apply", tag: "HOT-FIX", name: "hotfix-4-preset-apply" },
  { id: "hotfix-3-preset-save", tag: "HOT-FIX", name: "hotfix-3-preset-save" },
  { id: "hotfix-2-rename-safe", tag: "HOT-FIX", name: "hotfix-2-rename-safe" },
  { id: "hotfix-1-preset-apply", tag: "HOT-FIX", name: "hotfix-1-preset-apply" },
  { id: "submission-1-preset", tag: "SUBMIT", name: "submission-1-preset" },
  { id: "goal-1-prd-spec-docs", tag: "GOAL", name: "goal-1-prd-spec-docs" },
];

/** Map a real mission type to a sidebar display tag. */
function missionTag(type: MissionDoc["type"]): string {
  switch (type) {
    case "goal":
      return "GOAL";
    case "hotfix":
      return "HOT-FIX";
    case "submission":
      return "SUBMIT";
    case "feature":
      return "GOAL";
    default:
      return "SESSION";
  }
}

/** Map a real owner-prompt type to a sidebar display tag. */
function promptTag(type: OwnerPromptEntry["type"]): string {
  switch (type) {
    case "goal":
      return "GOAL";
    case "hot-fix":
      return "HOT-FIX";
    case "submission":
      return "SUBMIT";
    default:
      return "SESSION";
  }
}

/** CSS class suffix for a tag, matching the mockup: lowercase, no dash. */
function tagClass(tag: string): string {
  return "tag-" + tag.toLowerCase().replace("-", "");
}

/**
 * Build the workflow-history list from real data when available.
 * Prefers missions (richer label/type); falls back to ownerHistory; and
 * finally to the static mockup list so the design renders unchanged offline.
 */
export function buildSidebarEntries(
  missions?: MissionDoc[],
  ownerHistory?: OwnerPromptEntry[]
): SidebarEntry[] {
  if (missions && missions.length > 0) {
    return missions.map((m) => ({
      id: m.missionId,
      tag: missionTag(m.type),
      name: m.label || m.missionId,
    }));
  }
  if (ownerHistory && ownerHistory.length > 0) {
    return ownerHistory.map((p, i) => {
      const firstLine = (p.content ?? "").split("\n", 1)[0].trim();
      const name = firstLine.length > 0 ? firstLine : p.type;
      return {
        id: `prompt-${i}-${p.ts}`,
        tag: promptTag(p.type),
        name,
      };
    });
  }
  return GOAL_HISTORY_FALLBACK.map((e) => ({ ...e }));
}

export interface SidebarProps {
  collapsed: boolean;
  onToggle: () => void;
  /** Real missions; when present the list shows real goals/hotfixes/etc. */
  missions?: MissionDoc[];
  /** Real owner prompt history; used when missions are absent. */
  ownerHistory?: OwnerPromptEntry[];
  /** Optional bottom-half content (e.g. the ATTENTION rail), split 1:1 under the list. */
  footer?: React.ReactNode;
}

export function Sidebar({
  collapsed,
  onToggle,
  missions,
  ownerHistory,
  footer,
}: SidebarProps): React.JSX.Element {
  const entries = buildSidebarEntries(missions, ownerHistory);
  const [sel, setSel] = useState<string>(entries[0]?.id ?? "");
  return (
    <aside className={"sidebar" + (collapsed ? " is-collapsed" : "")}>
      <div className="sb-head">
        <span className="sb-avatar">AI</span>
        {!collapsed && (
          <div className="sb-id">
            <div className="sb-name">Administrator</div>
            <div className="sb-sub">workflow history</div>
          </div>
        )}
        <button className="sb-toggle" onClick={onToggle} title="collapse">
          {collapsed ? "›" : "‹"}
        </button>
      </div>
      {!collapsed && (
        <div className="sb-list">
          {entries.map((g) => (
            <button
              key={g.id}
              className={"sb-item" + (sel === g.id ? " is-active" : "")}
              onClick={() => setSel(g.id)}
            >
              <span className={"sb-tag " + tagClass(g.tag)}>
                /{g.tag.toLowerCase()}
              </span>
              <span className="sb-itemname">{g.name}</span>
            </button>
          ))}
        </div>
      )}
      {!collapsed && footer && <div className="sb-footer">{footer}</div>}
    </aside>
  );
}
