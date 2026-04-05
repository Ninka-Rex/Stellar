# Stellar Download Manager

An open source download manager for Windows and Linux, inspired by IDM. Built with Qt 6 and QML — no Electron, no web views, no bloat.

![screenshot placeholder]

## What it does

- **Parallel segmented downloads** — most servers throttle individual connections, so a single-connection download is artificially slow. Stellar opens multiple connections to the same file simultaneously, each fetching a different chunk, which saturates your actual bandwidth instead of the server's per-connection limit. Especially noticeable on fast connections downloading from rate-limited hosts.
- **Resume** — interrupted downloads pick up where they left off. Stores per-segment offsets in a `.stellar-meta` sidecar so nothing is re-downloaded.
- **Speed limiter** — global or per-download bandwidth cap with a token-bucket throttle.
- **Browser integration** — Firefox/Chrome extension intercepts downloads and hands them off to Stellar, including cookie pass-through for authenticated downloads (Google Drive etc).
- **Categories** — auto-assigns downloads to categories (Videos, Music, Documents, etc) by file extension or site pattern. Each category can have its own save folder. User-created categories supported.
- **Download queue** — configurable concurrency limit. Move items up/down, drag onto sidebar categories to reassign.
- **Persistent history** — download list survives restarts. JSON-based, no database.
- **System tray** — minimize to tray, tray context menu.

## Building

**Requirements:** Qt 6.5+, CMake 3.21+. Qt modules needed: QtQuick, QtQuick.Controls (Material), QtQuick.Dialogs, QtNetwork.

```bash
# Windows
cmake --preset windows-debug
cmake --build --preset windows-debug
./build/windows-debug/Stellar.exe

# Linux
cmake --preset linux-debug
cmake --build --preset linux-debug
```

No installer yet. Just run the exe from the build directory.

## Browser extension

The extension is in `extensions/`. Load it as an unpacked extension, then run Stellar once to auto-register the native messaging host. After that, downloads intercepted by the browser get sent to Stellar automatically.

Works with Firefox and Chrome/Chromium-based browsers.

## Tech notes

- Pure Qt 6 — `QGuiApplication`, no widgets anywhere
- QML frontend with Material Dark theme
- `QNetworkAccessManager` with parallel `Range:` requests
- JSON persistence via `QJsonDocument`, no Qt SQL

## Status

Usable for daily use. Active development.

**Not implemented yet:**
- Retry with exponential backoff (settings are wired, logic is not)
- Scheduler, FTP/SFTP, proxy per download

## License

[GPL v3.0](LICENSE)
