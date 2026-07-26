import AppKit
import SwiftUI

@main
struct MacDisplayConnectApp: App {
    @NSApplicationDelegateAdaptor(MacDisplayConnectApplicationDelegate.self)
    private var applicationDelegate

    @State private var model = ConnectionModel()

    var body: some Scene {
        WindowGroup("Mac Display Connect") {
            MacDisplayConnectRootView(model: model)
                .onAppear {
                    applicationDelegate.startPermissionMonitoring(
                        model: model
                    )
                }
        }
        .defaultSize(width: 420, height: 330)
        .windowResizability(.contentSize)
    }
}

struct MacDisplayConnectRootView: View {
    let model: ConnectionModel

    var body: some View {
        ZStack {
            switch model.viewState {
            case .permissions:
                PermissionsView(model: model)
            case .connection:
                ConnectionView(model: model)
            }
        }
    }
}

@MainActor
final class MacDisplayConnectApplicationDelegate:
    NSObject, NSApplicationDelegate {
    private weak var model: ConnectionModel?
    private var permissionMonitoringTask: Task<Void, Never>?

    func startPermissionMonitoring(model: ConnectionModel) {
        self.model = model
        guard permissionMonitoringTask == nil else {
            return
        }

        permissionMonitoringTask = Task { [weak self, model] in
            await model.monitorPermissions()
            self?.permissionMonitoringTask = nil
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        model?.refreshAccessibilityPermission()
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionMonitoringTask?.cancel()
        permissionMonitoringTask = nil
    }
}
