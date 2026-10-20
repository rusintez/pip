import MusicKit
import SwiftUI

struct MusicPageView: View {
    @Bindable var store: MusicStore
    let request: MusicPageRequest
    @Binding var cachedPages: [MusicPageRequest: MusicPage]
    @Binding var artistAlbumTabs: Set<MusicPageRequest>
    var onBack: () -> Void
    var onOpen: (MusicPageRequest) -> Void
    @State private var page: MusicPage?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var refreshID = UUID()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button(action: onBack) { Label("Back", systemImage: "chevron.left") }
                    .buttonStyle(.borderless)
                    .keyboardShortcut("[", modifiers: .command)
                Spacer()
                Text("iTunes · \(request.country)").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 28)
            .frame(height: 66)
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Text(page?.name ?? (request.name.isEmpty ? request.kind.rawValue.capitalized : request.name))
                    .font(.system(size: 29, weight: .bold))
                    .lineLimit(2)
                if let page {
                    if request.kind == .album, let artistID = page.artistID {
                        Button(page.artistName) {
                            onOpen(MusicPageRequest(id: artistID, name: page.artistName, kind: .artist, country: request.country))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Palette.accent)
                        .help("Show artist")
                        .accessibilityLabel("Show artist: \(page.artistName)")
                    }
                    HStack(spacing: 16) {
                        Button {
                            if let song = page.songs.first { play(song, in: page) }
                        } label: { Label(request.kind == .artist ? "Play Songs" : "Play", systemImage: "play.fill") }
                        .disabled(page.songs.isEmpty || store.isControlling)
                        if request.kind == .artist {
                            Picker("Show", selection: albumSelection) {
                                Text("Top Songs").tag(false)
                                Text("Albums").tag(true)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(maxWidth: 220)
                        } else {
                            Text(trackCount(page)).font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(28)

            if isLoading {
                ProgressView("Loading \(request.kind.rawValue)…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("Couldn’t load this \(request.kind.rawValue)", systemImage: "exclamationmark.circle")
                } description: { Text(errorMessage) } actions: {
                    Button("Retry") { refreshID = UUID() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let page {
                if artistAlbumTabs.contains(request), request.kind == .artist {
                    albumList(page)
                } else {
                    songList(page)
                }
            }
        }
        .background(Palette.canvas)
        .task(id: refreshID) {
            if let cached = cachedPages[request] { page = cached; isLoading = false; return }
            isLoading = true
            errorMessage = nil
            do {
                let result = try await ITunesSearch.page(for: request)
                try Task.checkCancellation()
                page = result
                if cachedPages.count >= 12 { cachedPages.removeAll(keepingCapacity: true) }
                cachedPages[request] = result
            } catch {
                guard !Task.isCancelled else { return }
                if let failure = error as? ITunesSearch.Failure {
                    errorMessage = failure == .rateLimited ? "Apple has limited lookups. Wait a moment, then retry." : failure.errorDescription
                } else {
                    errorMessage = "Couldn’t reach iTunes for these details. Check your connection and retry."
                }
            }
            isLoading = false
        }
    }

    private func songList(_ page: MusicPage) -> some View {
        List {
            ForEach(page.songs) { song in
                Button { play(song, in: page) } label: {
                    HStack(spacing: 12) {
                        let current = store.currentTrack?.id == song.id.rawValue
                        let artwork = song.artwork ?? page.album?.artwork
                        TrackTile(artwork: (current ? store.currentTrack?.artwork : nil) ?? artwork, isPlaying: current && store.isPlaying)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(song.title).foregroundStyle(current ? Palette.accent : .primary)
                            Text(song.albumTitle ?? song.artistName).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text(PlaybackTime.label(song.duration ?? 0)).font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(store.isControlling)
                .accessibilityLabel("Play \(song.title) by \(song.artistName)")
            }
        }
        .listStyle(.plain)
        .overlay {
            if page.songs.isEmpty {
                ContentUnavailableView("No songs available", systemImage: "music.note",
                    description: Text("iTunes returned no songs for this \(request.kind.rawValue) in \(request.country)."))
            }
        }
        .padding(.horizontal, 12)
    }

    private func albumList(_ page: MusicPage) -> some View {
        List(page.albums) { album in
            Button {
                onOpen(MusicPageRequest(id: album.id, name: album.name, kind: .album, country: request.country))
            } label: {
                HStack(spacing: 12) {
                    TrackTile(artwork: album.artwork)
                    Text(album.name).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                    if let year = album.year { Text(year).font(.system(size: 11)).foregroundStyle(.secondary) }
                    Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .padding(.vertical, 5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show album: \(album.name)")
        }
        .listStyle(.plain)
        .overlay {
            if page.albums.isEmpty {
                ContentUnavailableView("No albums available", systemImage: "square.stack",
                    description: Text("iTunes returned no albums in \(request.country)."))
            }
        }
        .padding(.horizontal, 12)
    }

    private func play(_ song: Song, in page: MusicPage) {
        Task { await store.play(song, in: page) }
    }

    private var albumSelection: Binding<Bool> {
        Binding(get: { artistAlbumTabs.contains(request) }, set: { selected in
            if selected { artistAlbumTabs.insert(request) }
            else { artistAlbumTabs.remove(request) }
        })
    }

    private func trackCount(_ page: MusicPage) -> String {
        if let total = page.trackCount, total > page.songs.count { return "\(page.songs.count) of \(total) tracks available" }
        return "\(page.songs.count) tracks"
    }
}
