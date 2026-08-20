import AVFoundation
import Foundation

/// Disk space, checked before a run spends minutes writing audio and clips.
enum Storage {
    static let wanted: Int64 = 2 * 1_000_000_000

    /// Not the same as free space: the system holds some back and purges
    /// caches for important use.
    static func available(at url: URL = .temporaryDirectory) -> Int64? {
        try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage
    }

    static func hasRoom(_ bytes: Int64 = wanted, at url: URL = .temporaryDirectory) -> Bool {
        guard let available = available(at: url) else { return true }
        return available >= bytes
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
        return ByteCountFormatStyle(style: .file).format(available)
    }
}
