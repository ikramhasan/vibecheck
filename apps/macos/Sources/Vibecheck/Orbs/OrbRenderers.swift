import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

enum OrbRenderer: String {
    case ticker, sprite, layer, swiftUI, apng, still
}

@MainActor
final class OrbRendering {
    static let shared = OrbRendering()

    let renderer: OrbRenderer
    let tickerFPS: Double

    private init() {
        let defaults = UserDefaults.standard
        renderer = defaults.string(forKey: "orbs.renderer").flatMap(OrbRenderer.init(rawValue:)) ?? .ticker
        let fps = defaults.double(forKey: "orbs.tickerFPS")
        tickerFPS = fps > 0 ? fps : 60
    }
}

struct OrbTimelineCanvas: View {
    let style: OrbStyle
    @State private var holder = OrbModelHolder()

    var body: some View {
        let model = holder.model(look: style.look, size: style.size)
        let still = style.still
        let floor = style.floor
        let ink = style.ink
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: still || !style.playing)) { context in
            let t = still ? 0 : context.date.timeIntervalSince(OrbClock.epoch) * 1000
            Canvas { ctx, _ in
                model.draw(t: t) { _, x, y, r, a in
                    guard a > 0 else { return }
                    ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)),
                             with: .color(ink.opacity(floor + (1 - floor) * a)))
                }
            }
        }
    }
}

@MainActor
private final class OrbModelHolder {
    private var current: OrbModel?

    func model(look: OrbLook, size: Double) -> OrbModel {
        if let current, current.look == look, current.size == size { return current }
        let made = OrbModel(look: look, size: size)
        current = made
        return made
    }
}

struct OrbLayerCanvas: NSViewRepresentable {
    let style: OrbStyle

    func makeNSView(context: Context) -> OrbLayerView { OrbLayerView() }

    func updateNSView(_ view: OrbLayerView, context: Context) { view.show(style) }
}

class OrbHostView: NSView {
    private(set) var style: OrbStyle?
    private(set) var ink = CGColor(gray: 0, alpha: 0)

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    var scale: Double { Double(window?.backingScaleFactor ?? 2) }

    var running: Bool {
        guard let style else { return false }
        return window != nil && style.playing && !style.still
    }

    func show(_ style: OrbStyle) {
        let previous = self.style
        self.style = style
        resolveInk()
        styleChanged(from: previous)
    }

    func styleChanged(from previous: OrbStyle?) {}

    func refresh() {}

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        resolveInk()
        refresh()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        refresh()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refresh()
    }

    private func resolveInk() {
        guard let style else { return }
        effectiveAppearance.performAsCurrentDrawingAppearance { ink = NSColor(style.ink).cgColor }
    }
}

final class OrbLayerView: OrbHostView {
    private let orb = OrbDrawingLayer()
    private var displayLink: CADisplayLink?

    override init(frame: NSRect) {
        super.init(frame: frame)
        layer?.addSublayer(orb)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        orb.frame = bounds
    }

    override func styleChanged(from previous: OrbStyle?) { refresh() }

    override func refresh() {
        guard let style else { return }
        if orb.model?.look != style.look || orb.model?.size != style.size {
            orb.model = OrbModel(look: style.look, size: style.size)
        }
        orb.ink = ink
        orb.floor = style.floor
        orb.still = style.still
        orb.contentsScale = scale
        orb.setNeedsDisplay()
        if running, displayLink == nil {
            let link = displayLink(target: self, selector: #selector(nextFrame))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
            link.add(to: .main, forMode: .common)
            displayLink = link
        } else if !running, let link = displayLink {
            link.invalidate()
            displayLink = nil
        }
    }

    @objc private func nextFrame() {
        orb.setNeedsDisplay()
    }
}

private final class OrbDrawingLayer: CALayer {
    var model: OrbModel?
    var ink = CGColor(gray: 0, alpha: 0)
    var floor = 0.0
    var still = true

    override init() {
        super.init()
        isGeometryFlipped = true
        needsDisplayOnBoundsChange = true
    }

    override init(layer: Any) { super.init(layer: layer) }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func action(forKey event: String) -> (any CAAction)? { nil }

    override func draw(in context: CGContext) {
        guard let model else { return }
        let t = still ? 0 : Date.now.timeIntervalSince(OrbClock.epoch) * 1000
        model.draw(t: t) { _, x, y, r, a in
            guard a > 0 else { return }
            context.setFillColor(ink.copy(alpha: floor + (1 - floor) * a) ?? ink)
            context.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
        }
    }
}

struct OrbDot {
    var x, y, r, a: Double
}

struct OrbFrames {
    let count: Int
    let frameSeconds: Double

    static func frameCount(_ look: OrbLook, fps: Double = 60) -> Int {
        look.loop == 0 ? 1 : Int((look.loop / 1000 * fps).rounded())
    }

    @discardableResult
    static func render(look: OrbLook, size: Double, fps: Double = 60, firstOnly: Bool = false,
                       each: (Int, [OrbDot]) -> Void) -> OrbFrames {
        let model = OrbModel(look: look, size: size)
        let count = frameCount(look, fps: fps)
        let frameMs = look.loop / Double(count)
        func dots(at t: Double) -> [OrbDot] {
            var out: [OrbDot] = []
            model.draw(t: look.loop + t) { _, x, y, r, a in out.append(OrbDot(x: x, y: y, r: r, a: a)) }
            return out
        }
        let leadCount = look.walkers > 0 ? Int(500 / frameMs) : 0
        let lead = (0..<leadCount).map { dots(at: Double($0) * frameMs) }
        for i in 0..<(firstOnly ? 1 : count) {
            var current = dots(at: Double(leadCount + i) * frameMs)
            let k = leadCount + i - count
            if k >= 0 {
                let s = Double(k) / Double(leadCount)
                for j in current.indices {
                    current[j].r += (lead[k][j].r - current[j].r) * s
                    current[j].a += (lead[k][j].a - current[j].a) * s
                }
            }
            each(i, current)
        }
        return OrbFrames(count: count, frameSeconds: frameMs / 1000)
    }
}

final class OrbSprite: @unchecked Sendable {
    let sheet: CGImage
    let rects: [CGRect]
    let duration: Double

    init(sheet: CGImage, rects: [CGRect], duration: Double) {
        self.sheet = sheet
        self.rects = rects
        self.duration = duration
    }
}

@MainActor
enum OrbSprites {
    private struct Key: Hashable, Sendable {
        let look: OrbLook
        let size: Double
        let floor: Double
        let scale: Double
        let ink: [CGFloat]
        let fps: Double
        let still: Bool
    }

    private struct Cached {
        weak var sprite: OrbSprite?
    }

    private static var cache: [Key: Cached] = [:]
    private static var building: [Key: [() -> Void]] = [:]

    static func sprite(look: OrbLook, size: Double, floor: Double, scale: Double, ink: CGColor, fps: Double = 60,
                       still: Bool = false) -> OrbSprite? {
        guard let key = key(look: look, size: size, floor: floor, scale: scale, ink: ink, fps: fps, still: still) else { return nil }
        if let cached = cache[key]?.sprite { return cached }
        guard let sprite = make(key) else { return nil }
        store(sprite, for: key)
        return sprite
    }

    private static func store(_ sprite: OrbSprite, for key: Key) {
        cache = cache.filter { $0.value.sprite != nil }
        cache[key] = Cached(sprite: sprite)
    }

    static func cachedSprite(look: OrbLook, size: Double, floor: Double, scale: Double, ink: CGColor, fps: Double,
                             whenBuilt: @escaping () -> Void) -> OrbSprite? {
        guard let key = key(look: look, size: size, floor: floor, scale: scale, ink: ink, fps: fps, still: false) else { return nil }
        if let cached = cache[key]?.sprite { return cached }
        if building[key] != nil {
            building[key]?.append(whenBuilt)
            return nil
        }
        building[key] = [whenBuilt]
        Task.detached(priority: .userInitiated) {
            let sprite = make(key)
            await MainActor.run {
                if let sprite { store(sprite, for: key) }
                building.removeValue(forKey: key)?.forEach { $0() }
            }
        }
        return nil
    }

    private static func key(look: OrbLook, size: Double, floor: Double, scale: Double, ink: CGColor, fps: Double,
                            still: Bool) -> Key? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ink = ink.converted(to: space, intent: .defaultIntent, options: nil) else { return nil }
        return Key(look: look, size: size, floor: floor, scale: scale, ink: ink.components ?? [], fps: fps, still: still)
    }

    nonisolated private static func make(_ key: Key) -> OrbSprite? {
        let (look, size, floor, scale, fps, still) = (key.look, key.size, key.floor, key.scale, key.fps, key.still)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ink = CGColor(colorSpace: space, components: key.ink) else { return nil }
        let count = still ? 1 : OrbFrames.frameCount(look, fps: fps)
        let cell = Int((size * scale).rounded(.up))
        let columns = Int(Double(count).squareRoot().rounded(.up))
        let rows = (count + columns - 1) / columns
        let width = columns * cell, height = rows * cell
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        var rects: [CGRect] = []
        let frames = OrbFrames.render(look: look, size: size, fps: fps, firstOnly: still) { i, dots in
            let column = i % columns, row = i / columns
            let left = Double(column * cell), top = Double(height - row * cell)
            for dot in dots where dot.a > 0 {
                let r = dot.r * scale
                context.setFillColor(ink.copy(alpha: floor + (1 - floor) * dot.a) ?? ink)
                context.fillEllipse(in: CGRect(x: left + dot.x * scale - r, y: top - dot.y * scale - r, width: 2 * r, height: 2 * r))
            }
            rects.append(CGRect(x: Double(column * cell) / Double(width), y: Double(height - (row + 1) * cell) / Double(height),
                                width: Double(cell) / Double(width), height: Double(cell) / Double(height)))
        }
        guard let sheet = context.makeImage() else { return nil }
        return OrbSprite(sheet: sheet, rects: rects, duration: Double(frames.count) * frames.frameSeconds)
    }
}

struct OrbSpriteCanvas: NSViewRepresentable {
    let style: OrbStyle

    func makeNSView(context: Context) -> OrbSpriteView { OrbSpriteView() }

    func updateNSView(_ view: OrbSpriteView, context: Context) { view.show(style) }
}

final class OrbSpriteView: OrbHostView {
    private let frames = CALayer()
    private var shown: (sprite: OrbSprite, animating: Bool)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        frames.contentsGravity = .resize
        layer?.addSublayer(frames)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        frames.frame = bounds
        CATransaction.commit()
    }

    override func styleChanged(from previous: OrbStyle?) { refresh() }

    override func refresh() {
        guard let style, let sprite = OrbSprites.sprite(look: style.look, size: style.size,
                                                         floor: style.floor, scale: scale, ink: ink) else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let animating = running && sprite.rects.count > 1
        if shown?.sprite !== sprite || shown?.animating != animating {
            frames.removeAnimation(forKey: "frames")
            frames.contents = sprite.sheet
            frames.contentsScale = scale
            frames.contentsRect = sprite.rects[0]
            if animating {
                let animation = CAKeyframeAnimation(keyPath: "contentsRect")
                animation.values = sprite.rects.map { NSValue(rect: $0) }
                animation.calculationMode = .discrete
                animation.duration = sprite.duration
                animation.repeatCount = .infinity
                animation.isRemovedOnCompletion = false
                let elapsed = Date.now.timeIntervalSince(OrbClock.epoch)
                animation.timeOffset = elapsed.truncatingRemainder(dividingBy: sprite.duration)
                animation.beginTime = frames.convertTime(CACurrentMediaTime(), from: nil)
                frames.add(animation, forKey: "frames")
            }
            shown = (sprite, animating)
        }
        CATransaction.commit()
    }
}

@MainActor
enum OrbAPNGs {
    private struct Key: Hashable {
        let look: OrbLook
        let size: Double
        let floor: Double
        let scale: Double
        let ink: [CGFloat]
    }

    private static var cache: [Key: Data] = [:]

    static func data(look: OrbLook, size: Double, floor: Double, scale: Double, ink: CGColor) -> Data? {
        let key = Key(look: look, size: size, floor: floor, scale: scale, ink: ink.components ?? [])
        if let cached = cache[key] { return cached }
        let cell = Int((size * scale).rounded(.up))
        let count = OrbFrames.frameCount(look)
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, count, nil),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        CGImageDestinationSetProperties(destination, [kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGLoopCount: 0]] as CFDictionary)
        let frameSeconds = look.loop / Double(count) / 1000
        let delay = [kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGDelayTime: frameSeconds,
                                                     kCGImagePropertyAPNGUnclampedDelayTime: frameSeconds]] as CFDictionary
        OrbFrames.render(look: look, size: size) { _, dots in
            guard let context = CGContext(data: nil, width: cell, height: cell, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            for dot in dots where dot.a > 0 {
                let r = dot.r * scale
                context.setFillColor(ink.copy(alpha: floor + (1 - floor) * dot.a) ?? ink)
                context.fillEllipse(in: CGRect(x: dot.x * scale - r, y: Double(cell) - dot.y * scale - r, width: 2 * r, height: 2 * r))
            }
            if let image = context.makeImage() {
                CGImageDestinationAddImage(destination, image, delay)
            }
        }
        guard CGImageDestinationFinalize(destination) else { return nil }
        cache[key] = data as Data
        return data as Data
    }
}

struct OrbAPNGCanvas: NSViewRepresentable {
    let style: OrbStyle

    func makeNSView(context: Context) -> OrbAPNGView { OrbAPNGView() }

    func updateNSView(_ view: OrbAPNGView, context: Context) { view.show(style) }
}

final class OrbAPNGView: OrbHostView {
    private let frames = CALayer()
    private var playback: (data: Data, token: PlaybackToken)?

    final class PlaybackToken {
        var stopped = false
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        frames.contentsGravity = .resize
        frames.actions = ["contents": NSNull()]
        layer?.addSublayer(frames)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        frames.frame = bounds
    }

    override func styleChanged(from previous: OrbStyle?) { refresh() }

    override func refresh() {
        guard let style, let data = OrbAPNGs.data(look: style.look, size: style.size, floor: style.floor,
                                                  scale: scale, ink: ink) else { return }
        frames.contentsScale = scale
        let animating = running && OrbFrames.frameCount(style.look) > 1
        if playback?.data == data, animating, playback?.token.stopped == false { return }
        playback?.token.stopped = true
        playback = nil
        guard animating else {
            if let source = CGImageSourceCreateWithData(data as CFData, nil) {
                frames.contents = CGImageSourceCreateImageAtIndex(source, 0, nil)
            }
            return
        }
        let token = PlaybackToken()
        playback = (data, token)
        CGAnimateImageDataWithBlock(data as CFData, nil) { [weak self] _, image, stop in
            guard let self, !token.stopped else {
                stop.pointee = true
                return
            }
            self.frames.contents = image
        }
    }
}

struct OrbTickerCanvas: NSViewRepresentable {
    let style: OrbStyle
    let fps: Double

    func makeNSView(context: Context) -> OrbTickerView { OrbTickerView() }

    func updateNSView(_ view: OrbTickerView, context: Context) {
        view.fps = fps
        view.show(style)
    }
}

final class OrbTickerView: OrbHostView {
    private let frames = CALayer()
    var fps = 60.0
    private var sprite: OrbSprite?
    private var shownFrame = -1

    override init(frame: NSRect) {
        super.init(frame: frame)
        frames.contentsGravity = .resize
        frames.actions = ["contents": NSNull(), "contentsRect": NSNull(), "bounds": NSNull(), "position": NSNull()]
        layer?.addSublayer(frames)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        frames.frame = bounds
    }

    override func styleChanged(from previous: OrbStyle?) { refresh() }

    override func refresh() {
        guard let style, window != nil else { return }
        let animated = running ? OrbSprites.cachedSprite(look: style.look, size: style.size, floor: style.floor, scale: scale,
                                                         ink: ink, fps: fps) { [weak self] in self?.refresh() } : nil
        sprite = animated ?? OrbSprites.sprite(look: style.look, size: style.size, floor: style.floor, scale: scale, ink: ink,
                                               fps: fps, still: true)
        guard let sprite else { return }
        frames.contents = sprite.sheet
        frames.contentsScale = scale
        shownFrame = -1
        advance(to: Date.now.timeIntervalSince(OrbClock.epoch))
        if running, sprite.rects.count > 1 { OrbTicker.shared.add(self) } else { OrbTicker.shared.remove(self) }
    }

    func advance(to elapsed: Double) {
        guard let sprite else { return }
        let next = running ? Int(elapsed / (sprite.duration / Double(sprite.rects.count))) % sprite.rects.count : 0
        guard next != shownFrame else { return }
        shownFrame = next
        frames.contentsRect = sprite.rects[next]
    }
}

@MainActor
final class OrbTicker {
    static let shared = OrbTicker()

    private var views: [ObjectIdentifier: WeakView] = [:]
    private var timer: Timer?
    private var fps = 0.0

    private struct WeakView {
        weak var view: OrbTickerView?
    }

    func add(_ view: OrbTickerView) {
        views[ObjectIdentifier(view)] = WeakView(view: view)
        schedule()
    }

    func remove(_ view: OrbTickerView) {
        views[ObjectIdentifier(view)] = nil
        schedule()
    }

    private func schedule() {
        let wanted = views.isEmpty ? 0 : OrbRendering.shared.tickerFPS
        guard wanted != fps else { return }
        fps = wanted
        timer?.invalidate()
        timer = nil
        guard wanted > 0 else { return }
        let timer = Timer(timeInterval: 1 / wanted, repeats: true) { _ in
            MainActor.assumeIsolated { OrbTicker.shared.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        let elapsed = Date.now.timeIntervalSince(OrbClock.epoch)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (id, entry) in views {
            if let view = entry.view { view.advance(to: elapsed) } else { views[id] = nil }
        }
        CATransaction.commit()
        if views.isEmpty { schedule() }
    }
}
