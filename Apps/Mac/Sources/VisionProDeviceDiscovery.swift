import Darwin
import Foundation
import ObjectiveC

@MainActor
enum VisionProDeviceDiscovery {
    // SidecarCore is private: missing or changed runtime contracts must fail closed.
    private static let framework = dlopen(
        "/System/Library/PrivateFrameworks/SidecarCore.framework/SidecarCore",
        RTLD_LAZY
    )

    static func controlCenterIdentifiers() -> Set<String> {
        guard framework != nil,
              let deviceClass = NSClassFromString("SidecarDevice"),
              let devices = objectValue(from: deviceClass, selector: "allDevices") as? [AnyObject] else {
            return []
        }
        return controlCenterIdentifiers(from: devices)
    }

    static func controlCenterIdentifiers(from devices: [AnyObject]) -> Set<String> {
        var identifiers = Set<String>()
        for device in devices {
            let selector = NSSelectorFromString("isRealityDevice")
            guard let implementation = getter(on: device, selector: selector, returning: "B") else {
                continue
            }
            typealias BooleanGetter = @convention(c) (AnyObject, Selector) -> Bool
            let isRealityDevice = unsafeBitCast(implementation, to: BooleanGetter.self)
            guard isRealityDevice(device, selector) else { continue }

            if let uuid = objectValue(from: device, selector: "identifier") as? NSUUID {
                identifiers.insert("screen-mirroring-device-Sidecar:\(uuid.uuidString)")
            }
            if let route = objectValue(from: device, selector: "mediaRouteIdentifier") as? NSString,
               route.length > 0 {
                identifiers.insert("screen-mirroring-device-AirPlay:\(route)")
            }
        }
        return identifiers
    }

    private static func objectValue(from object: AnyObject, selector name: String) -> AnyObject? {
        let selector = NSSelectorFromString(name)
        guard let implementation = getter(on: object, selector: selector, returning: "@") else {
            return nil
        }
        typealias ObjectGetter = @convention(c) (AnyObject, Selector) -> Unmanaged<AnyObject>?
        let value = unsafeBitCast(implementation, to: ObjectGetter.self)
        return value(object, selector)?.takeUnretainedValue()
    }

    private static func getter(on object: AnyObject, selector: Selector, returning type: String) -> IMP? {
        guard let objectClass = object_getClass(object),
              let method = class_getInstanceMethod(objectClass, selector),
              method_getNumberOfArguments(method) == 2 else {
            return nil
        }
        let returnType = method_copyReturnType(method)
        defer { free(returnType) }
        guard String(cString: returnType) == type else { return nil }
        return method_getImplementation(method)
    }
}
