import AVFoundation
import Foundation

/// Disk space, checked before a run spends minutes writing audio and clips.
enum Storage {
    /// Headroom to leave behind, on top of whatever is about to be written.
    ///
    /// A clip is tens of megabytes and the audio pulled out of an hour-long
    /// recording is a few hundred, so this is a floor to keep the volume off
    /// the edge rather than a figure any one write needs.
    static let headroom: Int64 = 250_000_000

    /// Not the same as free space: the system holds some back and purges
    /// caches for important use.
    static func available(at url: URL = .temporaryDirectory) -> Int64? {
        try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage
    }

    /// Whether `bytes` can be written with the headroom left over. A volume
    /// that will not say counts as room: refusing to work because a figure
    /// could not be read is worse than trying and reporting a real failure.
    static func hasRoom(for bytes: Int64 = 0, at url: URL = .temporaryDirectory) -> Bool {
        guard let available = available(at: url) else { return true }
        return available >= headroom + bytes
    }

    /// AVFoundation, Cocoa, and POSIX each report a full disk in their own
    /// domain, and wrap one another.
    static func isFull(_ error: any Error) -> Bool {
        let error = error as NSError
        switch error.domain {
        case NSCocoaErrorDomain:
            return error.code == NSFileWriteOutOfSpaceError
        case NSPOSIXErrorDomain:
            return error.code == Int(ENOSPC)
        case AVFoundationErrorDomain:
            return error.code == AVError.Code.diskFull.rawValue
        default:
            return error.underlyingErrors.contains(where: isFull)
        }
    }

    static func freeSpaceLabel(at url: URL = .temporaryDirectory) -> String? {
        guard let available = available(at: url) else { return nil }
        return label(available)
    }

    /// A size as a reader would say it.
    static func label(_ bytes: Int64) -> String {
        ByteCountFormatStyle(style: .file).format(max(0, bytes))
    }

    /// What a write of `bytes` actually asks the volume for, headroom included.
    /// This is the figure to quote when there is not enough.
    static func demand(_ bytes: Int64) -> String {
        label(max(0, bytes) + headroom)
    }
}
