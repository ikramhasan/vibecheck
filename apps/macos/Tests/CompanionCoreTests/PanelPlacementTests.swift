import CoreGraphics
import Foundation
import Testing
@testable import CompanionCore

@Suite struct PanelPlacementTests {
    @Test func defaultsToTheMiddleOfTheRightEdge() {
        let placement = PanelPlacement()
        #expect(placement.side == .right)
        #expect(placement.centerFromBottom(cardHeight: 100, in: 1000) == 500)
    }

    @Test func keepsTheCardInsideTheScreen() {
        let top = PanelPlacement(heightFraction: 1)
        #expect(top.centerFromBottom(cardHeight: 200, in: 1000) == 900)
        let bottom = PanelPlacement(heightFraction: 0)
        #expect(bottom.centerFromBottom(cardHeight: 200, in: 1000) == 100)
    }

    @Test func centersACardTallerThanTheScreen() {
        #expect(PanelPlacement(heightFraction: 0.9).centerFromBottom(cardHeight: 1200, in: 1000) == 500)
    }

    @Test func scalesWithTheScreenHeight() {
        let placement = PanelPlacement(heightFraction: 0.25)
        #expect(placement.centerFromBottom(cardHeight: 100, in: 800) == 200)
        #expect(placement.centerFromBottom(cardHeight: 100, in: 1600) == 400)
    }

    @Test func snapsToTheNearerSide() {
        let area = CGRect(x: 1000, y: 100, width: 1000, height: 800)
        let left = PanelPlacement.dropped(at: CGPoint(x: 1400, y: 700), in: area, displayUUID: "A")
        #expect(left == PanelPlacement(side: .left, heightFraction: 0.75, displayUUID: "A"))
        let right = PanelPlacement.dropped(at: CGPoint(x: 1600, y: 100), in: area, displayUUID: nil)
        #expect(right == PanelPlacement(side: .right, heightFraction: 0, displayUUID: nil))
    }

    @Test func clampsADropOutsideTheVisibleArea() {
        let area = CGRect(x: 0, y: 0, width: 1000, height: 800)
        #expect(PanelPlacement.dropped(at: CGPoint(x: 900, y: 900), in: area, displayUUID: nil).heightFraction == 1)
    }

    @MainActor
    @Test func persistsAcrossLaunches() throws {
        let suite = "PanelPlacementTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let placement = PanelPlacement(side: .left, heightFraction: 0.3, displayUUID: "DISPLAY")
        AppSettings(defaults: defaults).panelPlacement = placement
        #expect(AppSettings(defaults: defaults).panelPlacement == placement)
    }
}
