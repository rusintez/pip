# Pip interface

Native macOS app; familiar controls and a compact listening workflow take priority over decoration. Cider is the product reference; preserve the compact native player layout.

- System appearance, system typography and SF Symbols; coral accent for playback and the primary action.
- A 188-point navigation rail, flexible music list, optional 260-point playback queue, and an 88-point player.
- Artwork comes from MusicKit. Before connection, show an honest first-run state without invented library data.
- Songs display title, artist, album and duration. Search defaults to Library. The scope menu also offers public iTunes Store search (submitted on Return, with a country selector) and the full Apple Music catalog (requires MusicKit registration). iTunes results identify their source and country; do not show public preview clips as subscription playback.
- Native buttons, lists, focus, accessibility labels and sliders. Command-F searches; Command-P plays or pauses; Command-arrow keys change tracks.
- No webview, animated backgrounds or third-party UI dependencies. Only the active window samples elapsed playback time.
