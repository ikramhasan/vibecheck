import CoreGraphics

public struct PanelPlacement: Codable, Equatable, Sendable {
    public enum Side: String, Codable, Sendable { case left, right }

    public var side: Side
    public var heightFraction: Double
    public var displayUUID: String?

    public init(side: Side = .right, heightFraction: Double = 0.5, displayUUID: String? = nil) {
        self.side = side
        self.heightFraction = heightFraction
        self.displayUUID = displayUUID
    }

    public func centerFromBottom(cardHeight: CGFloat, in length: CGFloat) -> CGFloat {
        guard cardHeight < length else { return length / 2 }
        return min(max(CGFloat(heightFraction) * length, cardHeight / 2), length - cardHeight / 2)
    }

    public static func dropped(at center: CGPoint, in area: CGRect, displayUUID: String?) -> PanelPlacement {
        PanelPlacement(side: center.x < area.midX ? .left : .right,
                       heightFraction: min(max((center.y - area.minY) / area.height, 0), 1),
                       displayUUID: displayUUID)
    }
}
