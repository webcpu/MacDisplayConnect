import Foundation

public struct ControlCenterElement: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case checkbox
        case disclosure
        case other
    }

    public let index: Int
    public let kind: Kind
    public let identifier: String?
    public let text: [String]
    public let isSelected: Bool?

    public init(
        index: Int,
        kind: Kind,
        identifier: String?,
        text: [String],
        isSelected: Bool?
    ) {
        self.index = index
        self.kind = kind
        self.identifier = identifier
        self.text = text
        self.isSelected = isSelected
    }
}

public enum ControlCenterAction: Equatable, Sendable {
    case expandVisionPro(elementIndex: Int)
    case selectMacVirtualDisplay(elementIndex: Int)
    case alreadyConnected
    case visionProNotFound
}

public enum ControlCenterDisconnectAction: Equatable, Sendable {
    case expandVisionPro(elementIndex: Int)
    case disconnectAirPlayDevice(elementIndex: Int)
    case disconnectSidecar(elementIndex: Int)
    case alreadyDisconnected
    case visionProNotFound
}

public enum ControlCenterNavigationAction: Equatable, Sendable {
    case openControlCenter(elementIndex: Int)
    case openScreenMirroring(elementIndex: Int)
    case screenMirroringAlreadyOpen
    case screenMirroringNotFound
}

public enum ControlCenterNavigationPlanner {
    public static func action(
        for elements: [ControlCenterElement]
    ) -> ControlCenterNavigationAction {
        if elements.contains(where: {
            $0.identifier == "screen-mirroring-header"
        }) {
            return .screenMirroringAlreadyOpen
        }

        return screenMirroringModule(in: elements)
            .map { .openScreenMirroring(elementIndex: $0.index) }
            ?? controlCenterElement(in: elements)
                .map { .openControlCenter(elementIndex: $0.index) }
            ?? pinnedScreenMirroringElement(in: elements)
                .map { .openScreenMirroring(elementIndex: $0.index) }
            ?? .screenMirroringNotFound
    }

    private static func screenMirroringModule(
        in elements: [ControlCenterElement]
    ) -> ControlCenterElement? {
        elements.first {
            $0.identifier == "controlcenter-screen-mirroring"
        }
    }

    private static func controlCenterElement(
        in elements: [ControlCenterElement]
    ) -> ControlCenterElement? {
        elements.first {
            $0.identifier == "com.apple.menuextra.controlcenter"
        }
    }

    private static func pinnedScreenMirroringElement(
        in elements: [ControlCenterElement]
    ) -> ControlCenterElement? {
        elements.first {
            $0.identifier == "com.apple.menuextra.screen-mirroring"
        }
    }
}

public enum ControlCenterPlanner {
    public static func action(
        for elements: [ControlCenterElement],
        visionProIdentifiers: Set<String> = []
    ) -> ControlCenterAction {
        guard let identifier = visionProIdentifier(
            in: elements,
            knownIdentifiers: visionProIdentifiers
        ) else {
            return .visionProNotFound
        }

        return macVirtualDisplayAction(
            in: elements,
            identifier: identifier
        )
    }

    fileprivate static func visionProIdentifier(
        in elements: [ControlCenterElement],
        knownIdentifiers: Set<String>
    ) -> String? {
        let identifiers = Set(
            elements.compactMap { element -> String? in
                guard element.kind != .other,
                      let identifier = element.identifier,
                      knownIdentifiers.contains(identifier),
                      identifier.hasPrefix("screen-mirroring-device-Sidecar:")
                        || identifier.hasPrefix("screen-mirroring-device-AirPlay:")
                else {
                    return nil
                }
                return identifier
            }
        )
        return identifiers.count == 1 ? identifiers.first : nil
    }

    private static func macVirtualDisplayAction(
        in elements: [ControlCenterElement],
        identifier: String
    ) -> ControlCenterAction {
        let matchingControls = elements.filter {
            $0.kind != .other && $0.identifier == identifier
        }
        guard let visionPro = matchingControls.first else {
            return .visionProNotFound
        }
        let containsOnlyAirPlayHeaders =
            identifier.hasPrefix("screen-mirroring-device-AirPlay:")
            && matchingControls.dropFirst().allSatisfy {
                $0.kind == visionPro.kind
                    && $0.text == visionPro.text
            }
        guard !containsOnlyAirPlayHeaders
            || matchingControls.allSatisfy({
                $0.isSelected == visionPro.isSelected
            })
        else {
            return .visionProNotFound
        }
        // The first control is the device header, even when its name matches
        // a mode label. Identical collapsed headers are not child modes.
        let macVirtualDisplayRows = matchingControls.dropFirst().filter {
            !containsOnlyAirPlayHeaders
                && $0.kind == .checkbox
                && $0.describesMacVirtualDisplay
        }
        if let macVirtualDisplay = macVirtualDisplayRows.first {
            guard macVirtualDisplayRows.dropFirst().allSatisfy({
                $0.isSelected == macVirtualDisplay.isSelected
            }) else {
                return .visionProNotFound
            }
            return macVirtualDisplay.isSelected == true
                ? .alreadyConnected
                : .selectMacVirtualDisplay(
                    elementIndex: macVirtualDisplay.index
                )
        }

        guard matchingControls.count == 1
            || containsOnlyAirPlayHeaders
        else {
            return .visionProNotFound
        }

        if visionPro.isSelected == true {
            return .alreadyConnected
        }
        if identifier.hasPrefix("screen-mirroring-device-AirPlay:") {
            return .expandVisionPro(elementIndex: visionPro.index)
        }
        guard visionPro.kind == .checkbox else {
            return .visionProNotFound
        }
        return .selectMacVirtualDisplay(elementIndex: visionPro.index)
    }
}

public enum ControlCenterDisconnectPlanner {
    public static func action(
        for elements: [ControlCenterElement],
        visionProIdentifiers: Set<String> = []
    ) -> ControlCenterDisconnectAction {
        guard let identifier = ControlCenterPlanner.visionProIdentifier(
            in: elements,
            knownIdentifiers: visionProIdentifiers
        ) else {
            return .visionProNotFound
        }

        let matchingControls = elements.filter {
            $0.kind != .other && $0.identifier == identifier
        }
        if identifier.hasPrefix("screen-mirroring-device-Sidecar:"),
           matchingControls.count == 1,
           let sidecarVisionPro = matchingControls.first,
           sidecarVisionPro.kind == .checkbox,
           let isSelected = sidecarVisionPro.isSelected
        {
            return isSelected
                ? .disconnectSidecar(
                    elementIndex: sidecarVisionPro.index
                )
                : .alreadyDisconnected
        }

        guard identifier.hasPrefix("screen-mirroring-device-AirPlay:")
        else {
            return .visionProNotFound
        }

        let actionablePositions = elements.indices.filter {
            elements[$0].identifier == identifier
                && elements[$0].kind != .other
        }
        guard let firstPosition = actionablePositions.first else {
            return .visionProNotFound
        }
        let firstRow = elements[firstPosition]
        // Labels only distinguish duplicate headers from their mode rows;
        // device identity was already established by the typed identifiers.
        let devicePositions = actionablePositions.filter {
            elements[$0].kind == .disclosure
                || (elements[$0].kind == firstRow.kind
                    && elements[$0].text.map(\.normalizedForMatching)
                        == firstRow.text.map(\.normalizedForMatching))
        }
        let deviceRows = devicePositions.map { elements[$0] }
        guard let deviceRow = deviceRows.first,
              deviceRows.dropFirst().allSatisfy({
                  ElementSignature($0) == ElementSignature(deviceRow)
              })
        else {
            return .visionProNotFound
        }

        guard let modeGroups = airPlayModeGroups(
            in: elements,
            identifier: identifier,
            devicePositions: devicePositions
        ),
            let modeRows = modeGroups.first
        else {
            return .visionProNotFound
        }
        let modeSignature = modeRows.map(ElementSignature.init)
        guard modeGroups.dropFirst().allSatisfy({
            $0.map(ElementSignature.init) == modeSignature
        }) else {
            return .visionProNotFound
        }

        let macVirtualDisplayRows = modeRows.filter(
            \.describesMacVirtualDisplay
        )
        guard !macVirtualDisplayRows.isEmpty else {
            if deviceRow.kind == .checkbox,
               deviceRow.isSelected == false,
               modeRows.isEmpty
            {
                return .alreadyDisconnected
            }
            if deviceRow.kind == .disclosure,
               deviceRow.isSelected == false,
               modeRows.isEmpty
            {
                return .expandVisionPro(elementIndex: deviceRow.index)
            }
            return .visionProNotFound
        }

        guard modeRows.allSatisfy({ $0.kind == .checkbox }),
              macVirtualDisplayRows.count == 1,
              let macVirtualDisplay = macVirtualDisplayRows.first,
              let isSelected = macVirtualDisplay.isSelected
        else {
            return .visionProNotFound
        }

        let otherModeRows = modeRows.filter {
            !$0.describesMacVirtualDisplay
        }
        guard otherModeRows.allSatisfy({
            $0.isSelected == false
        }) else {
            return .visionProNotFound
        }

        guard isSelected else {
            return .alreadyDisconnected
        }
        guard deviceRow.kind == .disclosure,
              deviceRow.isSelected == true
        else {
            return .visionProNotFound
        }
        return .disconnectAirPlayDevice(elementIndex: deviceRow.index)
    }

    private static func airPlayModeGroups(
        in elements: [ControlCenterElement],
        identifier: String,
        devicePositions: [Int]
    ) -> [[ControlCenterElement]]? {
        let devicePositionSet = Set(devicePositions)
        var accountedPositions = devicePositionSet
        var groups: [[ControlCenterElement]] = []

        for devicePosition in devicePositions {
            let groupEnd = elements.indices.first {
                guard $0 > devicePosition else {
                    return false
                }
                if devicePositionSet.contains($0) {
                    return true
                }

                let element = elements[$0]
                guard element.kind != .other,
                      let candidateIdentifier = element.identifier,
                      candidateIdentifier.hasPrefix(
                          "screen-mirroring-device-"
                      )
                else {
                    return false
                }
                return candidateIdentifier != identifier
                    || element.kind == .disclosure
            } ?? elements.endIndex

            let modePositions = elements.indices.filter {
                $0 > devicePosition
                    && $0 < groupEnd
                    && elements[$0].identifier == identifier
                    && elements[$0].kind != .other
            }
            accountedPositions.formUnion(modePositions)
            groups.append(modePositions.map { elements[$0] })
        }

        let actionablePositions = Set(elements.indices.filter {
            elements[$0].identifier == identifier
                && elements[$0].kind != .other
        })
        guard accountedPositions == actionablePositions else {
            return nil
        }
        return groups
    }

    private struct ElementSignature: Equatable {
        let kind: ControlCenterElement.Kind
        let text: [String]
        let isSelected: Bool?

        init(_ element: ControlCenterElement) {
            kind = element.kind
            text = element.text.map(\.normalizedForMatching)
            isSelected = element.isSelected
        }
    }
}

private extension ControlCenterElement {
    var describesMacVirtualDisplay: Bool {
        text.contains {
            $0.normalizedForMatching == "mac virtual display"
        }
    }
}

private extension String {
    var normalizedForMatching: String {
        components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .lowercased()
    }
}
