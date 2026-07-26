import Foundation

enum MacDisplayConnectError: LocalizedError {
    case accessibilityPermissionRequired
    case controlCenterNotRunning
    case screenMirroringControlNotFound
    case visionProControlNotFound
    case connectionNotConfirmed

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionRequired:
            "Grant Accessibility access to Mac Display Connect, then try again."
        case .controlCenterNotRunning:
            "macOS Control Center is not running."
        case .screenMirroringControlNotFound:
            "Screen Mirroring was not found in Control Center."
        case .visionProControlNotFound:
            "No Apple Vision Pro was found in Screen Mirroring."
        case .connectionNotConfirmed:
            "Mac Virtual Display did not become active."
        }
    }
}
