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

public enum ControlCenterNavigationAction: Equatable, Sendable {
    case openControlCenter(elementIndex: Int)
    case openScreenMirroring(elementIndex: Int)
    case screenMirroringNotFound
}

public enum ControlCenterNavigationPlanner {
    public static func action(
        for elements: [ControlCenterElement]
    ) -> ControlCenterNavigationAction {
        screenMirroringModule(in: elements)
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
        visionProName: String? = nil
    ) -> ControlCenterAction {
        guard let identifier = visionProIdentifier(
            in: elements,
            named: visionProName ?? "Apple Vision Pro"
        ) else {
            return .visionProNotFound
        }

        return macVirtualDisplayAction(
            in: elements,
            identifier: identifier
        )
    }

    private static func visionProIdentifier(
        in elements: [ControlCenterElement],
        named visionProName: String
    ) -> String? {
        let normalizedName = visionProName.normalizedForMatching
        guard !normalizedName.isEmpty else {
            return nil
        }

        let exactIdentifiers: Set<String> = Set(
            elements.compactMap { element -> String? in
                guard element.kind != .other,
                      element.describesVisionPro,
                      let identifier = element.identifier,
                      identifier.hasPrefix("screen-mirroring-device-")
                else {
                    return nil
                }
                guard element.text.contains(where: {
                    $0.normalizedForMatching == normalizedName
                }) else {
                    return nil
                }
                return identifier
            }
        )

        if exactIdentifiers.count == 1 {
            return exactIdentifiers.first
        }
        guard exactIdentifiers.isEmpty else {
            return nil
        }
        guard normalizedName == "apple vision pro" else {
            return nil
        }

        let containingIdentifiers: Set<String> = Set(
            elements.compactMap { element -> String? in
                guard element.kind != .other,
                      element.describesVisionPro,
                      let identifier = element.identifier,
                      identifier.hasPrefix("screen-mirroring-device-")
                else {
                    return nil
                }
                guard element.text.contains(where: {
                    $0.normalizedForMatching.hasSuffix(normalizedName)
                }) else {
                    return nil
                }
                return identifier
            }
        )

        guard containingIdentifiers.count == 1 else {
            return nil
        }
        return containingIdentifiers.first
    }

    private static func macVirtualDisplayAction(
        in elements: [ControlCenterElement],
        identifier: String
    ) -> ControlCenterAction {
        let matchingCheckboxes = elements.filter {
            $0.kind == .checkbox && $0.identifier == identifier
        }
        let macVirtualDisplayRows = matchingCheckboxes.filter(
            \.describesMacVirtualDisplay
        )
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

        let matchingControls = elements.filter {
            $0.kind != .other && $0.identifier == identifier
        }
        guard let visionPro = matchingControls.first,
              visionPro.describesVisionPro
        else {
            return .visionProNotFound
        }

        let containsOnlyIdenticalAirPlayRows =
            identifier.hasPrefix("screen-mirroring-device-AirPlay:")
            && matchingControls.dropFirst().allSatisfy {
                $0.kind == visionPro.kind
                    && $0.text == visionPro.text
                    && $0.isSelected == visionPro.isSelected
            }
        guard matchingControls.count == 1
            || containsOnlyIdenticalAirPlayRows
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

private extension ControlCenterElement {
    var describesVisionPro: Bool {
        text.contains {
            $0.normalizedForMatching.contains("vision pro")
        }
    }

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
