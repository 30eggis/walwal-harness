import { NextResponse } from "next/server";
import { readHarnessState } from "@/lib/harness-state";
import { resolveHarnessRoot } from "@/lib/harness-root";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function GET() {
  const root = resolveHarnessRoot();
  const snapshot = readHarnessState(root);
  return NextResponse.json(snapshot, {
    status: 200,
    headers: { "Cache-Control": "no-store" },
  });
}
