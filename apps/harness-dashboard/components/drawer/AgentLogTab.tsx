"use client";
import { useEffect, useRef, useState } from "react";

interface AgentLogTabProps {
  agentId: string;
}

export function AgentLogTab({ agentId }: AgentLogTabProps) {
  const [lines, setLines] = useState<string[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const scrollRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    let cancelled = false;
    setLines(null);
    setError(null);
    fetch(`/api/log?agent=${encodeURIComponent(agentId)}&limit=50`)
      .then((r) => r.json())
      .then((d) => {
        if (cancelled) return;
        setLines(d.lines ?? []);
      })
      .catch((e) => {
        if (cancelled) return;
        setError(String(e));
      });
    return () => {
      cancelled = true;
    };
  }, [agentId]);

  useEffect(() => {
    if (lines && scrollRef.current) {
      scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
    }
  }, [lines]);

  if (error) {
    return <div className="text-aura-alert">Error loading log: {error}</div>;
  }
  if (lines === null) {
    return <div className="text-gray-500">Loading…</div>;
  }
  if (lines.length === 0) {
    return <div className="text-gray-500">No log lines for {agentId}.</div>;
  }
  return (
    <div ref={scrollRef} className="space-y-1 max-h-full">
      {lines.map((line, i) => (
        <div key={i} className="whitespace-pre-wrap break-words text-[11px] leading-relaxed">
          {line}
        </div>
      ))}
    </div>
  );
}
