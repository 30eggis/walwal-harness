import { NextResponse } from "next/server";
import { readProgressLog } from "@/lib/log-filter";
import { resolveHarnessRoot } from "@/lib/harness-root";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";
export const revalidate = 0;

export async function GET(request: Request) {
  const url = new URL(request.url);
  const agentId = url.searchParams.get("agent") ?? undefined;
  const limitParam = url.searchParams.get("limit");
  const limit = limitParam ? Math.max(1, Math.min(500, parseInt(limitParam, 10))) : 50;
  const lines = readProgressLog(resolveHarnessRoot(), { agentId, limit });
  return NextResponse.json(
    { agentId: agentId ?? null, lines },
    { status: 200, headers: { "Cache-Control": "no-store" } }
  );
}
