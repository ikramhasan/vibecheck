import { Cursor, cursorPosition, type CursorKey } from "./components/Cursor";
import { MenuBar, Wallpaper, Window, screenBox, tone } from "./components/Desktop";
import { collapsedHeight, metrics, Panel } from "./components/Panel";
import {
  appearSpring,
  CollapsedBadges,
  GroupDivider,
  GroupView,
  Header,
  pressCurve,
  QuestionPage,
  ServerRow,
  UsageSection,
} from "./components/pages";
import { cascade, type Reveal } from "./components/parts";
import { beats, edge, localGroups, remoteGroups, servers } from "./story";
import { screen } from "./theme";
import { easeInOut, easeOut, seg, settle, spring, springs } from "./time";

const pageSpring = { response: 0.36, damping: 0.86 };
const growSpring = { response: 0.42, damping: 0.8 };
const popOut = { response: 0.42, damping: 0.68 };

const groupHeight = (sessions: number) => metrics.groupHeader + metrics.groupPadding + sessions * (metrics.sessionLine + metrics.detailLine);
const localList = groupHeight(2) + metrics.groupDivider + groupHeight(1);
const fullList = localList + 2 * (metrics.groupDivider + groupHeight(1));
const usageBlock = 30 + 2 * (22 + 2 * 20 + 10);
const sessionsPage = (list: number) => metrics.flare * 2 + metrics.header + list + usageBlock + 12;
const serversPage = metrics.flare * 2 + metrics.header + servers.length * metrics.serverRow + 8 + 12;
const questionPage = 334;

const cursorKeys: CursorKey[] = [
  { at: 0, x: 1180, y: 880 },
  { at: 9.3, x: 1419, y: 468, dur: 0.8, bow: 0.1 },
  { at: 11.85, x: 1238, y: 262, dur: 0.85, bow: 0.12 },
  { at: 14.95, x: 1150, y: 374, dur: 0.65, bow: 0.1 },
  { at: 16.2, x: 1290, y: 590, dur: 1.0, bow: 0.12 },
  { at: 19.55, x: 860, y: 660, dur: 0.6, bow: 0.06 },
  { at: 22.45, x: 1352, y: 560, dur: 0.75, bow: -0.12 },
];

function cursorOpacity(t: number) {
  const first = easeOut(seg(t, 9.15, 9.4)) * (1 - easeOut(seg(t, 19.95, 20.25)));
  const second = easeOut(seg(t, 22.3, 22.5)) * (1 - easeOut(seg(t, 23.95, 24.25)));
  return Math.max(first, second);
}

function ApiTerminal({ t }: { t: number }) {
  const asking = t >= beats.edgeAsks;
  const answered = t >= beats.answerClick + 0.35;
  const caret = Math.floor(t / 0.53) % 2 === 0;
  return (
    <>
      <span style={tone.prompt}>› </span>Migrate auth middleware to edge runtime{"\n\n"}
      <span style={tone.tool}>  Read </span>  src/middleware.ts{"\n"}
      <span style={tone.tool}>  Read </span>  src/auth/session.ts{"\n"}
      <span style={tone.dim}>  Both run on Node today. The edge runtime has no fs or crypto.</span>
      {"\n\n"}
      {asking && !answered && (
        <>
          <span style={tone.ask}>  ? Which runtime should the middleware target?{"\n"}</span>
          <span style={tone.ask}>    › Edge</span>
          {"\n      Node.js "}
          <span style={{ opacity: caret ? 1 : 0, background: "rgba(255,255,255,0.85)" }}> </span>
        </>
      )}
      {answered && (
        <>
          <span style={tone.dim}>  ✓ Edge{"\n"}</span>
          <span style={tone.edit}>  Edit </span>  src/middleware.ts   <span style={tone.str}>+31</span> <span style={{ color: "#ff8a8a" }}>−12</span>
        </>
      )}
    </>
  );
}

export function Screen({ t, cameraZoom }: { t: number; cameraZoom: number }) {
  const remotesIn = t >= beats.remotesJoin;
  const collapsedSessions = remotesIn ? [...localGroups, ...remoteGroups].flatMap((g) => g.sessions) : localGroups.flatMap((g) => g.sessions);

  const open = settle(t, 0, [
    { at: beats.hoverExpand, to: 1, spring: springs.open },
    { at: beats.collapseForAttention, to: 0, spring: springs.close },
    { at: beats.questionOpens, to: 1, spring: popOut },
    { at: beats.answerClick + 0.08, to: 0, spring: springs.close },
  ]);
  const listHeight = settle(t, localList, [{ at: beats.remotesJoin, to: fullList, spring: growSpring }]);
  const pageHeight = settle(t, sessionsPage(localList), [
    { at: beats.serversClick, to: serversPage, spring: pageSpring },
    { at: beats.agentsClick, to: sessionsPage(localList), spring: pageSpring },
    { at: beats.remotesJoin, to: sessionsPage(fullList), spring: growSpring },
    { at: beats.edgeAsks, to: questionPage, spring: pageSpring },
  ]);
  const onServers = settle(t, 0, [
    { at: beats.serversClick, to: 1, spring: springs.tab },
    { at: beats.agentsClick, to: 0, spring: springs.tab },
  ]);

  const rows: Reveal[] = [
    { at: beats.hoverExpand, shown: true, side: 1, paced: false },
    { at: beats.serversClick, shown: false, side: -1, paced: true },
    { at: beats.agentsClick, shown: true, side: -1, paced: true },
    { at: beats.collapseForAttention, shown: false, side: 1, paced: false },
  ];
  const serverRows: Reveal[] = [
    { at: beats.serversClick, shown: true, side: 1, paced: true },
    { at: beats.agentsClick, shown: false, side: 1, paced: true },
  ];
  const remoteRows: Reveal[] = [
    { at: beats.remotesJoin, shown: true, side: 1, paced: false },
    { at: beats.collapseForAttention, shown: false, side: 1, paced: false },
  ];

  const questionShown =
    easeOut(seg(t, beats.questionOpens + 0.1, beats.questionOpens + 0.35)) * (1 - easeOut(seg(t, beats.answerClick + 0.1, beats.answerClick + 0.3)));
  const cardHover = easeOut(seg(t, 23.15, 23.3));
  const click = (at: number) => pressCurve(t, at);
  const press = Math.max(click(beats.serversClick), click(beats.agentsClick), click(beats.answerClick));
  const countFlip = Math.sin(Math.PI * seg(t, beats.remotesJoin, beats.remotesJoin + 0.3));

  const cursor = cursorPosition(t, cursorKeys);
  const raise = easeInOut(seg(t, beats.answerClick + 0.15, beats.answerClick + 0.6));
  const raiseFade = 1 - easeOut(seg(t, 25.0, 25.5));
  const groups = [...localGroups, ...(remotesIn ? remoteGroups : [])];

  return (
    <div style={screenBox}>
      <Wallpaper />
      <MenuBar />
      <Window x={610} y={130} width={700} height={560} title="callback.ts — web-app">
        <span style={tone.key}>export async function</span> GET(req: Request) {"{\n"}
        {"  "}
        <span style={tone.key}>const</span> url = <span style={tone.key}>new</span> URL(req.url){"\n"}
        {"  "}
        <span style={tone.key}>const</span> code = url.searchParams.get(<span style={tone.str}>"code"</span>){"\n"}
        {"  "}
        <span style={tone.key}>if</span> (!code) <span style={tone.key}>return</span> redirect(<span style={tone.str}>"/login"</span>){"\n\n"}
        {"  "}
        <span style={tone.key}>const</span> token = <span style={tone.key}>await</span> exchange(code){"\n"}
        {"  "}
        <span style={tone.key}>const</span> session = <span style={tone.key}>await</span> createSession(token){"\n"}
        {"  "}
        <span style={tone.key}>return</span> redirect(<span style={tone.str}>"/"</span>, {"{ session })\n}"}
      </Window>
      <Window
        x={110}
        y={500}
        width={620}
        height={330}
        title="api — codex"
        active={raise > 0.5}
        style={{
          zIndex: raise > 0 ? 3 : undefined,
          transform: `translateY(${-8 * raise}px)`,
          boxShadow: `0 0 0 0.5px rgba(255,255,255,0.14), 0 28px 70px rgba(0,0,0,0.45), 0 0 0 ${3 * raise * raiseFade}px rgba(255,146,48,${0.9 * raise * raiseFade})`,
        }}
      >
        <ApiTerminal t={t} />
      </Window>
      <Window x={60} y={64} width={650} height={400} title="web-app — claude" active={raise < 0.5}>
        <span style={tone.prompt}>› </span>Add OAuth callback route{"\n\n"}
        <span style={tone.tool}>  Read </span>  src/auth/callback.ts{"\n"}
        <span style={tone.edit}>  Edit </span>  src/auth/callback.ts   <span style={tone.str}>+42</span> <span style={{ color: "#ff8a8a" }}>−7</span>
        {"\n"}
        <span style={tone.tool}>  Run  </span>  npm run dev{"\n"}
        <span style={tone.dim}>         ready on localhost:3000{"\n\n"}</span>
        <span style={tone.edit}>  Edit </span>  src/auth/session.ts   <span style={tone.str}>+86</span> <span style={{ color: "#ff8a8a" }}>−7</span>
        {"\n\n"}
        <span style={tone.dim}>  Thinking{".".repeat(1 + (Math.floor(t * 2.5) % 3))}</span>
      </Window>
      <div style={{ position: "absolute", inset: 0, zIndex: 5 }}>
        <Panel
          open={open}
          collapsedHeight={collapsedHeight(collapsedSessions.length)}
          pageHeight={pageHeight}
          centerY={screen.height / 2}
          shift={(metrics.collapsedWidth + 12) * (1 - spring(t - beats.panelArrives, popOut))}
          collapsed={
            <CollapsedBadges
              sessions={collapsedSessions}
              t={t}
              appear={(i) => appearSpring(t, i < 3 ? beats.panelArrives + 0.15 + i * 0.07 : beats.remotesJoin)}
              fill={easeOut(seg(t, beats.ringsFill, beats.ringsFill + 1.2))}
            />
          }
          expanded={
            <div style={{ position: "relative", height: "100%" }}>
              <div style={{ position: "absolute", inset: 0, paddingTop: metrics.flare, opacity: t < beats.edgeAsks ? 1 : 0 }}>
                <Header agents={remotesIn ? 5 : 3} countOpacity={1 - countFlip} onServers={onServers} />
                <div style={{ position: "relative" }}>
                  <div style={{ height: listHeight, overflow: "hidden" }}>
                    {groups.map((group, i) => {
                      const reveal = i < localGroups.length ? rows : remoteRows;
                      const index = i < localGroups.length ? i + 1 : i - localGroups.length + 1;
                      return (
                        <div key={group.name} style={cascade(t, index, reveal)}>
                          {i > 0 && <GroupDivider />}
                          <GroupView group={group} t={t} />
                        </div>
                      );
                    })}
                  </div>
                  <div style={cascade(t, groups.length + 1, rows)}>
                    <UsageSection />
                  </div>
                  <div style={{ position: "absolute", left: 0, right: 0, top: 0, padding: "4px 6px" }}>
                    {servers.map((server, i) => (
                      <div key={server.name} style={cascade(t, i + 1, serverRows)}>
                        <ServerRow server={server} />
                      </div>
                    ))}
                  </div>
                </div>
              </div>
              <div style={{ position: "absolute", inset: 0, opacity: questionShown }}>
                <QuestionPage group={localGroups[1]} agent={edge.agent} hover={cardHover} press={click(beats.answerClick)} />
              </div>
            </div>
          }
        />
      </div>
      <Cursor x={cursor.x} y={cursor.y} scale={1.45 / cameraZoom} press={press} opacity={cursorOpacity(t)} />
    </div>
  );
}
