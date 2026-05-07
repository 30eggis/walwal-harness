"use client";
import { useEffect } from "react";

export type DrawerTab = "agent-log" | "room-metrics" | "archive-list";

interface DrawerProps {
  open: boolean;
  tab: DrawerTab;
  title: string;
  onClose: () => void;
  onTabChange: (tab: DrawerTab) => void;
  children: React.ReactNode;
}

const TABS: Array<{ id: DrawerTab; label: string }> = [
  { id: "agent-log", label: "Agent Log" },
  { id: "room-metrics", label: "Room Metrics" },
  { id: "archive-list", label: "Archive" },
];

export function Drawer({ open, tab, title, onClose, onTabChange, children }: DrawerProps) {
  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [open, onClose]);

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
        className={`fixed top-0 right-0 h-[100dvh] w-full sm:w-[380px] bg-brick-bg border-l border-brick-wall shadow-2xl flex flex-col transition-transform duration-300 ease-out ${
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
        <nav className="flex border-b border-brick-wall text-xs font-mono">
          {TABS.map((t) => (
            <button
              key={t.id}
              type="button"
              data-testid={`drawer-tab-${t.id}`}
              data-active={t.id === tab}
              onClick={() => onTabChange(t.id)}
              className={`flex-1 px-3 py-2 transition-colors ${
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
