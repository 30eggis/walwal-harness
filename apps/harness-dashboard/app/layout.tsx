import path from "node:path";
import type { Metadata } from "next";
import "./globals.css";
import { resolveHarnessRoot } from "@/lib/harness-root";

export async function generateMetadata(): Promise<Metadata> {
  const root = resolveHarnessRoot();
  const name = path.basename(root);
  return {
    title: `Brick Office — ${name}`,
    description: `walwal-harness 라이브 운영 대시보드 — ${name}`,
  };
}

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="ko">
      <body>{children}</body>
    </html>
  );
}
