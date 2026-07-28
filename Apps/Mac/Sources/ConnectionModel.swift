import AppKit
import MacDisplayConnectCore
import MacDisplayConnectTransport
import Foundation
import Observation

@Observable
@MainActor
final class ConnectionModel {
    typealias ConnectOperation =
        @MainActor (String?) async throws -> String
    typealias ActivationOperation = @MainActor () async -> Bool
    typealias ConnectionStatusOperation = @MainActor () -> Bool
    typealias AccessibilityAccessCheck = @MainActor () -> Bool
    typealias AccessibilityAccessRequest = @MainActor () -> Void
    typealias LocalNetworkAccessEvents =
        @Sendable () -> AsyncStream<LocalNetworkAccessStatus>
    typealias LocalNetworkRetryDelay = @Sendable () async -> Void

    private(set) var phase = ConnectionPhase.ready
    private(set) var accessibilityAccessGranted: Bool
    private(set) var localNetworkAccess: LocalNetworkAccessStatus
    private let connect: ConnectOperation
    private let activateForRemoteConnection: ActivationOperation
    private let connectionStatus: ConnectionStatusOperation
    private let hasAccessibilityAccess: AccessibilityAccessCheck
    private let requestAccessibilityAccess: AccessibilityAccessRequest
    private let localNetworkAccessEvents: LocalNetworkAccessEvents
    private let waitBeforeLocalNetworkRetry: LocalNetworkRetryDelay
    @ObservationIgnored private var remoteServer: RemoteServer?

    init(
        connect: @escaping ConnectOperation = { visionProName in
            try await ConnectionController().connectAndExtend(
                visionProName: visionProName
            )
        },
        activateForRemoteConnection: @escaping ActivationOperation = {
            await activateApplication()
        },
        connectionStatus: @escaping ConnectionStatusOperation = {
            MacVirtualDisplayMonitor.shared.isConnected
        },
        hasAccessibilityAccess:
            @escaping AccessibilityAccessCheck = {
                ControlCenter.hasAccessibilityAccess
            },
        requestAccessibilityAccess:
            @escaping AccessibilityAccessRequest = {
                ControlCenter.requestAccessibilityAccess()
            },
        localNetworkAccessEvents:
            @escaping LocalNetworkAccessEvents = {
                LocalNetworkAccessMonitor().events()
            },
        waitBeforeLocalNetworkRetry:
            @escaping LocalNetworkRetryDelay = {
                try? await Task.sleep(for: .seconds(1))
            },
        initialLocalNetworkAccess: LocalNetworkAccessStatus = .checking
    ) {
        self.connect = connect
        self.activateForRemoteConnection = activateForRemoteConnection
        self.connectionStatus = connectionStatus
        self.hasAccessibilityAccess = hasAccessibilityAccess
        self.requestAccessibilityAccess = requestAccessibilityAccess
        self.localNetworkAccessEvents = localNetworkAccessEvents
        self.waitBeforeLocalNetworkRetry = waitBeforeLocalNetworkRetry
        accessibilityAccessGranted = hasAccessibilityAccess()
        localNetworkAccess = initialLocalNetworkAccess
        DiagnosticLog.record(
            "Application launched on "
                + ProcessInfo.processInfo.operatingSystemVersionString
        )
    }

    var isWorking: Bool {
        if case .working = phase {
            true
        } else {
            false
        }
    }

    var viewState: MacDisplayConnectViewState {
        allRequiredPermissionsGranted ? .connection : .permissions
    }

    var allRequiredPermissionsGranted: Bool {
        accessibilityAccessGranted && localNetworkAccess == .granted
    }

    func refreshConnectionStatus() {
        applyConnectionStatus(connectionStatus())
    }

    func refreshAccessibilityPermission() {
        let isGranted = hasAccessibilityAccess()
        guard accessibilityAccessGranted != isGranted else {
            return
        }

        accessibilityAccessGranted = isGranted
        DiagnosticLog.record(
            "Accessibility access changed: \(isGranted)"
        )
    }

    func requestAccessibilityPermission() {
        requestAccessibilityAccess()
        refreshAccessibilityPermission()
    }

    func monitorPermissions() async {
        refreshAccessibilityPermission()

        while !Task.isCancelled {
            for await status in localNetworkAccessEvents() {
                guard !Task.isCancelled else {
                    break
                }

                localNetworkAccess = status
                DiagnosticLog.record(
                    "Local Network access changed: \(status.diagnosticName)"
                )

                if status == .granted {
                    await startRemoteControl()
                } else {
                    await stopRemoteControl()
                }
            }

            guard !Task.isCancelled else {
                break
            }

            DiagnosticLog.record("Retrying Local Network access monitor")
            await waitBeforeLocalNetworkRetry()
        }

        await stopRemoteControl()
    }

    func startRemoteControl() async {
        guard localNetworkAccess == .granted,
              remoteServer == nil else {
            return
        }

        let server = RemoteServer { [weak self] request in
            guard let self else {
                return .failed(message: "The Mac app is no longer running.")
            }

            return await self.handleRemoteRequest(request)
        }
        remoteServer = server

        do {
            let serviceName = Host.current().localizedName ?? "Mac"
            let port = try await server.start(serviceName: serviceName)
            DiagnosticLog.record(
                "Remote control listening as \(serviceName) on port \(port)"
            )
        } catch {
            remoteServer = nil
            DiagnosticLog.record(
                "Remote control listener failed: \(error.localizedDescription)"
            )
        }
    }

    func stopRemoteControl() async {
        guard let remoteServer else {
            return
        }

        self.remoteServer = nil
        await remoteServer.stop()
        DiagnosticLog.record("Remote control stopped")
    }

    func openSystemSettings() {
        let url = URL(
            fileURLWithPath: "/System/Applications/System Settings.app"
        )
        NSWorkspace.shared.open(url)
    }

    func connectAndExtend(
        visionProName: String? = nil
    ) async -> RemoteResponse {
        refreshAccessibilityPermission()

        guard allRequiredPermissionsGranted else {
            let message = missingPermissionMessage
            DiagnosticLog.record(
                "Connection blocked by permissions: \(message)"
            )
            return .failed(message: message)
        }

        guard !isWorking else {
            return .busy
        }

        DiagnosticLog.record("Connect requested")
        phase = .working

        do {
            let message = try await connect(visionProName)
            DiagnosticLog.record("Connection flow succeeded: \(message)")
            phase = .success(message)
            return .succeeded(message: message)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
            DiagnosticLog.record(
                "Connection flow failed: \(type(of: error)): \(message)"
            )
            phase = .failure(message)
            return .failed(message: message)
        }
    }

    func handleRemoteRequest(_ request: RemoteRequest) async -> RemoteResponse {
        switch request {
        case let .connect(visionProName):
            return await handleRemoteConnect(visionProName: visionProName)
        case .status:
            let isConnected = connectionStatus()
            applyConnectionStatus(isConnected)
            DiagnosticLog.record(
                "Remote status response: connected=\(isConnected)"
            )
            return .status(isConnected: isConnected)
        }
    }

    func handleRemoteConnect(
        visionProName: String? = nil
    ) async -> RemoteResponse {
        DiagnosticLog.record(
            "Remote connect request received; target="
                + (visionProName ?? "automatic")
        )
        guard !isWorking else {
            DiagnosticLog.record("Remote response: busy")
            return .busy
        }

        DiagnosticLog.record("Activating Mac app for remote request")
        let isApplicationActive = await activateForRemoteConnection()
        DiagnosticLog.record("Mac app active: \(isApplicationActive)")
        guard isApplicationActive else {
            let message =
                "Mac Display Connect could not move to the foreground. "
                    + "Try again."
            phase = .failure(message)
            DiagnosticLog.record("Remote response: failed")
            return .failed(message: message)
        }

        let response = await connectAndExtend(visionProName: visionProName)
        DiagnosticLog.record("Remote response: \(response.diagnosticName)")
        return response
    }

    private func applyConnectionStatus(_ isConnected: Bool) {
        guard !isWorking else {
            return
        }

        if isConnected {
            phase = .success("Mac Virtual Display is connected.")
        } else if case .success = phase {
            phase = .ready
        }
    }

    private var missingPermissionMessage: String {
        if !accessibilityAccessGranted {
            return "Grant Accessibility access to Mac Display Connect, "
                + "then try again."
        }

        switch localNetworkAccess {
        case .needsAccess:
            return "Grant Local Network access to Mac Display Connect, "
                + "then try again."
        case .checking:
            return "Mac Display Connect is still checking Local Network "
                + "access. Try again in a moment."
        case .unavailable:
            return "Local Network access is unavailable. Check Wi-Fi "
                + "and try again."
        case .granted:
            return "Grant the required permissions, then try again."
        }
    }
}

@MainActor
private func activateApplication() async -> Bool {
    NSApp.windows.first(where: \.isVisible)?.makeKeyAndOrderFront(nil)
    NSApp.activate()

    if !NSApp.isActive {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.addsToRecentItems = false

        do {
            let application = try await NSWorkspace.shared.openApplication(
                at: Bundle.main.bundleURL,
                configuration: configuration
            )
            DiagnosticLog.record(
                "Workspace foreground activation requested: pid="
                    + "\(application.processIdentifier)"
            )
        } catch {
            DiagnosticLog.record(
                "Workspace foreground activation failed: "
                    + error.localizedDescription
            )
        }
    }

    for _ in 0..<20 where !NSApp.isActive {
        try? await Task.sleep(for: .milliseconds(50))
    }

    return NSApp.isActive
}

private extension RemoteResponse {
    var diagnosticName: String {
        switch self {
        case .succeeded:
            "succeeded"
        case .busy:
            "busy"
        case .failed:
            "failed"
        case .status:
            "status"
        }
    }
}

enum ConnectionPhase: Equatable {
    case ready
    case working
    case success(String)
    case failure(String)

    var title: String {
        switch self {
        case .ready:
            "Ready to Connect"
        case .working:
            "Connecting…"
        case .success:
            "Connected"
        case .failure:
            "Couldn’t Connect"
        }
    }

    var message: String {
        switch self {
        case .ready:
            "Wear and unlock your Apple Vision Pro."
        case .working:
            "Starting Mac Virtual Display…"
        case let .success(message), let .failure(message):
            message
        }
    }

    var actionTitle: String? {
        switch self {
        case .ready:
            "Connect"
        case .failure:
            "Try Again"
        case .working, .success:
            nil
        }
    }
}

enum MacDisplayConnectViewState: Equatable {
    case permissions
    case connection
}

private extension LocalNetworkAccessStatus {
    var diagnosticName: String {
        switch self {
        case .checking:
            "checking"
        case .granted:
            "granted"
        case .needsAccess:
            "needs-access"
        case .unavailable:
            "unavailable"
        }
    }
}
