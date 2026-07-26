import MacDisplayConnectCore
import Foundation
import Network

public enum RemoteTransportError: Error, LocalizedError, Sendable {
    case connectionClosed
    case connectionFailed(String)
    case invalidFrame
    case listenerFailed(String)
    case timedOut

    public var errorDescription: String? {
        switch self {
        case .connectionClosed:
            "The remote connection closed before a complete response arrived."
        case let .connectionFailed(message):
            "The remote connection failed: \(message)"
        case .invalidFrame:
            "The remote device sent an invalid message."
        case let .listenerFailed(message):
            "The remote listener failed: \(message)"
        case .timedOut:
            "The Mac did not respond in time."
        }
    }
}

enum RemoteConnectionIO {
    static func start(
        _ connection: NWConnection,
        on queue: DispatchQueue
    ) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        connection.stateUpdateHandler = nil
                        continuation.resume()
                    case let .failed(error):
                        connection.stateUpdateHandler = nil
                        continuation.resume(
                            throwing: RemoteTransportError.connectionFailed(
                                error.debugDescription
                            )
                        )
                    case .cancelled:
                        connection.stateUpdateHandler = nil
                        continuation.resume(
                            throwing: RemoteTransportError.connectionClosed
                        )
                    case .setup, .waiting, .preparing:
                        break
                    @unknown default:
                        break
                    }
                }
                connection.start(queue: queue)
            }
        } onCancel: {
            connection.cancel()
        }
    }

    static func send(_ data: Data, over connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, any Error>) in
            connection.send(
                content: data,
                contentContext: .defaultMessage,
                isComplete: true,
                completion: .contentProcessed { error in
                    if let error {
                        continuation.resume(
                            throwing: RemoteTransportError.connectionFailed(
                                error.debugDescription
                            )
                        )
                    } else {
                        continuation.resume()
                    }
                }
            )
        }
    }

    static func receiveFrame(from connection: NWConnection) async throws -> Data {
        var frame = Data()

        while true {
            let chunk = await receiveChunk(from: connection)
            if let data = chunk.data {
                frame.append(data)
            }

            guard frame.count <= RemoteProtocol.maximumFrameSize else {
                throw RemoteProtocolError.frameTooLarge
            }

            if let lineFeedIndex = frame.firstIndex(of: 0x0A) {
                guard frame.index(after: lineFeedIndex) == frame.endIndex else {
                    throw RemoteTransportError.invalidFrame
                }
                return frame
            }

            if let error = chunk.error {
                throw RemoteTransportError.connectionFailed(
                    error.debugDescription
                )
            }
            if chunk.isComplete {
                throw RemoteTransportError.connectionClosed
            }
        }
    }

    private static func receiveChunk(
        from connection: NWConnection
    ) async -> ConnectionChunk {
        await withCheckedContinuation { continuation in
            connection.receive(
                minimumIncompleteLength: 1,
                maximumLength: RemoteProtocol.maximumFrameSize + 1
            ) { data, _, isComplete, error in
                continuation.resume(
                    returning: ConnectionChunk(
                        data: data,
                        isComplete: isComplete,
                        error: error
                    )
                )
            }
        }
    }
}

private struct ConnectionChunk: Sendable {
    let data: Data?
    let isComplete: Bool
    let error: NWError?
}
