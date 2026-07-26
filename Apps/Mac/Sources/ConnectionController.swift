import Foundation

@MainActor
struct ConnectionController {
    func connectAndExtend(
        visionProName: String? = nil
    ) async throws -> String {
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
            return "Mac Virtual Display is connected."
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

        return didConnect
            ? "Mac Virtual Display is connected."
            : "Mac Virtual Display is already connected."
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
