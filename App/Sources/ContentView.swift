import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var model = ClipperModel()
    // Open by default, and remembered: the clip's card, its score and what the
    // models cost all live there.
    @AppStorage("showsInspector") private var showsInspector = true
    @State private var showsPerformance = false
    @State private var columns = NavigationSplitViewVisibility.detailOnly

    var body: some View {
        @Bindable var model = model

        NavigationSplitView(columnVisibility: $columns) {
            ClipList(
                picks: model.picks,
                sentences: model.sentences,
                source: model.source,
                selection: $model.selection
            )
        } detail: {
            DetailContent()
        }
        // The sidebar holds the result, so it opens on the first clip and is
        // gone until there is one, including after another video is opened.
        .onChange(of: model.picks.isEmpty) { _, empty in
            columns = empty ? .detailOnly : .all
        }
        .inspector(isPresented: presentedInspector) {
            Inspector(
                pick: model.selectedPick,
                sentences: model.sentences,
                source: model.source,
                reading: model.reading,
                performance: model.performance,
                titleProblem: model.titleProblem
            )
            .inspectorColumnWidth(min: 240, ideal: 320, max: 560)
        }
        .sheet(isPresented: $showsPerformance) {
            if let performance = model.performance {
                PerformanceSheet(performance: performance)
            }
        }
        .environment(model)
        .onOpenURL { model.open($0) }
        .focusedSceneValue(\.clipperModel, model)
        .focusedSceneValue(\.inspectorShown, $showsInspector)
        .navigationTitle(title)
        .navigationSubtitle(subtitle)
        .modifier(DocumentProxy(url: model.asset?.url))
        .overlay(alignment: .bottom) {
            if case .exporting(let done, let total) = model.phase {
                ExportProgress(done: done, total: total)
            }
        }
        .fileImporter(
            isPresented: $model.isChoosingVideo,
            allowedContentTypes: [.movie]
        ) { result in
            if case .success(let url) = result { model.open(url) }
        }
        .fileExporter(
            isPresented: $model.isExporting,
            documents: model.finished,
            contentType: .mpeg4Movie
        ) { _ in
            model.finishExporting()
        }
        .fileExporter(
            isPresented: $model.isExportingTranscript,
            document: model.transcriptFile,
            contentType: .plainText,
            defaultFilename: model.transcriptFile?.name
        ) { _ in
            model.finishExportingTranscript()
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: isVideo) else { return false }
            model.open(url)
            return true
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Export Clip…", action: exportSelectedClip)
                        .disabled(model.exportableClip == nil)
                    Button("Export All Clips…") { model.export(model.picks) }
                    Divider()
                    Button("Export Subtitles…") {
                        model.exportTranscript(of: model.selectedPick)
                    }
                    .disabled(model.selectedPick == nil)
                } label: {
                    Label("Export", systemImage: "square.and.arrow.down")
                } primaryAction: {
                    exportSelectedClip()
                }
                .disabled(!model.canExport)
                .help("Export the selected clip")
            }

            ToolbarItem(placement: .primaryAction) {
                Button("Performance", systemImage: "stopwatch") {
                    showsPerformance = true
                }
                .help("How fast each model ran")
                .disabled(model.performance == nil)
            }

            ToolbarSpacer(.fixed, placement: .primaryAction)

            ToolbarItem(placement: .primaryAction) {
                Button("Inspector", systemImage: "sidebar.trailing") {
                    showsInspector.toggle()
                }
                .disabled(model.selectedPick == nil)
            }
        }
    }

    private func exportSelectedClip() {
        guard let clip = model.exportableClip else { return }
        model.export([clip])
    }

    /// Shown only once there is something to inspect, without forgetting that
    /// it was left open: opening a video should not reveal an empty panel
    /// beside a drop zone.
    private var presentedInspector: Binding<Bool> {
        Binding(
            get: { showsInspector && model.selectedPick != nil },
            set: { showsInspector = $0 }
        )
    }

    /// What is selected, which is the recording's own name when that is what
    /// is selected. The file keeps its identity through the proxy icon.
    private var title: String {
        guard !model.videoName.isEmpty else { return "Clipper" }
        guard let pick = model.selectedPick, !pick.isWholeRecording else { return model.videoName }
        return pick.displayTitle
    }

    /// `11 clips` on its own, and what the whole run cost beside it once the
    /// clips have been named.
    private var subtitle: String {
        guard !model.picks.isEmpty else { return "" }
        let clips = model.picks.count == 1 ? "1 clip" : "\(model.picks.count) clips"
        guard let total = model.performance?.total else { return clips }
        return "\(clips) created in \(total.formattedSeconds)"
    }

    // Audio would transcribe, but a clip is written out as an mp4 and played
    // back in a video view, so there would be nothing to see.
    private func isVideo(_ url: URL) -> Bool {
        let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType
        return type?.conforms(to: .movie) ?? false
    }
}

private struct DetailContent: View {
    @Environment(ClipperModel.self) private var model
    @Environment(ModelWarmup.self) private var warmup

    var body: some View {
        switch model.phase {
        case .idle:
            if warmup.pending.isEmpty {
                DropZone { model.chooseVideo() }
            } else {
                WarmupView()
            }
        case .failed(let message):
            ContentUnavailableView {
                Label("Could not make clips", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Open Another Video") { model.chooseVideo() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        // Selection returns every clip in one go, so the first one takes over
        // from the progress while the titles are still being written. Each card
        // then fills in where its clip already sits.
        case .ready, .exporting, .writingTitles:
            if let pick = model.selectedPick {
                @Bindable var model = model
                VStack(spacing: 0) {
                    ClipDetail(pick: pick)
                    Divider()
                    Timeline(
                        picks: model.picks,
                        sentences: model.sentences,
                        duration: model.source?.duration.seconds ?? 0,
                        selection: $model.selection
                    )
                }
            } else {
                ContentUnavailableView("No clip selected", systemImage: "sparkles.rectangle.stack")
            }
        case .extractingAudio, .loadingSpeech, .transcribing, .preparingModels, .selecting:
            WorkingView()
        }
    }
}

private struct ExportProgress: View {
    let done: Int
    let total: Int

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("Exporting clip \(done + 1) of \(total)")
                .font(.callout)
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: .capsule)
        .padding(.bottom, 20)
    }
}

/// Puts the file's icon in the title bar, with the path menu and the drag-out
/// that every document window has. SwiftUI has no optional form, so a window
/// with nothing open carries no proxy.
private struct DocumentProxy: ViewModifier {
    let url: URL?

    func body(content: Content) -> some View {
        if let url {
            content.navigationDocument(url)
        } else {
            content
        }
    }
}
