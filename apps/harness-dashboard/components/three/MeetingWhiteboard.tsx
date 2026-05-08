"use client";
import { Html } from "@react-three/drei";
import { ROOM_RECTS } from "@/lib/iso";
import type { MeetingsState, ParallelTrack } from "@/lib/types";

interface MeetingWhiteboardProps {
  meetings: MeetingsState;
  tracks: ParallelTrack[];
}

const TYPE_LABEL: Record<string, { ko: string; tone: string }> = {
  standup: { ko: "스탠드업", tone: "bg-aura-typing/30 text-aura-typing" },
  "sprint-review": { ko: "스프린트 리뷰", tone: "bg-aura-talking/30 text-aura-talking" },
  "spec-review": { ko: "스펙 리뷰", tone: "bg-aura-talking/30 text-aura-talking" },
  "incident-war-room": { ko: "워룸", tone: "bg-aura-alert/30 text-aura-alert" },
  "all-hands": { ko: "올핸즈", tone: "bg-aura-typing/30 text-aura-typing" },
  "followup-review": { ko: "팔로우업", tone: "bg-aura-talking/30 text-aura-talking" },
};

const CADENCE_TONE: Record<string, string> = {
  light: "bg-aura-idle/40 text-gray-200",
  normal: "bg-aura-typing/30 text-aura-typing",
  heavy: "bg-aura-alert/30 text-aura-alert",
};

// Whiteboard mounted on the back wall of the meeting room. Surfaces:
//   - active meeting type (typed badge)
//   - cadence (light/normal/heavy)
//   - active parallel track count
// When no meeting is in session and no tracks are active, the board reads
// "idle" so the room never looks broken.
export function MeetingWhiteboard({ meetings, tracks }: MeetingWhiteboardProps) {
  const room = ROOM_RECTS.find((r) => r.id === "meeting")!;
  const cx = room.wx + room.ww / 2;
  const cz = room.wy + 0.18;
  const meeting = meetings.current;
  const typeInfo = meeting ? TYPE_LABEL[meeting.type] : null;
  const cadenceTone = CADENCE_TONE[meetings.cadence] ?? CADENCE_TONE.normal;

  return (
    <Html
      position={[cx, 0.85, cz]}
      transform
      occlude={false}
      scale={0.14}
      pointerEvents="none"
      zIndexRange={[5, 0]}
    >
      <div
        data-testid="meeting-whiteboard"
        className="rounded-md border border-brick-wall bg-brick-bg/95 px-3 py-2 shadow-lg text-gray-100 font-mono"
        style={{ minWidth: 240, maxWidth: 320 }}
      >
        <div className="text-[9px] uppercase tracking-widest text-gray-400">
          MEETING ROOM
        </div>
        <div className="mt-1 flex flex-wrap items-center gap-1">
          {typeInfo ? (
            <span
              data-testid={`meeting-type-${meeting!.type}`}
              className={`rounded px-1.5 py-0.5 text-[10px] uppercase ${typeInfo.tone}`}
            >
              {typeInfo.ko}
            </span>
          ) : (
            <span className="rounded bg-aura-idle/40 px-1.5 py-0.5 text-[10px] uppercase text-gray-300">
              유휴
            </span>
          )}
          <span
            data-testid={`cadence-${meetings.cadence}`}
            className={`rounded px-1.5 py-0.5 text-[10px] uppercase ${cadenceTone}`}
          >
            cadence: {meetings.cadence}
          </span>
          {tracks.length > 0 && (
            <span
              data-testid="track-count"
              className="rounded bg-aura-talking/30 px-1.5 py-0.5 text-[10px] uppercase text-aura-talking"
            >
              tracks ×{tracks.length}
            </span>
          )}
        </div>
        {meeting?.topic && (
          <div className="mt-1 text-[10px] text-gray-300 leading-snug">
            {meeting.topic}
          </div>
        )}
        {meetings.next_scheduled && (
          <div className="mt-1 text-[9px] text-gray-500">
            next {meetings.next_scheduled}
          </div>
        )}
      </div>
    </Html>
  );
}
