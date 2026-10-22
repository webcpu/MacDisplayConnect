import Foundation
import Testing
@testable import MacDisplayConnect

@Suite("Vision Pro device discovery")
@MainActor
struct VisionProDeviceDiscoveryTests {
    private let uuid = NSUUID(uuidString: "54FAD8ED-2AF7-449A-90BC-85055F42ABAD")!

    @Test("a reality device supplies both exact Control Center identifiers")
    func includesBothIdentifiers() {
        let device = DiscoveryDevice(identifier: uuid, route: "route-42")

        #expect(VisionProDeviceDiscovery.controlCenterIdentifiers(from: [device]) == [
            "screen-mirroring-device-Sidecar:\(uuid.uuidString)",
            "screen-mirroring-device-AirPlay:route-42",
        ])
    }

    @Test("other device types are excluded regardless of their identifiers")
    func excludesNonRealityDevice() {
        let device = DiscoveryDevice(isRealityDevice: false, identifier: uuid, route: "route-42")

        #expect(VisionProDeviceDiscovery.controlCenterIdentifiers(from: [device]).isEmpty)
    }

    @Test("objects without the reality-device getter are excluded")
    func excludesMissingGetter() {
        #expect(VisionProDeviceDiscovery.controlCenterIdentifiers(from: [NSObject()]).isEmpty)
    }

    @Test("a non-Boolean reality-device getter is never invoked as a Boolean")
    func excludesWrongFlagReturnType() {
        #expect(VisionProDeviceDiscovery.controlCenterIdentifiers(from: [WrongFlagDevice()]).isEmpty)
    }

    @Test("a reality device without identity getters produces no identifiers")
    func excludesMissingIdentityGetters() {
        #expect(VisionProDeviceDiscovery.controlCenterIdentifiers(from: [UnidentifiedDevice()]).isEmpty)
    }

    @Test("a missing UUID does not prevent a valid media-route identifier")
    func acceptsRouteWithoutUUID() {
        let device = DiscoveryDevice(identifier: nil, route: "route-42")

        #expect(VisionProDeviceDiscovery.controlCenterIdentifiers(from: [device]) == [
            "screen-mirroring-device-AirPlay:route-42",
        ])
    }

    @Test("a string is not accepted in place of the device UUID")
    func rejectsWrongIdentifierObject() {
        let device = DiscoveryDevice(identifier: uuid.uuidString as NSString, route: nil)

        #expect(VisionProDeviceDiscovery.controlCenterIdentifiers(from: [device]).isEmpty)
    }

    @Test("an empty media route does not produce an AirPlay identifier")
    func rejectsEmptyRoute() {
        let device = DiscoveryDevice(identifier: uuid, route: "")

        #expect(VisionProDeviceDiscovery.controlCenterIdentifiers(from: [device]) == [
            "screen-mirroring-device-Sidecar:\(uuid.uuidString)",
        ])
    }

    @Test("a non-string media route is excluded")
    func rejectsWrongRouteObject() {
        let device = DiscoveryDevice(identifier: nil, route: NSNumber(value: 42))

        #expect(VisionProDeviceDiscovery.controlCenterIdentifiers(from: [device]).isEmpty)
    }

    @Test("non-object identity getters are never invoked as object getters")
    func rejectsWrongIdentityReturnTypes() {
        #expect(VisionProDeviceDiscovery.controlCenterIdentifiers(from: [WrongIdentityDevice()]).isEmpty)
    }
}

private final class DiscoveryDevice: NSObject {
    @objc let isRealityDevice: Bool
    @objc let identifier: AnyObject?
    @objc let mediaRouteIdentifier: AnyObject?

    init(isRealityDevice: Bool = true, identifier: AnyObject?, route: Any?) {
        self.isRealityDevice = isRealityDevice
        self.identifier = identifier
        mediaRouteIdentifier = route as AnyObject?
    }
}

private final class WrongFlagDevice: NSObject {
    @objc var isRealityDevice: Int { 1 }
    @objc var mediaRouteIdentifier: NSString { "route-42" }
}

private final class UnidentifiedDevice: NSObject {
    @objc var isRealityDevice: Bool { true }
}

private final class WrongIdentityDevice: NSObject {
    @objc var isRealityDevice: Bool { true }
    @objc var identifier: Int { 42 }
    @objc var mediaRouteIdentifier: Int { 42 }
}
