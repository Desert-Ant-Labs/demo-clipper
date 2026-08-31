import SwiftUI

extension View {
    /// Shows the answer to a check, and offers the release page when there is
    /// one to open.
    func updateAlert(_ updates: UpdateCheck) -> some View {
        modifier(UpdateAlert(updates: updates))
    }
}

private struct UpdateAlert: ViewModifier {
    @Bindable var updates: UpdateCheck

    func body(content: Content) -> some View {
        content.alert(
            title,
            isPresented: Binding(
                get: { updates.answer != nil },
                set: { if !$0 { updates.answer = nil } }
            ),
            presenting: updates.answer
        ) { answer in
            if case .available(_, let page) = answer {
                Link("Download", destination: page)
                Button("Later", role: .cancel) {}
            } else {
                Button("OK", role: .cancel) {}
            }
        } message: { answer in
            Text(message(for: answer))
        }
    }

    private var title: String {
        switch updates.answer {
        case .available(let version, _): "Clipper \(version) is available"
        case .current: "Clipper is up to date"
        case .failed, nil: "Clipper could not check for updates"
        }
    }

    private func message(for answer: UpdateCheck.Answer) -> String {
        switch answer {
        case .available:
            "The release page has the disk image and what changed."
        case .current(let version):
            "Version \(version) is the newest release."
        case .failed(let reason):
            reason
        }
    }
}
