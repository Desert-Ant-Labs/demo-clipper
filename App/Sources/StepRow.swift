import SwiftUI

struct StepRow: View {
    enum State {
        case done, running, waiting
    }

    let title: String
    let detail: String?
    let state: State

    var body: some View {
        HStack(spacing: 8) {
            marker
                .frame(width: 18)
            // Only the running step gets the ellipsis.
            Text(state == .running ? "\(title)…" : title)
                .foregroundStyle(state == .waiting ? .secondary : .primary)
            Spacer(minLength: 8)
            if let detail {
                Text(detail)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
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
    StepPanel(width: 300) {
        StepRow(title: "Loading Voz", detail: "Downloading 42%", state: .running)
        StepRow(title: "Loading Clips", detail: nil, state: .waiting)
    }
    .padding(40)
}
