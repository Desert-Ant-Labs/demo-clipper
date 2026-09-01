import SwiftUI

extension View {
    /// Offers the cut clips to be saved.
    func clipExporter(_ model: ClipperModel) -> some View {
        modifier(ClipExporter(model: model))
    }
}

/// One clip and several take different panels, and which one it is belongs
/// here rather than in the model: a save panel that asks for a name, and one
/// that asks for a folder to put them all in. Only the save panel is given a
/// name, and the several-document exporter has no parameter for one, which is
/// why a single clip went out as "Exported MPEG-4 movie".
private struct ClipExporter: ViewModifier {
    @Bindable var model: ClipperModel

    func body(content: Content) -> some View {
        if let only = model.finished.first, model.finished.count == 1 {
            content.fileExporter(
                isPresented: $model.isExporting,
                document: only,
                contentType: only.contentType,
                defaultFilename: only.name
            ) { _ in
                model.finishExporting()
            }
        } else {
            content.fileExporter(
                isPresented: $model.isExporting,
                documents: model.finished,
                contentType: model.finished.first?.contentType ?? .mpeg4Movie
            ) { _ in
                model.finishExporting()
            }
        }
    }
}
