import type { OrbLook } from "../../apps/web/lib/orb-core";

export const scenes = {
  desk: 0,
  glance: 4,
  hover: 9,
  machines: 15.4,
  attention: 19.6,
  end: 25.6,
};
export const duration = 30.6;

export const beats = {
  panelArrives: 1.2,
  ringsFill: 1.7,
  zoomToScreen: 3.0,
  flakyDone: 6.7,
  hoverExpand: 10.15,
  serversClick: 12.95,
  agentsClick: 15.75,
  remotesJoin: 16.55,
  collapseForAttention: 19.85,
  edgeAsks: 20.6,
  questionOpens: 21.2,
  answerClick: 23.55,
  edgeResumes: 24.7,
};

export type Agent = "claude" | "codex" | "pi";
export type Status = "working" | "asking" | "idle";

export type Session = {
  id: string;
  agent: Agent;
  look: OrbLook;
  task: string;
  activity: string;
  reply?: string;
  elapsed: string;
  context?: number;
  diff?: [number, number];
  runsServer?: boolean;
};

export type Group = {
  name: string;
  icon?: string;
  monogram: string;
  host?: string;
  sessions: Session[];
};

export const oauth: Session = {
  id: "oauth",
  agent: "claude",
  look: { state: "working" },
  task: "Add OAuth callback route",
  activity: "Editing src/auth/callback.ts",
  elapsed: "4m",
  context: 0.42,
  diff: [128, 14],
  runsServer: true,
};

export const flaky: Session = {
  id: "flaky",
  agent: "codex",
  look: { state: "searching", variant: "lighthouse" },
  task: "Fix flaky checkout test",
  activity: "Running npm test",
  reply: "Fixed the race in cart.spec.ts",
  elapsed: "2m",
  diff: [9, 3],
};

export const edge: Session = {
  id: "edge",
  agent: "codex",
  look: { state: "background", variant: "spiral" },
  task: "Migrate auth middleware to edge runtime",
  activity: "Reading middleware.ts",
  elapsed: "7m",
  context: 0.68,
};

export const loader: Session = {
  id: "loader",
  agent: "claude",
  look: { state: "working", variant: "gyro" },
  task: "Speed up the data loader",
  activity: "Running python bench.py",
  elapsed: "12m",
  context: 0.31,
};

export const health: Session = {
  id: "health",
  agent: "pi",
  look: { state: "base" },
  task: "Add a health check endpoint",
  activity: "",
  reply: "Added /healthz with a database ping",
  elapsed: "3m ago",
};

export const localGroups: Group[] = [
  { name: "web-app", icon: "projects/web-app.svg", monogram: "WA", sessions: [oauth, flaky] },
  { name: "api", icon: "projects/api.svg", monogram: "AP", sessions: [edge] },
];

export const remoteGroups: Group[] = [
  { name: "ml-pipeline", icon: "projects/ml-pipeline.svg", monogram: "ML", host: "gpu-box", sessions: [loader] },
  { name: "infra", icon: "projects/infra.svg", monogram: "IN", host: "staging-01", sessions: [health] },
];

export function statusChanges(session: Session): number[] {
  if (session === flaky) return [beats.flakyDone];
  if (session === edge) return [beats.edgeAsks, beats.edgeResumes];
  return [];
}

export function statusAt(session: Session, t: number): Status {
  if (session === flaky) return t < beats.flakyDone ? "working" : "idle";
  if (session === edge) return t >= beats.edgeAsks && t < beats.edgeResumes ? "asking" : "working";
  if (session === health) return "idle";
  return "working";
}

export const servers = [
  { framework: "nextjs", name: "Next.js", address: "localhost:3000", agent: "claude" as Agent, label: "web-app" },
  { framework: "vite", name: "Vite", address: "localhost:5173", agent: "codex" as Agent, label: "web-app/admin" },
  { framework: "node", name: "Node.js", address: "localhost:8080", agent: "codex" as Agent, label: "api" },
];

export const usage = [
  {
    agent: "claude" as Agent,
    name: "Claude",
    plan: "Max 5x",
    windows: [
      { label: "5h", used: 37, resets: "3h 36m" },
      { label: "Weekly", used: 82, resets: "6d 0h" },
    ],
  },
  {
    agent: "codex" as Agent,
    name: "Codex",
    plan: "Plus",
    windows: [
      { label: "5h", used: 12, resets: "2h 12m" },
      { label: "Weekly", used: 41, resets: "3d 0h" },
    ],
  },
];

export const question = {
  header: "Runtime",
  text: "Which runtime should the middleware target?",
  options: [
    { label: "Edge", description: "Runs close to your users, without Node APIs" },
    { label: "Node.js", description: "Full Node APIs, served from one region" },
  ],
};
