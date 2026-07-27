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
        try await openScreenMirroring(using: automation(for: application))
    }

    static func openScreenMirroring(
        using automation: ControlCenterAutomation
    ) async throws {
        let navigationScan = try automation.scan()
        let navigationAction = ControlCenterNavigationPlanner.action(
            for: navigationScan.snapshots
        )
        DiagnosticLog.record(
            "Navigation scan: "
                + "\(navigationScan.snapshots.diagnosticSummary); "
                + "action=\(navigationAction.diagnosticName)"
        )
        var lastControlCenterPressAttempt: Int?

        switch navigationAction {
        case let .openScreenMirroring(elementIndex):
            guard !navigationScan.isWindow(elementIndex) else {
                DiagnosticLog.record("Screen Mirroring panel is already open")
                return
            }
            try navigationScan.press(elementIndex)
            return
        case let .openControlCenter(elementIndex):
            if try reopenControlCenterIfNeeded(
                elementIndex: elementIndex,
                in: navigationScan
            ) {
                lastControlCenterPressAttempt = 0
            }
        case .screenMirroringAlreadyOpen:
            DiagnosticLog.record("Screen Mirroring panel is already open")
            return
        case .screenMirroringNotFound:
            break
        }

        guard automation.maximumAttempts > 0 else {
            throw MacDisplayConnectError.screenMirroringControlNotFound
        }

        for attempt in 1...automation.maximumAttempts {
            try await automation.wait()
            let scan = try automation.scan()
            let action = ControlCenterNavigationPlanner.action(
                for: scan.snapshots
            )
            DiagnosticLog.record(
                "Control Center panel scan \(attempt): "
                    + "\(scan.snapshots.diagnosticSummary); "
                    + "action=\(action.diagnosticName)"
            )

            switch action {
            case let .openScreenMirroring(elementIndex):
                guard !scan.isWindow(elementIndex) else {
                    DiagnosticLog.record(
                        "Screen Mirroring panel is already open"
                    )
                    return
                }
                try scan.press(elementIndex)
                return
            case let .openControlCenter(elementIndex):
                let hasObservedTwoMissingScans =
                    lastControlCenterPressAttempt.map {
                        attempt - $0 >= 2
                    } ?? true
                guard attempt < automation.maximumAttempts,
                      hasObservedTwoMissingScans
                else {
                    continue
                }

                if try reopenControlCenterIfNeeded(
                    elementIndex: elementIndex,
                    in: scan
                ) {
                    lastControlCenterPressAttempt = attempt
                }
            case .screenMirroringAlreadyOpen:
                DiagnosticLog.record("Screen Mirroring panel is already open")
                return
            case .screenMirroringNotFound:
                continue
            }
        }

        throw MacDisplayConnectError.screenMirroringControlNotFound
    }

    static func connectMacVirtualDisplay(
        visionProName: String? = nil
    ) async throws -> Bool {
        DiagnosticLog.record(
            "Selecting Mac Virtual Display; target="
                + (visionProName ?? "automatic")
        )
        let application = try controlCenterApplication()
        return try await connectMacVirtualDisplay(
            visionProName: visionProName,
            using: automation(for: application)
        )
    }

    static func connectMacVirtualDisplay(
        visionProName: String? = nil,
        using automation: ControlCenterAutomation
    ) async throws -> Bool {
        guard automation.maximumAttempts > 0 else {
            throw MacDisplayConnectError.visionProControlNotFound
        }

        var didActivateExpandableVisionPro = false
        for attempt in 1...automation.maximumAttempts {
            let scan = try automation.scan()
            let action = ControlCenterPlanner.action(
                for: scan.snapshots,
                visionProName: visionProName
            )
            DiagnosticLog.record(
                "Vision Pro scan \(attempt): "
                    + "\(scan.snapshots.diagnosticSummary); "
                    + "action=\(action.diagnosticName)"
            )

            switch action {
            case let .expandVisionPro(elementIndex):
                if didActivateExpandableVisionPro {
                    DiagnosticLog.record(
                        "Waiting for the first Vision Pro row action to settle"
                    )
                } else {
                    try scan.press(elementIndex)
                    didActivateExpandableVisionPro = true
                }
            case let .selectMacVirtualDisplay(elementIndex):
                try scan.press(elementIndex)
                return true
            case .alreadyConnected:
                return false
            case .visionProNotFound:
                if attempt < automation.maximumAttempts {
                    try recoverScreenMirroringIfNeeded(from: scan)
                }
                if attempt == automation.maximumAttempts {
                    DiagnosticLog.record(
                        "Vision Pro scan details: "
                            + scan.snapshots.diagnosticDetails
                    )
                }
            }

            if attempt < automation.maximumAttempts {
                try await automation.wait()
            }
        }

        throw MacDisplayConnectError.visionProControlNotFound
    }

    static func disconnectMacVirtualDisplay(
        visionProName: String? = nil
    ) async throws -> Bool {
        DiagnosticLog.record(
            "Deselecting Mac Virtual Display; target="
                + (visionProName ?? "automatic")
        )
        let application = try controlCenterApplication()
        return try await disconnectMacVirtualDisplay(
            visionProName: visionProName,
            using: automation(for: application)
        )
    }

    static func disconnectMacVirtualDisplay(
        visionProName: String? = nil,
        using automation: ControlCenterAutomation
    ) async throws -> Bool {
        guard automation.maximumAttempts > 0 else {
            throw MacDisplayConnectError.visionProControlNotFound
        }

        for attempt in 1...automation.maximumAttempts {
            let scan = try automation.scan()
            let action = ControlCenterDisconnectPlanner.action(
                for: scan.snapshots,
                visionProName: visionProName
            )
            DiagnosticLog.record(
                "Vision Pro disconnect scan \(attempt): "
                    + "\(scan.snapshots.diagnosticSummary); "
                    + "action=\(action.diagnosticName)"
            )

            switch action {
            case let .expandVisionPro(elementIndex):
                try scan.press(elementIndex)
            case let .disconnectAirPlayDevice(elementIndex):
                try scan.activateDevicePrimaryAction(elementIndex)
                return true
            case let .disconnectSidecar(elementIndex):
                try scan.press(elementIndex)
                return true
            case .alreadyDisconnected:
                return false
            case .visionProNotFound:
                if attempt < automation.maximumAttempts {
                    try recoverScreenMirroringIfNeeded(from: scan)
                }
                if attempt == automation.maximumAttempts {
                    DiagnosticLog.record(
                        "Vision Pro disconnect scan details: "
                            + scan.snapshots.diagnosticDetails
                    )
                }
            }

            if attempt < automation.maximumAttempts {
                try await automation.wait()
            }
        }

        throw MacDisplayConnectError.visionProControlNotFound
    }

    @discardableResult
    private static func reopenControlCenterIfNeeded(
        elementIndex: Int,
        in scan: ControlCenterScan
    ) throws -> Bool {
        let containsWindow = scan.snapshots.indices.contains {
            scan.isWindow($0)
        }
        guard !containsWindow else {
            return false
        }

        DiagnosticLog.record(
            "Reopening Control Center because its panel is not visible"
        )
        try scan.press(elementIndex)
        return true
    }

    private static func recoverScreenMirroringIfNeeded(
        from scan: ControlCenterScan
    ) throws {
        let navigationAction = ControlCenterNavigationPlanner.action(
            for: scan.snapshots
        )

        switch navigationAction {
        case let .openControlCenter(elementIndex):
            try reopenControlCenterIfNeeded(
                elementIndex: elementIndex,
                in: scan
            )
        case let .openScreenMirroring(elementIndex):
            guard !scan.isWindow(elementIndex) else {
                return
            }
            DiagnosticLog.record(
                "Reopening Screen Mirroring after its panel disappeared"
            )
            try scan.press(elementIndex)
        case .screenMirroringAlreadyOpen:
            return
        case .screenMirroringNotFound:
            return
        }
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

    private static func automation(
        for application: AXUIElement
    ) -> ControlCenterAutomation {
        ControlCenterAutomation(
            maximumAttempts: ControlCenterTiming.actionAttempts,
            scan: {
                let elements = accessibilityTree(from: application)
                return ControlCenterScan(
                    snapshots: elements.snapshots,
                    isWindow: { index in
                        elements.indices.contains(index)
                            && elements[index].role == kAXWindowRole
                    },
                    press: { index in
                        try press(elements, at: index)
                    },
                    activateDevicePrimaryAction: { index in
                        try activateDevicePrimaryAction(
                            elements,
                            at: index
                        )
                    }
                )
            },
            wait: {
                try await Task.sleep(for: ControlCenterTiming.actionDelay)
            }
        )
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

    private static func activateDevicePrimaryAction(
        _ elements: [AXUIElement],
        at index: Int
    ) throws {
        guard elements.indices.contains(index) else {
            throw MacDisplayConnectError.visionProControlNotFound
        }

        let deviceRow = elements[index]
        guard deviceRow.role == kAXDisclosureTriangleRole,
              deviceRow.selectedValue == true,
              let identifier = deviceRow.identifier,
              identifier.hasPrefix("screen-mirroring-device-AirPlay:"),
              deviceRow.searchableText.contains(where: {
                  $0.normalizedForDiagnostics.contains("vision pro")
              }),
              let deviceFrame = deviceRow.frame,
              deviceFrame.width > 0,
              deviceFrame.height > 0
        else {
            DiagnosticLog.record(
                "Device disconnect action rejected: stale device row"
            )
            throw MacDisplayConnectError.visionProControlNotFound
        }

        let refreshedSnapshots = elements.snapshots
        guard refreshedSnapshots.indices.contains(index),
              let visionProName = refreshedSnapshots[index].text.first(where: {
                  $0.normalizedForDiagnostics.contains("vision pro")
              }),
              ControlCenterDisconnectPlanner.action(
                  for: refreshedSnapshots,
                  visionProName: visionProName
              ) == .disconnectAirPlayDevice(elementIndex: index),
              let modeElementPositions =
                  ControlCenterDeviceActionValidation.modeElementPositions(
                      in: refreshedSnapshots,
                      deviceElementIndex: index
                  ),
              modeElementPositions.allSatisfy(elements.indices.contains)
        else {
            DiagnosticLog.record(
                "Device disconnect action rejected: unsafe current state"
            )
            throw MacDisplayConnectError.visionProControlNotFound
        }

        let controlCenterMenuItems = elements.filter {
            $0.role == kAXMenuBarItemRole
                && $0.identifier == "com.apple.menuextra.controlcenter"
        }
        guard controlCenterMenuItems.count == 1,
              let controlCenterMenuItem = controlCenterMenuItems.first,
              let menuItemFrame = controlCenterMenuItem.frame,
              menuItemFrame.width > 0,
              menuItemFrame.height > 0
        else {
            DiagnosticLog.record(
                "Device disconnect action rejected: "
                    + "Control Center cannot be dismissed safely"
            )
            throw MacDisplayConnectError.visionProControlNotFound
        }

        let matchingModeRows = modeElementPositions.map { elements[$0] }
        let modeFrames = matchingModeRows.compactMap(\.frame)
        let allMatchingModeRows = elements.filter {
            $0.identifier == identifier && $0.kind == .checkbox
        }
        let allModeFrames = allMatchingModeRows.compactMap(\.frame)
        guard modeFrames.count == matchingModeRows.count,
              allModeFrames.count == allMatchingModeRows.count,
              let point =
                  ControlCenterDeviceActionGeometry.primaryActionPoint(
                      deviceFrame: deviceFrame,
                      modeFrames: modeFrames
                  ),
              allModeFrames.allSatisfy({
                  !$0.contains(point)
              })
        else {
            DiagnosticLog.record(
                "Device disconnect action rejected: unsafe row geometry"
            )
            throw MacDisplayConnectError.visionProControlNotFound
        }

        guard let eventSource = CGEventSource(
            stateID: .combinedSessionState
        ) else {
            throw MacDisplayConnectError.visionProControlNotFound
        }
        let previousMouseLocation = CGEvent(source: eventSource)?.location
        try postMouseClick(at: point, source: eventSource)
        Thread.sleep(forTimeInterval: 0.3)
        try postMouseClick(
            at: CGPoint(x: menuItemFrame.midX, y: menuItemFrame.midY),
            source: eventSource
        )

        if let previousMouseLocation,
           let restore = CGEvent(
               mouseEventSource: eventSource,
               mouseType: .mouseMoved,
               mouseCursorPosition: previousMouseLocation,
               mouseButton: .left
           )
        {
            restore.post(tap: .cghidEventTap)
        }

        DiagnosticLog.record(
            "Activated device disconnect action for "
                + "\(deviceRow.diagnosticSummary)"
        )
    }

    private static func postMouseClick(
        at point: CGPoint,
        source: CGEventSource
    ) throws {
        guard let move = CGEvent(
            mouseEventSource: source,
            mouseType: .mouseMoved,
            mouseCursorPosition: point,
            mouseButton: .left
        ),
            let mouseDown = CGEvent(
                mouseEventSource: source,
                mouseType: .leftMouseDown,
                mouseCursorPosition: point,
                mouseButton: .left
            ),
            let mouseUp = CGEvent(
                mouseEventSource: source,
                mouseType: .leftMouseUp,
                mouseCursorPosition: point,
                mouseButton: .left
            )
        else {
            throw MacDisplayConnectError.visionProControlNotFound
        }
        mouseDown.setIntegerValueField(.mouseEventClickState, value: 1)
        mouseUp.setIntegerValueField(.mouseEventClickState, value: 1)

        move.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.12)
        mouseDown.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.1)
        mouseUp.post(tap: .cghidEventTap)
    }
}

enum ControlCenterDeviceActionValidation {
    static func modeElementPositions(
        in elements: [ControlCenterElement],
        deviceElementIndex: Int
    ) -> [Int]? {
        let matchingDevicePositions = elements.indices.filter {
            elements[$0].index == deviceElementIndex
        }
        guard matchingDevicePositions.count == 1,
              let devicePosition = matchingDevicePositions.first
        else {
            return nil
        }

        let deviceRow = elements[devicePosition]
        guard deviceRow.kind == .disclosure,
              deviceRow.isSelected == true,
              let identifier = deviceRow.identifier,
              identifier.hasPrefix("screen-mirroring-device-AirPlay:"),
              deviceRow.text.contains(where: {
                  $0.normalizedForDiagnostics.contains("vision pro")
              })
        else {
            return nil
        }

        let nextDevicePosition = elements.indices.first { position in
            guard position > devicePosition,
                  elements[position].kind != .other,
                  let candidateIdentifier = elements[position].identifier,
                  candidateIdentifier.hasPrefix(
                      "screen-mirroring-device-"
                  )
            else {
                return false
            }

            if candidateIdentifier != identifier {
                return true
            }
            return elements[position].kind == .disclosure
                || elements[position].text.contains {
                    $0.normalizedForDiagnostics.contains("vision pro")
                }
        }
        let groupEnd = nextDevicePosition ?? elements.endIndex
        let modePositions = elements.indices.filter {
            $0 > devicePosition
                && $0 < groupEnd
                && elements[$0].kind == .checkbox
                && elements[$0].identifier == identifier
        }
        let modeRows = modePositions.map { elements[$0] }
        let macVirtualDisplayRows = modeRows.filter {
            $0.text.contains {
                $0.normalizedForDiagnostics == "mac virtual display"
            }
        }
        let otherModeRows = modeRows.filter {
            !$0.text.contains {
                $0.normalizedForDiagnostics == "mac virtual display"
            }
        }
        guard macVirtualDisplayRows.count == 1,
              macVirtualDisplayRows[0].isSelected == true,
              otherModeRows.allSatisfy({ $0.isSelected == false })
        else {
            return nil
        }

        return modePositions
    }
}

enum ControlCenterDeviceActionGeometry {
    static func primaryActionPoint(
        deviceFrame: CGRect,
        modeFrames: [CGRect]
    ) -> CGPoint? {
        guard deviceFrame.width > 0,
              deviceFrame.height > 0,
              !modeFrames.isEmpty,
              modeFrames.allSatisfy({
                  $0.width > 0 && $0.height > 0
              })
        else {
            return nil
        }

        let firstModeTop = modeFrames
            .map(\.minY)
            .filter { $0 > deviceFrame.minY }
            .min()
            ?? deviceFrame.maxY
        let headerBottom = min(deviceFrame.maxY, firstModeTop)
        guard headerBottom > deviceFrame.minY else {
            return nil
        }

        let point = CGPoint(
            x: deviceFrame.minX + deviceFrame.width / 3,
            y: deviceFrame.minY
                + (headerBottom - deviceFrame.minY) / 2
        )
        guard deviceFrame.contains(point),
              modeFrames.allSatisfy({ !$0.contains(point) })
        else {
            return nil
        }
        return point
    }
}

@MainActor
struct ControlCenterAutomation {
    let maximumAttempts: Int
    let scan: () throws -> ControlCenterScan
    let wait: () async throws -> Void
}

@MainActor
struct ControlCenterScan {
    let snapshots: [ControlCenterElement]
    let isWindow: (Int) -> Bool
    let press: (Int) throws -> Void
    let activateDevicePrimaryAction: (Int) throws -> Void
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
        case .screenMirroringAlreadyOpen:
            "screenMirroringAlreadyOpen"
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

private extension ControlCenterDisconnectAction {
    var diagnosticName: String {
        switch self {
        case let .expandVisionPro(index):
            "expandVisionPro(index=\(index))"
        case let .disconnectAirPlayDevice(index):
            "disconnectAirPlayDevice(index=\(index))"
        case let .disconnectSidecar(index):
            "disconnectSidecar(index=\(index))"
        case .alreadyDisconnected:
            "alreadyDisconnected"
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

    var frame: CGRect? {
        guard let position: AXValue = copiedAttribute(
            kAXPositionAttribute as CFString
        ),
            let size: AXValue = copiedAttribute(
                kAXSizeAttribute as CFString
            )
        else {
            return nil
        }

        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position, .cgPoint, &point),
              AXValueGetValue(size, .cgSize, &dimensions)
        else {
            return nil
        }
        return CGRect(origin: point, size: dimensions)
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
