"use client";

import { useEffect, useId, useState } from "react";
import type { Status } from "./Orb";

const lerp = (a: number, b: number, k: number) => a + (b - a) * k;
const ease = (x: number) => (1 - Math.cos(Math.PI * Math.min(1, Math.max(0, x)))) / 2;
const mod = (a: number, b: number) => ((a % b) + b) % b;

function useSeconds(animated: boolean) {
  const [seconds, setSeconds] = useState(0);

  useEffect(() => {
    if (!animated || matchMedia("(prefers-reduced-motion: reduce)").matches) return;
    const start = performance.now();
    let frame = requestAnimationFrame(function step(now) {
      setSeconds((now - start) / 1000);
      frame = requestAnimationFrame(step);
    });
    return () => cancelAnimationFrame(frame);
  }, [animated]);

  return seconds;
}

export function RingOrb({ status, size }: { status: Status; size: number }) {
  const t = useSeconds(status !== "idle");
  const line = Math.max(1.5, size / 15.5);
  const radius = size / 2 - line / 2;
  const centre = size / 2;
  const shineId = useId().replace(/[^a-zA-Z0-9_-]/g, "");
  const point = (degrees: number) => {
    const angle = (degrees * Math.PI) / 180;
    return `${centre + radius * Math.cos(angle)},${centre + radius * Math.sin(angle)}`;
  };
  const quarter = (from: number) => `M${point(from)} A${radius},${radius} 0 0 1 ${point(from + 90)}`;
  const period = status === "blocked" ? 2.4 : 360 / 330;
  const swell = status === "asking" ? 0.5 + 0.5 * Math.sin((t * 2 * Math.PI) / 1.2) : 0;
  const spins = status === "working" || status === "blocked";

  return (
    <svg className={`orb tint-${status}`} width={size} height={size} viewBox={`0 0 ${size} ${size}`} overflow="visible" aria-hidden>
      <defs>
        <radialGradient id={shineId} cx="0.35" cy="0.3" r="0.573">
          <stop offset="0" stopColor="#fff" stopOpacity="0.55" />
          <stop offset="1" stopColor="#fff" stopOpacity="0" />
        </radialGradient>
      </defs>
      {spins ? (
        <g transform={`rotate(${mod(t / period, 1) * 360} ${centre} ${centre})`} fill="none" strokeWidth={line}>
          <path d={quarter(-45)} stroke="currentColor" strokeOpacity="0.35" />
          <path d={quarter(-135)} stroke="currentColor" />
        </g>
      ) : (
        <circle
          cx={centre}
          cy={centre}
          r={radius}
          fill="none"
          stroke="currentColor"
          strokeWidth={line}
          strokeOpacity={status === "asking" ? 0.6 : 0.3}
          opacity={1 - 0.6 * swell}
          transform={`translate(${centre} ${centre}) scale(${1 + 0.14 * swell}) translate(${-centre} ${-centre})`}
        />
      )}
      <circle cx={centre} cy={centre} r={size * 0.35} fill="currentColor" />
      <circle cx={centre} cy={centre} r={size * 0.35} fill={`url(#${shineId})`} />
    </svg>
  );
}

type Eyes = "open" | "wide" | "happy" | "asleep";

type Expression = {
  eyes: Eyes;
  hop: number;
  stretchX: number;
  stretchY: number;
  lookX: number;
  lookY: number;
  blink: number;
  zee?: number;
};

const blinkAt = (t: number, every: number) => (mod(t, every) < 0.12 ? 0.12 : 1);

function expression(status: Status, t: number): Expression {
  const face: Expression = { eyes: "open", hop: 0, stretchX: 1, stretchY: 1, lookX: 0, lookY: 0, blink: 1 };
  switch (status) {
    case "working": {
      const p = mod(t, 4) / 4;
      if (p < 0.7) {
        const line = mod(p / 0.35, 1);
        face.lookX = line < 0.8 ? lerp(-1, 1, ease(line / 0.8)) : lerp(1, -1, ease((line - 0.8) / 0.2));
        face.lookY = 0.6;
      } else {
        const glance = (p - 0.7) / 0.3;
        const away = ease(glance / 0.4);
        const back = ease((glance - 0.75) / 0.25);
        face.lookX = lerp(lerp(-1, 0.55, away), -1, back);
        face.lookY = lerp(lerp(0.6, -0.9, away), 0.6, back);
      }
      face.blink = blinkAt(t, 3.7);
      face.stretchY = 1 + 0.02 * Math.sin(t * 2.6);
      face.stretchX = 2 - face.stretchY;
      return face;
    }
    case "asking": {
      face.eyes = "wide";
      face.lookY = -0.5;
      const p = mod(t, 1.7) / 1.7;
      const height = p < 0.2 ? Math.sin((Math.PI * p) / 0.2) : p < 0.4 ? 0.8 * Math.sin((Math.PI * (p - 0.2)) / 0.2) : 0;
      const landing = p > 0.4 && p < 0.5 ? Math.sin((Math.PI * (p - 0.4)) / 0.1) : 0;
      face.hop = -0.1 * height;
      face.stretchY = 1 + 0.06 * height - 0.07 * landing;
      face.stretchX = 1 - 0.04 * height + 0.06 * landing;
      face.blink = blinkAt(t + 1, 2.9);
      return face;
    }
    case "blocked":
      face.eyes = "asleep";
      face.hop = 0.03;
      face.stretchY = 0.97 + 0.03 * Math.sin(t * 1.4);
      face.stretchX = 2 - face.stretchY;
      face.zee = mod(t, 2.4) / 2.4;
      return face;
    case "idle":
      face.eyes = "happy";
      return face;
  }
}

function arc(cx: number, cy: number, radius: number, from: number, to: number) {
  return Array.from({ length: 17 }, (_, step) => {
    const angle = (from + ((to - from) * step) / 16) * Math.PI;
    return `${step ? "L" : "M"}${cx + radius * Math.cos(angle)},${cy + radius * Math.sin(angle)}`;
  }).join(" ");
}

function Eye({ eyes }: { eyes: Eyes }) {
  const width = 0.13;
  const height = 0.24;
  switch (eyes) {
    case "open":
    case "wide": {
      const grow = eyes === "wide" ? 1.24 : 1;
      const w = width * grow;
      const h = height * grow;
      return <rect x={-w / 2} y={-h / 2} width={w} height={h} rx={w / 2} />;
    }
    case "happy":
      return <path d={arc(0, height * 0.32, width * 0.62, 1.12, 1.88)} className="buddy-stroke" />;
    case "asleep":
      return <path d={arc(0, -height * 0.12, width * 0.6, 0.14, 0.86)} className="buddy-stroke" />;
  }
}

const ground = 0.9;
const give = 0.7;

export function BuddyOrb({ status, size }: { status: Status; size: number }) {
  const t = useSeconds(status !== "idle");
  const face = expression(status, status === "idle" ? 0 : t || (status === "working" ? 0.56 : 1.2));
  const maskId = useId().replace(/[^a-zA-Z0-9_-]/g, "");
  const pose = [
    `translate(0.5 ${ground + face.hop})`,
    `scale(${1 + (face.stretchX - 1) * give} ${1 + (face.stretchY - 1) * give})`,
    `translate(-0.5 ${-ground})`,
  ].join(" ");
  const zee = face.zee;
  const half = zee === undefined ? 0 : (0.26 + 0.08 * zee) * 0.3;
  const zx = zee === undefined ? 0 : 0.84 + 0.06 * zee;
  const zy = zee === undefined ? 0 : 0.17 - 0.1 * zee;

  return (
    <svg className={`orb tint-${status}`} width={size} height={size} viewBox="0 0 1 1" overflow="visible" aria-hidden>
      <mask id={maskId} maskUnits="userSpaceOnUse" x="-1" y="-1" width="3" height="3">
        <rect x="-1" y="-1" width="3" height="3" fill="#fff" />
        {[0.36, 0.64].map((x) => (
          <g key={x} transform={`translate(${x + face.lookX * 0.065} ${0.57 + face.lookY * 0.045}) scale(1 ${face.blink})`}>
            <Eye eyes={face.eyes} />
          </g>
        ))}
      </mask>
      <g transform={pose}>
        <rect x="0.1" y="0.22" width="0.8" height="0.68" rx="0.28" fill="currentColor" mask={`url(#${maskId})`} />
      </g>
      {zee !== undefined && (
        <path
          d={`M${zx - half},${zy - half} L${zx + half},${zy - half} L${zx - half},${zy + half} L${zx + half},${zy + half}`}
          className="buddy-zee"
          opacity={Math.sin(Math.PI * Math.min(1, zee * 1.3))}
        />
      )}
    </svg>
  );
}
