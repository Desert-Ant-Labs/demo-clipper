import AVKit
import DesertAntUI
import SwiftUI

struct ClipDetail: View {
    let pick: Pick

    @Environment(ClipperModel.self) private var model
    @AppStorage("playerHeight") private var storedHeight = 320.0
    @State private var draggedHeight: Double?
    @State private var player = AVPlayer()

    private static let minPlayer = 160.0
    private static let minTranscript = 160.0
    private static let pane = "clipDetailPane"

    /// The live drag wins, so a drag does not route through user defaults on
    /// every frame.
    private var playerHeight: Double { draggedHeight ?? storedHeight }

    var body: some View {
        Group {
            // The audio transport is one row and has no height to trade.
            if model.source?.hasVideo == true {
                GeometryReader { proxy in
                    let ceiling = max(Self.minPlayer, proxy.size.height - Self.minTranscript)
                    VStack(spacing: 0) {
                        playerPane
                            .frame(height: playerHeight.clamped(to: Self.minPlayer...ceiling))
                        ResizeHandle(
                            space: Self.pane,
                            limits: Self.minPlayer...ceiling,
                            height: playerHeight,
                            onDrag: { draggedHeight = $0 },
                            onEnd: {
                                storedHeight = playerHeight.clamped(to: Self.minPlayer...ceiling)
                                draggedHeight = nil
                            }
                        )
                        transcript
                    }
                    .coordinateSpace(.named(Self.pane))
                }
            } else {
                VStack(spacing: 0) {
                    playerPane
                    transcript
                }
            }
        }
        .frame(minWidth: 280)
        .task(id: pick) { await loadPreview() }
    }

    private var playerPane: some View {
        ClipPlayer(
            player: player,
            duration: pick.duration(in: model.sentences),
            aspectRatio: model.source?.aspectRatio
        )
    }

    private var transcript: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Transcript")
                    .font(.caption2.weight(.medium).monospaced())
                    .textCase(.uppercase)
                    .kerning(0.8)
                    .foregroundStyle(DA.Color.textMuted)
                ClipTranscript(
                    pick: pick,
                    sentences: model.sentences,
                    play: play(from:),
                    // A Binding's setter is Sendable, and SwiftUI calls this
                    // one on the main actor, which its type cannot say.
                    setSelected: { sentence, selected in
                        MainActor.assumeIsolated {
                            model.setSentence(sentence, selected: selected, inPick: pick.id)
                        }
                    }
                )
                .textSelection(.enabled)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: .infinity)
    }

    private func play(from seconds: Double) {
        player.seek(
            to: CMTime(seconds: seconds, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        player.play()
    }

    private func loadPreview() async {
        player.pause()
        guard let asset = model.asset else { return }
        // The recording plays as itself. Composing it from its own sentences
        // would splice out every pause and trim the head and the tail.
        guard !pick.isWholeRecording else {
            player.replaceCurrentItem(with: AVPlayerItem(asset: asset))
            return
        }
        guard let composition = try? await Cutting.composition(
            of: asset, keeping: pick.ranges(in: model.sentences)
        ) else { return }
        player.replaceCurrentItem(with: AVPlayerItem(asset: composition))
    }
}

// A nested split view inside the detail column of a NavigationSplitView that
// also has an inspector puts AppKit's constraint solver into a loop it aborts
// on. This is the divider without the second NSSplitViewController.
private struct ResizeHandle: View {
    let space: String
    let limits: ClosedRange<Double>
    let height: Double
    let onDrag: (Double) -> Void
    let onEnd: () -> Void

    @State private var heightAtStart: Double?

    var body: some View {
        Divider()
            .frame(height: 1)
            .padding(.vertical, 4)
            .contentShape(.rect)
            .pointerStyle(.rowResize)
            .gesture(
                // Measured against the pane: in the handle's own space the
                // origin moves with the drag and the divider stutters.
                DragGesture(minimumDistance: 1, coordinateSpace: .named(space))
                    .onChanged { drag in
                        let start = heightAtStart ?? height
                        heightAtStart = start
                        onDrag((start + drag.translation.height).clamped(to: limits))
                    }
                    .onEnded { _ in
                        heightAtStart = nil
                        onEnd()
                    }
            )
            .accessibilityLabel("Resize the player")
    }
}

extension Double {
    func clamped(to limits: ClosedRange<Double>) -> Double {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}
