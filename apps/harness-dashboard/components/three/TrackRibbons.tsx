"use client";
import { Html } from "@react-three/drei";
import { ROOM_RECTS } from "@/lib/iso";
import type { ParallelTrack, RoomId } from "@/lib/types";

interface TrackRibbonsProps {
  tracks: ParallelTrack[];
}

const STATUS_COLOR: Record<string, string> = {
  dispatched: "#fbbf24",
  in_progress: "#22d3ee",
  joined: "#34d399",
  blocked: "#ef4444",
};

function roomCenter(roomId: RoomId): [number, number] | null {
  const r = ROOM_RECTS.find((x) => x.id === roomId);
  if (!r) return null;
  return [r.wx + r.ww / 2, r.wy + r.wh / 2];
}

// Floor ribbon connecting the meeting room to each fork target room. Each
// track is a flat plane at floor height, coloured by status. Renders a small
// floating tag at the midpoint with the track id.
export function TrackRibbons({ tracks }: TrackRibbonsProps) {
  if (tracks.length === 0) return null;
  const meetingCenter = roomCenter("meeting");
  if (!meetingCenter) return null;
  const [mx, mz] = meetingCenter;

  return (
    <group data-testid="track-ribbons">
      {tracks.map((t) => {
        const target = roomCenter(t.to_room);
        if (!target) return null;
        const [tx, tz] = target;
        const dx = tx - mx;
        const dz = tz - mz;
        const length = Math.hypot(dx, dz);
        if (length < 0.01) return null;
        const yaw = Math.atan2(dx, dz);
        const cx = (mx + tx) / 2;
        const cz = (mz + tz) / 2;
        const color = STATUS_COLOR[t.status] ?? STATUS_COLOR.dispatched;

        return (
          <group key={t.id}>
            <mesh
              position={[cx, 0.22, cz]}
              rotation={[-Math.PI / 2, 0, -yaw]}
            >
              <planeGeometry args={[0.3, length]} />
              <meshBasicMaterial
                color={color}
                transparent
                opacity={t.status === "joined" ? 0.35 : 0.55}
                depthWrite={false}
              />
            </mesh>
            <Html
              position={[cx, 0.4, cz]}
              transform
              occlude={false}
              scale={0.08}
              pointerEvents="none"
            >
              <div
                data-testid={`track-${t.id}`}
                className="rounded bg-black/80 px-1.5 py-0.5 text-[10px] font-mono whitespace-nowrap"
                style={{ color }}
              >
                {t.id} · {t.status}
              </div>
            </Html>
          </group>
        );
      })}
    </group>
  );
}
