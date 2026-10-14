// Ported from thinking-orbs by Yogesh (MIT, see LICENSE in this folder):
// https://github.com/yogesharc/thinking-orbs/blob/main/apps/web/registry/orb/orb-core.ts

import CompanionCore
import SwiftUI

enum OrbLook: Hashable {
    case base, working, gyro, reasoning, twins, searching, lighthouse, background, spiral, retrying, waiting

    init(_ style: LoaderStyle, seed: String) {
        switch style.resolved(seed: seed) {
        case .working, .random: self = .working
        case .gyro: self = .gyro
        case .reasoning: self = .reasoning
        case .twins: self = .twins
        case .searching: self = .searching
        case .lighthouse: self = .lighthouse
        case .background: self = .background
        case .spiral: self = .spiral
        }
    }

    fileprivate var period: Double {
        switch self {
        case .working: 3400
        case .gyro: 3000
        case .base, .reasoning, .twins: 6500
        case .waiting: 12000
        case .searching, .lighthouse, .background, .spiral, .retrying: 13000
        }
    }

    var loop: Double {
        switch self {
        case .base: 0
        case .working: 3400
        case .gyro: 6000
        case .reasoning, .twins: 6500
        case .waiting: 12000
        case .searching, .lighthouse, .background, .spiral: 13000
        case .retrying: 16000
        }
    }

    var walkers: Int {
        switch self {
        case .reasoning: 1
        case .twins: 2
        default: 0
        }
    }
}

struct Orb: View {
    let look: OrbLook
    var size: CGFloat = 20
    var color: Color
    var animated = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.orbsOnScreen) private var onScreen
    @Environment(\.orbMaxFPS) private var maxFPS

    var body: some View {
        let light = colorScheme == .light
        let style = OrbStyle(look: look, size: Double(size),
                             ink: light ? color.mix(with: .black, by: 0.25) : color,
                             floor: light ? 0.35 : 0.2,
                             still: !animated || reduceMotion,
                             playing: onScreen)
        Group {
            switch OrbRendering.shared.renderer {
            case .ticker: OrbTickerCanvas(style: style, fps: min(OrbRendering.shared.tickerFPS, maxFPS))
            case .swiftUI: OrbTimelineCanvas(style: style)
            case .layer: OrbLayerCanvas(style: style)
            case .sprite: OrbSpriteCanvas(style: style)
            case .apng: OrbAPNGCanvas(style: style)
            case .still: OrbSpriteCanvas(style: OrbStyle(look: look, size: Double(size), ink: style.ink, floor: style.floor,
                                                         still: true, playing: false))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct OrbStyle: Equatable {
    let look: OrbLook
    let size: Double
    let ink: Color
    let floor: Double
    let still: Bool
    let playing: Bool
}

extension EnvironmentValues {
    @Entry var orbsOnScreen = true
    @Entry var orbMaxFPS = Double.infinity
}

enum OrbClock {
    static let epoch = Date.now
}

private let tau = Double.pi * 2
private let golden = Double.pi * (3 - 5.0.squareRoot())
private func ease(_ x: Double) -> Double { (1 - cos(.pi * x)) / 2 }
private func hash(_ n: Double) -> Double {
    let s = sin(n * 127.1) * 43758.5453
    return s - floor(s)
}
private func dist2(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double {
    let d = a - b
    return (d * d).sum()
}
private func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }

private let ringAxis: SIMD3<Double> = {
    let tip = radians(30), roll = radians(10)
    return [-sin(roll) * cos(tip), cos(roll) * cos(tip), sin(tip)]
}()
private let twist = 1.4
private let lean = radians(30), trail = Double.pi / 2
private let lensMs = 13000.0 / 7, lensSpots = 7.0, lensMove = 0.4, lensRadius = 0.6
private let hop = 6500.0 / 30, tail = 5, reach = 24, walkLength = 16

private func spring(_ x: Double) -> Double {
    1 - exp(-4.5 * x) * cos(3 * .pi * x) - x * exp(-4.5)
}

private func rewind(_ t: Double, _ w: Double) -> Double {
    let p = 3200.0, k = floor(t / p), u = t - k * p
    let back = 1300 * w
    let forward = (2000 + 100 + 100) * w
    let a: Double
    if u < 2000 {
        a = u * w
    } else if u < 2200 {
        let x = (u - 2000) / 200
        a = (2000 + 200 * (x - x * x / 2)) * w
    } else if u < 3000 {
        a = 2100 * w - back * spring((u - 2200) / 800)
    } else {
        let x = (u - 3000) / 200
        a = 2100 * w - back + 100 * x * x * w
    }
    return k * (forward - back) + a
}

private func spot(_ k: Double) -> SIMD3<Double> {
    let phi = k * 2.45 + hash(k) * 1.5, theta = radians(15 + 30 * hash(k + 0.5))
    return [sin(theta) * cos(phi), sin(theta) * sin(phi), cos(theta)]
}

private func lens(at t: Double) -> SIMD3<Double> {
    let k = floor(t / lensMs), u = t / lensMs - k
    let e = u < lensMove ? (1 - cos(u / lensMove * .pi)) / 2 : 1
    let a = spot(k.truncatingRemainder(dividingBy: lensSpots)), b = spot((k + 1).truncatingRemainder(dividingBy: lensSpots))
    let v = a + (b - a) * e
    return v / (v * v).sum().squareRoot()
}

private func nearest(_ points: [SIMD3<Double>], _ i: Int, _ k: Int) -> [Int] {
    var index: [Int] = [], distance: [Double] = []
    for j in points.indices where j != i {
        let e = dist2(points[i], points[j])
        if index.count == k {
            if e >= distance[k - 1] { continue }
            index.removeLast()
            distance.removeLast()
        }
        let at = distance.firstIndex { $0 > e } ?? distance.count
        index.insert(j, at: at)
        distance.insert(e, at: at)
    }
    return index
}

private func spiralArms(_ count: Int) -> [SIMD3<Double>] {
    func at(_ lat: Double, _ lon: Double) -> SIMD3<Double> { [cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon)] }
    let g = (4 * Double.pi / Double(count)).squareRoot(), n = 8, along = 0.6 * g
    return (0..<n).flatMap { m -> [SIMD3<Double>] in
        let room = m == 0 ? n : m & -m
        let limit = min(radians(85), acos(min(1, g * Double(n) / (tau * Double(room)))))
        var out: [SIMD3<Double>] = []
        var lat = -limit + (Double(m) * 0.618).truncatingRemainder(dividingBy: 1) * along
        while lat <= limit {
            out.append(at(lat, Double(m) / Double(n) * tau - lat))
            lat += along / (1 + cos(lat) * cos(lat)).squareRoot()
        }
        return out
    }
}

private func fibonacciSphere(_ count: Int) -> [SIMD3<Double>] {
    (0..<count).map { i in
        let y = 1 - 2 * (Double(i) + 0.5) / Double(count), r = (1 - y * y).squareRoot(), th = Double(i) * golden
        return [r * cos(th), y, r * sin(th)]
    }
}

final class OrbModel {
    let look: OrbLook
    let size: Double
    private let points: [SIMD3<Double>]
    private let dotRadius: Double
    private let neighbours: [[Int]]
    private var walks: [[Int]]
    private var hops = 0

    init(look: OrbLook, size: Double) {
        self.look = look
        self.size = size
        let density = look == .background ? 1.0 : 4.0
        let count = max(8, Int((size * density).rounded()))
        let points = look == .spiral ? spiralArms(count) : fibonacciSphere(count)
        self.points = points
        dotRadius = pow(size / 64, 0.6) * 0.72 * (4 / density).squareRoot()
        let walking = look.walkers > 0 && points.count > 1
        neighbours = walking ? points.indices.map { nearest(points, $0, reach) } : []
        walks = Array(repeating: [], count: walking ? look.walkers : 0)
    }

    private func yaw(_ t: Double) -> Double {
        switch look {
        case .retrying: return rewind(2 * t, tau / 9000)
        default: return t / look.period * tau
        }
    }

    func draw(t: Double, dot: (Int, Double, Double, Double, Double) -> Void) {
        let c = size / 2, radius = c * 0.8
        let yaw = yaw(t)
        let gyro: Double? = look == .gyro ? t / 6000 * tau : nil
        let pitch = radians(20 + (gyro.map { 10 * cos($0) } ?? 0))
        let roll = gyro.map { radians(12 * sin($0)) } ?? 0, sr = sin(roll), cr = cos(roll)
        let sy = sin(yaw), cy = cos(yaw), st = sin(pitch), ct = cos(pitch)

        let lit = walk(t: t) { k in
            let p = self.points[k]
            return p.y * st + (-p.x * sy + p.z * cy) * ct
        }

        let ahead = tau / 2000 + tau / look.period
        let head = t / 2000 * tau + yaw
        func headLat(_ tt: Double) -> Double { radians(70) * (1 - 2 * (tt.truncatingRemainder(dividingBy: 6000) / 6000)) }
        let glow = min(1, 3 * sin(.pi * (t.truncatingRemainder(dividingBy: 6000) / 6000)))
        let lensCentre = look == .searching ? lens(at: t) : nil
        let tw = look == .gyro ? 0.5 * sin(t / 3000 * tau) : 0

        for (i, p) in points.enumerated() {
            let (x, y, z) = (p.x, p.y, p.z)
            let turn = yaw + twist * tw * y
            let (ly, lc) = tw != 0 ? (sin(turn), cos(turn)) : (sy, cy)
            let z1 = -x * ly + z * lc
            var vx = x * lc + z * ly, vy = y * ct - z1 * st
            let vz = y * st + z1 * ct, d = (vz + 1) / 2
            var r = (0.5 + 1.4 * d) * dotRadius
            var a = max(0, (d - 0.3) / 0.7)

            if let lensCentre {
                let cosine = (vx * lensCentre.x + vy * lensCentre.y + vz * lensCentre.z) / (vx * vx + vy * vy + vz * vz).squareRoot()
                let angle = acos(min(1, cosine))
                let w = angle < lensRadius ? pow(1 - pow(angle / lensRadius, 2), 2) : 0
                a *= 1 - 0.55 * (1 - w)
                if size <= 24 { r *= 1 + 0.5 * w }
                if w > 0 {
                    vx *= 1 + 0.12 * w
                    vy *= 1 + 0.12 * w
                    vx += (vx - lensCentre.x) * 0.35 * w
                    vy += (vy - lensCentre.y) * 0.35 * w
                    r *= 1 + 0.9 * w
                    a += (1 - a) * w
                }
            }
            if look == .working {
                let u = t.truncatingRemainder(dividingBy: 1700), at = 1.3 - 2.6 * ease(min(1, u / 1200))
                let q = vx * ringAxis.x + vy * ringAxis.y + vz * ringAxis.z
                let g = u < 1200 ? exp(-pow((q - at) / 0.2, 2)) : 0
                r *= 1 + 0.6 * g
                a += (1 - a) * g
                let w = min(1, max(0, (q - at) / 0.2)) * (u < 1200 ? 1 : 1 - min(1, 1.6 * ((u - 1200) / 800)))
                vx *= 1 - 0.08 * w
                vy *= 1 - 0.08 * w
                r *= 1 - 0.15 * w
            }
            if look == .lighthouse {
                a *= 0.5
                let across = vx * cos(lean) - vy * sin(lean)
                let toward = -st * (vx * sin(lean) + vy * cos(lean)) + ct * vz
                let off = atan2(across, toward) - ((t / 2600).truncatingRemainder(dividingBy: 1) * tau - .pi)
                let dphi = ((off + .pi).truncatingRemainder(dividingBy: tau) + tau).truncatingRemainder(dividingBy: tau) - .pi
                let beam = dphi < 0 ? max(0, 1 + dphi / trail) : exp(-pow(dphi / 0.45, 2))
                let g = beam * (0.25 + 0.75 * min(1, max(0, (d - 0.4) / 0.3)))
                r *= 1 + 0.6 * g
                a += (1 - a) * g
            }
            if !walks.isEmpty {
                let spark = lit[i] ?? 0
                a *= 0.5
                if spark > 0 {
                    r *= 1 + 0.8 * spark
                    a += (1 - a) * spark
                }
            }
            if look == .waiting {
                let length = (x * x + y * y + z * z).squareRoot()
                let lat = asin(y / (length == 0 ? 1 : length)), lon = atan2(z, x)
                let off = atan2(sin(lon - head), cos(lon - head)), along = off * cos(lat)
                let g = exp(-pow((lat - headLat(t + off / ahead)) / 0.28, 2))
                    * exp(-pow(along / (off * ahead > 0 ? 0.12 : 1), 2))
                let w = glow * pow(g, 0.6)
                a = a * 0.5 + (1 - a * 0.5) * w
                r *= 1 + 1.1 * w
            }
            if roll != 0 { (vx, vy) = (vx * cr - vy * sr, vx * sr + vy * cr) }
            dot(i, c + vx * radius, c - vy * radius, max(0.45, r), a < 0.005 ? 0 : min(1, a))
        }
    }

    private func walk(t: Double, facing: (Int) -> Double) -> [Int: Double] {
        guard !walks.isEmpty else { return [:] }
        let s = t / hop, n = Int(floor(s)), f = s - floor(s)
        if walks[0].isEmpty {
            let first = points.indices.max { facing($0) < facing($1) } ?? 0
            func apart(_ k: Int) -> Double { facing(k) + dist2(points[k], points[first]) }
            for w in walks.indices {
                walks[w] = [w == 0 ? first : points.indices.max { apart($0) < apart($1) } ?? 0]
            }
        }
        hops = max(hops, n - walkLength)
        while hops < n {
            for w in walks.indices {
                let recent = walks[w].suffix(8), from = walks[w].last!
                let other = walks.count == 2 ? walks[1 - w].last : nil
                var best = -1, score = -Double.infinity
                for (j, k) in neighbours[from].enumerated() {
                    let apart = other.map { 1.2 * min(dist2(points[k], points[$0]).squareRoot(), 0.8) } ?? 0
                    let candidate = facing(k) + 0.35 * hash(Double(hops * 31 + j + w * 977)) + apart
                    if !recent.contains(k), candidate > score {
                        score = candidate
                        best = k
                    }
                }
                walks[w].append(best < 0 ? neighbours[from][0] : best)
                if walks[w].count > walkLength { walks[w].removeFirst() }
            }
            hops += 1
        }
        var lit: [Int: Double] = [:]
        for walk in walks {
            for j in stride(from: tail - 1, through: 0, by: -1) where walk.count - 1 - j >= 0 {
                let value = j == 0 ? ease(min(1, f * 2)) : 1 - (Double(j - 1) + f) / Double(tail)
                let k = walk[walk.count - 1 - j]
                lit[k] = max(lit[k] ?? 0, value)
            }
        }
        return lit
    }
}
