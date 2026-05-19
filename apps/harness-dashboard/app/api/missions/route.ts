import { NextResponse } from "next/server";
import { readHarnessState } from "@/lib/harness-state";
import { resolveHarnessRoot } from "@/lib/harness-root";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";
export const revalidate = 0;

export async function GET() {
  const snapshot = readHarnessState(resolveHarnessRoot());
  return NextResponse.json(
    { missions: snapshot.missions },
    { status: 200, headers: { "Cache-Control": "no-store" } }
  );
}
