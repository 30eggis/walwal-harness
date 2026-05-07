import { ROOM_RECTS, CORRIDOR_RECTS } from "./iso";
import { doorsForRoom } from "./furniture";
import type { RoomId } from "./types";

export type Zone = RoomId | "corridor" | "outdoor";

export function zoneAt(x: number, z: number): Zone {
  for (const r of ROOM_RECTS) {
    if (x >= r.wx && x <= r.wx + r.ww && z >= r.wy && z <= r.wy + r.wh) {
      return r.id;
    }
  }
  for (const c of CORRIDOR_RECTS) {
    if (x >= c.wx && x <= c.wx + c.ww && z >= c.wy && z <= c.wy + c.wh) {
      return "corridor";
    }
  }
  return "outdoor";
}

// Returns the corridor-side foot of the room's primary door — i.e. a point
// just outside the wall, so a minifig walking to it leaves the room cleanly
// through the door opening.
export function exitWaypoint(roomId: RoomId): [number, number] | null {
  const rect = ROOM_RECTS.find((r) => r.id === roomId);
  if (!rect) return null;
  const doors = doorsForRoom(rect);
  if (doors.length === 0) return null;
  // Pick the door that points "down" (toward south corridor) when available;
  // it gives the most natural look because all rooms have a south or north
  // corridor adjacency.
  const preferred =
    doors.find((d) => d.side === "south") ??
    doors.find((d) => d.side === "north") ??
    doors[0];
  const offset = 0.6;
  switch (preferred.side) {
    case "north":
      return [preferred.position[0], preferred.position[1] - offset];
    case "south":
      return [preferred.position[0], preferred.position[1] + offset];
    case "east":
      return [preferred.position[0] + offset, preferred.position[1]];
    case "west":
      return [preferred.position[0] - offset, preferred.position[1]];
  }
}

// Plans a wall-respecting path from `from` to `to`.
// Rule: leaving a room or entering a room must pass through that room's door.
// Movement within the same zone (or between corridor / outdoor) is direct.
export function planPath(
  from: [number, number],
  to: [number, number]
): Array<[number, number]> {
  const fromZone = zoneAt(from[0], from[1]);
  const toZone = zoneAt(to[0], to[1]);
  const waypoints: Array<[number, number]> = [];

  const isRoom = (z: Zone): z is RoomId => z !== "corridor" && z !== "outdoor";

  if (isRoom(fromZone) && fromZone !== toZone) {
    const exit = exitWaypoint(fromZone);
    if (exit) waypoints.push(exit);
  }
  if (isRoom(toZone) && fromZone !== toZone) {
    const entry = exitWaypoint(toZone);
    if (entry) waypoints.push(entry);
  }
  waypoints.push(to);
  return waypoints;
}
