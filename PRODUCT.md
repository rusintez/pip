# Product

<!-- impeccable:product-schema 1 -->

## Platform

Native macOS desktop app, macOS 14 and later.

## Stack

SwiftUI and MusicKit. No webview or third-party dependencies. Swift Package Manager runs the tests; the Xcode project builds the app bundle.

## Users

Mac users who want a small native player for their own Apple Music subscription.

## Product Purpose

A local Apple Music client with a lightweight interface, inspired by [Cider](https://cider.sh/).

## Capabilities and Constraints

Browse and search library songs and playlists, discover music, and play selections independently through MusicKit. Local library access and subscription playback have worked with ad hoc signing in development; distribution and account compatibility are not guaranteed. Catalog API search and personalized recommendations require registered MusicKit credentials. No developer team is selected automatically.

Public iTunes search identifies its source and country. It is not the complete Apple Music catalog. Public charts, editorial shelves, artist/album lookup, artwork, and song stations extend discovery without substituting preview clips for subscription playback. Public page parsing and Codable metadata adapters remain experimental.

Artist and album pages preserve playback and browsing history. Album Play queues the native album from the beginning; selecting a track starts there and continues in order. Preparation recovery retains the complete requested queue. Missing artwork, incomplete catalog coverage, and local tracks without public links have honest fallback states.

The current track's context menu offers native sharing, exact Apple Music links, and station lookup. A failed lookup leaves the existing queue unchanged. No library mutations, offline downloads, or custom DRM are implemented.

## Brand Commitments

Cider is a product reference, not an asset or source-code license. Pip uses original UI code and system iconography. Apple Music content and artwork retain their respective owners' rights.

## Product Principles

- Prefer native platform APIs and controls.
- Keep playback controls available while browsing.
- Make authorization, loading, empty, and error states honest.
- Keep dependencies and background work minimal.
- Keep credentials, personal library data, and build products out of source control.
