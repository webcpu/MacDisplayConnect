import Foundation

public struct DiagnosticLogEntry: Equatable, Sendable {
    public let timestamp: String
    public let message: String

    public init(timestamp: String, message: String) {
        self.timestamp = timestamp
        self.message = message
    }

    public var line: String {
        let oneLineMessage = message
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
        return "[\(timestamp)] \(oneLineMessage)\n"
    }
}
