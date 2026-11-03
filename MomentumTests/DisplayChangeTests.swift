import CoreGraphics
import Foundation
import Testing
@testable import Momentum

/// Plugging a monitor in or out: macOS moves the Desktops to the other display and keeps their Space IDs (MD-11).
@MainActor
struct DisplayChangeTests {
    private let old = LayoutKey(displayID: 1, spaceID: 10)
    private let moved = LayoutKey(displayID: 3, spaceID: 10)
    private let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)

    private func visible(_ windows: [WindowID]) -> DisplayLayoutState.VisibleLayout { .init(bounds: bounds, windows: windows) }

    // MARK: Layout state

    @Test func aDesktopMovedToAnotherDisplayTakesItsLayoutAlong() {
        var state = DisplayLayoutState()
        state.reconcile(visible: [old: visible([1, 2])], connectedDisplays: [1], focused: 2)
        state.swap(1, with: 2, in: old)
        #expect(state.trees[old]?.windows == [2, 1])
        // Display 1 is gone; the apps now list the windows in the other order.
        state.reconcile(visible: [moved: visible([1, 2])], connectedDisplays: [3], spaceOwners: [10: 3])
        #expect(state.trees[moved]?.windows == [2, 1])
        #expect(state.lastFocused[moved] == 2)
        #expect(state.joinOrder[moved] == [1, 2])
        #expect(state.trees[old] == nil)
        #expect(state.lastFocused[old] == nil)
        #expect(state.joinOrder[old] == nil)
    }

    @Test func aLayoutWaitsWhileNoDisplayShowsItsDesktop() {
        var state = DisplayLayoutState()
        state.reconcile(visible: [old: visible([1, 2])], connectedDisplays: [1], focused: 2)
        state.swap(1, with: 2, in: old)
        // The display is gone but its Desktops haven't reached another one yet.
        state.reconcile(visible: [:], connectedDisplays: [3], membership: [1: .space(10), 2: .space(10)])
        #expect(state.trees[old]?.windows == [2, 1])
        // They arrive about a second later.
        state.reconcile(visible: [moved: visible([1, 2])], connectedDisplays: [3],
                        membership: [1: .space(10), 2: .space(10)], spaceOwners: [10: 3])
        #expect(state.trees[moved]?.windows == [2, 1])
        #expect(state.trees[old] == nil)
    }

    @Test func aMovedLayoutReplacesAnOlderOneAtTheNewDisplay() {
        var state = DisplayLayoutState()
        // The new display still holds a layout it kept for this Desktop id, with windows nobody lists now.
        state.reconcile(visible: [moved: visible([5, 6])], connectedDisplays: [3], focused: 5)
        state.reconcile(visible: [old: visible([2, 1])], connectedDisplays: [1, 3], focused: 2)
        #expect(state.trees[moved]?.windows == [5, 6])
        state.reconcile(visible: [:], connectedDisplays: [3], spaceOwners: [10: 3])
        #expect(state.trees[moved]?.windows == [2, 1])
        #expect(state.lastFocused[moved] == 2)
        #expect(state.trees[old] == nil)
    }

    @Test func aWaitingLayoutGoesWhenItsWindowsDo() {
        var state = DisplayLayoutState()
        state.reconcile(visible: [old: visible([1, 2])], connectedDisplays: [1], focused: 2)
        state.reconcile(visible: [:], connectedDisplays: [3], membership: [1: .closed, 2: .space(99)])
        #expect(state.trees[old] == nil)
        #expect(state.lastFocused[old] == nil)
    }

    // MARK: Whole manager

    private func display(_ id: DisplayID, space: SpaceID, kind: DisplayTopology.SpaceKind = .normal) -> DisplayTopology.Display {
        .init(id: id, frame: bounds, usableFrame: CGRect(x: 0, y: 20, width: 1000, height: 780),
              activeSpace: .init(id: space, kind: kind))
    }

    private func inventory(_ display: DisplayTopology.Display, desktops: [SpaceID]) -> Spaces.DisplayInventory {
        .init(topology: .init(displays: [display]),
              desktops: [display.id: .init(identifier: "d\(display.id)", activeSpace: display.activeSpace, desktopSpaces: desktops)])
    }

    private struct Setup {
        let fixture: TilingFixture
        let manager: TilingManager
        let teams: FakeTilingWindow
        let slack: FakeTilingWindow
        let answers: Answers
    }

    private final class Answers { var order: [FakeTilingWindow] = [] }

    /// Slack on the left and Teams on the right of display 1's Desktop 11.
    private func makeSetup() -> Setup {
        let f = TilingFixture()
        let teams = FakeTilingWindow(1, CGRect(x: 10, y: 30, width: 400, height: 300), space: 11)
        let slack = FakeTilingWindow(2, CGRect(x: 10, y: 30, width: 400, height: 300), space: 11)
        f.windows = [teams, slack]
        let answers = Answers()
        answers.order = [slack, teams]
        var environment = f.environment
        environment.windows = { answers.order.map(\.handle) }
        f.displayInventory = inventory(display(1, space: 11), desktops: [11])
        let manager = TilingManager(configStore: f.config.store, environment: environment, initiallyTrusted: true)
        manager.retile()
        return Setup(fixture: f, manager: manager, teams: teams, slack: slack, answers: answers)
    }

    @Test func slackStaysLeftWhenTheDesktopsMoveToAnotherMonitor() {
        let s = makeSetup(); defer { s.fixture.cleanup() }
        let slackTile = s.slack.frame, teamsTile = s.teams.frame
        #expect(slackTile.minX < teamsTile.minX)

        s.fixture.displayInventory = inventory(display(3, space: 11), desktops: [11])
        s.answers.order = [s.teams, s.slack]  // the apps answer Teams first this time
        s.manager.retile()
        #expect(s.manager.layoutState.trees[LayoutKey(displayID: 3, spaceID: 11)]?.windows == [2, 1])
        #expect(s.manager.layoutState.trees[LayoutKey(displayID: 1, spaceID: 11)] == nil)
        #expect(s.slack.frame == slackTile)
        #expect(s.teams.frame == teamsTile)
    }

    @Test func theLayoutOutlastsTheGapBeforeTheDesktopsReachTheNewMonitor() {
        let s = makeSetup(); defer { s.fixture.cleanup() }
        let slackTile = s.slack.frame, teamsTile = s.teams.frame

        // About a second where the new display only has a placeholder Space and no Desktops yet.
        s.fixture.displayInventory = inventory(display(3, space: 1771, kind: .unknown), desktops: [])
        s.manager.retile()
        #expect(s.manager.layoutState.trees[LayoutKey(displayID: 1, spaceID: 11)]?.windows == [2, 1])

        s.fixture.displayInventory = inventory(display(3, space: 11), desktops: [11])
        s.answers.order = [s.teams, s.slack]
        s.manager.retile()
        #expect(s.manager.layoutState.trees[LayoutKey(displayID: 3, spaceID: 11)]?.windows == [2, 1])
        #expect(s.slack.frame == slackTile)
        #expect(s.teams.frame == teamsTile)
    }

    @Test func twoDisplaysShowingTheSameDesktopDontGuessWhereALayoutWent() {
        let s = makeSetup(); defer { s.fixture.cleanup() }
        let a = display(3, space: 11)
        let b = DisplayTopology.Display(id: 4, frame: CGRect(x: 1000, y: 0, width: 800, height: 600),
                                        usableFrame: CGRect(x: 1000, y: 20, width: 800, height: 580),
                                        activeSpace: .init(id: 11, kind: .normal))
        // Shared Spaces: both displays list the same Desktop, so neither one owns the old layout.
        s.fixture.displayInventory = .init(
            topology: .init(displays: [a, b]),
            desktops: [3: .init(identifier: "d3", activeSpace: a.activeSpace, desktopSpaces: [11]),
                       4: .init(identifier: "d4", activeSpace: b.activeSpace, desktopSpaces: [11])])
        s.answers.order = [s.teams, s.slack]
        s.manager.retile()
        // Built fresh in the order the apps answered, not taken from display 1.
        #expect(s.manager.layoutState.trees[LayoutKey(displayID: 3, spaceID: 11)]?.windows == [1, 2])
    }
}
