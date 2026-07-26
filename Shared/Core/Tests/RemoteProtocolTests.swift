import Foundation
import Testing
@testable import MacDisplayConnectCore

@Suite("Remote connection protocol")
struct RemoteProtocolTests {
    @Test("publishes the version, service type, and frame limit")
    func publishesProtocolConstants() {
        #expect(RemoteProtocol.version == 1)
        #expect(RemoteProtocol.serviceType == "_macdisplayconnect._tcp")
        #expect(RemoteProtocol.maximumFrameSize == 4_096)
    }

    @Test("encodes one connect request as one UTF-8 JSON line")
    func encodesConnectRequest() throws {
        let frame = try RemoteProtocol.encode(
            .connect(visionProName: nil)
        )

        #expect(frame.last == 0x0A)
        #expect(!frame.dropLast().contains(0x0A))
        #expect(String(data: frame, encoding: .utf8) != nil)
        #expect(
            try RemoteProtocol.decodeRequest(frame)
                == .connect(visionProName: nil)
        )
    }

    @Test("round-trips the requested Vision Pro name")
    func roundTripsVisionProName() throws {
        let request = RemoteRequest.connect(
            visionProName: "S’s Apple Vision Pro"
        )

        let frame = try RemoteProtocol.encode(request)

        #expect(try RemoteProtocol.decodeRequest(frame) == request)
    }

    @Test("decodes a legacy connect request without a Vision Pro name")
    func decodesLegacyConnectRequest() throws {
        let frame = jsonLine(#"{"version":1,"command":"connect"}"#)

        #expect(
            try RemoteProtocol.decodeRequest(frame)
                == .connect(visionProName: nil)
        )
    }

    @Test("round-trips a status request")
    func roundTripsStatusRequest() throws {
        let frame = try RemoteProtocol.encode(.status)

        #expect(try RemoteProtocol.decodeRequest(frame) == .status)
    }

    @Test("round-trips a succeeded response")
    func roundTripsSucceededResponse() throws {
        let response = RemoteResponse.succeeded(message: "Connected")

        let frame = try RemoteProtocol.encode(response)

        #expect(try RemoteProtocol.decodeResponse(frame) == response)
    }

    @Test("round-trips a busy response")
    func roundTripsBusyResponse() throws {
        let response = RemoteResponse.busy

        let frame = try RemoteProtocol.encode(response)

        #expect(try RemoteProtocol.decodeResponse(frame) == response)
    }

    @Test("round-trips a failed response")
    func roundTripsFailedResponse() throws {
        let response = RemoteResponse.failed(message: "Vision Pro not found")

        let frame = try RemoteProtocol.encode(response)

        #expect(try RemoteProtocol.decodeResponse(frame) == response)
    }

    @Test(
        "round-trips the current connection status",
        arguments: [true, false]
    )
    func roundTripsConnectionStatus(isConnected: Bool) throws {
        let response = RemoteResponse.status(isConnected: isConnected)

        let frame = try RemoteProtocol.encode(response)

        #expect(try RemoteProtocol.decodeResponse(frame) == response)
    }

    @Test("rejects an unsupported request version")
    func rejectsUnsupportedRequestVersion() {
        let frame = jsonLine(#"{"version":2,"command":"connect"}"#)

        #expect(throws: RemoteProtocolError.unsupportedVersion(2)) {
            try RemoteProtocol.decodeRequest(frame)
        }
    }

    @Test("rejects an unknown command")
    func rejectsUnknownCommand() {
        let frame = jsonLine(#"{"version":1,"command":"disconnect"}"#)

        #expect(throws: RemoteProtocolError.unknownCommand("disconnect")) {
            try RemoteProtocol.decodeRequest(frame)
        }
    }

    @Test("rejects an unknown response status")
    func rejectsUnknownResponseStatus() {
        let frame = jsonLine(#"{"version":1,"status":"waiting"}"#)

        #expect(throws: RemoteProtocolError.unknownStatus("waiting")) {
            try RemoteProtocol.decodeResponse(frame)
        }
    }

    @Test("rejects malformed JSON")
    func rejectsMalformedJSON() {
        let frame = jsonLine(#"{"version":1,"command":"connect""#)

        #expect(throws: RemoteProtocolError.malformedFrame) {
            try RemoteProtocol.decodeRequest(frame)
        }
    }

    @Test("rejects a frame larger than 4096 bytes")
    func rejectsOversizedFrame() {
        let frame = Data(repeating: 0x20, count: 4_096) + Data([0x0A])

        #expect(throws: RemoteProtocolError.frameTooLarge) {
            try RemoteProtocol.decodeRequest(frame)
        }
    }

    @Test("rejects multiple frames")
    func rejectsMultipleFrames() {
        let frame = jsonLine(#"{"version":1,"command":"connect"}"#)
            + jsonLine(#"{"version":1,"command":"connect"}"#)

        #expect(throws: RemoteProtocolError.malformedFrame) {
            try RemoteProtocol.decodeRequest(frame)
        }
    }

    @Test("rejects a frame without its line ending")
    func rejectsMissingLineEnding() {
        let frame = Data(#"{"version":1,"command":"connect"}"#.utf8)

        #expect(throws: RemoteProtocolError.malformedFrame) {
            try RemoteProtocol.decodeRequest(frame)
        }
    }

    private func jsonLine(_ json: String) -> Data {
        Data("\(json)\n".utf8)
    }
}
