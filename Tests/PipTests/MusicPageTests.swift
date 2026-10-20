import Foundation
import MusicKit
import Testing
@testable import Pip

@Test func catalogNavigationUsesSongIDsAndTrustedSongLinks() {
    #expect(Track.catalogID(id: "123", url: nil) == 123)
    #expect(Track.catalogID(id: "l.library", url: URL(string: "https://music.apple.com/hk/album/name/700?i=123")) == 123)
    #expect(Track.catalogID(id: "l.local", url: URL(string: "https://music.apple.com/hk/album/name/700")) == nil)
    #expect(Track.catalogID(id: "l.local", url: URL(string: "https://music.apple.com.evil.invalid/album/700?i=123")) == nil)
    #expect(Track.catalogID(id: "0", url: nil) == nil)
}

@Test func nowPlayingLinksPointToTheExactCatalogSong() throws {
    let songs = try ITunesSearch.decode(Data(#"{"results":[{"kind":"song","trackId":6807192581,"artistName":"ADÉLA","trackName":"KGB"}]}"#.utf8))
    let track = Track(try #require(songs.first))
    #expect(track.appleMusicURL?.absoluteString == "https://music.apple.com/song/6807192581")
    let local = try JSONDecoder().decode(Song.self, from: Data(#"{"id":"l.local","type":"library-songs","attributes":{"name":"Local song","artistName":"Artist"}}"#.utf8))
    #expect(Track(local).appleMusicURL == nil)
}

@Test func pageLookupsValidateIDsCountryAndLimits() throws {
    let request = try ITunesSearch.lookupRequest(id: 123, country: "HK", entity: .song, limit: 200)
    let url = try #require(request.url)
    #expect(url.host == "itunes.apple.com")
    #expect(url.path == "/lookup")
    let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
    #expect(query.first(where: { $0.name == "id" })?.value == "123")
    #expect(query.first(where: { $0.name == "entity" })?.value == "song")
    #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    #expect(throws: ITunesSearch.Failure.self) { try ITunesSearch.lookupRequest(id: 0, country: "HK") }
    #expect(throws: ITunesSearch.Failure.self) { try ITunesSearch.lookupRequest(id: 123, country: "HK&x=1") }
    #expect(throws: ITunesSearch.Failure.self) { try ITunesSearch.lookupRequest(id: 123, country: "HK", limit: 201) }
}

@Test func trackLookupRequiresTheExactSongBeforeOpeningItsRelatedEntity() throws {
    let data = Data(#"{"results":[{"kind":"song","trackId":99,"artistId":9,"collectionId":90},{"kind":"song","trackId":123,"artistId":10,"collectionId":700}]}"#.utf8)
    #expect(try ITunesSearch.relatedID(in: data, songID: 123, kind: .artist) == 10)
    #expect(try ITunesSearch.relatedID(in: data, songID: 123, kind: .album) == 700)
    #expect(throws: ITunesSearch.Failure.self) { try ITunesSearch.relatedID(in: data, songID: 999, kind: .artist) }
}

@Test func albumPagesFilterCollectionsAndKeepDiscThenTrackOrder() throws {
    let data = Data(#"{"results":[{"wrapperType":"collection","collectionType":"Album","collectionId":700,"artistId":10,"artistName":"Artist","collectionName":"Album","trackCount":4},{"kind":"song","trackId":3,"collectionId":700,"artistName":"Artist","trackName":"Disc two","discNumber":2,"trackNumber":1},{"kind":"song","trackId":2,"collectionId":700,"artistName":"Artist","trackName":"Second","discNumber":1,"trackNumber":2},{"kind":"song","trackId":1,"collectionId":700,"artistName":"Artist","trackName":"First","discNumber":1,"trackNumber":1},{"kind":"song","trackId":4,"collectionId":701,"artistName":"Artist","trackName":"Other album"}]}"#.utf8)
    let page = try ITunesSearch.decodeAlbum(data, id: 700)
    #expect(page.name == "Album")
    #expect(page.artistID == 10)
    #expect(page.trackCount == 4)
    #expect(page.songs.map(\.title) == ["First", "Second", "Disc two"])
    #expect(page.album?.id.rawValue == "700")
    #expect(page.album?.title == "Album")
    #expect(page.album?.playParameters != nil)
    #expect(throws: ITunesSearch.Failure.self) { try ITunesSearch.decodeAlbum(data, id: 701) }
}

@Test func artistPagesRejectOtherArtistsAndDuplicateAlbums() throws {
    let songs = Data(#"{"results":[{"wrapperType":"artist","artistId":10,"artistName":"Artist"},{"kind":"song","trackId":1,"artistId":10,"artistName":"Artist","trackName":"Correct"},{"kind":"song","trackId":2,"artistId":11,"artistName":"Other","trackName":"Wrong artist"}]}"#.utf8)
    let albums = Data(#"{"results":[{"wrapperType":"collection","collectionType":"Album","artistId":10,"artistName":"Artist","collectionId":700,"collectionName":"Album","releaseDate":"2025-01-01T00:00:00Z"},{"wrapperType":"collection","collectionType":"Album","artistId":10,"collectionId":700,"collectionName":"Duplicate"},{"wrapperType":"collection","collectionType":"Album","artistId":11,"collectionId":701,"collectionName":"Other artist"}]}"#.utf8)
    let page = try ITunesSearch.decodeArtist(songs: songs, albums: albums, id: 10)
    #expect(page.name == "Artist")
    #expect(page.songs.map(\.title) == ["Correct"])
    #expect(page.albums.map(\.name) == ["Album"])
    #expect(page.albums.first?.year == "2025")
    #expect(page.album == nil)
}

@Test func artistAndAlbumPagesRetainArtworkBeforePlayback() throws {
    let data = Data(#"{"results":[{"wrapperType":"artist","artistId":10,"artistName":"Artist"},{"wrapperType":"collection","collectionType":"Album","collectionId":700,"artistId":10,"artistName":"Artist","collectionName":"Album","artworkUrl100":"https://is1-ssl.mzstatic.com/album.jpg"},{"kind":"song","trackId":1,"collectionId":700,"artistId":10,"artistName":"Artist","trackName":"With cover","artworkUrl100":"https://is1-ssl.mzstatic.com/song.jpg"},{"kind":"song","trackId":2,"collectionId":700,"artistId":10,"artistName":"Artist","trackName":"Without cover"}]}"#.utf8)
    let album = try ITunesSearch.decodeAlbum(data, id: 700)
    #expect(album.album?.artwork?.url(width: 36, height: 36)?.lastPathComponent == "album.jpg")
    #expect(album.songs[0].artwork?.url(width: 36, height: 36)?.lastPathComponent == "song.jpg")
    #expect(album.songs[1].artwork == nil)
    let artist = try ITunesSearch.decodeArtist(songs: data, albums: data, id: 10)
    #expect(artist.albums.first?.artwork?.url(width: 36, height: 36)?.lastPathComponent == "album.jpg")
    #expect(artist.songs[0].artwork?.url(width: 36, height: 36)?.lastPathComponent == "song.jpg")
    #expect(artist.songs[1].artwork == nil)
}
