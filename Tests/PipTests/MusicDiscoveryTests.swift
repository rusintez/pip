import Foundation
import MusicKit
import Testing
@testable import Pip

@Test func stationLookupFailurePreservesTheQueueAndHidesErrorDetails() {
    let unavailable = MusicFailure.stationMessage(for: MusicDiscovery.Failure.stationUnavailable)
    #expect(unavailable.contains("no station"))
    #expect(unavailable.contains("queue is unchanged"))
    let failure = NSError(domain: NSURLErrorDomain, code: -1009, userInfo: [NSLocalizedDescriptionKey: "private-account-info"])
    let message = MusicFailure.stationMessage(for: failure)
    #expect(message.contains("network"))
    #expect(!message.contains("private-account-info"))
}

@Test func songStationsRequireTheExactPublicStationBeforePlayback() throws {
    let request = try MusicDiscovery.stationRequest(songID: 123, country: "HK")
    #expect(request.url?.absoluteString == "https://music.apple.com/hk/station/ra.123")
    #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    #expect(throws: MusicDiscovery.Failure.self) { try MusicDiscovery.stationRequest(songID: 0, country: "HK") }
    #expect(throws: MusicDiscovery.Failure.self) { try MusicDiscovery.stationRequest(songID: 123, country: "../US") }
    let html = #"<script id="serialized-server-data">{"data":[{"data":{"sections":[{"items":[{"title":"Other Station","contentDescriptor":{"kind":"radioStation","identifiers":{"storeAdamID":"ra.999"}}},{"title":"Song Station","contentDescriptor":{"kind":"radioStation","identifiers":{"storeAdamID":"ra.123"}}}]}]}}]}</script>"#
    let station = try MusicDiscovery.decodeStation(Data(html.utf8), songID: 123)
    #expect(station.id.rawValue == "ra.123")
    #expect(station.name == "Song Station")
    #expect(station.playParameters != nil)
    #expect(throws: MusicDiscovery.Failure.self) { try MusicDiscovery.decodeStation(Data(html.utf8), songID: 124) }
    let disabled = html.replacingOccurrences(of: "\"title\":\"Song Station\"", with: "\"isDisabled\":true,\"title\":\"Song Station\"")
    #expect(throws: MusicDiscovery.Failure.self) { try MusicDiscovery.decodeStation(Data(disabled.utf8), songID: 123) }
    #expect(throws: MusicDiscovery.Failure.self) { try MusicDiscovery.decodeStation(Data("<html>Changed</html>".utf8), songID: 123) }
}

@Test func discoveryRequestsUsePublicCountrySpecificSources() throws {
    let chart = try MusicDiscovery.request(source: .playlists, country: "HK")
    #expect(chart.url?.absoluteString == "https://rss.marketingtools.apple.com/api/v2/hk/music/most-played/25/playlists.json")
    #expect(chart.value(forHTTPHeaderField: "Authorization") == nil)
    let featured = try MusicDiscovery.request(source: .featured, country: "US")
    #expect(featured.url?.absoluteString == "https://music.apple.com/us/new")
    #expect(throws: MusicDiscovery.Failure.self) { try MusicDiscovery.request(source: .topSongs, country: "US/other") }
    #expect(throws: MusicDiscovery.Failure.self) { try MusicDiscovery.request(source: .personal, country: "US") }
}

@Test func discoveryFeedsKeepOrderAndDecodePlayableCollections() throws {
    let songs = Data(#"{"feed":{"results":[{"id":"42","name":"First","artistName":"Artist","kind":"songs"},{"id":"42","name":"Duplicate","kind":"songs"},{"id":"8","name":"Wrong kind","kind":"albums"},{"id":"bad","name":"Bad ID","kind":"songs"},{"id":"43","name":"Second","kind":"songs"}]}}"#.utf8)
    let result = try MusicDiscovery.decodeFeed(songs, source: .topSongs)
    #expect(result.map(\.title) == ["First", "Second"])
    guard case .song(let song) = try #require(result.first) else { Issue.record("Expected song"); return }
    #expect(song.playParameters != nil)
    let playlists = Data(#"{"feed":{"results":[{"id":"pl.example","name":"Featured mix","kind":"playlists","artworkUrl100":"https://evil.invalid/image.jpg"},{"id":"pl.bad/path","name":"Invalid ID","kind":"playlists"}]}}"#.utf8)
    let collections = try MusicDiscovery.decodeFeed(playlists, source: .playlists)
    #expect(collections.count == 1)
    guard case .playlist(let playlist) = try #require(collections.first) else { Issue.record("Expected playlist"); return }
    #expect(playlist.playParameters != nil)
    #expect(playlist.artwork == nil)
    #expect(MusicDiscovery.chartSections(items: [], source: .topSongs).isEmpty)
}

@Test func onlyNativePreparationFailuresAllowAQueueRetry() {
    let preparation = NSError(domain: "MPMusicPlayerControllerErrorDomain", code: 6)
    let wrapped = NSError(domain: NSCocoaErrorDomain, code: 0, userInfo: [NSUnderlyingErrorKey: preparation])
    #expect(MusicFailure.isPreparationFailure(preparation))
    #expect(MusicFailure.isPreparationFailure(wrapped))
    #expect(!MusicFailure.isPreparationFailure(NSError(domain: "OtherError", code: 6)))
    #expect(!MusicFailure.isPreparationFailure(MusicTokenRequestError.developerTokenRequestFailed))
    #expect(MusicFailure.playbackMessage(for: preparation).contains("prepare this selection"))
}

@Test @MainActor func preparationRecoveryRetriesOnceAndLeavesSuccessfulPlaybackAlone() async throws {
    var events: [String] = []
    let failure = NSError(domain: "MPMusicPlayerControllerErrorDomain", code: 6)
    try await PlaybackRecovery.start(play: { events.append("play") }, prepareAgain: { events.append("prepare") })
    #expect(events == ["play"])
    events = []
    try await PlaybackRecovery.start(play: {
        events.append("play")
        if events.count == 1 { throw failure }
    }, prepareAgain: { events.append("prepare") })
    #expect(events == ["play", "prepare", "play"])
    events = []
    do {
        try await PlaybackRecovery.start(play: { events.append("play"); throw failure },
                                         prepareAgain: { events.append("prepare") })
        Issue.record("Expected the second preparation failure to reach the UI")
    } catch { #expect((error as NSError).code == 6) }
    #expect(events == ["play", "prepare", "play"])
    events = []
    do {
        try await PlaybackRecovery.start(play: { events.append("play"); throw MusicTokenRequestError.developerTokenRequestFailed },
                                         prepareAgain: { events.append("prepare") })
        Issue.record("Expected authorization failure")
    } catch { #expect(error as? MusicTokenRequestError == .developerTokenRequestFailed) }
    #expect(events == ["play"])
}

@Test @MainActor func failedSelectionRestoresOnceAndPreservesItsOriginalError() async {
    var events: [String] = []
    let failure = NSError(domain: "MPMusicPlayerControllerErrorDomain", code: 6)
    do {
        try await PlaybackRecovery.start(play: { events.append("play"); throw failure },
            prepareAgain: { events.append("prepare-selection") }, restore: { error in
                #expect((error as NSError).code == 6)
                events.append("restore-previous")
            })
        Issue.record("Expected the selection error")
    } catch {
        #expect((error as NSError).domain == "MPMusicPlayerControllerErrorDomain")
        #expect((error as NSError).code == 6)
    }
    #expect(events == ["play", "prepare-selection", "play", "restore-previous"])
}

@Test func featuredPagePreservesShelvesAndFiltersUnsupportedContent() throws {
    let html = #"<html><script type="application/json" id="serialized-server-data">{"data":[{"data":{"sections":[{"items":[{"title":"Top mix","subtitle":"Apple Music","contentDescriptor":{"kind":"playlist","identifiers":{"storeAdamID":"pl.mix"}}}]},{"header":{"item":{"titleLink":{"title":"New This Week"}}},"items":[{"titleLinks":[{"title":"New album"}],"subtitleLinks":[{"title":"Artist"}],"contentDescriptor":{"kind":"album","identifiers":{"storeAdamID":"123"}}},{"title":"Artist page","contentDescriptor":{"kind":"artist","identifiers":{"storeAdamID":"124"}}},{"title":"Unavailable","isDisabled":true,"contentDescriptor":{"kind":"album","identifiers":{"storeAdamID":"125"}}}]}]}}]}</script></html>"#
    let sections = try MusicDiscovery.decodeFeatured(Data(html.utf8))
    #expect(sections.map(\.title) == ["Featured", "New This Week"])
    #expect(sections[1].items.count == 1)
    guard case .album(let album) = try #require(sections[1].items.first) else { Issue.record("Expected album"); return }
    #expect(album.artistName == "Artist")
    #expect(album.playParameters != nil)
    #expect(throws: MusicDiscovery.Failure.self) { try MusicDiscovery.decodeFeatured(Data("<html>Changed</html>".utf8)) }
}

@Test func recommendationsReportAuthorizationWithoutExposingDescriptions() {
    let error = NSError(domain: "ICError", code: -8200, userInfo: [NSLocalizedDescriptionKey: "private-session-placeholder"])
    let message = MusicDiscovery.message(for: error, source: .personal)
    #expect(message.contains("registered bundle ID"))
    #expect(!message.contains("private-session-placeholder"))
    #expect(!MusicDiscovery.message(for: error, source: .topSongs).contains("registered bundle ID"))
}
