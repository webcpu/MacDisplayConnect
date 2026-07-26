import MacDisplayConnectCore
import Foundation
import Network

public actor RemoteServer {
    public typealias Handler = @Sendable (RemoteRequest) async -> RemoteResponse

    private let handler: Handler
    private let queue = DispatchQueue(
        label: "MacDisplayConnect.RemoteServer.\(UUID().uuidString)"
    )
    private var listener: NWListener?

    public init(handler: @escaping Handler) {
        self.handler = handler
    }

    public func start(serviceName: String? = nil) async throws -> NWEndpoint.Port {
        if let listener, let port = listener.port {
            return port
        }

        let parameters = NWParameters.tcp
        parameters.acceptLocalOnly = true
        parameters.allowLocalEndpointReuse = true
        parameters.includePeerToPeer = true
        if serviceName == nil {
            parameters.requiredLocalEndpoint = .hostPort(
                host: .ipv4(.loopback),
                port: .any
            )
        }

        let listener = try NWListener(using: parameters)
        if let serviceName {
            listener.service = NWListener.Service(
                name: serviceName,
                type: RemoteProtocol.serviceType
            )
        }

        let handler = handler
        let queue = queue
        listener.newConnectionHandler = { connection in
            Task {
                await Self.serve(
                    connection,
                    on: queue,
                    handler: handler
                )
            }
        }
        self.listener = listener

        do {
            return try await Self.start(listener, on: queue)
        } catch {
            listener.cancel()
            self.listener = nil
            throw error
        }
    }

    public func stop() {
        listener?.cancel()
        listener = nil
    }

    private static func start(
        _ listener: NWListener,
        on queue: DispatchQueue
    ) async throws -> NWEndpoint.Port {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                listener.stateUpdateHandler = { state in
                    switch listenerStartDecision(for: state) {
                    case .ready:
                        listener.stateUpdateHandler = nil
                        if let port = listener.port {
                            continuation.resume(returning: port)
                        } else {
                            continuation.resume(
                                throwing: RemoteTransportError.listenerFailed(
                                    "No listening port was assigned."
                                )
                            )
                        }
                    case let .failure(message):
                        listener.stateUpdateHandler = nil
                        continuation.resume(
                            throwing: RemoteTransportError.listenerFailed(
                                message
                            )
                        )
                    case .pending:
                        break
                    }
                }
                listener.start(queue: queue)
            }
        } onCancel: {
            listener.cancel()
        }
    }

    private static func serve(
        _ connection: NWConnection,
        on queue: DispatchQueue,
        handler: Handler
    ) async {
        defer {
            connection.cancel()
        }

        do {
            try await RemoteConnectionIO.start(connection, on: queue)
            let frame = try await RemoteConnectionIO.receiveFrame(
                from: connection
            )
            let request = try RemoteProtocol.decodeRequest(frame)
            let response = await handler(request)
            try await RemoteConnectionIO.send(
                RemoteProtocol.encode(response),
                over: connection
            )
        } catch {
            return
        }
    }
}

enum ListenerStartDecision: Equatable {
    case pending
    case ready
    case failure(String)
}

func listenerStartDecision(
    for state: NWListener.State
) -> ListenerStartDecision {
    switch state {
    case .ready:
        .ready
    case let .failed(error):
        .failure(error.debugDescription)
    case .cancelled:
        .failure("The listener was cancelled.")
    case .setup, .waiting:
        .pending
    @unknown default:
        .pending
    }
}
