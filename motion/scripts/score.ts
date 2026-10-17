import { writeFileSync } from "node:fs";
import { beats, duration, scenes } from "../src/story.ts";

const rate = 48000;
const length = Math.ceil(duration * rate);
const dry = [new Float32Array(length), new Float32Array(length)];
const wet = [new Float32Array(length), new Float32Array(length)];
const TAU = Math.PI * 2;

const beat = scenes.end / 40;
const at = (n: number) => n * beat;

let seed = 7;
const noise = () => {
  seed = (seed * 1664525 + 1013904223) >>> 0;
  return seed / 2147483648 - 1;
};

const names: Record<string, number> = { C: 0, "C#": 1, D: 2, "D#": 3, E: 4, F: 5, "F#": 6, G: 7, "G#": 8, A: 9, "A#": 10, B: 11 };
function hz(note: string) {
  const [, name, octave] = note.match(/^([A-G]#?)(\d)$/)!;
  return 440 * 2 ** ((names[name] + 12 * (+octave + 1) - 69) / 12);
}

function voice(start: number, seconds: number, gain: number, pan: number, send: number, sample: (t: number) => number) {
  const from = Math.max(0, Math.round(start * rate));
  const to = Math.min(length, from + Math.round(seconds * rate));
  const left = gain * Math.cos(((pan + 1) * Math.PI) / 4);
  const right = gain * Math.sin(((pan + 1) * Math.PI) / 4);
  for (let i = from; i < to; i++) {
    const v = sample((i - from) / rate);
    dry[0][i] += v * left;
    dry[1][i] += v * right;
    wet[0][i] += v * left * send;
    wet[1][i] += v * right * send;
  }
}

const envelope = (t: number, attack: number, decay: number) => Math.min(1, t / attack) * Math.exp(-t / decay);

function pad(notes: string[], start: number, seconds: number, gain: number) {
  notes.forEach((note, n) => {
    const f = hz(note);
    voice(start, seconds + 2, gain, n % 2 ? 0.35 : -0.35, 0.8, (t) => {
      const swell = Math.min(1, t / 1.4) * Math.min(1, Math.max(0, (seconds + 1.6 - t) / 1.6));
      const tone = [-0.07, 0, 0.07].reduce((sum, cents) => {
        const p = TAU * f * 2 ** (cents / 12) * t;
        return sum + Math.sin(p) + 0.18 * Math.sin(2 * p) + 0.06 * Math.sin(3 * p);
      }, 0);
      return (tone / 3) * swell;
    });
  });
}

function keys(notes: string[], start: number, seconds: number, gain: number) {
  notes.forEach((note, n) => {
    const f = hz(note);
    voice(start + n * 0.012, seconds + 1.5, gain, (n / notes.length - 0.5) * 0.6, 0.45, (t) => {
      const index = 1.6 * Math.exp(-t / 0.35);
      const release = Math.min(1, Math.max(0, (seconds + 1.2 - t) / 1.2));
      return Math.sin(TAU * f * t + index * Math.sin(TAU * f * t)) * envelope(t, 0.006, 1.6) * release;
    });
  });
}

function bass(note: string, start: number, seconds: number, gain: number) {
  const f = hz(note);
  voice(start, seconds + 0.3, gain, 0, 0.05, (t) => {
    const release = Math.min(1, Math.max(0, (seconds + 0.25 - t) / 0.25));
    return (Math.sin(TAU * f * t) + 0.22 * Math.sin(TAU * 2 * f * t)) * Math.min(1, t / 0.012) * Math.exp(-t / 1.4) * release;
  });
}

function mallet(note: string, start: number, gain: number, pan = 0.2) {
  const f = hz(note);
  voice(start, 1.2, gain, pan, 0.35, (t) =>
    Math.sin(TAU * f * t) * envelope(t, 0.002, 0.32) + 0.3 * Math.sin(TAU * 4 * f * t) * envelope(t, 0.001, 0.05),
  );
}

function bell(note: string, start: number, gain: number, pan = 0) {
  const f = hz(note);
  voice(start, 4, gain, pan, 0.7, (t) => {
    const tremolo = 1 - 0.12 * (0.5 + 0.5 * Math.sin(TAU * 5.2 * t));
    return (Math.sin(TAU * f * t) * envelope(t, 0.003, 1.4) + 0.35 * Math.sin(TAU * 3.99 * f * t) * envelope(t, 0.002, 0.25)) * tremolo;
  });
}

function kick(start: number, gain: number) {
  voice(start, 0.5, gain, 0, 0.05, (t) => {
    const phase = TAU * (45 * t + (75 / 28) * (1 - Math.exp(-28 * t)));
    return Math.sin(phase) * envelope(t, 0.002, 0.16);
  });
}

function filteredNoise(start: number, seconds: number, gain: number, pan: number, send: number, cutoff: (t: number) => number, shape: (t: number) => number, highpass = false) {
  let low = 0;
  voice(start, seconds, gain, pan, send, (t) => {
    const k = 1 - Math.exp((-TAU * cutoff(t)) / rate);
    const n = noise();
    low += k * (n - low);
    return (highpass ? n - low : low) * shape(t);
  });
}

const hat = (start: number, gain: number) => filteredNoise(start, 0.08, gain, 0.3, 0.1, () => 7000, (t) => envelope(t, 0.001, 0.018), true);
const shaker = (start: number, gain: number) => filteredNoise(start, 0.12, gain, -0.3, 0.1, () => 5000, (t) => envelope(t, 0.012, 0.03), true);
function sidestick(start: number, gain: number) {
  filteredNoise(start, 0.06, gain, -0.15, 0.25, () => 2500, (t) => envelope(t, 0.0005, 0.012), true);
  voice(start, 0.06, gain * 0.5, -0.15, 0.25, (t) => Math.sin(TAU * 1700 * t) * envelope(t, 0.0005, 0.015));
}
const crash = (start: number, gain: number) => filteredNoise(start, 3.5, gain, 0.1, 0.5, () => 6000, (t) => envelope(t, 0.003, 0.9), true);

function pop(start: number, gain: number, pan = 0.4) {
  voice(start, 0.2, gain, pan, 0.3, (t) => {
    const phase = TAU * (900 * t - 400 * 0.02 * (1 - Math.exp(-t / 0.02)));
    return Math.sin(phase) * envelope(t, 0.002, 0.045);
  });
}
function click(start: number, gain: number, pan = 0.4) {
  filteredNoise(start, 0.03, gain, pan, 0.05, () => 3500, (t) => envelope(t, 0.0003, 0.004), true);
  voice(start, 0.04, gain * 0.6, pan, 0.05, (t) => Math.sin(TAU * 2600 * t) * envelope(t, 0.0005, 0.008));
}
const tick = (start: number, gain: number, pan = 0.4) => voice(start, 0.03, gain, pan, 0.2, (t) => Math.sin(TAU * 5200 * t) * envelope(t, 0.0005, 0.006));
function whoosh(start: number, seconds: number, gain: number) {
  filteredNoise(
    start,
    seconds,
    gain,
    0,
    0.3,
    (t) => 250 + 2200 * Math.sin((Math.PI * t) / seconds) ** 2,
    (t) => Math.sin((Math.PI * t) / seconds) ** 2,
  );
}
function swell(end: number, seconds: number, gain: number) {
  filteredNoise(end - seconds, seconds, gain, 0, 0.4, (t) => 300 + 5000 * (t / seconds) ** 2, (t) => (t / seconds) ** 3);
}

pad(["D3", "A3", "F#4"], 0, at(8), 0.05);
pad(["B2", "F#3", "D4"], at(8), at(8), 0.05);
bell("A5", 0.2, 0.08);

const pattern = "x.x.X.xx";
const melody = ["F#5", "A4", "D5", "A4"];
let hit = 0;
for (let step = 0; step < 64; step++) {
  const mark = pattern[step % 8];
  if (mark === ".") continue;
  mallet(melody[hit++ % melody.length], at(8 + step / 2), mark === "X" ? 0.075 : 0.055);
}

const bars: [number, string[], string][] = [
  [16, ["D3", "F#3", "A3", "D4"], "D2"],
  [20, ["B2", "D3", "F#3", "B3"], "B1"],
  [24, ["G2", "B2", "D3", "G3"], "G1"],
  [28, ["A2", "C#3", "E3", "A3"], "A1"],
  [32, ["D3", "F#3", "A3", "D4"], "D2"],
  [36, ["A2", "C#3", "E3", "G3"], "A1"],
];
for (const [bar, chord, root] of bars) {
  keys(chord, at(bar), at(4), 0.04);
  pad(chord.slice(1), at(bar), at(4), 0.022);
  bass(root, at(bar), at(1.5), 0.11);
  bass(root, at(bar + 2.5), at(1), 0.08);
}
for (let b = 16; b < 40; b++) {
  if (b % 2 === 0) kick(at(b), 0.22);
  else sidestick(at(b), 0.09);
  hat(at(b), 0.03);
  hat(at(b + 0.5), 0.045);
  if (b >= 32) {
    shaker(at(b + 0.25), 0.03);
    shaker(at(b + 0.75), 0.03);
  }
}

pop(beats.panelArrives + 0.1, 0.16);
[0, 1, 2].forEach((i) => tick(beats.panelArrives + 0.18 + i * 0.07, 0.05));
whoosh(beats.zoomToScreen - 0.1, 1.2, 0.14);
whoosh(4.35, 1.5, 0.1);
pop(6.0, 0.1, 0.5);
pop(6.35, 0.1, 0.5);
bell("E6", beats.flakyDone, 0.1, 0.4);
bell("A6", beats.flakyDone + 0.09, 0.06, 0.4);
whoosh(9.85, 1.1, 0.08);
pop(beats.hoverExpand, 0.16);
[0, 1, 2, 3].forEach((i) => tick(beats.hoverExpand + 0.08 + i * 0.05, 0.035));
click(beats.serversClick, 0.22);
[0, 1, 2].forEach((i) => tick(beats.serversClick + 0.1 + i * 0.04, 0.035));
click(beats.agentsClick, 0.22);
pop(beats.remotesJoin, 0.12);
[0, 1].forEach((i) => tick(beats.remotesJoin + 0.1 + i * 0.07, 0.045));
whoosh(19.6, 0.8, 0.07);
bell("A5", beats.edgeAsks, 0.11, 0.45);
bell("D6", beats.edgeAsks + 0.16, 0.1, 0.45);
pop(beats.questionOpens, 0.16);
click(beats.answerClick, 0.24);
whoosh(beats.answerClick + 0.1, 1.4, 0.12);
tick(beats.edgeResumes, 0.04);

swell(scenes.end, 1.3, 0.16);
["D5", "E5", "F#5", "A5", "B5", "D6"].forEach((note, i) => mallet(note, scenes.end - 0.62 + i * 0.1, 0.05 + i * 0.006, -0.2 + i * 0.08));
keys(["D3", "F#3", "A3", "D4", "F#4"], scenes.end, 4, 0.06);
pad(["D3", "A3", "D4", "F#4"], scenes.end, 4.2, 0.03);
bass("D2", scenes.end, 4, 0.14);
kick(scenes.end, 0.3);
crash(scenes.end, 0.07);
bell("F#5", scenes.end + 0.05, 0.08);

function reverb(input: Float32Array, offset: number) {
  const out = new Float32Array(length);
  const combs = [1557, 1617, 1491, 1422].map((d) => ({ buffer: new Float32Array(d + offset), index: 0, low: 0 }));
  for (let i = 0; i < length; i++) {
    let sum = 0;
    for (const comb of combs) {
      const y = comb.buffer[comb.index];
      comb.low = y * 0.7 + comb.low * 0.3;
      comb.buffer[comb.index] = input[i] + comb.low * 0.84;
      comb.index = (comb.index + 1) % comb.buffer.length;
      sum += y;
    }
    out[i] = sum / 4;
  }
  for (const d of [225, 556]) {
    const buffer = new Float32Array(d + offset), state = { index: 0 };
    for (let i = 0; i < length; i++) {
      const delayed = buffer[state.index];
      const y = -out[i] + delayed;
      buffer[state.index] = out[i] + delayed * 0.5;
      state.index = (state.index + 1) % d;
      out[i] = y;
    }
  }
  return out;
}

const tails = [reverb(wet[0], 0), reverb(wet[1], 23)];
const mix = [new Float32Array(length), new Float32Array(length)];
let peak = 0;
for (let c = 0; c < 2; c++) {
  for (let i = 0; i < length; i++) {
    const t = i / rate;
    const fade = Math.min(1, t / 0.05) * Math.min(1, (duration - t) / 1.4);
    mix[c][i] = Math.tanh((dry[c][i] + tails[c][i] * 0.5) * 1.4) * fade;
    peak = Math.max(peak, Math.abs(mix[c][i]));
  }
}

const scale = 0.89 / peak;
const data = Buffer.alloc(length * 4);
for (let i = 0; i < length; i++) {
  data.writeInt16LE(Math.round(mix[0][i] * scale * 32767), i * 4);
  data.writeInt16LE(Math.round(mix[1][i] * scale * 32767), i * 4 + 2);
}
const header = Buffer.alloc(44);
header.write("RIFF", 0);
header.writeUInt32LE(36 + data.length, 4);
header.write("WAVEfmt ", 8);
header.writeUInt32LE(16, 16);
header.writeUInt16LE(1, 20);
header.writeUInt16LE(2, 22);
header.writeUInt32LE(rate, 24);
header.writeUInt32LE(rate * 4, 28);
header.writeUInt16LE(4, 32);
header.writeUInt16LE(16, 34);
header.write("data", 36);
header.writeUInt32LE(data.length, 40);
writeFileSync(new URL("../public/score.wav", import.meta.url), Buffer.concat([header, data]));
