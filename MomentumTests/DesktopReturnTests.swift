import CoreGraphics
import Foundation
import Testing
@testable import Momentum

/// Returning to a Desktop whose app answers the window read late (MD-18). Models `WindowObserver`:
/// an app lists only the windows on the visible Desktop, and one that misses the reload's wait keeps its last answer.
@MainActor
struct DesktopReturnTests {
    private let away: SpaceID = 10
    private let desktop: SpaceID = 11

    private final class Observer {
        var lastRead: [String: [FakeTilingWindow]] = [:]
        /// Apps that answer within the wait.
        var answeringInTime: Set<String> = ["Teams", "Slack"]
    }

    private struct Setup {
        let fixture: TilingFixture
        let observer: Observer
        let manager: TilingManager
        let teams: FakeTilingWindow
        let slack: FakeTilingWindow
    }

    private func makeSetup(desktop: SpaceID) -> Setup {
        let f = TilingFixture()
        f.display(1, space: desktop)
        let teams = FakeTilingWindow(1, CGRect(x: 10, y: 30, width: 400, height: 300), space: desktop)
        let slack = FakeTilingWindow(2, CGRect(x: 10, y: 30, width: 400, height: 300), space: desktop)
        f.windows = [teams, slack]
        let observer = Observer()
        let apps = [("Teams", teams), ("Slack", slack)]
        var environment = f.environment
        environment.windows = { apps.flatMap { observer.lastRead[$0.0] ?? [] }.map(\.handle) }
        environment.reload = {
            let visible = f.displayInventory.topology.displays[0].activeSpace?.id
            for (name, window) in apps where observer.answeringInTime.contains(name) {
                // An app lists a window only while it's shown on the visible Desktop.
                observer.lastRead[name] = window.space == visible && window.orderedIn ? [window] : []
            }
        }
        let manager = TilingManager(configStore: f.config.store, environment: environment, initiallyTrusted: true)
        return Setup(fixture: f, observer: observer, manager: manager, teams: teams, slack: slack)
    }

    private func refresh(_ manager: TilingManager) async {
        manager.retile()
        for _ in 0..<60 { await Task.yield() }
    }

    private func order(_ manager: TilingManager) -> [WindowID]? {
        manager.layoutState.trees[LayoutKey(displayID: 1, spaceID: desktop)]?.windows
    }

    /// Tiles Teams (left) and Slack (right) on the Desktop, leaves it, and comes back with only Slack answering.
    private func returnWithTeamsLate(_ s: Setup) async {
        await refresh(s.manager)
        s.fixture.display(1, space: away)
        await refresh(s.manager)
        s.fixture.display(1, space: desktop)
        s.observer.answeringInTime = ["Slack"]
        await refresh(s.manager)
    }

    @Test func anAppThatAnswersLateKeepsItsWindowsPlaceOnReturningToTheDesktop() async {
        let s = makeSetup(desktop: desktop); defer { s.fixture.cleanup() }
        await refresh(s.manager)
        let teamsTile = s.teams.frame, slackTile = s.slack.frame
        #expect(teamsTile.minX < slackTile.minX)

        await returnWithTeamsLate(s)
        // Slack keeps its half while Teams hasn't answered.
        #expect(order(s.manager) == [1, 2])
        #expect(s.slack.frame == slackTile)

        s.observer.answeringInTime = ["Teams", "Slack"]
        await refresh(s.manager)
        #expect(order(s.manager) == [1, 2])
        #expect(s.teams.frame == teamsTile)
        #expect(s.slack.frame == slackTile)
    }

    @Test func bothAppsAnsweringInTimeKeepTheirPlaces() async {
        let s = makeSetup(desktop: desktop); defer { s.fixture.cleanup() }
        await refresh(s.manager)
        let teamsTile = s.teams.frame, slackTile = s.slack.frame
        s.fixture.display(1, space: away)
        await refresh(s.manager)
        s.fixture.display(1, space: desktop)
        await refresh(s.manager)
        #expect(order(s.manager) == [1, 2])
        #expect(s.teams.frame == teamsTile)
        #expect(s.slack.frame == slackTile)
    }

    /// Electron apps (Granola, Slack, Teams) hide a window when it's closed. WindowServer keeps it on its Desktop,
    /// but no app lists it, which looks the same as an app that hasn't answered yet.
    @Test func aWindowItsAppHidWithoutDestroyingItStopsHoldingItsPlace() async {
        let s = makeSetup(desktop: desktop); defer { s.fixture.cleanup() }
        await refresh(s.manager)
        let slackTile = s.slack.frame
        #expect(order(s.manager) == [1, 2])

        s.slack.orderedIn = false
        await refresh(s.manager)
        #expect(order(s.manager) == [1])
        #expect(s.teams.frame.width > slackTile.width)

        // Showing it again tiles it like any new window.
        s.slack.orderedIn = true
        await refresh(s.manager)
        #expect(order(s.manager) == [1, 2])
    }

    @Test(arguments: ["closed", "moved to another Desktop", "minimized"])
    func aWindowThatNoLongerBelongsStopsHoldingItsPlaceEvenWhileItsAppIsSilent(_ change: String) async {
        let s = makeSetup(desktop: desktop); defer { s.fixture.cleanup() }
        await refresh(s.manager)
        let slackTile = s.slack.frame
        s.fixture.display(1, space: away)
        await refresh(s.manager)
        s.fixture.display(1, space: desktop)
        switch change {
        case "closed": s.fixture.windows = [s.slack]
        case "moved to another Desktop": s.teams.space = 12
        default: s.teams.standard = false
        }
        // Teams reports (minimized) or stays silent (closed, moved); either way it leaves the layout.
        s.observer.answeringInTime = change == "minimized" ? ["Teams", "Slack"] : ["Slack"]
        await refresh(s.manager)
        #expect(order(s.manager) == [2])
        #expect(s.slack.frame.width > slackTile.width)
    }
}
