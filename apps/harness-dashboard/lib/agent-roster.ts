import type { AgentId, Dept, RoomId } from "./types";

export interface RosterEntry {
  id: AgentId;
  name: string;
  dept: Dept;
  room: RoomId;
}

// SoT for the office roster. Derived once from .harness/agency-mapping.md §"조직 구성".
// If the harness re-organizes, update both this file and the mapping doc.
export const AGENT_ROSTER: RosterEntry[] = [
  { id: "dispatcher", name: "CEO (Dispatcher)", dept: "CEO", room: "ceo" },
  { id: "meeting-manager", name: "Meeting Manager", dept: "Meeting", room: "meeting" },
  { id: "planner", name: "COO (Planner)", dept: "Planner", room: "coo" },
  { id: "coo-developer", name: "Developer 1", dept: "Planner", room: "coo" },
  { id: "documentationer", name: "Documentationer 1", dept: "Planner", room: "coo" },
  { id: "conductor", name: "Conductor", dept: "CTO", room: "cto-team" },
  { id: "generator-backend", name: "CTO Lead — Backend", dept: "CTO", room: "cto-team" },
  { id: "generator-frontend", name: "CTO Lead — Frontend", dept: "CTO", room: "cto-team" },
  { id: "generator-designer", name: "Designer", dept: "CTO", room: "cto-team" },
  { id: "generator-devops", name: "DevOps", dept: "CTO", room: "cto-team" },
  { id: "evaluator-functional", name: "Eval — Functional", dept: "CQO", room: "cqo-team" },
  { id: "evaluator-visual", name: "Eval — Visual", dept: "CQO", room: "cqo-team" },
  { id: "evaluator-code-quality", name: "Eval — Code Quality", dept: "CQO", room: "cqo-team" },
  { id: "evaluator-architecture", name: "Eval — Architecture", dept: "CQO", room: "cqo-team" },
  { id: "evaluator-security", name: "Eval — Security", dept: "CQO", room: "cqo-team" },
  { id: "service-ops", name: "Service Ops", dept: "Operations", room: "service-ops" },
];

export const ROOM_LABELS: Record<RoomId, { ko: string; en: string; dept: Dept | "Archive" }> = {
  ceo: { ko: "CEO실", en: "CEO Office", dept: "CEO" },
  meeting: { ko: "회의실", en: "Meeting Room", dept: "Meeting" },
  coo: { ko: "COO실", en: "COO Office", dept: "Planner" },
  "cto-team": { ko: "CTO팀", en: "CTO Team", dept: "CTO" },
  "cqo-team": { ko: "CQO팀", en: "CQO Team", dept: "CQO" },
  "service-ops": { ko: "Service-Ops", en: "Service Ops", dept: "Operations" },
  archive: { ko: "아카이브", en: "Archive", dept: "Archive" },
};
