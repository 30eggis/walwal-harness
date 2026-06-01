import { defineConfig, devices } from "@playwright/test";

// Target is env-overridable so the suite can run against an already-running
// dashboard on any port (e.g. one started with a specific HARNESS_ROOT):
//   PW_BASE_URL=http://localhost:3097 PW_NO_WEBSERVER=1 npx playwright test
const baseURL = process.env.PW_BASE_URL ?? "http://localhost:3001";
const skipWebServer = process.env.PW_NO_WEBSERVER === "1";
// AGENTS.md §8: Playwright must run in a visible real browser. Headed by default;
// headless is only an explicit CI exception via PW_HEADLESS=1.
const headless = process.env.PW_HEADLESS === "1";

export default defineConfig({
  testDir: "./e2e",
  timeout: 30_000,
  expect: { timeout: 5_000 },
  fullyParallel: false,
  retries: 0,
  reporter: [["list"]],
  use: {
    baseURL,
    trace: "off",
    headless,
    channel: "chrome",
    launchOptions: { slowMo: headless ? 0 : 120 },
  },
  ...(skipWebServer
    ? {}
    : {
        webServer: {
          command: "npm run dev:dashboard",
          url: baseURL,
          reuseExistingServer: true,
          timeout: 60_000,
        },
      }),
  projects: [
    { name: "chromium", use: { ...devices["Desktop Chrome"] } },
  ],
});
