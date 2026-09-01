import SwiftUI

struct DropZone: View {
    let openVideo: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "film.stack")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.tertiary)
            VStack(spacing: 8) {
                Text("Drop a video or recording here")
                    .font(.title3.weight(.medium))
                Text("Clipper transcribes it, then picks the clips worth posting.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Button(action: openVideo) {
                HStack(spacing: 8) {
                    Text("Open Video")
                    Image(systemName: "return")
                        .imageScale(.small)
                        .opacity(0.6)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            Spacer()

            VStack(spacing: 6) {
                // The key is built as a String first. Interpolating into the
                // literal makes the URL a format placeholder rather than part
                // of the markdown, and the link comes out malformed.
                Text(LocalizedStringKey(
                    "Powered by [Voz, Clips and Title](\(About.homepage.absoluteString)), "
                        + "on-device models from Desert Ant Labs."))
                Text("Runs entirely on this Mac. Nothing is uploaded.")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .tint(.primary)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
