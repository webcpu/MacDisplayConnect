import Testing
@testable import MacDisplayConnectCore

@Suite("Control Center action planning")
struct ControlCenterPlannerTests {
    @Test("conflicting duplicate headers cannot impersonate a mode")
    func rejectsConflictingHeadersWhoseNameMatchesMode() {
        let targetID = "screen-mirroring-device-AirPlay:AVP"
        let elements = [true, false].enumerated().map { index, selected in
            element(
                index: 9 + index,
                kind: .checkbox,
                identifier: targetID,
                text: ["Mac Virtual Display"],
                isSelected: selected
            )
        }

        #expect(
            ControlCenterPlanner.action(
                for: elements,
                visionProIdentifiers: [targetID]
            ) == .visionProNotFound
        )
    }

    @Test(
        "a collapsed headset named Mac Virtual Display is still a device header",
        arguments: [1, 2]
    )
    func expandsHeadsetWhoseNameMatchesMode(duplicateCount: Int) {
        let targetID = "screen-mirroring-device-AirPlay:AVP"
        let elements = (0..<duplicateCount).map {
            element(
                index: 9 + $0,
                kind: .checkbox,
                identifier: targetID,
                text: ["Mac Virtual Display"],
                isSelected: false
            )
        }

        #expect(
            ControlCenterPlanner.action(
                for: elements,
                visionProIdentifiers: [targetID]
            ) == .expandVisionPro(elementIndex: 9)
        )
    }

    @Test("the first device header is not mistaken for its identically named mode")
    func selectsModeAfterIdenticallyNamedHeader() {
        let targetID = "screen-mirroring-device-AirPlay:AVP"
        let elements = [
            element(
                index: 9,
                kind: .checkbox,
                identifier: targetID,
                text: ["Mac Virtual Display"],
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
        ]

        #expect(
            ControlCenterPlanner.action(
                for: elements,
                visionProIdentifiers: [targetID]
            ) == .selectMacVirtualDisplay(elementIndex: 10)
        )
    }

    @Test("opens Control Center when the pinned Screen Mirroring label is hidden")
    func opensControlCenterFallback() {
        let elements = [
            element(
                index: 4,
                kind: .other,
                identifier: "com.apple.menuextra.controlcenter",
                text: ["Control Center"]
            ),
            element(index: 5, kind: .other),
        ]

        #expect(
            ControlCenterNavigationPlanner.action(for: elements)
                == .openControlCenter(elementIndex: 4)
        )
    }

    @Test("opens Screen Mirroring by its stable Control Center identifier")
    func opensScreenMirroringModule() {
        let elements = [
            element(
                index: 8,
                kind: .checkbox,
                identifier: "controlcenter-screen-mirroring",
                text: ["Screen\nMirroring"]
            ),
        ]

        #expect(
            ControlCenterNavigationPlanner.action(for: elements)
                == .openScreenMirroring(elementIndex: 8)
        )
    }

    @Test("recognizes the open Screen Mirroring panel by its header")
    func recognizesOpenScreenMirroringPanel() {
        let elements = [
            element(
                index: 3,
                kind: .other,
                identifier: "screen-mirroring-header",
                text: ["Screen Mirroring"]
            ),
            element(
                index: 17,
                kind: .other,
                identifier: "com.apple.menuextra.controlcenter",
                text: ["Control Center"]
            ),
        ]

        #expect(
            ControlCenterNavigationPlanner.action(for: elements)
                == .screenMirroringAlreadyOpen
        )
    }

    @Test("reopens Control Center when a stale Screen Mirroring panel is open")
    func reopensControlCenterFromStaleScreenMirroringPanel() {
        let elements = [
            element(
                index: 1,
                kind: .other,
                text: ["Screen Mirroring shield"]
            ),
            element(
                index: 10,
                kind: .other,
                identifier: "com.apple.menuextra.controlcenter",
                text: ["Control Center"]
            ),
            element(
                index: 20,
                kind: .other,
                identifier: "com.apple.menuextra.screen-mirroring",
                text: ["Screen Mirroring"]
            ),
        ]

        #expect(
            ControlCenterNavigationPlanner.action(for: elements)
                == .openControlCenter(elementIndex: 10)
        )
    }

    @Test("expands the Vision Pro device when its choices are collapsed")
    func expandsVisionProDevice() {
        let elements = [
            element(index: 0, kind: .other, text: ["Screen Mirroring"]),
            element(
                index: 1,
                kind: .disclosure,
                identifier: "screen-mirroring-device-AirPlay:AVP",
                text: ["Apple Vision Pro"]
            ),
        ]

        #expect(
            ControlCenterPlanner.action(
                for: elements,
                visionProIdentifiers: ["screen-mirroring-device-AirPlay:AVP"]
            ) == .expandVisionPro(elementIndex: 1)
        )
    }

    @Test("automatic selection does not guess from unlabeled AirPlay rows")
    func rejectsUnlabeledAirPlayRows() {
        let elements = [
            element(
                index: 8,
                kind: .checkbox,
                identifier: "screen-mirroring-device-Sidecar:IPAD"
            ),
            element(
                index: 9,
                kind: .checkbox,
                identifier: "screen-mirroring-device-AirPlay:TV",
                text: ["TV"]
            ),
            element(
                index: 10,
                kind: .checkbox,
                identifier: "screen-mirroring-device-AirPlay:VISION-PRO"
            ),
        ]

        #expect(
            ControlCenterPlanner.action(for: elements)
                == .visionProNotFound
        )
    }

    @Test("selects Mac Virtual Display instead of Mirror Display")
    func selectsMacVirtualDisplay() {
        let targetID = "screen-mirroring-device-AirPlay:AVP"
        let elements = [
            element(
                index: 2,
                kind: .disclosure,
                identifier: targetID,
                text: ["S’s Apple Vision Pro"]
            ),
            element(
                index: 3,
                kind: .checkbox,
                identifier: targetID,
                text: ["Mac Virtual Display"],
                isSelected: false
            ),
            element(
                index: 4,
                kind: .other,
                identifier: targetID,
                text: [
                    "Move your Mac display to Apple Vision Pro and expand your setup.",
                ]
            ),
            element(
                index: 5,
                kind: .checkbox,
                identifier: targetID,
                isSelected: true
            ),
        ]

        #expect(
            ControlCenterPlanner.action(
                for: elements,
                visionProIdentifiers: [targetID]
            ) == .selectMacVirtualDisplay(elementIndex: 3)
        )
    }

    @Test("expands a trusted custom-named AirPlay Vision Pro among unrelated devices")
    func expandsTrustedAirPlayVisionPro() {
        let elements = [
            element(
                index: 8,
                kind: .checkbox,
                identifier: "screen-mirroring-device-Sidecar:IPAD",
                text: ["ipad1"],
                isSelected: false
            ),
            element(
                index: 9,
                kind: .checkbox,
                identifier: "screen-mirroring-device-AirPlay:AVP",
                text: ["avp\u{00A0}"],
                isSelected: false
            ),
            element(
                index: 10,
                kind: .checkbox,
                identifier: "screen-mirroring-device-AirPlay:TV",
                text: ["TV"],
                isSelected: false
            ),
            element(
                index: 11,
                kind: .checkbox,
                identifier: "screen-mirroring-device-AirPlay:LIVING-ROOM",
                text: ["Living Room"],
                isSelected: false
            ),
        ]

        #expect(
            ControlCenterPlanner.action(
                for: elements,
                visionProIdentifiers: ["screen-mirroring-device-AirPlay:AVP"]
            ) == .expandVisionPro(elementIndex: 9)
        )
    }

    @Test("treats identical AirPlay rows as one Vision Pro")
    func expandsDuplicateAirPlayRepresentations() {
        let visionProID =
            "screen-mirroring-device-AirPlay:VISION-PRO"
        let elements = [
            element(
                index: 8,
                kind: .checkbox,
                identifier: "screen-mirroring-device-Sidecar:IPAD",
                text: ["ipad1"],
                isSelected: false
            ),
            element(
                index: 9,
                kind: .checkbox,
                identifier: visionProID,
                text: ["S’s Apple Vision Pro"],
                isSelected: false
            ),
            element(
                index: 10,
                kind: .checkbox,
                identifier: visionProID,
                text: ["S’s Apple Vision Pro"],
                isSelected: false
            ),
            element(
                index: 11,
                kind: .checkbox,
                identifier: "screen-mirroring-device-AirPlay:TV",
                text: ["TV"],
                isSelected: false
            ),
            element(
                index: 12,
                kind: .checkbox,
                identifier: "screen-mirroring-device-AirPlay:LIVING-ROOM",
                text: ["Living Room"],
                isSelected: false
            ),
        ]

        #expect(
            ControlCenterPlanner.action(
                for: elements,
                visionProIdentifiers: [visionProID]
            ) == .expandVisionPro(elementIndex: 9)
        )
    }

    @Test("selects the explicitly labeled Mac Virtual Display child")
    func selectsLabeledMacVirtualDisplayChild() {
        let targetID = "screen-mirroring-device-AirPlay:AVP"
        let elements = [
            element(
                index: 9,
                kind: .checkbox,
                identifier: targetID,
                text: ["S’s Apple\u{00A0}Vision\u{00A0}Pro"],
                isSelected: false
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
                identifier: "screen-mirroring-device-AirPlay:TV",
                text: ["TV"],
                isSelected: false
            ),
        ]

        #expect(
            ControlCenterPlanner.action(
                for: elements,
                visionProIdentifiers: [targetID]
            ) == .selectMacVirtualDisplay(elementIndex: 10)
        )
    }

    @Test("selects Mac Virtual Display when Control Center duplicates the group")
    func selectsMacVirtualDisplayFromDuplicateGroups() {
        let targetID = "screen-mirroring-device-AirPlay:AVP"
        let elements = [
            element(
                index: 8,
                kind: .disclosure,
                identifier: targetID,
                text: ["S’s Apple Vision Pro"],
                isSelected: true
            ),
            element(
                index: 9,
                kind: .checkbox,
                identifier: targetID,
                text: ["Mac Virtual Display"],
                isSelected: false
            ),
            element(
                index: 11,
                kind: .checkbox,
                identifier: targetID,
                text: ["Mirror Built-in Liquid Retina XDR Display"],
                isSelected: true
            ),
            element(
                index: 12,
                kind: .disclosure,
                identifier: targetID,
                text: ["S’s Apple Vision Pro"],
                isSelected: true
            ),
            element(
                index: 13,
                kind: .checkbox,
                identifier: targetID,
                text: ["Mac Virtual Display"],
                isSelected: false
            ),
            element(
                index: 15,
                kind: .checkbox,
                identifier: targetID,
                text: ["Mirror Built-in Liquid Retina XDR Display"],
                isSelected: true
            ),
        ]

        #expect(
            ControlCenterPlanner.action(
                for: elements,
                visionProIdentifiers: [targetID]
            ) == .selectMacVirtualDisplay(elementIndex: 9)
        )
    }

    @Test(
        "trusted AirPlay device selection ignores arbitrary, empty, and renamed labels",
        arguments: ["avp", "", "Renamed headset"]
    )
    func selectsTrustedAirPlayRegardlessOfLabel(label: String) {
        let targetID = "screen-mirroring-device-AirPlay:AVP"
        let elements = [
            element(
                index: 9,
                kind: .checkbox,
                identifier: targetID,
                text: [label],
                isSelected: false
            ),
        ]

        #expect(
            ControlCenterPlanner.action(
                for: elements,
                visionProIdentifiers: [targetID]
            ) == .expandVisionPro(elementIndex: 9)
        )
    }

    @Test("does not guess when multiple trusted Vision Pros are present")
    func rejectsMultipleTrustedVisionPros() {
        let elements = [
            element(
                index: 8,
                kind: .checkbox,
                identifier: "screen-mirroring-device-Sidecar:ONE",
                text: ["avp"],
                isSelected: false
            ),
            element(
                index: 9,
                kind: .checkbox,
                identifier: "screen-mirroring-device-Sidecar:TWO",
                text: ["Work headset"],
                isSelected: false
            ),
        ]

        #expect(
            ControlCenterPlanner.action(
                for: elements,
                visionProIdentifiers: [
                    "screen-mirroring-device-Sidecar:ONE",
                    "screen-mirroring-device-Sidecar:TWO",
                ]
            ) == .visionProNotFound
        )
    }

    @Test("empty discovery does not fall back to an Apple Vision Pro label")
    func rejectsVisionProLabelWithoutDiscovery() {
        let elements = [
            element(
                index: 9,
                kind: .checkbox,
                identifier: "screen-mirroring-device-Sidecar:AVP",
                text: ["Apple Vision Pro"],
                isSelected: false
            ),
        ]

        #expect(
            ControlCenterPlanner.action(
                for: elements,
                visionProIdentifiers: []
            ) == .visionProNotFound
        )
    }

    @Test("a misleading Apple Vision Pro label cannot authorize an unrelated AirPlay row")
    func rejectsMisleadingVisionProLabel() {
        let elements = [
            element(
                index: 10,
                kind: .checkbox,
                identifier: "screen-mirroring-device-AirPlay:TV",
                text: ["Apple Vision Pro"],
                isSelected: false
            ),
        ]

        #expect(
            ControlCenterPlanner.action(
                for: elements,
                visionProIdentifiers: ["screen-mirroring-device-AirPlay:AVP"]
            ) == .visionProNotFound
        )
    }

    @Test("either known transport alias works when it is the only alias present")
    func selectsOnlyPresentTransportAlias() {
        let airPlayID = "screen-mirroring-device-AirPlay:AVP"
        let sidecarID = "screen-mirroring-device-Sidecar:AVP"
        let cases: [(String, ControlCenterAction)] = [
            (airPlayID, .expandVisionPro(elementIndex: 9)),
            (sidecarID, .selectMacVirtualDisplay(elementIndex: 9)),
        ]

        for (identifier, expectedAction) in cases {
            let elements = [
                element(
                    index: 9,
                    kind: .checkbox,
                    identifier: identifier,
                    isSelected: false
                ),
            ]

            #expect(
                ControlCenterPlanner.action(
                    for: elements,
                    visionProIdentifiers: [airPlayID, sidecarID]
                ) == expectedAction
            )
        }
    }

    @Test("selects a trusted Sidecar Vision Pro without using its label")
    func selectsTrustedSidecarVisionPro() {
        let elements = [
            element(
                index: 9,
                kind: .checkbox,
                identifier: "screen-mirroring-device-Sidecar:AVP",
                text: ["avp"],
                isSelected: false
            ),
            element(
                index: 10,
                kind: .checkbox,
                identifier: "screen-mirroring-device-AirPlay:TV",
                text: ["TV"],
                isSelected: false
            ),
        ]

        #expect(
            ControlCenterPlanner.action(
                for: elements,
                visionProIdentifiers: ["screen-mirroring-device-Sidecar:AVP"]
            ) == .selectMacVirtualDisplay(elementIndex: 9)
        )
    }

    @Test("leaves the trusted Vision Pro alone when it is already connected")
    func leavesTrustedVisionProConnected() {
        let elements = [
            element(
                index: 9,
                kind: .checkbox,
                identifier: "screen-mirroring-device-Sidecar:AVP",
                text: ["S’s Apple\u{00A0}Vision\u{00A0}Pro"],
                isSelected: true
            ),
        ]

        #expect(
            ControlCenterPlanner.action(
                for: elements,
                visionProIdentifiers: ["screen-mirroring-device-Sidecar:AVP"]
            ) == .alreadyConnected
        )
    }

    @Test("does not select another device when the trusted Vision Pro is absent")
    func rejectsMissingTrustedVisionPro() {
        let elements = [
            element(
                index: 9,
                kind: .checkbox,
                identifier: "screen-mirroring-device-Sidecar:OTHER",
                text: ["Other Apple Vision Pro"],
                isSelected: false
            ),
            element(
                index: 10,
                kind: .checkbox,
                identifier: "screen-mirroring-device-AirPlay:TV",
                text: ["TV"],
                isSelected: false
            ),
        ]

        #expect(
            ControlCenterPlanner.action(
                for: elements,
                visionProIdentifiers: ["screen-mirroring-device-Sidecar:AVP"]
            ) == .visionProNotFound
        )
    }

    @Test("identical labels do not make two trusted IDs one device")
    func rejectsDistinctTrustedIDsWithIdenticalLabels() {
        let elements = [
            element(
                index: 8,
                kind: .checkbox,
                identifier: "screen-mirroring-device-Sidecar:ONE",
                text: ["Shared Apple Vision Pro"],
                isSelected: false
            ),
            element(
                index: 9,
                kind: .checkbox,
                identifier: "screen-mirroring-device-Sidecar:TWO",
                text: ["Shared Apple Vision Pro"],
                isSelected: false
            ),
        ]

        #expect(
            ControlCenterPlanner.action(
                for: elements,
                visionProIdentifiers: [
                    "screen-mirroring-device-Sidecar:ONE",
                    "screen-mirroring-device-Sidecar:TWO",
                ]
            ) == .visionProNotFound
        )
    }

    @Test("fails closed when duplicate rows do not label Mac Virtual Display")
    func rejectsUnlabeledDuplicateAirPlayRows() {
        let targetID = "screen-mirroring-device-AirPlay:VISION-PRO"
        let elements = [
            element(
                index: 8,
                kind: .checkbox,
                identifier: targetID,
                text: ["S’s Apple Vision Pro"],
                isSelected: false
            ),
            element(
                index: 9,
                kind: .checkbox,
                identifier: targetID,
                isSelected: false
            ),
        ]

        #expect(
            ControlCenterPlanner.action(
                for: elements,
                visionProIdentifiers: [targetID]
            ) == .visionProNotFound
        )
    }

    @Test("does nothing when Mac Virtual Display is already selected")
    func leavesConnectedVisionProAlone() {
        let targetID = "screen-mirroring-device-AirPlay:AVP"
        let elements = [
            element(
                index: 2,
                kind: .disclosure,
                identifier: targetID,
                text: ["S’s Apple Vision Pro"]
            ),
            element(
                index: 3,
                kind: .checkbox,
                identifier: targetID,
                text: ["Mac Virtual Display"],
                isSelected: true
            ),
            element(
                index: 4,
                kind: .other,
                identifier: targetID,
                text: [
                    "Move your Mac display to Apple Vision Pro and expand your setup.",
                ]
            ),
            element(
                index: 5,
                kind: .checkbox,
                identifier: targetID,
                isSelected: false
            ),
        ]

        #expect(
            ControlCenterPlanner.action(
                for: elements,
                visionProIdentifiers: [targetID]
            ) == .alreadyConnected
        )
    }

    @Test("ignores a Sidecar-only device list")
    func ignoresSidecarOnlyDeviceList() {
        let elements = [
            element(
                index: 1,
                kind: .checkbox,
                identifier: "screen-mirroring-device-Sidecar:IPAD",
                text: ["iPad"]
            ),
        ]

        #expect(
            ControlCenterPlanner.action(
                for: elements,
                visionProIdentifiers: ["screen-mirroring-device-Sidecar:AVP"]
            ) == .visionProNotFound
        )
    }

    @Test("does not guess when multiple trusted expandable devices are present")
    func rejectsAmbiguousExpandableDevices() {
        let elements = [
            element(
                index: 1,
                kind: .disclosure,
                identifier: "screen-mirroring-device-AirPlay:ONE"
            ),
            element(
                index: 2,
                kind: .disclosure,
                identifier: "screen-mirroring-device-AirPlay:TWO"
            ),
        ]

        #expect(
            ControlCenterPlanner.action(
                for: elements,
                visionProIdentifiers: [
                    "screen-mirroring-device-AirPlay:ONE",
                    "screen-mirroring-device-AirPlay:TWO",
                ]
            ) == .visionProNotFound
        )
    }

    @Test("simultaneous trusted transport aliases remain ambiguous")
    func rejectsSimultaneousTransportAliases() {
        let airPlayID = "screen-mirroring-device-AirPlay:AVP"
        let sidecarID = "screen-mirroring-device-Sidecar:AVP"
        let elements = [
            element(
                index: 8,
                kind: .checkbox,
                identifier: airPlayID,
                text: ["avp"],
                isSelected: false
            ),
            element(
                index: 9,
                kind: .checkbox,
                identifier: sidecarID,
                text: ["avp"],
                isSelected: false
            ),
        ]

        #expect(
            ControlCenterPlanner.action(
                for: elements,
                visionProIdentifiers: [airPlayID, sidecarID]
            ) == .visionProNotFound
        )
    }

    @Test("non-actionable trusted metadata does not make another device ambiguous")
    func ignoresNonActionableTrustedAlias() {
        let airPlayID = "screen-mirroring-device-AirPlay:AVP"
        let sidecarID = "screen-mirroring-device-Sidecar:AVP"
        let elements = [
            element(index: 8, kind: .other, identifier: airPlayID),
            element(
                index: 9,
                kind: .checkbox,
                identifier: sidecarID,
                isSelected: false
            ),
        ]

        #expect(
            ControlCenterPlanner.action(
                for: elements,
                visionProIdentifiers: [airPlayID, sidecarID]
            ) == .selectMacVirtualDisplay(elementIndex: 9)
        )
    }

    private func element(
        index: Int,
        kind: ControlCenterElement.Kind,
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
}
