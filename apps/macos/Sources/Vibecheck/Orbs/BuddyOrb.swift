import AppKit
import CompanionCore
import SwiftUI

enum BuddyFace: Equatable {
    case working, waiting, yourTurn, blocked, failed, interrupted

    init(_ session: AgentSession) {
        switch session.status {
        case .working: self = .working
        case .needsAttention: self = .waiting
        case .blocked: self = .blocked
        case .error: self = .failed
        case .idle: self = session.wasInterrupted ? .interrupted : .yourTurn
        }
    }

    fileprivate var isLively: Bool {
        switch self {
        case .working, .waiting, .blocked: true
        case .yourTurn, .failed, .interrupted: false
        }
    }

    fileprivate var stillTime: Double {
        switch self {
        case .working: 0.56
        case .waiting, .blocked: 1.2
        case .yourTurn, .failed, .interrupted: 0
        }
    }
}

struct BuddyOrbCanvas: NSViewRepresentable {
    let style: OrbStyle
    let face: BuddyFace

    func makeNSView(context: Context) -> BuddyOrbView { BuddyOrbView() }

    func updateNSView(_ view: BuddyOrbView, context: Context) { view.show(style, face: face) }
}

final class BuddyOrbView: OrbHostView, OrbTickable {
    private struct Change {
        let from: BuddyFace
        let ink: CGColor
        let at: Double
    }

    private static let blinkDuration = 0.32
    private static let settleDuration = 0.9
    private static let ground = 0.9
    private static let give = 0.7
    private static let eyeXs = [0.36, 0.64]
    private static let eyeY = 0.57
    private static let lookRange = CGSize(width: 0.065, height: 0.045)
    private static let headShape = CGPath(roundedRect: CGRect(x: 0.1, y: 0.22, width: 0.8, height: 0.68),
                                          cornerWidth: 0.28, cornerHeight: 0.28, transform: nil)
    private static let eyeShapes = Expression.Eyes.allCases.map(eyeShape)

    private let head = CAShapeLayer()
    private let zee = CAShapeLayer()
    private var face = BuddyFace.working
    private var enteredAt = -Double.infinity
    private var change: Change?

    override init(frame: NSRect) {
        super.init(frame: frame)
        head.fillRule = .evenOdd
        zee.fillColor = nil
        zee.lineCap = .round
        zee.lineJoin = .round
        for sublayer in [head, zee] { layer?.addSublayer(sublayer) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func show(_ style: OrbStyle, face: BuddyFace) {
        if face != self.face, self.style != nil {
            let now = Date.now.timeIntervalSince(OrbClock.epoch)
            change = running ? Change(from: self.face, ink: head.fillColor ?? ink, at: now) : nil
            enteredAt = running ? now : -.infinity
        }
        self.face = face
        show(style)
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        head.frame = bounds
        zee.frame = bounds
        advance(to: Date.now.timeIntervalSince(OrbClock.epoch))
        CATransaction.commit()
    }

    override func styleChanged(from previous: OrbStyle?) { refresh() }

    override func refresh() {
        guard style != nil else { return }
        let now = Date.now.timeIntervalSince(OrbClock.epoch)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        head.contentsScale = scale
        zee.contentsScale = scale
        advance(to: now)
        CATransaction.commit()
        if running, isMoving(at: now) { OrbTicker.shared.add(self) } else { OrbTicker.shared.remove(self) }
    }

    func advance(to elapsed: Double) {
        let time = running ? elapsed + (style?.offset ?? 0) : face.stillTime
        let since = running ? elapsed - enteredAt : .infinity
        var expression = Expression(face, time: time, since: since)
        var color = ink
        if let change {
            let progress = (elapsed - change.at) / Self.blinkDuration
            if running, progress < 1 {
                expression = .blend(Expression(change.from, time: time, since: .infinity), expression, progress)
                color = Self.mix(change.ink, ink, ease(progress))
            } else {
                self.change = nil
            }
        }
        draw(expression, color: color)
        if !isMoving(at: elapsed) { OrbTicker.shared.remove(self) }
    }

    private func isMoving(at elapsed: Double) -> Bool {
        face.isLively || elapsed - enteredAt < Self.settleDuration || change != nil
    }

    private func draw(_ expression: Expression, color: CGColor) {
        let side = min(bounds.width, bounds.height)
        guard side > 0 else { return }
        let unit = CGAffineTransform(a: side, b: 0, c: 0, d: -side, tx: bounds.midX - side / 2, ty: bounds.midY + side / 2)
        let pose = CGAffineTransform(translationX: -0.5, y: -Self.ground)
            .concatenating(CGAffineTransform(scaleX: 1 + (expression.stretchX - 1) * Self.give,
                                             y: 1 + (expression.stretchY - 1) * Self.give))
            .concatenating(CGAffineTransform(rotationAngle: expression.tilt))
            .concatenating(CGAffineTransform(translationX: 0.5, y: Self.ground + expression.hop))
            .concatenating(unit)

        let shape = CGMutablePath()
        shape.addPath(Self.headShape, transform: pose)
        for x in Self.eyeXs {
            let eye = CGAffineTransform(scaleX: 1, y: expression.blink)
                .concatenating(CGAffineTransform(translationX: x + expression.lookX * Self.lookRange.width,
                                                 y: Self.eyeY + expression.lookY * Self.lookRange.height))
                .concatenating(pose)
            shape.addPath(Self.eyeShapes[expression.eyes.rawValue], transform: eye)
        }
        head.path = shape
        head.fillColor = color
        head.opacity = Float(expression.opacity)

        zee.isHidden = expression.zee == nil
        guard let rise = expression.zee else { return }
        let half = (0.26 + 0.08 * rise) * 0.3
        let centre = CGPoint(x: 0.84 + 0.06 * rise, y: 0.17 - 0.1 * rise)
        let letter = CGMutablePath()
        letter.addLines(between: [CGPoint(x: centre.x - half, y: centre.y - half), CGPoint(x: centre.x + half, y: centre.y - half),
                                  CGPoint(x: centre.x - half, y: centre.y + half), CGPoint(x: centre.x + half, y: centre.y + half)],
                        transform: unit)
        zee.path = letter
        zee.lineWidth = 0.06 * side
        zee.strokeColor = color
        zee.opacity = Float(sin(.pi * min(1, rise * 1.3)))
    }

    nonisolated private static func eyeShape(_ eyes: Expression.Eyes) -> CGPath {
        let width = 0.13, height = 0.24
        switch eyes {
        case .open, .wide:
            let grow = eyes == .wide ? 1.24 : 1
            let w = width * grow, h = height * grow
            return CGPath(roundedRect: CGRect(x: -w / 2, y: -h / 2, width: w, height: h), cornerWidth: w / 2, cornerHeight: w / 2,
                          transform: nil)
        case .happy:
            return stroked(arc(centre: CGPoint(x: 0, y: height * 0.32), radius: width * 0.62, from: 1.12 * .pi, to: 1.88 * .pi))
        case .asleep:
            return stroked(arc(centre: CGPoint(x: 0, y: -height * 0.12), radius: width * 0.6, from: 0.14 * .pi, to: 0.86 * .pi))
        case .crossed:
            let reach = width * 0.48
            let cross = CGMutablePath()
            cross.addLines(between: [CGPoint(x: -reach, y: -reach), CGPoint(x: reach, y: reach)])
            cross.addLines(between: [CGPoint(x: reach, y: -reach), CGPoint(x: -reach, y: reach)])
            return stroked(cross)
        case .flat:
            let line = CGMutablePath()
            line.addLines(between: [CGPoint(x: -width * 0.6, y: height * 0.12), CGPoint(x: width * 0.6, y: height * 0.12)])
            return stroked(line)
        }
    }

    nonisolated private static func arc(centre: CGPoint, radius: Double, from start: Double, to end: Double) -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: (0...16).map { step in
            let angle = start + (end - start) * Double(step) / 16
            return CGPoint(x: centre.x + radius * cos(angle), y: centre.y + radius * sin(angle))
        })
        return path
    }

    nonisolated private static func stroked(_ path: CGPath) -> CGPath {
        let detail = 1000.0
        var up = CGAffineTransform(scaleX: detail, y: detail)
        var down = CGAffineTransform(scaleX: 1 / detail, y: 1 / detail)
        let outline = path.copy(using: &up)?
            .copy(strokingWithWidth: 0.075 * detail, lineCap: .round, lineJoin: .round, miterLimit: 10)
            .normalized()
        return outline?.copy(using: &down) ?? path
    }

    private static func mix(_ from: CGColor, _ to: CGColor, _ amount: Double) -> CGColor {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let a = from.converted(to: space, intent: .defaultIntent, options: nil)?.components,
              let b = to.converted(to: space, intent: .defaultIntent, options: nil)?.components,
              a.count == 4, b.count == 4
        else { return to }
        return CGColor(srgbRed: lerp(a[0], b[0], amount), green: lerp(a[1], b[1], amount), blue: lerp(a[2], b[2], amount),
                       alpha: lerp(a[3], b[3], amount))
    }
}

private struct Expression {
    enum Eyes: Int, CaseIterable { case open, wide, happy, asleep, crossed, flat }

    var eyes = Eyes.open
    var hop = 0.0
    var stretchX = 1.0
    var stretchY = 1.0
    var tilt = 0.0
    var opacity = 1.0
    var lookX = 0.0
    var lookY = 0.0
    var blink = 1.0
    var zee: Double?

    init(_ face: BuddyFace, time t: Double, since: Double) {
        switch face {
        case .working:
            let p = t.truncatingRemainder(dividingBy: 4) / 4
            if p < 0.7 {
                let line = (p / 0.35).truncatingRemainder(dividingBy: 1)
                lookX = line < 0.8 ? lerp(-1, 1, ease(line / 0.8)) : lerp(1, -1, ease((line - 0.8) / 0.2))
                lookY = 0.6
            } else {
                let glance = (p - 0.7) / 0.3
                let away = ease(glance / 0.4), back = ease((glance - 0.75) / 0.25)
                lookX = lerp(lerp(-1, 0.55, away), -1, back)
                lookY = lerp(lerp(0.6, -0.9, away), 0.6, back)
            }
            blink = Self.blink(at: t, every: 3.7)
            stretchY = 1 + 0.02 * sin(t * 2.6)
            stretchX = 2 - stretchY
        case .waiting:
            eyes = .wide
            lookY = -0.5
            let p = t.truncatingRemainder(dividingBy: 1.7) / 1.7
            let height = p < 0.2 ? sin(.pi * p / 0.2) : p < 0.4 ? 0.8 * sin(.pi * (p - 0.2) / 0.2) : 0
            let landing = p > 0.4 && p < 0.5 ? sin(.pi * (p - 0.4) / 0.1) : 0
            hop = -0.1 * height
            stretchY = 1 + 0.06 * height - 0.07 * landing
            stretchX = 1 - 0.04 * height + 0.06 * landing
            blink = Self.blink(at: t + 1, every: 2.9)
        case .yourTurn:
            eyes = .happy
            if since < 0.7 {
                let height = sin(.pi * since / 0.7)
                hop = -0.11 * height
                stretchY = 1 + 0.05 * height
            }
        case .blocked:
            eyes = .asleep
            hop = 0.03
            stretchY = 0.97 + 0.03 * sin(t * 1.4)
            stretchX = 2 - stretchY
            zee = t.truncatingRemainder(dividingBy: 2.4) / 2.4
        case .failed:
            eyes = .crossed
            tilt = 0.16
            if since < 0.9 { tilt += 0.22 * sin(since * 22) * (1 - since / 0.9) }
        case .interrupted:
            eyes = .flat
            stretchY = 0.96
            opacity = lerp(1, 0.5, ease(since / 0.5))
        }
    }

    static func blend(_ from: Expression, _ to: Expression, _ progress: Double) -> Expression {
        let k = ease(progress)
        var mixed = progress < 0.5 ? from : to
        mixed.hop = lerp(from.hop, to.hop, k)
        mixed.stretchX = lerp(from.stretchX, to.stretchX, k)
        mixed.stretchY = lerp(from.stretchY, to.stretchY, k)
        mixed.tilt = lerp(from.tilt, to.tilt, k)
        mixed.opacity = lerp(from.opacity, to.opacity, k)
        mixed.lookX = lerp(from.lookX, to.lookX, k)
        mixed.lookY = lerp(from.lookY, to.lookY, k)
        mixed.blink = (progress < 0.5 ? from.blink : to.blink) * (1 - 0.9 * sin(.pi * progress))
        mixed.zee = progress < 0.5 ? nil : to.zee
        return mixed
    }

    private static func blink(at t: Double, every period: Double) -> Double {
        t.truncatingRemainder(dividingBy: period) < 0.12 ? 0.12 : 1
    }
}

private func lerp(_ a: Double, _ b: Double, _ k: Double) -> Double { a + (b - a) * k }
private func ease(_ x: Double) -> Double { (1 - cos(.pi * min(1, max(0, x)))) / 2 }
