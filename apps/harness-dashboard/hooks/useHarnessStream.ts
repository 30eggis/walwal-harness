"use client";
import { useEffect, useRef, useState } from "react";
import type { HarnessSnapshot } from "@/lib/types";

export type ConnectionState = "connecting" | "open" | "stale" | "failed";

const FAILURE_THRESHOLD = 5;

export function useHarnessStream(initial: HarnessSnapshot): {
  snapshot: HarnessSnapshot;
  connectionState: ConnectionState;
} {
  const [snapshot, setSnapshot] = useState<HarnessSnapshot>(initial);
  const [connectionState, setConnectionState] = useState<ConnectionState>("connecting");
  const failuresRef = useRef(0);

  useEffect(() => {
    if (typeof window === "undefined") return;
    const es = new EventSource("/api/stream");

    es.onopen = () => {
      failuresRef.current = 0;
      setConnectionState("open");
    };

    es.onmessage = (ev) => {
      try {
        const next = JSON.parse(ev.data) as HarnessSnapshot;
        setSnapshot(next);
        failuresRef.current = 0;
        setConnectionState("open");
      } catch {
        // Malformed payload — leave snapshot unchanged.
      }
    };

    es.onerror = () => {
      failuresRef.current += 1;
      if (failuresRef.current >= FAILURE_THRESHOLD) {
        setConnectionState("failed");
        es.close();
      } else {
        setConnectionState("stale");
      }
    };

    return () => {
      es.close();
    };
  }, []);

  return { snapshot, connectionState };
}
