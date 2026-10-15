# Orb rendering: options and measurements

The status orbs are the only thing in vibecheck that animates continuously, so they decide
most of its idle cost. This file records every way we tried to draw them, what each one
costs, and how to switch between them. All of them are still in
`apps/macos/Sources/Vibecheck/Orbs/OrbRenderers.swift`.

**Shipping choice: Ticker at 60 fps.**

## Switching

The renderer and the Ticker frame rate are read once at launch from the app's preferences.
There is no UI for them.

```bash
# Release build (bundle id com.ikramulhasan.vibecheck)
defaults write com.ikramulhasan.vibecheck orbs.renderer sprite      # ticker | sprite | layer | swiftUI | apng | still
defaults write com.ikramulhasan.vibecheck orbs.tickerFPS -float 30   # Ticker only, default 60
defaults delete com.ikramulhasan.vibecheck orbs.renderer             # back to the default

# Debug build from run-debug.sh (domain "Vibecheck"), or for one launch:
.build/out/Products/Release/Vibecheck -orbs.renderer sprite -orbs.tickerFPS 30
```

To change the default for everyone, edit `OrbRendering.init()`.

## Results

6 working orbs (Random styles), panel collapsed, Release build, 3 interleaved rounds of
20 s each with a no-vibecheck control between them.

| Renderer | vibecheck CPU | WindowServer, above baseline | Memory (footprint) |
|---|---|---|---|
| SwiftUI (v0.4.0) | 26% | +31% | ~98 MB |
| Layer (PR #17) | 30% | +27% | ~92 MB |
| Sprite sheet | 1.1% | **+50%** | ~91 MB |
| APNG | 5.6% | +20% | ~200 MB |
| Ticker @ 10 fps | 1.8% | +9% | ~90 MB |
| Ticker @ 15 fps | 1.9% | +12% | ~90 MB |
| Ticker @ 20 fps | 2.0% | +16% | ~90 MB |
| Ticker @ 30 fps | 2.1% | +20% | ~90 MB |
| Ticker @ 60 fps | 8–14% (busy machine) | about the same as Layer | ~95 MB |
| Still (no animation) | 1.8% | +3% | ~88 MB |

WindowServer's baseline with vibecheck closed was 14.7% on the test machine (1920×1080
display). Ticker @ 60 fps was measured later on a busy machine, in the same run as Layer:
Layer 30–35% app, Ticker @ 60 fps 8–14% app, WindowServer equal or lower for Ticker. Its
app cost is several times Ticker @ 30 fps, so 30 fps is the next step if 60 is too much.

Activity Monitor shows only the vibecheck column. Compositing cost is charged to
WindowServer, so always compare both.

## The finding that matters

**Any running Core Animation animation makes WindowServer composite at the display's full
refresh rate, whatever the animation's own frame count.** A standalone app with a single
16 pt dot animating opacity in a 40×40 window cost WindowServer about +33%, and asking for
10 fps (discrete keyframes plus `preferredFrameRateRange`) changed nothing.

When the app pushes discrete updates itself instead (a timer setting a layer property
inside a `CATransaction`), WindowServer's cost follows the update rate, about +1% per
update per second:

| Probe (one 16 pt dot) | WindowServer |
|---|---|
| Nothing running | 19–21% |
| Static window | 20–22% |
| `CAKeyframeAnimation`, any frame count, with or without a 10 fps hint | 55–57% |
| Timer @ 60 fps | 48–52% |
| Timer @ 30 fps | 42–46% |
| Timer @ 15 fps | 35–36% |
| Timer @ 10 fps | 28–33% |

Window size, transparency and Liquid Glass made no measurable difference.

That's why the sprite sheet looks best in Activity Monitor and is the worst in total, and
why Ticker is the only renderer whose total cost can be tuned.

## The renderers

All renderers draw the same model (`OrbModel` in `Orb.swift`, ported from thinking-orbs)
and share `OrbHostView`. It ignores clicks, resolves the tint for the current appearance,
and runs only while the orb is on screen (the `orbsOnScreen` environment value) and
animated.

### Ticker (`ticker`, shipping)

Every frame of a style's loop is drawn once, tinted, into one RGBA sprite sheet
(`OrbSprites`). Each orb is a layer showing one cell of the sheet. One shared main-thread
timer (`OrbTicker`) moves every visible orb to its current frame in a single
`CATransaction`, and only touches orbs whose frame changed.

- Pros: lowest total cost; WindowServer cost follows the frame rate; extra orbs cost
  almost nothing because they update together; the timer stops when no orb is on screen.
- Cons: animations must loop (see Looping); below about 20 fps the motion looks steppy;
  sheets use memory, more at higher frame rates.
- Details: orbs that aren't playing get a one-frame sheet. The full sheet is built on a
  background thread the first time a style plays, and the orb shows its first frame until
  the sheet is ready, so opening the panel never waits on drawing.

### Sprite sheet (`sprite`)

The same sheets, stepped by a `CAKeyframeAnimation` on `contentsRect`
(`calculationMode = .discrete`, repeating) in the render server.

- Pros: almost no app CPU, whatever the number of orbs; smooth 60 fps.
- Cons: the full-rate WindowServer cost described above (+50%); sheets must loop.
- Notes: `contentsRect` has its origin at the bottom left. An earlier version used an
  alpha-only sheet as a mask over a tinted layer; the mask added an offscreen pass, and
  baking the tint into an RGBA sheet removed it.

### Layer (`layer`, what PR #17 ships)

Each orb is a `CALayer` that redraws itself with Core Graphics on a `CADisplayLink` capped
at 60 fps.

- Pros: exact animation, no loop constraints, no sheet memory.
- Cons: app CPU grows with every animating orb; the app wakes 60 times a second;
  WindowServer composites at the full rate.

### SwiftUI (`swiftUI`, what v0.4.0 ships)

A `TimelineView(.animation)` redraws a `Canvas` 60 times a second.

- Pros: least code; exact animation.
- Cons: every frame re-renders and lays out the whole panel's hosting view, so it has the
  highest app CPU; WindowServer composites at the full rate.

### APNG (`apng`)

Every frame is encoded once into an animated PNG (`CGImageDestination`) and played with
`CGAnimateImageDataWithBlock`.

- Pros: a standard file format that could be prebuilt or exported.
- Cons: decodes a PNG frame per orb per tick, so CPU grows with orbs; slow to build; each
  orb plays out of phase; the most memory.

### Still (`still`)

Every orb shows its first frame and never moves. Not an option, just the reference for
what the rest of the app costs.

## Looping

The sheet-based renderers (Ticker, Sprite sheet, APNG) need every style to loop, so a
few timings in `Orb.swift` were adjusted, and `OrbLook.loop` gives each style's loop
length:

| Style | Loop |
|---|---|
| base | still |
| working | 3.4 s |
| gyro | 6 s |
| reasoning, twins | 6.5 s |
| waiting | 12 s |
| searching, lighthouse, background, spiral | 13 s |
| retrying | 16 s |

Reasoning and twins use random-walking dots that can't loop exactly; their last 0.5 s
blends each dot back into its start. Frames are rendered starting at `t = loop` to avoid
negative remainders near zero.

## Other costs found on the way

- **Remote project names touched the disk.** `SessionGroup.make` built a `URL` from a
  remote path, which made macOS `lstat` it locally; paths like `/home/...` go through the
  automounter. It cost about 55 ms per panel render. Fixed by using
  `NSString.lastPathComponent`; same fix in `ServerList`.
- **Hidden pages.** The expanded and Settings pages stay mounted at opacity 0 so their
  items can cascade, and they cost a few percent of app CPU while collapsed. Unmounting them
  saved that, but rebuilding them took 0.5–1.7 s on every open, so we kept them mounted.
- **`forgetResumed` rewrote panel state** on every session update. It's now assigned only
  when it changes.
- **Status directory rescans** decode every status file once a second (~0.6% CPU with
  6 files). Not changed.

## Reproducing the measurements

Fake sessions: write status files whose `pid` is a long-running `sleep`, and point the app
at them with `VIBECHECK_DIR`.

```bash
#!/usr/bin/env bash
# fake.sh N: N working sessions in /tmp/vcbench/status (fake.sh 0 removes them)
rm -rf /tmp/vcbench/status/sessions; mkdir -p /tmp/vcbench/status/sessions
pkill -f 'sleep 9999' 2>/dev/null
[ "$1" -gt 0 ] || exit 0
sleep 9999 & S=$!
now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
for i in $(seq 1 $1); do
cat > /tmp/vcbench/status/sessions/fake--s$i.json <<J
{"schemaVersion":1,"agent":{"id":"fake","name":"Fake"},"session":{"id":"s$i","cwd":"/tmp/vcbench/p$i","name":"bench $i"},"pid":$S,"status":"working","updatedAt":"$now","startedAt":"$now"}
J
done
```

Interleaved app and WindowServer CPU. Arguments are `renderer[@fps]` or `none`. Keep the
display awake and the machine otherwise idle: WindowServer numbers are only meaningful
against a `none` run taken at the same time.

```bash
#!/usr/bin/env bash
B=apps/macos/.build/out/Products/Release/Vibecheck
WS=$(pgrep -x WindowServer)
cpu() { ps -o time= -p $1 | awk -F'[:.]' '{ if (NF==4) print ($1*3600+$2*60+$3)+("0."$4); else print ($1*60+$2)+("0."$3)}'; }
for round in $(seq ${ROUNDS:-3}); do
for c in "$@"; do
  r=${c%@*}; fps=${c#*@}; [ "$fps" = "$c" ] && fps=60
  if [ "$r" != none ]; then VIBECHECK_DIR=/tmp/vcbench/status $B -orbs.renderer $r -orbs.tickerFPS $fps >/dev/null 2>&1 & P=$!; fi
  sleep 8; w=$(cpu $WS); a=$([ "$r" != none ] && cpu $P || echo 0)
  sleep 12; x=$(cpu $WS); b=$([ "$r" != none ] && cpu $P || echo 0)
  [ "$r" != none ] && { kill $P; wait $P 2>/dev/null; }
  printf "%-14s app %5.1f%%  WS %5.1f%%\n" "$c" "$(echo "($b-$a)*100/12" | bc -l)" "$(echo "($x-$w)*100/12" | bc -l)"
done; done
```

Example: `ROUNDS=3 ./ws.sh none still ticker@60 ticker@15 sprite layer swiftUI apng`.
Memory: `footprint <pid>`. The app can't read WindowServer's CPU itself (libproc denies
it), so these numbers come from `ps`.

The standalone probe (build with `swiftc -O probe.swift -o probe`, run as
`probe small`, `probe "small fps=10 hint"`, `probe "timer fps=15"`, `probe "tall clear"`,
`probe static`):

```swift
import AppKit
let args = CommandLine.arguments
let tall = args.contains("tall"), clear = args.contains("clear")
let animate = !args.contains("static") && !args.contains("timer")
let fps = Float(args.first { $0.hasPrefix("fps=") }?.dropFirst(4) ?? "60") ?? 60
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let screen = NSScreen.main!.visibleFrame
let rect = tall ? NSRect(x: screen.maxX - 360, y: screen.minY, width: 360, height: screen.height)
                : NSRect(x: screen.maxX - 60, y: screen.midY, width: 40, height: 40)
let window = NSPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
window.level = .statusBar
window.isOpaque = !clear
window.backgroundColor = clear ? .clear : .windowBackgroundColor
let view = NSView(frame: NSRect(origin: .zero, size: rect.size))
view.wantsLayer = true
window.contentView = view
let dot = CALayer()
dot.frame = CGRect(x: rect.width - 30, y: rect.height / 2, width: 16, height: 16)
dot.backgroundColor = NSColor.systemBlue.cgColor
view.layer!.addSublayer(dot)
if animate {
    let a = CAKeyframeAnimation(keyPath: "opacity")
    a.values = (0..<Int(fps)).map { NSNumber(value: 0.3 + 0.7 * Double($0) / Double(fps)) }
    a.calculationMode = .discrete
    a.duration = 1
    a.repeatCount = .infinity
    if args.contains("hint") { a.preferredFrameRateRange = CAFrameRateRange(minimum: fps, maximum: fps, preferred: fps) }
    dot.add(a, forKey: "a")
}
if args.contains("timer") {
    var i = 0
    let t = Timer(timeInterval: 1 / Double(fps), repeats: true) { _ in
        i += 1
        CATransaction.begin(); CATransaction.setDisableActions(true)
        dot.opacity = Float(0.3 + 0.7 * Double(i % Int(fps)) / Double(fps))
        CATransaction.commit()
    }
    RunLoop.main.add(t, forMode: .common)
}
window.orderFrontRegardless()
app.run()
```

## Ring orbs

Settings → Loading indicator has a Ring tab. Choosing it (`settings.orbFamily = ring`) draws every
status as a solid core with a ring instead of a dot sphere: a spinning arc while working (slower
while blocked), a pulsing ring while waiting, a still ring otherwise. `RingOrb.swift` builds it from
a few `CAShapeLayer`s and moves them through the same `OrbTicker`, so it costs the same discrete
updates as Ticker and ignores `orbs.renderer`.

## Buddy orbs

The Buddy tab (`settings.orbFamily = buddy`) draws every status as a small face: a squircle head
with its eyes cut out. Working eyes read lines and glance up, waiting eyes go wide while the head
hops, your turn is ^ ^, blocked is asleep with a z drifting up, failed is × × with a tilt, and
interrupted is flat eyes on a faded head. When a session changes status, the eyes blink shut, the
face and colour swap while they're closed, and the new face opens; your turn bounces once and
failed wobbles once.

`BuddyOrb.swift` rebuilds one `CAShapeLayer` path per frame from an `Expression` (look, blink, hop,
squash, tilt, fade) on the shared `OrbTicker`. Your turn, failed and interrupted leave the ticker
once their entrance settles, so idle sessions cost nothing. Like Ring, it ignores `orbs.renderer`.

The eyes are cut out with an even-odd fill, not a path boolean op. The stroked eye shapes are built
and normalized once, so a frame only transforms and appends cached paths: about 2 µs per orb on an
M-series Mac, against about 21 µs when the eyes were subtracted from the head every frame.
