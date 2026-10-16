"use client";

import { useEffect, useRef } from "react";
import { mountOrb, type OrbLook } from "@/lib/orb-core";

export type Status = "working" | "asking" | "blocked" | "idle";

export const statusLook: Record<Status, OrbLook> = {
  working: { state: "working" },
  asking: { state: "waiting" },
  blocked: { state: "retrying" },
  idle: { state: "base" },
};

export function Orb({ look, size, status }: { look: OrbLook; size: number; status: Status }) {
  const ref = useRef<SVGSVGElement>(null);

  useEffect(() => {
    const orb = mountOrb(ref.current!, { ...look, size });
    if (status === "idle") orb.pause();
    return orb.destroy;
  }, [look, size, status]);

  return (
    <svg
      ref={ref}
      className={`orb tint-${status}`}
      width={size}
      height={size}
      viewBox={`0 0 ${size} ${size}`}
      fill="currentColor"
      aria-hidden
    />
  );
}
