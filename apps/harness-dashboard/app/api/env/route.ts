import { NextResponse } from "next/server";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import { resolveHarnessRoot } from "@/lib/harness-root";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";
export const revalidate = 0;

const ALLOWED_FILES = new Set([
  ".env",
  ".env.local",
  ".env.production",
  ".env.development",
  ".env.example",
]);

function isSafeKey(key: string): boolean {
  return /^[A-Z_][A-Z0-9_]*$/i.test(key);
}

function quoteValue(value: string): string {
  if (/^[A-Za-z0-9_./:@+-]*$/.test(value)) return value;
  return JSON.stringify(value);
}

export async function POST(request: Request) {
  const body = await request.json().catch(() => null);
  const file = String(body?.file ?? "");
  const key = String(body?.key ?? "");
  const value = String(body?.value ?? "");

  if (!ALLOWED_FILES.has(file) || !isSafeKey(key)) {
    return NextResponse.json({ ok: false, error: "invalid env target" }, { status: 400 });
  }

  const root = resolveHarnessRoot();
  const target = path.join(root, file);
  if (!existsSync(target)) {
    return NextResponse.json({ ok: false, error: "env file not found" }, { status: 404 });
  }

  const original = readFileSync(target, "utf-8");
  const lines = original.split("\n");
  const nextLine = `${key}=${quoteValue(value)}`;
  let replaced = false;
  const next = lines.map((line) => {
    if (line.trimStart().startsWith("#")) return line;
    const idx = line.indexOf("=");
    if (idx < 0) return line;
    if (line.slice(0, idx).trim() !== key) return line;
    replaced = true;
    return nextLine;
  });
  if (!replaced) next.push(nextLine);
  writeFileSync(target, next.join("\n").replace(/\n*$/, "\n"));

  return NextResponse.json(
    { ok: true, file, key, replaced },
    { status: 200, headers: { "Cache-Control": "no-store" } }
  );
}
