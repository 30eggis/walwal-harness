// Wordmark for the dashboard. Avoids LEGO trade dress: no studded brick logos,
// no 2x4 standard ratio, no LEGO red/yellow scheme. Plain typographic mark.
export function Wordmark({ className = "" }: { className?: string }) {
  return (
    <span
      className={`font-mono text-xl tracking-[0.18em] uppercase ${className}`}
      aria-label="Brick Office"
    >
      <span className="text-white">Brick</span>
      <span className="text-aura-typing"> · </span>
      <span className="text-gray-200">Office</span>
    </span>
  );
}
