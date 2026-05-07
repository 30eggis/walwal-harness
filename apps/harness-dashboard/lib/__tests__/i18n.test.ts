import { describe, it, expect } from "vitest";
import { t } from "../i18n";

describe("i18n.t", () => {
  it("returns ko by default", () => {
    expect(t("drawer.tab.agent_log")).toBe("에이전트 로그");
  });

  it("returns en when lang=en", () => {
    expect(t("drawer.tab.agent_log", "en")).toBe("Agent Log");
  });

  it("falls back to the key when missing", () => {
    expect(t("nonexistent.key", "en")).toBe("nonexistent.key");
  });
});
