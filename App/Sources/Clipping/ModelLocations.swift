import Clips
import Foundation
import Voz

/// Where the models are read from.
///
/// Both are read from disk rather than fetched, so a first run is not a
/// download. `Titles` has no remote at all: it takes a directory and nothing
/// else.
///
/// Looked for in two places, first hit wins:
///
/// 1. the environment: `CLIPPER_CLIPS_MODEL`, `CLIPPER_TITLE_MODEL`,
///    `CLIPPER_VOZ_MODEL`
/// 2. ``root``, where `mise run models` puts them
///
/// `nil` for ``clips`` or ``voz`` hands the choice to the SDK's managed
/// cache, which downloads. `nil` for ``title`` means the clips come back
/// unnamed.
struct ModelLocations: Sendable, Equatable {
    /// A directory holding the files in ``clipsFiles``. Those names are the
    /// SDK's, and a directory missing any of them is not adopted.
    var clips: URL?

    /// An MLX model folder: `config.json`, `model.safetensors`, `tokenizer.json`.
    var title: URL?

    /// A directory holding the files in ``vozFiles``.
    var voz: URL?

    init(clips: URL? = nil, title: URL? = nil, voz: URL? = nil) {
        self.clips = clips
        self.title = title
        self.voz = voz
    }

    /// Where `mise run models` writes them. Not sandboxed, so the app and the
    /// CLI resolve this to the same path.
    static var root: URL {
        URL.applicationSupportDirectory.appending(path: "Clipper/Models")
    }

    /// What this machine has.
    static var resolved: ModelLocations {
        ModelLocations(
            clips: found("CLIPPER_CLIPS_MODEL", "clips"),
            title: found("CLIPPER_TITLE_MODEL", "title"),
            voz: found("CLIPPER_VOZ_MODEL", "voz")
        )
    }

    /// The files the Clips SDK insists on, asked of the SDK rather than copied
    /// from it, since a copy goes stale silently: a directory missing a declared
    /// file is not adopted and the app falls back without saying so.
    ///
    /// The trailing `/` marks a directory in the SDK's manifest (`clips.mlmodelc`
    /// is a compiled bundle, not a file); `FileManager` does not need it.
    static let clipsFiles: [String] =
        (ClipModel.files[.apple] ?? []).map { $0.hasSuffix("/") ? String($0.dropLast()) : $0 }

    /// The files an MLX model folder has to have for the writer to load.
    static let titleFiles = ["config.json", "tokenizer.json"]

    /// The files the Voz SDK insists on, asked of the SDK for the same
    /// reason as ``clipsFiles``.
    static let vozFiles: [String] =
        (VozModel.files[.apple] ?? []).map { $0.hasSuffix("/") ? String($0.dropLast()) : $0 }

    /// What is missing from `directory`, or nothing when it is complete.
    static func missing(_ names: [String], in directory: URL) -> [String] {
        // Unencoded: the default path lives under "Application Support", and a
        // percent-encoded space is a path no file is ever at.
        names.filter {
            !FileManager.default.fileExists(
                atPath: directory.appending(path: $0).path(percentEncoded: false))
        }
    }

    /// A directory only counts when it is there and complete.
    private static func found(_ variable: String, _ folder: String) -> URL? {
        let candidates = [
            ProcessInfo.processInfo.environment[variable].map { URL(filePath: $0) },
            root.appending(path: folder),
        ].compactMap { $0 }

        let wanted = switch folder {
        case "clips": clipsFiles
        case "voz": vozFiles
        default: titleFiles
        }
        // Resolved: MLX enumerates the directory for its weights, and
        // enumerating a symlink yields nothing, so the model builds from
        // `config.json` and fails on an arbitrary missing tensor.
        return candidates.first { missing(wanted, in: $0).isEmpty }?.resolvingSymlinksInPath()
    }
}
