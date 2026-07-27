import CoreGraphics
import Foundation
import Testing
@testable import MacDisplayConnect

@Suite("Mac Virtual Display monitor")
@MainActor
struct MacVirtualDisplayMonitorTests {
    @Test("confirmation learns the single display added after the snapshot")
    func confirmationLearnsSingleNewDisplay() async throws {
        let system = TestDisplaySystem()
        system.installDisplay(
            id: 10,
            uuid: TestUUID.external,
            isOnline: true,
            isActive: true
        )

        let monitor = MacVirtualDisplayMonitor(
            dependencies: system.dependencies(),
            confirmationAttempts: 2,
            confirmationInterval: .zero
        )
        let snapshot = monitor.snapshotBeforeConnectionAttempt()

        system.onWait = {
            system.installDisplay(
                id: 20,
                uuid: TestUUID.visionPro,
                isOnline: true,
                isActive: true
            )
        }

        let didConfirm = try await monitor.confirmConnection(after: snapshot)

        #expect(didConfirm)
        #expect(monitor.learnedDisplayUUID == TestUUID.visionPro)
        #expect(system.storedUUID == TestUUID.visionPro)
        #expect(system.waitCount == 1)
    }

    @Test("confirmation does not learn when multiple displays are newly eligible")
    func confirmationRejectsAmbiguousNewDisplays() async throws {
        let system = TestDisplaySystem()
        let monitor = MacVirtualDisplayMonitor(
            dependencies: system.dependencies(),
            confirmationAttempts: 1,
            confirmationInterval: .zero
        )
        let snapshot = monitor.snapshotBeforeConnectionAttempt()

        system.installDisplay(
            id: 20,
            uuid: TestUUID.visionPro,
            isOnline: true,
            isActive: true
        )
        system.installDisplay(
            id: 30,
            uuid: TestUUID.external,
            isOnline: true,
            isActive: true
        )

        let didConfirm = try await monitor.confirmConnection(after: snapshot)

        #expect(!didConfirm)
        #expect(monitor.learnedDisplayUUID == nil)
        #expect(system.storedUUID == nil)
    }

    @Test("a candidate must be online, active, external, and unmirrored")
    func candidateEligibilityUsesPublicDisplayState() {
        let system = TestDisplaySystem()
        system.installDisplay(
            id: 1,
            uuid: TestUUID.builtIn,
            isOnline: true,
            isActive: true,
            isBuiltIn: true
        )
        system.installDisplay(
            id: 2,
            uuid: TestUUID.mirrored,
            isOnline: true,
            isActive: true,
            isMirrored: true
        )
        system.installDisplay(
            id: 3,
            uuid: TestUUID.inactive,
            isOnline: true,
            isActive: false
        )
        system.installDisplay(
            id: 4,
            uuid: TestUUID.offline,
            isOnline: false,
            isActive: true
        )
        system.installDisplay(
            id: 5,
            uuid: TestUUID.visionPro,
            isOnline: true,
            isActive: true
        )
        let monitor = MacVirtualDisplayMonitor(
            dependencies: system.dependencies()
        )

        let didLearn = monitor.learnAlreadyConnectedDisplayIfUnambiguous()

        #expect(didLearn)
        #expect(monitor.learnedDisplayUUID == TestUUID.visionPro)
    }

    @Test("already-connected learning requires exactly one eligible display")
    func alreadyConnectedLearningRejectsAmbiguity() {
        let system = TestDisplaySystem()
        system.installDisplay(
            id: 20,
            uuid: TestUUID.visionPro,
            isOnline: true,
            isActive: true
        )
        system.installDisplay(
            id: 30,
            uuid: TestUUID.external,
            isOnline: true,
            isActive: true
        )
        let monitor = MacVirtualDisplayMonitor(
            dependencies: system.dependencies()
        )

        let didLearn = monitor.learnAlreadyConnectedDisplayIfUnambiguous()

        #expect(!didLearn)
        #expect(monitor.learnedDisplayUUID == nil)
        #expect(system.storedUUID == nil)
    }

    @Test("connection refresh learns a replacement eligible display UUID")
    func connectionRefreshLearnsReplacementUUID() {
        let system = TestDisplaySystem()
        system.storedUUID = TestUUID.external
        system.displayIDByUUID[TestUUID.external] = 30
        system.installDisplay(
            id: 20,
            uuid: TestUUID.visionPro,
            isOnline: true,
            isActive: true
        )
        let monitor = MacVirtualDisplayMonitor(
            dependencies: system.dependencies()
        )

        #expect(!monitor.isConnected)
        #expect(monitor.learnAlreadyConnectedDisplayIfUnambiguous())
        #expect(monitor.learnedDisplayUUID == TestUUID.visionPro)
        #expect(system.storedUUID == TestUUID.visionPro)
    }

    @Test("connection state resolves the persisted UUID to its current display")
    func connectionStateUsesPersistedUUID() {
        let system = TestDisplaySystem()
        system.storedUUID = TestUUID.visionPro
        system.installDisplay(
            id: 20,
            uuid: TestUUID.visionPro,
            isOnline: true,
            isActive: true
        )
        let monitor = MacVirtualDisplayMonitor(
            dependencies: system.dependencies()
        )

        #expect(monitor.isConnected)

        system.activeDisplayIDs.remove(20)

        #expect(!monitor.isConnected)
    }

    @Test("disconnection confirmation waits for the learned display to disappear")
    func disconnectionConfirmationWaitsForDisplayRemoval() async throws {
        let system = TestDisplaySystem()
        system.storedUUID = TestUUID.visionPro
        system.installDisplay(
            id: 20,
            uuid: TestUUID.visionPro,
            isOnline: true,
            isActive: true
        )
        let monitor = MacVirtualDisplayMonitor(
            dependencies: system.dependencies(),
            confirmationAttempts: 2,
            confirmationInterval: .zero
        )
        system.onWait = {
            system.activeDisplayIDs.remove(20)
        }

        let didConfirm = try await monitor.confirmDisconnection()

        #expect(didConfirm)
        #expect(system.waitCount == 1)
    }

    @Test(
        "disconnection learns the removed display without confusing a remaining external display"
    )
    func disconnectionLearnsRemovedDisplayAmongExternalDisplays() async throws {
        let system = TestDisplaySystem()
        system.installDisplay(
            id: 20,
            uuid: TestUUID.visionPro,
            isOnline: true,
            isActive: true
        )
        system.installDisplay(
            id: 30,
            uuid: TestUUID.external,
            isOnline: true,
            isActive: true
        )
        let monitor = MacVirtualDisplayMonitor(
            dependencies: system.dependencies(),
            confirmationAttempts: 2,
            confirmationInterval: .zero
        )
        let snapshot = monitor.snapshotBeforeDisconnectionAttempt()
        system.onWait = {
            system.activeDisplayIDs.remove(20)
        }

        let didConfirm = try await monitor.confirmDisconnection(after: snapshot)

        #expect(didConfirm)
        #expect(monitor.learnedDisplayUUID == TestUUID.visionPro)
        #expect(system.storedUUID == TestUUID.visionPro)
        #expect(system.waitCount == 1)
        #expect(!monitor.isConnectedOrReconnected)

        system.installDisplay(
            id: 40,
            uuid: TestUUID.replacementVisionPro,
            isOnline: true,
            isActive: true
        )

        #expect(monitor.isConnectedOrReconnected)
    }

    @Test("an unchanged external display is not learned as Vision Pro")
    func disconnectionDoesNotLearnUnchangedExternalDisplay() async throws {
        let system = TestDisplaySystem()
        system.installDisplay(
            id: 30,
            uuid: TestUUID.external,
            isOnline: true,
            isActive: true
        )
        let monitor = MacVirtualDisplayMonitor(
            dependencies: system.dependencies(),
            confirmationAttempts: 1,
            confirmationInterval: .zero
        )
        let snapshot = monitor.snapshotBeforeDisconnectionAttempt()

        let didConfirm = try await monitor.confirmDisconnection(after: snapshot)

        #expect(!didConfirm)
        #expect(monitor.learnedDisplayUUID == nil)
        #expect(system.storedUUID == nil)
    }

    @Test("a replacement display prevents disconnection confirmation")
    func replacementDisplayPreventsDisconnectionConfirmation() async throws {
        let system = TestDisplaySystem()
        system.installDisplay(
            id: 20,
            uuid: TestUUID.visionPro,
            isOnline: true,
            isActive: true
        )
        system.installDisplay(
            id: 30,
            uuid: TestUUID.external,
            isOnline: true,
            isActive: true
        )
        let monitor = MacVirtualDisplayMonitor(
            dependencies: system.dependencies(),
            confirmationAttempts: 1,
            confirmationInterval: .zero
        )
        let snapshot = monitor.snapshotBeforeDisconnectionAttempt()
        system.activeDisplayIDs.remove(20)
        system.installDisplay(
            id: 40,
            uuid: TestUUID.replacementVisionPro,
            isOnline: true,
            isActive: true
        )

        let didConfirm = try await monitor.confirmDisconnection(after: snapshot)

        #expect(!didConfirm)
        #expect(monitor.learnedDisplayUUID == nil)
        #expect(system.storedUUID == nil)
    }

    @Test("disconnection confirmation times out while the display remains active")
    func disconnectionConfirmationTimesOut() async throws {
        let system = TestDisplaySystem()
        system.storedUUID = TestUUID.visionPro
        system.installDisplay(
            id: 20,
            uuid: TestUUID.visionPro,
            isOnline: true,
            isActive: true
        )
        let monitor = MacVirtualDisplayMonitor(
            dependencies: system.dependencies(),
            confirmationAttempts: 2,
            confirmationInterval: .zero
        )

        let didConfirm = try await monitor.confirmDisconnection()

        #expect(!didConfirm)
        #expect(system.waitCount == 1)
    }

    @Test("null display IDs are rejected before state predicates are called")
    func nullDisplayIDsAreGuarded() {
        let system = TestDisplaySystem()
        system.storedUUID = TestUUID.visionPro
        system.displayIDByUUID[TestUUID.visionPro] = kCGNullDirectDisplay
        system.onlineDisplayIDs = [kCGNullDirectDisplay]
        system.activeDisplayIDs = [kCGNullDirectDisplay]
        let monitor = MacVirtualDisplayMonitor(
            dependencies: system.dependencies()
        )

        #expect(!monitor.isConnected)
        #expect(!monitor.learnAlreadyConnectedDisplayIfUnambiguous())
        #expect(system.statePredicateDisplayIDs.isEmpty)
    }
}

@MainActor
private final class TestDisplaySystem {
    var onlineDisplayIDs: Set<CGDirectDisplayID> = []
    var activeDisplayIDs: Set<CGDirectDisplayID> = []
    var builtInDisplayIDs: Set<CGDirectDisplayID> = []
    var mirroredDisplayIDs: Set<CGDirectDisplayID> = []
    var displayUUIDByID: [CGDirectDisplayID: UUID] = [:]
    var displayIDByUUID: [UUID: CGDirectDisplayID] = [:]
    var storedUUID: UUID?
    var statePredicateDisplayIDs: [CGDirectDisplayID] = []
    var waitCount = 0
    var onWait: (() -> Void)?

    func installDisplay(
        id: CGDirectDisplayID,
        uuid: UUID,
        isOnline: Bool,
        isActive: Bool,
        isBuiltIn: Bool = false,
        isMirrored: Bool = false
    ) {
        displayUUIDByID[id] = uuid
        displayIDByUUID[uuid] = id

        if isOnline {
            onlineDisplayIDs.insert(id)
        }
        if isActive {
            activeDisplayIDs.insert(id)
        }
        if isBuiltIn {
            builtInDisplayIDs.insert(id)
        }
        if isMirrored {
            mirroredDisplayIDs.insert(id)
        }
    }

    func dependencies() -> MacVirtualDisplayMonitor.Dependencies {
        MacVirtualDisplayMonitor.Dependencies(
            onlineDisplayIDs: { self.onlineDisplayIDs },
            activeDisplayIDs: { self.activeDisplayIDs },
            isDisplayOnline: { displayID in
                self.statePredicateDisplayIDs.append(displayID)
                return self.onlineDisplayIDs.contains(displayID)
            },
            isDisplayActive: { displayID in
                self.statePredicateDisplayIDs.append(displayID)
                return self.activeDisplayIDs.contains(displayID)
            },
            isDisplayBuiltIn: { self.builtInDisplayIDs.contains($0) },
            isDisplayMirrored: { self.mirroredDisplayIDs.contains($0) },
            displayUUID: { self.displayUUIDByID[$0] },
            displayID: {
                self.displayIDByUUID[$0] ?? kCGNullDirectDisplay
            },
            loadLearnedDisplayUUID: { self.storedUUID },
            saveLearnedDisplayUUID: { self.storedUUID = $0 },
            wait: { _ in
                self.waitCount += 1
                self.onWait?()
            }
        )
    }
}

private enum TestUUID {
    static let builtIn = UUID(
        uuidString: "00000000-0000-0000-0000-000000000001"
    )!
    static let mirrored = UUID(
        uuidString: "00000000-0000-0000-0000-000000000002"
    )!
    static let inactive = UUID(
        uuidString: "00000000-0000-0000-0000-000000000003"
    )!
    static let offline = UUID(
        uuidString: "00000000-0000-0000-0000-000000000004"
    )!
    static let visionPro = UUID(
        uuidString: "00000000-0000-0000-0000-000000000005"
    )!
    static let external = UUID(
        uuidString: "00000000-0000-0000-0000-000000000006"
    )!
    static let replacementVisionPro = UUID(
        uuidString: "00000000-0000-0000-0000-000000000007"
    )!
}
