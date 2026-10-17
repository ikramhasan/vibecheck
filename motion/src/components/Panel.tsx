import type { ReactNode } from "react";
import { color } from "../theme";

export const metrics = {
  flare: 14,
  corner: 14,
  collapsedWidth: 44,
  expandedWidth: 340,
  badge: 26,
  slot: 33,
  header: 44,
  groupHeader: 26,
  groupPadding: 10,
  groupDivider: 5,
  sessionLine: 24,
  detailLine: 16,
  serverRow: 46,
};

export const collapsedHeight = (sessions: number) => metrics.flare * 2 + 16 + (sessions + 1) * metrics.slot + 1 + metrics.slot - metrics.badge;

function edgeTabPath(w: number, h: number) {
  const f = Math.min(metrics.flare, h / 4);
  const c = Math.max(0, Math.min(metrics.corner, (w - f) / 2, (h - 2 * f) / 2));
  return [
    `M${w},0`,
    `A${f},${f} 0 0 1 ${w - f},${f}`,
    `L${c},${f}`,
    `A${c},${c} 0 0 0 0,${f + c}`,
    `L0,${h - f - c}`,
    `A${c},${c} 0 0 0 ${c},${h - f}`,
    `L${w - f},${h - f}`,
    `A${f},${f} 0 0 1 ${w},${h}`,
    "Z",
  ].join(" ");
}

export function Panel({
  open,
  collapsedHeight,
  pageHeight,
  centerY,
  shift,
  collapsed,
  expanded,
}: {
  open: number;
  collapsedHeight: number;
  pageHeight: number;
  centerY: number;
  shift: number;
  collapsed: ReactNode;
  expanded: ReactNode;
}) {
  const w = metrics.collapsedWidth + (metrics.expandedWidth - metrics.collapsedWidth) * open;
  const h = Math.max(40, collapsedHeight + (pageHeight - collapsedHeight) * open);
  const path = edgeTabPath(w, h);
  const shown = Math.min(1, Math.max(0, open));

  return (
    <div
      style={{
        position: "absolute",
        right: 0,
        top: 0,
        width: w,
        height: h,
        transform: `translate(${shift}px, ${centerY - h / 2}px)`,
        color: color.ink,
      }}
    >
      <svg style={{ position: "absolute", inset: 0, width: "100%", height: "100%", overflow: "visible" }}>
        <path d={path} fill="rgba(0,0,0,0.55)" style={{ filter: "blur(18px)", transform: "translate(-4px, 10px)" }} />
      </svg>
      <div
        style={{
          position: "absolute",
          inset: 0,
          clipPath: `path("${path}")`,
          background: color.glass,
          backdropFilter: "blur(26px) saturate(1.9)",
        }}
      >
        <div
          style={{
            position: "absolute",
            inset: 0,
            background: "linear-gradient(180deg, rgba(255,255,255,0.07), rgba(255,255,255,0) 22%, rgba(255,255,255,0) 80%, rgba(255,255,255,0.03))",
          }}
        />
        <div
          style={{
            position: "absolute",
            right: 0,
            top: 0,
            width: metrics.expandedWidth,
            height: pageHeight,
            opacity: shown,
            transform: `translateY(${(h - pageHeight) / 2}px) scale(${0.96 + 0.04 * shown})`,
            transformOrigin: "right center",
          }}
        >
          {expanded}
        </div>
        <div
          style={{
            position: "absolute",
            right: 0,
            top: "50%",
            width: metrics.collapsedWidth,
            transform: "translateY(-50%)",
            opacity: 1 - shown,
          }}
        >
          {collapsed}
        </div>
      </div>
      <svg style={{ position: "absolute", inset: 0, width: "100%", height: "100%", overflow: "visible" }}>
        <path d={path} fill="none" stroke={color.glassEdge} strokeWidth={1} />
      </svg>
    </div>
  );
}
