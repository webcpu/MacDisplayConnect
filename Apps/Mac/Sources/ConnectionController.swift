import Foundation

@MainActor
struct ConnectionController {
    func connectAndExtend(
        visionProName: String? = nil
    ) async throws -> String {
        let transition = try await connectTransition(
            visionProName: visionProName
        )
        return transition == .changed
            ? "Mac Virtual Display is connected."
            : "Mac Virtual Display is already connected."
    }

    func connectForSystemTest(
        visionProName: String? = nil
    ) async throws -> Bool {
        try await connectTransition(visionProName: visionProName) == .changed
    }

    private func connectTransition(
        visionProName: String?
    ) async throws -> DisplayTransition {
        DiagnosticLog.record("ConnectionController started")
        try requireAccessibilityAccess()
        try await ControlCenter.openScreenMirroring()
        try await Task.sleep(for: .milliseconds(700))

        let monitor = MacVirtualDisplayMonitor.shared
        let snapshot = monitor.snapshotBeforeConnectionAttempt()

        let didConnect: Bool
        do {
            didConnect = try await ControlCenter.connectMacVirtualDisplay(
                visionProName: visionProName
            )
        } catch {
            guard try await monitor.confirmConnection(after: snapshot) else {
                throw error
            }

            DiagnosticLog.record(
                "Display became active while Control Center was updating"
            )
            return .changed
        }

        let isConnected = if didConnect {
            try await monitor.confirmConnection(after: snapshot)
        } else {
            monitor.learnAlreadyConnectedDisplayIfUnambiguous()
        }
        DiagnosticLog.record(
            "Mac Virtual Display state confirmed: \(isConnected)"
        )

        guard isConnected else {
            throw MacDisplayConnectError.connectionNotConfirmed
        }

        return didConnect ? .changed : .unchanged
    }

    func disconnect(
        visionProName: String? = nil
    ) async throws -> String {
        let transition = try await disconnectTransition(
            visionProName: visionProName
        )
        return transition == .changed
            ? "Mac Virtual Display is disconnected."
            : "Mac Virtual Display is already disconnected."
    }

    func disconnectForSystemTest(
        visionProName: String? = nil
    ) async throws -> Bool {
        try await disconnectTransition(visionProName: visionProName) == .changed
    }

    private func disconnectTransition(
        visionProName: String?
    ) async throws -> DisplayTransition {
        DiagnosticLog.record("DisconnectionController started")
        try requireAccessibilityAccess()

        let monitor = MacVirtualDisplayMonitor.shared
        let snapshot = monitor.snapshotBeforeDisconnectionAttempt()

        try await ControlCenter.openScreenMirroring()
        try await Task.sleep(for: .milliseconds(700))

        let didDisconnect: Bool
        do {
            didDisconnect = try await ControlCenter.disconnectMacVirtualDisplay(
                visionProName: visionProName
            )
        } catch {
            guard try await monitor.confirmDisconnection(after: snapshot) else {
                throw error
            }

            DiagnosticLog.record(
                "Display became inactive while Control Center was updating"
            )
            return .changed
        }

        guard didDisconnect else {
            monitor.confirmAlreadyDisconnected()
            DiagnosticLog.record(
                "Mac Virtual Display was already disconnected"
            )
            return .unchanged
        }

        let isDisconnected = try await monitor.confirmDisconnection(
            after: snapshot
        )
        DiagnosticLog.record(
            "Mac Virtual Display disconnection confirmed: \(isDisconnected)"
        )

        guard isDisconnected else {
            throw MacDisplayConnectError.disconnectionNotConfirmed
        }

        return .changed
    }

    private func requireAccessibilityAccess() throws {
        let hasAccess = ControlCenter.hasAccessibilityAccess
        DiagnosticLog.record("Accessibility trusted: \(hasAccess)")

        guard hasAccess else {
            DiagnosticLog.record("Requesting Accessibility permission")
            ControlCenter.requestAccessibilityAccess()
            throw MacDisplayConnectError.accessibilityPermissionRequired
        }
    }
}

private enum DisplayTransition {
    case changed
    case unchanged
}
