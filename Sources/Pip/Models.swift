import Foundation
import MusicKit

struct Track: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let artist: String
    let album: String
    let duration: Double
    var artwork: Artwork?
    let catalogID: UInt64?

    var appleMusicURL: URL? {
        catalogID.flatMap { URL(string: "https://music.apple.com/song/\($0)") }
    }

    init(_ song: Song) {
        id = song.id.rawValue
        title = song.title
        artist = song.artistName
        album = song.albumTitle ?? ""
        duration = song.duration ?? 0
        artwork = song.artwork
        catalogID = Self.catalogID(id: song.id.rawValue, url: song.url)
    }

    static func catalogID(id: String, url: URL?) -> UInt64? {
        if let value = UInt64(id), value > 0 { return value }
        guard let url, url.scheme == "https", let host = url.host, ["music.apple.com", "itunes.apple.com"].contains(host),
              let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "i" })?.value,
              let value = UInt64(value), value > 0 else { return nil }
        return value
    }
}

struct MusicPageRequest: Hashable, Sendable {
    enum Kind: String, Sendable { case artist, album }
    enum Reference: Hashable, Sendable { case track(Track), entity(UInt64) }
    let kind: Kind
    let reference: Reference
    let name: String
    let country: String

    init(track: Track, kind: Kind, country: String) {
        self.kind = kind
        reference = .track(track)
        name = kind == .artist ? track.artist : track.album
        self.country = country
    }

    init(id: UInt64, name: String, kind: Kind, country: String) {
        self.kind = kind
        reference = .entity(id)
        self.name = name
        self.country = country
    }
}

struct CatalogAlbum: Identifiable, Sendable {
    let id: UInt64
    let name: String
    let artist: String
    let year: String?
    let artwork: Artwork?
}

struct MusicPage: Sendable {
    let name: String
    let artistID: UInt64?
    let artistName: String
    let trackCount: Int?
    let songs: [Song]
    let albums: [CatalogAlbum]
    var album: Album? = nil
}

struct Playlist: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let name: String
}

enum MusicSection: String, CaseIterable, Identifiable {
    case explore = "Explore"
    case songs = "Songs"
    case playlists = "Playlists"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .explore: "safari"
        case .songs: "music.note"
        case .playlists: "music.note.list"
        }
    }
}

enum MusicSearchScope: String, CaseIterable, Identifiable {
    case library = "Library"
    case itunes = "iTunes"
    case catalog = "Catalog"

    var id: Self { self }
    var placeholder: String {
        switch self {
        case .library: "Search your library"
        case .itunes: "Search iTunes — press Return"
        case .catalog: "Search Apple Music catalog"
        }
    }
}

enum PlaybackTime {
    static func label(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let value = Int(min(seconds, Double(Int.max / 2)))
        if value >= 3600 {
            return String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60)
        }
        return String(format: "%d:%02d", value / 60, value % 60)
    }

    static func clamped(_ position: Double, duration: Double) -> Double {
        guard position.isFinite, duration.isFinite, duration > 0 else { return 0 }
        return min(max(position, 0), duration)
    }
}

@MainActor enum PlaybackRecovery {
    static func start(play: () async throws -> Void, prepareAgain: () async throws -> Void,
                      restore: (any Error) async -> Void = { _ in }) async throws {
        do {
            do { try await play() }
            catch {
                guard MusicFailure.isPreparationFailure(error) else { throw error }
                try await prepareAgain()
                try await play()
            }
        }
        catch {
            await restore(error)
            throw error
        }
    }
}

enum MusicFailure {
    static func isPreparationFailure(_ error: any Error) -> Bool {
        var next: NSError? = error as NSError
        for _ in 0..<5 {
            guard let current = next else { return false }
            if current.domain == "MPMusicPlayerControllerErrorDomain", current.code == 6 { return true }
            next = current.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return false
    }

    static func searchMessage(for error: any Error, scope: MusicSearchScope) -> String {
        if scope == .itunes {
            if let error = error as? ITunesSearch.Failure { return error.errorDescription ?? "iTunes search failed." }
            return "Couldn’t load iTunes search. Check your connection and press Return to retry."
        }
        let nsError = error as NSError
        if scope == .catalog,
           (error as? MusicTokenRequestError == .developerTokenRequestFailed ||
            (nsError.domain == "ICError" && nsError.code == -8200)) {
            return "Apple couldn’t authorize catalog search for this app. Enable MusicKit for its registered bundle ID. You can search your Library without catalog access."
        }
        if nsError.domain == NSURLErrorDomain {
            return "Search couldn’t reach Apple Music. Check your connection and try again."
        }
        if scope == .catalog {
            return "Catalog search couldn’t load. Check this app’s MusicKit registration and your connection, or switch to Library search."
        }
        return "Your library search couldn’t load. Check music access and Sync Library in Apple Music, then try again."
    }

    static func stationMessage(for error: any Error) -> String {
        let detail = (error as? MusicDiscovery.Failure)?.errorDescription ?? playbackMessage(for: error)
        return "Couldn’t load this song’s station. " + detail + " Your current queue is unchanged."
    }

    static func playbackMessage(for error: any Error) -> String {
        if let tokenError = error as? MusicTokenRequestError {
            switch tokenError {
            case .developerTokenRequestFailed:
                return "Apple Music couldn’t authorize this app. Enable MusicKit for its registered bundle ID and rebuild with the intended developer team."
            case .permissionDenied, .userTokenRevoked:
                return "Pip no longer has music access. Allow it in System Settings → Privacy & Security → Media & Apple Music, then reopen Pip."
            case .userNotSignedIn:
                return "Sign in to Apple Music on this Mac, then reopen Pip."
            case .privacyAcknowledgementRequired:
                return "Open Apple Music and accept its pending privacy notice, then retry playback in Pip."
            case .userTokenRequestFailed:
                return "Apple Music couldn’t authorize your media account. Check your sign-in and subscription in Music, then reopen Pip."
            case .unknown:
                break
            @unknown default:
                break
            }
        }

        // Keep only error identifiers: userInfo and descriptions may contain account or session data.
        var errors: [NSError] = []
        var next: NSError? = error as NSError
        while let current = next, errors.count < 5 {
            errors.append(current)
            next = current.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        let knownDomains: Set<String> = [
            "MPMusicPlayerControllerErrorDomain", NSCocoaErrorDomain, NSURLErrorDomain,
            NSOSStatusErrorDomain, "ICError", "AMSErrorDomain", "SKErrorDomain"
        ]
        let reference = errors.map {
            "\(knownDomains.contains($0.domain) ? $0.domain : "OtherError") \($0.code)"
        }.joined(separator: " → ")

        if errors.contains(where: {
            ($0.domain == "MPMusicPlayerControllerErrorDomain" && $0.code == 10) ||
            ($0.domain == NSCocoaErrorDomain && [4097, 4099].contains($0.code))
        }) {
            return "Apple’s playback service disconnected. Quit and reopen Pip. If this persists, check the app’s signing and MusicKit setup. [\(reference)]"
        }
        if errors.contains(where: { $0.domain == NSURLErrorDomain }) {
            return "Apple Music couldn’t reach the network. Check your connection and retry playback. [\(reference)]"
        }
        if isPreparationFailure(error) {
            return "Apple Music couldn’t prepare this selection. Try another song or collection, or reopen Pip. Availability may differ from the browsing country. [\(reference)]"
        }
        return "Apple Music couldn’t complete playback. Retry after reopening Pip. [\(reference)]"
    }
}
