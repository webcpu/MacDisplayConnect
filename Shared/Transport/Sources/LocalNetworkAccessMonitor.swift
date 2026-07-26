import MacDisplayConnectCore
import dnssd
import Foundation
import Network

public enum LocalNetworkAccessStatus: Equatable, Sendable {
    case checking
    case granted
    case needsAccess
    case unavailable(String)
}

public struct LocalNetworkAccessMonitor: Sendable {
    public init() {}

    public func events() -> AsyncStream<LocalNetworkAccessStatus> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let parameters = NWParameters.tcp
            parameters.includePeerToPeer = true

            let browser = NWBrowser(
                for: .bonjour(
                    type: RemoteProtocol.serviceType,
                    domain: nil
                ),
                using: parameters
            )
            browser.stateUpdateHandler = { state in
                if let status = localNetworkAccessStatus(for: state) {
                    continuation.yield(status)
                }

                switch state {
                case .failed, .cancelled:
                    continuation.finish()
                case .setup, .waiting, .ready:
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
                    label: "MacDisplayConnect.LocalNetworkAccess."
                        + UUID().uuidString
                )
            )
        }
    }
}

func localNetworkAccessStatus(
    for state: NWBrowser.State
) -> LocalNetworkAccessStatus? {
    switch state {
    case .ready:
        .granted
    case let .waiting(error):
        if case let .dns(code) = error,
           code == kDNSServiceErr_PolicyDenied {
            .needsAccess
        } else {
            .unavailable(error.localizedDescription)
        }
    case let .failed(error):
        .unavailable(error.localizedDescription)
    case .setup, .cancelled:
        nil
    @unknown default:
        nil
    }
}
