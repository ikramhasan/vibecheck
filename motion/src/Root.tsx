import { Composition } from "remotion";
import { Intro } from "./Intro";
import { duration } from "./story";
import { stage } from "./theme";

export function Root() {
  return (
    <Composition
      id="Intro"
      component={Intro}
      durationInFrames={Math.round(duration * stage.fps)}
      fps={stage.fps}
      width={stage.width}
      height={stage.height}
    />
  );
}
