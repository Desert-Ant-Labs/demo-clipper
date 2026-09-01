import SwiftUI

extension View {
    /// Reports an export that did not finish, leaving the clips it was made
    /// from on screen behind it.
    func exportProblemAlert(_ model: ClipperModel) -> some View {
        modifier(ExportProblemAlert(model: model))
    }
}

private struct ExportProblemAlert: ViewModifier {
    @Bindable var model: ClipperModel

    private var isPresented: Binding<Bool> {
        Binding(
            get: { model.exportProblem != nil },
            set: { if !$0 { model.exportProblem = nil } }
        )
    }

    func body(content: Content) -> some View {
        content.alert(
            "The clips could not be written",
            isPresented: isPresented,
            presenting: model.exportProblem
        ) { problem in
            // No retry: a moved file, a track that is not there, and a format
            // that cannot be written all fail the same way the second time.
            // The advice says when trying again is worth it.
            Button("OK") {}
                .keyboardShortcut(.defaultAction)
            // The whole sequence, not just the last line: which clip, which
            // stage, and what it was running on. A reader who does not need it
            // never has to read it.
            Button("Copy Details") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(Diagnostics.report(problem), forType: .string)
            }
        } message: { problem in
            Text(problem.advice.map { "\(problem.message)\n\n\($0)" } ?? problem.message)
        }
    }
}
