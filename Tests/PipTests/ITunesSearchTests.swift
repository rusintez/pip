import Foundation
import MusicKit
import Testing
@testable import Pip

@Test func publicSearchEncodesUnicodeAndQuerySeparators() throws {
    let term = "Ария & A+B"
    let request = try ITunesSearch.request(term: term, country: "US")
    let url = try #require(request.url)
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    #expect(components.scheme == "https")
    #expect(components.host == "itunes.apple.com")
    #expect(components.queryItems?.first(where: { $0.name == "term" })?.value == term)
    #expect(components.percentEncodedQuery?.contains("%2B") == true)
    #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    #expect(throws: ITunesSearch.Failure.self) { try ITunesSearch.request(term: "song", country: "US&entity=movie") }
}

@Test func publicResultsBecomePlayableSongsWithoutPreviewURLs() throws {
    let data = Data(#"{"results":[{"kind":"song","trackId":120954025,"trackName":"Upside Down","artistName":"Jack Johnson","collectionName":"Curious George","trackTimeMillis":210743,"artworkUrl100":"https://is1-ssl.mzstatic.com/image/thumb/cover/100x100bb.jpg","previewUrl":"https://example.invalid/preview.m4a"},{"kind":"song","trackId":120954025,"trackName":"Duplicate","artistName":"Jack Johnson"},{"kind":"music-video","trackId":2,"trackName":"Video","artistName":"Artist"},{"kind":"song","trackName":"Missing ID","artistName":"Artist"}]}"#.utf8)
    let songs = try ITunesSearch.decode(data)
    #expect(songs.count == 1)
    let song = try #require(songs.first)
    #expect(song.id.rawValue == "120954025")
    #expect(song.title == "Upside Down")
    #expect(song.artistName == "Jack Johnson")
    #expect(song.duration == 210.743)
    #expect(song.playParameters != nil)
    #expect(song.previewAssets?.isEmpty ?? true)
    #expect(song.artwork?.url(width: 72, height: 72)?.absoluteString == "https://is1-ssl.mzstatic.com/image/thumb/cover/100x100bb.jpg")
}

@Test func publicArtworkUsesAvailableSizesAndRejectsUntrustedURLs() throws {
    let data = Data(#"{"results":[{"kind":"song","trackId":1,"trackName":"Small cover","artistName":"Artist","artworkUrl60":"https://is1-ssl.mzstatic.com/60x60bb.jpg"},{"kind":"song","trackId":2,"trackName":"Insecure","artistName":"Artist","artworkUrl100":"http://is1-ssl.mzstatic.com/cover.jpg"},{"kind":"song","trackId":3,"trackName":"Wrong host","artistName":"Artist","artworkUrl100":"https://is1-ssl.mzstatic.com.evil.invalid/cover.jpg"},{"kind":"song","trackId":4,"trackName":"Missing","artistName":"Artist"},{"kind":"song","trackId":5,"trackName":"Credential URL","artistName":"Artist","artworkUrl100":"https://example:placeholder@is1-ssl.mzstatic.com/cover.jpg"},{"kind":"song","trackId":6,"trackName":"Fallback","artistName":"Artist","artworkUrl100":"file:///cover.jpg","artworkUrl30":"https://is1-ssl.mzstatic.com/30x30bb.jpg"}]}"#.utf8)
    let songs = try ITunesSearch.decode(data)
    #expect(songs.count == 6)
    #expect(songs[0].artwork?.url(width: 36, height: 36)?.lastPathComponent == "60x60bb.jpg")
    #expect(songs[1...4].allSatisfy { $0.artwork == nil })
    #expect(songs[5].artwork?.url(width: 36, height: 36)?.lastPathComponent == "30x30bb.jpg")
}
