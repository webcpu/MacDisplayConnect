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

    private(set) var phase = ConnectionPhase.ready
    private let connect: ConnectOperation
    private let activateForRemoteConnection: ActivationOperation
    private let connectionStatus: ConnectionStatusOperation
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
        }
    ) {
        self.connect = connect
        self.activateForRemoteConnection = activateForRemoteConnection
        self.connectionStatus = connectionStatus
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

    func refreshConnectionStatus() {
        applyConnectionStatus(connectionStatus())
    }

    func startRemoteControl() async {
        guard remoteServer == nil else {
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

    func connectAndExtend(
        visionProName: String? = nil
    ) async -> RemoteResponse {
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
        DiagnosticLog.record("Activating Mac app for remote request")
        let isApplicationActive = await activateForRemoteConnection()
        DiagnosticLog.record("Mac app active: \(isApplicationActive)")
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
}

@MainActor
private func activateApplication() async -> Bool {
    NSApp.windows.first(where: \.isVisible)?.makeKeyAndOrderFront(nil)
    NSApp.activate()

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
