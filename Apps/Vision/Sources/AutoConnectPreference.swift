import Foundation
import Observation

@Observable
@MainActor
final class AutoConnectPreference {
    static let storageKey = "automaticallyReconnectEnabled"

    @ObservationIgnored private let defaults: UserDefaults

    var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Self.storageKey)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.object(forKey: Self.storageKey) as? Bool ?? true
    }
}
