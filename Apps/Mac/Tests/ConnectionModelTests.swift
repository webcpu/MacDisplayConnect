import Foundation
import MacDisplayConnectCore
import MacDisplayConnectTransport
import Testing
@testable import MacDisplayConnect

@Suite("Mac connection model")
@MainActor
struct ConnectionModelTests {
    @Test("connection phases use Mac Virtual Display terminology")
    func connectionPhaseTerminology() {
        #expect(ConnectionPhase.ready.title == "Ready to Connect")
        #expect(
            ConnectionPhase.ready.message
                == "Wear and unlock your Apple Vision Pro."
        )
        #expect(ConnectionPhase.working.title == "Connecting…")
        #expect(
            ConnectionPhase.working.message
                == "Starting Mac Virtual Display…"
        )
        #expect(
            ConnectionPhase.success("Connected.").title == "Connected"
        )
    }

    @Test("only actionable phases offer a button title")
    func connectionPhaseActions() {
        #expect(ConnectionPhase.ready.actionTitle == "Connect")
        #expect(ConnectionPhase.working.actionTitle == nil)
        #expect(ConnectionPhase.success("Connected.").actionTitle == nil)
        #expect(
            ConnectionPhase.failure("Connection failed.").actionTitle
                == "Try Again"
        )
    }

    @Test("refreshes to connected when Mac Virtual Display is active")
    func refreshesToConnectedWhenDisplayIsActive() {
        let model = makeConnectionModel(connectionStatus: { true })

        model.refreshConnectionStatus()

        #expect(
            model.phase
                == .success("Mac Virtual Display is connected.")
        )
    }

    @Test("refreshes to ready when Mac Virtual Display is not active")
    func refreshesToReadyWhenDisplayIsNotActive() async {
        let model = makeConnectionModel(
            connect: { _ in "Mac Virtual Display is connected." },
            connectionStatus: { false }
        )

        _ = await model.connectAndExtend()
        model.refreshConnectionStatus()

        #expect(model.phase == .ready)
    }

    @Test("a successful operation returns success and updates the phase")
    func successfulOperation() async {
        let message = "Mac Virtual Display is connected."
        let model = makeConnectionModel(connect: { _ in message })

        let response = await model.connectAndExtend()

        #expect(response == .succeeded(message: message))
        #expect(model.phase == .success(message))
    }

    @Test("a thrown operation returns failure and updates the phase")
    func failedOperation() async {
        let model = makeConnectionModel(connect: { _ in
            throw TestConnectionError()
        })

        let response = await model.connectAndExtend()

        #expect(response == .failed(message: "Test connection failed."))
        #expect(model.phase == .failure("Test connection failed."))
    }

    @Test("a remote request activates the Mac app before connecting")
    func remoteRequestActivatesApplication() async {
        var isApplicationActive = false
        let message = "Mac Virtual Display is connected."
        let model = makeConnectionModel(
            connect: { _ in
                guard isApplicationActive else {
                    throw TestConnectionError()
                }
                return message
            },
            activateForRemoteConnection: {
                isApplicationActive = true
                return true
            }
        )

        let response = await model.handleRemoteConnect()

        #expect(response == .succeeded(message: message))
    }

    @Test("a remote request still connects when the Mac app cannot activate")
    func remoteRequestContinuesWhenApplicationCannotActivate() async {
        var didConnect = false
        let message = "Mac Virtual Display is connected."
        let model = makeConnectionModel(
            connect: { _ in
                didConnect = true
                return message
            },
            activateForRemoteConnection: { false }
        )

        let response = await model.handleRemoteConnect()

        #expect(didConnect)
        #expect(response == .succeeded(message: message))
        #expect(model.phase == .success(message))
    }

    @Test("a remote request forwards the requested Vision Pro name")
    func remoteRequestForwardsVisionProName() async {
        let model = makeConnectionModel(
            connect: { visionProName in
                visionProName ?? "No Vision Pro name"
            },
            activateForRemoteConnection: { true }
        )

        let response = await model.handleRemoteRequest(
            .connect(visionProName: "S’s Apple Vision Pro")
        )

        #expect(
            response == .succeeded(message: "S’s Apple Vision Pro")
        )
    }

    @Test("the Mac button keeps using automatic Vision Pro selection")
    func localRequestUsesAutomaticSelection() async {
        let model = makeConnectionModel(
            connect: { visionProName in
                visionProName ?? "Automatic selection"
            }
        )

        let response = await model.connectAndExtend()

        #expect(response == .succeeded(message: "Automatic selection"))
    }

    @Test("a status request reports the current display state without connecting")
    func statusRequestReportsCurrentDisplayState() async {
        var didActivate = false
        var didConnect = false
        let model = makeConnectionModel(
            connect: { _ in
                didConnect = true
                return "Mac Virtual Display is connected."
            },
            activateForRemoteConnection: {
                didActivate = true
                return true
            },
            connectionStatus: { true }
        )

        let response = await model.handleRemoteRequest(.status)

        #expect(response == .status(isConnected: true))
        #expect(
            model.phase
                == .success("Mac Virtual Display is connected.")
        )
        #expect(!didActivate)
        #expect(!didConnect)
    }

    @Test("a disconnected status request clears the connected phase")
    func disconnectedStatusRequestClearsConnectedPhase() async {
        let model = makeConnectionModel(
            connect: { _ in "Mac Virtual Display is connected." },
            connectionStatus: { false }
        )
        _ = await model.connectAndExtend()

        let response = await model.handleRemoteRequest(.status)

        #expect(response == .status(isConnected: false))
        #expect(model.phase == .ready)
    }

    @Test("a second request is busy while the first operation is suspended")
    func concurrentRequestIsBusy() async {
        let operation = SuspendedConnectOperation()
        let model = makeConnectionModel(
            connect: { _ in
                await operation.run()
            },
            connectionStatus: { false }
        )

        let firstRequest = Task { @MainActor in
            await model.connectAndExtend()
        }
        await operation.waitUntilStarted()

        let statusResponse = await model.handleRemoteRequest(.status)
        let secondResponse = await model.connectAndExtend()
        let invocationCountWhileBusy = await operation.invocationCount

        #expect(statusResponse == .status(isConnected: false))
        #expect(model.phase == .working)
        #expect(secondResponse == .busy)
        #expect(invocationCountWhileBusy == 1)

        await operation.release()
        let firstResponse = await firstRequest.value
        let finalInvocationCount = await operation.invocationCount

        #expect(
            firstResponse
                == .succeeded(message: "Mac Virtual Display is connected.")
        )
        #expect(finalInvocationCount == 1)
    }

    @Test("shows permissions until every required permission is granted")
    func permissionsDeterminePresentedView() {
        let missingAccessibility = ConnectionModel(
            hasAccessibilityAccess: { false },
            initialLocalNetworkAccess: .granted
        )
        let missingLocalNetwork = ConnectionModel(
            hasAccessibilityAccess: { true },
            initialLocalNetworkAccess: .needsAccess
        )
        let allGranted = ConnectionModel(
            hasAccessibilityAccess: { true },
            initialLocalNetworkAccess: .granted
        )

        #expect(missingAccessibility.viewState == .permissions)
        #expect(missingLocalNetwork.viewState == .permissions)
        #expect(allGranted.viewState == .connection)
    }

    @Test("requesting Accessibility access refreshes its current value")
    func requestingAccessibilityRefreshesItsValue() {
        var isGranted = false
        var requestCount = 0
        let model = ConnectionModel(
            hasAccessibilityAccess: { isGranted },
            requestAccessibilityAccess: {
                requestCount += 1
                isGranted = true
            },
            initialLocalNetworkAccess: .granted
        )

        model.requestAccessibilityPermission()

        #expect(requestCount == 1)
        #expect(model.accessibilityAccessGranted)
        #expect(model.viewState == .connection)
    }

    @Test("a local connection rechecks Accessibility before doing work")
    func localConnectionRechecksAccessibility() async {
        let access = TestAccessibilityAccess(isGranted: true)
        var didConnect = false
        let model = makeConnectionModel(
            connect: { _ in
                didConnect = true
                return "Mac Virtual Display is connected."
            },
            hasAccessibilityAccess: { access.isGranted }
        )
        access.isGranted = false

        let response = await model.connectAndExtend()

        #expect(!didConnect)
        #expect(model.viewState == .permissions)
        #expect(
            response == .failed(
                message: "Grant Accessibility access to Mac Display "
                    + "Connect, then try again."
            )
        )
    }

    @Test("an AVP connection rechecks Accessibility before doing work")
    func remoteConnectionRechecksAccessibility() async {
        let access = TestAccessibilityAccess(isGranted: true)
        var didConnect = false
        let model = makeConnectionModel(
            connect: { _ in
                didConnect = true
                return "Mac Virtual Display is connected."
            },
            activateForRemoteConnection: { true },
            hasAccessibilityAccess: { access.isGranted }
        )
        access.isGranted = false

        let response = await model.handleRemoteConnect()

        #expect(!didConnect)
        #expect(model.viewState == .permissions)
        #expect(
            response == .failed(
                message: "Grant Accessibility access to Mac Display "
                    + "Connect, then try again."
            )
        )
    }

    @Test("a Local Network revocation returns to the permissions view")
    func localNetworkRevocationReturnsToPermissions() async {
        let model = ConnectionModel(
            hasAccessibilityAccess: { true },
            localNetworkAccessEvents: {
                AsyncStream { continuation in
                    continuation.yield(.needsAccess)
                }
            },
            initialLocalNetworkAccess: .granted
        )

        let monitoringTask = Task { @MainActor in
            await model.monitorPermissions()
        }
        await waitUntil {
            model.localNetworkAccess == .needsAccess
        }

        #expect(model.localNetworkAccess == .needsAccess)
        #expect(model.viewState == .permissions)

        monitoringTask.cancel()
        await monitoringTask.value
    }

    @Test("restarts Local Network monitoring after a browser failure")
    func restartsLocalNetworkMonitoringAfterFailure() async {
        let events = RetryingLocalNetworkAccessEvents()
        let model = ConnectionModel(
            hasAccessibilityAccess: { true },
            localNetworkAccessEvents: {
                events.nextStream()
            },
            waitBeforeLocalNetworkRetry: {},
            initialLocalNetworkAccess: .granted
        )

        let monitoringTask = Task { @MainActor in
            await model.monitorPermissions()
        }
        await waitUntil {
            model.localNetworkAccess == .needsAccess
        }

        #expect(events.invocationCount >= 2)
        #expect(model.localNetworkAccess == .needsAccess)

        monitoringTask.cancel()
        await monitoringTask.value
    }

    @Test("a connection does no work without Local Network access")
    func localNetworkAccessIsCheckedBeforeConnecting() async {
        var didConnect = false
        let model = ConnectionModel(
            connect: { _ in
                didConnect = true
                return "Mac Virtual Display is connected."
            },
            hasAccessibilityAccess: { true },
            initialLocalNetworkAccess: .needsAccess
        )

        let response = await model.connectAndExtend()

        #expect(!didConnect)
        #expect(
            response == .failed(
                message: "Grant Local Network access to Mac Display "
                    + "Connect, then try again."
            )
        )
    }
}

@MainActor
private func makeConnectionModel(
    connect: @escaping ConnectionModel.ConnectOperation = { _ in
        "Mac Virtual Display is connected."
    },
    activateForRemoteConnection:
        @escaping ConnectionModel.ActivationOperation = { true },
    connectionStatus:
        @escaping ConnectionModel.ConnectionStatusOperation = { false },
    hasAccessibilityAccess: @escaping @MainActor () -> Bool = { true }
) -> ConnectionModel {
    ConnectionModel(
        connect: connect,
        activateForRemoteConnection: activateForRemoteConnection,
        connectionStatus: connectionStatus,
        hasAccessibilityAccess: hasAccessibilityAccess,
        initialLocalNetworkAccess: .granted
    )
}

private struct TestConnectionError: LocalizedError {
    var errorDescription: String? {
        "Test connection failed."
    }
}

@MainActor
private final class TestAccessibilityAccess {
    var isGranted: Bool

    init(isGranted: Bool) {
        self.isGranted = isGranted
    }
}

private final class RetryingLocalNetworkAccessEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var invocationCount: Int {
        lock.lock()
        defer {
            lock.unlock()
        }
        return count
    }

    func nextStream() -> AsyncStream<LocalNetworkAccessStatus> {
        lock.lock()
        count += 1
        let invocation = count
        lock.unlock()

        return AsyncStream { continuation in
            if invocation == 1 {
                continuation.yield(.unavailable("Network failed."))
                continuation.finish()
            } else {
                continuation.yield(.needsAccess)
            }
        }
    }
}

@MainActor
private func waitUntil(_ condition: () -> Bool) async {
    for _ in 0..<100 {
        guard !condition() else {
            return
        }
        await Task.yield()
    }
}

private actor SuspendedConnectOperation {
    private(set) var invocationCount = 0
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var startContinuations: [CheckedContinuation<Void, Never>] = []

    func run() async -> String {
        invocationCount += 1

        let continuations = startContinuations
        startContinuations.removeAll()
        continuations.forEach { $0.resume() }

        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }

        return "Mac Virtual Display is connected."
    }

    func waitUntilStarted() async {
        guard invocationCount == 0 else {
            return
        }

        await withCheckedContinuation { continuation in
            startContinuations.append(continuation)
        }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}
