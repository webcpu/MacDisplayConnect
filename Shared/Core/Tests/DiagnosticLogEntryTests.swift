import Testing
@testable import MacDisplayConnectCore

@Suite("Diagnostic log entries")
struct DiagnosticLogEntryTests {
    @Test("formats one safe line with a timestamp")
    func formatsOneLine() {
        let entry = DiagnosticLogEntry(
            timestamp: "2026-07-25T16:20:00.000Z",
            message: "Control Center\nnot found"
        )

        #expect(
            entry.line
                == "[2026-07-25T16:20:00.000Z] Control Center not found\n"
        )
    }
}
