"use client";
import { useEffect } from "react";

export type DrawerTab =
  | "mission-flow"      // Mission document hierarchy (PRIMARY)
  | "history"           // Owner prompt history
  | "gotchas"           // Harness gotcha knowledge base
  | "mission-doc"       // Single doc markdown view
  | "logs";             // Agent log (technical)

interface DrawerProps {
  open: boolean;
  tab: DrawerTab;
  title: string;
  onClose: () => void;
  onTabChange: (tab: DrawerTab) => void;
  children: React.ReactNode;
  mode?: "overlay" | "inline";
}

const TABS: Array<{ id: DrawerTab; label: string }> = [
  { id: "mission-flow", label: "Mission Flow" },
  { id: "history", label: "History" },
  { id: "gotchas", label: "Gotchas" },
  { id: "mission-doc", label: "Document" },
  { id: "logs", label: "Agent Log" },
];

export function Drawer({ open, tab, title, onClose, onTabChange, children, mode = "overlay" }: DrawerProps) {
  useEffect(() => {
    if (!open || mode === "inline") return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [open, onClose, mode]);

  if (mode === "inline") {
    return (
      <aside
        role="complementary"
        aria-label="Detail panel"
        data-testid="drawer"
        data-open="true"
        className="h-full min-h-[calc(100dvh-2.5rem)] rounded-md border border-brick-wall bg-brick-bg shadow-2xl flex flex-col overflow-hidden"
      >
        <header className="flex items-center justify-between border-b border-brick-wall px-4 py-3">
          <h2 className="text-sm font-mono uppercase tracking-widest text-gray-200 truncate">
            {title}
          </h2>
        </header>
        <nav className="flex flex-wrap border-b border-brick-wall text-[11px] font-mono">
          {TABS.map((t) => (
            <button
              key={t.id}
              type="button"
              data-testid={`drawer-tab-${t.id}`}
              data-active={t.id === tab}
              onClick={() => onTabChange(t.id)}
              className={`min-w-[33%] flex-1 px-2 py-2 transition-colors ${
                t.id === tab
                  ? "bg-brick-wall/50 text-gray-100 border-b-2 border-aura-typing"
                  : "text-gray-500 hover:text-gray-200"
              }`}
            >
              {t.label}
            </button>
          ))}
        </nav>
        <div className="flex-1 overflow-y-auto px-4 py-3 text-xs text-gray-200 font-mono">
          {children}
        </div>
      </aside>
    );
  }

  return (
    <>
      {/* Click-outside backdrop. Pointer-events flip with `open`. */}
      <div
        data-testid="drawer-backdrop"
        aria-hidden="true"
        onClick={onClose}
        className={`fixed inset-0 bg-black/30 transition-opacity duration-200 ${
          open ? "opacity-100 pointer-events-auto" : "opacity-0 pointer-events-none"
        }`}
      />
      <aside
        role="complementary"
        aria-label="Detail panel"
        aria-hidden={!open}
        data-testid="drawer"
        data-open={open}
        className={`fixed top-0 right-0 h-[100dvh] w-full sm:w-[50vw] sm:min-w-[600px] bg-brick-bg border-l border-brick-wall shadow-2xl flex flex-col transition-transform duration-300 ease-out ${
          open ? "translate-x-0" : "translate-x-full"
        }`}
      >
        <header className="flex items-center justify-between border-b border-brick-wall px-4 py-3">
          <h2 className="text-sm font-mono uppercase tracking-widest text-gray-200">
            {title}
          </h2>
          <button
            type="button"
            onClick={onClose}
            aria-label="Close panel"
            data-testid="drawer-close"
            className="rounded p-1 text-gray-400 hover:text-gray-100 hover:bg-brick-wall/40"
          >
            ✕
          </button>
        </header>
        <nav className="flex flex-wrap border-b border-brick-wall text-[11px] font-mono">
          {TABS.map((t) => (
            <button
              key={t.id}
              type="button"
              data-testid={`drawer-tab-${t.id}`}
              data-active={t.id === tab}
              onClick={() => onTabChange(t.id)}
              className={`min-w-[33%] flex-1 px-2 py-2 transition-colors ${
                t.id === tab
                  ? "bg-brick-wall/50 text-gray-100 border-b-2 border-aura-typing"
                  : "text-gray-500 hover:text-gray-200"
              }`}
            >
              {t.label}
            </button>
          ))}
        </nav>
        <div className="flex-1 overflow-y-auto px-4 py-3 text-xs text-gray-200 font-mono">
          {children}
        </div>
      </aside>
    </>
  );
}
