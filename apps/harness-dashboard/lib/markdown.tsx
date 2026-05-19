"use client";
import React from "react";

// ---------------------------------------------------------------------------
// Inline renderer — handles **bold**, `code`, *italic*
// ---------------------------------------------------------------------------
function renderInline(text: string): React.ReactNode[] {
  const parts: React.ReactNode[] = [];
  // Pattern order matters: bold, inline-code, italic
  const re = /(\*\*(.+?)\*\*|`(.+?)`|\*(.+?)\*)/g;
  let last = 0;
  let match: RegExpExecArray | null;
  let key = 0;

  while ((match = re.exec(text)) !== null) {
    if (match.index > last) {
      parts.push(text.slice(last, match.index));
    }
    if (match[0].startsWith("**")) {
      parts.push(
        <strong key={key++} className="text-white font-semibold">
          {match[2]}
        </strong>
      );
    } else if (match[0].startsWith("`")) {
      parts.push(
        <code
          key={key++}
          className="bg-gray-800 text-amber-300 text-[11px] px-1 rounded"
        >
          {match[3]}
        </code>
      );
    } else {
      parts.push(
        <em key={key++} className="italic text-gray-300">
          {match[4]}
        </em>
      );
    }
    last = match.index + match[0].length;
  }
  if (last < text.length) parts.push(text.slice(last));
  return parts;
}

// ---------------------------------------------------------------------------
// Table renderer
// ---------------------------------------------------------------------------
function renderTable(rows: string[]): React.ReactNode {
  // rows[0] = header, rows[1] = separator, rows[2+] = data
  const parseRow = (row: string): string[] =>
    row
      .split("|")
      .map((c) => c.trim())
      .filter((_, i, arr) => i > 0 && i < arr.length - 1);

  const headers = parseRow(rows[0]);
  const dataRows = rows.slice(2).map(parseRow);

  return (
    <div key={Math.random()} className="overflow-x-auto">
      <table className="w-full border-collapse font-mono text-[11px]">
        <thead>
          <tr>
            {headers.map((h, i) => (
              <th
                key={i}
                className="border border-gray-700/60 bg-gray-800/50 px-2 py-1 text-left text-cyan-300/90"
              >
                {renderInline(h)}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {dataRows.map((row, ri) => (
            <tr key={ri} className="border-b border-gray-700/40">
              {row.map((cell, ci) => (
                <td
                  key={ci}
                  className="border border-gray-700/40 px-2 py-1 text-gray-300"
                >
                  {renderInline(cell)}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Block renderer state machine
// ---------------------------------------------------------------------------
function renderBlocks(content: string): React.ReactNode[] {
  const lines = content.split("\n");
  const nodes: React.ReactNode[] = [];
  let i = 0;
  let keyCounter = 0;
  const k = () => keyCounter++;

  while (i < lines.length) {
    const line = lines[i];

    // ---- Fenced code block ----
    if (line.startsWith("```")) {
      const lang = line.slice(3).trim();
      const codeLines: string[] = [];
      i++;
      while (i < lines.length && !lines[i].startsWith("```")) {
        codeLines.push(lines[i]);
        i++;
      }
      i++; // skip closing ```
      nodes.push(
        <pre
          key={k()}
          className="overflow-x-auto rounded border border-gray-700/60 bg-[#0d1117] p-3 my-2"
        >
          <code className="text-emerald-300/90 text-[11px] font-mono whitespace-pre">
            {lang ? (
              <span className="block text-[10px] text-gray-600 mb-1">{lang}</span>
            ) : null}
            {codeLines.join("\n")}
          </code>
        </pre>
      );
      continue;
    }

    // ---- HR ----
    if (/^---+$/.test(line.trim())) {
      nodes.push(<hr key={k()} className="border-gray-700/50 my-3" />);
      i++;
      continue;
    }

    // ---- H1 ----
    if (line.startsWith("# ")) {
      nodes.push(
        <h1 key={k()} className="text-[16px] font-bold text-white mt-3 mb-1">
          {renderInline(line.slice(2))}
        </h1>
      );
      i++;
      continue;
    }

    // ---- H2 ----
    if (line.startsWith("## ")) {
      nodes.push(
        <h2
          key={k()}
          className="text-[13px] font-bold text-cyan-300/90 mt-4 mb-0.5 pb-0.5 border-b border-gray-700/40"
        >
          {renderInline(line.slice(3))}
        </h2>
      );
      i++;
      continue;
    }

    // ---- H3 ----
    if (line.startsWith("### ")) {
      nodes.push(
        <h3 key={k()} className="text-[12px] font-semibold text-gray-200 mt-3 mb-0.5">
          {renderInline(line.slice(4))}
        </h3>
      );
      i++;
      continue;
    }

    // ---- H4 ----
    if (line.startsWith("#### ")) {
      nodes.push(
        <h4 key={k()} className="text-[11px] font-semibold text-gray-300 mt-2 mb-0.5">
          {renderInline(line.slice(5))}
        </h4>
      );
      i++;
      continue;
    }

    // ---- Table ----
    if (line.includes("|") && i + 1 < lines.length && /^\|?[\s\-:|]+\|/.test(lines[i + 1])) {
      const tableRows: string[] = [line];
      i++;
      while (i < lines.length && lines[i].includes("|")) {
        tableRows.push(lines[i]);
        i++;
      }
      if (tableRows.length >= 2) {
        nodes.push(
          <div key={k()} className="my-2">
            {renderTable(tableRows)}
          </div>
        );
      }
      continue;
    }

    // ---- Checkbox list items ----
    if (/^- \[x\]/i.test(line)) {
      nodes.push(
        <div key={k()} className="flex items-start gap-1.5 text-[12px] text-gray-300 pl-2">
          <span className="text-emerald-400 shrink-0">✓</span>
          <span>{renderInline(line.slice(6).trim())}</span>
        </div>
      );
      i++;
      continue;
    }
    if (/^- \[ \]/.test(line)) {
      nodes.push(
        <div key={k()} className="flex items-start gap-1.5 text-[12px] text-gray-400 pl-2">
          <span className="text-gray-600 shrink-0">○</span>
          <span>{renderInline(line.slice(6).trim())}</span>
        </div>
      );
      i++;
      continue;
    }

    // ---- Bullet list ----
    if (/^(\s*)([-*])\s/.test(line)) {
      const listItems: React.ReactNode[] = [];
      while (i < lines.length && /^(\s*)([-*])\s/.test(lines[i])) {
        const indent = lines[i].match(/^(\s*)/)?.[1].length ?? 0;
        const text = lines[i].replace(/^\s*[-*]\s/, "");
        listItems.push(
          <li
            key={k()}
            style={{ paddingLeft: indent > 0 ? `${indent * 8}px` : undefined }}
            className="flex items-start gap-1.5"
          >
            <span className="text-gray-600 shrink-0 mt-0.5">•</span>
            <span>{renderInline(text)}</span>
          </li>
        );
        i++;
      }
      nodes.push(
        <ul key={k()} className="space-y-0.5 text-[12px] text-gray-300 my-1">
          {listItems}
        </ul>
      );
      continue;
    }

    // ---- Numbered list ----
    if (/^\d+\.\s/.test(line)) {
      const listItems: React.ReactNode[] = [];
      let num = 1;
      while (i < lines.length && /^\d+\.\s/.test(lines[i])) {
        const text = lines[i].replace(/^\d+\.\s/, "");
        listItems.push(
          <li key={k()} className="flex items-start gap-1.5">
            <span className="text-gray-500 shrink-0 tabular-nums">{num}.</span>
            <span>{renderInline(text)}</span>
          </li>
        );
        i++;
        num++;
      }
      nodes.push(
        <ol key={k()} className="space-y-0.5 text-[12px] text-gray-300 my-1">
          {listItems}
        </ol>
      );
      continue;
    }

    // ---- Blank line ----
    if (line.trim() === "") {
      i++;
      continue;
    }

    // ---- Regular paragraph ----
    nodes.push(
      <p key={k()} className="text-gray-300 text-[12px] leading-relaxed">
        {renderInline(line)}
      </p>
    );
    i++;
  }

  return nodes;
}

// ---------------------------------------------------------------------------
// Public component
// ---------------------------------------------------------------------------
export function MarkdownView({ source }: { source: string }) {
  // Strip YAML frontmatter (between --- ... ---)
  const content = source.replace(/^---[\s\S]*?---\n+/, "").trim();
  return (
    <div className="space-y-1.5 text-[12px] leading-relaxed">
      {renderBlocks(content)}
    </div>
  );
}
