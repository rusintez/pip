# Pip

[![CI](https://github.com/rusintez/pip/actions/workflows/ci.yml/badge.svg)](https://github.com/rusintez/pip/actions/workflows/ci.yml)

A small, native macOS Apple Music player. SwiftUI + MusicKit, macOS 14+, no webview or third-party dependencies. Inspired by [Cider](https://cider.sh/), with an independent implementation.

**Experimental:** library browsing and independent subscription playback have worked in local testing with ad hoc signing. This is not a guarantee for every Mac. Full catalog API search and personalized recommendations require a registered MusicKit App ID.

## Features

- Browse and search your library and playlists.
- Search the public iTunes Store, with a selectable country.
- Explore Top Songs, Popular Playlists, and New & Featured.
- Open artist and album pages, with cover art before playback.
- Play an album from the beginning or a selected track, with a persistent queue.
- Start a song station, copy an Apple Music link, or open the native sharing picker.
- Play/pause, skip, seek, and select queued tracks while browsing.
- Native macOS controls, system appearance, and accessibility labels.

Apple Music streaming requires your own active subscription and account authorization. Pip does not include library editing, offline downloads, lyrics, an equalizer, or lossless/Atmos controls.

## Build and run

Requires macOS 14+ and Xcode 16+ with Swift 6. Swift Package Manager is already configured; CocoaPods and Carthage are not needed.

```sh
git clone https://github.com/rusintez/pip.git
cd pip
sh scripts/run.sh
```

The script builds the app bundle, signs it ad hoc, and opens it. It stops the previous local Pip instance before replacing its executable. Alternatively, open `Pip.xcodeproj`, select **Pip → My Mac**, and run. No developer team or signing certificate is selected by default.

Sign in to Apple Music on your Mac, enable Sync Library, then choose **Connect to Apple Music** in Pip and allow music access. Building and opening the UI does not require a paid developer account. A bare `swift run` executable lacks the app bundle's music usage description; use the bundled app.

### MusicKit registration

For catalog API search and **For You** recommendations:

1. Use an authorized Apple Developer Program team.
2. Register a unique explicit bundle ID and enable its **MusicKit** app service.
3. Set the same bundle ID in Xcode, choose your team, and use Apple Development signing.
4. Rebuild, authorize music access, and connect your subscription.

MusicKit manages its tokens. Do not paste keys, passwords, or tokens into the source or issues. Registering MusicKit is separate from signing and notarizing a distributable app.

Apple references: [MusicKit setup](https://developer.apple.com/help/account/services/musickit), [automatic token generation](https://developer.apple.com/documentation/musickit/using-automatic-token-generation-for-apple-music-api).

## Using Pip

Search defaults to **Library**. Select **iTunes** for public store search and press Return or Search; **Catalog** uses the registered Apple Music API. Clearing the query returns to the current library view. iTunes search returns up to 100 results; library lists load in pages. Playing a song queues the songs currently loaded in that view.

Click the now-playing artist to open an artist page, or the title/artwork to open its album. Artist pages show Top Songs and Albums. Album **Play** starts the native album queue; a track row starts that album at the selected song and continues in order. **Back** or Command-[ follows browsing history.

Right-click the now-playing area for **Show Artist**, **Show Album**, **Start Station**, **Copy Apple Music Link**, and **Share Song…**. Unlinked local or uploaded tracks cannot use catalog-specific actions. Station lookup leaves playback controls available; a newer selection or transport command discards its pending result.

| Shortcut | Action |
| --- | --- |
| Command-F | Search |
| Command-P | Play/pause |
| Command-Left / Command-Right | Previous/next track |
| Command-[ | Back |

## Public metadata and limitations

Public search uses [Apple's iTunes Search API](https://performance-partners.apple.com/search-api), which searches the iTunes Store rather than the complete Apple Music catalog. Artist lookup returns up to 50 songs/albums; album lookup returns up to 200 tracks in disc/track order. The browsing country may differ from your subscription's storefront and availability.

Charts use [Apple's public RSS feeds](https://rss.marketingtools.apple.com/). New & Featured and song station lookup depend on serialized metadata from public Apple Music pages. These page formats are undocumented and can change. The bridge from public IDs to MusicKit resources is also experimental. **For You** uses native personalized recommendations, and reports a registration failure rather than substituting charts.

MusicKit performs subscription playback. Pip does not use preview clips as full songs, extract Music.app credentials, or download subscription audio. Public metadata requests use ephemeral sessions without stored cookies or credentials. Artwork loads from Apple's CDN when supplied; missing artwork retains a placeholder. There is no Pip account or analytics backend.

## Tests and CI

```sh
swift test
bash scripts/package.sh 0.1.0
```

The 24 fixture-based tests cover decoding, artwork, ID mapping, ordering, request validation, playback recovery, and sanitized errors. They do not sign in to Apple Music or verify live subscription playback.

[GitHub Actions](https://github.com/rusintez/pip/actions) runs tests and builds a Release app for Apple Silicon and Intel on pushes and pull requests. CI uses Xcode 16.4 on macOS 15, with actions pinned to commit hashes. Build ZIPs and SHA-256 checksums are retained as workflow artifacts for 14 days. Dependabot checks action updates weekly.

## Releases

[Tagged prereleases](https://github.com/rusintez/pip/releases) provide a universal macOS ZIP and SHA-256 checksum. **Current downloads are ad hoc signed, not Developer ID signed or notarized.** macOS Gatekeeper may block them; building from source is recommended. Playback on another Mac remains unverified.

Packaged releases use `io.github.rusintez.pip`; local development uses `local.pip.player`. macOS treats them as separate apps for music authorization. Neither identifier has MusicKit registration supplied by this repository.

To publish a release, a maintainer pushes an annotated `vMAJOR.MINOR.PATCH` tag after checks pass. The tag workflow reruns tests, embeds the tag's version and CI build number, verifies both architectures and the ad hoc signature, packages the app, and publishes an explicitly experimental prerelease. Build products and signing credentials stay out of Git.

For normal end-user distribution, configure a Developer ID certificate, hardened runtime signing, and [Apple notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution). These require separate developer setup and are not configured in this repository. CocoaPods is a library dependency manager, not an app distribution channel; a ZIP is sufficient for this initial release process.

## Troubleshooting

- **Catalog / For You authorization error:** configure the registered MusicKit bundle ID, or use Library and public iTunes search.
- **Playback service disconnected:** quit and reopen Pip. Do not rebuild or sign the running app in place. The local runner handles this.
- **Preparation error 6:** Pip retries the complete queue once, then restores the previous song queue on failure. Availability and album editions can differ; the error alone does not establish its cause.
- **Missing library items:** check music access and Sync Library in Music.app, then refresh Pip.

Debug builds accept `--pip-test-slow-station` for a five-second station lookup delay during loading/cancellation checks. Release builds ignore it.

## Contributing and license

See [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md). Source code is licensed under [MIT](LICENSE). Apple Music, MusicKit, and catalog artwork belong to their respective owners. Pip is independent and is not affiliated with Apple or Cider.
