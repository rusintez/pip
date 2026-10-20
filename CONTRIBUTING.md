# Contributing

Pip is a small native macOS app. Keep changes focused, use system controls, and avoid adding a package when the platform already provides the functionality.

Use Xcode 16+ with Swift 6 and macOS 14+. Build the app with `sh scripts/run.sh`; a bare `swift run` executable is not a substitute for the app bundle and its music usage description. See [the README](README.md) for authorization and MusicKit registration limits.

Before opening a pull request:

```sh
swift test
bash scripts/package.sh 0.1.0
```

The tests use fixtures and do not require an Apple Music account. For a UI or playback change, also try the bundled app and describe the macOS/Xcode version, music source, and behavior you verified. Keep account details, tokens, personal library screenshots, and raw MusicKit error payloads out of issues and pull requests.

`Package.swift` owns the test target. `Pip.xcodeproj` builds the app bundle and has an explicit source list, so add new app source files to both when necessary. Commit the Xcode project and shared scheme. Do not commit build products, user-specific Xcode state, signing files, or provisioning profiles. If dependencies are added, use Swift Package Manager and commit the app's resolved dependency lockfile.

Public metadata adapters depend on Apple-controlled formats. Add a small fixture regression test when changing decoding, ordering, ID mapping, or failure handling. Preserve native subscription playback and the current queue on lookup failures.

Contributions are accepted under the project's [MIT license](LICENSE).
