import AppKit
import Darwin
import Foundation
import SwiftUI

@main
struct MacDisplayConnectApp: App {
    @NSApplicationDelegateAdaptor(MacDisplayConnectApplicationDelegate.self)
    private var applicationDelegate

    @State private var model = ConnectionModel()
    private let systemTestConfiguration: SystemTestConfiguration?
    private let launchError: String?

    init() {
        do {
            systemTestConfiguration = try SystemTestConfiguration.parse(
                arguments: CommandLine.arguments
            )
            launchError = nil
        } catch {
            systemTestConfiguration = nil
            launchError = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    var body: some Scene {
        WindowGroup("Mac Display Connect") {
            Group {
                if let systemTestConfiguration {
                    SystemTestStatusView(
                        configuration: systemTestConfiguration
                    )
                } else if let launchError {
                    SystemTestLaunchErrorView(message: launchError)
                } else {
                    MacDisplayConnectRootView(model: model)
                }
            }
                .onAppear {
                    applicationDelegate.start(
                        model: model,
                        systemTestConfiguration: systemTestConfiguration,
                        launchError: launchError
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

private struct SystemTestStatusView: View {
    let configuration: SystemTestConfiguration

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("System Test Running")
                .font(.title2.bold())
            Text(
                "\(configuration.cycleCount) physical-device "
                    + "connection cycles"
            )
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}

private struct SystemTestLaunchErrorView: View {
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
            Text("Invalid System Test")
                .font(.title2.bold())
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}

@MainActor
final class MacDisplayConnectApplicationDelegate:
    NSObject, NSApplicationDelegate {
    private weak var model: ConnectionModel?
    private var permissionMonitoringTask: Task<Void, Never>?
    private var systemTestTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            guard let configuration = try SystemTestConfiguration.parse(
                arguments: CommandLine.arguments
            ) else {
                return
            }
            startSystemTest(configuration: configuration)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
            writeToStandardError(
                "Mac Display Connect system test: \(message)\n"
            )
            exit(EX_USAGE)
        }
    }

    func start(
        model: ConnectionModel,
        systemTestConfiguration: SystemTestConfiguration?,
        launchError: String?
    ) {
        self.model = model

        if let launchError {
            writeToStandardError(
                "Mac Display Connect system test: \(launchError)\n"
            )
            exit(EX_USAGE)
        }

        if let systemTestConfiguration {
            startSystemTest(configuration: systemTestConfiguration)
            return
        }

        startPermissionMonitoring(model: model)
    }

    private func startPermissionMonitoring(model: ConnectionModel) {
        guard permissionMonitoringTask == nil else {
            return
        }
        permissionMonitoringTask = Task { [weak self, model] in
            await model.monitorPermissions()
            self?.permissionMonitoringTask = nil
        }
    }

    private func startSystemTest(configuration: SystemTestConfiguration) {
        guard systemTestTask == nil else {
            return
        }

        systemTestTask = Task {
            DiagnosticLog.record(
                "System test is waiting for application launch to settle"
            )
            try? await Task.sleep(for: .seconds(1))
            NSApp.windows.first(where: \.isVisible)?
                .makeKeyAndOrderFront(nil)
            NSApp.activate()

            let report = await SystemTestRunner().run(
                configuration: configuration
            )
            let exitCode: Int32

            do {
                try report.write(to: configuration.reportURL)
                DiagnosticLog.record(
                    "System test report written to "
                        + configuration.reportURL.path
                )
                print("System test report: \(configuration.reportURL.path)")
                exitCode = report.passed ? EXIT_SUCCESS : EXIT_FAILURE
            } catch {
                let message = "Could not write the system test report: "
                    + error.localizedDescription
                DiagnosticLog.record(message)
                writeToStandardError("\(message)\n")
                exitCode = EXIT_FAILURE
            }

            exit(exitCode)
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        model?.refreshAccessibilityPermission()
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionMonitoringTask?.cancel()
        permissionMonitoringTask = nil
        systemTestTask?.cancel()
        systemTestTask = nil
    }
}

private func writeToStandardError(_ message: String) {
    try? FileHandle.standardError.write(contentsOf: Data(message.utf8))
}
