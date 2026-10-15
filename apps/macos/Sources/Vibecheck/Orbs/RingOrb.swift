import AppKit
import SwiftUI

struct RingOrbCanvas: NSViewRepresentable {
    let style: OrbStyle

    func makeNSView(context: Context) -> RingOrbView { RingOrbView() }

    func updateNSView(_ view: RingOrbView, context: Context) { view.show(style) }
}

final class RingOrbView: OrbHostView, OrbTickable {
    private enum Motion: Equatable {
        case spin(period: Double)
        case pulse
        case rest

        init(_ look: OrbLook) {
            switch look {
            case .base: self = .rest
            case .waiting: self = .pulse
            case .retrying: self = .spin(period: 2.4)
            default: self = .spin(period: 360.0 / 330)
            }
        }
    }

    private static let pulsePeriod = 1.2

    private let halo = CAShapeLayer()
    private let arc = CALayer()
    private let lead = CAShapeLayer()
    private let trail = CAShapeLayer()
    private let core = CAShapeLayer()
    private let shine = CAGradientLayer()
    private var motion = Motion.rest

    override init(frame: NSRect) {
        super.init(frame: frame)
        for ring in [halo, lead, trail] {
            ring.fillColor = nil
            ring.lineCap = .butt
        }
        shine.type = .radial
        shine.masksToBounds = true
        shine.colors = [CGColor(gray: 1, alpha: 0.55), CGColor(gray: 1, alpha: 0)]
        shine.startPoint = CGPoint(x: 0.35, y: 0.7)
        shine.endPoint = CGPoint(x: 0.35 + 0.573, y: 0.7 + 0.573)
        arc.addSublayer(trail)
        arc.addSublayer(lead)
        for sublayer in [halo, arc, core, shine] { layer?.addSublayer(sublayer) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let side = min(bounds.width, bounds.height)
        let box = CGRect(x: 0, y: 0, width: side, height: side)
        let line = max(1.5, side / 15.5)
        let radius = side / 2 - line / 2
        let centre = CGPoint(x: side / 2, y: side / 2)

        for ring in [halo, arc, lead, trail] {
            ring.bounds = box
        }
        for ring in [halo, arc] {
            ring.position = CGPoint(x: bounds.midX, y: bounds.midY)
        }
        for ring in [lead, trail] {
            ring.position = centre
        }
        for ring in [halo, lead, trail] {
            ring.lineWidth = line
        }
        halo.path = CGPath(ellipseIn: CGRect(x: line / 2, y: line / 2, width: 2 * radius, height: 2 * radius), transform: nil)
        lead.path = Self.quarter(centre: centre, radius: radius, from: .pi / 4)
        trail.path = Self.quarter(centre: centre, radius: radius, from: -.pi / 4)

        let diameter = side * 0.7
        let coreBox = CGRect(x: bounds.midX - diameter / 2, y: bounds.midY - diameter / 2, width: diameter, height: diameter)
        core.frame = coreBox
        core.path = CGPath(ellipseIn: CGRect(origin: .zero, size: coreBox.size), transform: nil)
        shine.frame = coreBox
        shine.cornerRadius = diameter / 2
        CATransaction.commit()
    }

    override func styleChanged(from previous: OrbStyle?) { refresh() }

    override func refresh() {
        guard let style else { return }
        motion = Motion(style.look)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for sublayer in [halo, lead, trail, core, shine] { sublayer.contentsScale = scale }
        core.fillColor = ink
        lead.strokeColor = ink
        trail.strokeColor = ink.copy(alpha: 0.35)
        halo.strokeColor = ink.copy(alpha: motion == .pulse ? 0.6 : 0.3)
        halo.isHidden = motion != .pulse && motion != .rest
        arc.isHidden = !halo.isHidden
        advance(to: Date.now.timeIntervalSince(OrbClock.epoch))
        CATransaction.commit()
        if running, motion != .rest { OrbTicker.shared.add(self) } else { OrbTicker.shared.remove(self) }
    }

    func advance(to elapsed: Double) {
        let t = running ? elapsed + (style?.offset ?? 0) : 0
        switch motion {
        case .spin(let period):
            arc.setAffineTransform(CGAffineTransform(rotationAngle: -(t / period).truncatingRemainder(dividingBy: 1) * 2 * .pi))
        case .pulse:
            let swell = running ? 0.5 + 0.5 * sin(t * 2 * .pi / Self.pulsePeriod) : 0
            halo.setAffineTransform(CGAffineTransform(scaleX: 1 + 0.14 * swell, y: 1 + 0.14 * swell))
            halo.opacity = Float(1 - 0.6 * swell)
        case .rest:
            halo.setAffineTransform(.identity)
            halo.opacity = 1
        }
    }

    private static func quarter(centre: CGPoint, radius: CGFloat, from start: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.addArc(center: centre, radius: radius, startAngle: start, endAngle: start + .pi / 2, clockwise: false)
        return path
    }
}
