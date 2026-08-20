import SwiftUI
import Transcript

struct Inspector: View {
    let pick: Pick?
    let sentences: [Sentence]
    let source: SourceInfo?
    let reading: Reading?
    let performance: ClipperModel.Performance?
    let titleProblem: String?

    @State private var showsClip = true
    @State private var showsFile = false
    @State private var showsPerformance = false

    var body: some View {
        // Filling in stages as source, transcript, then clips arrive is
        // three reflows.
        if let pick {
            Form {
                Section(isExpanded: $showsClip) {
                    ClipRows(pick: pick, sentences: sentences, titleProblem: titleProblem)
                } header: {
                    header("Clip", $showsClip)
                }
                if let performance {
                    Section(isExpanded: $showsPerformance) {
                        PerformanceRows(performance: performance)
                    } header: {
                        header("Performance", $showsPerformance)
                    }
                }
                if let source {
                    Section(isExpanded: $showsFile) {
                        FileRows(
                            source: source,
                            sentenceCount: sentences.count,
                            reading: reading
                        )
                    } header: {
                        header("File", $showsFile)
                    }
                }
            }
            .formStyle(.grouped)
            .controlSize(.small)
        } else {
            Text("No clip selected")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private extension Inspector {
    /// The whole title toggles the section, which is what a disclosure header
    /// does everywhere else. On its own it only answers to the chevron.
    func header(_ title: String, _ isExpanded: Binding<Bool>) -> some View {
        Text(title)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
            .onTapGesture { isExpanded.wrappedValue.toggle() }
    }
}

private struct ClipRows: View {
    let pick: Pick
    let sentences: [Sentence]
    let titleProblem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(pick.displayTitle)
                .font(.headline)
            Text(description)
                .font(.callout)
                .foregroundStyle(pick.card == nil ? .tertiary : .secondary)
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)

        LabeledContent("Length", value: pick.duration(in: sentences).formattedDuration)
        LabeledContent("Sentences", value: selectedSentences)
        LabeledContent("Segments", value: "\(pick.ranges(in: sentences).count)")
        LabeledContent("Rank", value: "\(pick.clip.id + 1)")
        // The scorer is trained to rank within one video, so the percentile is
        // the number that means anything and the raw score only means something
        // beside the other clips from this same transcript.
        LabeledContent("Percentile", value: String(format: "%.2f", pick.clip.percentile))
        LabeledContent("Score", value: String(format: "%.3f", pick.clip.score))
    }

    /// The card's line, or why there is no card to show one from.
    private var description: String {
        pick.card?.description ?? titleProblem ?? "No title written for this clip."
    }

    /// Says so when the pick has been edited, since that is the interesting case.
    private var selectedSentences: String {
        let kept = pick.keptSentenceIDs.count
        let suggested = pick.clip.sentenceIDs.count
        guard kept != suggested else { return "\(kept)" }
        return "\(kept), model picked \(suggested)"
    }
}

private struct FileRows: View {
    let source: SourceInfo
    let sentenceCount: Int
    let reading: Reading?

    var body: some View {
        LabeledContent("Name") {
            Text(source.name)
                .truncationMode(.middle)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }

        LabeledContent("Length", value: source.duration.seconds.formattedDuration)
        if let resolution = source.resolutionLabel {
            LabeledContent("Resolution", value: resolution)
        }
        if let rate = source.frameRateLabel {
            LabeledContent("Frame rate", value: rate)
        }
        if let codec = source.videoCodec {
            LabeledContent("Video", value: codec)
        }
        if let audio = source.audioLabel {
            LabeledContent("Audio", value: audio)
        }
        if let size = source.fileSizeLabel {
            LabeledContent("Size", value: size)
        }

        if sentenceCount > 0 {
            LabeledContent("Transcript", value: sentenceCount.sentenceCount)
            if reading != nil {
                LabeledContent("Model", value: "Voz")
            }
        }
    }
}

#Preview("Clip and file") {
    Inspector(
        pick: .sample,
        sentences: Sentence.samples,
        source: .sample,
        reading: .sample,
        performance: .sample,
        titleProblem: nil
    )
    .frame(width: 320, height: 520)
}

#Preview("Nothing open") {
    Inspector(
        pick: nil,
        sentences: [],
        source: nil,
        reading: nil,
        performance: nil,
        titleProblem: nil
    )
        .frame(width: 320, height: 240)
}
