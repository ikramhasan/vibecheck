import type { OrbLook } from "@/lib/orb-core";
import type { Status } from "./Orb";

export type Agent = "claude" | "codex" | "pi" | "kiro";

export type Session = {
  id: string;
  agent: Agent;
  status: Status;
  look: OrbLook;
  headline: string;
  detail: string;
  elapsed: string;
  context?: number;
};

export type Group = {
  name: string;
  monogram: string;
  sessions: Session[];
};

export type Usage = {
  agent: Agent;
  name: string;
  plan: string;
  windows: { label: string; used: number; resets: string }[];
};

export const groups: Group[] = [
  {
    name: "shop-web",
    monogram: "SW",
    sessions: [
      {
        id: "preview-2",
        agent: "codex",
        status: "asking",
        look: { state: "waiting" },
        headline: "Which runtime should the middleware target?",
        detail: "Migrate auth middleware to edge runtime",
        elapsed: "1m",
      },
      {
        id: "preview-1",
        agent: "claude",
        status: "working",
        look: { state: "working" },
        headline: "Add Stripe checkout to pricing page",
        detail: "Working · Running npm test",
        elapsed: "9m",
        context: 0.48,
      },
    ],
  },
  {
    name: "notes-app",
    monogram: "NA",
    sessions: [
      {
        id: "preview-4",
        agent: "claude",
        status: "blocked",
        look: { state: "retrying" },
        headline: "Write the release notes",
        detail: "Blocked · Usage limit reached",
        elapsed: "15m",
      },
      {
        id: "preview-3",
        agent: "pi",
        status: "working",
        look: { state: "reasoning" },
        headline: "Redesign the settings window",
        detail: "Working · Editing SettingsView.swift",
        elapsed: "4m",
      },
    ],
  },
  {
    name: "cli",
    monogram: "Cl",
    sessions: [
      {
        id: "preview-5",
        agent: "codex",
        status: "idle",
        look: { state: "base" },
        headline: "Fix flaky snapshot test",
        detail: "Fixed it. The snapshot depended on the time zone, so I pinned it to UTC.",
        elapsed: "1m ago",
      },
    ],
  },
];

export const usage: Usage[] = [
  {
    agent: "claude",
    name: "Claude",
    plan: "Max 5x",
    windows: [
      { label: "5h", used: 37, resets: "3h 36m" },
      { label: "Weekly", used: 82, resets: "6d 0h" },
    ],
  },
  {
    agent: "codex",
    name: "Codex",
    plan: "Plus",
    windows: [
      { label: "5h", used: 12, resets: "2h 12m" },
      { label: "Weekly", used: 41, resets: "3d 0h" },
    ],
  },
  {
    agent: "kiro",
    name: "Kiro",
    plan: "Power",
    windows: [{ label: "Monthly", used: 68, resets: "19d 0h" }],
  },
];
