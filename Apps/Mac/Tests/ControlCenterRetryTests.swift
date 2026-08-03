import CoreGraphics
import MacDisplayConnectCore
import Testing
@testable import MacDisplayConnect

@Suite("Control Center retry timing")
@MainActor
struct ControlCenterRetryTests {
    @Test("device action uses only modes in the first duplicated group")
    func deviceActionUsesModesFromSelectedDuplicateGroup() {
        let targetID = "screen-mirroring-device-AirPlay:AVP"
        let elements = [
            element(
                index: 9,
                kind: .disclosure,
                identifier: targetID,
                text: ["S’s Apple Vision Pro"],
                isSelected: true
            ),
            element(
                index: 10,
                kind: .checkbox,
                identifier: targetID,
                text: ["Mac Virtual Display"],
                isSelected: true
            ),
            element(
                index: 11,
                identifier: targetID,
                text: ["Move your Mac display to Apple Vision Pro."]
            ),
            element(
                index: 12,
                kind: .checkbox,
                identifier: targetID,
                text: ["Mirror Display"],
                isSelected: false
            ),
            element(
                index: 13,
                kind: .disclosure,
                identifier: targetID,
                text: ["S’s Apple Vision Pro"],
                isSelected: true
            ),
            element(
                index: 14,
                kind: .checkbox,
                identifier: targetID,
                text: ["Mac Virtual Display"],
                isSelected: true
            ),
            element(
                index: 15,
                kind: .checkbox,
                identifier: targetID,
                text: ["Mirror Display"],
                isSelected: false
            ),
        ]

        #expect(
            ControlCenterDeviceActionValidation.modeElementPositions(
                in: elements,
                deviceElementIndex: 9
            ) == [1, 3]
        )
    }

    @Test("device action rejects an unsafe selected mode in its group")
    func deviceActionRejectsUnsafeModeState() {
        let targetID = "screen-mirroring-device-AirPlay:AVP"
        let elements = [
            element(
                index: 9,
                kind: .disclosure,
                identifier: targetID,
                text: ["S’s Apple Vision Pro"],
                isSelected: true
            ),
            element(
                index: 10,
                kind: .checkbox,
                identifier: targetID,
                text: ["Mac Virtual Display"],
                isSelected: true
            ),
            element(
                index: 11,
                kind: .checkbox,
                identifier: targetID,
                text: ["Mirror Display"],
                isSelected: true
            ),
        ]

        #expect(
            ControlCenterDeviceActionValidation.modeElementPositions(
                in: elements,
                deviceElementIndex: 9
            ) == nil
        )
    }

    @Test("device action stops at a conflicting next target header")
    func deviceActionStopsAtConflictingNextHeader() {
        let targetID = "screen-mirroring-device-AirPlay:AVP"
        let elements = [
            element(
                index: 90,
                kind: .disclosure,
                identifier: targetID,
                text: ["S’s Apple Vision Pro"],
                isSelected: true
            ),
            element(
                index: 91,
                kind: .checkbox,
                identifier: targetID,
                text: ["Mac Virtual Display"],
                isSelected: true
            ),
            element(
                index: 92,
                kind: .disclosure,
                identifier: targetID,
                text: ["S’s Apple Vision Pro"],
                isSelected: false
            ),
            element(
                index: 93,
                kind: .checkbox,
                identifier: targetID,
                text: ["Mirror Display"],
                isSelected: false
            ),
        ]

        #expect(
            ControlCenterDeviceActionValidation.modeElementPositions(
                in: elements,
                deviceElementIndex: 90
            ) == [1]
        )
    }

    @Test("device action stays in the header above expanded mode rows")
    func deviceActionStaysAboveExpandedModes() {
        let deviceFrame = CGRect(x: 3_044, y: 138, width: 308, height: 120)
        let modeFrames = [
            CGRect(x: 3_058, y: 180, width: 280, height: 22),
            CGRect(x: 3_058, y: 230, width: 280, height: 22),
        ]

        let point = ControlCenterDeviceActionGeometry.primaryActionPoint(
            deviceFrame: deviceFrame,
            modeFrames: modeFrames
        )

        #expect(point == CGPoint(x: 3_044 + 308.0 / 3.0, y: 159))
        #expect(modeFrames.allSatisfy { $0.contains(point!) == false })
    }

    @Test("device action uses the row center when modes are below its frame")
    func deviceActionUsesStandaloneRowCenter() {
        let deviceFrame = CGRect(x: 1_426, y: 141, width: 280, height: 32)
        let modeFrames = [
            CGRect(x: 1_426, y: 181, width: 280, height: 22),
        ]

        let point = ControlCenterDeviceActionGeometry.primaryActionPoint(
            deviceFrame: deviceFrame,
            modeFrames: modeFrames
        )

        #expect(point == CGPoint(x: 1_426 + 280.0 / 3.0, y: 157))
    }

    @Test("Screen Mirroring can appear after a transient missing scan")
    func screenMirroringAppearsAfterTransientMissingScan() async throws {
        let script = ControlCenterScript(
            scans: [
                [
                    element(
                        index: 4,
                        identifier: "com.apple.menuextra.controlcenter",
                        text: ["Control Center"]
                    ),
                ],
                [
                    element(
                        index: 4,
                        identifier: "com.apple.menuextra.controlcenter",
                        text: ["Control Center"]
                    ),
                ],
                [
                    element(
                        index: 8,
                        kind: .checkbox,
                        identifier: "controlcenter-screen-mirroring",
                        text: ["Screen Mirroring"]
                    ),
                ],
            ]
        )

        try await ControlCenter.openScreenMirroring(
            using: script.automation(maximumAttempts: 3)
        )

        #expect(script.scanCount == 3)
        #expect(
            script.presses
                == [
                    .init(scanIndex: 0, elementIndex: 4),
                    .init(scanIndex: 2, elementIndex: 8),
                ]
        )
        #expect(script.waitCount == 2)
    }

    @Test("Control Center is reopened after two missing-panel scans")
    func controlCenterReopensAfterBackoff() async throws {
        let script = ControlCenterScript(
            scans: [
                [
                    element(
                        index: 4,
                        identifier: "com.apple.menuextra.controlcenter",
                        text: ["Control Center"]
                    ),
                ],
                [
                    element(
                        index: 4,
                        identifier: "com.apple.menuextra.controlcenter",
                        text: ["Control Center"]
                    ),
                ],
                [
                    element(
                        index: 4,
                        identifier: "com.apple.menuextra.controlcenter",
                        text: ["Control Center"]
                    ),
                ],
                [
                    element(
                        index: 8,
                        kind: .checkbox,
                        identifier: "controlcenter-screen-mirroring",
                        text: ["Screen Mirroring"]
                    ),
                ],
            ]
        )

        try await ControlCenter.openScreenMirroring(
            using: script.automation(maximumAttempts: 3)
        )

        #expect(
            script.presses
                == [
                    .init(scanIndex: 0, elementIndex: 4),
                    .init(scanIndex: 2, elementIndex: 4),
                    .init(scanIndex: 3, elementIndex: 8),
                ]
        )
        #expect(script.waitCount == 3)
    }

    @Test("a Vision Pro can become selectable after a transient missing scan")
    func visionProBecomesSelectableAfterTransientMissingScan() async throws {
        let script = ControlCenterScript(
            scans: [
                [],
                [
                    element(
                        index: 9,
                        kind: .checkbox,
                        identifier: "screen-mirroring-device-Sidecar:AVP",
                        text: ["S’s Apple Vision Pro"],
                        isSelected: false
                    ),
                ],
            ]
        )

        let didConnect = try await ControlCenter.connectMacVirtualDisplay(
            visionProName: "S’s Apple Vision Pro",
            using: script.automation(maximumAttempts: 3)
        )

        #expect(didConnect)
        #expect(script.scanCount == 2)
        #expect(
            script.presses
                == [.init(scanIndex: 1, elementIndex: 9)]
        )
        #expect(script.waitCount == 1)
    }

    @Test("connection waits for delayed requested Vision Pro readiness")
    func connectionWaitsForDelayedRequestedVisionProReadiness() async throws {
        let waitingForDevice = [
            element(
                index: 3,
                identifier: "screen-mirroring-header",
                text: ["Screen Mirroring"]
            ),
        ]
        let script = ControlCenterScript(
            scans: [
                waitingForDevice,
                waitingForDevice,
                waitingForDevice,
                waitingForDevice,
                [
                    element(
                        index: 9,
                        kind: .checkbox,
                        identifier: "screen-mirroring-device-Sidecar:AVP",
                        text: ["S’s Apple Vision Pro"],
                        isSelected: false
                    ),
                ],
            ]
        )

        let didConnect = try await ControlCenter.connectMacVirtualDisplay(
            visionProName: "S’s Apple Vision Pro",
            using: script.automation(
                maximumAttempts: 3,
                connectionReadinessAttempts: 5
            )
        )

        #expect(didConnect)
        #expect(script.scanCount == 5)
        #expect(
            script.presses == [.init(scanIndex: 4, elementIndex: 9)]
        )
        #expect(script.waitCount == 4)
    }

    @Test("connection does not toggle an unchanged AirPlay row twice")
    func connectionDoesNotRepeatAirPlayRowAction() async throws {
        let targetID = "screen-mirroring-device-AirPlay:AVP"
        let collapsedRow = element(
            index: 9,
            kind: .checkbox,
            identifier: targetID,
            text: ["S’s Apple Vision Pro"],
            isSelected: false
        )
        let script = ControlCenterScript(
            scans: [
                [collapsedRow],
                [collapsedRow],
                [
                    element(
                        index: 9,
                        kind: .disclosure,
                        identifier: targetID,
                        text: ["S’s Apple Vision Pro"],
                        isSelected: true
                    ),
                    element(
                        index: 10,
                        kind: .checkbox,
                        identifier: targetID,
                        text: ["Mac Virtual Display"],
                        isSelected: false
                    ),
                    element(
                        index: 11,
                        kind: .checkbox,
                        identifier: targetID,
                        text: ["Mirror Display"],
                        isSelected: false
                    ),
                ],
            ]
        )

        let didConnect = try await ControlCenter.connectMacVirtualDisplay(
            visionProName: "S’s Apple Vision Pro",
            using: script.automation(maximumAttempts: 3)
        )

        #expect(didConnect)
        #expect(
            script.presses
                == [
                    .init(scanIndex: 0, elementIndex: 9),
                    .init(scanIndex: 2, elementIndex: 10),
                ]
        )
        #expect(script.waitCount == 2)
    }

    @Test("connection reopens Screen Mirroring after its panel disappears")
    func connectionReopensMissingScreenMirroringPanel() async throws {
        let script = ControlCenterScript(
            scans: [
                [
                    element(
                        index: 4,
                        identifier: "com.apple.menuextra.controlcenter",
                        text: ["Control Center"]
                    ),
                ],
                [
                    element(
                        index: 8,
                        kind: .checkbox,
                        identifier: "controlcenter-screen-mirroring",
                        text: ["Screen Mirroring"]
                    ),
                ],
                [
                    element(
                        index: 9,
                        kind: .checkbox,
                        identifier: "screen-mirroring-device-Sidecar:AVP",
                        text: ["S’s Apple Vision Pro"],
                        isSelected: false
                    ),
                ],
            ]
        )

        let didConnect = try await ControlCenter.connectMacVirtualDisplay(
            visionProName: "S’s Apple Vision Pro",
            using: script.automation(maximumAttempts: 3)
        )

        #expect(didConnect)
        #expect(
            script.presses
                == [
                    .init(scanIndex: 0, elementIndex: 4),
                    .init(scanIndex: 1, elementIndex: 8),
                    .init(scanIndex: 2, elementIndex: 9),
                ]
        )
        #expect(script.waitCount == 2)
    }

    @Test("disconnect activates the selected Vision Pro device row")
    func disconnectActivatesVisionProDeviceRow() async throws {
        let targetID = "screen-mirroring-device-AirPlay:AVP"
        let script = ControlCenterScript(
            scans: [
                [
                    element(
                        index: 9,
                        kind: .disclosure,
                        identifier: targetID,
                        text: ["S’s Apple Vision Pro"],
                        isSelected: true
                    ),
                    element(
                        index: 10,
                        kind: .checkbox,
                        identifier: targetID,
                        text: ["Mac Virtual Display"],
                        isSelected: true
                    ),
                    element(
                        index: 11,
                        kind: .checkbox,
                        identifier: targetID,
                        text: ["Mirror Display"],
                        isSelected: false
                    ),
                ],
            ]
        )

        let didDisconnect = try await ControlCenter.disconnectMacVirtualDisplay(
            visionProName: "S’s Apple Vision Pro",
            using: script.automation(maximumAttempts: 3)
        )

        #expect(didDisconnect)
        #expect(script.presses.isEmpty)
        #expect(
            script.devicePrimaryActions
                == [.init(scanIndex: 0, elementIndex: 9)]
        )
        #expect(script.waitCount == 0)
    }

    @Test("disconnect expands a collapsed Vision Pro before activating its row")
    func disconnectExpandsCollapsedVisionPro() async throws {
        let targetID = "screen-mirroring-device-AirPlay:AVP"
        let script = ControlCenterScript(
            scans: [
                [
                    element(
                        index: 9,
                        kind: .disclosure,
                        identifier: targetID,
                        text: ["S’s Apple Vision Pro"],
                        isSelected: false
                    ),
                ],
                [
                    element(
                        index: 9,
                        kind: .disclosure,
                        identifier: targetID,
                        text: ["S’s Apple Vision Pro"],
                        isSelected: true
                    ),
                    element(
                        index: 10,
                        kind: .checkbox,
                        identifier: targetID,
                        text: ["Mac Virtual Display"],
                        isSelected: true
                    ),
                    element(
                        index: 11,
                        kind: .checkbox,
                        identifier: targetID,
                        text: ["Mirror Display"],
                        isSelected: false
                    ),
                ],
            ]
        )

        let didDisconnect = try await ControlCenter.disconnectMacVirtualDisplay(
            visionProName: "S’s Apple Vision Pro",
            using: script.automation(maximumAttempts: 3)
        )

        #expect(didDisconnect)
        #expect(
            script.presses
                == [
                    .init(scanIndex: 0, elementIndex: 9),
                ]
        )
        #expect(
            script.devicePrimaryActions
                == [.init(scanIndex: 1, elementIndex: 9)]
        )
        #expect(script.waitCount == 1)
    }

    @Test("disconnect presses a selected Sidecar device directly")
    func disconnectPressesSelectedSidecarDevice() async throws {
        let script = ControlCenterScript(
            scans: [
                [
                    element(
                        index: 9,
                        kind: .checkbox,
                        identifier: "screen-mirroring-device-Sidecar:AVP",
                        text: ["S’s Apple Vision Pro"],
                        isSelected: true
                    ),
                ],
            ]
        )

        let didDisconnect = try await ControlCenter.disconnectMacVirtualDisplay(
            visionProName: "S’s Apple Vision Pro",
            using: script.automation(maximumAttempts: 3)
        )

        #expect(didDisconnect)
        #expect(
            script.presses == [.init(scanIndex: 0, elementIndex: 9)]
        )
        #expect(script.devicePrimaryActions.isEmpty)
    }

    @Test("disconnect leaves an already disconnected display unchanged")
    func disconnectLeavesDisconnectedDisplayUnchanged() async throws {
        let targetID = "screen-mirroring-device-AirPlay:AVP"
        let script = ControlCenterScript(
            scans: [
                [
                    element(
                        index: 9,
                        kind: .disclosure,
                        identifier: targetID,
                        text: ["S’s Apple Vision Pro"]
                    ),
                    element(
                        index: 10,
                        kind: .checkbox,
                        identifier: targetID,
                        text: ["Mac Virtual Display"],
                        isSelected: false
                    ),
                ],
            ]
        )

        let didDisconnect = try await ControlCenter.disconnectMacVirtualDisplay(
            visionProName: "S’s Apple Vision Pro",
            using: script.automation(maximumAttempts: 3)
        )

        #expect(!didDisconnect)
        #expect(script.presses.isEmpty)
        #expect(script.waitCount == 0)
    }

    @Test("permanently absent Screen Mirroring fails after bounded retries")
    func permanentlyAbsentScreenMirroringFailsAfterBoundedRetries() async {
        let script = ControlCenterScript(
            scans: [
                [
                    element(
                        index: 4,
                        identifier: "com.apple.menuextra.controlcenter",
                        text: ["Control Center"]
                    ),
                ],
                [
                    element(
                        index: 4,
                        identifier: "com.apple.menuextra.controlcenter",
                        text: ["Control Center"]
                    ),
                ],
                [
                    element(
                        index: 4,
                        identifier: "com.apple.menuextra.controlcenter",
                        text: ["Control Center"]
                    ),
                ],
                [
                    element(
                        index: 4,
                        identifier: "com.apple.menuextra.controlcenter",
                        text: ["Control Center"]
                    ),
                ],
            ]
        )

        do {
            try await ControlCenter.openScreenMirroring(
                using: script.automation(maximumAttempts: 3)
            )
            Issue.record("Expected Screen Mirroring lookup to fail.")
        } catch MacDisplayConnectError.screenMirroringControlNotFound {
            #expect(script.scanCount == 4)
            #expect(
                script.presses
                    == [
                        .init(scanIndex: 0, elementIndex: 4),
                        .init(scanIndex: 2, elementIndex: 4),
                    ]
            )
            #expect(script.waitCount == 3)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("an unrelated AX window does not suppress reopening Control Center")
    func unrelatedWindowDoesNotSuppressControlCenterReopen() async throws {
        let script = ControlCenterScript(
            scans: [
                [
                    element(index: 0, text: ["Unrelated window"]),
                    element(
                        index: 4,
                        identifier: "com.apple.menuextra.controlcenter",
                        text: ["Control Center"]
                    ),
                ],
                [
                    element(
                        index: 8,
                        kind: .checkbox,
                        identifier: "controlcenter-screen-mirroring",
                        text: ["Screen Mirroring"]
                    ),
                ],
            ],
            windowElementIndices: [[0], []]
        )

        try await ControlCenter.openScreenMirroring(
            using: script.automation(maximumAttempts: 1)
        )

        #expect(
            script.presses
                == [
                    .init(scanIndex: 0, elementIndex: 4),
                    .init(scanIndex: 1, elementIndex: 8),
                ]
        )
        #expect(script.waitCount == 1)
    }

    @Test("connection cleanup leaves a naturally closed popover untouched")
    func connectionCleanupLeavesClosedPopoverUntouched() async {
        let script = ControlCenterScript(
            scans: [
                [
                    element(
                        index: 4,
                        identifier: "com.apple.menuextra.controlcenter",
                        text: ["Control Center"]
                    ),
                    element(
                        index: 5,
                        identifier: "com.apple.menuextra.screen-mirroring",
                        text: ["Screen Mirroring"]
                    ),
                ],
            ]
        )

        await ControlCenter.dismissScreenMirroringIfStillOpen(
            using: script.automation(maximumAttempts: 1)
        )

        #expect(script.waitCount == 1)
        #expect(script.scanCount == 1)
        #expect(script.presses.isEmpty)
        #expect(script.controlCenterDismissalCount == 0)
    }

    @Test("connection cleanup dismisses a popover still open after its grace period")
    func connectionCleanupDismissesOpenPopover() async {
        let script = ControlCenterScript(
            scans: [
                [
                    element(
                        index: 3,
                        identifier: "screen-mirroring-header",
                        text: ["Screen Mirroring"]
                    ),
                    element(
                        index: 4,
                        identifier: "com.apple.menuextra.controlcenter",
                        text: ["Control Center"]
                    ),
                ],
            ]
        )

        await ControlCenter.dismissScreenMirroringIfStillOpen(
            using: script.automation(maximumAttempts: 1)
        )

        #expect(script.waitCount == 1)
        #expect(script.scanCount == 1)
        #expect(script.presses.isEmpty)
        #expect(script.controlCenterDismissalCount == 1)
    }

    @Test("connection cleanup dismisses the Control Center main popover")
    func connectionCleanupDismissesOpenControlCenter() async {
        let script = ControlCenterScript(
            scans: [
                [
                    element(
                        index: 4,
                        identifier: "com.apple.menuextra.controlcenter",
                        text: ["Control Center"]
                    ),
                    element(
                        index: 8,
                        kind: .checkbox,
                        identifier: "controlcenter-screen-mirroring",
                        text: ["Screen Mirroring"]
                    ),
                ],
            ]
        )

        await ControlCenter.dismissScreenMirroringIfStillOpen(
            using: script.automation(maximumAttempts: 1)
        )

        #expect(script.waitCount == 1)
        #expect(script.scanCount == 1)
        #expect(script.presses.isEmpty)
        #expect(script.controlCenterDismissalCount == 1)
    }

    @Test("permanently absent Vision Pro fails after bounded retries")
    func permanentlyAbsentVisionProFailsAfterBoundedRetries() async {
        let script = ControlCenterScript(scans: [[], [], []])

        do {
            _ = try await ControlCenter.connectMacVirtualDisplay(
                visionProName: "S’s Apple Vision Pro",
                using: script.automation(maximumAttempts: 3)
            )
            Issue.record("Expected Vision Pro lookup to fail.")
        } catch MacDisplayConnectError.visionProControlNotFound {
            #expect(script.scanCount == 3)
            #expect(script.presses.isEmpty)
            #expect(script.waitCount == 2)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}

@MainActor
private final class ControlCenterScript {
    private let scans: [[ControlCenterElement]]
    private let windowElementIndices: [Set<Int>]
    private var nextScanIndex = 0

    private(set) var presses: [ControlCenterPress] = []
    private(set) var devicePrimaryActions: [ControlCenterPress] = []
    private(set) var controlCenterDismissalCount = 0
    private(set) var waitCount = 0

    var scanCount: Int {
        nextScanIndex
    }

    init(
        scans: [[ControlCenterElement]],
        windowElementIndices: [[Int]] = []
    ) {
        self.scans = scans
        self.windowElementIndices = windowElementIndices.map(Set.init)
    }

    func automation(
        maximumAttempts: Int,
        connectionReadinessAttempts: Int? = nil
    ) -> ControlCenterAutomation {
        ControlCenterAutomation(
            maximumAttempts: maximumAttempts,
            connectionReadinessAttempts: connectionReadinessAttempts,
            scan: { [self] in
                try nextScan()
            },
            wait: { [self] in
                waitCount += 1
            }
        )
    }

    private func nextScan() throws -> ControlCenterScan {
        guard scans.indices.contains(nextScanIndex) else {
            throw UnexpectedControlCenterScan()
        }

        let scanIndex = nextScanIndex
        let snapshots = scans[nextScanIndex]
        let windows = windowElementIndices.indices.contains(nextScanIndex)
            ? windowElementIndices[nextScanIndex]
            : []
        nextScanIndex += 1

        return ControlCenterScan(
            snapshots: snapshots,
            isWindow: { windows.contains($0) },
            press: { [self] index in
                presses.append(
                    ControlCenterPress(
                        scanIndex: scanIndex,
                        elementIndex: index
                    )
                )
            },
            dismissControlCenter: { [self] in
                controlCenterDismissalCount += 1
            },
            activateDevicePrimaryAction: { [self] index in
                devicePrimaryActions.append(
                    ControlCenterPress(
                        scanIndex: scanIndex,
                        elementIndex: index
                    )
                )
            }
        )
    }
}

private struct ControlCenterPress: Equatable {
    let scanIndex: Int
    let elementIndex: Int
}

private struct UnexpectedControlCenterScan: Error {}

private func element(
    index: Int,
    kind: ControlCenterElement.Kind = .other,
    identifier: String? = nil,
    text: [String] = [],
    isSelected: Bool? = nil
) -> ControlCenterElement {
    ControlCenterElement(
        index: index,
        kind: kind,
        identifier: identifier,
        text: text,
        isSelected: isSelected
    )
}
