import AppKit
import AVKit
import SwiftUI

struct ClipPlayer: View {
    let player: AVPlayer
    /// The length of the cut, in seconds.
    let duration: Double
    let aspectRatio: CGFloat?

    var body: some View {
        if let aspectRatio {
            // No background of its own. The sidebar and the inspector are glass
            // over the detail column, so anything painted across its full width
            // shows through them as a band that stops where the player does.
            VideoSurface(player: player)
                .aspectRatio(aspectRatio, contentMode: .fit)
                .clipShape(.rect(cornerRadius: 10))
                .shadow(color: .black.opacity(0.22), radius: 10, y: 3)
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            AudioTransport(player: player, duration: duration)
        }
    }
}

// SwiftUI's VideoPlayer aborts on macOS 26: "failed to demangle superclass of
// VideoPlayerView". AVPlayerView also takes the videoGravity set below.
private struct VideoSurface: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        // The frame is already the video's shape, so filling it crops a
        // fraction of a point rather than leaving a hairline of the view's own
        // black where the fitted picture rounds short of its bounds.
        view.videoGravity = .resizeAspectFill
        view.player = player
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player { view.player = player }
    }
}

// AVPlayerView renders a black rectangle for audio.
private struct AudioTransport: View {
    let player: AVPlayer
    let duration: Double

    @State private var elapsed = CMTime.zero
    @State private var isPlaying = false
    @State private var isScrubbing = false
    @State private var ticker: Any?

    private var total: Double { max(duration, 0.1) }

    var body: some View {
        HStack(spacing: 16) {
            Button(action: playPause) {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.tint)
            }
            .buttonStyle(.plain)
            .help(isPlaying ? "Pause" : "Play")

            Text(elapsed.seconds.formattedDuration)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Slider(
                value: Binding(
                    get: { min(elapsed.seconds, total) },
                    set: { elapsed = CMTime(seconds: $0, preferredTimescale: 600) }
                ),
                in: 0...total,
                onEditingChanged: scrub
            )
            .controlSize(.small)

            Text(duration.formattedDuration)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .task { follow() }
        .onDisappear(perform: stopFollowing)
    }

    private func playPause() {
        isPlaying ? player.pause() : player.play()
    }

    private func scrub(_ editing: Bool) {
        isScrubbing = editing
        guard !editing else { return }
        player.seek(to: elapsed, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func follow() {
        stopFollowing()
        ticker = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 10),
            queue: .main
        ) { time in
            // The observer was asked for the main queue, which the compiler
            // cannot see from the closure's type.
            MainActor.assumeIsolated {
                isPlaying = player.timeControlStatus == .playing
                guard !isScrubbing else { return }
                elapsed = time
            }
        }
    }

    private func stopFollowing() {
        if let ticker { player.removeTimeObserver(ticker) }
        ticker = nil
    }
}
