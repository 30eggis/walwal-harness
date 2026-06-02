import path from "node:path";
import type { Metadata } from "next";
import "./globals.css";
import "./brick.css";
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
      <head>
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link
          rel="preconnect"
          href="https://fonts.gstatic.com"
          crossOrigin="anonymous"
        />
        <link
          href="https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;500;600&family=IBM+Plex+Sans:wght@400;500;600&display=swap"
          rel="stylesheet"
        />
      </head>
      <body>{children}</body>
    </html>
  );
}
