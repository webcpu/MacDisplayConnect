import ApplicationServices
import MacDisplayConnectCore
import Testing
@testable import MacDisplayConnect

@Suite("Control Center accessibility sources")
@MainActor
struct ControlCenterAccessibilityTests {
    @Test("macOS 26 keeps the original Control Center source")
    func controlCenterWithoutMenuBarAgent() throws {
        let applications = try ControlCenter.controlCenterApplications {
            $0 == "com.apple.controlcenter" ? 1_000_001 : nil
        }

        #expect(processIdentifiers(of: applications) == [1_000_001])
    }

    @Test("macOS 27 includes the separate menu bar accessibility source")
    func includesMenuBarAgent() throws {
        let applications = try ControlCenter.controlCenterApplications {
            switch $0 {
            case "com.apple.controlcenter": 1_000_001
            case "com.apple.MenuBarAgent": 1_000_002
            default: nil
            }
        }

        #expect(
            processIdentifiers(of: applications) == [1_000_001, 1_000_002]
        )
    }

    @Test("the menu bar agent does not replace a missing Control Center")
    func requiresControlCenter() {
        #expect(throws: MacDisplayConnectError.controlCenterNotRunning) {
            try ControlCenter.controlCenterApplications {
                $0 == "com.apple.MenuBarAgent" ? 1_000_002 : nil
            }
        }
    }

    @Test("a single accessibility tree retains its existing order")
    func preservesOriginalTree() {
        let tree = [1_000_001, 1_000_002, 1_000_002].map {
            AXUIElementCreateApplication(pid_t($0))
        }

        let elements = ControlCenter.mergedAccessibilityElements([tree])

        #expect(
            processIdentifiers(of: elements) == [1_000_001, 1_000_002, 1_000_002]
        )
    }

    @Test("menu bar elements remain reachable when the panel tree is empty")
    func includesMenuBarWithEmptyPanel() {
        let menuBar = AXUIElementCreateApplication(1_000_002)

        let elements = ControlCenter.mergedAccessibilityElements([
            [], [menuBar],
        ])

        #expect(processIdentifiers(of: elements) == [1_000_002])
    }

    @Test("shared accessibility elements keep their first source's index")
    func mergesSplitTreesWithoutDuplicateElements() {
        let panel = AXUIElementCreateApplication(1_000_001)
        let shared = AXUIElementCreateApplication(1_000_002)
        let menuBar = AXUIElementCreateApplication(1_000_003)
        let secondReference = AXUIElementCreateApplication(1_000_002)

        let elements = ControlCenter.mergedAccessibilityElements([
            [panel, shared],
            [menuBar, secondReference],
        ])

        #expect(
            processIdentifiers(of: elements) == [1_000_001, 1_000_002, 1_000_003]
        )
    }

    private func processIdentifiers(
        of applications: [AXUIElement]
    ) -> [pid_t] {
        applications.map { application in
            var identifier: pid_t = 0
            #expect(AXUIElementGetPid(application, &identifier) == .success)
            return identifier
        }
    }
}
