import Foundation
import OSLog

/// What to hand someone who is filing an issue: what went wrong, what it was
/// running on, and what the app logged on the way there.
///
/// Asking a person to open Console and reproduce the fault is asking for a
/// report nobody sends. This is one menu item and a paste.
enum Diagnostics {
    /// The most lines worth carrying. A run of a dozen clips logs three lines
    /// each, and everything before that is still the same session.
    static let lines = 200

    /// `problem` is absent when nobody asked because something failed: a run
    /// that hangs reports no error at all, and the log is the only account of
    /// where it stopped.
    static func report(_ problem: Problem? = nil) -> String {
        let head = problem.map { [$0.message, $0.detail] } ?? []
        return (head + versions + log()).joined(separator: "\n")
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
    /// the current process, and a read that comes back empty is worth saying
    /// so: it is different from a run that logged nothing.
    private static func log(lastMinutes minutes: Int = 10) -> [String] {
        guard let store = try? OSLogStore(scope: .currentProcessIdentifier),
              let entries = try? store.getEntries(
                  at: store.position(date: .now.addingTimeInterval(-Double(minutes) * 60))
              )
        else { return ["", "The log could not be read."] }

        let found = entries
            .compactMap { $0 as? OSLogEntryLog }
            .filter { $0.subsystem == Log.subsystem }
            .map { "\($0.date.formatted(date: .omitted, time: .standard)) \($0.composedMessage)" }
            .suffix(lines)
        return found.isEmpty ? ["", "Nothing logged yet."] : [""] + found
    }
}
