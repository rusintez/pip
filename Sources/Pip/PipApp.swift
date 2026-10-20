import SwiftUI

@main
struct PipApp: App {
    @State private var store = MusicStore()

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
                .frame(minWidth: 860, minHeight: 560)
                .tint(Palette.accent)
        }
        .defaultSize(width: 1120, height: 740)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Connect to Apple Music") { Task { await store.connect() } }
                    .disabled(store.isConnected || store.isConnecting)
            }
            CommandMenu("Playback") {
                Button(store.isPlaying ? "Pause" : "Play") { Task { await store.togglePlayback() } }
                    .keyboardShortcut("p", modifiers: .command)
                    .disabled(store.currentTrack == nil)
                Button("Next Track") { Task { await store.next() } }
                    .keyboardShortcut(.rightArrow, modifiers: .command)
                    .disabled(store.currentTrack == nil)
                Button("Previous Track") { Task { await store.previous() } }
                    .keyboardShortcut(.leftArrow, modifiers: .command)
                    .disabled(store.currentTrack == nil)
            }
        }
    }
}

enum Palette {
    static let accent = Color(red: 0.96, green: 0.43, blue: 0.26)
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let line = Color.primary.opacity(0.09)
}
