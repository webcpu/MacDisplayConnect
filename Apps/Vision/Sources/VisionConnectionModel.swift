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
    typealias ConnectOperation =
        @Sendable (RemoteRequest, NWEndpoint) async throws -> RemoteResponse
    typealias StatusOperation =
        @Sendable (NWEndpoint) async throws -> RemoteResponse

    private(set) var macs: [RemoteMac] = []
    private(set) var phase = VisionConnectionPhase.searching

    @ObservationIgnored private let discover: DiscoverOperation
    @ObservationIgnored private let readVisionProName: VisionProNameOperation
    @ObservationIgnored private let sendConnect: ConnectOperation
    @ObservationIgnored private let sendStatus: StatusOperation
    @ObservationIgnored private var lastSelectedMac: RemoteMac?
    @ObservationIgnored private var statusGeneration = 0

    init(
        discover: @escaping DiscoverOperation = {
            RemoteBrowser().events()
        },
        visionProName: @escaping VisionProNameOperation = {
            UIDevice.current.name
        },
        connect: @escaping ConnectOperation = { request, endpoint in
            try await RemoteClient().send(request, to: endpoint)
        },
        status: @escaping StatusOperation = { endpoint in
            try await RemoteClient().send(.status, to: endpoint)
        }
    ) {
        self.discover = discover
        readVisionProName = visionProName
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
            apply(event)
        }
    }

    func connect(to mac: RemoteMac) async {
        guard !isConnecting else {
            return
        }

        statusGeneration += 1
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

        let isConnected: Bool?
        do {
            if case let .status(value) = try await sendStatus(mac.endpoint) {
                isConnected = value
            } else {
                isConnected = nil
            }
        } catch is CancellationError {
            return
        } catch {
            isConnected = nil
        }

        guard generation == statusGeneration,
              !isConnecting,
              lastSelectedMac?.endpoint == mac.endpoint
        else {
            return
        }

        if let isConnected {
            phase = phase.applyingConnectionStatus(
                isConnected,
                hasAvailableMacs: !macs.isEmpty
            )
        } else {
            phase = phase.applyingUnavailableStatus()
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

    private func apply(_ event: RemoteDiscoveryEvent) {
        switch event {
        case let .results(macs):
            let didRemoveSelectedMac = lastSelectedMac.map { selectedMac in
                !macs.contains { $0.endpoint == selectedMac.endpoint }
            } ?? false
            self.macs = macs

            if didRemoveSelectedMac {
                lastSelectedMac = nil
                statusGeneration += 1

                if case .success = phase {
                    phase = .statusUnavailable
                    return
                }
            }

            guard phase.acceptsDiscoveryUpdates else {
                return
            }
            phase = macs.isEmpty ? .searching : .ready
        case let .unavailable(message):
            if macs.isEmpty, phase.acceptsDiscoveryUpdates {
                phase = .discoveryFailure(message)
            }
        }
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
        case let .status(isConnected):
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
        case .searching, .ready, .discoveryFailure:
            true
        case .connecting, .success, .statusUnavailable, .failure:
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

    private static let connectedMessage =
        "Mac Virtual Display is connected."
}
