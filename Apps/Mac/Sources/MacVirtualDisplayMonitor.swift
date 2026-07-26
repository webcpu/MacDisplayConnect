import ColorSync
import CoreGraphics
import Foundation

@MainActor
final class MacVirtualDisplayMonitor {
    static let shared = MacVirtualDisplayMonitor()

    struct Snapshot: Equatable, Sendable {
        fileprivate let eligibleDisplayUUIDs: Set<UUID>
    }

    struct Dependencies {
        typealias DisplayList =
            @MainActor () -> Set<CGDirectDisplayID>
        typealias DisplayState =
            @MainActor (CGDirectDisplayID) -> Bool
        typealias DisplayUUIDLookup =
            @MainActor (CGDirectDisplayID) -> UUID?
        typealias DisplayIDLookup =
            @MainActor (UUID) -> CGDirectDisplayID
        typealias LearnedUUIDLoad =
            @MainActor () -> UUID?
        typealias LearnedUUIDSave =
            @MainActor (UUID) -> Void
        typealias Wait =
            @MainActor (Duration) async throws -> Void

        let onlineDisplayIDs: DisplayList
        let activeDisplayIDs: DisplayList
        let isDisplayOnline: DisplayState
        let isDisplayActive: DisplayState
        let isDisplayBuiltIn: DisplayState
        let isDisplayMirrored: DisplayState
        let displayUUID: DisplayUUIDLookup
        let displayID: DisplayIDLookup
        let loadLearnedDisplayUUID: LearnedUUIDLoad
        let saveLearnedDisplayUUID: LearnedUUIDSave
        let wait: Wait

        static let live = Self(
            onlineDisplayIDs: {
                SystemDisplayAPI.onlineDisplayIDs()
            },
            activeDisplayIDs: {
                SystemDisplayAPI.activeDisplayIDs()
            },
            isDisplayOnline: {
                CGDisplayIsOnline($0) != 0
            },
            isDisplayActive: {
                CGDisplayIsActive($0) != 0
            },
            isDisplayBuiltIn: {
                CGDisplayIsBuiltin($0) != 0
            },
            isDisplayMirrored: {
                CGDisplayIsInMirrorSet($0) != 0
            },
            displayUUID: {
                SystemDisplayAPI.uuid(for: $0)
            },
            displayID: {
                SystemDisplayAPI.displayID(for: $0)
            },
            loadLearnedDisplayUUID: {
                UserDefaults.standard
                    .string(forKey: learnedDisplayUUIDDefaultsKey)
                    .flatMap(UUID.init(uuidString:))
            },
            saveLearnedDisplayUUID: {
                UserDefaults.standard.set(
                    $0.uuidString,
                    forKey: learnedDisplayUUIDDefaultsKey
                )
            },
            wait: {
                try await Task.sleep(for: $0)
            }
        )
    }

    private(set) var learnedDisplayUUID: UUID?

    private let dependencies: Dependencies
    private let confirmationAttempts: Int
    private let confirmationInterval: Duration

    init(
        dependencies: Dependencies = .live,
        confirmationAttempts: Int = 50,
        confirmationInterval: Duration = .milliseconds(100)
    ) {
        self.dependencies = dependencies
        self.confirmationAttempts = max(1, confirmationAttempts)
        self.confirmationInterval = confirmationInterval
        learnedDisplayUUID = dependencies.loadLearnedDisplayUUID()
    }

    func snapshotBeforeConnectionAttempt() -> Snapshot {
        Snapshot(eligibleDisplayUUIDs: eligibleDisplayUUIDs())
    }

    func confirmConnection(after snapshot: Snapshot) async throws -> Bool {
        for attempt in 0..<confirmationAttempts {
            if isConnected {
                return true
            }

            let newlyEligibleDisplayUUIDs = eligibleDisplayUUIDs()
                .subtracting(snapshot.eligibleDisplayUUIDs)

            if newlyEligibleDisplayUUIDs.count == 1,
               let displayUUID = newlyEligibleDisplayUUIDs.first
            {
                learn(displayUUID)
                return true
            }

            if attempt + 1 < confirmationAttempts {
                try await dependencies.wait(confirmationInterval)
            }
        }

        return false
    }

    var isConnected: Bool {
        guard let learnedDisplayUUID else {
            return false
        }

        let displayID = dependencies.displayID(learnedDisplayUUID)
        guard displayID != kCGNullDirectDisplay else {
            return false
        }

        guard dependencies.onlineDisplayIDs().contains(displayID),
              dependencies.activeDisplayIDs().contains(displayID)
        else {
            return false
        }

        return dependencies.isDisplayOnline(displayID)
            && dependencies.isDisplayActive(displayID)
            && !dependencies.isDisplayBuiltIn(displayID)
            && !dependencies.isDisplayMirrored(displayID)
    }

    @discardableResult
    func learnAlreadyConnectedDisplayIfUnambiguous() -> Bool {
        if isConnected {
            return true
        }

        let displayUUIDs = eligibleDisplayUUIDs()
        guard displayUUIDs.count == 1,
              let displayUUID = displayUUIDs.first
        else {
            return false
        }

        learn(displayUUID)
        return true
    }

    private func eligibleDisplayUUIDs() -> Set<UUID> {
        let displayIDs = dependencies.onlineDisplayIDs()
            .intersection(dependencies.activeDisplayIDs())

        return displayIDs.reduce(into: Set<UUID>()) { result, displayID in
            guard displayID != kCGNullDirectDisplay else {
                return
            }

            guard dependencies.isDisplayOnline(displayID),
                  dependencies.isDisplayActive(displayID),
                  !dependencies.isDisplayBuiltIn(displayID),
                  !dependencies.isDisplayMirrored(displayID),
                  let displayUUID = dependencies.displayUUID(displayID)
            else {
                return
            }

            result.insert(displayUUID)
        }
    }

    private func learn(_ displayUUID: UUID) {
        learnedDisplayUUID = displayUUID
        dependencies.saveLearnedDisplayUUID(displayUUID)
    }
}

private let learnedDisplayUUIDDefaultsKey =
    "MacDisplayConnect.macVirtualDisplayUUID"

private enum SystemDisplayAPI {
    typealias DisplayListQuery = (
        UInt32,
        UnsafeMutablePointer<CGDirectDisplayID>?,
        UnsafeMutablePointer<UInt32>?
    ) -> CGError

    static func onlineDisplayIDs() -> Set<CGDirectDisplayID> {
        displayIDs { maximumDisplayCount, displays, displayCount in
            CGGetOnlineDisplayList(
                maximumDisplayCount,
                displays,
                displayCount
            )
        }
    }

    static func activeDisplayIDs() -> Set<CGDirectDisplayID> {
        displayIDs { maximumDisplayCount, displays, displayCount in
            CGGetActiveDisplayList(
                maximumDisplayCount,
                displays,
                displayCount
            )
        }
    }

    static func uuid(for displayID: CGDirectDisplayID) -> UUID? {
        guard let unmanagedUUID =
            CGDisplayCreateUUIDFromDisplayID(displayID)
        else {
            return nil
        }

        let displayUUID = unmanagedUUID.takeRetainedValue()
        let uuidString = CFUUIDCreateString(nil, displayUUID) as String
        return UUID(uuidString: uuidString)
    }

    static func displayID(for uuid: UUID) -> CGDirectDisplayID {
        guard let displayUUID = CFUUIDCreateFromString(
            nil,
            uuid.uuidString as CFString
        ) else {
            return kCGNullDirectDisplay
        }

        return CGDisplayGetDisplayIDFromUUID(displayUUID)
    }

    private static func displayIDs(
        query: DisplayListQuery
    ) -> Set<CGDirectDisplayID> {
        var displayCount: UInt32 = 0
        guard query(0, nil, &displayCount) == .success,
              displayCount > 0
        else {
            return []
        }

        var displayIDs = [CGDirectDisplayID](
            repeating: kCGNullDirectDisplay,
            count: Int(displayCount)
        )
        var returnedDisplayCount = displayCount
        let error = displayIDs.withUnsafeMutableBufferPointer { buffer in
            query(
                displayCount,
                buffer.baseAddress,
                &returnedDisplayCount
            )
        }

        guard error == .success else {
            return []
        }

        let safeDisplayCount = min(displayCount, returnedDisplayCount)
        return Set(displayIDs.prefix(Int(safeDisplayCount)))
    }
}
