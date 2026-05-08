"use client";
import { useRef, useMemo } from "react";
import { useFrame } from "@react-three/fiber";
import { Html } from "@react-three/drei";
import type { Group, Mesh } from "three";
import type { AgentState, MinifigState, RoomId } from "@/lib/types";
import { ROOM_RECTS, ROAM_POOL, type RoomRect } from "@/lib/iso";
import { homeDeskFor, deskSlotsForRoom } from "@/lib/furniture";
import { planPath } from "@/lib/path-planning";

const AURA: Record<MinifigState, { color: string; emissive: number }> = {
  idle: { color: "#8696b8", emissive: 0.0 },
  queued: { color: "#60a5fa", emissive: 0.25 },
  typing: { color: "#22d3ee", emissive: 0.5 },
  talking: { color: "#fbbf24", emissive: 0.4 },
  "red-alert": { color: "#ef4444", emissive: 0.7 },
};

function hatColor(id: string): string {
  const palette = [
    "#e25555", "#5577e8", "#37a872", "#d68a2d", "#a05ad6", "#2da6c2", "#c54a8a", "#e0a02d",
    "#5a7ad6", "#54b07a", "#b06fce", "#d6624a", "#3aa5b5", "#c19425",
  ];
  let h = 0;
  for (const ch of id) h = (h * 31 + ch.charCodeAt(0)) >>> 0;
  return palette[h % palette.length];
}

interface MinifigProps {
  agent: AgentState;
  index: number;
  // Where typing pins them; undefined for archive (no desk).
  deskTarget?: { pos: [number, number, number]; facing: number };
  // Where talking pins them (a meeting-room seat).
  talkingTarget?: { pos: [number, number, number]; facing: number };
  // Phase offset so 14 minifigs don't move in lock-step.
  phase: number;
  // Initial spawn point so each minifig starts in their home room.
  spawn: [number, number];
  onClick?: () => void;
}

function lerp(a: number, b: number, t: number) {
  return a + (b - a) * t;
}

function approach(current: number, target: number, maxStep: number) {
  const diff = target - current;
  if (Math.abs(diff) <= maxStep) return target;
  return current + Math.sign(diff) * maxStep;
}

function Minifig({ agent, index, deskTarget, talkingTarget, phase, spawn, onClick }: MinifigProps) {
  const groupRef = useRef<Group>(null!);
  const leftLegRef = useRef<Mesh>(null!);
  const rightLegRef = useRef<Mesh>(null!);
  const aura = AURA[agent.minifigState];
  const hat = useMemo(() => hatColor(agent.id), [agent.id]);
  // Per-minifig RNG seeded with the agent id so random walks are distinct but
  // stable on a remount.
  const rngState = useRef<number>(
    Array.from(agent.id).reduce((h, ch) => (h * 31 + ch.charCodeAt(0)) >>> 0, 7)
  );
  const rng = () => {
    let x = rngState.current;
    x ^= x << 13;
    x ^= x >>> 17;
    x ^= x << 5;
    rngState.current = x >>> 0;
    return (rngState.current % 100000) / 100000;
  };

  const lastPos = useRef<{ x: number; z: number; yaw: number }>({
    x: spawn[0],
    z: spawn[1],
    yaw: 0,
  });
  // Free-roam path-queue state (idle only). `path[0]` is the immediate target;
  // when reached we shift it off and walk to the next. Empty queue → pick a
  // new destination via planPath which routes through doors, never walls.
  const roam = useRef<{ path: Array<[number, number]>; dwellUntil: number }>({
    path: [],
    dwellUntil: 0,
  });

  function pickRoamTarget(): [number, number] {
    return ROAM_POOL[Math.floor(rng() * ROAM_POOL.length)];
  }

  useFrame((state, delta) => {
    if (!groupRef.current) return;
    const t = state.clock.elapsedTime + phase;

    let tx = lastPos.current.x;
    let tz = lastPos.current.z;
    let targetYaw = lastPos.current.yaw;
    let isMoving = false;

    if ((agent.minifigState === "typing" || agent.minifigState === "queued") && deskTarget) {
      // Route to the desk through doors if we're currently outside the home room.
      const desiredX = deskTarget.pos[0];
      const desiredZ = deskTarget.pos[2];
      const distToDesk = Math.hypot(
        desiredX - lastPos.current.x,
        desiredZ - lastPos.current.z
      );
      if (roam.current.path.length === 0 && distToDesk > 0.05) {
        roam.current.path = planPath(
          [lastPos.current.x, lastPos.current.z],
          [desiredX, desiredZ]
        );
      }
      if (roam.current.path.length > 0) {
        [tx, tz] = roam.current.path[0];
        const dx = tx - lastPos.current.x;
        const dz = tz - lastPos.current.z;
        if (Math.abs(dx) + Math.abs(dz) > 0.01) {
          targetYaw = Math.atan2(dx, dz);
          isMoving = true;
        }
      } else {
        tx = desiredX;
        tz = desiredZ;
        targetYaw = deskTarget.facing;
      }
    } else if (agent.minifigState === "talking" && talkingTarget) {
      const desiredX = talkingTarget.pos[0];
      const desiredZ = talkingTarget.pos[2];
      const distToSeat = Math.hypot(
        desiredX - lastPos.current.x,
        desiredZ - lastPos.current.z
      );
      if (roam.current.path.length === 0 && distToSeat > 0.05) {
        roam.current.path = planPath(
          [lastPos.current.x, lastPos.current.z],
          [desiredX, desiredZ]
        );
      }
      if (roam.current.path.length > 0) {
        [tx, tz] = roam.current.path[0];
        const dx = tx - lastPos.current.x;
        const dz = tz - lastPos.current.z;
        if (Math.abs(dx) + Math.abs(dz) > 0.01) {
          targetYaw = Math.atan2(dx, dz);
          isMoving = true;
        }
      } else {
        tx = desiredX;
        tz = desiredZ;
        targetYaw = talkingTarget.facing;
      }
    } else if (agent.minifigState === "red-alert") {
      const home = deskTarget;
      if (home) {
        tx = home.pos[0] + Math.sin(t * 22) * 0.04;
        tz = home.pos[2] + Math.cos(t * 22) * 0.04;
        targetYaw = home.facing;
      }
      roam.current.path = [];
    } else {
      // idle — random destinations, but every transition between zones is
      // routed through door waypoints so we never clip walls.
      const now = state.clock.elapsedTime;
      if (roam.current.path.length === 0 && now >= roam.current.dwellUntil) {
        const dest = pickRoamTarget();
        roam.current.path = planPath(
          [lastPos.current.x, lastPos.current.z],
          dest
        );
      }

      if (roam.current.path.length > 0) {
        [tx, tz] = roam.current.path[0];
        const dx = tx - lastPos.current.x;
        const dz = tz - lastPos.current.z;
        if (Math.abs(dx) + Math.abs(dz) > 0.01) {
          targetYaw = Math.atan2(dx, dz);
          isMoving = true;
        }
      }
    }

    // Path step advance — once we're close enough to the immediate waypoint,
    // pop it and continue to the next, or start dwelling if the queue is
    // exhausted.
    if (roam.current.path.length > 0) {
      const [pt0x, pt0z] = roam.current.path[0];
      const reach = Math.hypot(pt0x - lastPos.current.x, pt0z - lastPos.current.z);
      if (reach < 0.12) {
        roam.current.path.shift();
        if (
          roam.current.path.length === 0 &&
          agent.minifigState !== "typing" &&
          agent.minifigState !== "queued" &&
          agent.minifigState !== "talking"
        ) {
          roam.current.dwellUntil = state.clock.elapsedTime + 0.4 + rng() * 1.4;
        }
      }
    }

    const speed = isMoving ? 1.6 : 1.4; // walking cadence — slower than before
    const dist = Math.hypot(tx - lastPos.current.x, tz - lastPos.current.z);
    if (dist > 0.001) {
      const step = Math.min(dist, speed * delta);
      const ratio = step / dist;
      lastPos.current.x = lerp(lastPos.current.x, tx, ratio);
      lastPos.current.z = lerp(lastPos.current.z, tz, ratio);
      if (step > 0.005) isMoving = true;
    }
    const TAU = Math.PI * 2;
    let yawDiff = ((targetYaw - lastPos.current.yaw + Math.PI) % TAU) - Math.PI;
    if (yawDiff < -Math.PI) yawDiff += TAU;
    lastPos.current.yaw = approach(lastPos.current.yaw, lastPos.current.yaw + yawDiff, 8 * delta);

    const bob = isMoving ? Math.abs(Math.sin(t * 8)) * 0.05 : Math.sin(t * 1.6) * 0.02;
    groupRef.current.position.set(lastPos.current.x, 0.18 + bob, lastPos.current.z);
    groupRef.current.rotation.y = lastPos.current.yaw;

    if (leftLegRef.current && rightLegRef.current) {
      const swing = isMoving ? Math.sin(t * 8) * 0.4 : 0;
      leftLegRef.current.rotation.x = swing;
      rightLegRef.current.rotation.x = -swing;
    }
  });

  return (
    <group
      ref={groupRef}
      userData={{ agentId: agent.id, minifigState: agent.minifigState, index }}
      onClick={(e) => {
        e.stopPropagation();
        onClick?.();
      }}
      onPointerOver={(e) => {
        e.stopPropagation();
        document.body.style.cursor = "pointer";
      }}
      onPointerOut={() => {
        document.body.style.cursor = "default";
      }}
    >
      {/* Body */}
      <mesh castShadow position={[0, 0.18, 0]}>
        <boxGeometry args={[0.32, 0.36, 0.22]} />
        <meshStandardMaterial color="#dde3ee" roughness={0.7} />
      </mesh>
      {/* Legs — pivoted at the hip so leg swing rotates the whole leg. */}
      <group position={[-0.08, 0, 0]}>
        <mesh ref={leftLegRef} castShadow position={[0, -0.06, 0]}>
          <boxGeometry args={[0.12, 0.16, 0.12]} />
          <meshStandardMaterial color="#3b4256" roughness={0.85} />
        </mesh>
      </group>
      <group position={[0.08, 0, 0]}>
        <mesh ref={rightLegRef} castShadow position={[0, -0.06, 0]}>
          <boxGeometry args={[0.12, 0.16, 0.12]} />
          <meshStandardMaterial color="#3b4256" roughness={0.85} />
        </mesh>
      </group>
      {/* Head */}
      <mesh castShadow position={[0, 0.5, 0]}>
        <sphereGeometry args={[0.16, 16, 16]} />
        <meshStandardMaterial color="#f3d6a8" roughness={0.6} />
      </mesh>
      {/* Cap base */}
      <mesh castShadow position={[0, 0.6, -0.02]}>
        <cylinderGeometry args={[0.17, 0.17, 0.1, 16]} />
        <meshStandardMaterial color={hat} roughness={0.7} />
      </mesh>
      {/* Cap brim */}
      <mesh castShadow position={[0, 0.59, 0.12]} rotation={[0.1, 0, 0]}>
        <boxGeometry args={[0.22, 0.04, 0.12]} />
        <meshStandardMaterial color={hat} roughness={0.7} />
      </mesh>

      {/* Aura ring */}
      <mesh
        rotation={[-Math.PI / 2, 0, 0]}
        position={[0, -0.17, 0]}
        scale={agent.minifigState === "red-alert" ? [1.1, 1.1, 1.1] : [1, 1, 1]}
      >
        <ringGeometry args={[0.22, 0.3, 32]} />
        <meshStandardMaterial
          color={aura.color}
          emissive={aura.color}
          emissiveIntensity={aura.emissive}
          opacity={agent.minifigState === "idle" ? 0.35 : 0.85}
          transparent
        />
      </mesh>

      {/* Talking speech bubble — Drei <Html> with transform mode keeps the
          DOM size stable under the orthographic camera, unlike distanceFactor
          which doesn't respect ortho zoom. */}
      {agent.minifigState === "talking" && (
        <>
          <mesh position={[0.18, 0.78, 0]}>
            <sphereGeometry args={[0.06, 12, 12]} />
            <meshStandardMaterial
              color="#fbbf24"
              emissive="#fbbf24"
              emissiveIntensity={0.6}
            />
          </mesh>
          <Html
            position={[0, 1.0, 0]}
            transform
            occlude={false}
            scale={0.18}
            pointerEvents="none"
            zIndexRange={[10, 0]}
          >
            <div
              data-testid={`speech-${agent.id}`}
              className="rounded-md bg-aura-talking text-black px-2 py-1 text-[14px] font-mono shadow-md whitespace-nowrap border border-yellow-500"
              style={{ minWidth: 60 }}
            >
              {(agent.talkingPreview ?? "…").slice(0, 40)}
            </div>
          </Html>
        </>
      )}
    </group>
  );
}

interface Minifigs3DProps {
  agents: AgentState[];
  onAgentClick?: (id: import("@/lib/types").AgentId) => void;
}

// Build a meeting-room seat assignment table. Talking agents fill the meeting
// desks in stable order so they don't fight for the same chair.
function meetingSeats(): Array<{ pos: [number, number, number]; facing: number }> {
  const meetingRect = ROOM_RECTS.find((r) => r.id === "meeting")!;
  return deskSlotsForRoom(meetingRect).map((s) => ({ pos: s.chair, facing: s.facing }));
}

export function Minifigs3D({ agents, onAgentClick }: Minifigs3DProps) {
  const meetingSeatList = useMemo(() => meetingSeats(), []);
  const homeRoomCache = useMemo(() => {
    const out = new Map<RoomId, RoomRect>();
    for (const r of ROOM_RECTS) out.set(r.id, r);
    return out;
  }, []);

  // Stable index for talkers so each gets the same seat.
  const talkers = agents.filter((a) => a.minifigState === "talking").map((a) => a.id);
  const talkerSeatIdx = new Map<string, number>();
  talkers.forEach((id, i) => talkerSeatIdx.set(id, i));

  return (
    <group>
      {agents.map((agent, i) => {
        const homeRect = homeRoomCache.get(agent.homeRoom);
        if (!homeRect) return null;

        const homeDesk = homeDeskFor(agent.id);
        const deskTarget = homeDesk
          ? { pos: homeDesk.chair, facing: homeDesk.facing }
          : undefined;

        let talkingTarget: { pos: [number, number, number]; facing: number } | undefined;
        if (agent.minifigState === "talking") {
          const idx = talkerSeatIdx.get(agent.id) ?? 0;
          const seat = meetingSeatList[idx % meetingSeatList.length];
          talkingTarget = seat;
        }

        // Spawn each agent at their home desk's chair (or room center if no desk).
        const spawn: [number, number] = homeDesk
          ? [homeDesk.chair[0], homeDesk.chair[2]]
          : [homeRect.wx + homeRect.ww / 2, homeRect.wy + homeRect.wh / 2];

        return (
          <Minifig
            key={agent.id}
            agent={agent}
            index={i}
            deskTarget={deskTarget}
            talkingTarget={talkingTarget}
            phase={i * 0.7}
            spawn={spawn}
            onClick={() => onAgentClick?.(agent.id)}
          />
        );
      })}
    </group>
  );
}
