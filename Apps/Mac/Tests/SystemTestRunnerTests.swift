import Foundation
import Testing
@testable import MacDisplayConnect

@Suite("Physical-device system test runner")
@MainActor
struct SystemTestRunnerTests {
    @Test("launch arguments without a system-test flag stay interactive")
    func interactiveArgumentsHaveNoConfiguration() throws {
        #expect(
            try SystemTestConfiguration.parse(
                arguments: ["/Applications/MacDisplayConnect"]
            ) == nil
        )
    }

    @Test("launch arguments parse cycles, device name, and report path")
    func parsesSystemTestArguments() throws {
        let parsed = try SystemTestConfiguration.parse(
            arguments: [
                "/Applications/MacDisplayConnect",
                "--system-test-cycles", "20",
                "--vision-pro-name", "S’s Apple Vision Pro",
                "--system-test-report", "/tmp/report.json",
            ]
        )
        let configuration = try #require(parsed)

        #expect(configuration.cycleCount == 20)
        #expect(configuration.visionProName == "S’s Apple Vision Pro")
        #expect(configuration.reportURL.path == "/tmp/report.json")
    }

    @Test(
        "missing, nonpositive, nonnumeric, and duplicate cycle values are rejected",
        arguments: [
            ["app", "--system-test-cycles"],
            ["app", "--system-test-cycles", "0"],
            ["app", "--system-test-cycles", "-1"],
            ["app", "--system-test-cycles", "twenty"],
            [
                "app",
                "--system-test-cycles", "1",
                "--system-test-cycles", "2",
            ],
        ]
    )
    func rejectsInvalidCycleArguments(_ arguments: [String]) {
        #expect(throws: SystemTestConfigurationError.self) {
            try SystemTestConfiguration.parse(arguments: arguments)
        }
    }

    @Test("two successful cycles connect and disconnect in order")
    func runsTwoSuccessfulCycles() async {
        let system = TestSystem()
        let configuration = configuration(cycles: 2)
        let runner = runner(system: system)

        let report = await runner.run(configuration: configuration)

        #expect(
            system.actions
                == [
                    "disconnect:S’s Apple Vision Pro",
                    "connect:S’s Apple Vision Pro",
                    "disconnect:S’s Apple Vision Pro",
                    "connect:S’s Apple Vision Pro",
                    "disconnect:S’s Apple Vision Pro",
                ]
        )
        #expect(report.passed)
        #expect(report.cycleResults.map(\.status) == [.passed, .passed])
        #expect(!report.aborted)
    }

    @Test("preflight disconnects an active display before the first cycle")
    func preflightNormalizesAnActiveDisplay() async {
        let system = TestSystem()
        system.isConnected = true
        let runner = runner(system: system)

        let report = await runner.run(configuration: configuration(cycles: 1))

        #expect(
            system.actions
                == [
                    "disconnect:S’s Apple Vision Pro",
                    "connect:S’s Apple Vision Pro",
                    "disconnect:S’s Apple Vision Pro",
                ]
        )
        #expect(report.passed)
    }

    @Test("a connect no-op cannot count as a successful cycle")
    func rejectsConnectWithoutTransition() async {
        let system = TestSystem()
        system.connectShouldChangeState = false
        let runner = runner(system: system)

        let report = await runner.run(configuration: configuration(cycles: 1))

        #expect(!report.passed)
        #expect(report.cycleResults[0].failurePhase == .connect)
    }

    @Test("a connection lost during dwell records a failed cycle")
    func recordsConnectionLossDuringDwell() async {
        let system = TestSystem()
        system.onWait = {
            if system.waitCount == 2 {
                system.isConnected = false
                system.onWait = nil
            }
        }
        let runner = runner(system: system)

        let report = await runner.run(configuration: configuration(cycles: 1))

        #expect(!report.passed)
        #expect(report.cycleResults.count == 1)
        #expect(report.cycleResults[0].status == .failed)
        #expect(report.cycleResults[0].failurePhase == .dwell)
        #expect(!report.aborted)
    }

    @Test("a recoverable failed cycle cleans up and continues")
    func recoverableFailureContinuesAfterCleanup() async {
        let system = TestSystem()
        system.connectErrorCalls = [1]
        let runner = runner(system: system)

        let report = await runner.run(configuration: configuration(cycles: 2))

        #expect(
            system.actions
                == [
                    "disconnect:S’s Apple Vision Pro",
                    "connect:S’s Apple Vision Pro",
                    "disconnect:S’s Apple Vision Pro",
                    "connect:S’s Apple Vision Pro",
                    "disconnect:S’s Apple Vision Pro",
                ]
        )
        #expect(!report.passed)
        #expect(report.cycleResults.map(\.status) == [.failed, .passed])
        #expect(!report.aborted)
    }

    @Test("cleanup failure aborts the remaining cycles")
    func cleanupFailureAbortsRemainingCycles() async {
        let system = TestSystem()
        system.connectErrorCalls = [1]
        system.disconnectErrorCalls = [2]
        let runner = runner(system: system)

        let report = await runner.run(configuration: configuration(cycles: 3))

        #expect(!report.passed)
        #expect(report.aborted)
        #expect(report.cycleResults.count == 1)
        #expect(system.connectCount == 1)
        #expect(system.disconnectCount == 2)
    }

    private func configuration(cycles: Int) -> SystemTestConfiguration {
        SystemTestConfiguration(
            cycleCount: cycles,
            visionProName: "S’s Apple Vision Pro",
            reportURL: URL(fileURLWithPath: "/tmp/report.json")
        )
    }

    private func runner(system: TestSystem) -> SystemTestRunner {
        SystemTestRunner(
            dependencies: .init(
                connect: { name in
                    try system.connect(name: name)
                },
                disconnect: { name in
                    try system.disconnect(name: name)
                },
                isConnected: {
                    system.isConnected
                },
                wait: { _ in
                    system.wait()
                },
                now: {
                    Date(timeIntervalSince1970: 1_000)
                },
                log: { _ in }
            ),
            timing: .init(
                transitionAttempts: 1,
                stableSamples: 1,
                dwellSamples: 1,
                recoverySamples: 1,
                pollInterval: .zero
            )
        )
    }
}

@MainActor
private final class TestSystem {
    var isConnected = false
    var actions: [String] = []
    var connectErrorCalls: Set<Int> = []
    var connectShouldChangeState = true
    var disconnectErrorCalls: Set<Int> = []
    var onWait: (() -> Void)?

    private(set) var connectCount = 0
    private(set) var disconnectCount = 0
    private(set) var waitCount = 0

    func connect(name: String?) throws -> Bool {
        connectCount += 1
        actions.append("connect:\(name ?? "automatic")")
        isConnected = true

        if connectErrorCalls.contains(connectCount) {
            throw TestSystemError()
        }
        return connectShouldChangeState
    }

    func disconnect(name: String?) throws -> Bool {
        disconnectCount += 1
        actions.append("disconnect:\(name ?? "automatic")")

        if disconnectErrorCalls.contains(disconnectCount) {
            throw TestSystemError()
        }
        isConnected = false
        return true
    }

    func wait() {
        waitCount += 1
        onWait?()
    }
}

private struct TestSystemError: LocalizedError {
    var errorDescription: String? {
        "Injected system-test failure."
    }
}
