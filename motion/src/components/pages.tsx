import { useLayoutEffect, useRef, type CSSProperties, type ReactNode } from "react";
import { Img, staticFile } from "remotion";
import { question, servers, statusAt, usage, type Agent, type Group, type Session } from "../story";
import { color, font } from "../theme";
import { clamp01, lerp, spring, springs } from "../time";
import { metrics } from "./Panel";
import { AgentGlyph, ProjectBadge, PromptGlyph, StatusOrb, usageTint } from "./parts";

const ellipsis: CSSProperties = { overflow: "hidden", whiteSpace: "nowrap", textOverflow: "ellipsis" };
const spacer = <span style={{ flex: 1, minWidth: 6 }} />;

export function CollapsedBadges({ sessions, t, appear, fill }: { sessions: Session[]; t: number; appear: (i: number) => number; fill: number }) {
  return (
    <div style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: metrics.slot - metrics.badge, paddingLeft: 3 }}>
      {sessions.map((session, i) => {
        const s = appear(i);
        return (
          <div
            key={session.id}
            style={{ position: "relative", width: metrics.badge, height: metrics.badge, opacity: clamp01(s), transform: `scale(${0.3 + 0.7 * s})` }}
          >
            <div style={{ position: "absolute", inset: -2.5 }}>
              <StatusOrb session={session} size={31} t={t} pulse />
            </div>
            {session.runsServer && (
              <span
                style={{
                  position: "absolute",
                  right: -4,
                  top: -4,
                  width: 13,
                  height: 13,
                  borderRadius: "50%",
                  display: "grid",
                  placeItems: "center",
                  background: "rgba(80,80,88,0.7)",
                  boxShadow: "inset 0 0 0 0.5px rgba(255,255,255,0.25)",
                  color: color.ink,
                }}
              >
                <PromptGlyph size={7} stroke={1.3} />
              </span>
            )}
            <AgentGlyph agent={session.agent} size={13} style={{ position: "absolute", right: -4, bottom: -4 }} />
          </div>
        );
      })}
      <div style={{ width: metrics.badge * 0.6, height: 1, borderRadius: 1, background: color.separator }} />
      <UsageDial fill={fill} />
    </div>
  );
}

function UsageDial({ fill }: { fill: number }) {
  const size = metrics.badge, line = 3, gap = 1.5;
  return (
    <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} style={{ overflow: "visible" }}>
      {usage.map((provider, index) => {
        const peak = Math.max(...provider.windows.map((w) => w.used));
        const r = size / 2 - index * (line + gap) - line / 2;
        const c = 2 * Math.PI * r;
        const tint = usageTint(peak);
        return (
          <g key={provider.agent}>
            <circle cx={13} cy={13} r={r} fill="none" stroke={tint} strokeOpacity={0.2} strokeWidth={line} />
            <circle
              cx={13}
              cy={13}
              r={r}
              fill="none"
              stroke={tint}
              strokeWidth={line}
              strokeLinecap="round"
              strokeDasharray={`${(c * peak * fill) / 100} ${c}`}
              transform="rotate(-90 13 13)"
              style={{ opacity: fill > 0.01 ? 1 : 0 }}
            />
          </g>
        );
      })}
    </svg>
  );
}

function CountChip({ children, tint }: { children: ReactNode; tint?: string }) {
  return (
    <span
      style={{
        fontSize: 11,
        fontWeight: 500,
        fontVariantNumeric: "tabular-nums",
        padding: "1px 6px",
        borderRadius: 99,
        color: tint ?? color.ink2,
        background: tint ? `color-mix(in srgb, ${tint} 14%, transparent)` : "rgba(255,255,255,0.06)",
      }}
    >
      {children}
    </span>
  );
}

const glassCircle: CSSProperties = {
  width: 24,
  height: 24,
  borderRadius: "50%",
  display: "grid",
  placeItems: "center",
  color: color.ink2,
  background: "rgba(255,255,255,0.07)",
  boxShadow: "inset 0 0.5px 0 rgba(255,255,255,0.22), inset 0 0 0 0.5px rgba(255,255,255,0.1)",
};

export function Header({ agents, countOpacity, onServers }: { agents: number; countOpacity: number; onServers: number }) {
  const tabs = useRef<(HTMLSpanElement | null)[]>([]);
  const pill = useRef<HTMLSpanElement>(null);
  useLayoutEffect(() => {
    const [agentsTab, serversTab] = tabs.current.map((el) => el!);
    pill.current!.style.left = `${lerp(agentsTab.offsetLeft, serversTab.offsetLeft, onServers)}px`;
    pill.current!.style.width = `${lerp(agentsTab.offsetWidth, serversTab.offsetWidth, onServers)}px`;
  });
  const agentsTint = onServers < 0.5 ? color.ink : color.ink3;
  const serversTint = onServers >= 0.5 ? color.ink : color.ink3;

  return (
    <div style={{ position: "relative", display: "flex", alignItems: "center", gap: 2, height: metrics.header, padding: "0 10px" }}>
      <span
        ref={pill}
        style={{
          position: "absolute",
          top: 8,
          height: 28,
          borderRadius: 14,
          background: "rgba(255,255,255,0.11)",
          boxShadow: "inset 0 0.5px 0 rgba(255,255,255,0.25), inset 0 0 0 0.5px rgba(255,255,255,0.08), 0 2px 8px rgba(0,0,0,0.18)",
        }}
      />
      <span ref={(el) => void (tabs.current[0] = el)} style={{ position: "relative", display: "flex", alignItems: "center", gap: 6, height: 28, padding: "0 6px" }}>
        <span style={{ fontSize: 13, fontWeight: 600, color: agentsTint }}>Agents</span>
        <CountChip>
          <span style={{ display: "inline-block", opacity: countOpacity }}>{agents}</span>
        </CountChip>
      </span>
      <span ref={(el) => void (tabs.current[1] = el)} style={{ position: "relative", display: "flex", alignItems: "center", gap: 6, height: 28, padding: "0 6px" }}>
        <span style={{ fontSize: 13, fontWeight: 600, color: serversTint }}>Servers</span>
        <CountChip>{servers.length}</CountChip>
      </span>
      <span style={{ position: "relative", width: 28, height: 28, display: "grid", placeItems: "center", color: color.ink3 }}>
        <svg width="11" height="13" viewBox="0 0 11 14" fill="currentColor">
          <path d="M6.6 0 0 8h4.4L3.6 14 11 5.6H6.4z" />
        </svg>
      </span>
      {spacer}
      <span style={{ display: "flex", gap: 4 }}>
        <span style={glassCircle}>
          <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round">
            <circle cx="12" cy="12" r="3" />
            <path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 1 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06A1.65 1.65 0 0 0 4.68 15a1.65 1.65 0 0 0-1.51-1H3a2 2 0 1 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06A1.65 1.65 0 0 0 9 4.68a1.65 1.65 0 0 0 1-1.51V3a2 2 0 1 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06A1.65 1.65 0 0 0 19.4 9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 1 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z" />
          </svg>
        </span>
        <span style={glassCircle}>
          <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.6" strokeLinecap="round">
            <path d="M12 3v8" />
            <path d="M6.3 6.8a8 8 0 1 0 11.4 0" />
          </svg>
        </span>
      </span>
    </div>
  );
}

export function GroupView({ group, t }: { group: Group; t: number }) {
  return (
    <div style={{ padding: `${metrics.groupPadding / 2}px 6px` }}>
      <div style={{ display: "flex", alignItems: "center", gap: 8, height: metrics.groupHeader, padding: "0 12px" }}>
        <ProjectBadge group={group} size={18} />
        <span style={{ fontSize: 12.5, fontWeight: 600 }}>{group.name}</span>
        {group.host && (
          <span style={{ display: "flex", alignItems: "center", gap: 3, fontSize: 11, color: color.ink3 }}>
            <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
              <circle cx="12" cy="12" r="9" />
              <path d="M3 12h18M12 3c3.2 3.6 3.2 14.4 0 18M12 3c-3.2 3.6-3.2 14.4 0 18" />
            </svg>
            {group.host}
          </span>
        )}
        {spacer}
        {group.sessions.length > 1 && <span style={{ fontSize: 11, color: color.ink3 }}>{group.sessions.length} agents</span>}
      </div>
      {group.sessions.map((session) => (
        <SessionLine key={session.id} session={session} t={t} />
      ))}
    </div>
  );
}

function SessionLine({ session, t }: { session: Session; t: number }) {
  const status = statusAt(session, t);
  const headline = status === "asking" ? question.text : session.task;
  const detail = status === "idle" ? session.reply : status === "asking" ? session.task : `Working · ${session.activity}`;
  const elapsed = status === "idle" && session.id === "flaky" ? "now" : session.elapsed;
  const titleColor = status === "asking" ? color.orange : status === "idle" ? "rgba(255,255,255,0.62)" : color.ink;
  return (
    <div style={{ padding: "0 12px", borderRadius: 12 }}>
      <div style={{ display: "flex", alignItems: "center", gap: 8, height: metrics.sessionLine }}>
        <StatusOrb session={session} size={18} t={t} />
        <span style={{ fontSize: 12, color: titleColor, ...ellipsis }}>{headline}</span>
        <span style={{ flex: 1 }} />
        <span style={{ display: "flex", alignItems: "center", gap: 8, flexShrink: 0 }}>
          {session.context !== undefined && <ContextGauge fraction={session.context} />}
          <span style={{ fontSize: 11, color: color.ink3, fontVariantNumeric: "tabular-nums" }}>{elapsed}</span>
        </span>
      </div>
      <div style={{ display: "flex", gap: 8, height: metrics.detailLine, paddingLeft: 26, fontSize: 11, color: color.ink3 }}>
        <span style={ellipsis}>{detail}</span>
        {spacer}
        <span style={{ display: "flex", alignItems: "center", gap: 8, height: 13, flexShrink: 0 }}>
          <AgentGlyph agent={session.agent} size={12} />
          {session.diff && (
            <span style={{ display: "flex", gap: 3, fontSize: 10, fontWeight: 500, fontVariantNumeric: "tabular-nums" }}>
              <span style={{ color: "rgba(48,209,88,0.85)" }}>+{session.diff[0]}</span>
              <span style={{ color: "rgba(255,66,69,0.8)" }}>−{session.diff[1]}</span>
            </span>
          )}
        </span>
      </div>
    </div>
  );
}

function ContextGauge({ fraction }: { fraction: number }) {
  const r = 3.7, c = 2 * Math.PI * r;
  return (
    <svg width="9" height="9" viewBox="0 0 9 9" fill="none" strokeWidth="1.6">
      <circle cx="4.5" cy="4.5" r={r} stroke="rgba(255,255,255,0.12)" />
      <circle cx="4.5" cy="4.5" r={r} stroke="rgba(255,255,255,0.5)" strokeLinecap="round" strokeDasharray={`${c * fraction} ${c}`} transform="rotate(-90 4.5 4.5)" />
    </svg>
  );
}

export function GroupDivider() {
  return (
    <div style={{ height: metrics.groupDivider, display: "flex", alignItems: "center", padding: "0 18px" }}>
      <div style={{ flex: 1, height: 1, background: color.separator }} />
    </div>
  );
}

export const usageHeight = 30 + usage.reduce((sum, u) => sum + 22 + u.windows.length * 20 + 10, 0);

export function UsageSection() {
  return (
    <div style={{ height: usageHeight }}>
      <div
        style={{
          display: "flex",
          alignItems: "flex-end",
          gap: 6,
          height: 30,
          margin: "0 18px",
          borderTop: `1px solid ${color.separator}`,
          color: color.ink3,
        }}
      >
        <span style={{ fontSize: 11, fontWeight: 600, letterSpacing: "0.04em", textTransform: "uppercase" }}>Usage</span>
        {spacer}
        <span style={{ fontSize: 10, fontWeight: 500 }}>% used</span>
        <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round" style={{ margin: "0 3px 3px" }}>
          <path d="M21 12a9 9 0 1 1-2.64-6.36L21 8" />
          <path d="M21 3v5h-5" />
        </svg>
      </div>
      <div style={{ display: "flex", flexDirection: "column", gap: 10, padding: "6px 18px 0" }}>
        {usage.map((provider) => (
          <div key={provider.agent}>
            <div style={{ display: "flex", alignItems: "center", gap: 6, height: 22 }}>
              <AgentGlyph agent={provider.agent} size={13} />
              <span style={{ fontSize: 12, fontWeight: 600 }}>{provider.name}</span>
              <span style={{ padding: "1px 5px", borderRadius: 99, background: "rgba(255,255,255,0.06)", color: color.ink2, fontSize: 10, fontWeight: 500 }}>
                {provider.plan}
              </span>
            </div>
            {provider.windows.map((w) => (
              <div
                key={w.label}
                style={{
                  display: "grid",
                  gridTemplateColumns: "50px 1fr 34px 56px",
                  alignItems: "center",
                  gap: 8,
                  height: 20,
                  fontSize: 11,
                  fontVariantNumeric: "tabular-nums",
                }}
              >
                <span style={{ fontWeight: 500, color: color.ink2 }}>{w.label}</span>
                <span style={{ height: 4, borderRadius: 2, background: color.ink4 }}>
                  <span style={{ display: "block", height: "100%", width: `${w.used}%`, borderRadius: 2, background: usageTint(w.used) }} />
                </span>
                <span style={{ fontWeight: 500, textAlign: "right" }}>{w.used}%</span>
                <span style={{ textAlign: "right", color: color.ink3 }}>{w.resets}</span>
              </div>
            ))}
          </div>
        ))}
      </div>
    </div>
  );
}

export function ServerRow({ server }: { server: (typeof servers)[number] }) {
  return (
    <div style={{ height: metrics.serverRow, padding: "3px 12px", borderRadius: 12 }}>
      <div style={{ display: "flex", alignItems: "center", gap: 8, height: 24 }}>
        <span style={{ width: 18, display: "grid", placeItems: "center" }}>
          <Img src={staticFile(`frameworks/${server.framework}.svg`)} width={16} height={16} />
        </span>
        <span style={{ fontSize: 12, fontWeight: 500 }}>{server.name}</span>
        <span style={{ fontSize: 11, color: color.ink2, fontVariantNumeric: "tabular-nums" }}>{server.address}</span>
      </div>
      <div style={{ display: "flex", alignItems: "center", gap: 5, height: 16, paddingLeft: 26, fontSize: 11, color: color.ink3 }}>
        <AgentGlyph agent={server.agent} size={10} />
        {server.label}
      </div>
    </div>
  );
}

export function QuestionPage({ group, agent, hover, press }: { group: Group; agent: Agent; hover: number; press: number }) {
  return (
    <div style={{ paddingTop: metrics.flare }}>
      <div style={{ display: "flex", alignItems: "center", gap: 8, height: metrics.header, padding: "0 12px 0 16px" }}>
        <span style={{ fontSize: 13, fontWeight: 600 }}>Needs you</span>
        {spacer}
        <span
          style={{
            height: 26,
            padding: "0 10px",
            display: "grid",
            placeItems: "center",
            borderRadius: 13,
            fontSize: 11,
            fontWeight: 500,
            color: color.ink2,
            background: "rgba(255,255,255,0.07)",
            boxShadow: "inset 0 0.5px 0 rgba(255,255,255,0.22), inset 0 0 0 0.5px rgba(255,255,255,0.1)",
          }}
        >
          Show all
        </span>
      </div>
      <div style={{ padding: "0 10px" }}>
        <div
          style={{
            padding: 12,
            borderRadius: 16,
            background: `rgba(255,146,48,${lerp(0.16, 0.26, hover)})`,
            boxShadow: `inset 0 0.5px 0 rgba(255,255,255,0.22), inset 0 0 0 0.5px rgba(255,146,48,${lerp(0.3, 0.45, hover)})`,
            transform: `scale(${1 - 0.025 * press})`,
          }}
        >
          <div style={{ display: "flex", alignItems: "center", gap: 8, height: 22, marginBottom: 10 }}>
            <ProjectBadge group={group} size={18} />
            <span style={{ fontSize: 12.5, fontWeight: 600 }}>{group.name}</span>
            {spacer}
            <AgentGlyph agent={agent} size={12} />
            <span style={{ fontSize: 11, color: color.ink3, fontVariantNumeric: "tabular-nums" }}>now</span>
          </div>
          <span
            style={{
              display: "inline-flex",
              alignItems: "center",
              height: 18,
              padding: "0 6px",
              borderRadius: 9,
              marginBottom: 6,
              fontSize: 9.5,
              fontWeight: 600,
              letterSpacing: "0.04em",
              textTransform: "uppercase",
              color: color.orange,
              background: "rgba(255,146,48,0.14)",
            }}
          >
            {question.header}
          </span>
          <div style={{ fontSize: 13, fontWeight: 600, lineHeight: "17px" }}>{question.text}</div>
          <div style={{ display: "flex", flexDirection: "column", gap: 5, marginTop: 8 }}>
            {question.options.map((option) => (
              <div key={option.label} style={{ padding: 8, borderRadius: 10, background: "rgba(255,255,255,0.06)" }}>
                <div style={{ fontSize: 12, fontWeight: 500, lineHeight: "15px" }}>{option.label}</div>
                <div style={{ fontSize: 11, lineHeight: "14px", marginTop: 2, color: color.ink2 }}>{option.description}</div>
              </div>
            ))}
          </div>
          <div style={{ display: "flex", alignItems: "center", gap: 6, height: 24, marginTop: 12, fontSize: 11 }}>
            <span style={{ color: color.ink3, ...ellipsis }}>Migrate auth middleware to edge runtime</span>
            {spacer}
            <span style={{ fontWeight: 500, color: color.orange, opacity: lerp(0.8, 1, hover), whiteSpace: "nowrap" }}>Answer in Terminal</span>
            <svg width="9" height="9" viewBox="0 0 24 24" fill="none" stroke={color.orange} strokeWidth="3.4" strokeLinecap="round" strokeLinejoin="round" style={{ opacity: lerp(0.8, 1, hover), flexShrink: 0 }}>
              <path d="M7 17 17 7M9 7h8v8" />
            </svg>
          </div>
        </div>
      </div>
    </div>
  );
}

export const pressCurve = (t: number, at: number) => Math.sin(Math.PI * clamp01((t - at) / 0.22));
export const appearSpring = (t: number, at: number) => spring(t - at, springs.badge);
