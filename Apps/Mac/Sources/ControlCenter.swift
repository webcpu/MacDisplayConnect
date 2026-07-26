import AppKit
import MacDisplayConnectCore
import ApplicationServices

@MainActor
enum ControlCenter {
    static var hasAccessibilityAccess: Bool {
        AXIsProcessTrusted()
    }

    static func requestAccessibilityAccess() {
        DiagnosticLog.record("Displaying the Accessibility permission prompt")
        let options = [
            "AXTrustedCheckOptionPrompt": true,
        ] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    static func openScreenMirroring() async throws {
        DiagnosticLog.record("Opening Screen Mirroring")
        let application = try controlCenterApplication()
        let elements = accessibilityTree(from: application)
        let action = ControlCenterNavigationPlanner.action(
            for: elements.snapshots
        )
        DiagnosticLog.record(
            "Navigation scan: \(elements.snapshots.diagnosticSummary); "
                + "action=\(action.diagnosticName)"
        )

        switch action {
        case let .openScreenMirroring(elementIndex):
            guard elements[elementIndex].role != kAXWindowRole else {
                DiagnosticLog.record("Screen Mirroring panel is already open")
                return
            }
            try press(elements, at: elementIndex)
        case let .openControlCenter(elementIndex):
            try press(elements, at: elementIndex)
            try await Task.sleep(for: ControlCenterTiming.actionDelay)
            try openScreenMirroringModule(in: application)
        case .screenMirroringNotFound:
            throw MacDisplayConnectError.screenMirroringControlNotFound
        }
    }

    static func connectMacVirtualDisplay(
        visionProName: String? = nil
    ) async throws -> Bool {
        DiagnosticLog.record(
            "Selecting Mac Virtual Display; target="
                + (visionProName ?? "automatic")
        )
        let application = try controlCenterApplication()

        for attempt in 1...ControlCenterTiming.actionAttempts {
            let elements = accessibilityTree(from: application)
            let action = ControlCenterPlanner.action(
                for: elements.snapshots,
                visionProName: visionProName
            )
            DiagnosticLog.record(
                "Vision Pro scan \(attempt): "
                    + "\(elements.snapshots.diagnosticSummary); "
                    + "action=\(action.diagnosticName)"
            )

            switch action {
            case let .expandVisionPro(elementIndex):
                try press(elements, at: elementIndex)
                try await Task.sleep(for: ControlCenterTiming.actionDelay)
            case let .selectMacVirtualDisplay(elementIndex):
                try press(elements, at: elementIndex)
                return true
            case .alreadyConnected:
                return false
            case .visionProNotFound:
                DiagnosticLog.record(
                    "Vision Pro scan details: "
                        + elements.snapshots.diagnosticDetails
                )
                throw MacDisplayConnectError.visionProControlNotFound
            }
        }

        throw MacDisplayConnectError.visionProControlNotFound
    }

    private static func controlCenterApplication() throws -> AXUIElement {
        guard let process = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.controlcenter"
        ).first else {
            DiagnosticLog.record("Control Center process was not running")
            throw MacDisplayConnectError.controlCenterNotRunning
        }

        DiagnosticLog.record(
            "Found Control Center process pid=\(process.processIdentifier)"
        )
        return AXUIElementCreateApplication(process.processIdentifier)
    }

    private static func openScreenMirroringModule(
        in application: AXUIElement
    ) throws {
        let elements = accessibilityTree(from: application)
        let action = ControlCenterNavigationPlanner.action(
            for: elements.snapshots
        )
        DiagnosticLog.record(
            "Control Center panel scan: "
                + "\(elements.snapshots.diagnosticSummary); "
                + "action=\(action.diagnosticName)"
        )

        guard case let .openScreenMirroring(elementIndex) =
            action
        else {
            throw MacDisplayConnectError.screenMirroringControlNotFound
        }

        try press(elements, at: elementIndex)
    }

    private static func accessibilityTree(
        from root: AXUIElement,
        maximumDepth: Int = 12
    ) -> [AXUIElement] {
        descendants(of: root, remainingDepth: maximumDepth)
    }

    private static func descendants(
        of element: AXUIElement,
        remainingDepth: Int
    ) -> [AXUIElement] {
        guard remainingDepth > 0 else {
            return [element]
        }

        return [element] + element.children.flatMap {
            descendants(of: $0, remainingDepth: remainingDepth - 1)
        }
    }

    private static func performPress(_ element: AXUIElement) -> Bool {
        guard element.actionNames.contains(kAXPressAction as String) else {
            DiagnosticLog.record(
                "Element cannot be pressed: \(element.diagnosticSummary)"
            )
            return false
        }

        let error = AXUIElementPerformAction(
            element,
            kAXPressAction as CFString
        )
        DiagnosticLog.record(
            "Pressed \(element.diagnosticSummary); AXError=\(error.rawValue)"
        )
        return error == .success
    }

    private static func press(
        _ elements: [AXUIElement],
        at index: Int
    ) throws {
        guard elements.indices.contains(index), performPress(elements[index])
        else {
            throw MacDisplayConnectError.visionProControlNotFound
        }
    }
}

private enum ControlCenterTiming {
    static let actionAttempts = 3
    static let actionDelay = Duration.milliseconds(500)
}

private extension [AXUIElement] {
    var snapshots: [ControlCenterElement] {
        enumerated().map { index, element in
            ControlCenterElement(
                index: index,
                kind: element.kind,
                identifier: element.identifier,
                text: element.searchableText,
                isSelected: element.selectedValue
            )
        }
    }
}

private extension [ControlCenterElement] {
    var diagnosticSummary: String {
        let checkboxCount = count { $0.kind == .checkbox }
        let disclosureCount = count { $0.kind == .disclosure }
        let visionTextCount = count {
            $0.text.contains {
                $0.normalizedForDiagnostics.contains("vision pro")
            }
        }
        let screenMirroringCount = count {
            $0.identifier == "controlcenter-screen-mirroring"
        }
        let deviceRows = enumerated()
            .compactMap { index, element in
                guard let identifier = element.identifier,
                      identifier.hasPrefix("screen-mirroring-device-")
                else {
                    return nil
                }

                let selected = element.isSelected.map(String.init) ?? "unknown"
                return "\(index):\(identifier):selected=\(selected)"
            }
            .joined(separator: ",")

        return "elements=\(count), checkboxes=\(checkboxCount), "
            + "disclosures=\(disclosureCount), "
            + "visionText=\(visionTextCount), "
            + "screenMirroringModules=\(screenMirroringCount), "
            + "deviceRows=[\(deviceRows)]"
    }

    var diagnosticDetails: String {
        enumerated()
            .map { index, element in
                let selected =
                    element.isSelected.map(String.init) ?? "unknown"
                return "\(index):kind=\(element.kind),"
                    + "identifier=\(element.identifier ?? "none"),"
                    + "selected=\(selected),"
                    + "text=\(element.text)"
            }
            .joined(separator: "; ")
    }
}

private extension String {
    var normalizedForDiagnostics: String {
        components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .lowercased()
    }
}

private extension ControlCenterNavigationAction {
    var diagnosticName: String {
        switch self {
        case let .openControlCenter(index):
            "openControlCenter(index=\(index))"
        case let .openScreenMirroring(index):
            "openScreenMirroring(index=\(index))"
        case .screenMirroringNotFound:
            "screenMirroringNotFound"
        }
    }
}

private extension ControlCenterAction {
    var diagnosticName: String {
        switch self {
        case let .expandVisionPro(index):
            "expandVisionPro(index=\(index))"
        case let .selectMacVirtualDisplay(index):
            "selectMacVirtualDisplay(index=\(index))"
        case .alreadyConnected:
            "alreadyConnected"
        case .visionProNotFound:
            "visionProNotFound"
        }
    }
}

private extension AXUIElement {
    var children: [AXUIElement] {
        copiedAttribute(kAXChildrenAttribute as CFString) ?? []
    }

    var kind: ControlCenterElement.Kind {
        switch role {
        case kAXCheckBoxRole:
            .checkbox
        case kAXDisclosureTriangleRole:
            .disclosure
        default:
            .other
        }
    }

    var identifier: String? {
        copiedAttribute(kAXIdentifierAttribute as CFString)
    }

    var selectedValue: Bool? {
        (copiedAttribute(kAXSelectedAttribute as CFString) as Bool?)
            ?? (copiedAttribute(kAXValueAttribute as CFString) as NSNumber?)
                .map(\.boolValue)
    }

    var actionNames: [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(self, &names) == .success else {
            return []
        }
        return names as? [String] ?? []
    }

    var searchableText: [String] {
        [
            kAXTitleAttribute,
            kAXDescriptionAttribute,
            kAXValueAttribute,
            kAXHelpAttribute,
        ].compactMap { copiedAttribute($0 as CFString) }
    }

    var diagnosticSummary: String {
        let identifierText = identifier ?? "none"
        let roleText = role ?? "unknown"
        return "role=\(roleText), identifier=\(identifierText), "
            + "selected=\(selectedValue.map(String.init) ?? "unknown")"
    }

    var role: String? {
        copiedAttribute(kAXRoleAttribute as CFString)
    }

    private func copiedAttribute<Value>(_ attribute: CFString) -> Value? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, attribute, &value) == .success
        else {
            return nil
        }
        return value as? Value
    }
}
