import AppKit
import MacDisplayConnectCore
import Foundation

@MainActor
enum DiagnosticLog {
    static var fileURL: URL {
        FileManager.default
            .urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appending(path: "Logs", directoryHint: .isDirectory)
            .appending(path: "Mac Display Connect", directoryHint: .isDirectory)
            .appending(path: "Mac Display Connect.log")
    }

    static func record(_ message: String) {
        do {
            try prepareFile()
            try append(entry(for: message))
        } catch {
            NSLog("Mac Display Connect could not write its diagnostic log: \(error)")
        }
    }

    static func showInFinder() {
        record("User requested the diagnostic log")
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    private static func prepareFile() throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        guard !FileManager.default.fileExists(atPath: fileURL.path) else {
            return
        }

        try Data().write(to: fileURL, options: .atomic)
    }

    private static func entry(for message: String) -> DiagnosticLogEntry {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds,
        ]

        return DiagnosticLogEntry(
            timestamp: formatter.string(from: .now),
            message: message
        )
    }

    private static func append(_ entry: DiagnosticLogEntry) throws {
        let handle = try FileHandle(forWritingTo: fileURL)
        defer {
            try? handle.close()
        }

        try handle.seekToEnd()
        try handle.write(contentsOf: Data(entry.line.utf8))
    }
}
