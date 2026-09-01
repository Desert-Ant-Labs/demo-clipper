import Foundation
import OSLog

extension Logger {
    /// The export's own log. A run that goes wrong on someone else's machine
    /// is readable with:
    ///
    ///     log show --predicate 'subsystem == "com.desertant.clipper"' --last 10m
    static let export = Logger(subsystem: Diagnostics.subsystem, category: "export")
}

/// What to hand someone who is filing an issue: what went wrong, what it was
/// running on, and what the app logged on the way there.
///
/// Asking a person to open Console and reproduce the fault is asking for a
/// report nobody sends. This is one button and a paste.
enum Diagnostics {
    /// The app's own identifier, so the log's subsystem cannot drift from the
    /// bundle it came out of.
    static let subsystem = Bundle.main.bundleIdentifier ?? "com.desertant.clipper"

    static func report(_ problem: Problem) -> String {
        ([problem.message, problem.detail] + versions + log())
            .joined(separator: "\n")
    }

    /// What it was running on. The OS build and the machine are here because a
    /// fault that only one release or one chip shows is otherwise a guess.
    static var versions: [String] {
        let bundle = Bundle.main
        let short = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let release = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        return [
            "Clipper \(short) (\(build))",
            "macOS \(release) (\(sysctl("kern.osversion") ?? "?"))",
            "\(sysctl("hw.model") ?? "?") \(sysctl("hw.machine") ?? "?"), "
                + "\(ProcessInfo.processInfo.processorCount) cores, "
                + memory,
        ]
    }

    private static var memory: String {
        ByteCountFormatStyle(style: .memory)
            .format(Int64(ProcessInfo.processInfo.physicalMemory))
    }

    /// One of the kernel's own strings, for the details Foundation does not
    /// carry: the OS build and which Mac this is.
    private static func sysctl(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var value = [UInt8](repeating: 0, count: size)
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return String(decoding: value.prefix(while: { $0 != 0 }), as: UTF8.self)
    }

    /// This process's own entries. The store is read without permission for
    /// the current process, and an empty read is not worth reporting: the rest
    /// of the report still says what happened.
    private static func log(lastMinutes minutes: Int = 10) -> [String] {
        guard let store = try? OSLogStore(scope: .currentProcessIdentifier),
              let entries = try? store.getEntries(
                  at: store.position(date: .now.addingTimeInterval(-Double(minutes) * 60))
              )
        else { return [] }

        let lines = entries
            .compactMap { $0 as? OSLogEntryLog }
            .filter { $0.subsystem == subsystem }
            .map { "\($0.date.formatted(date: .omitted, time: .standard)) \($0.composedMessage)" }
        return lines.isEmpty ? [] : [""] + lines
    }
}
