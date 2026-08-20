import SwiftUI
import Transcript

// What the clip passes over is folded away and can be opened, so a pick is
// corrected in either direction without leaving the clip.
struct ClipTranscript: View {
    let pick: Pick
    let sentences: [Sentence]
    let play: (Double) -> Void
    let setSelected: @Sendable (Int, Bool) -> Void

    /// Held rather than derived: ticking a sentence inside an open fold would
    /// re-split the runs under the pointer and move everything below it.
    @State private var layout: Layout?
    @State private var openIDs: Set<Int> = []

    /// Runs are positions in one transcript, and opening another video
    /// replaces it before this view settles again.
    private var runs: [Run] {
        guard let layout,
              layout.pickID == pick.id,
              layout.transcriptCount == sentences.count
        else { return partition() }
        return layout.runs
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(runs) { run in
                if run.isSelected {
                    rows(for: run)
                } else {
                    Fold(
                        count: run.ids.count,
                        skipped: span(of: run),
                        isOpen: isOpen(run),
                        toggle: { toggle(run) }
                    )
                    if isOpen(run) { rows(for: run) }
                }
            }
        }
        .frame(maxWidth: 660, alignment: .leading)
        .task(id: pick.id) { settle() }
    }

    @ViewBuilder
    private func rows(for run: Run) -> some View {
        ForEach(run.ids.filter(sentences.indices.contains), id: \.self) { id in
            SentenceRow(
                sentence: sentences[id],
                isSelected: pick.includes(id),
                canDeselect: !pick.isWholeRecording && pick.keptSentenceIDs.count > 1,
                play: { play(offset(of: sentences[id])) },
                setSelected: { setSelected(id, $0) }
            )
        }
    }

    /// Runs of consecutive sentences that are all in the clip or all outside it.
    private func partition() -> [Run] {
        var runs: [Run] = []
        for id in sentences.indices {
            let selected = pick.includes(id)
            if var last = runs.last, last.isSelected == selected {
                last.ids.append(id)
                runs[runs.endIndex - 1] = last
            } else {
                runs.append(Run(ids: [id], isSelected: selected))
            }
        }
        return runs
    }

    private func settle() {
        layout = Layout(pickID: pick.id, transcriptCount: sentences.count, runs: partition())
    }

    private func isOpen(_ run: Run) -> Bool {
        run.ids.contains(where: openIDs.contains)
    }

    private func toggle(_ run: Run) {
        if isOpen(run) {
            openIDs.subtract(run.ids)
            settle()
        } else {
            openIDs.formUnion(run.ids)
        }
    }

    /// Source time the run covers, which opening it puts back.
    private func span(of run: Run) -> Double {
        guard let first = run.ids.first, let last = run.ids.last,
              sentences.indices.contains(first), sentences.indices.contains(last)
        else { return 0 }
        return sentences[last].end - sentences[first].start
    }

    /// Where the sentence lands in the cut, not in the source.
    private func offset(of sentence: Sentence) -> Double {
        // The recording plays unedited, so a sentence sits where it always did.
        pick.isWholeRecording
            ? sentence.start
            : Cutting.offset(of: sentence.start, in: pick.ranges(in: sentences))
    }

    private struct Layout {
        let pickID: Pick.ID
        let transcriptCount: Int
        let runs: [Run]
    }

    private struct Run: Identifiable {
        var ids: [Int]
        var isSelected: Bool
        var id: Int { ids.first ?? 0 }
    }
}

private struct SentenceRow: View {
    let sentence: Sentence
    let isSelected: Bool
    let canDeselect: Bool
    let play: () -> Void
    let setSelected: @Sendable (Bool) -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Toggle(isOn: Binding(get: { isSelected }, set: setSelected)) {}
                .toggleStyle(CheckToggleStyle())
                .disabled(isSelected && !canDeselect)
                .help(isSelected ? "In this clip" : "Add to this clip")

            Button(action: play) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(sentence.start.formattedDuration)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(timestampColor)
                        .frame(width: 38, alignment: .leading)
                    Text(sentence.text)
                        .font(.callout)
                        .lineSpacing(2)
                        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(!isSelected)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(.quaternary)
                .opacity(isHovering ? 1 : 0)
        )
        .onHover { isHovering = $0 }
    }

    private var timestampColor: Color {
        guard isSelected else { return .secondary.opacity(0.5) }
        return isHovering ? .accentColor : .secondary.opacity(0.7)
    }
}

private struct Fold: View {
    let count: Int
    let skipped: Double
    let isOpen: Bool
    let toggle: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 10) {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
                    .frame(width: 10)

                Text("\(count.sentenceCount), \(skipped.formattedDuration)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(isHovering ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))

                Spacer(minLength: 0)
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 8)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .animation(.easeOut(duration: 0.15), value: isOpen)
        .accessibilityLabel("\(count.sentenceCount) skipped, \(skipped.formattedDuration)")
    }
}

private struct CheckToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            Image(systemName: configuration.isOn ? "checkmark.circle.fill" : "circle")
                .font(.body)
                .foregroundStyle(configuration.isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ClipTranscript(
        pick: .sample,
        sentences: Sentence.samples,
        play: { _ in },
        setSelected: { _, _ in }
    )
    .frame(width: 560, height: 400)
}
