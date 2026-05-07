import type { RoomId } from "./types";

// Isometric projection (2:1 dimetric). Tile basis vectors:
//   X axis (world right) → screen ( +TILE_W/2, +TILE_H/2 )
//   Y axis (world down)  → screen ( -TILE_W/2, +TILE_H/2 )
// Caller multiplies by world coordinates and adds an origin offset.
export const TILE_W = 64;
export const TILE_H = 32;

export interface ScreenPoint {
  sx: number;
  sy: number;
}

export function worldToScreen(
  wx: number,
  wy: number,
  origin: ScreenPoint = { sx: 0, sy: 0 }
): ScreenPoint {
  return {
    sx: origin.sx + (wx - wy) * (TILE_W / 2),
    sy: origin.sy + (wx + wy) * (TILE_H / 2),
  };
}

// Each room is a world-coordinate axis-aligned rectangle. Floor plan is laid out
// in a 12x8 world grid. Rectangles do not overlap interior cells.
export interface RoomRect {
  id: RoomId;
  wx: number;
  wy: number;
  ww: number;
  wh: number;
}

// Rooms are now spaced apart so the gaps between them form a real corridor
// network (1 unit wide). The corridor mesh is rendered in Floor3D.
export const ROOM_RECTS: RoomRect[] = [
  { id: "ceo",         wx: 0,  wy: 0, ww: 3, wh: 2 },
  { id: "meeting",     wx: 4,  wy: 0, ww: 3, wh: 2 },
  { id: "coo",         wx: 8,  wy: 0, ww: 3, wh: 2 },
  { id: "cto-team",    wx: 0,  wy: 3, ww: 5, wh: 3 },
  { id: "cqo-team",    wx: 6,  wy: 3, ww: 5, wh: 3 },
  { id: "service-ops", wx: 0,  wy: 7, ww: 4, wh: 2 },
  { id: "archive",     wx: 5,  wy: 7, ww: 6, wh: 2 },
];

export interface CorridorRect {
  wx: number;
  wy: number;
  ww: number;
  wh: number;
}

// Corridor segments — vertical gaps between rooms in the same row, plus the
// horizontal corridors that run between row blocks.
export const CORRIDOR_RECTS: CorridorRect[] = [
  { wx: 3, wy: 0, ww: 1, wh: 2 },   // ceo ↔ meeting
  { wx: 7, wy: 0, ww: 1, wh: 2 },   // meeting ↔ coo
  { wx: 5, wy: 3, ww: 1, wh: 3 },   // cto-team ↔ cqo-team
  { wx: 4, wy: 7, ww: 1, wh: 2 },   // service-ops ↔ archive
  { wx: 0, wy: 2, ww: 11, wh: 1 },  // horizontal corridor (top ↔ middle row)
  { wx: 0, wy: 6, ww: 11, wh: 1 },  // horizontal corridor (middle ↔ bottom row)
];

// Free-roam waypoint pool: union of room interiors + corridor cells + a few
// outdoor strolling spots. Coordinates are in world space. The minifig roam
// loop picks a random target from this list when idle, so the office reads as
// "people moving naturally" instead of marching a rectangular track.
export const ROAM_POOL: Array<[number, number]> = [
  // room interiors (center + a corner each)
  [1.5, 1], [5.5, 1], [9.5, 1],
  [2.5, 4.5], [8.5, 4.5],
  [2, 8], [8, 8],
  // corridor — top row gaps
  [3.5, 1], [3.5, 1.5], [7.5, 1], [7.5, 1.5],
  // corridor — between top and middle row (runs full width)
  [1, 2.5], [3, 2.5], [5.5, 2.5], [8, 2.5], [10, 2.5],
  // corridor — between middle and bottom row
  [1, 6.5], [3, 6.5], [5.5, 6.5], [8, 6.5], [10, 6.5],
  // corridor — between cto/cqo teams
  [5.5, 4], [5.5, 5],
  // corridor — between service-ops/archive
  [4.5, 7.5], [4.5, 8.5],
  // outdoor strolling spots
  [-1, -0.6], [12, -0.6], [-1, 4], [12, 4], [-1, 9.5], [12, 9.5],
  [3, 10], [8, 10],
];

// Canvas origin chosen so every projected room point falls inside viewBox 0..1200 x 0..720.
// World grid spans x:[0..9], y:[0..7]. Projected x range = (0-7..9-0) = -7..+9 cells →
// width (-7..+9)*TILE_W/2 = (-224..+288). Shift x so min becomes ~80.
// Projected y range = (0+0..9+7) = 0..16 cells → height 16*TILE_H/2 = 256. Shift y so top
// is at ~140 (leaves room for header inside layout).
export const ISO_ORIGIN: ScreenPoint = { sx: 80 + 224, sy: 140 };

export function roomPolygon(rect: RoomRect): string {
  const o = ISO_ORIGIN;
  const a = worldToScreen(rect.wx, rect.wy, o);
  const b = worldToScreen(rect.wx + rect.ww, rect.wy, o);
  const c = worldToScreen(rect.wx + rect.ww, rect.wy + rect.wh, o);
  const d = worldToScreen(rect.wx, rect.wy + rect.wh, o);
  return `${a.sx},${a.sy} ${b.sx},${b.sy} ${c.sx},${c.sy} ${d.sx},${d.sy}`;
}

export function roomCenter(rect: RoomRect): ScreenPoint {
  return worldToScreen(rect.wx + rect.ww / 2, rect.wy + rect.wh / 2, ISO_ORIGIN);
}

// Returns N seat positions inside a room rectangle, arranged in a grid that fits
// gracefully even when the room is small. Used by Minifig placement.
export function seatPositions(rect: RoomRect, count: number): ScreenPoint[] {
  if (count <= 0) return [];
  const cols = Math.min(count, Math.max(2, Math.floor(rect.ww)));
  const rows = Math.ceil(count / cols);
  const padX = rect.ww / (cols + 1);
  const padY = rect.wh / (rows + 1);
  const out: ScreenPoint[] = [];
  for (let i = 0; i < count; i++) {
    const col = i % cols;
    const row = Math.floor(i / cols);
    const wx = rect.wx + padX * (col + 1);
    const wy = rect.wy + padY * (row + 1);
    out.push(worldToScreen(wx, wy, ISO_ORIGIN));
  }
  return out;
}

// Given a world rectangle, returns the smallest screen-space bounding box.
// Used by tests to assert non-overlap.
export function rectBounds(rect: RoomRect): {
  minX: number;
  maxX: number;
  minY: number;
  maxY: number;
} {
  const o = ISO_ORIGIN;
  const corners = [
    worldToScreen(rect.wx, rect.wy, o),
    worldToScreen(rect.wx + rect.ww, rect.wy, o),
    worldToScreen(rect.wx + rect.ww, rect.wy + rect.wh, o),
    worldToScreen(rect.wx, rect.wy + rect.wh, o),
  ];
  return {
    minX: Math.min(...corners.map((c) => c.sx)),
    maxX: Math.max(...corners.map((c) => c.sx)),
    minY: Math.min(...corners.map((c) => c.sy)),
    maxY: Math.max(...corners.map((c) => c.sy)),
  };
}
