import SwiftUI

/// What each model cost on the video that just ran.
struct PerformanceSheet: View {
    let performance: ClipperModel.Performance

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PerformanceRows(performance: performance)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Performance")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(width: 420, height: 420)
    }
}
