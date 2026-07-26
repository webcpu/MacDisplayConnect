import MacDisplayConnectCore
import Foundation
import Network

public struct RemoteMac: Hashable, Identifiable, Sendable {
    public let name: String
    public let endpoint: NWEndpoint

    public var id: NWEndpoint {
        endpoint
    }

    public init?(endpoint: NWEndpoint) {
        guard case let .service(name, _, _, _) = endpoint else {
            return nil
        }

        self.name = name
        self.endpoint = endpoint
    }
}

public enum RemoteDiscoveryEvent: Sendable {
    case results([RemoteMac])
    case unavailable(String)
}

public struct RemoteBrowser: Sendable {
    public init() {}

    public func events() -> AsyncStream<RemoteDiscoveryEvent> {
        AsyncStream { continuation in
            let parameters = NWParameters.tcp
            parameters.includePeerToPeer = true

            let browser = NWBrowser(
                for: .bonjour(
                    type: RemoteProtocol.serviceType,
                    domain: nil
                ),
                using: parameters
            )
            browser.browseResultsChangedHandler = { results, _ in
                let macs = Set(
                    results.compactMap { RemoteMac(endpoint: $0.endpoint) }
                ).sorted { left, right in
                    left.name.localizedCaseInsensitiveCompare(right.name)
                        == .orderedAscending
                }
                continuation.yield(.results(macs))
            }
            browser.stateUpdateHandler = { state in
                switch state {
                case let .waiting(error):
                    continuation.yield(
                        .unavailable(error.localizedDescription)
                    )
                case let .failed(error):
                    continuation.yield(
                        .unavailable(error.localizedDescription)
                    )
                    continuation.finish()
                case .cancelled:
                    continuation.finish()
                case .setup, .ready:
                    break
                @unknown default:
                    break
                }
            }
            continuation.onTermination = { _ in
                browser.cancel()
            }
            browser.start(
                queue: DispatchQueue(
                    label: "MacDisplayConnect.RemoteBrowser.\(UUID().uuidString)"
                )
            )
        }
    }
}
