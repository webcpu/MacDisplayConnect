import MacDisplayConnectCore
import MacDisplayConnectTransport
import Foundation
import Network
import Observation
import UIKit

@Observable
@MainActor
final class VisionConnectionModel {
    typealias DiscoverOperation =
        @Sendable () -> AsyncStream<RemoteDiscoveryEvent>
    typealias VisionProNameOperation = @MainActor () -> String
    typealias AutoConnectEnabledOperation = @MainActor () -> Bool
    typealias ConnectOperation =
        @Sendable (RemoteRequest, NWEndpoint) async throws -> RemoteResponse
    typealias StatusOperation =
        @Sendable (NWEndpoint) async throws -> RemoteResponse

    private(set) var macs: [RemoteMac] = []
    private(set) var phase = VisionConnectionPhase.searching {
        didSet {
            guard oldValue != phase else {
                return
            }
            VisionDiagnosticLog.record(
                "Connection phase: \(oldValue.title) -> \(phase.title)"
            )
        }
    }

    @ObservationIgnored private let discover: DiscoverOperation
    @ObservationIgnored private let readVisionProName: VisionProNameOperation
    @ObservationIgnored private let readAutoConnectEnabled:
        AutoConnectEnabledOperation
    @ObservationIgnored private let sendConnect: ConnectOperation
    @ObservationIgnored private let sendStatus: StatusOperation
    @ObservationIgnored private var lastSelectedMac: RemoteMac?
    @ObservationIgnored private var isSceneActive = false
    @ObservationIgnored private var isAutoConnectArmed = false
    @ObservationIgnored private var lastConnectionAvailability: Bool?
    @ObservationIgnored private var statusGeneration = 0

    init(
        discover: @escaping DiscoverOperation = {
            RemoteBrowser().events()
        },
        visionProName: @escaping VisionProNameOperation = {
            UIDevice.current.name
        },
        autoConnectEnabled: @escaping AutoConnectEnabledOperation = {
            true
        },
        connect: @escaping ConnectOperation = { request, endpoint in
            try await RemoteClient(timeout: .seconds(120))
                .send(request, to: endpoint)
        },
        status: @escaping StatusOperation = { endpoint in
            try await RemoteClient().send(.status, to: endpoint)
        }
    ) {
        self.discover = discover
        readVisionProName = visionProName
        readAutoConnectEnabled = autoConnectEnabled
        self.sendConnect = connect
        self.sendStatus = status
    }

    var isConnecting: Bool {
        if case .connecting = phase {
            true
        } else {
            false
        }
    }

    func startDiscovery() async {
        for await event in discover() {
            await apply(event)
        }
    }

    func sceneDidBecomeActive() async {
        guard !Task.isCancelled else {
            return
        }

        isSceneActive = true
        isAutoConnectArmed = true
        lastConnectionAvailability = nil
        await refreshStatus()
    }

    func sceneDidLeaveActive() {
        isSceneActive = false
        statusGeneration += 1
        lastConnectionAvailability = nil
        guard isAutoConnectArmed else {
            return
        }

        isAutoConnectArmed = false
        VisionDiagnosticLog.record(
            "Auto-connect stopped: scene is no longer active"
        )
    }

    func connect(to mac: RemoteMac) async {
        guard !isConnecting else {
            return
        }

        statusGeneration += 1
        if lastSelectedMac?.endpoint != mac.endpoint {
            lastConnectionAvailability = nil
        }
        lastSelectedMac = mac
        phase = .connecting(mac.name)

        do {
            phase = VisionConnectionPhase(
                response: try await sendConnect(
                    .connect(visionProName: readVisionProName()),
                    mac.endpoint
                )
            )
        } catch is CancellationError {
            phase = macs.isEmpty ? .searching : .ready
        } catch {
            let message = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
            phase = .failure(message)
        }
    }

    func refreshStatus() async {
        guard !isConnecting, let mac = lastSelectedMac ?? macs.first else {
            return
        }

        lastSelectedMac = mac
        statusGeneration += 1
        let generation = statusGeneration

        let status: (isConnected: Bool, isAvailable: Bool)?
        do {
            if case let .status(isConnected, isAvailable) =
                try await sendStatus(mac.endpoint) {
                status = (isConnected, isAvailable)
            } else {
                status = nil
            }
        } catch is CancellationError {
            return
        } catch {
            status = nil
        }

        guard generation == statusGeneration,
              !isConnecting,
              lastSelectedMac?.endpoint == mac.endpoint
        else {
            return
        }

        if let status {
            phase = phase.applyingConnectionStatus(
                status.isConnected,
                hasAvailableMacs: !macs.isEmpty
            )
        } else {
            phase = phase.applyingUnavailableStatus()
        }

        if let status {
            await applyConnectionAvailability(
                status.isAvailable,
                confirmedConnected: status.isConnected
            )
        }
    }

    func monitorStatus() async {
        while !Task.isCancelled {
            await refreshStatus()

            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                return
            }
        }
    }

    private func apply(_ event: RemoteDiscoveryEvent) async {
        switch event {
        case let .results(macs):
            let didRemoveSelectedMac = lastSelectedMac.map { selectedMac in
                !macs.contains { $0.endpoint == selectedMac.endpoint }
            } ?? false
            self.macs = macs

            if didRemoveSelectedMac {
                statusGeneration += 1
                lastConnectionAvailability = nil
            }

            if didRemoveSelectedMac, phase.isConnected {
                phase = .statusUnavailable
            } else if phase.acceptsDiscoveryUpdates {
                phase = macs.isEmpty ? .searching : .ready
            }

            if isSceneActive {
                await refreshStatus()
            }
        case let .unavailable(message):
            if macs.isEmpty, phase.acceptsDiscoveryUpdates {
                phase = .discoveryFailure(message)
            }
        }
    }

    private func applyConnectionAvailability(
        _ isAvailable: Bool,
        confirmedConnected: Bool
    ) async {
        guard isSceneActive else {
            return
        }

        let wasAvailable = lastConnectionAvailability
        lastConnectionAvailability = isAvailable

        guard isAvailable else {
            if wasAvailable != false {
                VisionDiagnosticLog.record(
                    "Auto-connect waiting: Mac is unavailable"
                )
            }
            return
        }

        if wasAvailable == false {
            isAutoConnectArmed = true
            VisionDiagnosticLog.record(
                "Auto-connect armed: Mac became available"
            )
        }

        await attemptAutoConnect(
            confirmedConnected: confirmedConnected
        )
    }

    private func attemptAutoConnect(
        confirmedConnected: Bool = false
    ) async {
        switch autoConnectDecision(
            isEnabled: readAutoConnectEnabled(),
            isArmed: isAutoConnectArmed,
            phase: phase,
            preferredMac: lastSelectedMac,
            discoveredMacs: macs
        ) {
        case .noAction:
            return
        case .disabled:
            isAutoConnectArmed = false
            VisionDiagnosticLog.record("Auto-connect disabled")
        case .waitForPreferredMac:
            VisionDiagnosticLog.record(
                "Auto-connect waiting for preferred Mac discovery"
            )
        case .alreadyConnected:
            if confirmedConnected {
                isAutoConnectArmed = false
                VisionDiagnosticLog.record(
                    "Auto-connect skipped: connection confirmed"
                )
            } else {
                VisionDiagnosticLog.record(
                    "Auto-connect waiting for refreshed status"
                )
            }
        case .connectionInProgress:
            isAutoConnectArmed = false
            VisionDiagnosticLog.record(
                "Auto-connect skipped: connection already in progress"
            )
        case let .connect(mac):
            isAutoConnectArmed = false
            VisionDiagnosticLog.record(
                "Auto-connect attempting \(mac.name)"
            )
            await connect(to: mac)
            VisionDiagnosticLog.record(
                "Auto-connect outcome: \(phase.title)"
            )
        }
    }
}

enum AutoConnectDecision: Equatable {
    case noAction
    case disabled
    case waitForPreferredMac
    case alreadyConnected
    case connectionInProgress
    case connect(RemoteMac)
}

func autoConnectDecision(
    isEnabled: Bool,
    isArmed: Bool,
    phase: VisionConnectionPhase,
    preferredMac: RemoteMac?,
    discoveredMacs: [RemoteMac]
) -> AutoConnectDecision {
    guard isArmed else {
        return .noAction
    }

    guard isEnabled else {
        return .disabled
    }

    switch phase {
    case .success:
        return .alreadyConnected
    case .connecting:
        return .connectionInProgress
    default:
        return preferredMac
            .flatMap { preferredMac in
                discoveredMacs.first {
                    $0.endpoint == preferredMac.endpoint
                }
            }
            .map(AutoConnectDecision.connect)
            ?? .waitForPreferredMac
    }
}

enum VisionConnectionPhase: Equatable {
    case searching
    case ready
    case connecting(String)
    case success(String)
    case statusUnavailable
    case failure(String)
    case discoveryFailure(String)

    init(response: RemoteResponse) {
        switch response {
        case let .succeeded(message):
            self = .success(message)
        case .busy:
            self = .failure(
                "The Mac is already connecting. Try again shortly."
            )
        case let .failed(message):
            self = .failure(message)
        case let .status(isConnected, _):
            self = isConnected
                ? .success(Self.connectedMessage)
                : .ready
        }
    }

    func applyingConnectionStatus(
        _ isConnected: Bool,
        hasAvailableMacs: Bool
    ) -> Self {
        if isConnected {
            return .success(Self.connectedMessage)
        }

        switch self {
        case .success, .statusUnavailable:
            return hasAvailableMacs ? .ready : .searching
        default:
            return self
        }
    }

    func applyingUnavailableStatus() -> Self {
        switch self {
        case .success, .statusUnavailable:
            .statusUnavailable
        default:
            self
        }
    }

    var acceptsDiscoveryUpdates: Bool {
        switch self {
        case .searching, .ready, .statusUnavailable, .discoveryFailure:
            true
        case .connecting, .success, .failure:
            false
        }
    }

    var title: String {
        switch self {
        case .searching:
            "Finding Your Mac"
        case .ready:
            "Mac Found"
        case .connecting:
            "Connecting…"
        case .success:
            "Connected"
        case .statusUnavailable:
            "Status Unavailable"
        case .failure, .discoveryFailure:
            "Couldn’t Connect"
        }
    }

    var message: String {
        switch self {
        case .searching:
            "Open Mac Display Connect on your Mac. It will appear here automatically."
        case .ready:
            "Choose your Mac to start Mac Virtual Display."
        case let .connecting(name):
            "Asking \(name) to start Mac Virtual Display…"
        case let .success(message), let .failure(message):
            message
        case .statusUnavailable:
            "The Mac could not confirm whether Mac Virtual Display is connected."
        case let .discoveryFailure(message):
            "Mac discovery is unavailable: \(message)"
        }
    }

    var actionTitle: String? {
        switch self {
        case .ready, .statusUnavailable:
            "Connect"
        case .failure:
            "Try Again"
        case .searching, .connecting, .success, .discoveryFailure:
            nil
        }
    }

    var isConnected: Bool {
        if case .success = self {
            true
        } else {
            false
        }
    }

    private static let connectedMessage =
        "Mac Virtual Display is connected."
}
