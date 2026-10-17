import type { CSSProperties, ReactNode } from "react";
import { color, font, screen } from "../theme";

const wallpaper = [
  "radial-gradient(60% 80% at 82% 30%, #b8502b 0%, transparent 60%)",
  "radial-gradient(55% 70% at 70% 85%, #8c1f4a 0%, transparent 62%)",
  "radial-gradient(70% 90% at 15% 20%, #22328f 0%, transparent 60%)",
  "radial-gradient(60% 70% at 25% 95%, #0f5f57 0%, transparent 60%)",
  "linear-gradient(135deg, #141a4a, #4a1736 55%, #6b2f19)",
].join(", ");

export function Wallpaper() {
  return <div style={{ position: "absolute", inset: 0, background: wallpaper }} />;
}

export function MenuBar() {
  return (
    <div
      style={{
        position: "absolute",
        left: 0,
        right: 0,
        top: 0,
        height: 26,
        display: "flex",
        alignItems: "center",
        gap: 20,
        padding: "0 18px",
        fontSize: 13,
        color: "rgba(255,255,255,0.9)",
        background: "rgba(10,10,14,0.28)",
        backdropFilter: "blur(20px)",
      }}
    >
      <span style={{ fontWeight: 700 }}>Terminal</span>
      {["Shell", "Edit", "View", "Window", "Help"].map((item) => (
        <span key={item}>{item}</span>
      ))}
      <span style={{ flex: 1 }} />
      <span style={{ fontVariantNumeric: "tabular-nums" }}>Tue 9:41</span>
    </div>
  );
}

export function Window({
  x,
  y,
  width,
  height,
  title,
  active = false,
  style,
  children,
}: {
  x: number;
  y: number;
  width: number;
  height: number;
  title: string;
  active?: boolean;
  style?: CSSProperties;
  children: ReactNode;
}) {
  const lights = active ? ["#ff5f57", "#febc2e", "#28c840"] : ["#4a4a4f", "#4a4a4f", "#4a4a4f"];
  return (
    <div
      style={{
        position: "absolute",
        left: x,
        top: y,
        width,
        height,
        borderRadius: 14,
        overflow: "hidden",
        background: "rgba(24,24,28,0.94)",
        boxShadow: "0 0 0 0.5px rgba(255,255,255,0.14), 0 28px 70px rgba(0,0,0,0.45), 0 4px 14px rgba(0,0,0,0.25)",
        ...style,
      }}
    >
      <div
        style={{
          position: "relative",
          height: 32,
          display: "flex",
          alignItems: "center",
          gap: 8,
          padding: "0 13px",
          borderBottom: "1px solid rgba(255,255,255,0.06)",
        }}
      >
        {lights.map((c, i) => (
          <span key={i} style={{ width: 12, height: 12, borderRadius: "50%", background: c }} />
        ))}
        <span
          style={{
            position: "absolute",
            left: 0,
            right: 0,
            textAlign: "center",
            fontSize: 12,
            fontWeight: 600,
            color: active ? "rgba(255,255,255,0.75)" : "rgba(255,255,255,0.4)",
          }}
        >
          {title}
        </span>
      </div>
      <div style={{ padding: "14px 18px", fontFamily: font.mono, fontSize: 12.5, lineHeight: 1.7, color: "rgba(255,255,255,0.72)", whiteSpace: "pre" }}>
        {children}
      </div>
    </div>
  );
}

export const tone = {
  dim: { color: "rgba(255,255,255,0.38)" },
  prompt: { color: color.blue },
  tool: { color: "#7ee0a1" },
  edit: { color: "#ffcf70" },
  ask: { color: color.orange },
  key: { color: "#c792ea" },
  str: { color: "#a5e075" },
} satisfies Record<string, CSSProperties>;

export const screenBox: CSSProperties = { position: "absolute", left: 0, top: 0, width: screen.width, height: screen.height, overflow: "hidden" };
