import AppKit
import DesertAntUI
import Foundation
import SwiftUI

// The Clips license requires an app shipping the models to credit Desert Ant
// Labs.
enum About {
    static let homepage = URL(string: "https://desertant.com")!
    static let windowID = "about"

    /// The line under the drop zone, reused in the About window so the two
    /// read the same. The splash renders the model names as a link; this is
    /// the plain form.
    static let footer =
        "Powered by Voz, Clips and Title, on-device models from Desert Ant Labs. "
        + "Runs entirely on this Mac. Nothing is uploaded."
}

// SwiftUI has no standard About panel, so this is a window of its own.
struct AboutView: View {
    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 76, height: 76)

            Text("Clipper")
                .font(.title2.weight(.semibold))
                .padding(.top, 10)
            Text(version)
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 2)

            Text(About.footer)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 16)

            // The credit the model license asks for, in the kit's lockup.
            Link(destination: About.homepage) {
                DA.Attribution()
            }
            .buttonStyle(.plain)
            .padding(.top, 18)

            Text(copyright)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 18)
        }
        .padding(.horizontal, 36)
        .padding(.vertical, 32)
        .frame(width: 360)
    }

    private var version: String {
        let short = string("CFBundleShortVersionString")
        let build = string("CFBundleVersion")
        return build.isEmpty ? "Version \(short)" : "Version \(short) (\(build))"
    }

    private var copyright: String {
        string("NSHumanReadableCopyright")
    }

    private func string(_ key: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? ""
    }
}

#Preview {
    AboutView()
}
