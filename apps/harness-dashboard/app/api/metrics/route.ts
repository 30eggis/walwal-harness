import { NextResponse } from "next/server";
import { sampleMetrics } from "@/lib/metrics/sampler";
import { resolveHarnessRoot } from "@/lib/harness-root";

// node:fs + ps/tmux child_process require the Node.js runtime (not Edge).
export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function GET() {
  const root = resolveHarnessRoot();
  const sample = await sampleMetrics(root);
  return NextResponse.json(sample, {
    status: 200,
    headers: { "Cache-Control": "no-store" },
  });
}
