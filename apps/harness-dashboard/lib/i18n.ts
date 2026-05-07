export type Lang = "ko" | "en";

const DICT: Record<string, { ko: string; en: string }> = {
  "banner.run_dispatcher_first.ko": {
    ko: "Dispatcher를 먼저 실행하세요.",
    en: "Run Dispatcher first.",
  },
  "banner.progress_corrupt": {
    ko: "progress.json이 손상되었습니다.",
    en: "progress.json is corrupt.",
  },
  "drawer.tab.agent_log": { ko: "에이전트 로그", en: "Agent Log" },
  "drawer.tab.room_metrics": { ko: "룸 메트릭", en: "Room Metrics" },
  "drawer.tab.archive_list": { ko: "아카이브", en: "Archive" },
  "header.subtitle": {
    ko: "walwal-harness 라이브 운영 대시보드",
    en: "walwal-harness live operations dashboard",
  },
  "goal.empty": { ko: "활성 GOAL 없음", en: "No active goal" },
};

export function t(key: string, lang: Lang = "ko"): string {
  const entry = DICT[key];
  if (!entry) return key;
  return entry[lang] ?? entry.ko ?? key;
}
