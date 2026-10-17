import { useLayoutEffect, useRef } from "react";
import { orbDrawer, type OrbLook } from "../../../apps/web/lib/orb-core";

export function Orb({ look, size, color, time }: { look: OrbLook; size: number; color: string; time: number | null }) {
  const svg = useRef<SVGSVGElement>(null);
  const draw = useRef<(t: number) => void>(() => {});

  useLayoutEffect(() => {
    svg.current!.replaceChildren();
    draw.current = orbDrawer(svg.current!, { ...look, size }).draw;
  }, [look.state, look.variant, size]);

  useLayoutEffect(() => {
    draw.current((time ?? 0) * 1000);
  });

  return <svg ref={svg} width={size} height={size} style={{ color, display: "block", overflow: "visible" }} />;
}
