"use client";
import { useRef } from "react";
import { useFrame } from "@react-three/fiber";
import { Html } from "@react-three/drei";
import type { Mesh } from "three";
import { ROOM_RECTS } from "@/lib/iso";
import type { IncidentEntry } from "@/lib/types";

interface OpsSirenProps {
  incidents: IncidentEntry[];
}

// Rotating light fixture mounted on the Service-Ops ceiling. When there's no
// open incident, the bulb is a dim grey dome — drawing the eye to the room
// only when something is actually wrong.
export function OpsSiren({ incidents }: OpsSirenProps) {
  const room = ROOM_RECTS.find((r) => r.id === "service-ops")!;
  const cx = room.wx + room.ww / 2;
  const cz = room.wy + 0.4;
  const bulbRef = useRef<Mesh>(null);
  const beamRef = useRef<Mesh>(null);
  const active = incidents.length > 0;
  const critical = incidents.some((i) => i.severity === "critical" || i.severity === "high");

  useFrame((state, _delta) => {
    if (!bulbRef.current || !beamRef.current) return;
    const t = state.clock.elapsedTime;
    if (active) {
      // Strobe pulse — faster when there's a high/critical incident.
      const speed = critical ? 6 : 3;
      const intensity = (Math.sin(t * speed) + 1) / 2;
      const mat = bulbRef.current.material as { emissiveIntensity?: number };
      if (mat.emissiveIntensity !== undefined) {
        mat.emissiveIntensity = 0.4 + intensity * 1.6;
      }
      beamRef.current.rotation.y = t * (critical ? 4 : 2);
      beamRef.current.visible = true;
    } else {
      const mat = bulbRef.current.material as { emissiveIntensity?: number };
      if (mat.emissiveIntensity !== undefined) {
        mat.emissiveIntensity = 0.05;
      }
      beamRef.current.visible = false;
    }
  });

  const color = active ? (critical ? "#ef4444" : "#f59e0b") : "#3b4256";

  return (
    <group data-testid="ops-siren" position={[cx, 0, cz]}>
      {/* Wall-mounted dome */}
      <mesh position={[0, 1.05, 0]} castShadow>
        <cylinderGeometry args={[0.12, 0.12, 0.06, 16]} />
        <meshStandardMaterial color="#1a1f2e" roughness={0.6} />
      </mesh>
      <mesh ref={bulbRef} position={[0, 1.0, 0]}>
        <sphereGeometry args={[0.14, 24, 24]} />
        <meshStandardMaterial
          color={color}
          emissive={color}
          emissiveIntensity={active ? 1.2 : 0.05}
          roughness={0.3}
        />
      </mesh>
      {/* Sweeping beam — a thin cone made visible only when active. */}
      <group ref={beamRef} position={[0, 0.95, 0]}>
        <mesh rotation={[Math.PI / 2, 0, 0]} position={[0, 0, 0.6]}>
          <coneGeometry args={[0.4, 1.2, 16, 1, true]} />
          <meshBasicMaterial
            color={color}
            transparent
            opacity={0.18}
            depthWrite={false}
          />
        </mesh>
      </group>
      {active && (
        <Html
          position={[0, 1.4, 0]}
          transform
          occlude={false}
          scale={0.1}
          pointerEvents="none"
        >
          <div
            data-testid="ops-incident-badge"
            className={`rounded px-1.5 py-0.5 text-[10px] font-mono uppercase ${
              critical
                ? "bg-aura-alert text-black"
                : "bg-aura-talking text-black"
            }`}
          >
            {incidents.length} incident{incidents.length === 1 ? "" : "s"}
          </div>
        </Html>
      )}
    </group>
  );
}
