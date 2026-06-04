"use client";

/* =============================================================
   walwal-harness · BRICK OFFICE — markdown renderer + DocViewer
   Ported from design_handoff_harness_dashboard/harness/reports.jsx.

   The mockup hard-coded its report bodies in a REPORTS table; here
   buildReport returns REAL markdown supplied by the adapter
   (agent.report / worker.report), with leading YAML frontmatter
   stripped before rendering. Everything else (classNames, CSS,
   markdown grammar, DocViewer layout) is preserved verbatim.

   Exports: MD, DocViewer, buildReport
   ============================================================= */

import React, { useEffect, type CSSProperties, type ReactNode } from "react";
import {
  fmt,
  statusColor,
  type ContractState,
  type ContractAgent,
  type ContractWorker,
  type DocTarget,
} from "../../lib/brick/contract";
import { stripFrontmatter } from "../../lib/brick/adapter";
import { StatusDot } from "./ui";

/* ---- tiny markdown renderer ------------------------------------------- */

/** Inline pass: splits on `code` and **bold**, returns React children. */
function inline(text: string, key: string | number): ReactNode[] {
  const out: ReactNode[] = [];
  let rest = text;
  let i = 0;
  const re = /(`[^`]+`|\*\*[^*]+\*\*)/;
  while (rest.length) {
    const m = rest.match(re);
    if (!m || m.index === undefined) {
      out.push(rest);
      break;
    }
    if (m.index > 0) out.push(rest.slice(0, m.index));
    const tok = m[0];
    if (tok.startsWith("`")) {
      out.push(<code key={key + "-" + i}>{tok.slice(1, -1)}</code>);
    } else {
      out.push(<b key={key + "-" + i}>{tok.slice(2, -2)}</b>);
    }
    rest = rest.slice(m.index + tok.length);
    i++;
  }
  return out;
}

interface ListProps {
  ordered: boolean;
  items: string[];
}

function List({ ordered, items }: ListProps): React.JSX.Element {
  const Tag = ordered ? "ol" : "ul";
  return (
    <Tag>
      {items.map((it, i) => (
        <li key={i}>{inline(it, "li" + i)}</li>
      ))}
    </Tag>
  );
}

export interface MDProps {
  src: string;
}

/**
 * Block-level markdown renderer. Supports #/##/###, -/1. lists, `code`,
 * **bold**, > blockquote and --- rules (same grammar as the mockup).
 */
export function MD({ src }: MDProps): React.JSX.Element {
  const lines = src.split("\n");
  const blocks: ReactNode[] = [];
  // accumulate list items so consecutive bullets/numbers merge into one list
  let listOrdered: boolean | null = null;
  let listItems: string[] = [];
  let listKey = 0;
  const flush = () => {
    if (listOrdered !== null) {
      blocks.push(
        <List key={"list-" + listKey} ordered={listOrdered} items={listItems} />
      );
      listOrdered = null;
      listItems = [];
    }
  };

  lines.forEach((ln, idx) => {
    const t = ln.trimEnd();
    if (!t.trim()) {
      flush();
      return;
    }
    if (t.startsWith("### ")) {
      flush();
      blocks.push(<h4 key={idx}>{inline(t.slice(4), idx)}</h4>);
      return;
    }
    if (t.startsWith("## ")) {
      flush();
      blocks.push(<h3 key={idx}>{inline(t.slice(3), idx)}</h3>);
      return;
    }
    if (t.startsWith("# ")) {
      flush();
      blocks.push(<h2 key={idx}>{inline(t.slice(2), idx)}</h2>);
      return;
    }
    if (t === "---") {
      flush();
      blocks.push(<hr key={idx} />);
      return;
    }
    if (t.startsWith("> ")) {
      flush();
      blocks.push(<blockquote key={idx}>{inline(t.slice(2), idx)}</blockquote>);
      return;
    }
    const oli = t.match(/^(\d+)\.\s+(.*)/);
    const uli = t.match(/^[-*]\s+(.*)/);
    if (oli || uli) {
      const ordered = !!oli;
      if (listOrdered === null || listOrdered !== ordered) {
        flush();
        listOrdered = ordered;
        listKey = idx;
      }
      listItems.push(oli ? oli[2] : uli![1]);
      return;
    }
    flush();
    blocks.push(<p key={idx}>{inline(t, idx)}</p>);
  });
  flush();
  return <div className="md">{blocks}</div>;
}

/* ---- report assembly (REAL markdown, not the mockup table) ------------ */

export interface BuiltReport {
  /** Title shown in the meta block (agent work string / worker name). */
  title: string;
  /** The owning agent of this document. */
  owner: ContractAgent;
  /** Short document-kind label. */
  kind: string;
  /** Status string for the StatusDot + color. */
  status: string;
  /** Markdown body, frontmatter already stripped. */
  body: string;
}

const NO_SOURCE = "_no report source — this agent has not produced a document yet._";
const NO_WORKER_SOURCE = "_no report source — this worker has not produced a brief yet._";

/**
 * Build the document to render for a DocTarget, pulling REAL markdown from
 * the adapter-provided report strings. Agent reports are stripped of leading
 * YAML frontmatter at render time (per spec); worker reports are already
 * stripped by the adapter but stripping again is harmless and keeps the
 * render path uniform.
 */
export function buildReport(target: DocTarget, state: ContractState): BuiltReport {
  const agent =
    state.agents.find((a) => a.id === target.agent) ?? state.agents[0];

  // When opened from a timeline activity block, prefix the report with the
  // moment (time + mission) the clicked block represents.
  const moment =
    target.at != null
      ? `**Activity @ ${new Date(target.at).toLocaleString()}**` +
        (target.mission ? ` · mission \`${target.mission}\`` : "") +
        `\n\n---\n\n`
      : "";

  if (target.type === "worker") {
    const worker = target.worker;
    const body = moment + (stripFrontmatter(worker.report) || NO_WORKER_SOURCE);
    return {
      title: worker.name,
      owner: agent,
      kind: target.at != null ? "Worker · moment" : "Worker Brief",
      status: worker.status,
      body,
    };
  }

  const body = moment + (stripFrontmatter(agent.report) || NO_SOURCE);
  return {
    title: agent.work,
    owner: agent,
    kind: target.at != null ? "CXX · moment" : "CXX Document",
    status: agent.status,
    body,
  };
}

/* ---- DocViewer drawer -------------------------------------------------- */

export interface DocViewerProps {
  /** The document to show, or null to render nothing. */
  target: DocTarget | null;
  /** The live contract state. */
  state: ContractState;
  /** Close the drawer. */
  onClose: () => void;
  /** Re-point the drawer at another document (e.g. a spawned worker). */
  onRetarget: (target: DocTarget) => void;
}

/** Right-hand document drawer with the agent meta block + markdown body. */
export function DocViewer({
  target,
  state,
  onClose,
  onRetarget,
}: DocViewerProps): React.JSX.Element | null {
  useEffect(() => {
    const h = (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
    };
    window.addEventListener("keydown", h);
    return () => window.removeEventListener("keydown", h);
  }, [onClose]);

  if (!target) return null;

  const rep = buildReport(target, state);
  const a = rep.owner;
  const mine = state.workers.filter((w) => w.agent === a.id);
  const hueVar = { "--hue": a.hue } as CSSProperties;

  return (
    <div className="docroot">
      <div className="docback" onClick={onClose} />
      <aside className="docview" style={hueVar}>
        <div className="docview-bar">
          <span className="docview-crumb">
            DOCUMENT VIEWER <span className="dv-sep">·</span>
            <span style={{ color: a.hue }}>{a.name}</span>
            {target.type === "worker" && (
              <>
                <span className="dv-sep">·</span> {target.worker.name}
              </>
            )}
          </span>
          <button className="docview-x" onClick={onClose}>
            esc ✕
          </button>
        </div>
        <div className="docview-scroll">
          <div className="docview-meta">
            <span
              className="glyph glyph-lg"
              style={{ color: a.hue, borderColor: a.hue + "66" }}
            >
              {a.name}
            </span>
            <div className="dvm-id">
              <div className="dvm-kind">{rep.kind}</div>
              <div className="dvm-status" style={{ color: statusColor(rep.status) }}>
                <StatusDot status={rep.status} size={7} />
                {rep.status}
              </div>
            </div>
            <div className="dvm-time">{fmt.time(new Date(state.now))}</div>
          </div>

          {target.type === "agent" && mine.length > 0 && (
            <div className="dvm-workers">
              <span className="dvm-wlabel">spawned workers</span>
              {mine.map((w: ContractWorker) => (
                <button
                  key={w.id}
                  className="dvm-wchip"
                  onClick={() =>
                    onRetarget({ type: "worker", agent: a.id, worker: w })
                  }
                >
                  <StatusDot status={w.status} size={5} pulse={false} />
                  {w.name} <em>{w.progress == null ? "—" : Math.round(w.progress) + "%"}</em>
                </button>
              ))}
            </div>
          )}

          <MD src={rep.body} />
        </div>
      </aside>
    </div>
  );
}
