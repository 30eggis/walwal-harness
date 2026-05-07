import { describe, it, expect } from "vitest";
import { ROOM_RECTS, CORRIDOR_RECTS, worldToScreen } from "../iso";

describe("iso projection", () => {
  it("worldToScreen is a pure linear transform", () => {
    const a = worldToScreen(0, 0);
    expect(a).toEqual({ sx: 0, sy: 0 });
    const b = worldToScreen(2, 0);
    const c = worldToScreen(0, 2);
    expect(b.sy).toBe(c.sy);
    expect(b.sx).toBe(-c.sx);
  });

  it("rooms do not overlap corridors (corridors fill the gaps)", () => {
    for (const r of ROOM_RECTS) {
      for (const c of CORRIDOR_RECTS) {
        const overlapX = r.wx < c.wx + c.ww && c.wx < r.wx + r.ww;
        const overlapY = r.wy < c.wy + c.wh && c.wy < r.wy + r.wh;
        expect(
          overlapX && overlapY,
          `room ${r.id} overlaps corridor at (${c.wx},${c.wy})`
        ).toBe(false);
      }
    }
  });

  it("rooms have unique ids and non-overlapping world rectangles", () => {
    const ids = new Set(ROOM_RECTS.map((r) => r.id));
    expect(ids.size).toBe(ROOM_RECTS.length);
    expect(ROOM_RECTS.length).toBe(7);

    for (let i = 0; i < ROOM_RECTS.length; i++) {
      for (let j = i + 1; j < ROOM_RECTS.length; j++) {
        const a = ROOM_RECTS[i];
        const b = ROOM_RECTS[j];
        const overlapX = a.wx < b.wx + b.ww && b.wx < a.wx + a.ww;
        const overlapY = a.wy < b.wy + b.wh && b.wy < a.wy + a.wh;
        expect(overlapX && overlapY, `rooms overlap: ${a.id} vs ${b.id}`).toBe(false);
      }
    }
  });
});
