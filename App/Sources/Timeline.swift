import SwiftUI
import Transcript

/// Where the clips fall in the recording, laid out like an editor's timeline:
/// a ruler, the clips, and the recording they were cut from.
///
/// One second is always the same width, so a clip looks the same length in
/// every video and a long recording scrolls rather than being squeezed to fit.
struct Timeline: View {
    let picks: [Pick]
    let sentences: [Sentence]
    let duration: Double
    @Binding var selection: Pick.ID?

    var body: some View {
        let lanes = lanes
        ScrollView(.horizontal) {
            VStack(alignment: .leading, spacing: Self.spacing) {
                ruler
                ForEach(lanes.indices, id: \.self) { row in
                    ZStack(alignment: .leading) {
                        ForEach(lanes[row]) { clip in
                            block(clip)
                        }
                    }
                }
                RoundedRectangle(cornerRadius: Self.recordingHeight / 2)
                    .fill(.quaternary)
                    .frame(height: Self.recordingHeight)
            }
            .frame(width: points(duration), alignment: .leading)
            .padding(.horizontal, Self.inset)
            .padding(.top, Self.topInset)
            .padding(.bottom, Self.spacing + Self.scrollerHeight)
        }
        // Padding inside a scroll view moves its content, not its scroller,
        // which would otherwise sit on the window's own bottom edge.
        .contentMargins(.bottom, Self.spacing, for: .scrollIndicators)
        .frame(height: height(rows: lanes.count))
        .background(.quinary)
    }

    // MARK: - Parts

    /// Each mark and its time sit on one line, so the ruler costs a single row.
    private var ruler: some View {
        ZStack(alignment: .leading) {
            ForEach(ticks, id: \.self) { seconds in
                HStack(spacing: 4) {
                    Rectangle()
                        .fill(.quaternary)
                        .frame(width: 1, height: Self.rulerHeight)
                    Text(seconds.formattedDuration)
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .offset(x: points(seconds))
            }
        }
        .frame(height: Self.rulerHeight, alignment: .leading)
    }

    /// The block sizes its own title, so a clip too short for its whole name
    /// truncates to what fits rather than spilling over the clip beside it.
    private func block(_ clip: Clipped) -> some View {
        let isSelected = clip.id == selection
        return Button {
            selection = clip.id
        } label: {
            Text(clip.title)
                .font(.caption2)
                .lineLimit(1)
                .foregroundStyle(isSelected ? .white : .primary)
                .padding(.horizontal, 6)
                .frame(
                    width: max(Self.minimumWidth, points(clip.duration)),
                    height: Self.clipHeight,
                    alignment: .leading
                )
                .background(
                    isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.tint.opacity(0.22)),
                    in: .rect(cornerRadius: Self.cornerRadius)
                )
        }
        .buttonStyle(.plain)
        .offset(x: points(clip.start))
        .help(clip.title)
    }

    // MARK: - Layout

    private func points(_ seconds: Double) -> Double {
        seconds * Self.pointsPerSecond
    }

    /// Clips packed into as few rows as they fit in, so two that overlap are
    /// both visible rather than one hiding the other.
    ///
    /// The model returns a non-overlapping set, so this is one row in practice.
    /// It costs a sort and a scan to not depend on that.
    private var lanes: [[Clipped]] {
        var lanes: [[Clipped]] = []
        for clip in clips.sorted(by: { $0.start < $1.start }) {
            if let row = lanes.firstIndex(where: { ($0.last?.end ?? 0) <= clip.start }) {
                lanes[row].append(clip)
            } else {
                lanes.append([clip])
            }
        }
        return lanes
    }

    private var clips: [Clipped] {
        picks.compactMap { pick in
            let ranges = pick.ranges(in: sentences)
            guard let start = ranges.first?.start, let end = ranges.last?.end else { return nil }
            return Clipped(id: pick.id, title: pick.displayTitle, start: start, end: end)
        }
    }

    /// Round marks, spaced far enough apart to read.
    private var ticks: [Double] {
        guard duration > 0 else { return [] }
        let steps = [1.0, 5, 10, 15, 30, 60, 120, 300, 600, 900, 1800, 3600]
        let step = steps.first { points($0) >= Self.tickSpacing } ?? duration
        return Array(stride(from: 0, to: duration, by: step))
    }

    /// Tall enough for what it draws: the ruler, a row per lane, and the
    /// recording bar, with a gap between each, the insets at the head and the
    /// foot, and room for the scroller to sit clear of the recording.
    private func height(rows: Int) -> Double {
        let rows = Double(max(1, rows))
        let bars = Self.rulerHeight + rows * Self.clipHeight + Self.recordingHeight
        let gaps = (rows + 2) * Self.spacing
        return bars + gaps + Self.topInset + Self.scrollerHeight
    }

    /// One clip's place on the timeline, in seconds from the start.
    private struct Clipped: Identifiable {
        let id: Pick.ID
        let title: String
        let start: Double
        let end: Double

        var duration: Double { end - start }
    }

    /// Wide enough that a clip of a few seconds is still a block you can hit,
    /// and that most titles have room to read.
    private static let pointsPerSecond = 6.0
    private static let rulerHeight = 11.0
    private static let clipHeight = 22.0
    private static let cornerRadius = 6.0

    /// An overlay scroller draws inside the content, so the foot is left free
    /// for it rather than letting it cross the recording.
    private static let scrollerHeight = 12.0
    private static let spacing = 7.0

    /// The ruler runs up against the divider on the plain row gap, so the head
    /// is given more room than the rows are.
    private static let topInset = 16.0
    private static let recordingHeight = 8.0
    private static let minimumWidth = 6.0
    private static let tickSpacing = 70.0
    private static let inset = 20.0
}

#Preview {
    @Previewable @State var selection: Pick.ID? = Pick.samples.first?.id
    Timeline(
        picks: Pick.samples,
        sentences: Sentence.samples,
        duration: 30,
        selection: $selection
    )
    .frame(width: 620)
}
