import DesertAntUI
import Foundation
import SwiftUI

// The Clips license requires an app shipping the models to credit Desert Ant
// Labs.
enum About {
    static let homepage = URL(string: "https://desertant.com")!
    static let windowID = "about"
}

// SwiftUI has no standard About panel, so this is a window of its own.
struct AboutView: View {
    var body: some View {
        VStack(spacing: 10) {
            Text("Clipper")
                .font(.title2.weight(.semibold))
            Text(version)
                .font(.callout)
                .foregroundStyle(.secondary)

            Text(credits)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 6)

            // The credit the model license asks for, in the kit's lockup.
            Link(destination: About.homepage) {
                DA.Attribution()
            }
            .buttonStyle(.plain)
            .padding(.top, 4)

            Text(copyright)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
        }
        .padding(28)
        .frame(width: 380)
    }

    private var credits: String {
        """
        Voz reads the speech, Clips picks the moments, and Title writes \
        the cards. Everything runs on this Mac.
        """
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
