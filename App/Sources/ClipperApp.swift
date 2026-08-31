import DesertAntUI
import SwiftUI

@main
struct ClipperApp: App {
    @State private var warmup = ModelWarmup()
    @State private var updates = UpdateCheck()

    var body: some Scene {
        // One window: the app works on one video at a time, and a second
        // window is a second copy of everything with nothing more in it.
        Window("Clipper", id: "clipper") {
            main
        }
        .defaultSize(width: 1240, height: 820)
        .windowResizability(.contentMinSize)
        .commands { ClipperCommands(updates: updates) }

        Window("About Clipper", id: About.windowID) {
            AboutView()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }

    private var main: some View {
        ContentView()
            // The brand accent: ink in light, cream in dark, like the mark.
            .tint(DA.Color.accent)
            .environment(warmup)
            .task { warmup.warm() }
            .updateAlert(updates)
    }
}

private struct ClipperCommands: Commands {
    let updates: UpdateCheck

    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.clipperModel) private var model
    @FocusedValue(\.inspectorShown) private var inspectorShown

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Clipper") { openWindow(id: About.windowID) }

            Button("Check for Updates…") {
                Task { await updates.check() }
            }
            .disabled(updates.isChecking)
        }

        CommandGroup(replacing: .newItem) {
            Button("Open Video…") { model?.chooseVideo() }
                .keyboardShortcut("o")
                .disabled(model == nil)

            Menu("Open Recent") {
                ForEach(model?.recents ?? [], id: \.self) { url in
                    Button(url.lastPathComponent) { model?.open(url) }
                }
                if model?.recents.isEmpty == false {
                    Divider()
                    Button("Clear Menu") { model?.forgetRecents() }
                }
            }
            .disabled(model?.recents.isEmpty != false)

            Divider()

            // This app has no Close item of its own: a `Window` scene brings
            // none, so ⌘W did nothing before. A disabled item would swallow the
            // shortcut rather than pass it on, so the item stays enabled and
            // closes the window once there is no video left to close.
            Button(model?.isOpen == true ? "Close Video" : "Close Window") {
                model?.closeVideoOrWindow()
            }
            .keyboardShortcut("w")
            .disabled(model == nil)
        }

        CommandGroup(replacing: .saveItem) {
            Button("Export Clip…") {
                guard let model, let clip = model.selectedPick else { return }
                model.export([clip])
            }
            .keyboardShortcut("e")
            .disabled(model?.selectedPick == nil || model?.canExport == false)

            Button("Export All Clips…") {
                guard let model else { return }
                model.export(model.picks)
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(model?.canExport != true)
        }

        CommandGroup(after: .toolbar) {
            Button("Inspector") { inspectorShown?.wrappedValue.toggle() }
                .keyboardShortcut("i")
                .disabled(model?.selectedPick == nil)
        }
    }
}

extension FocusedValues {
    @Entry var clipperModel: ClipperModel?
    @Entry var inspectorShown: Binding<Bool>?
}
