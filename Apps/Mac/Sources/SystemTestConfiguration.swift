import Foundation

struct SystemTestConfiguration: Equatable, Sendable {
    let cycleCount: Int
    let visionProName: String?
    let reportURL: URL

    static func parse(arguments: [String]) throws -> Self? {
        let cycleValues = try values(
            for: "--system-test-cycles",
            in: arguments
        )
        let visionProValues = try values(
            for: "--vision-pro-name",
            in: arguments
        )
        let reportValues = try values(
            for: "--system-test-report",
            in: arguments
        )

        guard !cycleValues.isEmpty else {
            guard visionProValues.isEmpty, reportValues.isEmpty else {
                throw SystemTestConfigurationError.invalidArguments(
                    "--vision-pro-name and --system-test-report require "
                        + "--system-test-cycles."
                )
            }
            return nil
        }
        guard cycleValues.count == 1,
              let cycleCount = Int(cycleValues[0]),
              cycleCount > 0
        else {
            throw SystemTestConfigurationError.invalidArguments(
                "--system-test-cycles requires one positive integer."
            )
        }
        guard visionProValues.count <= 1,
              visionProValues.first.map({ !$0.isEmpty }) ?? true
        else {
            throw SystemTestConfigurationError.invalidArguments(
                "--vision-pro-name accepts one nonempty value."
            )
        }
        guard reportValues.count <= 1,
              reportValues.first.map({ !$0.isEmpty }) ?? true
        else {
            throw SystemTestConfigurationError.invalidArguments(
                "--system-test-report accepts one nonempty path."
            )
        }

        return Self(
            cycleCount: cycleCount,
            visionProName: visionProValues.first,
            reportURL: reportValues.first
                .map { URL(fileURLWithPath: $0) }
                ?? defaultReportURL()
        )
    }

    private static func values(
        for flag: String,
        in arguments: [String]
    ) throws -> [String] {
        try arguments.indices.compactMap { index in
            guard arguments[index] == flag else {
                return nil
            }

            let valueIndex = arguments.index(after: index)
            guard arguments.indices.contains(valueIndex),
                  !arguments[valueIndex].hasPrefix("--")
            else {
                throw SystemTestConfigurationError.invalidArguments(
                    "\(flag) requires a value."
                )
            }
            return arguments[valueIndex]
        }
    }

    private static func defaultReportURL() -> URL {
        let runID = UUID().uuidString.lowercased()
        return FileManager.default
            .urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appending(path: "Logs", directoryHint: .isDirectory)
            .appending(path: "Mac Display Connect", directoryHint: .isDirectory)
            .appending(path: "System Tests", directoryHint: .isDirectory)
            .appending(path: runID, directoryHint: .isDirectory)
            .appending(path: "report.json")
    }
}

enum SystemTestConfigurationError: LocalizedError {
    case invalidArguments(String)

    var errorDescription: String? {
        switch self {
        case let .invalidArguments(message):
            message
        }
    }
}
