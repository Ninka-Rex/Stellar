# 🌌 Stellar Download Manager

An open source download manager for Windows and Linux, inspired by IDM. Built with Qt 6 and QML

![Screenshot](screenshots/preview.webp)

## What it does

* **Parallel segmented downloads** - Opens multiple connections to the same file simultaneously, each fetching a different chunk, which saturates your actual bandwidth instead of the server's per-connection limit
* **Resume** - interrupted downloads pick up where they left off
* **Speed limiter** - global or per-download bandwidth cap
* **Browser integration** - Firefox/Chrome extension intercepts downloads and hands them off to Stellar, including cookie pass-through for authenticated downloads (Google Drive etc)
* **Categories** - auto-assigns downloads to categories (Videos, Music, Documents, etc) by file extension or site pattern. Each category can have its own save folder. User-created categories supported
* **Download queue** - Configurable concurrency limit, move items up/down, drag onto sidebar categories to reassign

## Status

Currently work in progress

## License

[GPL v3.0](LICENSE)
