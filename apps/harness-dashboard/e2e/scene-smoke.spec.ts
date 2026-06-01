import { test, expect } from "@playwright/test";

// Minimal visual/interaction smoke for the current mission-centric dashboard
// (components/Scene.tsx). Replaces the obsolete 2.5D brick-office spec. Runs in
// CI / against an installed project (the webServer in playwright.config serves
// the dashboard); not executed in the bare package repo, which has no .harness.
test("dashboard mounts: header, wordmark, and goal navigator render without console errors", async ({ page }) => {
  // Real client errors only — filter dev-server / browser noise.
  const BENIGN = [
    "favicon",
    "ResizeObserver loop",
    "React DevTools",
    "source map",
    "[Fast Refresh]",
    "hydrat", // Next dev hydration warnings
  ];
  const isBenign = (t: string) => BENIGN.some((b) => t.toLowerCase().includes(b.toLowerCase()));
  const errors: string[] = [];
  page.on("console", (msg) => {
    if (msg.type() !== "error") return;
    const t = msg.text();
    // Resource-load failures are reported here without the URL — covered by the
    // 'response' listener below, which has the URL to filter on.
    if (t.includes("Failed to load resource")) return;
    if (!isBenign(t)) errors.push(`console: ${t}`);
  });
  page.on("pageerror", (err) => { if (!isBenign(err.message)) errors.push(`pageerror: ${err.message}`); });
  // Catch real HTTP failures (broken API/page) but ignore favicon, Next static,
  // and source maps that 404 harmlessly in dev.
  page.on("response", (resp) => {
    if (resp.status() < 400) return;
    const u = resp.url();
    if (/favicon|\.map(\?|$)|\/_next\//.test(u)) return;
    errors.push(`http ${resp.status()}: ${u}`);
  });

  await page.goto("/");

  // Top header chrome is always present (project badge + live label).
  await expect(page.locator("header")).toBeVisible();
  await expect(page.getByText("walwal-harness", { exact: false })).toBeVisible();

  // The left workflow-history navigator always renders its /goal section,
  // whether or not a mission exists yet.
  await expect(page.getByText("/goal", { exact: false }).first()).toBeVisible();

  // No uncaught client errors on first paint.
  expect(errors, errors.join("\n")).toHaveLength(0);
});
