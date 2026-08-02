import MacDisplayConnectCore
import MacDisplayConnectTransport
import Foundation
import Network
import Testing
@testable import MacDisplayConnectVision

@MainActor
@Suite("Vision connection model")
struct VisionConnectionModelTests {
    @Test("connection phases use Mac Virtual Display terminology")
    func connectionPhaseTerminology() {
        #expect(
            VisionConnectionPhase.success("Connected.").title
                == "Connected"
        )
        #expect(
            VisionConnectionPhase.connecting("Desk Mac").message
                == "Asking Desk Mac to start Mac Virtual Display…"
        )
    }

    @Test("only actionable phases offer a button title")
    func connectionPhaseActions() {
        #expect(VisionConnectionPhase.searching.actionTitle == nil)
        #expect(VisionConnectionPhase.ready.actionTitle == "Connect")
        #expect(
            VisionConnectionPhase.connecting("Desk Mac").actionTitle
                == nil
        )
        #expect(
            VisionConnectionPhase.success("Connected.").actionTitle
                == nil
        )
        #expect(
            VisionConnectionPhase.statusUnavailable.actionTitle
                == "Connect"
        )
        #expect(
            VisionConnectionPhase.failure("Failed.").actionTitle
                == "Try Again"
        )
        #expect(
            VisionConnectionPhase.discoveryFailure("Failed.").actionTitle
                == nil
        )
    }

    @Test("shows Macs received from discovery")
    func receivesDiscoveredMacs() async {
        let mac = makeMac(name: "Studio Mac")
        let events = AsyncStream<RemoteDiscoveryEvent> { continuation in
            continuation.yield(.results([mac]))
            continuation.finish()
        }
        let model = VisionConnectionModel(
            discover: { events },
            connect: { _, _ in .busy }
        )

        await model.startDiscovery()

        #expect(model.macs == [mac])
        #expect(model.phase == .ready)
    }

    @Test("auto-connects to the discovered preferred Mac when active")
    func autoConnectsWhenSceneBecomesActive() async {
        let mac = makeMac(name: "Studio Mac")
        let events = AsyncStream<RemoteDiscoveryEvent> { continuation in
            continuation.yield(.results([mac]))
            continuation.finish()
        }
        let endpoints = EndpointProbe()
        let model = VisionConnectionModel(
            discover: { events },
            connect: { _, endpoint in
                await endpoints.record(endpoint)
                return .failed(message: "Not connected")
            }
        )

        await model.startDiscovery()
        await model.connect(to: mac)
        await model.sceneDidBecomeActive()

        #expect(await endpoints.values() == [mac.endpoint, mac.endpoint])
        #expect(model.phase == .failure("Not connected"))
    }

    @Test("waits for the preferred Mac and retries only on discovery updates")
    func waitsForPreferredMacAndDiscoveryUpdates() async {
        let preferredMac = makeMac(name: "Studio Mac")
        let otherMac = makeMac(name: "Other Mac")
        let events = AsyncStream<RemoteDiscoveryEvent> { continuation in
            continuation.yield(.results([otherMac]))
            continuation.yield(.results([otherMac, preferredMac]))
            continuation.yield(.results([preferredMac, otherMac]))
            continuation.finish()
        }
        let endpoints = EndpointProbe()
        let model = VisionConnectionModel(
            discover: { events },
            connect: { _, endpoint in
                await endpoints.record(endpoint)
                return .failed(message: "Not connected")
            }
        )

        await model.connect(to: preferredMac)
        await model.sceneDidBecomeActive()
        await model.startDiscovery()

        #expect(
            await endpoints.values()
                == [
                    preferredMac.endpoint,
                    preferredMac.endpoint,
                    preferredMac.endpoint,
                ]
        )
        #expect(model.phase == .failure("Not connected"))
    }

    @Test("auto-connect decision requires the discovered preferred Mac")
    func autoConnectRequiresDiscoveredPreferredMac() {
        let preferredMac = makeMac(name: "Studio Mac")
        let otherMac = makeMac(name: "Other Mac")

        #expect(
            autoConnectDecision(
                isEnabled: true,
                isArmed: true,
                phase: .ready,
                preferredMac: preferredMac,
                discoveredMacs: [otherMac]
            ) == .waitForPreferredMac
        )
        #expect(
            autoConnectDecision(
                isEnabled: true,
                isArmed: true,
                phase: .ready,
                preferredMac: preferredMac,
                discoveredMacs: [otherMac, preferredMac]
            ) == .connect(preferredMac)
        )
    }

    @Test("disabled auto-connect consumes an armed decision")
    func disabledAutoConnectDecision() {
        let preferredMac = makeMac(name: "Studio Mac")

        #expect(
            autoConnectDecision(
                isEnabled: false,
                isArmed: true,
                phase: .ready,
                preferredMac: preferredMac,
                discoveredMacs: [preferredMac]
            ) == .disabled
        )
    }

    @Test("disabled preference prevents auto-connect at activation")
    func disabledPreferencePreventsActivationAutoConnect() async {
        let mac = makeMac(name: "Studio Mac")
        let events = AsyncStream<RemoteDiscoveryEvent> { continuation in
            continuation.yield(.results([mac]))
            continuation.finish()
        }
        let endpoints = EndpointProbe()
        let preference = AutoConnectEnabledProbe(false)
        let model = VisionConnectionModel(
            discover: { events },
            autoConnectEnabled: { preference.value },
            connect: { _, endpoint in
                await endpoints.record(endpoint)
                return .failed(message: "Not connected")
            }
        )
        await model.startDiscovery()
        await model.connect(to: mac)

        await model.sceneDidBecomeActive()

        #expect(await endpoints.values() == [mac.endpoint])
        #expect(model.phase == .failure("Not connected"))
    }

    @Test("disabling while waiting prevents later discovery auto-connect")
    func disablingWhileWaitingPreventsDiscoveryAutoConnect() async {
        let mac = makeMac(name: "Studio Mac")
        let events = AsyncStream<RemoteDiscoveryEvent> { continuation in
            continuation.yield(.results([mac]))
            continuation.finish()
        }
        let endpoints = EndpointProbe()
        let preference = AutoConnectEnabledProbe(true)
        let model = VisionConnectionModel(
            discover: { events },
            autoConnectEnabled: { preference.value },
            connect: { _, endpoint in
                await endpoints.record(endpoint)
                return .failed(message: "Not connected")
            }
        )
        await model.connect(to: mac)
        await model.sceneDidBecomeActive()
        preference.value = false

        await model.startDiscovery()

        #expect(await endpoints.values() == [mac.endpoint])
        #expect(model.phase == .failure("Not connected"))
    }

    @Test("manual connection remains available while auto-connect is disabled")
    func manualConnectionWorksWhileAutoConnectDisabled() async {
        let mac = makeMac(name: "Studio Mac")
        let endpoints = EndpointProbe()
        let model = VisionConnectionModel(
            discover: emptyDiscovery,
            autoConnectEnabled: { false },
            connect: { _, endpoint in
                await endpoints.record(endpoint)
                return .succeeded(message: "Connected")
            }
        )

        await model.connect(to: mac)

        #expect(await endpoints.values() == [mac.endpoint])
        #expect(model.phase == .success("Connected"))
    }

    @Test("re-enabling waits for a later automatic opportunity")
    func reenablingWaitsForFutureDiscovery() async {
        let mac = makeMac(name: "Studio Mac")
        let (events, continuation) =
            AsyncStream<RemoteDiscoveryEvent>.makeStream()
        let endpoints = EndpointProbe()
        let preference = AutoConnectEnabledProbe(false)
        let model = VisionConnectionModel(
            discover: { events },
            autoConnectEnabled: { preference.value },
            connect: { _, endpoint in
                await endpoints.record(endpoint)
                return .failed(message: "Not connected")
            }
        )
        await model.connect(to: mac)
        await model.sceneDidBecomeActive()
        preference.value = true

        #expect(await endpoints.values() == [mac.endpoint])

        let discovery = Task { @MainActor in
            await model.startDiscovery()
        }
        continuation.yield(.results([mac]))
        continuation.finish()
        await discovery.value

        #expect(await endpoints.values() == [mac.endpoint, mac.endpoint])
    }

    @Test("disabling during an auto-connect clears its pending intent")
    func disablingDuringAutoConnectClearsPendingIntent() async {
        let mac = makeMac(name: "Studio Mac")
        let events = AsyncStream<RemoteDiscoveryEvent> { continuation in
            continuation.yield(.results([mac]))
            continuation.finish()
        }
        let connection = DelayedAutoConnectOperation()
        let preference = AutoConnectEnabledProbe(true)
        let model = VisionConnectionModel(
            discover: { events },
            autoConnectEnabled: { preference.value },
            connect: { _, endpoint in
                await connection.run(endpoint: endpoint)
            },
            status: { _ in .status(isConnected: false) }
        )
        await model.startDiscovery()
        await model.connect(to: mac)
        let activation = Task { @MainActor in
            await model.sceneDidBecomeActive()
        }
        await connection.waitUntilAutoConnectRequested()
        preference.value = false
        await connection.releaseAutoConnect(
            .failed(message: "Not connected")
        )
        await activation.value

        preference.value = true
        await model.refreshStatus()

        #expect(
            await connection.endpoints()
                == [mac.endpoint, mac.endpoint]
        )
    }

    @Test("does not auto-connect again while already connected")
    func skipsAutoConnectWhenConnected() async {
        let mac = makeMac(name: "Studio Mac")
        let endpoints = EndpointProbe()
        let model = VisionConnectionModel(
            discover: emptyDiscovery,
            connect: { _, endpoint in
                await endpoints.record(endpoint)
                return .succeeded(message: "Connected")
            },
            status: { _ in .status(isConnected: true) }
        )

        await model.connect(to: mac)
        await model.sceneDidBecomeActive()
        await model.refreshStatus()

        #expect(await endpoints.values() == [mac.endpoint])
        #expect(
            model.phase
                == .success("Mac Virtual Display is connected.")
        )
    }

    @Test("reconnects when status corrects stale connected state after activation")
    func reconnectsAfterActiveStatusRefresh() async {
        let mac = makeMac(name: "Studio Mac")
        let events = AsyncStream<RemoteDiscoveryEvent> { continuation in
            continuation.yield(.results([mac]))
            continuation.finish()
        }
        let endpoints = EndpointProbe()
        let model = VisionConnectionModel(
            discover: { events },
            connect: { _, endpoint in
                await endpoints.record(endpoint)
                return .succeeded(message: "Connected")
            },
            status: { _ in .status(isConnected: false) }
        )
        await model.startDiscovery()
        await model.connect(to: mac)

        await model.sceneDidBecomeActive()
        await model.refreshStatus()

        #expect(await endpoints.values() == [mac.endpoint, mac.endpoint])
        #expect(model.phase == .success("Connected"))
    }

    @Test("does not auto-connect while a connection attempt is in progress")
    func skipsAutoConnectWhileConnecting() async {
        let mac = makeMac(name: "Studio Mac")
        let connection = SuspendedConnectOperation()
        let model = VisionConnectionModel(
            discover: emptyDiscovery,
            connect: { _, endpoint in
                await connection.run(endpoint: endpoint)
            }
        )
        let manualConnection = Task { @MainActor in
            await model.connect(to: mac)
        }
        await connection.waitUntilRequested()

        await model.sceneDidBecomeActive()

        #expect(await connection.endpoints() == [mac.endpoint])
        await connection.release(.succeeded(message: "Connected"))
        await manualConnection.value
    }

    @Test("does not auto-connect after the active session ends")
    func doesNotAutoConnectAfterSceneLeavesActive() async {
        let mac = makeMac(name: "Studio Mac")
        let events = AsyncStream<RemoteDiscoveryEvent> { continuation in
            continuation.yield(.results([mac]))
            continuation.finish()
        }
        let endpoints = EndpointProbe()
        let model = VisionConnectionModel(
            discover: { events },
            connect: { _, endpoint in
                await endpoints.record(endpoint)
                return .succeeded(message: "Connected")
            }
        )

        await model.sceneDidBecomeActive()
        model.sceneDidLeaveActive()
        await model.startDiscovery()

        #expect(await endpoints.values().isEmpty)
        #expect(model.phase == .ready)
    }

    @Test("connects to the selected Mac and shows its success")
    func connectsToSelectedMac() async {
        let mac = makeMac(name: "Desk Mac")
        let endpoints = EndpointProbe()
        let model = VisionConnectionModel(
            discover: emptyDiscovery,
            connect: { _, endpoint in
                await endpoints.record(endpoint)
                return .succeeded(message: "Mac Virtual Display is extended.")
            }
        )

        await model.connect(to: mac)

        #expect(await endpoints.values() == [mac.endpoint])
        #expect(
            model.phase
                == .success("Mac Virtual Display is extended.")
        )
    }

    @Test("sends the current Vision Pro name to the selected Mac")
    func sendsCurrentVisionProName() async {
        let mac = makeMac(name: "Desk Mac")
        let currentName = VisionProNameProbe("Old Vision Pro Name")
        let connection = ConnectionProbe()
        let model = VisionConnectionModel(
            discover: emptyDiscovery,
            visionProName: { currentName.value },
            connect: { request, endpoint in
                await connection.record(request, endpoint)
                return .succeeded(message: "Connected")
            }
        )
        currentName.value = "S’s Apple Vision Pro"

        await model.connect(to: mac)

        #expect(
            await connection.requests()
                == [.connect(visionProName: "S’s Apple Vision Pro")]
        )
        #expect(await connection.endpoints() == [mac.endpoint])
    }

    @Test("explains when the Mac is already connecting")
    func reportsBusyMac() async {
        let model = VisionConnectionModel(
            discover: emptyDiscovery,
            connect: { _, _ in .busy }
        )

        await model.connect(to: makeMac())

        #expect(
            model.phase
                == .failure("The Mac is already connecting. Try again shortly.")
        )
    }

    @Test("shows a connection error")
    func reportsConnectionError() async {
        let model = VisionConnectionModel(
            discover: emptyDiscovery,
            connect: { _, _ in throw TestError.unreachable }
        )

        await model.connect(to: makeMac())

        #expect(model.phase == .failure("The Mac could not be reached."))
    }

    @Test("clears a stale success when the Mac reports disconnected")
    func clearsStaleSuccess() async {
        let mac = makeMac(name: "Desk Mac")
        let model = VisionConnectionModel(
            discover: emptyDiscovery,
            connect: { _, _ in
                .succeeded(message: "Mac Virtual Display is extended.")
            },
            status: { _ in .status(isConnected: false) }
        )

        await model.connect(to: mac)
        await model.refreshStatus()

        #expect(model.phase == .searching)
    }

    @Test("returns to ready when a discovered Mac reports disconnected")
    func showsDiscoveredMacAsReadyWhenDisconnected() async {
        let mac = makeMac(name: "Desk Mac")
        let events = AsyncStream<RemoteDiscoveryEvent> { continuation in
            continuation.yield(.results([mac]))
            continuation.finish()
        }
        let model = VisionConnectionModel(
            discover: { events },
            connect: { _, _ in
                .succeeded(message: "Mac Virtual Display is extended.")
            },
            status: { _ in .status(isConnected: false) }
        )

        await model.startDiscovery()
        await model.connect(to: mac)
        await model.refreshStatus()

        #expect(model.phase == .ready)
    }

    @Test("shows unknown instead of disconnected when live status is unavailable")
    func showsUnknownWhenStatusFails() async {
        let model = VisionConnectionModel(
            discover: emptyDiscovery,
            connect: { _, _ in
                .succeeded(message: "Mac Virtual Display is extended.")
            },
            status: { _ in throw TestError.unreachable }
        )

        await model.connect(to: makeMac())
        await model.refreshStatus()

        #expect(model.phase == .statusUnavailable)
    }

    @Test("ignores a status response started before a newer connection")
    func ignoresStaleStatusResponse() async {
        let mac = makeMac(name: "Desk Mac")
        let status = SuspendedStatusOperation()
        let model = VisionConnectionModel(
            discover: emptyDiscovery,
            connect: { _, _ in
                .succeeded(message: "Mac Virtual Display is connected.")
            },
            status: { _ in await status.run() }
        )
        await model.connect(to: mac)
        let refresh = Task { @MainActor in
            await model.refreshStatus()
        }
        await status.waitUntilRequested()

        await model.connect(to: mac)
        await status.release(.status(isConnected: false))
        await refresh.value

        #expect(
            model.phase
                == .success("Mac Virtual Display is connected.")
        )
    }

    @Test("keeps discovery inventory current while showing connected")
    func updatesDiscoveryInventoryWhileConnected() async {
        let mac = makeMac(name: "Desk Mac")
        let (events, continuation) =
            AsyncStream<RemoteDiscoveryEvent>.makeStream()
        let model = VisionConnectionModel(
            discover: { events },
            connect: { _, _ in
                .succeeded(message: "Mac Virtual Display is connected.")
            }
        )
        let discovery = Task { @MainActor in
            await model.startDiscovery()
        }
        continuation.yield(.results([mac]))
        for _ in 0..<20 where model.macs.isEmpty {
            await Task.yield()
        }
        await model.connect(to: mac)

        continuation.yield(.results([]))
        for _ in 0..<20 where !model.macs.isEmpty {
            await Task.yield()
        }
        continuation.finish()
        await discovery.value

        #expect(model.macs.isEmpty)
        #expect(model.phase == .statusUnavailable)
    }

    @Test("returns to ready when an unavailable Mac reappears")
    func recoversWhenSelectedMacReappears() async {
        let mac = makeMac(name: "Desk Mac")
        let (events, continuation) =
            AsyncStream<RemoteDiscoveryEvent>.makeStream()
        let model = VisionConnectionModel(
            discover: { events },
            connect: { _, _ in
                .succeeded(message: "Mac Virtual Display is connected.")
            }
        )
        let discovery = Task { @MainActor in
            await model.startDiscovery()
        }

        continuation.yield(.results([mac]))
        for _ in 0..<20 where model.macs.isEmpty {
            await Task.yield()
        }
        await model.connect(to: mac)

        continuation.yield(.results([]))
        for _ in 0..<20 where !model.macs.isEmpty {
            await Task.yield()
        }
        #expect(model.phase == .statusUnavailable)

        continuation.yield(.results([mac]))
        for _ in 0..<20 where model.macs.isEmpty {
            await Task.yield()
        }
        continuation.finish()
        await discovery.value

        #expect(model.phase == .ready)
    }

    @Test("shows connected when a discovered Mac reports connected")
    func showsLiveConnectedStatus() async {
        let mac = makeMac(name: "Studio Mac")
        let events = AsyncStream<RemoteDiscoveryEvent> { continuation in
            continuation.yield(.results([mac]))
            continuation.finish()
        }
        let endpoints = EndpointProbe()
        let model = VisionConnectionModel(
            discover: { events },
            connect: { _, _ in .busy },
            status: { endpoint in
                await endpoints.record(endpoint)
                return .status(isConnected: true)
            }
        )

        await model.startDiscovery()
        await model.refreshStatus()

        #expect(await endpoints.values() == [mac.endpoint])
        #expect(
            model.phase
                == .success("Mac Virtual Display is connected.")
        )
    }
}

private actor EndpointProbe {
    private var endpoints: [NWEndpoint] = []

    func record(_ endpoint: NWEndpoint) {
        endpoints.append(endpoint)
    }

    func values() -> [NWEndpoint] {
        endpoints
    }
}

private actor ConnectionProbe {
    private var recordedRequests: [RemoteRequest] = []
    private var recordedEndpoints: [NWEndpoint] = []

    func record(_ request: RemoteRequest, _ endpoint: NWEndpoint) {
        recordedRequests.append(request)
        recordedEndpoints.append(endpoint)
    }

    func requests() -> [RemoteRequest] {
        recordedRequests
    }

    func endpoints() -> [NWEndpoint] {
        recordedEndpoints
    }
}

@MainActor
private final class VisionProNameProbe {
    var value: String

    init(_ value: String) {
        self.value = value
    }
}

@MainActor
private final class AutoConnectEnabledProbe {
    var value: Bool

    init(_ value: Bool) {
        self.value = value
    }
}

private actor SuspendedStatusOperation {
    private var didStart = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var responseWaiter:
        CheckedContinuation<RemoteResponse, Never>?

    func run() async -> RemoteResponse {
        didStart = true
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()

        return await withCheckedContinuation { continuation in
            responseWaiter = continuation
        }
    }

    func waitUntilRequested() async {
        guard !didStart else {
            return
        }

        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func release(_ response: RemoteResponse) {
        responseWaiter?.resume(returning: response)
        responseWaiter = nil
    }
}

private actor SuspendedConnectOperation {
    private var recordedEndpoints: [NWEndpoint] = []
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var responseWaiter:
        CheckedContinuation<RemoteResponse, Never>?

    func run(endpoint: NWEndpoint) async -> RemoteResponse {
        recordedEndpoints.append(endpoint)
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()

        return await withCheckedContinuation { continuation in
            responseWaiter = continuation
        }
    }

    func waitUntilRequested() async {
        guard recordedEndpoints.isEmpty else {
            return
        }

        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func endpoints() -> [NWEndpoint] {
        recordedEndpoints
    }

    func release(_ response: RemoteResponse) {
        responseWaiter?.resume(returning: response)
        responseWaiter = nil
    }
}

private actor DelayedAutoConnectOperation {
    private var recordedEndpoints: [NWEndpoint] = []
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var responseWaiter:
        CheckedContinuation<RemoteResponse, Never>?

    func run(endpoint: NWEndpoint) async -> RemoteResponse {
        recordedEndpoints.append(endpoint)

        guard recordedEndpoints.count > 1 else {
            return .failed(message: "Not connected")
        }

        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()
        return await withCheckedContinuation { continuation in
            responseWaiter = continuation
        }
    }

    func waitUntilAutoConnectRequested() async {
        guard recordedEndpoints.count < 2 else {
            return
        }

        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func endpoints() -> [NWEndpoint] {
        recordedEndpoints
    }

    func releaseAutoConnect(_ response: RemoteResponse) {
        responseWaiter?.resume(returning: response)
        responseWaiter = nil
    }
}

private enum TestError: LocalizedError {
    case unreachable

    var errorDescription: String? {
        "The Mac could not be reached."
    }
}

private func makeMac(name: String = "Mac") -> RemoteMac {
    RemoteMac(
        endpoint: .service(
            name: name,
            type: "_macdisplayconnect._tcp",
            domain: "local.",
            interface: nil
        )
    )!
}

private func emptyDiscovery() -> AsyncStream<RemoteDiscoveryEvent> {
    AsyncStream { continuation in
        continuation.finish()
    }
}
