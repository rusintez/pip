// MusicKit's player lacks Sendable annotations; the store serializes player commands on MainActor.
@preconcurrency import MusicKit
import Foundation
import Observation

@MainActor @Observable
final class MusicStore {
    private(set) var isConnected = false
    private(set) var isConnecting = false
    private(set) var isLoading = false
    private(set) var isControlling = false
    private(set) var startingStationTitle: String?
    private(set) var isPlaying = false
    private(set) var hasMore = false
    private(set) var hasMorePlaylists = false
    private(set) var tracks: [Track] = []
    private(set) var playlists: [Playlist] = []
    private(set) var queue: [Track] = []
    private(set) var currentTrack: Track?
    private(set) var position = 0.0
    var errorMessage: String?
    var searchScope = MusicSearchScope.library
    var iTunesCountry = (Locale.current.region?.identifier).flatMap { ITunesSearch.countries.contains($0) ? $0 : nil } ?? "US"

    @ObservationIgnored private lazy var player = ApplicationMusicPlayer.shared
    @ObservationIgnored private var songs: [Song] = []
    @ObservationIgnored private var songPage: MusicItemCollection<Song>?
    @ObservationIgnored private var playlistTrackPage: MusicItemCollection<MusicKit.Track>?
    @ObservationIgnored private var playlistPage: MusicItemCollection<MusicKit.Playlist>?
    @ObservationIgnored private var libraryPlaylists: [MusicKit.Playlist] = []
    @ObservationIgnored private var browsingRequest = LatestRequest()
    @ObservationIgnored private var stationRequest = LatestRequest()

    var connectionDetail: String {
        isConnected ? "Independent MusicKit player" : "Ready to connect your library."
    }

    let welcomeDetail = "Your Apple Music library in a small, native player. Connect your subscription to browse, search, and play your music."
    let queueDetail = "Songs in the current playback queue."

    func connect() async {
        guard !isConnecting, !isConnected else { return }
        isConnecting = true
        errorMessage = nil
        defer { isConnecting = false }

        guard Bundle.main.object(forInfoDictionaryKey: "NSAppleMusicUsageDescription") != nil else {
            errorMessage = "Open the bundled Pip.app or run the Pip target in Xcode. A bare Swift executable cannot request music access."
            return
        }

        let status = await MusicAuthorization.request()
        guard status == .authorized else {
            errorMessage = "Allow Pip in System Settings → Privacy & Security → Media & Apple Music, then connect again."
            return
        }

        isConnected = true
        await refresh(query: "", playlist: nil)
    }

    func refresh(query: String, playlist: Playlist?) async {
        guard isConnected else { return }
        await loadSongs(query: query, playlist: playlist)
        await loadPlaylists()
    }

    func loadSongs(query: String, playlist: Playlist?) async {
        guard isConnected else { return }
        let request = browsingRequest.begin()
        let scope = searchScope
        isLoading = true
        hasMore = false
        errorMessage = nil
        // Clear old results so an in-flight search cannot play the previous query.
        tracks = []
        songs = []
        songPage = nil
        playlistTrackPage = nil
        defer { if browsingRequest.isCurrent(request) { isLoading = false } }

        do {
            let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if !term.isEmpty {
                if scope == .itunes {
                    let results = try await ITunesSearch.songs(term: term, country: iTunesCountry)
                    try Task.checkCancellation()
                    guard browsingRequest.isCurrent(request) else { return }
                    accept(results)
                    return
                }
                let page: MusicItemCollection<Song>
                switch scope {
                case .library:
                    var search = MusicLibraryRequest<Song>()
                    search.filter(text: term)
                    search.sort(by: \.title, ascending: true)
                    search.limit = 50
                    page = try await search.response().items
                case .catalog:
                    var search = MusicCatalogSearchRequest(term: term, types: [Song.self])
                    search.limit = 50
                    page = try await search.response().songs
                case .itunes:
                    return
                }
                try Task.checkCancellation()
                guard browsingRequest.isCurrent(request) else { return }
                songPage = page
                accept(Array(page))
                hasMore = page.hasNextBatch
            } else if let playlist {
                guard let source = libraryPlaylists.first(where: { $0.id.rawValue == playlist.id }) else { return }
                let loaded = try await source.with([.tracks])
                try Task.checkCancellation()
                guard browsingRequest.isCurrent(request) else { return }
                playlistTrackPage = loaded.tracks
                accept(songItems(loaded.tracks))
                hasMore = loaded.tracks?.hasNextBatch ?? false
            } else {
                var library = MusicLibraryRequest<Song>()
                library.limit = 50
                library.sort(by: \.title, ascending: true)
                let page = try await library.response().items
                try Task.checkCancellation()
                guard browsingRequest.isCurrent(request) else { return }
                songPage = page
                accept(Array(page))
                hasMore = page.hasNextBatch
            }
        } catch is CancellationError {
            // Navigation or typing replaced this request.
        } catch {
            guard browsingRequest.isCurrent(request), !Task.isCancelled else { return }
            errorMessage = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Couldn’t load your library. Check music access and Sync Library in Apple Music, then refresh."
                : MusicFailure.searchMessage(for: error, scope: scope)
        }
    }

    func loadMore() async {
        guard isConnected, hasMore, !isLoading else { return }
        let request = browsingRequest.current
        isLoading = true
        defer { if browsingRequest.isCurrent(request) { isLoading = false } }
        do {
            if let page = songPage {
                let next = try await page.nextBatch(limit: 50)
                try Task.checkCancellation()
                guard browsingRequest.isCurrent(request) else { return }
                songPage = next
                accept(Array(next ?? []), appending: true)
                hasMore = next?.hasNextBatch ?? false
            } else if let page = playlistTrackPage {
                let next = try await page.nextBatch(limit: 50)
                try Task.checkCancellation()
                guard browsingRequest.isCurrent(request) else { return }
                playlistTrackPage = next
                accept(songItems(next), appending: true)
                hasMore = next?.hasNextBatch ?? false
            }
        } catch {
            if browsingRequest.isCurrent(request), !Task.isCancelled {
                errorMessage = "Couldn’t load the next songs. Try again when your connection is available."
            }
        }
    }

    func loadMorePlaylists() async {
        guard hasMorePlaylists, let page = playlistPage, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let next = try await page.nextBatch(limit: 50)
            playlistPage = next
            libraryPlaylists += Array(next ?? [])
            playlists = libraryPlaylists.map { Playlist(id: $0.id.rawValue, name: $0.name) }
            hasMorePlaylists = next?.hasNextBatch ?? false
        } catch {
            errorMessage = "Couldn’t load more playlists. Please try again."
        }
    }

    func play(_ track: Track) async {
        guard isConnected, !isControlling else { return }
        guard let song = songs.first(where: { $0.id.rawValue == track.id }) else { return }
        let selection = songs
        await startPlayback(startingAt: song) { ApplicationMusicPlayer.Queue(for: selection, startingAt: song) }
    }

    func play(_ song: Song, in page: MusicPage) async {
        guard isConnected, !isControlling else { return }
        if let album = page.album {
            await startPlayback(startingAt: song) { ApplicationMusicPlayer.Queue(album: album, startingAt: .song(song)) }
        } else {
            await playDiscovery(.song(song), among: page.songs.map(DiscoveryItem.song))
        }
    }

    func selectQueueTrack(_ track: Track) async {
        guard isConnected, !isControlling,
              let entry = player.queue.entries.first(where: {
                  if case .song(let song) = $0.item { return song.id.rawValue == track.id }
                  return false
              }) else { return }
        player.queue.currentEntry = entry
        await control { try await self.player.play() }
    }

    func playDiscovery(_ item: DiscoveryItem, among items: [DiscoveryItem]) async {
        guard isConnected, !isControlling else { return }
        switch item {
        case .song(let song):
            let songs = items.compactMap { item -> Song? in
                if case .song(let song) = item { return song }
                return nil
            }
            await startPlayback(startingAt: song) { ApplicationMusicPlayer.Queue(for: songs, startingAt: song) }
        case .playlist(let playlist): await startPlayback { ApplicationMusicPlayer.Queue(for: [playlist]) }
        case .album(let album): await startPlayback { ApplicationMusicPlayer.Queue(for: [album]) }
        case .station(let station): await startPlayback { ApplicationMusicPlayer.Queue(for: [station]) }
        }
    }

    private func startPlayback(startingAt song: Song? = nil, queue: () -> ApplicationMusicPlayer.Queue) async {
        await control(selectionName: song?.title) {
            try await self.replacePlayback(startingAt: song, queue: queue)
        }
    }

    func startStation(for track: Track) async {
        guard isConnected, !isControlling, startingStationTitle == nil, let songID = track.catalogID else { return }
        let request = stationRequest.begin()
        startingStationTitle = track.title
        errorMessage = nil
        defer { if stationRequest.isCurrent(request) { startingStationTitle = nil } }
        do {
            let station = try await MusicDiscovery.station(songID: songID, country: iTunesCountry)
            guard stationRequest.isCurrent(request), !Task.isCancelled else { return }
            await startPlayback { ApplicationMusicPlayer.Queue(for: [station]) }
        } catch {
            guard stationRequest.isCurrent(request), !Task.isCancelled else { return }
            errorMessage = MusicFailure.stationMessage(for: error)
        }
    }

    private func replacePlayback(startingAt song: Song? = nil, queue: () -> ApplicationMusicPlayer.Queue) async throws {
        let previousSongs = self.player.queue.entries.compactMap { entry -> Song? in
            if case .song(let song) = entry.item { return song }
            return nil
        }
        let previousSong: Song?
        if case .song(let song) = self.player.queue.currentEntry?.item { previousSong = song }
        else { previousSong = nil }
        let previousPosition = self.player.playbackTime
        let wasPlaying = self.player.state.playbackStatus == .playing
        self.player.queue = queue()
        try await PlaybackRecovery.start(play: { try await self.player.play() }, prepareAgain: {
            self.player.stop()
            self.player.queue = queue()
            try await self.player.prepareToPlay()
        }, restore: { failure in
            guard let previousSong, !previousSongs.isEmpty else { return }
            self.player.stop()
            self.player.queue = ApplicationMusicPlayer.Queue(for: previousSongs, startingAt: previousSong)
            if wasPlaying, MusicFailure.isPreparationFailure(failure), previousSong.id != song?.id {
                do {
                    try await self.player.prepareToPlay()
                    self.player.playbackTime = PlaybackTime.clamped(previousPosition, duration: previousSong.duration ?? 0)
                    try await self.player.play()
                } catch { /* Keep the original selection failure visible. */ }
            }
        })
    }

    func togglePlayback() async {
        guard isConnected, currentTrack != nil else { return }
        await control {
            if self.player.state.playbackStatus == .playing { self.player.pause() }
            else { try await self.player.play() }
        }
    }

    func next() async {
        await control { try await self.player.skipToNextEntry() }
    }

    func previous() async {
        await control { try await self.player.skipToPreviousEntry() }
    }

    func seek(to value: Double) async {
        guard isConnected, let currentTrack else { return }
        player.playbackTime = PlaybackTime.clamped(value, duration: currentTrack.duration)
        synchronizePlayback()
    }

    func observePlayback() async {
        // Only the visible app samples elapsed time; MusicKit continues playing in the background.
        while !Task.isCancelled {
            synchronizePlayback()
            do { try await Task.sleep(for: .seconds(1)) }
            catch { return }
        }
    }

    private func loadPlaylists() async {
        do {
            var request = MusicLibraryRequest<MusicKit.Playlist>()
            request.limit = 50
            request.sort(by: \.name, ascending: true)
            let page = try await request.response().items
            playlistPage = page
            libraryPlaylists = Array(page)
            playlists = libraryPlaylists.map { Playlist(id: $0.id.rawValue, name: $0.name) }
            hasMorePlaylists = page.hasNextBatch
        } catch {
            errorMessage = "Couldn’t load playlists. Check that Sync Library is enabled in Apple Music, then refresh."
        }
    }

    private func accept(_ items: [Song], appending: Bool = false) {
        var seen = Set(appending ? songs.map(\.id) : [])
        let unique = items.filter { seen.insert($0.id).inserted }
        songs = appending ? songs + unique : unique
        tracks = songs.map(Track.init)
    }

    private func songItems(_ page: MusicItemCollection<MusicKit.Track>?) -> [Song] {
        (page ?? []).compactMap {
            if case .song(let song) = $0 { return song }
            return nil
        }
    }

    private func control(selectionName: String? = nil, _ operation: () async throws -> Void) async {
        guard isConnected, !isControlling else { return }
        _ = stationRequest.begin()
        startingStationTitle = nil
        isControlling = true
        errorMessage = nil
        defer { isControlling = false; synchronizePlayback() }
        do { try await operation() }
        catch { errorMessage = (selectionName.map { "Couldn’t play “\($0)”. " } ?? "") + MusicFailure.playbackMessage(for: error) }
    }

    private func synchronizePlayback() {
        isPlaying = player.state.playbackStatus == .playing
        position = player.playbackTime
        let entries = player.queue.entries.compactMap { entry -> Track? in
            if case .song(let song) = entry.item { return Track(song) }
            return nil
        }
        if queue != entries { queue = entries }
        let current: Track?
        if case .song(let song) = player.queue.currentEntry?.item { current = Track(song) }
        else { current = nil }
        if currentTrack != current { currentTrack = current }
    }
}

// MusicKit requests can finish out of order even when a task has been cancelled.
struct LatestRequest {
    private(set) var current = UUID()

    mutating func begin() -> UUID {
        current = UUID()
        return current
    }

    func isCurrent(_ request: UUID) -> Bool { current == request }
}
