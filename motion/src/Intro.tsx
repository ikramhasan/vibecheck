import { AbsoluteFill, Audio, staticFile, useCurrentFrame } from "remotion";
import { Caption, Chip, words } from "./components/Caption";
import { Orb } from "./components/Orb";
import { Screen } from "./Screen";
import { beats, duration, scenes } from "./story";
import { color, font, screen, stage } from "./theme";
import { clamp01, easeIn, easeInOut, easeOut, lerp, seg, spring, springs } from "./time";

const detail = 4;

type Shot = { cx: number; cy: number; z: number };
type Move = Shot & { at: number; dur: number };

const framed: Shot = { cx: 0, cy: 450, z: 0.6 };
const pinned = (z: number): Shot => ({ cx: screen.width - stage.width / 2 / z, cy: screen.height / 2, z });
const zoomed = beats.zoomToScreen + 1.15;
const moves: Move[] = [
  { at: beats.zoomToScreen, dur: zoomed - beats.zoomToScreen, ...pinned(4 / 3) },
  { at: 4.35, dur: 1.6, ...pinned(3) },
  { at: 9.85, dur: 1.2, ...pinned(1.85) },
  { at: 13.0, dur: 0.9, ...pinned(2.3) },
  { at: 15.6, dur: 1.3, ...pinned(1.55) },
  { at: 19.7, dur: 1.2, ...pinned(2.4) },
  { at: 23.65, dur: 1.4, ...pinned(4 / 3) },
];

function camera(t: number): Shot {
  let shot = framed;
  for (const move of moves) {
    const p = easeInOut(seg(t, move.at, move.at + move.dur));
    shot = {
      cx: lerp(shot.cx, move.cx, p),
      cy: lerp(shot.cy, move.cy, p),
      z: Math.exp(lerp(Math.log(shot.z), Math.log(move.z), p)),
    };
  }
  return t >= zoomed ? pinned(shot.z) : shot;
}

function Callout({ t, at, x, y, label, dot }: { t: number; at: number; x: number; y: number; label: string; dot: string }) {
  const p = easeOut(clamp01((t - at) / 0.55));
  const out = easeIn(seg(t, 8.7, 9.05));
  return (
    <div
      style={{
        position: "absolute",
        right: stage.width - x,
        top: y,
        transform: "translateY(-50%)",
        display: "flex",
        alignItems: "center",
        opacity: p * (1 - out),
      }}
    >
      <Chip style={{ fontSize: 24, padding: "12px 22px", transform: `translateX(${(p - 1) * 18}px)` }}>
        <span style={{ width: 12, height: 12, borderRadius: "50%", background: dot, boxShadow: `0 0 12px ${dot}` }} />
        {label}
      </Chip>
      <span style={{ width: 44 * p, height: 1.5, background: "rgba(255,255,255,0.35)" }} />
    </div>
  );
}

function EndCard({ t }: { t: number }) {
  const local = t - scenes.end;
  if (local < 0) return null;
  const orb = spring(local - 0.3, springs.pop);
  const tagline = easeOut(clamp01((local - 1.05) / 0.7));
  const install = easeOut(clamp01((local - 1.45) / 0.7));
  const note = easeOut(clamp01((local - 1.75) / 0.7));
  return (
    <AbsoluteFill style={{ alignItems: "center", justifyContent: "center" }}>
      <div style={{ display: "flex", flexDirection: "column", alignItems: "center" }}>
        <div style={{ display: "flex", alignItems: "center", gap: 40 }}>
          <div style={{ transform: `scale(${Math.max(0.01, orb)})`, opacity: clamp01(orb * 3) }}>
            <Orb look={{ state: "working" }} size={190} color={color.blue} time={t} />
          </div>
          <h1
            style={{
              margin: 0,
              fontFamily: font.display,
              fontSize: 176,
              lineHeight: 1,
              fontWeight: 700,
              letterSpacing: "-0.045em",
              color: color.text,
            }}
          >
            {words("vibecheck", t, scenes.end + 0.55, 0)}
          </h1>
        </div>
        <p
          style={{
            margin: "20px 0 0",
            fontFamily: font.text,
            fontSize: 42,
            letterSpacing: "-0.015em",
            color: color.text2,
            opacity: tagline,
            transform: `translateY(${(1 - tagline) * 16}px)`,
            filter: `blur(${(1 - tagline) * 6}px)`,
          }}
        >
          Every coding agent, at the edge of your screen.
        </p>
        <div style={{ marginTop: 56, opacity: install, transform: `translateY(${(1 - install) * 16}px)` }}>
          <Chip style={{ fontFamily: font.mono, fontSize: 26, padding: "18px 30px" }}>
            <span style={{ color: color.text3 }}>$</span>
            brew install --cask ikramhasan/tap/vibecheck
          </Chip>
        </div>
        <p style={{ margin: "26px 0 0", fontFamily: font.text, fontSize: 22, color: color.text3, opacity: note }}>
          Free · macOS 26 on Apple Silicon
        </p>
      </div>
    </AbsoluteFill>
  );
}

export function Intro() {
  const t = useCurrentFrame() / stage.fps;
  const shot = camera(t);
  const enter = easeOut(seg(t, 0, 1.0));
  const framing = 1 - easeInOut(seg(t, beats.zoomToScreen, beats.zoomToScreen + 1.15));
  const leave = easeInOut(seg(t, scenes.end - 0.3, scenes.end + 0.6));
  const x = stage.width / 2 - shot.cx * shot.z + (1 - enter) * 90;
  const y = stage.height / 2 - shot.cy * shot.z;
  const scrim = easeOut(seg(t, 4.6, 5.4)) * (1 - easeOut(seg(t, 23.65, 24.3)));
  const answerChip = easeOut(clamp01((t - 24.45) / 0.55)) * (1 - easeIn(seg(t, 25.25, 25.55)));
  const fadeOut = easeIn(seg(t, duration - 0.5, duration));

  return (
    <AbsoluteFill style={{ background: color.ground, fontFamily: font.text, overflow: "hidden" }}>
      <AbsoluteFill
        style={{
          background: `radial-gradient(90% 80% at 85% 0%, rgba(0,145,255,0.16), transparent 60%), radial-gradient(70% 70% at 0% 100%, rgba(255,146,48,0.08), transparent 60%)`,
        }}
      />
      {t < scenes.end + 0.6 && (
        <AbsoluteFill
          style={{
            opacity: enter * (1 - leave),
            transform: `scale(${1 - 0.06 * leave})`,
            filter: leave > 0 ? `blur(${14 * leave}px)` : undefined,
          }}
        >
          <div
            style={{
              position: "absolute",
              left: 0,
              top: 0,
              width: screen.width * detail,
              height: screen.height * detail,
              transformOrigin: "0 0",
              transform: `translate(${x}px, ${y}px) scale(${shot.z / detail})`,
              clipPath: `inset(0 round ${((22 * detail) / shot.z) * framing}px)`,
              boxShadow: `0 ${50 * detail * framing}px ${120 * detail * framing}px rgba(0,0,0,${0.5 * framing}), 0 0 0 ${(1.5 * detail) / shot.z}px rgba(255,255,255,${0.1 + 0.05 * framing})`,
            }}
          >
            <div style={{ zoom: detail, width: screen.width, height: screen.height }}>
              <Screen t={t} cameraZoom={shot.z} />
            </div>
          </div>
          <AbsoluteFill
            style={{
              opacity: scrim,
              background: `linear-gradient(90deg, ${color.ground} 0%, rgba(11,11,14,0.9) 34%, rgba(11,11,14,0.55) 46%, transparent 58%)`,
            }}
          />
        </AbsoluteFill>
      )}

      <Caption t={t} enter={0.25} exit={2.85} title="vibecheck" sub="Every agent’s status, without switching windows" top={370} size={168} width={760} />
      <Caption t={t} enter={5.2} exit={8.75} title="Lives on the edge of your screen" sub="One orb per session, and the usage you have left" />
      <Callout t={t} at={6.0} x={1778} y={478} label="Live status" dot={color.blue} />
      <Callout t={t} at={6.35} x={1778} y={700} label="Usage left" dot={color.green} />
      <Caption t={t} enter={10.6} exit={12.75} title="Hover to see every session" sub="Grouped by project, with what each agent is doing" />
      <Caption t={t} enter={13.35} exit={15.35} title="And every server they started" sub="Dev servers your agents left running, and their ports" />
      <Caption t={t} enter={16.15} exit={19.45} title="Every machine, over SSH" sub="Sessions on your other machines sit beside your own" />
      <Caption t={t} enter={20.5} exit={23.4} title="When an agent needs you, it says so" sub="The panel opens on its own, with the question waiting" />
      <div
        style={{
          position: "absolute",
          right: 96,
          bottom: 96,
          opacity: answerChip,
          transform: `translateY(${(1 - answerChip) * 16}px)`,
        }}
      >
        <Chip>
          <span style={{ width: 12, height: 12, borderRadius: "50%", background: color.orange, boxShadow: `0 0 12px ${color.orange}` }} />
          One click takes you back to its terminal
        </Chip>
      </div>

      <Audio src={staticFile("score.wav")} />
      <EndCard t={t} />
      <AbsoluteFill style={{ background: color.ground, opacity: fadeOut }} />
    </AbsoluteFill>
  );
}
