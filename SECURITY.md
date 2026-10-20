# Security

Pip is experimental. Only the latest source and prerelease are maintained; there is no security response SLA.

Report vulnerabilities privately through this repository's **Security → Report a vulnerability** page. Do not post account credentials, session cookies, developer keys, MusicKit tokens, or raw account-specific error payloads in public issues.

Pip uses MusicKit for authorization and subscription playback. Public metadata requests use ephemeral sessions without stored cookies or credentials. The app does not extract Music.app sessions, download subscription audio, or implement its own DRM.

Current CI downloads are ad hoc signed and not notarized. Checksums detect damaged downloads but do not replace Developer ID signing, notarization, or a trusted distribution channel.
