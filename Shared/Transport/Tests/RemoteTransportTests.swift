import Darwin
import Foundation
import Network
import Testing
import MacDisplayConnectCore
@testable import MacDisplayConnectTransport

@Suite("Remote transport")
struct RemoteTransportTests {
    @Test("round-trips one request through an injected async handler")
    func roundTripsRequest() async throws {
        let expectedResponse = RemoteResponse.succeeded(message: "Connected")
        let probe = RequestProbe(response: expectedResponse)
        let server = RemoteServer { request in
            await probe.handle(request)
        }
        let port = try await server.start()

        do {
            let endpoint = NWEndpoint.hostPort(
                host: .ipv4(.loopback),
                port: port
            )
            let response = try await RemoteClient().send(
                .connect(visionProName: "S’s Apple Vision Pro"),
                to: endpoint
            )
            let requests = await probe.receivedRequests()

            #expect(response == expectedResponse)
            #expect(
                requests == [
                    .connect(visionProName: "S’s Apple Vision Pro"),
                ]
            )
        } catch {
            await server.stop()
            throw error
        }

        await server.stop()
    }

    @Test("accepts a request frame split across TCP writes")
    func acceptsFragmentedRequestFrame() async throws {
        let expectedResponse = RemoteResponse.succeeded(message: "Connected")
        let probe = RequestProbe(response: expectedResponse)
        let server = RemoteServer { request in
            await probe.handle(request)
        }
        let port = try await server.start()
        let requestFrame = try RemoteProtocol.encode(
            .connect(visionProName: nil)
        )
        let splitIndex = requestFrame.index(
            requestFrame.startIndex,
            offsetBy: requestFrame.count / 2
        )

        do {
            let responseFrame = try await exchangeRaw(
                chunks: [
                    Data(requestFrame[..<splitIndex]),
                    Data(requestFrame[splitIndex...]),
                ],
                port: port.rawValue
            )
            let response = try RemoteProtocol.decodeResponse(responseFrame)
            let requests = await probe.receivedRequests()

            #expect(response == expectedResponse)
            #expect(requests == [.connect(visionProName: nil)])
        } catch {
            await server.stop()
            throw error
        }

        await server.stop()
    }

    @Test("does not invoke the handler for malformed input")
    func rejectsMalformedInputBeforeHandling() async throws {
        let probe = RequestProbe(response: .busy)
        let server = RemoteServer { request in
            await probe.handle(request)
        }
        let port = try await server.start()

        _ = try? await exchangeRaw(
            chunks: [Data("not-json\n".utf8)],
            port: port.rawValue
        )
        let requests = await probe.receivedRequests()

        #expect(requests.isEmpty)
        await server.stop()
    }

    @Test("cancelling a request stops waiting for the response")
    func cancelsWhileWaitingForResponse() async throws {
        let probe = SuspendedResponseProbe()
        let server = RemoteServer { request in
            await probe.handle(request)
        }
        let port = try await server.start()
        let endpoint = NWEndpoint.hostPort(
            host: .ipv4(.loopback),
            port: port
        )
        let request = Task {
            try await RemoteClient().send(
                .connect(visionProName: nil),
                to: endpoint
            )
        }

        await probe.waitUntilRequested()
        request.cancel()
        let result = await request.result
        await probe.release()
        await server.stop()

        guard case let .failure(error) = result else {
            Issue.record("The cancelled request unexpectedly succeeded.")
            return
        }
        #expect(error is CancellationError)
    }

    @Test("stops waiting when the response deadline passes")
    func timesOutWhileWaitingForResponse() async throws {
        let probe = SuspendedResponseProbe()
        let server = RemoteServer { request in
            await probe.handle(request)
        }
        let port = try await server.start()
        let endpoint = NWEndpoint.hostPort(
            host: .ipv4(.loopback),
            port: port
        )

        do {
            _ = try await RemoteClient(
                timeout: .milliseconds(50)
            ).send(.connect(visionProName: nil), to: endpoint)
            Issue.record("The request unexpectedly succeeded.")
        } catch let error as RemoteTransportError {
            guard case .timedOut = error else {
                Issue.record("Unexpected transport error: \(error)")
                await probe.release()
                await server.stop()
                return
            }
        }

        await probe.release()
        await server.stop()
    }

    @Test("a temporarily waiting listener remains pending")
    func keepsWaitingForListenerRecovery() {
        let error = NWError.posix(.ENETDOWN)

        #expect(
            listenerStartDecision(for: .waiting(error)) == .pending
        )
    }
}

private actor RequestProbe {
    private let response: RemoteResponse
    private var requests: [RemoteRequest] = []

    init(response: RemoteResponse) {
        self.response = response
    }

    func handle(_ request: RemoteRequest) -> RemoteResponse {
        requests.append(request)
        return response
    }

    func receivedRequests() -> [RemoteRequest] {
        requests
    }
}

private actor SuspendedResponseProbe {
    private var didReceiveRequest = false
    private var requestWaiters: [CheckedContinuation<Void, Never>] = []
    private var responseWaiter: CheckedContinuation<RemoteResponse, Never>?

    func handle(_ request: RemoteRequest) async -> RemoteResponse {
        didReceiveRequest = true
        requestWaiters.forEach { $0.resume() }
        requestWaiters.removeAll()

        return await withCheckedContinuation { continuation in
            responseWaiter = continuation
        }
    }

    func waitUntilRequested() async {
        guard !didReceiveRequest else {
            return
        }

        await withCheckedContinuation { continuation in
            requestWaiters.append(continuation)
        }
    }

    func release() {
        responseWaiter?.resume(returning: .busy)
        responseWaiter = nil
    }
}

private func exchangeRaw(
    chunks: [Data],
    port: UInt16
) async throws -> Data {
    try await Task.detached {
        try exchangeRawSynchronously(chunks: chunks, port: port)
    }.value
}

private func exchangeRawSynchronously(
    chunks: [Data],
    port: UInt16
) throws -> Data {
    let socketDescriptor = socket(AF_INET, SOCK_STREAM, 0)
    guard socketDescriptor >= 0 else {
        throw RawSocketError.systemCall("socket", errno)
    }
    defer { Darwin.close(socketDescriptor) }

    try configure(socketDescriptor)
    try connect(socketDescriptor, port: port)

    for (index, chunk) in chunks.enumerated() {
        try sendAll(chunk, to: socketDescriptor)
        if index < chunks.count - 1 {
            usleep(20_000)
        }
    }

    return try receiveFrame(from: socketDescriptor)
}

private func configure(_ socketDescriptor: Int32) throws {
    var enabled: Int32 = 1
    guard setsockopt(
        socketDescriptor,
        SOL_SOCKET,
        SO_NOSIGPIPE,
        &enabled,
        socklen_t(MemoryLayout.size(ofValue: enabled))
    ) == 0 else {
        throw RawSocketError.systemCall("setsockopt", errno)
    }

    var timeout = timeval(tv_sec: 2, tv_usec: 0)
    guard setsockopt(
        socketDescriptor,
        SOL_SOCKET,
        SO_RCVTIMEO,
        &timeout,
        socklen_t(MemoryLayout.size(ofValue: timeout))
    ) == 0 else {
        throw RawSocketError.systemCall("setsockopt", errno)
    }
}

private func connect(_ socketDescriptor: Int32, port: UInt16) throws {
    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = port.bigEndian
    address.sin_addr = in_addr(s_addr: INADDR_LOOPBACK.bigEndian)

    let result = withUnsafePointer(to: &address) { addressPointer in
        addressPointer.withMemoryRebound(
            to: sockaddr.self,
            capacity: 1
        ) { socketAddress in
            Darwin.connect(
                socketDescriptor,
                socketAddress,
                socklen_t(MemoryLayout<sockaddr_in>.size)
            )
        }
    }

    guard result == 0 else {
        throw RawSocketError.systemCall("connect", errno)
    }
}

private func sendAll(_ data: Data, to socketDescriptor: Int32) throws {
    try data.withUnsafeBytes { bytes in
        guard let baseAddress = bytes.baseAddress else {
            return
        }

        var sentByteCount = 0
        while sentByteCount < bytes.count {
            let result = Darwin.send(
                socketDescriptor,
                baseAddress.advanced(by: sentByteCount),
                bytes.count - sentByteCount,
                0
            )

            if result < 0, errno == EINTR {
                continue
            }
            guard result > 0 else {
                throw RawSocketError.systemCall("send", errno)
            }
            sentByteCount += result
        }
    }
}

private func receiveFrame(from socketDescriptor: Int32) throws -> Data {
    var frame = Data()
    var buffer = [UInt8](repeating: 0, count: 1_024)

    while !frame.contains(0x0A) {
        let receivedByteCount = Darwin.recv(
            socketDescriptor,
            &buffer,
            buffer.count,
            0
        )

        if receivedByteCount < 0, errno == EINTR {
            continue
        }
        guard receivedByteCount >= 0 else {
            throw RawSocketError.systemCall("recv", errno)
        }
        guard receivedByteCount > 0 else {
            return frame
        }

        frame.append(contentsOf: buffer.prefix(receivedByteCount))
        guard frame.count <= RemoteProtocol.maximumFrameSize else {
            throw RawSocketError.responseTooLarge
        }
    }

    return frame
}

private enum RawSocketError: Error {
    case systemCall(String, Int32)
    case responseTooLarge
}
