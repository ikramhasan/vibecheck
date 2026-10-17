import type { CSSProperties } from "react";
import { color, font } from "../theme";
import { clamp01, easeIn, easeOut } from "../time";

export function words(text: string, t: number, start: number, stagger: number) {
  return text.split(" ").map((word, i) => {
    const p = easeOut(clamp01((t - start - i * stagger) / 0.7));
    return (
      <span
        key={i}
        style={{
          display: "inline-block",
          whiteSpace: "pre",
          opacity: p,
          transform: `translateY(${(1 - p) * 0.38}em)`,
          filter: `blur(${(1 - p) * 10}px)`,
        }}
      >
        {word + (i < text.split(" ").length - 1 ? " " : "")}
      </span>
    );
  });
}

export function Caption({
  t,
  enter,
  exit,
  title,
  sub,
  left = 140,
  top = 360,
  size = 84,
  width = 780,
}: {
  t: number;
  enter: number;
  exit: number;
  title: string;
  sub?: string;
  left?: number;
  top?: number;
  size?: number;
  width?: number;
}) {
  if (t < enter - 0.1 || t > exit + 0.6) return null;
  const out = easeIn(clamp01((t - exit) / 0.45));
  const subIn = easeOut(clamp01((t - enter - 0.35 - title.split(" ").length * 0.05) / 0.7));
  const block: CSSProperties = {
    position: "absolute",
    left,
    top,
    width,
    opacity: 1 - out,
    transform: `translateY(${-18 * out}px)`,
    filter: `blur(${6 * out}px)`,
  };
  return (
    <div style={block}>
      <h2
        style={{
          margin: 0,
          fontFamily: font.display,
          fontSize: size,
          lineHeight: 1.04,
          fontWeight: 700,
          letterSpacing: "-0.035em",
          color: color.text,
        }}
      >
        {words(title, t, enter, 0.055)}
      </h2>
      {sub && (
        <p
          style={{
            margin: "26px 0 0",
            fontFamily: font.text,
            fontSize: 34,
            lineHeight: 1.32,
            letterSpacing: "-0.01em",
            color: color.text2,
            opacity: subIn,
            transform: `translateY(${(1 - subIn) * 14}px)`,
            filter: `blur(${(1 - subIn) * 6}px)`,
          }}
        >
          {sub}
        </p>
      )}
    </div>
  );
}

export function Chip({ children, style }: { children: React.ReactNode; style?: CSSProperties }) {
  return (
    <div
      style={{
        display: "inline-flex",
        alignItems: "center",
        gap: 14,
        padding: "14px 26px",
        borderRadius: 999,
        fontFamily: font.text,
        fontSize: 26,
        fontWeight: 500,
        color: color.text,
        background: "rgba(40,40,46,0.72)",
        backdropFilter: "blur(20px) saturate(1.6)",
        boxShadow: "inset 0 0.5px 0 rgba(255,255,255,0.2), inset 0 0 0 1px rgba(255,255,255,0.08), 0 12px 30px rgba(0,0,0,0.3)",
        ...style,
      }}
    >
      {children}
    </div>
  );
}
