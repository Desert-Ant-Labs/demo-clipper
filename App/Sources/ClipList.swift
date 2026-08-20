import SwiftUI
import Transcript

struct ClipList: View {
    let picks: [Pick]
    let sentences: [Sentence]
    let source: SourceInfo?
    @Binding var selection: Pick.ID?

    var body: some View {
        List(selection: $selection) {
            // The recording leads the clips cut from it, so the whole
            // transcript has somewhere to be read and exported from.
            if let source, !sentences.isEmpty {
                RecordingRow(source: source, sentenceCount: sentences.count)
                    .tag(Pick.wholeRecordingID)
            }
            ForEach(picks) { pick in
                ClipRow(pick: pick, sentences: sentences)
                    .tag(pick.id)
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 220, ideal: 300, max: 540)
        .overlay {
            if picks.isEmpty { EmptyClipList() }
        }
    }
}

/// A row knows everything about a clip except its title for the first seconds,
/// so the title fades in over a placeholder.
private struct ClipRow: View {
    let pick: Pick
    let sentences: [Sentence]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(pick.card?.title ?? CardPlaceholder.title)
                .font(.callout.weight(.medium))
                .lineLimit(2)
                .foregroundStyle(pick.card == nil ? .secondary : .primary)
                .redacted(reason: pick.card == nil ? .placeholder : [])
            HStack(spacing: 6) {
                Text(pick.duration(in: sentences).formattedDuration)
                    .monospacedDigit()
                    .layoutPriority(1)
                Text(pick.keptSentenceIDs.count.sentenceCount)
                if pick.card == nil {
                    Spacer(minLength: 0)
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.6)
                        .frame(width: 12, height: 12)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(.vertical, 4)
        .animation(.easeOut(duration: 0.25), value: pick.card)
    }
}

/// The recording itself. Called what it is rather than what it is named: the
/// file name is in the toolbar and the inspector, and nothing writes it a
/// title the way the clips get one.
private struct RecordingRow: View {
    let source: SourceInfo
    let sentenceCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Original")
                .font(.callout.weight(.medium))
            HStack(spacing: 6) {
                Text(source.duration.seconds.formattedDuration)
                    .monospacedDigit()
                Text(sentenceCount.sentenceCount)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(.vertical, 4)
    }
}

// ContentUnavailableView is sized for a detail pane and swamps a sidebar.
private struct EmptyClipList: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "film.stack")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.tertiary)
            Text("No clips yet")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 16)
    }
}

#Preview("Clips") {
    @Previewable @State var selection: Pick.ID? = Pick.samples.first?.id
    ClipList(
        picks: Pick.samples,
        sentences: Sentence.samples,
        source: .sample,
        selection: $selection
    )
        .frame(width: 260, height: 360)
}

#Preview("Empty") {
    @Previewable @State var selection: Pick.ID?
    ClipList(picks: [], sentences: [], source: nil, selection: $selection)
        .frame(width: 260, height: 360)
}
