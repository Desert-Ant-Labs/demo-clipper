import SwiftUI

struct StepRow: View {
    enum State {
        case done, running, waiting
    }

    let title: String
    /// What is happening to it now: fetching the weights, or getting them
    /// ready. Two different waits, so the row names which one it is in.
    let phase: String?
    /// How far the fetch has got. Absent while preparing, which reports no
    /// fraction, so the bar is only ever shown for something it can measure.
    let progress: Double?
    let state: State

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                marker
                    .frame(width: 18)
                Text(title)
                    .foregroundStyle(state == .waiting ? .secondary : .primary)
                Spacer(minLength: 8)
                if let phase {
                    // Only a running step gets the ellipsis.
                    Text(state == .running ? "\(phase)…" : phase)
                        .foregroundStyle(.secondary)
                }
            }
            if let progress {
                HStack(spacing: 8) {
                    ProgressView(value: progress)
                    Text(progress.formatted(.percent.precision(.fractionLength(0))))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .padding(.leading, 26)
            }
        }
        .font(.callout)
        .opacity(state == .waiting ? 0.55 : 1)
    }

    @ViewBuilder
    private var marker: some View {
        switch state {
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
        case .running: ProgressView().controlSize(.small).scaleEffect(0.7)
        case .waiting: Image(systemName: "circle").foregroundStyle(.tertiary)
        }
    }
}

struct StepPanel<Content: View>: View {
    let width: Double
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content
        }
        .frame(maxWidth: width, alignment: .leading)
        .padding(20)
        .background(.background.secondary, in: .rect(cornerRadius: 10))
    }
}

#Preview {
    StepPanel(width: 320) {
        StepRow(title: "Voz model", phase: "Downloading", progress: 0.42, state: .running)
        StepRow(title: "Clips model", phase: "Preparing", progress: nil, state: .running)
        StepRow(title: "Title model", phase: nil, progress: nil, state: .waiting)
    }
    .padding(40)
}
