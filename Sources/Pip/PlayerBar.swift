import AppKit
import SwiftUI

struct PlayerBar: View {
    @Bindable var store: MusicStore
    @Binding var queueVisible: Bool
    var onBrowse: (Track, MusicPageRequest.Kind) -> Void
    @State private var seeking = false
    @State private var seekPosition = 0.0

    var body: some View {
        HStack(spacing: 24) {
            HStack(spacing: 12) {
                Button { browse(.album) } label: {
                    TrackTile(artwork: store.currentTrack?.artwork, isPlaying: store.isPlaying)
                }
                .buttonStyle(.plain)
                .disabled(store.currentTrack == nil)
                .help("Show album")
                .accessibilityLabel("Show album")
                VStack(alignment: .leading, spacing: 5) {
                    Button { browse(.album) } label: {
                        Text(store.currentTrack?.title ?? "Nothing playing")
                    }
                        .buttonStyle(.plain)
                        .disabled(store.currentTrack == nil)
                        .font(.system(size: 12, weight: .semibold))
                        .help("Show album: \(store.currentTrack?.album ?? "")")
                        .accessibilityLabel(store.currentTrack.map { "\($0.title). Show album: \($0.album)" } ?? "Nothing playing")
                    Button { browse(.artist) } label: {
                        Text(store.currentTrack?.artist ?? "Find your next favorite.")
                            .foregroundStyle(store.currentTrack == nil ? Color.secondary : Palette.accent)
                    }
                    .buttonStyle(.plain)
                    .disabled(store.currentTrack == nil)
                    .font(.system(size: 11))
                    .help("Show artist")
                    .accessibilityLabel("Show artist: \(store.currentTrack?.artist ?? "Nothing playing")")
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: 230)
            .contextMenu {
                if let track = store.currentTrack {
                    Button("Show Artist") { browse(.artist) }
                    Button("Show Album") { browse(.album) }
                    Divider()
                    Button("Start Station") { Task { await store.startStation(for: track) } }
                        .disabled(!store.isConnected || store.isControlling || store.startingStationTitle != nil || track.catalogID == nil)
                    if let url = track.appleMusicURL {
                        Divider()
                        Button("Copy Apple Music Link") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.writeObjects([url as NSURL])
                        }
                        ShareLink("Share Song…", item: url)
                    } else {
                        Button("Copy Apple Music Link") {}.disabled(true)
                        Button("Share Song…") {}.disabled(true)
                    }
                }
            }

            VStack(spacing: 6) {
                HStack(spacing: 24) {
                    Button { Task { await store.previous() } } label: { Image(systemName: "backward.end.fill") }
                        .help("Previous track (⌘←)")
                        .accessibilityLabel("Previous track")
                    Button { Task { await store.togglePlayback() } } label: {
                        Image(systemName: store.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 17))
                            .frame(width: 32, height: 27)
                    }
                    .help(store.isPlaying ? "Pause (⌘P)" : "Play (⌘P)")
                    .accessibilityLabel(store.isPlaying ? "Pause" : "Play")
                    Button { Task { await store.next() } } label: { Image(systemName: "forward.end.fill") }
                        .help("Next track (⌘→)")
                        .accessibilityLabel("Next track")
                }
                .buttonStyle(.borderless)
                .disabled(store.currentTrack == nil || store.isControlling)
                HStack(spacing: 8) {
                    Text(PlaybackTime.label(seeking ? seekPosition : store.position))
                        .frame(width: 42, alignment: .trailing)
                    Slider(value: Binding(
                        get: { seeking ? seekPosition : PlaybackTime.clamped(store.position, duration: duration) },
                        set: { seekPosition = $0 }
                    ), in: 0...max(duration, 1)) { editing in
                        if editing { seekPosition = store.position }
                        seeking = editing
                        if !editing { Task { await store.seek(to: seekPosition) } }
                    }
                    .controlSize(.mini)
                    .disabled(store.currentTrack == nil || duration <= 0)
                    .accessibilityLabel("Playback position")
                    Text(PlaybackTime.label(duration)).frame(width: 42, alignment: .leading)
                }
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 16) {
                if let title = store.startingStationTitle {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Starting station…").font(.system(size: 11))
                    }
                    .foregroundStyle(.secondary)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Starting station from \(title)")
                } else {
                    Text("Apple Music")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Button { queueVisible.toggle() } label: {
                    Image(systemName: "list.bullet")
                        .foregroundStyle(queueVisible ? Palette.accent : .secondary)
                }
                .buttonStyle(.borderless)
                .help("Show playback queue")
                .accessibilityLabel(queueVisible ? "Hide playback queue" : "Show playback queue")
            }
        }
        .padding(.horizontal, 24)
        .frame(height: 88)
    }

    private var duration: Double { store.currentTrack?.duration ?? 0 }

    private func browse(_ kind: MusicPageRequest.Kind) {
        if let track = store.currentTrack { onBrowse(track, kind) }
    }
}
