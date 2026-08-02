import Foundation
import OSLog
import SwiftUI

@main
struct MacDisplayConnectVisionApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var autoConnectPreference: AutoConnectPreference
    @State private var model: VisionConnectionModel

    init() {
        let preference = AutoConnectPreference()
        _autoConnectPreference = State(initialValue: preference)
        _model = State(
            initialValue: VisionConnectionModel(
                autoConnectEnabled: { preference.isEnabled }
            )
        )
        VisionDiagnosticLog.record(
            "Application initialized: pid="
                + "\(ProcessInfo.processInfo.processIdentifier)"
        )
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                VisionConnectionView(model: model)
            }
            .frame(width: 560, height: 460)
            .overlay(alignment: .topTrailing) {
                AutoConnectOptionsMenu(
                    preference: autoConnectPreference
                )
                .padding(20)
            }
            .onAppear {
                VisionDiagnosticLog.record("Window appeared")
            }
        }
        .defaultSize(width: 560, height: 460)
        .windowResizability(.contentSize)
        .onChange(of: scenePhase, initial: true) { oldPhase, newPhase in
            VisionDiagnosticLog.record(
                "Scene phase: \(oldPhase.diagnosticName) -> "
                    + newPhase.diagnosticName
            )

            if newPhase == .active {
                Task {
                    await model.sceneDidBecomeActive()
                }
            } else {
                model.sceneDidLeaveActive()
            }
        }
    }
}

enum VisionDiagnosticLog {
    private static let logger = Logger(
        subsystem: "local.macdisplayconnect.vision",
        category: "VisionLifecycle"
    )

    static func record(_ message: String) {
        logger.notice("\(message, privacy: .public)")
    }
}

private extension ScenePhase {
    var diagnosticName: String {
        switch self {
        case .active:
            "active"
        case .inactive:
            "inactive"
        case .background:
            "background"
        @unknown default:
            "unknown"
        }
    }
}
