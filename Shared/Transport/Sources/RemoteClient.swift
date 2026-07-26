import MacDisplayConnectCore
import Foundation
import Network

public struct RemoteClient: Sendable {
    private let timeout: Duration

    public init(timeout: Duration = .seconds(10)) {
        self.timeout = timeout
    }

    public func send(
        _ request: RemoteRequest,
        to endpoint: NWEndpoint
    ) async throws -> RemoteResponse {
        let timeout = timeout

        return try await withThrowingTaskGroup(
            of: RemoteResponse.self
        ) { group in
            group.addTask {
                try await roundTrip(request, to: endpoint)
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw RemoteTransportError.timedOut
            }
            defer {
                group.cancelAll()
            }

            guard let response = try await group.next() else {
                throw CancellationError()
            }
            return response
        }
    }

    private func roundTrip(
        _ request: RemoteRequest,
        to endpoint: NWEndpoint
    ) async throws -> RemoteResponse {
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true

        let connection = NWConnection(to: endpoint, using: parameters)
        let queue = DispatchQueue(label: "MacDisplayConnect.RemoteClient")

        return try await withTaskCancellationHandler {
            defer {
                connection.cancel()
            }

            do {
                try await RemoteConnectionIO.start(connection, on: queue)
                try await RemoteConnectionIO.send(
                    RemoteProtocol.encode(request),
                    over: connection
                )
                let responseFrame = try await RemoteConnectionIO.receiveFrame(
                    from: connection
                )
                try Task.checkCancellation()
                return try RemoteProtocol.decodeResponse(responseFrame)
            } catch {
                try Task.checkCancellation()
                throw error
            }
        } onCancel: {
            connection.cancel()
        }
    }
}
