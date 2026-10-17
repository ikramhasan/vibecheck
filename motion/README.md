# vibecheck intro

The 30-second intro video, built with [Remotion](https://www.remotion.dev). Every frame is a
function of time, so renders are exact and repeatable.

```bash
npm --prefix motion install
npm --prefix motion run studio   # scrub and preview at localhost:3000
npm --prefix motion run render   # writes motion/out/vibecheck-intro.mp4 (1920×1080, 60 fps, with sound)
```

`render` renders at 4K and downsamples to 1080p, so text and edges move in half-pixel steps
instead of jumping a whole pixel at a time. The screen is also laid out at 4× detail
(`detail` in `Intro.tsx`) so the camera's zoom doesn't magnify layout rounding.

| File | What it is |
|---|---|
| `src/story.ts` | Scene start times, story beats and the sample sessions, servers, usage and question |
| `src/Intro.tsx` | The film: camera moves, captions, callouts and the end card |
| `src/Screen.tsx` | The desktop: wallpaper, windows, the panel's state over time, and the cursor |
| `src/components/Panel.tsx` | The edge tab shape and glass, with the app's metrics from `PanelMetrics` |
| `src/components/pages.tsx` | Collapsed badges, header tabs, session groups, usage, servers and the question card |
| `src/components/Orb.tsx` | The thinking orbs, drawn by `apps/web/lib/orb-core.ts` at each frame's time |
| `scripts/score.ts` | Synthesizes the music and sound effects into `public/score.wav`, timed from `story.ts` |
| `src/time.ts` | Easing and the SwiftUI-style springs (`response`, `dampingFraction`) the app animates with |

The panel follows the app: the same sizes, the same springs for opening, closing and page
changes, the same row cascade, and the default thinking orbs (a random working look per
session, waiting for questions, resting for "your turn").
