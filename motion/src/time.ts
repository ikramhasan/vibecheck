import { Easing } from "remotion";

export const clamp01 = (x: number) => Math.min(1, Math.max(0, x));
export const lerp = (a: number, b: number, p: number) => a + (b - a) * p;
export const seg = (t: number, from: number, to: number) => clamp01((t - from) / (to - from));

export const easeOut = Easing.bezier(0.22, 1, 0.36, 1);
export const easeInOut = Easing.bezier(0.65, 0, 0.35, 1);
export const easeIn = Easing.bezier(0.55, 0, 1, 0.45);

export type Spring = { response: number; damping: number };

export const springs = {
  open: { response: 0.46, damping: 0.62 },
  close: { response: 0.34, damping: 0.86 },
  rowsIn: { response: 0.5, damping: 0.7 },
  pageIn: { response: 0.3, damping: 0.86 },
  tab: { response: 0.32, damping: 0.86 },
  badge: { response: 0.4, damping: 0.7 },
  pop: { response: 0.55, damping: 0.55 },
} satisfies Record<string, Spring>;

export function spring(t: number, { response, damping }: Spring) {
  if (t <= 0) return 0;
  const w0 = (2 * Math.PI) / response;
  const wd = w0 * Math.sqrt(1 - damping * damping);
  const decay = Math.exp(-damping * w0 * t);
  return 1 - decay * (Math.cos(wd * t) + ((damping * w0) / wd) * Math.sin(wd * t));
}

export type Step = { at: number; to: number; spring: Spring };

export function settle(t: number, from: number, steps: Step[]) {
  let value = from;
  let target = from;
  for (const step of steps) {
    value += (step.to - target) * spring(t - step.at, step.spring);
    target = step.to;
  }
  return value;
}
