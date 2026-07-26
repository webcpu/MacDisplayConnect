import dnssd
import Network
import Testing
@testable import MacDisplayConnectTransport

@Suite("Local Network access")
struct LocalNetworkAccessTests {
    @Test("a ready Bonjour browser means access is granted")
    func readyBrowserMeansAccessIsGranted() {
        #expect(
            localNetworkAccessStatus(for: .ready) == .granted
        )
    }

    @Test("Bonjour policy denial means access is required")
    func policyDenialMeansAccessIsRequired() {
        let error = NWError.dns(
            DNSServiceErrorType(kDNSServiceErr_PolicyDenied)
        )

        #expect(
            localNetworkAccessStatus(for: .waiting(error))
                == .needsAccess
        )
    }

    @Test("a temporary network failure is not a permission denial")
    func temporaryFailureIsNotPermissionDenial() {
        let status = localNetworkAccessStatus(
            for: .waiting(.posix(.ENETDOWN))
        )

        guard case .unavailable = status else {
            Issue.record("Expected a temporary unavailable status.")
            return
        }
    }

    @Test("a failed browser reports unavailable")
    func failedBrowserReportsUnavailable() {
        let status = localNetworkAccessStatus(
            for: .failed(.posix(.ENETDOWN))
        )

        guard case .unavailable = status else {
            Issue.record("Expected a failed browser to be unavailable.")
            return
        }
    }
}
