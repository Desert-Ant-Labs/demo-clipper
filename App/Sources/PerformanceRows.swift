import SwiftUI

/// What each model cost on this video: how many times the recording's own
/// length it ran at, and the wall clock behind that. The multiple is what makes
/// the models comparable to each other and across videos.
struct PerformanceRows: View {
    let performance: ClipperModel.Performance

    var body: some View {
        // First because it is the first thing that happens to the file, and
        // because End to end counts it.
        row("Audio extraction", performance.timings.extractingSeconds)
        row("Voz", performance.timings.readingSeconds)
        if let selection = performance.selectionSeconds {
            row("Clips", selection)
        }
        if let cards = performance.cardTotal {
            row("Title", cards)
        }
        if let total = performance.total {
            row("End to end", total)
        }
    }

    private func row(_ label: String, _ value: Double) -> some View {
        LabeledContent(label) {
            HStack(spacing: 8) {
                Text(value.formattedSeconds)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                if let multiple = multiple(value) {
                    Text(multiple)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
            }
        }
    }

    private func multiple(_ value: Double) -> String? {
        let media = performance.timings.mediaSeconds
        guard value > 0, media > 0 else { return nil }
        return "\(Int((media / value).rounded()))x"
    }
}
