"use client";
import { Canvas } from "@react-three/fiber";
import { ContactShadows } from "@react-three/drei";
import type { AgentId, HarnessSnapshot, RoomId } from "@/lib/types";
import { Floor3D } from "./Floor3D";
import { Minifigs3D } from "./Minifig3D";
import { GoalCard3D } from "./GoalCard3D";
import { ArchiveBoxes } from "./ArchiveBoxes";
import { MeetingWhiteboard } from "./MeetingWhiteboard";
import { DeptBoard } from "./DeptBoard";
import { OpsSiren } from "./OpsSiren";
import { HypothesisCards } from "./HypothesisCards";
import { TrackRibbons } from "./TrackRibbons";

interface Stage3DProps {
  snapshot: HarnessSnapshot;
  lang?: "ko" | "en";
  onAgentClick?: (id: AgentId) => void;
  onRoomClick?: (id: RoomId) => void;
}

// Fixed isometric framing. R3F's built-in camera prop (with orthographic=true)
// auto-aims at the scene origin, which is exactly what we want.
export function Stage3D({ snapshot, lang = "ko", onAgentClick, onRoomClick }: Stage3DProps) {
  const ctoRoom = snapshot.rooms.find((r) => r.id === "cto-team");
  const cqoRoom = snapshot.rooms.find((r) => r.id === "cqo-team");
  return (
    <Canvas
      orthographic
      shadows
      dpr={[1, 2]}
      style={{
        width: "100%",
        height: "100%",
        display: "block",
        background: "#11151a",
      }}
      gl={{ antialias: true, preserveDrawingBuffer: true }}
      camera={{ position: [14, 14, 14], zoom: 60, near: -80, far: 120 }}
      data-testid="brick-office-canvas"
    >
      <ambientLight intensity={0.48} />
      <hemisphereLight args={["#d7f8f0", "#2f342b", 0.42]} />
      <directionalLight
        position={[8, 14, 6]}
        intensity={1.4}
        castShadow
        shadow-mapSize-width={2048}
        shadow-mapSize-height={2048}
        shadow-camera-near={1}
        shadow-camera-far={40}
        shadow-camera-left={-15}
        shadow-camera-right={15}
        shadow-camera-top={15}
        shadow-camera-bottom={-15}
      />

      {/* World grid spans x:[0..11] z:[0..9]; shift so the building (and its
          surrounding lawn/corridors) center on the camera target. */}
      <group position={[-5.5, 0, -4.5]}>
        <Floor3D rooms={snapshot.rooms} lang={lang} onRoomClick={onRoomClick} />
        <Minifigs3D agents={snapshot.agents} onAgentClick={onAgentClick} />
        <GoalCard3D
          goal={snapshot.goal}
          lang={lang}
          contract={snapshot.contract}
          escalations={snapshot.escalations}
        />
        <MeetingWhiteboard meetings={snapshot.meetings} tracks={snapshot.tracks} />
        <TrackRibbons tracks={snapshot.tracks} />
        <HypothesisCards hypothesis={snapshot.hypothesis} />
        <OpsSiren incidents={snapshot.incidents} />
        {ctoRoom && (
          <DeptBoard
            roomId="cto-team"
            contract={snapshot.contract}
            evalScores={snapshot.evalScores}
            passRate={ctoRoom.metrics?.pass_rate ?? null}
            openArchRisks={ctoRoom.metrics?.open_arch_risks}
          />
        )}
        {cqoRoom && (
          <DeptBoard
            roomId="cqo-team"
            contract={snapshot.contract}
            evalScores={snapshot.evalScores}
            passRate={cqoRoom.metrics?.pass_rate ?? null}
            openRegressions={cqoRoom.metrics?.open_regressions}
            sprintVerdict={cqoRoom.metrics?.sprint_verdict}
          />
        )}
        <ArchiveBoxes archive={snapshot.archive} />
      </group>

      <ContactShadows
        position={[0, 0.01, 0]}
        opacity={0.3}
        scale={6}
        blur={1.5}
        far={3}
      />
    </Canvas>
  );
}
