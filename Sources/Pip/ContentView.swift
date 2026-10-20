import AppKit
import MusicKit
import SwiftUI

struct ContentView: View {
    @Bindable var store: MusicStore
    @State private var section = MusicSection.songs
    @State private var search = ""
    @State private var selectedPlaylist: Playlist?
    @State private var queueVisible = false
    @State private var detailPath: [MusicPageRequest] = []
    @State private var cachedPages: [MusicPageRequest: MusicPage] = [:]
    @State private var artistAlbumTabs: Set<MusicPageRequest> = []
    @FocusState private var searchFocused: Bool
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                sidebar
                Divider()
                ZStack {
                  VStack(alignment: .leading, spacing: 0) {
                    if section != .explore || !store.isConnected {
                        toolbar
                        Divider()
                    }
                    if let message = store.errorMessage {
                        errorBanner(message)
                    }
                    if section == .explore, store.isConnected {
                        ExploreView(store: store, queueVisible: $queueVisible)
                    } else {
                        mainContent
                    }
                  }
                  .opacity(detailPath.isEmpty ? 1 : 0)
                  .disabled(!detailPath.isEmpty)
                  .accessibilityHidden(!detailPath.isEmpty)

                  if let request = detailPath.last {
                      VStack(spacing: 0) {
                          if let message = store.errorMessage { errorBanner(message) }
                          MusicPageView(store: store, request: request, cachedPages: $cachedPages, artistAlbumTabs: $artistAlbumTabs,
                                        onBack: { detailPath.removeLast() }, onOpen: { detailPath.append($0) })
                              .id(request)
                      }
                  }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if queueVisible {
                    Divider()
                    queue
                        .frame(width: 260)
                }
            }
            Divider()
            PlayerBar(store: store, queueVisible: $queueVisible) { track, kind in
                detailPath.append(MusicPageRequest(track: track, kind: kind, country: store.iTunesCountry))
            }
        }
        .background(Palette.canvas)
        .task(id: store.isConnected && scenePhase == .active) {
            guard store.isConnected, scenePhase == .active else { return }
            await store.observePlayback()
        }
        .task(id: "\(section.rawValue):\(store.searchScope.rawValue):\(search)") {
            guard store.isConnected, section != .explore else { return }
            guard store.searchScope != .itunes || search.isEmpty else { return }
            do {
                try await Task.sleep(for: .milliseconds(250))
                await store.loadSongs(query: search, playlist: selectedPlaylist)
            } catch { /* A newer search replaced this one. */ }
        }
        .onChange(of: store.searchScope) { _, scope in
            if scope == .itunes, !search.isEmpty {
                Task { await store.loadSongs(query: search, playlist: selectedPlaylist) }
            }
        }
        .onChange(of: store.iTunesCountry) { _, _ in
            if store.searchScope == .itunes, !search.isEmpty {
                Task { await store.loadSongs(query: search, playlist: selectedPlaylist) }
            }
        }
        .onChange(of: section) { _, _ in
            selectedPlaylist = nil
            search = ""
        }
        .background {
            Button("Focus Search") { searchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .hidden()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Palette.accent)
                Text("Pip").font(.system(size: 25, weight: .bold, design: .rounded))
            }
            .padding(.top, 52)
            .padding(.bottom, 36)
            .padding(.horizontal, 22)

            Text("YOUR MUSIC")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
                .padding(.bottom, 10)

            ForEach(MusicSection.allCases) { item in
                Button {
                    section = item
                    detailPath = []
                } label: {
                    Label(item.rawValue, systemImage: item.symbol)
                        .font(.system(size: 13, weight: section == item ? .semibold : .regular))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .foregroundStyle(section == item ? Color.primary : .secondary)
                        .background(section == item ? Color.primary.opacity(0.07) : .clear,
                                    in: RoundedRectangle(cornerRadius: 7))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .accessibilityAddTraits(section == item ? .isSelected : [])
            }
            Spacer()
            VStack(alignment: .leading, spacing: 7) {
                Label(store.isConnected ? "Connected" : "Apple Music", systemImage: store.isConnected ? "checkmark.circle.fill" : "music.note")
                    .font(.system(size: 12, weight: .medium))
                Text(store.connectionDetail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(22)
        }
        .frame(width: 188)
        .background(.primary.opacity(0.025))
    }

    private var toolbar: some View {
        HStack(spacing: 14) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(store.searchScope.placeholder, text: $search)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .disabled(!store.isConnected)
                .onSubmit { submitSearch() }
            if !search.isEmpty {
                Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Clear search")
                    .accessibilityLabel("Clear search")
            }
            if store.searchScope == .itunes {
                Button("Search") { submitSearch() }
                    .disabled(!store.isConnected || store.isLoading || search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Menu(store.iTunesCountry) {
                    Picker("iTunes Store country", selection: $store.iTunesCountry) {
                        ForEach(ITunesSearch.countries, id: \.self) { country in
                            Text(Locale.current.localizedString(forRegionCode: country) ?? country).tag(country)
                        }
                    }
                }
                .fixedSize()
                .disabled(!store.isConnected)
                .help("iTunes Store country; availability may differ from your Apple Music account")
                .accessibilityLabel("iTunes Store country: \(store.iTunesCountry)")
            }
            Picker("Search in", selection: $store.searchScope) {
                ForEach(MusicSearchScope.allCases) { scope in
                    Text(scope.rawValue).tag(scope)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            .disabled(!store.isConnected)
            .help("Choose library search, public iTunes search, or the Apple Music catalog")
            Button { Task { await store.refresh(query: search, playlist: selectedPlaylist) } } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(!store.isConnected || store.isLoading)
            .help("Refresh library")
            .accessibilityLabel("Refresh library")
        }
        .padding(.horizontal, 28)
        .frame(height: 66)
    }

    @ViewBuilder private var mainContent: some View {
        if !store.isConnected {
            welcome
        } else {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    if selectedPlaylist != nil {
                        Button {
                            selectedPlaylist = nil
                            search = ""
                        } label: { Image(systemName: "chevron.left") }
                            .buttonStyle(.borderless)
                            .help("Back to playlists")
                            .accessibilityLabel("Back to playlists")
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(search.isEmpty ? (selectedPlaylist?.name ?? section.rawValue) : "Search results")
                            .font(.system(size: 29, weight: .bold))
                            .lineLimit(2)
                        Text(store.isLoading ? "Loading your music…" : contentSubtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if store.isLoading { ProgressView().controlSize(.small) }
                }
                .padding(.horizontal, 28)
                .padding(.top, 28)

                if section == .playlists && selectedPlaylist == nil && search.isEmpty {
                    playlistList
                } else {
                    songList
                }
            }
        }
    }

    private var contentSubtitle: String {
        if section == .playlists && selectedPlaylist == nil && search.isEmpty {
            return "\(store.playlists.count) playlists in your library"
        }
        if !search.isEmpty, store.searchScope == .itunes {
            return "\(store.tracks.count) songs · iTunes Store (\(store.iTunesCountry)) · up to \(ITunesSearch.limit) results"
        }
        let source = search.isEmpty ? "" : " in \(store.searchScope.rawValue.lowercased())"
        return "\(store.tracks.count) songs\(source)\(store.hasMore ? " loaded" : "")"
    }

    private func submitSearch() {
        guard !store.isLoading else { return }
        Task { await store.loadSongs(query: search, playlist: selectedPlaylist) }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
            Image(systemName: "waveform")
                .font(.system(size: 45, weight: .light))
                .foregroundStyle(Palette.accent)
                .padding(.bottom, 28)
                .accessibilityHidden(true)
            Text("A little less app.\nA lot more music.")
                .font(.system(size: 36, weight: .bold))
                .tracking(-0.8)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 16)
            Text(store.welcomeDetail)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .lineSpacing(5)
                .frame(maxWidth: 380, alignment: .leading)
                .padding(.bottom, 28)
            Button {
                Task { await store.connect() }
            } label: {
                HStack(spacing: 9) {
                    if store.isConnecting { ProgressView().controlSize(.small) }
                    Text(store.isConnecting ? "Connecting…" : "Connect to Apple Music")
                    if !store.isConnecting { Image(systemName: "arrow.right") }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
            }
            .buttonStyle(.borderedProminent)
            .disabled(store.isConnecting)
            Spacer()
            Text("Your library. Your subscription. A quieter place to listen.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.bottom, 30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, 52)
    }

    private var songList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("TITLE").frame(maxWidth: .infinity, alignment: .leading)
                if !queueVisible { Text("ALBUM").frame(width: 150, alignment: .leading) }
                Image(systemName: "clock").frame(width: 44)
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 28)
            .padding(.bottom, 10)

            if store.tracks.isEmpty && !store.isLoading {
                ContentUnavailableView(search.isEmpty ? "No songs here yet" : "No matching songs",
                                       systemImage: "music.note",
                                       description: Text(search.isEmpty ? "Add music to your Apple Music library, then refresh." : "Try another song, artist, or album."))
                    .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(store.tracks) { track in
                        Button {
                            Task { await store.play(track) }
                        } label: {
                            HStack(spacing: 12) {
                                TrackTile(artwork: track.artwork, isPlaying: store.currentTrack?.id == track.id && store.isPlaying)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(track.title).foregroundStyle(store.currentTrack?.id == track.id ? Palette.accent : .primary)
                                    Text(track.artist).font(.system(size: 11)).foregroundStyle(.secondary)
                                }
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                if !queueVisible {
                                  Text(track.album)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .frame(width: 150, alignment: .leading)
                                }
                                Text(PlaybackTime.label(track.duration))
                                    .font(.system(size: 11).monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 44)
                            }
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Play \(track.title) by \(track.artist)")
                    }
                    if store.hasMore {
                        Button("Load more songs") {
                            Task { await store.loadMore() }
                        }
                        .disabled(store.isLoading)
                    }
                }
                .listStyle(.plain)
                .padding(.horizontal, 12)
            }
        }
    }

    private var playlistList: some View {
        List {
          ForEach(store.playlists) { playlist in
            Button {
                selectedPlaylist = playlist
                Task { await store.loadSongs(query: search, playlist: playlist) }
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 19))
                        .foregroundStyle(Palette.accent)
                        .frame(width: 42, height: 42)
                        .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 5))
                    Text(playlist.name).frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .padding(.vertical, 5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
          }
          if store.hasMorePlaylists {
              Button("Load more playlists") { Task { await store.loadMorePlaylists() } }
                  .disabled(store.isLoading)
          }
        }
        .listStyle(.plain)
        .overlay {
            if store.playlists.isEmpty && !store.isLoading {
                ContentUnavailableView("No playlists yet", systemImage: "music.note.list",
                                       description: Text("Create a playlist in Apple Music, then refresh."))
            }
        }
        .padding(.horizontal, 12)
    }

    private var queue: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Playback queue").font(.system(size: 17, weight: .semibold))
            Text(store.queueDetail).font(.system(size: 12)).foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(store.queue) { track in
                        Button {
                            Task { await store.selectQueueTrack(track) }
                        } label: {
                            HStack(spacing: 10) {
                                TrackTile(artwork: track.artwork, isPlaying: store.currentTrack?.id == track.id && store.isPlaying)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(track.title).font(.system(size: 12, weight: .medium))
                                    Text(track.artist).font(.system(size: 11)).foregroundStyle(.secondary)
                                }
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if store.queue.isEmpty { Text("Choose a song to start listening.").font(.system(size: 12)).foregroundStyle(.secondary) }
            Spacer(minLength: 0)
        }
        .padding(22)
        .padding(.top, 44)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle")
            Text(message).font(.system(size: 12)).textSelection(.enabled)
            Spacer(minLength: 0)
            Button { store.errorMessage = nil } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
                .accessibilityLabel("Dismiss error")
        }
        .foregroundStyle(.primary)
        .padding(14)
        .background(.orange.opacity(0.12))
    }
}

struct TrackTile: View {
    var artwork: Artwork?
    var isPlaying = false

    var body: some View {
        Group {
          if let artwork {
            ArtworkImage(artwork, width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 5))
          } else {
            Image(systemName: isPlaying ? "waveform" : "music.note")
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(isPlaying ? Palette.accent : .secondary)
            .frame(width: 36, height: 36)
            .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 5))
          }
        }
            .accessibilityHidden(true)
    }
}
