import { NextResponse } from "next/server";
import { execFileSync } from "node:child_process";
import { existsSync } from "node:fs";
import path from "node:path";
import { resolveHarnessRoot } from "@/lib/harness-root";

export const dynamic = "force-dynamic";

// Per-project hourly-wake launchd control, keyed by HARNESS_BASE_PORT. The
// dashboard runs locally for the Owner, so it may toggle the Owner's own
// launchd job. Only the fixed subcommands status|on|off are ever invoked.
function runControl(action: "status" | "on" | "off") {
  const root = resolveHarnessRoot();
  const script = path.join(root, "scripts", "harness-wake-control.sh");
  if (!existsSync(script)) {
    return { supported: false, enabled: false, error: "harness-wake-control.sh not installed in this project" };
  }
  try {
    const out = execFileSync("bash", [script, action, root], {
      encoding: "utf8",
      timeout: 20000,
    });
    const lastLine = out.trim().split("\n").filter(Boolean).pop() ?? "{}";
    return JSON.parse(lastLine);
  } catch (e) {
    return { supported: false, enabled: false, error: (e as Error).message };
  }
}

export async function GET() {
  return NextResponse.json(runControl("status"));
}

export async function POST(req: Request) {
  const body = (await req.json().catch(() => ({}))) as { action?: string };
  const action = body.action === "on" ? "on" : body.action === "off" ? "off" : null;
  if (!action) {
    return NextResponse.json({ error: "action must be 'on' or 'off'" }, { status: 400 });
  }
  return NextResponse.json(runControl(action));
}
