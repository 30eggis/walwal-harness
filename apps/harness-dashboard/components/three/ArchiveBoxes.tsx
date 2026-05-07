"use client";
import { Html } from "@react-three/drei";
import { ROOM_RECTS } from "@/lib/iso";
import type { ArchiveStat } from "@/lib/types";

interface ArchiveBoxesProps {
  archive: ArchiveStat;
}

// Visualises completed sprints as cardboard boxes stacked inside the archive
// room. The most-recent three are labelled (drei <Html>); the rest are
// anonymous boxes plus a "+N more" label.
export function ArchiveBoxes({ archive }: ArchiveBoxesProps) {
  const room = ROOM_RECTS.find((r) => r.id === "archive")!;
  const cols = 6;
  const rowSpacingX = (room.ww - 1.0) / cols; // leave 0.5 inset on each side
  const rowSpacingZ = 0.45;
  const baseX = room.wx + 0.5;
  const baseZ = room.wy + 0.5;

  const boxes = Array.from({ length: archive.sprintCount }, (_, i) => {
    const col = i % cols;
    const row = Math.floor(i / cols);
    return {
      x: baseX + col * rowSpacingX + rowSpacingX / 2,
      z: baseZ + row * rowSpacingZ,
      isRecent: i < 3,
      entry: i < archive.recent.length ? archive.recent[i] : null,
    };
  });

  const overflowAfterThree = Math.max(0, archive.sprintCount - 3);

  return (
    <group data-testid="archive-boxes">
      {boxes.map((b, i) => (
        <group key={i} position={[b.x, 0.21, b.z]}>
          <mesh castShadow position={[0, 0.16, 0]}>
            <boxGeometry args={[0.34, 0.32, 0.28]} />
            <meshStandardMaterial
              color={b.isRecent ? "#caa978" : "#8a7c5a"}
              roughness={0.85}
            />
          </mesh>
          {/* Tape line on top — toy cardboard cue. */}
          <mesh position={[0, 0.33, 0]}>
            <boxGeometry args={[0.36, 0.01, 0.06]} />
            <meshStandardMaterial color="#6a5a3a" />
          </mesh>
          {b.isRecent && b.entry && (
            <Html
              position={[0, 0.45, 0]}
              transform
              occlude={false}
              scale={0.08}
              pointerEvents="none"
              zIndexRange={[3, 0]}
            >
              <div className="rounded bg-black/70 px-1.5 py-0.5 text-[10px] font-mono text-gray-100 whitespace-nowrap">
                {b.entry.label}
              </div>
            </Html>
          )}
        </group>
      ))}
      {overflowAfterThree > 0 && (
        <Html
          position={[room.wx + room.ww / 2, 0.6, room.wy + room.wh - 0.3]}
          transform
          occlude={false}
          scale={0.1}
          pointerEvents="none"
        >
          <div className="rounded bg-aura-typing/40 px-2 py-0.5 text-[10px] font-mono text-aura-typing whitespace-nowrap">
            +{overflowAfterThree} more
          </div>
        </Html>
      )}
    </group>
  );
}
