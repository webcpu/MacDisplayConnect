import Foundation

public enum RemoteRequest: Equatable, Sendable {
    case connect(visionProName: String?)
    case status
}

public enum RemoteResponse: Equatable, Sendable {
    case succeeded(message: String)
    case busy
    case failed(message: String)
    case status(isConnected: Bool, isAvailable: Bool)
}

public enum RemoteProtocolError: Error, Equatable, Sendable {
    case malformedFrame
    case frameTooLarge
    case unsupportedVersion(Int)
    case unknownCommand(String)
    case unknownStatus(String)
}

public enum RemoteProtocol {
    public static let version = 1
    public static let serviceType = "_macdisplayconnect._tcp"
    public static let maximumFrameSize = 4_096

    public static func encode(_ request: RemoteRequest) throws -> Data {
        let payload = switch request {
        case let .connect(visionProName):
            RequestPayload(
                version: version,
                command: "connect",
                visionProName: visionProName
            )
        case .status:
            RequestPayload(
                version: version,
                command: "status",
                visionProName: nil
            )
        }
        return try encodeFrame(payload)
    }

    public static func encode(_ response: RemoteResponse) throws -> Data {
        try encodeFrame(ResponsePayload(response))
    }

    public static func decodeRequest(_ frame: Data) throws -> RemoteRequest {
        let payload: RequestPayload = try decodePayload(from: frame)
        try validate(version: payload.version)

        return switch payload.command {
        case "connect":
            .connect(visionProName: payload.visionProName)
        case "status": .status
        default: throw RemoteProtocolError.unknownCommand(payload.command)
        }
    }

    public static func decodeResponse(_ frame: Data) throws -> RemoteResponse {
        let payload: ResponsePayload = try decodePayload(from: frame)
        try validate(version: payload.version)

        return try payload.response
    }

    private static func encodeFrame<Value: Encodable>(
        _ value: Value
    ) throws -> Data {
        let payload = try JSONEncoder().encode(value)
        let frame = payload + Data([lineFeed])

        guard frame.count <= maximumFrameSize else {
            throw RemoteProtocolError.frameTooLarge
        }

        return frame
    }

    private static func decodePayload<Value: Decodable>(
        from frame: Data
    ) throws -> Value {
        let payload = try framePayload(frame)

        do {
            return try JSONDecoder().decode(Value.self, from: payload)
        } catch {
            throw RemoteProtocolError.malformedFrame
        }
    }

    private static func framePayload(_ frame: Data) throws -> Data {
        guard frame.count <= maximumFrameSize else {
            throw RemoteProtocolError.frameTooLarge
        }
        guard frame.last == lineFeed else {
            throw RemoteProtocolError.malformedFrame
        }

        let payload = frame.dropLast()
        guard
            !payload.isEmpty,
            !payload.contains(lineFeed),
            String(data: Data(payload), encoding: .utf8) != nil
        else {
            throw RemoteProtocolError.malformedFrame
        }

        return Data(payload)
    }

    private static func validate(version receivedVersion: Int) throws {
        guard receivedVersion == version else {
            throw RemoteProtocolError.unsupportedVersion(receivedVersion)
        }
    }

    private static let lineFeed: UInt8 = 0x0A
}

private struct RequestPayload: Codable {
    let version: Int
    let command: String
    let visionProName: String?
}

private struct ResponsePayload: Codable {
    let version: Int
    let status: String
    let message: String?
    let isConnected: Bool?
    let isAvailable: Bool?

    private init(
        version: Int,
        status: String,
        message: String?,
        isConnected: Bool? = nil,
        isAvailable: Bool? = nil
    ) {
        self.version = version
        self.status = status
        self.message = message
        self.isConnected = isConnected
        self.isAvailable = isAvailable
    }

    init(_ response: RemoteResponse) {
        switch response {
        case .succeeded(let message):
            self.init(
                version: RemoteProtocol.version,
                status: "succeeded",
                message: message
            )
        case .busy:
            self.init(
                version: RemoteProtocol.version,
                status: "busy",
                message: nil
            )
        case .failed(let message):
            self.init(
                version: RemoteProtocol.version,
                status: "failed",
                message: message
            )
        case let .status(isConnected, isAvailable):
            self.init(
                version: RemoteProtocol.version,
                status: "status",
                message: nil,
                isConnected: isConnected,
                isAvailable: isAvailable
            )
        }
    }

    var response: RemoteResponse {
        get throws {
            switch status {
            case "succeeded":
                guard let message else {
                    throw RemoteProtocolError.malformedFrame
                }
                return .succeeded(message: message)
            case "busy":
                return .busy
            case "failed":
                guard let message else {
                    throw RemoteProtocolError.malformedFrame
                }
                return .failed(message: message)
            case "status":
                guard let isConnected else {
                    throw RemoteProtocolError.malformedFrame
                }
                return .status(
                    isConnected: isConnected,
                    isAvailable: isAvailable ?? false
                )
            default:
                throw RemoteProtocolError.unknownStatus(status)
            }
        }
    }
}
