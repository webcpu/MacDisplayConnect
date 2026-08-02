import Foundation
import Testing
@testable import MacDisplayConnectVision

@MainActor
@Suite("Auto-Connect preference")
struct AutoConnectPreferenceTests {
    @Test("defaults to enabled when no value was saved")
    func defaultsToEnabled() {
        let defaults = makeDefaults()

        let preference = AutoConnectPreference(defaults: defaults)

        #expect(preference.isEnabled)
    }

    @Test("persists the disabled value locally")
    func persistsDisabledValue() {
        let defaults = makeDefaults()
        let preference = AutoConnectPreference(defaults: defaults)

        preference.isEnabled = false

        #expect(!AutoConnectPreference(defaults: defaults).isEnabled)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "AutoConnectPreferenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
