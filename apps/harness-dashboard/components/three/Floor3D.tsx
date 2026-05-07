"use client";
import { Html } from "@react-three/drei";
import { ROOM_RECTS, CORRIDOR_RECTS, type RoomRect } from "@/lib/iso";
import { ROOM_LABELS } from "@/lib/agent-roster";
import {
  deskSlotsForRoom,
  doorsForRoom,
  type DoorSpec,
} from "@/lib/furniture";
import type { RoomId, RoomState } from "@/lib/types";

const ROOM_PALETTE: Record<string, { floor: string; wall: string; trim: string }> = {
  ceo: { floor: "#3a4a72", wall: "#4d5f8f", trim: "#88a2d4" },
  meeting: { floor: "#324063", wall: "#465782", trim: "#7e98c6" },
  coo: { floor: "#374566", wall: "#48598a", trim: "#83a0d3" },
  "cto-team": { floor: "#2a3a55", wall: "#3a4d72", trim: "#6a87b5" },
  "cqo-team": { floor: "#3a304a", wall: "#4d4068", trim: "#9476c0" },
  "service-ops": { floor: "#28394d", wall: "#385069", trim: "#6da4c2" },
  archive: { floor: "#2a2d3a", wall: "#3a3d4d", trim: "#7c8197" },
};

const FLOOR_THICKNESS = 0.2;
const WALL_HEIGHT = 0.9;
const WALL_THICKNESS = 0.12;
const Y_BASE = 0;

// Build the segments for one wall, removing the slice covered by each door.
// Returns absolute world-space ranges along the wall axis (in absolute coords,
// not local-to-room).
function wallSegments(wallStart: number, wallEnd: number, doors: number[][]): Array<[number, number]> {
  const segments: Array<[number, number]> = [[wallStart, wallEnd]];
  for (const [doorStart, doorEnd] of doors) {
    const next: Array<[number, number]> = [];
    for (const [s, e] of segments) {
      if (doorEnd <= s || doorStart >= e) {
        next.push([s, e]);
        continue;
      }
      if (doorStart > s) next.push([s, doorStart]);
      if (doorEnd < e) next.push([doorEnd, e]);
    }
    segments.splice(0, segments.length, ...next);
  }
  return segments.filter(([s, e]) => e - s > 0.01);
}

function doorsBySide(rect: RoomRect, side: "north" | "south" | "east" | "west"): number[][] {
  // Returns gap intervals along the wall axis in absolute world coords.
  const out: number[][] = [];
  for (const d of doorsForRoom(rect)) {
    if (d.side !== side) continue;
    if (side === "north" || side === "south") {
      out.push([d.position[0] - d.width / 2, d.position[0] + d.width / 2]);
    } else {
      out.push([d.position[1] - d.width / 2, d.position[1] + d.width / 2]);
    }
  }
  return out;
}

interface RoomBlockProps {
  rect: RoomRect;
  room: RoomState | undefined;
  lang: "ko" | "en";
  onRoomClick?: (id: RoomId) => void;
}

function Wall({
  start,
  end,
  axis,
  fixedCoord,
  height,
  color,
}: {
  start: number;
  end: number;
  axis: "x" | "z";
  fixedCoord: number;
  height: number;
  color: string;
}) {
  const len = end - start;
  if (len <= 0.01) return null;
  const cx = axis === "x" ? (start + end) / 2 : fixedCoord;
  const cz = axis === "z" ? (start + end) / 2 : fixedCoord;
  const w = axis === "x" ? len : WALL_THICKNESS;
  const d = axis === "z" ? len : WALL_THICKNESS;
  return (
    <mesh
      castShadow
      receiveShadow
      position={[cx, FLOOR_THICKNESS + height / 2, cz]}
    >
      <boxGeometry args={[w, height, d]} />
      <meshStandardMaterial color={color} roughness={0.85} />
    </mesh>
  );
}

function Desk({
  position,
  facing,
}: {
  position: [number, number, number];
  facing: number;
}) {
  return (
    <group position={position} rotation={[0, facing, 0]}>
      {/* Desktop */}
      <mesh castShadow receiveShadow position={[0, 0.32, 0]}>
        <boxGeometry args={[0.7, 0.06, 0.4]} />
        <meshStandardMaterial color="#caa978" roughness={0.7} />
      </mesh>
      {/* Legs (front pair only — the back is hidden by the wall) */}
      <mesh castShadow position={[-0.3, 0.16, 0.16]}>
        <boxGeometry args={[0.06, 0.32, 0.06]} />
        <meshStandardMaterial color="#5a4a30" roughness={0.85} />
      </mesh>
      <mesh castShadow position={[0.3, 0.16, 0.16]}>
        <boxGeometry args={[0.06, 0.32, 0.06]} />
        <meshStandardMaterial color="#5a4a30" roughness={0.85} />
      </mesh>
      {/* Monitor */}
      <mesh castShadow position={[0, 0.5, -0.12]}>
        <boxGeometry args={[0.32, 0.22, 0.04]} />
        <meshStandardMaterial color="#1a1f2e" emissive="#22d3ee" emissiveIntensity={0.25} roughness={0.4} />
      </mesh>
      <mesh position={[0, 0.36, -0.12]}>
        <boxGeometry args={[0.06, 0.06, 0.04]} />
        <meshStandardMaterial color="#1a1f2e" />
      </mesh>
    </group>
  );
}

function Chair({ position, facing }: { position: [number, number, number]; facing: number }) {
  return (
    <group position={position} rotation={[0, facing, 0]}>
      <mesh castShadow position={[0, 0.18, 0]}>
        <boxGeometry args={[0.32, 0.06, 0.32]} />
        <meshStandardMaterial color="#2c3e63" roughness={0.7} />
      </mesh>
      <mesh castShadow position={[0, 0.34, 0.13]}>
        <boxGeometry args={[0.32, 0.32, 0.06]} />
        <meshStandardMaterial color="#2c3e63" roughness={0.7} />
      </mesh>
      <mesh position={[0, 0.06, 0]}>
        <cylinderGeometry args={[0.04, 0.04, 0.12, 8]} />
        <meshStandardMaterial color="#1a1f2e" />
      </mesh>
    </group>
  );
}

function RoomBlock({ rect, room, lang, onRoomClick }: RoomBlockProps) {
  const palette = ROOM_PALETTE[rect.id];
  const cx = rect.wx + rect.ww / 2;
  const cz = rect.wy + rect.wh / 2;
  const label = lang === "ko" ? ROOM_LABELS[rect.id].ko : ROOM_LABELS[rect.id].en;
  const verdict = room?.metrics?.sprint_verdict;
  const desks = deskSlotsForRoom(rect);

  // Walls with door gaps. North/south run along x-axis; east/west run along z-axis.
  const northSegs = wallSegments(rect.wx, rect.wx + rect.ww, doorsBySide(rect, "north"));
  const southSegs = wallSegments(rect.wx, rect.wx + rect.ww, doorsBySide(rect, "south"));
  const westSegs = wallSegments(rect.wy, rect.wy + rect.wh, doorsBySide(rect, "west"));
  const eastSegs = wallSegments(rect.wy, rect.wy + rect.wh, doorsBySide(rect, "east"));

  return (
    <group userData={{ roomId: rect.id }}>
      {/* Floor slab — placed at the room center in absolute world coords.
          Clicking the floor opens the room-metrics drawer. */}
      <mesh
        receiveShadow
        position={[cx, FLOOR_THICKNESS / 2, cz]}
        onClick={(e) => {
          e.stopPropagation();
          onRoomClick?.(rect.id);
        }}
        onPointerOver={(e) => {
          e.stopPropagation();
          document.body.style.cursor = "pointer";
        }}
        onPointerOut={() => {
          document.body.style.cursor = "default";
        }}
      >
        <boxGeometry args={[rect.ww, FLOOR_THICKNESS, rect.wh]} />
        <meshStandardMaterial color={palette.floor} roughness={0.85} metalness={0.05} />
      </mesh>

      {/* Trim border on top of floor */}
      <mesh position={[cx, FLOOR_THICKNESS + 0.02, cz]}>
        <boxGeometry args={[rect.ww, 0.04, rect.wh]} />
        <meshStandardMaterial color={palette.trim} roughness={0.5} metalness={0.2} opacity={0.35} transparent />
      </mesh>

      {/* North wall (z = rect.wy) */}
      {northSegs.map(([s, e], i) => (
        <Wall
          key={`n${i}`}
          axis="x"
          start={s}
          end={e}
          fixedCoord={rect.wy}
          height={WALL_HEIGHT}
          color={palette.wall}
        />
      ))}
      {/* South wall (z = rect.wy + rect.wh) */}
      {southSegs.map(([s, e], i) => (
        <Wall
          key={`s${i}`}
          axis="x"
          start={s}
          end={e}
          fixedCoord={rect.wy + rect.wh}
          height={WALL_HEIGHT}
          color={palette.wall}
        />
      ))}
      {/* West wall (x = rect.wx) */}
      {westSegs.map(([s, e], i) => (
        <Wall
          key={`w${i}`}
          axis="z"
          start={s}
          end={e}
          fixedCoord={rect.wx}
          height={WALL_HEIGHT}
          color={palette.wall}
        />
      ))}
      {/* East wall (x = rect.wx + rect.ww) */}
      {eastSegs.map(([s, e], i) => (
        <Wall
          key={`e${i}`}
          axis="z"
          start={s}
          end={e}
          fixedCoord={rect.wx + rect.ww}
          height={WALL_HEIGHT}
          color={palette.wall}
        />
      ))}

      {/* Door frame trim — emphasises openings */}
      {doorsForRoom(rect).map((d, i) => (
        <DoorFrame key={`door${i}`} rect={rect} door={d} color={palette.trim} />
      ))}

      {/* Desks + chairs */}
      {desks.map((slot) => (
        <group key={`desk-${slot.index}`}>
          <Desk position={slot.desk} facing={slot.facing} />
          <Chair position={slot.chair} facing={slot.facing} />
        </group>
      ))}

      {/* Room label as DOM overlay */}
      <Html
        position={[cx, FLOOR_THICKNESS + 0.05, cz + rect.wh / 2 - 0.3]}
        center
        distanceFactor={20}
        pointerEvents="none"
      >
        <span
          className="select-none rounded bg-black/55 px-2 py-0.5 text-[11px] font-mono uppercase tracking-widest text-gray-100"
          style={{ whiteSpace: "nowrap" }}
        >
          {label}
        </span>
      </Html>

      {verdict && verdict !== "pending" && (
        <Html
          position={[cx, FLOOR_THICKNESS + 0.06, cz - rect.wh / 2 + 0.3]}
          center
          distanceFactor={20}
          pointerEvents="none"
        >
          <span
            className={`select-none rounded px-1.5 py-0.5 text-[9px] font-mono ${
              verdict === "PASS"
                ? "bg-aura-typing/30 text-aura-typing"
                : "bg-aura-alert/30 text-aura-alert"
            }`}
          >
            {verdict}
          </span>
        </Html>
      )}
    </group>
  );
}

function DoorFrame({
  rect,
  door,
  color,
}: {
  rect: RoomRect;
  door: DoorSpec;
  color: string;
}) {
  const cy = FLOOR_THICKNESS + WALL_HEIGHT;
  if (door.side === "north" || door.side === "south") {
    const z = door.side === "north" ? rect.wy : rect.wy + rect.wh;
    return (
      <mesh position={[door.position[0], cy + 0.05, z]} castShadow>
        <boxGeometry args={[door.width + 0.1, 0.1, WALL_THICKNESS + 0.04]} />
        <meshStandardMaterial color={color} metalness={0.3} roughness={0.5} />
      </mesh>
    );
  }
  const x = door.side === "west" ? rect.wx : rect.wx + rect.ww;
  return (
    <mesh position={[x, cy + 0.05, door.position[1]]} castShadow>
      <boxGeometry args={[WALL_THICKNESS + 0.04, 0.1, door.width + 0.1]} />
      <meshStandardMaterial color={color} metalness={0.3} roughness={0.5} />
    </mesh>
  );
}

interface Floor3DProps {
  rooms: RoomState[];
  lang?: "ko" | "en";
  onRoomClick?: (id: RoomId) => void;
}

export function Floor3D({ rooms, lang = "ko", onRoomClick }: Floor3DProps) {
  const byId = new Map(rooms.map((r) => [r.id, r]));
  return (
    <group>
      {/* Ground / lawn — extends well past the building to give the figures
          room to stroll outside the office. */}
      <mesh receiveShadow position={[5.5, -0.05, 4.5]} rotation={[-Math.PI / 2, 0, 0]}>
        <planeGeometry args={[26, 22]} />
        <meshStandardMaterial color="#7ba27a" roughness={1} />
      </mesh>

      {/* Corridor floors — same height as room floors, lighter palette so the
          path between rooms reads as a connector. */}
      {CORRIDOR_RECTS.map((c, i) => (
        <group key={`corr-${i}`}>
          <mesh
            receiveShadow
            position={[c.wx + c.ww / 2, FLOOR_THICKNESS / 2, c.wy + c.wh / 2]}
          >
            <boxGeometry args={[c.ww, FLOOR_THICKNESS, c.wh]} />
            <meshStandardMaterial color="#9aa6b8" roughness={0.85} />
          </mesh>
          <mesh position={[c.wx + c.ww / 2, FLOOR_THICKNESS + 0.011, c.wy + c.wh / 2]}>
            <boxGeometry args={[c.ww, 0.02, c.wh]} />
            <meshStandardMaterial color="#cdd5e0" roughness={0.7} />
          </mesh>
        </group>
      ))}

      {/* Sidewalk strip leading to the entrance */}
      <mesh position={[5.5, 0.0, -1.2]} rotation={[-Math.PI / 2, 0, 0]} receiveShadow>
        <planeGeometry args={[14, 0.7]} />
        <meshStandardMaterial color="#bcc4d4" roughness={1} />
      </mesh>

      {ROOM_RECTS.map((rect) => (
        <RoomBlock
          key={rect.id}
          rect={rect}
          room={byId.get(rect.id)}
          lang={lang}
          onRoomClick={onRoomClick}
        />
      ))}

      {/* Decorative trees — placed where the corridor meets the lawn so the
          building doesn't sit on a flat green disk. */}
      {[
        [-1.8, 0.8],
        [-1.8, 4.5],
        [-1.8, 8.5],
        [12.5, 0.8],
        [12.5, 4.5],
        [12.5, 8.5],
        [3, 10.5],
        [8, 10.5],
        [5, -1.2],
        [9, -1.2],
      ].map(([x, z], i) => (
        <group key={i} position={[x, 0, z]}>
          <mesh castShadow position={[0, 0.5, 0]}>
            <cylinderGeometry args={[0.08, 0.1, 1, 8]} />
            <meshStandardMaterial color="#7a4f2e" roughness={0.95} />
          </mesh>
          <mesh castShadow position={[0, 1.2, 0]}>
            <icosahedronGeometry args={[0.55, 0]} />
            <meshStandardMaterial color="#5a8a52" roughness={0.9} />
          </mesh>
        </group>
      ))}
    </group>
  );
}
