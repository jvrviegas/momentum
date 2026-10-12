import Testing
@testable import Momentum

@MainActor
struct SettingsNavigationTests {
    @Test func sidebarPagesHaveStableUniqueIdentifiers() {
        #expect(SettingsPage.allCases.first == .layout)
        #expect(Set(SettingsPage.allCases.map(\.id)).count == SettingsPage.allCases.count)
        for page in SettingsPage.allCases {
            #expect(SettingsPage(rawValue: page.rawValue) == page)
            #expect(!page.title.isEmpty)
            #expect(!page.subtitle.isEmpty)
            #expect(!page.icon.isEmpty)
        }
    }

    @Test func shortcutGroupsCoverEveryActionExactlyOnce() {
        let grouped = SettingsShortcutGroup.allCases.flatMap(\.actions)
        #expect(grouped.count == Action.allCases.count)
        #expect(Set(grouped) == Set(Action.allCases))
        #expect(Set(grouped).count == grouped.count)
        #expect(SettingsShortcutGroup.focus.actions == Direction.allCases.map(Action.focus))
        #expect(SettingsShortcutGroup.move.actions == Direction.allCases.map(Action.move))
        #expect(SettingsShortcutGroup.desktops.actions.count == 18)
        #expect(SettingsShortcutGroup.displays.actions == [.sendToPreviousDisplay, .sendToNextDisplay])
        #expect(SettingsShortcutGroup.other.actions.contains(.toggleKeepAwake))
    }

    @Test func settingsPreferencesApplyOnlyToNextKeepAwakeSession() throws {
        let fixture = KeepAwakeFixture()
        defer { fixture.cleanup() }
        fixture.service.start()
        let deadline = fixture.service.deadline
        try fixture.config.store.updateKeepAwake(.init(duration: .oneHour, mode: .systemAndDisplay))
        #expect(fixture.service.mode == .system)
        #expect(fixture.service.deadline == deadline)
        fixture.service.stop()
        fixture.service.start()
        #expect(fixture.service.mode == .systemAndDisplay)
        #expect(fixture.service.deadline == fixture.time + 3600)
    }
}
