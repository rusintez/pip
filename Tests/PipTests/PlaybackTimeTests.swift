import Testing
import Foundation
import MusicKit
@testable import Pip

@Test func playbackTimeHandlesStreamValues() {
    #expect(PlaybackTime.label(.nan) == "0:00")
    #expect(PlaybackTime.label(.infinity) == "0:00")
    #expect(PlaybackTime.label(-20) == "0:00")
    #expect(PlaybackTime.label(65.9) == "1:05")
    #expect(PlaybackTime.label(3665) == "1:01:05")
    #expect(PlaybackTime.clamped(-5, duration: 180) == 0)
    #expect(PlaybackTime.clamped(200, duration: 180) == 180)
    #expect(PlaybackTime.clamped(20, duration: .nan) == 0)
}

@Test func newerSearchInvalidatesInFlightPages() {
    var requests = LatestRequest()
    let firstSearch = requests.begin()
    let pageOfFirstSearch = requests.current
    let secondSearch = requests.begin()
    #expect(!requests.isCurrent(firstSearch))
    #expect(!requests.isCurrent(pageOfFirstSearch))
    #expect(requests.isCurrent(secondSearch))
}

@Test func playbackFailurePreservesServiceCauseWithoutLeakingContext() {
    let underlying = NSError(domain: NSCocoaErrorDomain, code: 4097)
    let error = NSError(domain: "MPMusicPlayerControllerErrorDomain", code: 10, userInfo: [
        NSUnderlyingErrorKey: underlying,
        NSLocalizedDescriptionKey: "sensitive-session-data",
        "account": "private-account-data"
    ])
    let message = MusicFailure.playbackMessage(for: error)
    #expect(message.contains("playback service disconnected"))
    #expect(message.contains("MPMusicPlayerControllerErrorDomain 10"))
    #expect(message.contains("NSCocoaErrorDomain 4097"))
    #expect(!message.contains("sensitive-session-data"))
    #expect(!message.contains("private-account-data"))
    #expect(!message.contains("Check your connection"))
}

@Test func playbackFailureSeparatesNetworkAndAppAuthorization() {
    let network = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
    #expect(MusicFailure.playbackMessage(for: network).contains("couldn’t reach the network"))
    #expect(MusicFailure.playbackMessage(for: MusicTokenRequestError.developerTokenRequestFailed)
        .contains("registered bundle ID"))
    #expect(MusicFailure.playbackMessage(for: MusicTokenRequestError.userNotSignedIn)
        .contains("Sign in to Apple Music"))
}

@Test func catalogAuthorizationDoesNotMislabelLibrarySearch() {
    let error = MusicTokenRequestError.developerTokenRequestFailed
    let catalog = MusicFailure.searchMessage(for: error, scope: .catalog)
    #expect(catalog.contains("authorize catalog search"))
    #expect(catalog.contains("search your Library"))
    let library = MusicFailure.searchMessage(for: error, scope: .library)
    #expect(!library.contains("registered bundle ID"))
    #expect(MusicSearchScope.library.placeholder == "Search your library")
}
