import Testing
@testable import MacDisplayConnectCore

@Suite("Control Center action planning")
struct ControlCenterPlannerTests {
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
            ControlCenterPlanner.action(for: elements)
                == .expandVisionPro(elementIndex: 1)
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
            ControlCenterPlanner.action(for: elements)
                == .selectMacVirtualDisplay(elementIndex: 3)
        )
    }

    @Test("expands the named AirPlay Vision Pro from the real device list")
    func expandsNamedAirPlayVisionPro() {
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
                text: ["S’s Apple\u{00A0}Vision\u{00A0}Pro"],
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
                visionProName: "S’s Apple Vision Pro"
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
                visionProName: "Apple Vision Pro"
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
                visionProName: "S’s Apple Vision Pro"
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
                visionProName: "S’s Apple Vision Pro"
            ) == .selectMacVirtualDisplay(elementIndex: 9)
        )
    }

    @Test("uses a generic Vision Pro name when it identifies one device")
    func selectsUniqueVisionProFromGenericName() {
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
                text: ["S’s Apple\u{00A0}Vision\u{00A0}Pro"],
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
                visionProName: "Apple Vision Pro"
            ) == .expandVisionPro(elementIndex: 9)
        )
    }

    @Test("does not guess when a generic name matches multiple Vision Pros")
    func rejectsAmbiguousGenericVisionProName() {
        let elements = [
            element(
                index: 8,
                kind: .checkbox,
                identifier: "screen-mirroring-device-Sidecar:ONE",
                text: ["Alice’s Apple Vision Pro"],
                isSelected: false
            ),
            element(
                index: 9,
                kind: .checkbox,
                identifier: "screen-mirroring-device-Sidecar:TWO",
                text: ["Bob’s Apple Vision Pro"],
                isSelected: false
            ),
        ]

        #expect(
            ControlCenterPlanner.action(
                for: elements,
                visionProName: "Apple Vision Pro"
            ) == .visionProNotFound
        )
    }

    @Test("does not partially match a personalized device name")
    func rejectsPartialPersonalizedVisionProName() {
        let elements = [
            element(
                index: 9,
                kind: .checkbox,
                identifier: "screen-mirroring-device-Sidecar:AVP",
                text: ["Living Room Apple Vision Pro"],
                isSelected: false
            ),
        ]

        #expect(
            ControlCenterPlanner.action(
                for: elements,
                visionProName: "Living Room"
            ) == .visionProNotFound
        )
    }

    @Test("does not select an exact AirPlay name")
    func rejectsExactAirPlayName() {
        let elements = [
            element(
                index: 10,
                kind: .checkbox,
                identifier: "screen-mirroring-device-AirPlay:TV",
                text: ["Living Room"],
                isSelected: false
            ),
        ]

        #expect(
            ControlCenterPlanner.action(
                for: elements,
                visionProName: "Living Room"
            ) == .visionProNotFound
        )
    }

    @Test("does not use a generic name to select an AirPlay device")
    func rejectsGenericAirPlayName() {
        let elements = [
            element(
                index: 10,
                kind: .checkbox,
                identifier: "screen-mirroring-device-AirPlay:TV",
                text: ["Living Room Apple Vision Pro TV"],
                isSelected: false
            ),
        ]

        #expect(
            ControlCenterPlanner.action(
                for: elements,
                visionProName: "Apple Vision Pro"
            ) == .visionProNotFound
        )
    }

    @Test("automatic selection uses a uniquely labeled Vision Pro")
    func automaticallySelectsUniqueVisionPro() {
        let elements = [
            element(
                index: 9,
                kind: .checkbox,
                identifier: "screen-mirroring-device-Sidecar:AVP",
                text: ["S’s Apple\u{00A0}Vision\u{00A0}Pro"],
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
            ControlCenterPlanner.action(for: elements)
                == .selectMacVirtualDisplay(elementIndex: 9)
        )
    }

    @Test("leaves the named Vision Pro alone when it is already connected")
    func leavesNamedVisionProConnected() {
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
                visionProName: "S’s Apple Vision Pro"
            ) == .alreadyConnected
        )
    }

    @Test("does not select another device when the named Vision Pro is absent")
    func rejectsMissingVisionProName() {
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
                visionProName: "S’s Apple Vision Pro"
            ) == .visionProNotFound
        )
    }

    @Test("does not guess when the Vision Pro name is duplicated")
    func rejectsDuplicateVisionProNames() {
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
                visionProName: "Shared Apple Vision Pro"
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
                visionProName: "S’s Apple Vision Pro"
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
            ControlCenterPlanner.action(for: elements) == .alreadyConnected
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
            ControlCenterPlanner.action(for: elements) == .visionProNotFound
        )
    }

    @Test("does not guess when multiple expandable devices are present")
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
            ControlCenterPlanner.action(for: elements) == .visionProNotFound
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
