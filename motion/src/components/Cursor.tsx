import { clamp01, easeInOut, lerp } from "../time";

export type CursorKey = { at: number; x: number; y: number; dur?: number; bow?: number };

export function cursorPosition(t: number, keys: CursorKey[]) {
  let x = keys[0].x, y = keys[0].y;
  for (const key of keys.slice(1)) {
    const dur = key.dur ?? 0.8;
    const p = easeInOut(clamp01((t - key.at) / dur));
    const dx = key.x - x, dy = key.y - y;
    const bow = (key.bow ?? 0.12) * Math.sin(Math.PI * p);
    const nx = lerp(x, key.x, p) - dy * bow;
    const ny = lerp(y, key.y, p) + dx * bow;
    if (t < key.at) break;
    x = nx;
    y = ny;
  }
  return { x, y };
}

export function Cursor({ x, y, scale, press, opacity }: { x: number; y: number; scale: number; press: number; opacity: number }) {
  return (
    <div style={{ position: "absolute", left: x, top: y, opacity, pointerEvents: "none", zIndex: 50 }}>
      {press > 0 && (
        <span
          style={{
            position: "absolute",
            left: -18 * scale,
            top: -18 * scale,
            width: 36 * scale,
            height: 36 * scale,
            borderRadius: "50%",
            background: "rgba(255,255,255,0.35)",
            opacity: press * 0.8,
            transform: `scale(${0.4 + 0.6 * press})`,
          }}
        />
      )}
      <svg
        width={24}
        height={24}
        viewBox="0 0 24 24"
        style={{
          position: "absolute",
          left: -5,
          top: -3,
          transform: `scale(${scale * (1 - 0.12 * press)})`,
          transformOrigin: "5px 3px",
          filter: "drop-shadow(0 2px 3px rgba(0,0,0,0.35))",
        }}
      >
        <path d="M5 3v16.5l4.3-4.1 2.8 6.4 2.9-1.3-2.8-6.2H18.3z" fill="#000" stroke="#fff" strokeWidth="1.4" strokeLinejoin="round" />
      </svg>
    </div>
  );
}
