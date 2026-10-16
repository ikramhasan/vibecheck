"use client";

import { useEffect, useRef, useState } from "react";
import { Orb } from "./Orb";
import { groups, usage, type Agent, type Group, type Session, type Usage } from "./sessions";

const flare = 14;
const corner = 14;
const collapsedWidth = 44;
const expandedWidth = 340;
const badgeSize = 26;
const collapsedSlot = badgeSize + 7;
const headerHeight = 44;
const groupHeader = 26;
const groupPadding = 10;
const groupDivider = 5;
const sessionLine = 24;
const detailLine = 16;
const usageHeaderHeight = 30;
const usageProviderHeader = 22;
const usageLine = 20;
const usageProviderGap = 10;

const sessions = groups.flatMap((g) => g.sessions);
const groupHeight = (g: Group) => groupHeader + groupPadding + g.sessions.length * (sessionLine + detailLine);
const listHeight = groups.map(groupHeight).reduce((a, b) => a + b, 0) + (groups.length - 1) * groupDivider;
const usageHeight =
  usageHeaderHeight + usage.reduce((sum, u) => sum + usageProviderHeader + u.windows.length * usageLine + usageProviderGap, 0);
const expandedHeight = flare * 2 + headerHeight + listHeight + usageHeight + 12;
const collapsedHeight = flare * 2 + 16 + (sessions.length + 1) * collapsedSlot + 1 + collapsedSlot - badgeSize;

function edgeTabPath(w: number, h: number) {
  const f = Math.min(flare, h / 4);
  const c = Math.min(corner, (w - f) / 2, (h - 2 * f) / 2);
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

type SpringSettings = { response: number; damping: number };
const opening: SpringSettings = { response: 0.46, damping: 0.62 };
const closing: SpringSettings = { response: 0.34, damping: 0.86 };

type Spot = "away" | "tab" | "row" | "hidden";
type CursorMove = { spot: Spot; duration: number };

export function PanelPreview() {
  const stage = useRef<HTMLDivElement>(null);
  const panel = useRef<HTMLDivElement>(null);
  const card = useRef<HTMLDivElement>(null);
  const collapsed = useRef<HTMLDivElement>(null);
  const shadowPath = useRef<SVGPathElement>(null);
  const edgePath = useRef<SVGPathElement>(null);
  const glass = useRef<HTMLDivElement>(null);
  const progress = useRef({ value: 0, velocity: 0, target: 0, spring: opening, frame: 0 });
  const [size, setSize] = useState({ width: 0, height: 0 });
  const [cursor, setCursor] = useState<CursorMove>({ spot: "away", duration: 0 });

  const scale = Math.min(1, (size.height - 56) / expandedHeight, (size.width - 32) / expandedWidth);

  useEffect(() => {
    const observer = new ResizeObserver(([entry]) =>
      setSize({ width: entry.contentRect.width, height: entry.contentRect.height }),
    );
    observer.observe(stage.current!);
    return () => observer.disconnect();
  }, []);

  useEffect(() => {
    const render = (p: number) => {
      const w = collapsedWidth + (expandedWidth - collapsedWidth) * p;
      const h = collapsedHeight + (expandedHeight - collapsedHeight) * p;
      const path = edgeTabPath(w, h);
      const shown = Math.min(1, Math.max(0, p));
      panel.current!.style.width = `${w}px`;
      panel.current!.style.height = `${h}px`;
      glass.current!.style.clipPath = `path("${path}")`;
      shadowPath.current!.setAttribute("d", path);
      edgePath.current!.setAttribute("d", path);
      card.current!.style.opacity = String(shown);
      card.current!.style.transform = `translateY(-50%) scale(${0.96 + 0.04 * shown})`;
      collapsed.current!.style.opacity = String(1 - shown);
    };
    render(progress.current.value);

    const animateTo = (target: number, spring: SpringSettings) => {
      const state = progress.current;
      state.target = target;
      state.spring = spring;
      cancelAnimationFrame(state.frame);
      let last = performance.now();
      const step = (now: number) => {
        const dt = Math.min(0.05, (now - last) / 1000);
        last = now;
        const stiffness = (2 * Math.PI / state.spring.response) ** 2;
        const friction = (4 * Math.PI * state.spring.damping) / state.spring.response;
        for (let i = 0; i < 8; i++) {
          const force = -stiffness * (state.value - state.target) - friction * state.velocity;
          state.velocity += (force * dt) / 8;
          state.value += (state.velocity * dt) / 8;
        }
        const settled = Math.abs(state.value - state.target) < 0.0005 && Math.abs(state.velocity) < 0.005;
        if (settled) state.value = state.target;
        render(state.value);
        if (!settled) state.frame = requestAnimationFrame(step);
      };
      state.frame = requestAnimationFrame(step);
    };

    if (matchMedia("(prefers-reduced-motion: reduce)").matches) {
      progress.current.value = 1;
      render(1);
      setCursor({ spot: "hidden", duration: 0 });
      return;
    }

    let cancelled = false;
    const wait = (seconds: number) => new Promise((resolve) => setTimeout(resolve, seconds * 1000));
    const loop = async () => {
      while (!cancelled) {
        await wait(1.2);
        if (cancelled) return;
        setCursor({ spot: "tab", duration: 0.9 });
        await wait(1.0);
        if (cancelled) return;
        animateTo(1, opening);
        setCursor({ spot: "row", duration: 0.7 });
        await wait(3.6);
        if (cancelled) return;
        setCursor({ spot: "away", duration: 0.8 });
        await wait(0.45);
        if (cancelled) return;
        animateTo(0, closing);
      }
    };
    loop();
    return () => {
      cancelled = true;
      cancelAnimationFrame(progress.current.frame);
    };
  }, []);

  const point = cursorPoint(cursor.spot, size, scale);

  return (
    <div className="stage" ref={stage} role="img" aria-label="Preview of the vibecheck panel opening from the screen edge">
      <div className="wallpaper" aria-hidden />
      <div
        className="panel"
        ref={panel}
        style={{ transform: `translateY(-50%) scale(${scale || 1})`, visibility: size.width ? "visible" : "hidden" }}
        aria-hidden
      >
        <svg className="panel-shadow">
          <path ref={shadowPath} />
        </svg>
        <div className="glass" ref={glass}>
          <div className="card" ref={card} style={{ height: expandedHeight }}>
            <ExpandedContent />
          </div>
          <div className="collapsed" ref={collapsed}>
            <CollapsedContent />
          </div>
        </div>
        <svg className="panel-edge">
          <path ref={edgePath} />
        </svg>
      </div>
      <svg
        className="cursor"
        width="24"
        height="24"
        viewBox="0 0 24 24"
        style={{
          transform: `translate(${point.x - 5}px, ${point.y - 3}px)`,
          transitionDuration: `${cursor.duration}s`,
          opacity: size.width && cursor.spot !== "hidden" ? 1 : 0,
        }}
        aria-hidden
      >
        <path d="M5 3v16.5l4.3-4.1 2.8 6.4 2.9-1.3-2.8-6.2H18.3z" fill="#000" stroke="#fff" strokeWidth="1.4" strokeLinejoin="round" />
      </svg>
    </div>
  );
}

function cursorPoint(spot: Spot, size: { width: number; height: number }, scale: number) {
  switch (spot) {
    case "away":
      return { x: size.width * 0.3, y: size.height * 0.62 };
    case "tab":
      return { x: size.width - collapsedWidth * scale * 0.45, y: size.height * 0.5 + 6 };
    case "row":
      return { x: size.width - expandedWidth * scale * 0.55, y: size.height * 0.5 + 10 };
    case "hidden":
      return { x: -40, y: -40 };
  }
}

function CollapsedContent() {
  return (
    <div className="badges">
      {sessions.map((session) => (
        <div className="badge" key={session.id}>
          <Orb look={session.look} size={31} status={session.status} />
          <AgentGlyph agent={session.agent} size={13} className="badge-agent" />
        </div>
      ))}
      <div className="badge-divider" />
      <UsageDial />
    </div>
  );
}

function UsageDial() {
  const lineWidth = 3;
  const gap = 1.5;
  return (
    <svg className="usage-dial" width={badgeSize} height={badgeSize} viewBox={`0 0 ${badgeSize} ${badgeSize}`}>
      {usage.map((provider, index) => {
        const peak = Math.max(...provider.windows.map((w) => w.used));
        const radius = badgeSize / 2 - index * (lineWidth + gap) - lineWidth;
        const circumference = 2 * Math.PI * radius;
        return (
          <g key={provider.agent} className={`meter-${usageLevel(peak)}`}>
            <circle cx="13" cy="13" r={radius} className="ring-track" strokeWidth={lineWidth} />
            <circle
              cx="13"
              cy="13"
              r={radius}
              className="ring-fill"
              strokeWidth={lineWidth}
              strokeDasharray={`${(circumference * peak) / 100} ${circumference}`}
              transform="rotate(-90 13 13)"
            />
          </g>
        );
      })}
    </svg>
  );
}

function ExpandedContent() {
  return (
    <div className="expanded">
      <div className="expanded-header">
        <span className="expanded-title">Agents</span>
        <span className="expanded-count">{sessions.length}</span>
        <span className="spacer" />
        <span className="gear">
          <GearIcon />
        </span>
      </div>
      <div style={{ height: listHeight }}>
        {groups.map((group, index) => (
          <div key={group.name}>
            {index > 0 && <div className="group-divider" />}
            <SessionGroup group={group} />
          </div>
        ))}
      </div>
      <UsageSection />
    </div>
  );
}

function SessionGroup({ group }: { group: Group }) {
  return (
    <div className="group">
      <div className="group-header">
        <span className="project-badge">{group.monogram}</span>
        <span className="group-name">{group.name}</span>
        <span className="spacer" />
        {group.sessions.length > 1 && <span className="group-count">{group.sessions.length} agents</span>}
      </div>
      {group.sessions.map((session) => (
        <SessionLine key={session.id} session={session} />
      ))}
    </div>
  );
}

function SessionLine({ session }: { session: Session }) {
  return (
    <div className={`line line-${session.status}`}>
      <div className="line-main">
        <Orb look={session.look} size={18} status={session.status} />
        <span className="line-headline">{session.headline}</span>
        <span className="spacer" />
        {session.context !== undefined && <ContextGauge fraction={session.context} />}
        <span className="line-elapsed">{session.elapsed}</span>
      </div>
      <div className="line-detail">
        <span className="line-detail-text">{session.detail}</span>
        <span className="spacer" />
        <AgentGlyph agent={session.agent} size={12} />
      </div>
    </div>
  );
}

function ContextGauge({ fraction }: { fraction: number }) {
  const radius = 3.7;
  const circumference = 2 * Math.PI * radius;
  return (
    <svg className="context-gauge" width="9" height="9" viewBox="0 0 9 9">
      <circle cx="4.5" cy="4.5" r={radius} className="gauge-track" />
      <circle
        cx="4.5"
        cy="4.5"
        r={radius}
        className="gauge-fill"
        strokeDasharray={`${circumference * fraction} ${circumference}`}
        transform="rotate(-90 4.5 4.5)"
      />
    </svg>
  );
}

function UsageSection() {
  return (
    <div className="usage" style={{ height: usageHeight }}>
      <div className="usage-header">
        <span className="usage-title">Usage</span>
        <span className="spacer" />
        <span className="usage-unit">% used</span>
        <RefreshIcon />
      </div>
      <div className="usage-providers">
        {usage.map((provider) => (
          <ProviderUsage key={provider.agent} provider={provider} />
        ))}
      </div>
    </div>
  );
}

function ProviderUsage({ provider }: { provider: Usage }) {
  return (
    <div>
      <div className="provider-header">
        <AgentGlyph agent={provider.agent} size={13} />
        <span className="provider-name">{provider.name}</span>
        <span className="provider-plan">{provider.plan}</span>
      </div>
      {provider.windows.map((window) => (
        <div className="window" key={window.label}>
          <span className="window-label">{window.label}</span>
          <span className={`window-bar meter-${usageLevel(window.used)}`}>
            <span style={{ width: `${window.used}%` }} />
          </span>
          <span className="window-percent">{window.used}%</span>
          <span className="window-reset">{window.resets}</span>
        </div>
      ))}
    </div>
  );
}

function usageLevel(used: number) {
  if (used < 75) return "low";
  if (used < 90) return "mid";
  return "high";
}

function AgentGlyph({ agent, size, className }: { agent: Agent; size: number; className?: string }) {
  return <img className={className} src={`/agents/${agent}.svg`} width={size} height={size} alt="" />;
}

function GearIcon() {
  return (
    <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <circle cx="12" cy="12" r="3" />
      <path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 1 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06A1.65 1.65 0 0 0 4.68 15a1.65 1.65 0 0 0-1.51-1H3a2 2 0 1 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06A1.65 1.65 0 0 0 9 4.68a1.65 1.65 0 0 0 1-1.51V3a2 2 0 1 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06A1.65 1.65 0 0 0 19.4 9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 1 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z" />
    </svg>
  );
}

function RefreshIcon() {
  return (
    <svg className="refresh" width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round">
      <path d="M21 12a9 9 0 1 1-2.64-6.36L21 8" />
      <path d="M21 3v5h-5" />
    </svg>
  );
}
