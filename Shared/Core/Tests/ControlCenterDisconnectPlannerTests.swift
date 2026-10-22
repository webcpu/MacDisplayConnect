import Testing
@testable import MacDisplayConnectCore

@Suite("Control Center disconnect action planning")
struct ControlCenterDisconnectPlannerTests {
    @Test("a Sidecar mode checkbox is not treated as the device disconnect control")
    func rejectsExpandedSidecarModeAsDisconnectControl() {
        let targetID = "screen-mirroring-device-Sidecar:AVP"
        let elements = [
            element(
                index: 9,
                kind: .disclosure,
                identifier: targetID,
                text: ["avp"],
                isSelected: true
            ),
            element(
                index: 10,
                kind: .checkbox,
                identifier: targetID,
                text: ["Mac Virtual Display"],
                isSelected: true
            ),
        ]

        #expect(
            ControlCenterDisconnectPlanner.action(
                for: elements,
                visionProIdentifiers: [targetID]
            ) == .visionProNotFound
        )
    }

    @Test("an unselected Sidecar Vision Pro is already disconnected")
    func unselectedSidecarVisionProIsDisconnected() {
        let elements = [
            element(
                index: 9,
                kind: .checkbox,
                identifier: "screen-mirroring-device-Sidecar:AVP",
                text: ["S’s Apple\u{00A0}Vision\u{00A0}Pro"],
                isSelected: false
            ),
        ]

        #expect(
            ControlCenterDisconnectPlanner.action(
                for: elements,
                visionProIdentifiers: ["screen-mirroring-device-Sidecar:AVP"]
            ) == .alreadyDisconnected
        )
    }

    @Test(
        "a trusted Sidecar Vision Pro disconnects regardless of its label",
        arguments: ["avp", "", "Renamed headset"]
    )
    func selectedSidecarVisionProCanBeDisconnected(label: String) {
        let elements = [
            element(
                index: 9,
                kind: .checkbox,
                identifier: "screen-mirroring-device-Sidecar:AVP",
                text: [label],
                isSelected: true
            ),
        ]

        #expect(
            ControlCenterDisconnectPlanner.action(
                for: elements,
                visionProIdentifiers: ["screen-mirroring-device-Sidecar:AVP"]
            ) == .disconnectSidecar(elementIndex: 9)
        )
    }

    @Test("disconnects the selected Mac Virtual Display for a trusted custom-named Vision Pro")
    func disconnectsSelectedMacVirtualDisplay() {
        let targetID = "screen-mirroring-device-AirPlay:AVP"
        let elements = [
            element(
                index: 2,
                kind: .disclosure,
                identifier: targetID,
                text: ["avp"],
                isSelected: true
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
                kind: .checkbox,
                identifier: targetID,
                text: ["Mirror Built-in Liquid Retina XDR Display"],
                isSelected: false
            ),
        ]

        #expect(
            ControlCenterDisconnectPlanner.action(
                for: elements,
                visionProIdentifiers: [targetID]
            ) == .disconnectAirPlayDevice(elementIndex: 2)
        )
    }

    @Test("disconnects when Control Center duplicates an identical expanded group")
    func disconnectsFromIdenticalDuplicateGroups() {
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
                kind: .other,
                identifier: targetID,
                text: ["Move your Mac display to Apple Vision Pro."]
            ),
            element(
                index: 12,
                kind: .checkbox,
                identifier: targetID,
                text: ["Mirror Built-in Liquid Retina XDR Display"],
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
                kind: .other,
                identifier: targetID,
                text: ["Move your Mac display to Apple Vision Pro."]
            ),
            element(
                index: 16,
                kind: .checkbox,
                identifier: targetID,
                text: ["Mirror Built-in Liquid Retina XDR Display"],
                isSelected: false
            ),
        ]

        #expect(
            ControlCenterDisconnectPlanner.action(
                for: elements,
                visionProIdentifiers: [targetID]
            ) == .disconnectAirPlayDevice(elementIndex: 9)
        )
    }

    @Test("fails closed when duplicated device rows disagree")
    func rejectsInconsistentDuplicateDeviceRows() {
        let targetID = "screen-mirroring-device-AirPlay:AVP"
        let elements = [
            element(
                index: 2,
                kind: .disclosure,
                identifier: targetID,
                text: ["S’s Apple Vision Pro"],
                isSelected: true
            ),
            element(
                index: 3,
                kind: .checkbox,
                identifier: targetID,
                text: ["Mac Virtual Display"],
                isSelected: true
            ),
            element(
                index: 8,
                kind: .disclosure,
                identifier: targetID,
                text: ["S’s Apple Vision Pro"],
                isSelected: false
            ),
            element(
                index: 9,
                kind: .checkbox,
                identifier: targetID,
                text: ["Mac Virtual Display"],
                isSelected: true
            ),
        ]

        #expect(
            ControlCenterDisconnectPlanner.action(
                for: elements,
                visionProIdentifiers: [targetID]
            ) == .visionProNotFound
        )
    }

    @Test("fails closed when one duplicated group omits a mode")
    func rejectsIncompleteDuplicateModeGroups() {
        let targetID = "screen-mirroring-device-AirPlay:AVP"
        let elements = [
            element(
                index: 2,
                kind: .disclosure,
                identifier: targetID,
                text: ["S’s Apple Vision Pro"],
                isSelected: true
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
                kind: .checkbox,
                identifier: targetID,
                text: ["Mirror Display"],
                isSelected: false
            ),
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
                isSelected: true
            ),
        ]

        #expect(
            ControlCenterDisconnectPlanner.action(
                for: elements,
                visionProIdentifiers: [targetID]
            ) == .visionProNotFound
        )
    }

    @Test("fails closed when duplicate mode totals hide unequal groups")
    func rejectsUnequallyDistributedDuplicateModes() {
        let targetID = "screen-mirroring-device-AirPlay:AVP"
        let elements = [
            element(
                index: 20,
                kind: .disclosure,
                identifier: targetID,
                text: ["S’s Apple Vision Pro"],
                isSelected: true
            ),
            element(
                index: 21,
                kind: .checkbox,
                identifier: targetID,
                text: ["Mac Virtual Display"],
                isSelected: true
            ),
            element(
                index: 22,
                kind: .checkbox,
                identifier: targetID,
                text: ["Mirror Display"],
                isSelected: false
            ),
            element(
                index: 23,
                kind: .checkbox,
                identifier: targetID,
                text: ["Mirror Display"],
                isSelected: false
            ),
            element(
                index: 40,
                kind: .disclosure,
                identifier: targetID,
                text: ["S’s Apple Vision Pro"],
                isSelected: true
            ),
            element(
                index: 41,
                kind: .checkbox,
                identifier: targetID,
                text: ["Mac Virtual Display"],
                isSelected: true
            ),
        ]

        #expect(
            ControlCenterDisconnectPlanner.action(
                for: elements,
                visionProIdentifiers: [targetID]
            ) == .visionProNotFound
        )
    }

    @Test("fails closed when duplicate Mac Virtual Display rows share one group")
    func rejectsUnequallyDistributedMacVirtualDisplayRows() {
        let targetID = "screen-mirroring-device-AirPlay:AVP"
        let elements = [
            element(
                index: 20,
                kind: .disclosure,
                identifier: targetID,
                text: ["S’s Apple Vision Pro"],
                isSelected: true
            ),
            element(
                index: 21,
                kind: .checkbox,
                identifier: targetID,
                text: ["Mac Virtual Display"],
                isSelected: true
            ),
            element(
                index: 22,
                kind: .checkbox,
                identifier: targetID,
                text: ["Mac Virtual Display"],
                isSelected: true
            ),
            element(
                index: 40,
                kind: .disclosure,
                identifier: targetID,
                text: ["S’s Apple Vision Pro"],
                isSelected: true
            ),
        ]

        #expect(
            ControlCenterDisconnectPlanner.action(
                for: elements,
                visionProIdentifiers: [targetID]
            ) == .visionProNotFound
        )
    }

    @Test("expands the trusted AirPlay Vision Pro when its choices are collapsed")
    func expandsCollapsedVisionPro() {
        let elements = [
            element(
                index: 8,
                kind: .disclosure,
                identifier: "screen-mirroring-device-AirPlay:AVP",
                text: ["S’s Apple\u{00A0}Vision\u{00A0}Pro"],
                isSelected: false
            ),
            element(
                index: 9,
                kind: .checkbox,
                identifier: "screen-mirroring-device-AirPlay:TV",
                text: ["TV"],
                isSelected: false
            ),
        ]

        #expect(
            ControlCenterDisconnectPlanner.action(
                for: elements,
                visionProIdentifiers: ["screen-mirroring-device-AirPlay:AVP"]
            ) == .expandVisionPro(elementIndex: 8)
        )
    }

    @Test("an unchecked AirPlay Vision Pro is already disconnected")
    func uncheckedAirPlayVisionProIsDisconnected() {
        let elements = [
            element(
                index: 8,
                kind: .checkbox,
                identifier: "screen-mirroring-device-AirPlay:AVP",
                text: ["S’s Apple Vision Pro"],
                isSelected: false
            ),
        ]

        #expect(
            ControlCenterDisconnectPlanner.action(
                for: elements,
                visionProIdentifiers: ["screen-mirroring-device-AirPlay:AVP"]
            ) == .alreadyDisconnected
        )
    }

    @Test("does not toggle a selected device row without the exact child")
    func rejectsSelectedDeviceRowWithoutMacVirtualDisplayChild() {
        let elements = [
            element(
                index: 8,
                kind: .checkbox,
                identifier: "screen-mirroring-device-AirPlay:AVP",
                text: ["S’s Apple Vision Pro"],
                isSelected: true
            ),
        ]

        #expect(
            ControlCenterDisconnectPlanner.action(
                for: elements,
                visionProIdentifiers: ["screen-mirroring-device-AirPlay:AVP"]
            ) == .visionProNotFound
        )
    }

    @Test("reports already disconnected when Mac Virtual Display is not selected")
    func reportsAlreadyDisconnected() {
        let targetID = "screen-mirroring-device-AirPlay:AVP"
        let elements = [
            element(
                index: 2,
                kind: .disclosure,
                identifier: targetID,
                text: ["S’s Apple Vision Pro"],
                isSelected: true
            ),
            element(
                index: 3,
                kind: .checkbox,
                identifier: targetID,
                text: ["Mac Virtual Display"],
                isSelected: false
            ),
        ]

        #expect(
            ControlCenterDisconnectPlanner.action(
                for: elements,
                visionProIdentifiers: [targetID]
            ) == .alreadyDisconnected
        )
    }

    @Test("reports an expanded unchecked AirPlay row already disconnected")
    func reportsExpandedUncheckedAirPlayRowAlreadyDisconnected() {
        let targetID = "screen-mirroring-device-AirPlay:AVP"
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
                text: ["Mac Virtual Display"],
                isSelected: false
            ),
            element(
                index: 10,
                kind: .checkbox,
                identifier: targetID,
                text: ["Mirror Display"],
                isSelected: false
            ),
        ]

        #expect(
            ControlCenterDisconnectPlanner.action(
                for: elements,
                visionProIdentifiers: [targetID]
            ) == .alreadyDisconnected
        )
    }

    @Test("fails closed when multiple trusted Vision Pro IDs are present")
    func rejectsMultipleTrustedVisionPros() {
        let elements = [
            element(
                index: 2,
                kind: .checkbox,
                identifier: "screen-mirroring-device-AirPlay:ONE",
                text: ["Shared Apple Vision Pro"],
                isSelected: true
            ),
            element(
                index: 3,
                kind: .checkbox,
                identifier: "screen-mirroring-device-AirPlay:TWO",
                text: ["Shared Apple Vision Pro"],
                isSelected: true
            ),
        ]

        #expect(
            ControlCenterDisconnectPlanner.action(
                for: elements,
                visionProIdentifiers: [
                    "screen-mirroring-device-AirPlay:ONE",
                    "screen-mirroring-device-AirPlay:TWO",
                ]
            ) == .visionProNotFound
        )
    }

    @Test("fails closed when duplicate Mac Virtual Display rows disagree")
    func rejectsInconsistentMacVirtualDisplayState() {
        let targetID = "screen-mirroring-device-AirPlay:AVP"
        let elements = [
            element(
                index: 2,
                kind: .disclosure,
                identifier: targetID,
                text: ["S’s Apple Vision Pro"],
                isSelected: true
            ),
            element(
                index: 3,
                kind: .checkbox,
                identifier: targetID,
                text: ["Mac Virtual Display"],
                isSelected: true
            ),
            element(
                index: 8,
                kind: .checkbox,
                identifier: targetID,
                text: ["Mac Virtual Display"],
                isSelected: false
            ),
        ]

        #expect(
            ControlCenterDisconnectPlanner.action(
                for: elements,
                visionProIdentifiers: [targetID]
            ) == .visionProNotFound
        )
    }

    @Test("fails closed when Mirror Display is selected")
    func rejectsSelectedMirrorDisplayAlongsideMacVirtualDisplay() {
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
                kind: .checkbox,
                identifier: targetID,
                text: ["Mirror Display"],
                isSelected: true
            ),
        ]

        #expect(
            ControlCenterDisconnectPlanner.action(
                for: elements,
                visionProIdentifiers: [targetID]
            ) == .visionProNotFound
        )
    }

    @Test("does not call a mirrored display disconnected")
    func rejectsUnselectedMacVirtualDisplayWhenMirrorDisplayIsSelected() {
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
                kind: .checkbox,
                identifier: targetID,
                text: ["Mirror Display"],
                isSelected: true
            ),
        ]

        #expect(
            ControlCenterDisconnectPlanner.action(
                for: elements,
                visionProIdentifiers: [targetID]
            ) == .visionProNotFound
        )
    }

    @Test("ignores unrelated AirPlay devices")
    func ignoresUnrelatedAirPlayDevices() {
        let targetID = "screen-mirroring-device-AirPlay:AVP"
        let elements = [
            element(
                index: 1,
                kind: .checkbox,
                identifier: "screen-mirroring-device-AirPlay:TV",
                text: ["Living Room"],
                isSelected: true
            ),
            element(
                index: 2,
                kind: .disclosure,
                identifier: targetID,
                text: ["S’s Apple Vision Pro"],
                isSelected: true
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
                kind: .checkbox,
                identifier: "screen-mirroring-device-AirPlay:PROJECTOR",
                text: ["Projector"],
                isSelected: true
            ),
        ]

        #expect(
            ControlCenterDisconnectPlanner.action(
                for: elements,
                visionProIdentifiers: [targetID]
            ) == .disconnectAirPlayDevice(elementIndex: 2)
        )
    }

    @Test("does not use a selected mirror-display row as a disconnect target")
    func rejectsMirrorDisplayAsDisconnectTarget() {
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
                text: ["Mirror Built-in Liquid Retina XDR Display"],
                isSelected: true
            ),
        ]

        #expect(
            ControlCenterDisconnectPlanner.action(
                for: elements,
                visionProIdentifiers: [targetID]
            ) == .visionProNotFound
        )
    }

    @Test("empty discovery never disconnects an Apple Vision Pro label")
    func rejectsVisionProLabelWithoutDiscovery() {
        let elements = [
            element(
                index: 9,
                kind: .checkbox,
                identifier: "screen-mirroring-device-Sidecar:AVP",
                text: ["Apple Vision Pro"],
                isSelected: true
            ),
        ]

        #expect(
            ControlCenterDisconnectPlanner.action(
                for: elements,
                visionProIdentifiers: []
            ) == .visionProNotFound
        )
    }

    @Test("a misleading Apple Vision Pro label cannot authorize a disconnect")
    func rejectsMisleadingVisionProLabel() {
        let elements = [
            element(
                index: 9,
                kind: .checkbox,
                identifier: "screen-mirroring-device-Sidecar:IPAD",
                text: ["Apple Vision Pro"],
                isSelected: true
            ),
        ]

        #expect(
            ControlCenterDisconnectPlanner.action(
                for: elements,
                visionProIdentifiers: ["screen-mirroring-device-Sidecar:AVP"]
            ) == .visionProNotFound
        )
    }

    @Test("either trusted transport alias can report an already disconnected device")
    func recognizesOnlyPresentTransportAlias() {
        let airPlayID = "screen-mirroring-device-AirPlay:AVP"
        let sidecarID = "screen-mirroring-device-Sidecar:AVP"

        for identifier in [airPlayID, sidecarID] {
            let elements = [
                element(
                    index: 9,
                    kind: .checkbox,
                    identifier: identifier,
                    isSelected: false
                ),
            ]

            #expect(
                ControlCenterDisconnectPlanner.action(
                    for: elements,
                    visionProIdentifiers: [airPlayID, sidecarID]
                ) == .alreadyDisconnected
            )
        }
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
                isSelected: true
            ),
        ]

        #expect(
            ControlCenterDisconnectPlanner.action(
                for: elements,
                visionProIdentifiers: [airPlayID, sidecarID]
            ) == .visionProNotFound
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
