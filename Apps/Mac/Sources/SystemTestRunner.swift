import Foundation

enum SystemTestPhase: String, Codable, Sendable {
    case preflight
    case connect
    case connectedStability
    case dwell
    case disconnect
    case disconnectedStability
    case recovery
}

enum SystemTestCycleStatus: String, Codable, Sendable {
    case passed
    case failed
}

struct SystemTestCycleResult: Codable, Sendable {
    let cycle: Int
    let status: SystemTestCycleStatus
    let failurePhase: SystemTestPhase?
    let message: String?
    let connectDurationSeconds: Double?
    let disconnectDurationSeconds: Double?
}

struct SystemTestReport: Codable, Sendable {
    let runID: String
    let startedAt: Date
    let completedAt: Date
    let requestedCycles: Int
    let cycleResults: [SystemTestCycleResult]
    let passed: Bool
    let aborted: Bool
    let abortReason: String?

    func write(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }
}

@MainActor
struct SystemTestRunner {
    struct Dependencies {
        typealias Operation =
            @MainActor (_ visionProName: String?) async throws -> Bool
        typealias ConnectionState = @MainActor () -> Bool
        typealias Wait = @MainActor (Duration) async throws -> Void
        typealias Now = @MainActor () -> Date
        typealias Log = @MainActor (String) -> Void

        let connect: Operation
        let disconnect: Operation
        let isConnected: ConnectionState
        let wait: Wait
        let now: Now
        let log: Log

        static let live = Self(
            connect: { visionProName in
                try await ConnectionController().connectForSystemTest(
                    visionProName: visionProName
                )
            },
            disconnect: { visionProName in
                try await ConnectionController().disconnectForSystemTest(
                    visionProName: visionProName
                )
            },
            isConnected: {
                MacVirtualDisplayMonitor.shared.isConnectedOrReconnected
            },
            wait: {
                try await Task.sleep(for: $0)
            },
            now: {
                .now
            },
            log: {
                DiagnosticLog.record($0)
            }
        )
    }

    struct Timing {
        let transitionAttempts: Int
        let stableSamples: Int
        let dwellSamples: Int
        let recoverySamples: Int
        let pollInterval: Duration

        static let live = Self(
            transitionAttempts: 150,
            stableSamples: 10,
            dwellSamples: 50,
            recoverySamples: 30,
            pollInterval: .milliseconds(100)
        )
    }

    private let dependencies: Dependencies
    private let timing: Timing

    init(
        dependencies: Dependencies = .live,
        timing: Timing = .live
    ) {
        self.dependencies = dependencies
        self.timing = timing
    }

    func run(
        configuration: SystemTestConfiguration
    ) async -> SystemTestReport {
        let runID = UUID().uuidString.lowercased()
        let startedAt = dependencies.now()
        var results: [SystemTestCycleResult] = []
        var aborted = false
        var abortReason: String?

        dependencies.log(
            "System test \(runID) started; "
                + "cycles=\(configuration.cycleCount), target="
                + (configuration.visionProName ?? "automatic")
        )

        do {
            try await normalizeDisconnectedState(
                visionProName: configuration.visionProName
            )
        } catch {
            aborted = true
            abortReason = message(for: error)
            dependencies.log(
                "System test \(runID) preflight failed: \(abortReason!)"
            )
        }

        if !aborted {
            for cycle in 1...configuration.cycleCount {
                let result = await runCycle(
                    cycle,
                    runID: runID,
                    visionProName: configuration.visionProName
                )
                results.append(result.result)

                guard result.canContinue else {
                    aborted = true
                    abortReason = result.abortReason
                    break
                }
            }
        }

        let passed = !aborted
            && results.count == configuration.cycleCount
            && results.allSatisfy { $0.status == .passed }
        let report = SystemTestReport(
            runID: runID,
            startedAt: startedAt,
            completedAt: dependencies.now(),
            requestedCycles: configuration.cycleCount,
            cycleResults: results,
            passed: passed,
            aborted: aborted,
            abortReason: abortReason
        )
        dependencies.log(
            "System test \(runID) finished; "
                + "passed=\(passed), completed=\(results.count)/"
                + "\(configuration.cycleCount), aborted=\(aborted)"
        )
        return report
    }

    private func runCycle(
        _ cycle: Int,
        runID: String,
        visionProName: String?
    ) async -> CycleExecution {
        var phase = SystemTestPhase.preflight
        var connectDuration: Double?
        var disconnectDuration: Double?

        dependencies.log("System test \(runID) cycle \(cycle) started")

        do {
            try await waitForStableConnectionState(false)

            phase = .connect
            let connectStart = ContinuousClock.now
            guard try await dependencies.connect(visionProName) else {
                throw SystemTestRunnerError.transitionDidNotOccur(.connect)
            }
            connectDuration = seconds(
                from: connectStart.duration(to: ContinuousClock.now)
            )

            phase = .connectedStability
            try await waitForStableConnectionState(true)

            phase = .dwell
            try await requireConnectionDuringDwell()

            phase = .disconnect
            let disconnectStart = ContinuousClock.now
            guard try await dependencies.disconnect(visionProName) else {
                throw SystemTestRunnerError.transitionDidNotOccur(.disconnect)
            }
            disconnectDuration = seconds(
                from: disconnectStart.duration(to: ContinuousClock.now)
            )

            phase = .disconnectedStability
            try await waitForStableConnectionState(false)

            phase = .recovery
            try await requireDisconnectedRecovery()

            dependencies.log(
                "System test \(runID) cycle \(cycle) passed; "
                    + "connect=\(connectDuration ?? 0)s, "
                    + "disconnect=\(disconnectDuration ?? 0)s"
            )
            return CycleExecution(
                result: SystemTestCycleResult(
                    cycle: cycle,
                    status: .passed,
                    failurePhase: nil,
                    message: nil,
                    connectDurationSeconds: connectDuration,
                    disconnectDurationSeconds: disconnectDuration
                ),
                canContinue: true,
                abortReason: nil
            )
        } catch {
            let failureMessage = message(for: error)
            dependencies.log(
                "System test \(runID) cycle \(cycle) failed in "
                    + "\(phase.rawValue): \(failureMessage)"
            )

            let cleanup = await restoreDisconnectedState(
                visionProName: visionProName
            )
            return CycleExecution(
                result: SystemTestCycleResult(
                    cycle: cycle,
                    status: .failed,
                    failurePhase: phase,
                    message: failureMessage,
                    connectDurationSeconds: connectDuration,
                    disconnectDurationSeconds: disconnectDuration
                ),
                canContinue: cleanup.succeeded,
                abortReason: cleanup.message
            )
        }
    }

    private func normalizeDisconnectedState(
        visionProName: String?
    ) async throws {
        dependencies.log("System test preflight is normalizing disconnection")
        _ = try await dependencies.disconnect(visionProName)
        try await waitForStableConnectionState(false)
        try await requireDisconnectedRecovery()
    }

    private func restoreDisconnectedState(
        visionProName: String?
    ) async -> CleanupResult {
        do {
            _ = try await dependencies.disconnect(visionProName)
            try await waitForStableConnectionState(false)
            try await requireDisconnectedRecovery()
            return CleanupResult(succeeded: true, message: nil)
        } catch {
            let cleanupMessage =
                "Cleanup could not confirm a disconnected state: "
                + message(for: error)
            dependencies.log(cleanupMessage)
            return CleanupResult(
                succeeded: false,
                message: cleanupMessage
            )
        }
    }

    private func waitForStableConnectionState(
        _ expectedState: Bool
    ) async throws {
        var consecutiveMatches = 0

        for attempt in 0..<max(1, timing.transitionAttempts) {
            if dependencies.isConnected() == expectedState {
                consecutiveMatches += 1
                if consecutiveMatches >= max(1, timing.stableSamples) {
                    return
                }
            } else {
                consecutiveMatches = 0
            }

            if attempt + 1 < max(1, timing.transitionAttempts) {
                try await dependencies.wait(timing.pollInterval)
            }
        }

        throw SystemTestRunnerError.stateDidNotStabilize(expectedState)
    }

    private func requireConnectionDuringDwell() async throws {
        for _ in 0..<max(1, timing.dwellSamples) {
            try await dependencies.wait(timing.pollInterval)
            guard dependencies.isConnected() else {
                throw SystemTestRunnerError.connectionDroppedDuringDwell
            }
        }
    }

    private func requireDisconnectedRecovery() async throws {
        for _ in 0..<max(1, timing.recoverySamples) {
            try await dependencies.wait(timing.pollInterval)
            guard !dependencies.isConnected() else {
                throw SystemTestRunnerError.reconnectedDuringRecovery
            }
        }
    }

    private func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription
            ?? error.localizedDescription
    }

    private func seconds(from duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds)
            + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }
}

private struct CycleExecution {
    let result: SystemTestCycleResult
    let canContinue: Bool
    let abortReason: String?
}

private struct CleanupResult {
    let succeeded: Bool
    let message: String?
}

private enum SystemTestRunnerError: LocalizedError {
    case stateDidNotStabilize(Bool)
    case connectionDroppedDuringDwell
    case reconnectedDuringRecovery
    case transitionDidNotOccur(SystemTestPhase)

    var errorDescription: String? {
        switch self {
        case let .stateDidNotStabilize(expectedState):
            expectedState
                ? "The display did not reach a stable connected state."
                : "The display did not reach a stable disconnected state."
        case .connectionDroppedDuringDwell:
            "The display disconnected during the connected dwell period."
        case .reconnectedDuringRecovery:
            "The display unexpectedly reconnected during recovery."
        case let .transitionDidNotOccur(phase):
            "The \(phase.rawValue) operation did not change display state."
        }
    }
}
