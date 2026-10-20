import Foundation
import MusicKit

enum ITunesSearch {
    static let limit = 100
    static let countries = Locale.Region.isoRegions.map(\.identifier)
        .filter { $0.count == 2 && $0.utf8.allSatisfy { (65...90).contains($0) } }.sorted()

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 20
        return URLSession(configuration: configuration)
    }()

    static func request(term: String, country: String) throws -> URLRequest {
        let term = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { throw Failure.emptyQuery }
        guard countries.contains(country) else { throw Failure.invalidCountry }
        var url = URLComponents(string: "https://itunes.apple.com/search")!
        url.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "country", value: country),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        // The endpoint interprets a literal '+' as a space, including inside search terms.
        url.percentEncodedQuery = url.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        var request = URLRequest(url: url.url!)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    static func songs(term: String, country: String) async throws -> [Song] {
        try await decode(data(for: request(term: term, country: country)))
    }

    private static func data(for request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw Failure.unavailable }
        guard response.statusCode != 429 else { throw Failure.rateLimited }
        guard response.statusCode == 200 else { throw Failure.unavailable }
        return data
    }

    static func decode(_ data: Data) throws -> [Song] {
        let response = try JSONDecoder().decode(Response.self, from: data)
        return try decodeSongs(response.results)
    }

    private static func decodeSongs(_ results: [Result]) throws -> [Song] {
        var seen = Set<UInt64>()
        return try results.compactMap { result in
            guard result.kind == "song", let id = result.trackId, id > 0,
                  let title = result.trackName, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let artist = result.artistName, seen.insert(id).inserted else { return nil }
            var attributes: [String: Any] = [
                "name": title,
                "artistName": artist,
                "albumName": result.collectionName ?? "",
                "durationInMillis": max(result.trackTimeMillis ?? 0, 0),
                "genreNames": result.primaryGenreName.map { [$0] } ?? [],
                "playParams": ["id": String(id), "kind": "song"]
            ]
            attributes["artwork"] = result.artwork
            let resource: [String: Any] = ["id": String(id), "type": "songs", "attributes": attributes]
            // shortcut: adapt public IDs through MusicKit's Codable resource format; revisit if its decoder changes.
            return try JSONDecoder().decode(Song.self, from: JSONSerialization.data(withJSONObject: resource))
        }
    }

    enum LookupEntity: String { case song, album }

    static func lookupRequest(id: UInt64, country: String, entity: LookupEntity? = nil, limit: Int = 50) throws -> URLRequest {
        guard id > 0, (1...200).contains(limit) else { throw Failure.missingDetails }
        guard countries.contains(country) else { throw Failure.invalidCountry }
        var url = URLComponents(string: "https://itunes.apple.com/lookup")!
        url.queryItems = [URLQueryItem(name: "id", value: String(id)), URLQueryItem(name: "country", value: country),
                          URLQueryItem(name: "limit", value: String(limit))]
        if let entity { url.queryItems?.append(URLQueryItem(name: "entity", value: entity.rawValue)) }
        var request = URLRequest(url: url.url!)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    static func page(for request: MusicPageRequest) async throws -> MusicPage {
        let id: UInt64
        switch request.reference {
        case .entity(let entityID): id = entityID
        case .track(let track):
            guard let songID = track.catalogID else { throw Failure.noCatalogLink }
            let metadata = try await data(for: lookupRequest(id: songID, country: request.country))
            id = try relatedID(in: metadata, songID: songID, kind: request.kind)
        }
        if request.kind == .album {
            let result = try await data(for: lookupRequest(id: id, country: request.country, entity: .song, limit: 200))
            return try decodeAlbum(result, id: id)
        }
        async let songs = data(for: lookupRequest(id: id, country: request.country, entity: .song))
        async let albums = data(for: lookupRequest(id: id, country: request.country, entity: .album))
        return try await decodeArtist(songs: songs, albums: albums, id: id)
    }

    static func relatedID(in data: Data, songID: UInt64, kind: MusicPageRequest.Kind) throws -> UInt64 {
        let results = try JSONDecoder().decode(Response.self, from: data).results
        guard let song = results.first(where: { $0.kind == "song" && $0.trackId == songID }),
              let id = kind == .artist ? song.artistId : song.collectionId, id > 0 else { throw Failure.missingDetails }
        return id
    }

    static func decodeAlbum(_ data: Data, id: UInt64) throws -> MusicPage {
        let results = try JSONDecoder().decode(Response.self, from: data).results
        guard let album = results.first(where: { $0.wrapperType == "collection" && $0.collectionType == "Album" && $0.collectionId == id }),
              let name = album.collectionName else { throw Failure.missingDetails }
        let ordered = results.enumerated().filter { $0.element.kind == "song" && $0.element.collectionId == id }
            .sorted {
                let lhs = ($0.element.discNumber ?? 1, $0.element.trackNumber ?? ($0.offset + 1), $0.offset)
                let rhs = ($1.element.discNumber ?? 1, $1.element.trackNumber ?? ($1.offset + 1), $1.offset)
                return lhs < rhs
            }.map(\.element)
        // Queue the album ID so MusicKit resolves one collection instead of separate public song resources.
        var attributes: [String: Any] = [
            "name": name, "artistName": album.artistName ?? "",
            "playParams": ["id": String(id), "kind": "album"]
        ]
        attributes["artwork"] = album.artwork
        let resource: [String: Any] = ["id": String(id), "type": "albums", "attributes": attributes]
        let playableAlbum = try JSONDecoder().decode(Album.self, from: JSONSerialization.data(withJSONObject: resource))
        return try MusicPage(name: name, artistID: album.artistId, artistName: album.artistName ?? "",
                             trackCount: album.trackCount, songs: decodeSongs(ordered), albums: [], album: playableAlbum)
    }

    static func decodeArtist(songs: Data, albums: Data, id: UInt64) throws -> MusicPage {
        let songs = try JSONDecoder().decode(Response.self, from: songs).results
        let albums = try JSONDecoder().decode(Response.self, from: albums).results
        guard let artist = (songs + albums).first(where: { $0.wrapperType == "artist" && $0.artistId == id }),
              let name = artist.artistName else { throw Failure.missingDetails }
        var seen = Set<UInt64>()
        let collections = try albums.compactMap { result -> CatalogAlbum? in
            guard result.wrapperType == "collection", result.collectionType == "Album", result.artistId == id,
                  let albumID = result.collectionId, albumID > 0, seen.insert(albumID).inserted,
                  let title = result.collectionName else { return nil }
            let artwork = try result.artwork.map {
                try JSONDecoder().decode(Artwork.self, from: JSONSerialization.data(withJSONObject: $0))
            }
            return CatalogAlbum(id: albumID, name: title, artist: result.artistName ?? name,
                                year: result.releaseDate.map { String($0.prefix(4)) }, artwork: artwork)
        }
        return try MusicPage(name: name, artistID: id, artistName: name, trackCount: nil,
            songs: decodeSongs(songs.filter { $0.artistId == id }), albums: collections)
    }

    enum Failure: LocalizedError {
        case emptyQuery, invalidCountry, rateLimited, unavailable, missingDetails, noCatalogLink

        var errorDescription: String? {
            switch self {
            case .emptyQuery: "Enter a song or artist to search iTunes."
            case .invalidCountry: "Choose a valid iTunes Store country."
            case .rateLimited: "iTunes has limited search requests. Wait a moment, then press Return to retry."
            case .unavailable: "iTunes search is unavailable right now. Try again shortly."
            case .missingDetails: "These details aren’t available in this store. Try another country in Search or Explore, then open the page again."
            case .noCatalogLink: "This local or uploaded track has no public catalog link. Its artist and album pages aren’t available."
            }
        }
    }

    private struct Response: Decodable { let results: [Result] }

    private struct Result: Decodable {
        let wrapperType: String?
        let collectionType: String?
        let artistId: UInt64?
        let collectionId: UInt64?
        let kind: String?
        let trackId: UInt64?
        let trackName: String?
        let artistName: String?
        let collectionName: String?
        let trackTimeMillis: Int?
        let primaryGenreName: String?
        let discNumber: Int?
        let trackNumber: Int?
        let trackCount: Int?
        let releaseDate: String?
        let artworkUrl100: String?
        let artworkUrl60: String?
        let artworkUrl30: String?

        var artwork: [String: Any]? {
            for (source, size) in [(artworkUrl100, 100), (artworkUrl60, 60), (artworkUrl30, 30)] {
                guard let source, let url = URL(string: source), url.scheme == "https",
                      let host = url.host, host.hasSuffix(".mzstatic.com"),
                      url.user == nil, url.password == nil else { continue }
                return ["url": url.absoluteString, "width": size, "height": size]
            }
            return nil
        }
    }
}
