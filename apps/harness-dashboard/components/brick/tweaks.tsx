"use client";

/* =============================================================
   walwal-harness · BRICK OFFICE — Tweaks panel
   Ported from the design-handoff mockup (harness/tweaks-panel.jsx).

   Differences from the mockup (intentional, for the real Next.js app):
   - No host edit-mode protocol (postMessage __edit_mode_*). That was a
     design-tool artifact. Here the panel is self-contained: it opens by
     default, the ✕ dismisses it, and a floating pill (.twk-fab) re-opens it.
   - useTweaks persists to localStorage (SSR-safe: defaults on first render,
     hydrate from storage in an effect to avoid hydration mismatch).
   - All CSS lives in app/brick.css (the .twk-* block) — no inline <style>.

   The four real tweaks drive the shell:
     agentLayout card|list  -> GridView layout
     density     compact|comfy -> [data-density] on the shell root
     motion      active|calm|off -> live-motion intensity passed to the adapter/views
     surface     midnight|slate  -> [data-tone] on the shell root
   ============================================================= */

import React, {
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react";

/* ---- tweak value model ------------------------------------------------- */

export type AgentLayout = "card" | "list";
export type TweakDensity = "compact" | "comfy";
export type TweakMotion = "active" | "calm" | "off";
export type TweakSurface = "midnight" | "slate";

/** The persisted tweak state. */
export interface TweakValues {
  agentLayout: AgentLayout;
  density: TweakDensity;
  motion: TweakMotion;
  surface: TweakSurface;
}

export const TWEAK_DEFAULTS: TweakValues = {
  agentLayout: "card",
  density: "compact",
  motion: "active",
  surface: "slate",
};

const STORAGE_KEY = "brick.tweaks.v1";

/** Setter overloads: setTweak('key', value) or setTweak({ partial }). */
export type SetTweak = {
  <K extends keyof TweakValues>(key: K, value: TweakValues[K]): void;
  (edits: Partial<TweakValues>): void;
};

function readStored(): Partial<TweakValues> | null {
  if (typeof window === "undefined") return null;
  try {
    const raw = window.localStorage.getItem(STORAGE_KEY);
    if (!raw) return null;
    const parsed: unknown = JSON.parse(raw);
    if (parsed && typeof parsed === "object") {
      return parsed as Partial<TweakValues>;
    }
  } catch {
    // ignore corrupt/blocked storage
  }
  return null;
}

// ── useTweaks ───────────────────────────────────────────────────────────────
// Single source of truth for tweak values. setTweak persists to localStorage.
// SSR-safe: starts from defaults (so server and first client render match),
// then hydrates from storage in an effect.
export function useTweaks(
  defaults: TweakValues = TWEAK_DEFAULTS
): [TweakValues, SetTweak] {
  const [values, setValues] = useState<TweakValues>(defaults);

  useEffect(() => {
    const stored = readStored();
    if (stored) setValues((prev) => ({ ...prev, ...stored }));
  }, []);

  const setTweak = useCallback<SetTweak>(
    (keyOrEdits: keyof TweakValues | Partial<TweakValues>, val?: unknown) => {
      const edits: Partial<TweakValues> =
        typeof keyOrEdits === "object" && keyOrEdits !== null
          ? keyOrEdits
          : ({ [keyOrEdits]: val } as Partial<TweakValues>);
      setValues((prev) => {
        const next = { ...prev, ...edits };
        try {
          window.localStorage.setItem(STORAGE_KEY, JSON.stringify(next));
        } catch {
          // ignore blocked storage
        }
        return next;
      });
    },
    []
  );

  return [values, setTweak];
}

// ── TweaksPanel ─────────────────────────────────────────────────────────────
// Floating, draggable shell. Open by default; ✕ dismisses to a floating pill
// that re-opens it. Clamps itself to the viewport on resize.

const PAD = 16;

interface TweaksPanelProps {
  title?: string;
  children?: React.ReactNode;
}

export function TweaksPanel({
  title = "Tweaks",
  children,
}: TweaksPanelProps): React.JSX.Element {
  const [open, setOpen] = useState(true);
  const dragRef = useRef<HTMLDivElement | null>(null);
  const offsetRef = useRef<{ x: number; y: number }>({ x: PAD, y: PAD });

  const clampToViewport = useCallback(() => {
    const panel = dragRef.current;
    if (!panel) return;
    const w = panel.offsetWidth;
    const h = panel.offsetHeight;
    const maxRight = Math.max(PAD, window.innerWidth - w - PAD);
    const maxBottom = Math.max(PAD, window.innerHeight - h - PAD);
    offsetRef.current = {
      x: Math.min(maxRight, Math.max(PAD, offsetRef.current.x)),
      y: Math.min(maxBottom, Math.max(PAD, offsetRef.current.y)),
    };
    panel.style.right = `${offsetRef.current.x}px`;
    panel.style.bottom = `${offsetRef.current.y}px`;
  }, []);

  useEffect(() => {
    if (!open) return;
    clampToViewport();
    if (typeof ResizeObserver === "undefined") {
      window.addEventListener("resize", clampToViewport);
      return () => window.removeEventListener("resize", clampToViewport);
    }
    const ro = new ResizeObserver(clampToViewport);
    ro.observe(document.documentElement);
    return () => ro.disconnect();
  }, [open, clampToViewport]);

  const onDragStart = (e: React.MouseEvent) => {
    const panel = dragRef.current;
    if (!panel) return;
    const r = panel.getBoundingClientRect();
    const sx = e.clientX;
    const sy = e.clientY;
    const startRight = window.innerWidth - r.right;
    const startBottom = window.innerHeight - r.bottom;
    const move = (ev: MouseEvent) => {
      offsetRef.current = {
        x: startRight - (ev.clientX - sx),
        y: startBottom - (ev.clientY - sy),
      };
      clampToViewport();
    };
    const up = () => {
      window.removeEventListener("mousemove", move);
      window.removeEventListener("mouseup", up);
    };
    window.addEventListener("mousemove", move);
    window.addEventListener("mouseup", up);
  };

  if (!open) {
    return (
      <button
        type="button"
        className="twk-fab"
        aria-label="Open tweaks"
        onClick={() => setOpen(true)}
      >
        {title}
      </button>
    );
  }

  return (
    <div
      ref={dragRef}
      className="twk-panel"
      style={{ right: offsetRef.current.x, bottom: offsetRef.current.y }}
    >
      <div className="twk-hd" onMouseDown={onDragStart}>
        <b>{title}</b>
        <button
          className="twk-x"
          type="button"
          aria-label="Close tweaks"
          onMouseDown={(e) => e.stopPropagation()}
          onClick={() => setOpen(false)}
        >
          ✕
        </button>
      </div>
      <div className="twk-body">{children}</div>
    </div>
  );
}

// ── Layout helpers ──────────────────────────────────────────────────────────

interface TweakSectionProps {
  label: string;
  children?: React.ReactNode;
}

export function TweakSection({
  label,
  children,
}: TweakSectionProps): React.JSX.Element {
  return (
    <>
      <div className="twk-sect">{label}</div>
      {children}
    </>
  );
}

interface TweakRowProps {
  label: string;
  value?: React.ReactNode;
  children?: React.ReactNode;
  inline?: boolean;
}

export function TweakRow({
  label,
  value,
  children,
  inline = false,
}: TweakRowProps): React.JSX.Element {
  return (
    <div className={inline ? "twk-row twk-row-h" : "twk-row"}>
      <div className="twk-lbl">
        <span>{label}</span>
        {value != null && <span className="twk-val">{value}</span>}
      </div>
      {children}
    </div>
  );
}

// ── Controls ────────────────────────────────────────────────────────────────

/** An option for the segmented / select / color controls. */
export type TweakOption<T> = T | { value: T; label: string };

interface TweakSliderProps {
  label: string;
  value: number;
  min?: number;
  max?: number;
  step?: number;
  unit?: string;
  onChange: (v: number) => void;
}

export function TweakSlider({
  label,
  value,
  min = 0,
  max = 100,
  step = 1,
  unit = "",
  onChange,
}: TweakSliderProps): React.JSX.Element {
  return (
    <TweakRow label={label} value={`${value}${unit}`}>
      <input
        type="range"
        className="twk-slider"
        min={min}
        max={max}
        step={step}
        value={value}
        onChange={(e) => onChange(Number(e.target.value))}
      />
    </TweakRow>
  );
}

interface TweakToggleProps {
  label: string;
  value: boolean;
  onChange: (v: boolean) => void;
}

export function TweakToggle({
  label,
  value,
  onChange,
}: TweakToggleProps): React.JSX.Element {
  return (
    <div className="twk-row twk-row-h">
      <div className="twk-lbl">
        <span>{label}</span>
      </div>
      <button
        type="button"
        className="twk-toggle"
        data-on={value ? "1" : "0"}
        role="switch"
        aria-checked={value}
        onClick={() => onChange(!value)}
      >
        <i />
      </button>
    </div>
  );
}

function optLabel<T>(o: TweakOption<T>): string {
  return typeof o === "object" && o !== null && "label" in o
    ? (o as { label: string }).label
    : String(o);
}
function optValue<T>(o: TweakOption<T>): T {
  return typeof o === "object" && o !== null && "value" in o
    ? (o as { value: T }).value
    : (o as T);
}

interface TweakRadioProps<T> {
  label: string;
  value: T;
  options: ReadonlyArray<TweakOption<T>>;
  onChange: (v: T) => void;
}

export function TweakRadio<T>({
  label,
  value,
  options,
  onChange,
}: TweakRadioProps<T>): React.JSX.Element {
  const trackRef = useRef<HTMLDivElement | null>(null);
  const [dragging, setDragging] = useState(false);
  // The active value is read by pointer-move handlers attached for the lifetime
  // of a drag — ref it so a stale closure doesn't fire onChange for every move.
  const valueRef = useRef<T>(value);
  valueRef.current = value;

  // Segments wrap mid-word once per-segment width runs out (~16 chars for 2
  // options, ~10 for 3). Past that (or >3 options) fall back to a dropdown.
  const maxLen = options.reduce((m, o) => Math.max(m, optLabel(o).length), 0);
  const fitMap: Record<number, number> = { 2: 16, 3: 10 };
  const fitsAsSegments = maxLen <= (fitMap[options.length] ?? 0);

  const opts = useMemo(
    () =>
      options.map((o) => ({ value: optValue(o), label: optLabel(o) })),
    [options]
  );
  const idx = Math.max(0, opts.findIndex((o) => o.value === value));
  const n = opts.length;

  const segAt = useCallback(
    (clientX: number): T => {
      const track = trackRef.current;
      if (!track) return valueRef.current;
      const r = track.getBoundingClientRect();
      const inner = r.width - 4;
      const i = Math.floor(((clientX - r.left - 2) / inner) * n);
      return opts[Math.max(0, Math.min(n - 1, i))].value;
    },
    [n, opts]
  );

  if (!fitsAsSegments) {
    return (
      <TweakSelect
        label={label}
        value={value}
        options={options}
        onChange={onChange}
      />
    );
  }

  const onPointerDown = (e: React.PointerEvent) => {
    setDragging(true);
    const v0 = segAt(e.clientX);
    if (v0 !== valueRef.current) onChange(v0);
    const move = (ev: PointerEvent) => {
      if (!trackRef.current) return;
      const v = segAt(ev.clientX);
      if (v !== valueRef.current) onChange(v);
    };
    const up = () => {
      setDragging(false);
      window.removeEventListener("pointermove", move);
      window.removeEventListener("pointerup", up);
    };
    window.addEventListener("pointermove", move);
    window.addEventListener("pointerup", up);
  };

  return (
    <TweakRow label={label}>
      <div
        ref={trackRef}
        role="radiogroup"
        onPointerDown={onPointerDown}
        className={dragging ? "twk-seg dragging" : "twk-seg"}
      >
        <div
          className="twk-seg-thumb"
          style={{
            left: `calc(2px + ${idx} * (100% - 4px) / ${n})`,
            width: `calc((100% - 4px) / ${n})`,
          }}
        />
        {opts.map((o) => (
          <button
            key={String(o.value)}
            type="button"
            role="radio"
            aria-checked={o.value === value}
            onClick={() => onChange(o.value)}
          >
            {o.label}
          </button>
        ))}
      </div>
    </TweakRow>
  );
}

interface TweakSelectProps<T> {
  label: string;
  value: T;
  options: ReadonlyArray<TweakOption<T>>;
  onChange: (v: T) => void;
}

export function TweakSelect<T>({
  label,
  value,
  options,
  onChange,
}: TweakSelectProps<T>): React.JSX.Element {
  // <select> emits strings; map the chosen string back to the original
  // option value so the control stays type-preserving.
  const resolve = (s: string): T => {
    const m = options.find((o) => String(optValue(o)) === s);
    return m === undefined ? (s as unknown as T) : optValue(m);
  };
  return (
    <TweakRow label={label}>
      <select
        className="twk-field"
        value={String(value)}
        onChange={(e) => onChange(resolve(e.target.value))}
      >
        {options.map((o) => {
          const v = optValue(o);
          return (
            <option key={String(v)} value={String(v)}>
              {optLabel(o)}
            </option>
          );
        })}
      </select>
    </TweakRow>
  );
}

interface TweakTextProps {
  label: string;
  value: string;
  placeholder?: string;
  onChange: (v: string) => void;
}

export function TweakText({
  label,
  value,
  placeholder,
  onChange,
}: TweakTextProps): React.JSX.Element {
  return (
    <TweakRow label={label}>
      <input
        className="twk-field"
        type="text"
        value={value}
        placeholder={placeholder}
        onChange={(e) => onChange(e.target.value)}
      />
    </TweakRow>
  );
}

interface TweakNumberProps {
  label: string;
  value: number;
  min?: number;
  max?: number;
  step?: number;
  unit?: string;
  onChange: (v: number) => void;
}

export function TweakNumber({
  label,
  value,
  min,
  max,
  step = 1,
  unit = "",
  onChange,
}: TweakNumberProps): React.JSX.Element {
  const clamp = (n: number): number => {
    if (min != null && n < min) return min;
    if (max != null && n > max) return max;
    return n;
  };
  const startRef = useRef<{ x: number; val: number }>({ x: 0, val: 0 });
  const onScrubStart = (e: React.PointerEvent) => {
    e.preventDefault();
    startRef.current = { x: e.clientX, val: value };
    const decimals = (String(step).split(".")[1] ?? "").length;
    const move = (ev: PointerEvent) => {
      const dx = ev.clientX - startRef.current.x;
      const raw = startRef.current.val + dx * step;
      const snapped = Math.round(raw / step) * step;
      onChange(clamp(Number(snapped.toFixed(decimals))));
    };
    const up = () => {
      window.removeEventListener("pointermove", move);
      window.removeEventListener("pointerup", up);
    };
    window.addEventListener("pointermove", move);
    window.addEventListener("pointerup", up);
  };
  return (
    <div className="twk-num">
      <span className="twk-num-lbl" onPointerDown={onScrubStart}>
        {label}
      </span>
      <input
        type="number"
        value={value}
        min={min}
        max={max}
        step={step}
        onChange={(e) => onChange(clamp(Number(e.target.value)))}
      />
      {unit && <span className="twk-num-unit">{unit}</span>}
    </div>
  );
}

// Relative-luminance contrast pick — a checkmark over a swatch must read on
// both dark and light fills. Hex input only (#rgb / #rrggbb).
function twkIsLight(hex: string): boolean {
  const h = String(hex).replace("#", "");
  const x = h.length === 3 ? h.replace(/./g, (c) => c + c) : h.padEnd(6, "0");
  const n = parseInt(x.slice(0, 6), 16);
  if (Number.isNaN(n)) return true;
  const r = (n >> 16) & 255;
  const g = (n >> 8) & 255;
  const b = n & 255;
  return r * 299 + g * 587 + b * 114 > 148000;
}

function TwkCheck({ light }: { light: boolean }): React.JSX.Element {
  return (
    <svg viewBox="0 0 14 14" aria-hidden="true">
      <path
        d="M3 7.2 5.8 10 11 4.2"
        fill="none"
        strokeWidth="2.2"
        strokeLinecap="round"
        strokeLinejoin="round"
        stroke={light ? "rgba(0,0,0,.78)" : "#fff"}
      />
    </svg>
  );
}

/** A color tweak option: a single hex string or a 1-5 hex palette array. */
export type ColorOption = string | string[];

interface TweakColorProps {
  label: string;
  value: ColorOption;
  options?: ReadonlyArray<ColorOption>;
  onChange: (v: ColorOption) => void;
}

export function TweakColor({
  label,
  value,
  options,
  onChange,
}: TweakColorProps): React.JSX.Element {
  if (!options || !options.length) {
    return (
      <div className="twk-row twk-row-h">
        <div className="twk-lbl">
          <span>{label}</span>
        </div>
        <input
          type="color"
          className="twk-swatch"
          value={typeof value === "string" ? value : (value[0] ?? "#000000")}
          onChange={(e) => onChange(e.target.value)}
        />
      </div>
    );
  }
  // Native <input type=color> emits lowercase hex, so compare lowercased.
  const key = (o: ColorOption): string =>
    String(JSON.stringify(o)).toLowerCase();
  const cur = key(value);
  return (
    <TweakRow label={label}>
      <div className="twk-chips" role="radiogroup">
        {options.map((o, i) => {
          const colors = Array.isArray(o) ? o : [o];
          const hero = colors[0] ?? "#000000";
          const sup = colors.slice(1, 5);
          const on = key(o) === cur;
          return (
            <button
              key={i}
              type="button"
              className="twk-chip"
              role="radio"
              aria-checked={on}
              data-on={on ? "1" : "0"}
              aria-label={colors.join(", ")}
              title={colors.join(" · ")}
              style={{ background: hero }}
              onClick={() => onChange(o)}
            >
              {sup.length > 0 && (
                <span>
                  {sup.map((c, j) => (
                    <i key={j} style={{ background: c }} />
                  ))}
                </span>
              )}
              {on && <TwkCheck light={twkIsLight(hero)} />}
            </button>
          );
        })}
      </div>
    </TweakRow>
  );
}

interface TweakButtonProps {
  label: string;
  onClick: () => void;
  secondary?: boolean;
}

export function TweakButton({
  label,
  onClick,
  secondary = false,
}: TweakButtonProps): React.JSX.Element {
  return (
    <button
      type="button"
      className={secondary ? "twk-btn secondary" : "twk-btn"}
      onClick={onClick}
    >
      {label}
    </button>
  );
}

// ── BrickTweaks ───────────────────────────────────────────────────────────
// The wired-up panel for the Brick Office dashboard: the four real tweaks
// (agent layout, density, motion, surface). Mirrors the mockup App() block.

interface BrickTweaksProps {
  values: TweakValues;
  setTweak: SetTweak;
  title?: string;
}

export function BrickTweaks({
  values,
  setTweak,
  title = "Tweaks",
}: BrickTweaksProps): React.JSX.Element {
  return (
    <TweaksPanel title={title}>
      <TweakSection label="View" />
      <TweakRadio<AgentLayout>
        label="Agent layout"
        value={values.agentLayout}
        options={["card", "list"]}
        onChange={(v) => setTweak("agentLayout", v)}
      />
      <TweakRadio<TweakDensity>
        label="Density"
        value={values.density}
        options={["compact", "comfy"]}
        onChange={(v) => setTweak("density", v)}
      />
      <TweakSection label="Motion" />
      <TweakRadio<TweakMotion>
        label="Live motion"
        value={values.motion}
        options={["active", "calm", "off"]}
        onChange={(v) => setTweak("motion", v)}
      />
      <TweakSection label="Surface" />
      <TweakRadio<TweakSurface>
        label="Background"
        value={values.surface}
        options={["midnight", "slate"]}
        onChange={(v) => setTweak("surface", v)}
      />
    </TweaksPanel>
  );
}
