import type { CSSProperties } from "react";
import { Img, staticFile } from "remotion";
import type { Agent, Group, Session, Status } from "../story";
import { statusAt, statusChanges } from "../story";
import { color, font } from "../theme";
import { clamp01, easeOut, seg, spring, springs } from "../time";
import { Orb } from "./Orb";

export function AgentGlyph({ agent, size, style }: { agent: Agent; size: number; style?: CSSProperties }) {
  return <Img src={staticFile(`agents/${agent}.svg`)} width={size} height={size} style={{ display: "block", flexShrink: 0, ...style }} />;
}

export function ProjectBadge({ group, size }: { group: Group; size: number }) {
  const radius = size * 0.28;
  return (
    <span
      style={{
        width: size,
        height: size,
        flexShrink: 0,
        borderRadius: radius,
        overflow: "hidden",
        display: "grid",
        placeItems: "center",
        background: group.icon ? undefined : color.ink4,
        boxShadow: "inset 0 0 0 0.5px rgba(255,255,255,0.08)",
        fontFamily: font.rounded,
        fontSize: size * 0.46,
        fontWeight: 700,
      }}
    >
      {group.icon ? <Img src={staticFile(group.icon)} width={size} height={size} style={{ display: "block" }} /> : group.monogram}
    </span>
  );
}

const statusColor: Record<Status, string> = { working: color.blue, asking: color.orange, idle: color.green };

function StatusLayer({ session, status, size, t }: { session: Session; status: Status; size: number; t: number }) {
  if (status === "asking") return <Orb look={{ state: "waiting" }} size={size} color={statusColor.asking} time={t} />;
  if (status === "idle") return <Orb look={{ state: "base" }} size={size} color={statusColor.idle} time={null} />;
  return <Orb look={session.look} size={size} color={statusColor.working} time={t} />;
}

export function StatusOrb({ session, size, t, pulse = false }: { session: Session; size: number; t: number; pulse?: boolean }) {
  const now = statusAt(session, t);
  const at = statusChanges(session).filter((c) => c <= t).at(-1);
  const since = at === undefined ? Infinity : t - at;
  const before = at === undefined ? now : statusAt(session, at - 0.001);
  const p = clamp01(since / 0.35);
  const pop = since === Infinity ? 1 : spring(since, springs.pop);
  const ring = pulse && since < 1.1 ? easeOut(clamp01(since / 1.1)) : 1;

  return (
    <span style={{ position: "relative", width: size, height: size, flexShrink: 0, display: "block" }}>
      {p < 1 && (
        <span style={{ position: "absolute", inset: 0, opacity: 1 - p, transform: `scale(${1 - 0.3 * p})` }}>
          <StatusLayer session={session} status={before} size={size} t={t} />
        </span>
      )}
      <span style={{ position: "absolute", inset: 0, opacity: p, transform: `scale(${0.55 + 0.45 * pop})` }}>
        <StatusLayer session={session} status={now} size={size} t={t} />
      </span>
      {ring < 1 && (
        <span
          style={{
            position: "absolute",
            inset: 0,
            borderRadius: "50%",
            border: `1.5px solid ${statusColor[now]}`,
            opacity: 0.9 * (1 - ring),
            transform: `scale(${0.7 + 1.1 * ring})`,
          }}
        />
      )}
    </span>
  );
}

export type Reveal = { at: number; shown: boolean; side: 1 | -1; paced: boolean };

export function cascade(t: number, index: number, reveals: Reveal[]): CSSProperties {
  const step = Math.min(index, 6);
  let x = 24, o = 0, tx = 24, to = 0;
  for (const r of reveals) {
    const nx = r.shown ? 0 : r.side * (r.paced ? 28 : 24);
    const no = r.shown ? 1 : 0;
    let p: number;
    if (r.shown && r.paced) p = spring(t - r.at - (0.05 + step * 0.02), springs.pageIn);
    else if (r.shown) p = spring(t - r.at - (0.04 + step * 0.04), springs.rowsIn);
    else if (r.paced) p = easeOut(seg(t, r.at + step * 0.01, r.at + step * 0.01 + 0.12));
    else p = easeOut(seg(t, r.at, r.at + 0.12));
    x += (nx - tx) * p;
    o += (no - to) * p;
    tx = nx;
    to = no;
  }
  return { transform: `translateX(${x}px)`, opacity: clamp01(o) };
}

export function PromptGlyph({ size, stroke }: { size: number; stroke: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 10 10" fill="none" stroke="currentColor" strokeWidth={stroke} strokeLinecap="round" strokeLinejoin="round">
      <path d="M1.5 2.5 4 5 1.5 7.5M5.5 8h3" />
    </svg>
  );
}

export function usageTint(used: number) {
  if (used < 75) return color.green;
  if (used < 90) return color.orange;
  return color.red;
}
