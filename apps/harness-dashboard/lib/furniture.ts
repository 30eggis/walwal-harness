import { ROOM_RECTS, type RoomRect } from "./iso";
import type { RoomId } from "./types";
import { AGENT_ROSTER } from "./agent-roster";

// How many desks each room should physically contain. The meeting room is
// over-provisioned because anyone can drop in. Room desks must accommodate the
// full roster in agent-roster.ts (CEO+Brainstormer; CTO+Conductor+4 Generators;
// CQO+5 Evaluators).
export const ROOM_CAPACITY: Record<RoomId, number> = {
  ceo: 2,
  meeting: 7,
  coo: 3,
  "cto-team": 6,
  "cqo-team": 6,
  "service-ops": 1,
  archive: 0,
};

export interface DeskSlot {
  index: number;
  // Desk position (slab top center) in world coords.
  desk: [number, number, number];
  // Where the seated character stands (chair position).
  chair: [number, number, number];
  // Facing direction (yaw, radians) — character faces the desk.
  facing: number;
}

const DESK_INSET = 0.55; // distance from room edge to desk
const DESK_SPACING_MIN = 0.85;

// Layout desks in two rows along the room's long axis, each row hugging one
// of the long walls. Chairs sit on the inside of each row.
export function deskSlotsForRoom(rect: RoomRect): DeskSlot[] {
  const cap = ROOM_CAPACITY[rect.id];
  if (cap === 0) return [];

  const slots: DeskSlot[] = [];
  const longAxisIsX = rect.ww >= rect.wh;
  const longLen = longAxisIsX ? rect.ww : rect.wh;
  const shortLen = longAxisIsX ? rect.wh : rect.ww;

  // 2 rows if room is deep enough, else 1 row.
  const rows = shortLen >= 2.0 && cap >= 3 ? 2 : 1;
  const perRow = Math.ceil(cap / rows);
  const usable = longLen - DESK_INSET * 2;
  const spacing = perRow > 1 ? Math.max(DESK_SPACING_MIN, usable / perRow) : 0;
  const startLong = rect.wx + (longAxisIsX ? DESK_INSET + spacing / 2 : 0);
  const startLongZ = rect.wy + (!longAxisIsX ? DESK_INSET + spacing / 2 : 0);

  for (let i = 0; i < cap; i++) {
    const row = i % rows;
    const col = Math.floor(i / rows);
    const longOffset = perRow > 1 ? col * spacing : longLen / 2;

    let dx: number;
    let dz: number;
    let cx: number;
    let cz: number;
    let facing: number;

    if (longAxisIsX) {
      dx = (startLong as number) + longOffset;
      // Row 0 hugs the +z wall, row 1 hugs the -z wall.
      const wallZ =
        row === 0 ? rect.wy + rect.wh - DESK_INSET : rect.wy + DESK_INSET;
      dz = wallZ;
      cx = dx;
      cz = row === 0 ? wallZ - 0.55 : wallZ + 0.55;
      facing = row === 0 ? Math.PI : 0; // face the wall (Roblox cubicle vibe)
    } else {
      dz = (startLongZ as number) + longOffset;
      const wallX =
        row === 0 ? rect.wx + rect.ww - DESK_INSET : rect.wx + DESK_INSET;
      dx = wallX;
      cx = row === 0 ? wallX - 0.55 : wallX + 0.55;
      cz = dz;
      facing = row === 0 ? -Math.PI / 2 : Math.PI / 2;
    }

    slots.push({
      index: i,
      desk: [dx, 0.2, dz],
      chair: [cx, 0.2, cz],
      facing,
    });
  }

  return slots;
}

// Stable mapping: which desk slot each agent owns in their *home* room.
// Built once at module load from AGENT_ROSTER.
const agentHomeDesk: Record<string, DeskSlot> = (() => {
  const out: Record<string, DeskSlot> = {};
  const counters = new Map<RoomId, number>();
  for (const entry of AGENT_ROSTER) {
    const slots = deskSlotsForRoom(
      ROOM_RECTS.find((r) => r.id === entry.room)!
    );
    if (slots.length === 0) continue;
    const idx = counters.get(entry.room) ?? 0;
    out[entry.id] = slots[idx % slots.length];
    counters.set(entry.room, idx + 1);
  }
  return out;
})();

export function homeDeskFor(agentId: string): DeskSlot | undefined {
  return agentHomeDesk[agentId];
}

// Door positions per room — used by Floor3D to leave gaps in the walls and by
// the meeting-room teleport logic. We pick the side that opens onto the
// largest neighbor footprint so the office reads as "all connected".
export interface DoorSpec {
  side: "north" | "south" | "east" | "west";
  // World position of the door center.
  position: [number, number];
  width: number;
}

export function doorsForRoom(rect: RoomRect): DoorSpec[] {
  const w = 1.0;
  const cx = rect.wx + rect.ww / 2;
  const cz = rect.wy + rect.wh / 2;
  const doors: DoorSpec[] = [];

  // Every room has a door on every side that opens onto a corridor — the
  // corridor mesh is drawn around all rooms in Floor3D.
  switch (rect.id) {
    case "ceo":
      doors.push({ side: "east", position: [rect.wx + rect.ww, cz], width: w });
      doors.push({ side: "south", position: [cx, rect.wy + rect.wh], width: w });
      break;
    case "meeting":
      doors.push({ side: "west", position: [rect.wx, cz], width: w });
      doors.push({ side: "east", position: [rect.wx + rect.ww, cz], width: w });
      doors.push({ side: "south", position: [cx, rect.wy + rect.wh], width: w });
      break;
    case "coo":
      doors.push({ side: "west", position: [rect.wx, cz], width: w });
      doors.push({ side: "south", position: [cx, rect.wy + rect.wh], width: w });
      break;
    case "cto-team":
      doors.push({ side: "north", position: [cx, rect.wy], width: w });
      doors.push({ side: "east", position: [rect.wx + rect.ww, cz], width: w });
      doors.push({ side: "south", position: [cx, rect.wy + rect.wh], width: w });
      break;
    case "cqo-team":
      doors.push({ side: "north", position: [cx, rect.wy], width: w });
      doors.push({ side: "west", position: [rect.wx, cz], width: w });
      doors.push({ side: "south", position: [cx, rect.wy + rect.wh], width: w });
      break;
    case "service-ops":
      doors.push({ side: "north", position: [cx, rect.wy], width: w });
      doors.push({ side: "east", position: [rect.wx + rect.ww, cz], width: w });
      break;
    case "archive":
      doors.push({ side: "north", position: [cx, rect.wy], width: w });
      doors.push({ side: "west", position: [rect.wx, cz], width: w });
      break;
  }
  return doors;
}
