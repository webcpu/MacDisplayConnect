import Network
import Testing
@testable import MacDisplayConnectTransport

@Suite("Remote Mac discovery")
struct RemoteDiscoveryTests {
    @Test("maps a Bonjour service endpoint to a named Mac")
    func mapsBonjourEndpoint() {
        let endpoint = NWEndpoint.service(
            name: "Studio Mac",
            type: "_macdisplayconnect._tcp",
            domain: "local.",
            interface: nil
        )

        let mac = RemoteMac(endpoint: endpoint)

        #expect(mac?.name == "Studio Mac")
        #expect(mac?.endpoint == endpoint)
    }

    @Test("ignores endpoints that are not Bonjour services")
    func ignoresNonBonjourEndpoint() {
        let endpoint = NWEndpoint.hostPort(
            host: .ipv4(.loopback),
            port: 9_999
        )

        #expect(RemoteMac(endpoint: endpoint) == nil)
    }
}
