import SwiftUI

struct StepRow: View {
    enum State: Equatable {
        case done, running, waiting
        case failed(reason: String)
    }

    let title: String
    /// What is happening to it now: fetching the weights, or getting them
    /// ready. Two different waits, so the row names which one it is in.
    let phase: String?
    /// How far the fetch has got. Absent while preparing, which reports no
    /// fraction, so only a phase that can be counted shows a percentage.
    let progress: Double?
    let state: State
    /// Offered on a failed row. A fetch this size fails on a dropped
    /// connection often enough that starting it again is the whole fix.
    var retry: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                marker
                    .frame(width: 18)
                Text(title)
                    .foregroundStyle(state == .waiting ? .secondary : .primary)
                Spacer(minLength: 8)
                if case .failed = state, let retry {
                    // Borderless rather than `.link`: the same accent text,
                    // but it stays a button, and a link is what VoiceOver
                    // announces for `.link` whatever the action does.
                    Button("Try again", action: retry)
                        .buttonStyle(.borderless)
                } else if let label {
                    Text(label)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            if case .failed(let reason) = state {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 26)
            }
        }
        .font(.callout)
        .opacity(state == .waiting ? 0.55 : 1)
    }

    /// The percentage says a fetch is moving, so the ellipsis is left to a
    /// phase that counts nothing.
    private var label: String? {
        guard let phase else { return nil }
        if let progress {
            return "\(phase) \(progress.formatted(.percent.precision(.fractionLength(0))))"
        }
        return state == .running ? "\(phase)…" : phase
    }

    @ViewBuilder
    private var marker: some View {
        switch state {
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
        case .running: ProgressView().controlSize(.small).scaleEffect(0.7)
        case .waiting: Image(systemName: "circle").foregroundStyle(.tertiary)
        case .failed: Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.secondary)
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
        StepRow(
            title: "Title model",
            phase: nil,
            progress: nil,
            state: .failed(reason: "The Internet connection appears to be offline."),
            retry: {}
        )
    }
    .padding(40)
}
