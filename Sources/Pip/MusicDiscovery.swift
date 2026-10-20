import Foundation
import MusicKit

enum ExploreSource: String, CaseIterable, Identifiable {
    case topSongs = "Top Songs"
    case playlists = "Popular Playlists"
    case featured = "New & Featured"
    case personal = "For You"

    var id: Self { self }
}

enum DiscoveryItem: Identifiable, Hashable, Sendable {
    case song(Song)
    case playlist(MusicKit.Playlist)
    case album(Album)
    case station(Station)

    var id: String {
        switch self {
        case .song(let item): "song:\(item.id.rawValue)"
        case .playlist(let item): "playlist:\(item.id.rawValue)"
        case .album(let item): "album:\(item.id.rawValue)"
        case .station(let item): "station:\(item.id.rawValue)"
        }
    }

    var title: String {
        switch self {
        case .song(let item): item.title
        case .playlist(let item): item.name
        case .album(let item): item.title
        case .station(let item): item.name
        }
    }

    var subtitle: String {
        switch self {
        case .song(let item): item.artistName
        case .playlist(let item): item.curatorName ?? "Apple Music playlist"
        case .album(let item): item.artistName
        case .station: "Apple Music station"
        }
    }

    var artwork: Artwork? {
        switch self {
        case .song(let item): item.artwork
        case .playlist(let item): item.artwork
        case .album(let item): item.artwork
        case .station(let item): item.artwork
        }
    }
}

struct DiscoverySection: Identifiable, Sendable {
    let id: String
    let title: String
    let items: [DiscoveryItem]
}

enum MusicDiscovery {
    static let limit = 25
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 25
        return URLSession(configuration: configuration)
    }()

    static func request(source: ExploreSource, country: String) throws -> URLRequest {
        guard ITunesSearch.countries.contains(country), source != .personal else { throw Failure.unavailable }
        let region = country.lowercased()
        let url: URL
        if source == .featured {
            url = URL(string: "https://music.apple.com/\(region)/new")!
        } else {
            let kind = source == .topSongs ? "songs" : "playlists"
            url = URL(string: "https://rss.marketingtools.apple.com/api/v2/\(region)/music/most-played/\(limit)/\(kind).json")!
        }
        return URLRequest(url: url)
    }

    static func sections(source: ExploreSource, country: String) async throws -> [DiscoverySection] {
        if source == .personal {
            var request = MusicPersonalRecommendationsRequest()
            request.limit = 10
            let response = try await request.response()
            return response.recommendations.compactMap { recommendation in
                let items = recommendation.items.prefix(limit).compactMap { item -> DiscoveryItem? in
                    switch item {
                    case .album(let album): .album(album)
                    case .playlist(let playlist): .playlist(playlist)
                    case .station(let station): .station(station)
                    @unknown default: nil
                    }
                }
                return items.isEmpty ? nil : DiscoverySection(id: recommendation.id.rawValue,
                    title: recommendation.title ?? "Recommended for you", items: items)
            }
        }
        let (data, response) = try await session.data(for: request(source: source, country: country))
        guard let response = response as? HTTPURLResponse, data.count <= 8_000_000 else { throw Failure.unavailable }
        guard response.statusCode != 429 else { throw Failure.rateLimited }
        guard response.statusCode == 200 else { throw Failure.unavailable }
        if source == .featured { return try decodeFeatured(data) }
        let items = try decodeFeed(data, source: source)
        return chartSections(items: items, source: source)
    }

    static func chartSections(items: [DiscoveryItem], source: ExploreSource) -> [DiscoverySection] {
        items.isEmpty ? [] : [DiscoverySection(id: source.rawValue, title: "Most played · Top \(limit)", items: items)]
    }

    static func decodeFeed(_ data: Data, source: ExploreSource) throws -> [DiscoveryItem] {
        let response = try JSONDecoder().decode(FeedResponse.self, from: data)
        let kind = source == .topSongs ? "songs" : "playlists"
        var seen = Set<String>()
        return try response.feed.results.prefix(limit).compactMap { result in
            guard result.kind == kind, seen.insert(result.id).inserted else { return nil }
            return try resource(id: result.id, kind: source == .topSongs ? "song" : "playlist",
                                title: result.name, subtitle: result.artistName ?? "Apple Music playlist",
                                artworkURL: result.artworkUrl100)
        }
    }

    static func decodeFeatured(_ data: Data) throws -> [DiscoverySection] {
        let page = try JSONDecoder().decode(FeaturedPage.self, from: publicPageJSON(data))
        guard let sections = page.data.first?.data.sections else { throw Failure.pageChanged }
        let result = try sections.prefix(30).enumerated().compactMap { index, section -> DiscoverySection? in
            var seen = Set<String>()
            let items = try section.items.prefix(limit).compactMap { item -> DiscoveryItem? in
                guard item.isDisabled != true, let descriptor = item.contentDescriptor,
                      let id = descriptor.identifiers.storeAdamID, seen.insert(id).inserted,
                      let title = item.title ?? item.titleLinks?.first?.title else { return nil }
                return try resource(id: id, kind: descriptor.kind, title: title,
                    subtitle: item.subtitle ?? item.artistName ?? item.subtitleLinks?.compactMap(\.title).joined(separator: ", ") ?? "",
                    artworkURL: item.artwork?.dictionary.url)
            }
            return items.isEmpty ? nil : DiscoverySection(id: "featured:\(index)",
                title: section.header?.item?.titleLink?.title ?? "Featured", items: items)
        }
        guard !result.isEmpty else { throw Failure.pageChanged }
        return result
    }

    static func stationRequest(songID: UInt64, country: String) throws -> URLRequest {
        guard songID > 0, ITunesSearch.countries.contains(country) else { throw Failure.stationUnavailable }
        return URLRequest(url: URL(string: "https://music.apple.com/\(country.lowercased())/station/ra.\(songID)")!)
    }

    static func station(songID: UInt64, country: String) async throws -> Station {
        #if DEBUG
        // Exercise pending-state UI and cancellation without changing the Mac's network settings.
        if CommandLine.arguments.contains("--pip-test-slow-station") { try await Task.sleep(for: .seconds(5)) }
        #endif
        let (data, response) = try await session.data(for: stationRequest(songID: songID, country: country))
        guard let response = response as? HTTPURLResponse, data.count <= 8_000_000 else { throw Failure.stationUnavailable }
        guard response.statusCode != 429 else { throw Failure.rateLimited }
        guard response.statusCode == 200 else { throw Failure.stationUnavailable }
        return try decodeStation(data, songID: songID)
    }

    static func decodeStation(_ data: Data, songID: UInt64) throws -> Station {
        let page: FeaturedPage
        do { page = try JSONDecoder().decode(FeaturedPage.self, from: publicPageJSON(data)) }
        catch { throw Failure.stationPageChanged }
        let id = "ra.\(songID)"
        guard songID > 0,
              let item = page.data.first?.data.sections.flatMap(\.items).first(where: {
                  $0.contentDescriptor?.kind == "radioStation" && $0.contentDescriptor?.identifiers.storeAdamID == id && $0.isDisabled != true
              }), let name = item.title, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Failure.stationUnavailable }
        // shortcut: validate Apple's public ra.<songID> page; use Song.station after catalog access is configured.
        let resource: [String: Any] = ["id": id, "type": "stations", "attributes": ["name": name, "isLive": false,
            "playParams": ["id": id, "kind": "radioStation"]]]
        return try JSONDecoder().decode(Station.self, from: JSONSerialization.data(withJSONObject: resource))
    }

    private static func publicPageJSON(_ data: Data) throws -> Data {
        guard let html = String(data: data, encoding: .utf8),
              let marker = html.range(of: "id=\"serialized-server-data\""),
              let start = html.range(of: ">", range: marker.upperBound..<html.endIndex)?.upperBound,
              let end = html.range(of: "</script>", range: start..<html.endIndex)?.lowerBound,
              let json = html[start..<end].data(using: .utf8) else { throw Failure.pageChanged }
        // shortcut: Apple's public page schema is undocumented; replace this adapter if its structure changes.
        return json
    }

    private static func resource(id: String, kind: String, title: String, subtitle: String, artworkURL: String?) throws -> DiscoveryItem? {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        switch kind {
        case "song", "album": guard let numeric = UInt64(id), numeric > 0 else { return nil }
        case "playlist": guard id.hasPrefix("pl."), id.count <= 100,
            id.utf8.allSatisfy({ [45, 46, 95].contains($0) || (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) }) else { return nil }
        default: return nil
        }
        var attributes: [String: Any] = ["name": title, "artistName": subtitle, "curatorName": subtitle,
                                        "playParams": ["id": id, "kind": kind]]
        if let artworkURL, let url = URL(string: artworkURL.replacingOccurrences(of: "{", with: "%7B").replacingOccurrences(of: "}", with: "%7D")),
           url.scheme == "https", let host = url.host, host.hasSuffix(".mzstatic.com") {
            let image = artworkURL.replacingOccurrences(of: "{w}", with: "100").replacingOccurrences(of: "{h}", with: "100")
                .replacingOccurrences(of: "{c}", with: "cc").replacingOccurrences(of: "{f}", with: "jpg")
            attributes["artwork"] = ["url": image, "width": 100, "height": 100]
        }
        let json = try JSONSerialization.data(withJSONObject: ["id": id, "type": kind + "s", "attributes": attributes])
        let decoder = JSONDecoder()
        switch kind {
        case "song": return .song(try decoder.decode(Song.self, from: json))
        case "playlist": return .playlist(try decoder.decode(MusicKit.Playlist.self, from: json))
        case "album": return .album(try decoder.decode(Album.self, from: json))
        default: return nil
        }
    }

    static func message(for error: any Error, source: ExploreSource) -> String {
        if let error = error as? Failure { return error.errorDescription ?? "Explore couldn’t load. Try again." }
        let nativeError = error as NSError
        if source == .personal,
           (nativeError.domain == "ICError" && nativeError.code == -8200 ||
            error as? MusicTokenRequestError == .developerTokenRequestFailed) {
            return "Apple couldn’t authorize personalized recommendations for Pip. Enable MusicKit for its registered bundle ID, then retry."
        }
        return source == .personal
            ? "Couldn’t load your recommendations. Check your connection and Pip’s MusicKit registration, then retry."
            : "Couldn’t load Explore. Check your connection, try another country, or retry."
    }

    enum Failure: LocalizedError {
        case unavailable, rateLimited, pageChanged, stationUnavailable, stationPageChanged
        var errorDescription: String? {
            switch self {
            case .unavailable: "This collection isn’t available. Try another country or retry shortly."
            case .rateLimited: "Apple has limited requests. Wait a moment, then retry."
            case .pageChanged: "Apple’s featured page couldn’t be read. Try Top Songs or Popular Playlists instead."
            case .stationUnavailable: "Apple’s public page has no station for this song in the selected country. Try another song or country."
            case .stationPageChanged: "Apple’s station page couldn’t be read. Retry or choose another song."
            }
        }
    }

    private struct FeedResponse: Decodable {
        let feed: Feed
        struct Feed: Decodable { let results: [Item] }
        struct Item: Decodable {
            let id: String
            let name: String
            let kind: String
            let artistName: String?
            let artworkUrl100: String?
        }
    }

    private struct FeaturedPage: Decodable {
        let data: [Page]
        struct Page: Decodable { let data: Contents }
        struct Contents: Decodable { let sections: [Shelf] }
        struct Shelf: Decodable {
            let header: Header?
            let items: [Item]
        }
        struct Header: Decodable { let item: HeaderItem? }
        struct HeaderItem: Decodable { let titleLink: TextLink? }
        struct Item: Decodable {
            let title: String?
            let subtitle: String?
            let artistName: String?
            let titleLinks: [TextLink]?
            let subtitleLinks: [TextLink]?
            let contentDescriptor: Descriptor?
            let artwork: Image?
            let isDisabled: Bool?
        }
        struct TextLink: Decodable { let title: String? }
        struct Descriptor: Decodable {
            let kind: String
            let identifiers: Identifiers
        }
        struct Identifiers: Decodable { let storeAdamID: String? }
        struct Image: Decodable {
            let dictionary: ImageDictionary
        }
        struct ImageDictionary: Decodable { let url: String? }
    }
}
