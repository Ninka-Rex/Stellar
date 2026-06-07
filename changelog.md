# Stellar Download Manager - Changelog

---

## Version 0.10.1 Beta - June 7, 2026

### Improved
- The main window now stays hidden when Stellar cold-starts to handle an intercepted download

### Fixed
- Linux: file picker and save dialogs now use the native desktop picker
- Linux: "Grant permission" for Flatpak Firefox no longer fails with an OpenSSL version mismatch

---

## Version 0.10.0 Beta - June 7, 2026

### New
- Light and dark mode with theme toggle in the View menu
- FTP and FTPS protocol support
- Torrent file download priority - set Low, Normal, High, or Maximum per file
- Status bar can now show total peer connections and DHT nodes (Options > General)
- Loading progress bar on startup
- Metadata description auto-fill for video, image, and raw file downloads

### Improved
- HTTP download progress dialog redesigned
- VPN network adapter binding hardened
- Libtorrent settings tuned for faster seeding
- Removed Microsoft Visual C++ Redistributable from the Windows installer
- Torrent name now updates when you rename the root folder

### Fixed
- Torrent speed sawtooth pattern
- Text cut off in statistics and grabber dialogs when using foreign languages
- Category panel widths shifting when switching between selections
- Download table column headers truncated too early
- File info and download complete dialogs missing their own taskbar buttons
- Queue dropdown menu padding and alignment

### Removed
- Removed DHT online user estimation

---

## Version 0.9.0 Beta - June 1, 2026

### New
- Import and export file list, settings, torrents, share ratios, etc in Options > General > Backup & Restore
- Options > Media: choose a default browser for yt-dlp cookie authentication, skipping the prompt on auth-required downloads

### Improved
- Improved download engine handling of PDFs

### Fixed
- Fixed "Restart Now" not working when changing language
- Fixed some incorrect translations
- Fixed the toolbar not being translated

---

## Version 0.8.2 Beta - May 28, 2026

### New
- Ability to import and export file list, queues, and selected downloads (compatible with IDM .ef2 format)
- Settings to stop all torrents on startup
- Lots of new keyboard shortcuts

### Improved
- Status Bar emojies now use SVG icons for consistency across linux distros
- Improved performance of part file pre-allocation
- Improved yt-dlp downloader
- Minor UI improvements

### Fixed
- Fixed tons of miscellaneous bugs

---

## Version 0.8.1 Beta - May 21, 2026

### Important: This release breaks the auto-update feature. A manual update is required.

### New
- Toolbar customization - Click View > Toolbar to add/remove/rearrange buttons
- New keyboard shortcuts, Ctrl+D download, Ctrl+Q scheduler, and more
- UI scale and font size controls in Settings > General
- Browser cookie import, Stellar uses cookies from Chrome/Firefox when manually adding downloads like IDM
- Verify Local Data on torrents from the right-click menu

### Improved
- Status bar now shows running, seeding, paused, and checking counts
- New icons
- Speed limiter settings streamlined
- Grabber results dialog visual overhaul
- Downloading torrents sort to top when status column is active

### Fixed
- VPN binding on Linux
- Geo IP database auto-discovers filename (no more hardcoded date)
- Resume button not enabled on errored downloads
- Sidebar hide not expanding download table
- Last try date not set for yt-dlp downloads
- Torrent seeders always showing as 0

---

## Version 0.8.0 Beta - May 14, 2026

### New
- **New!** 77 languages supported, with a language picker in Settings
- **New!** Torrent creator -create `.torrent` files directly from the app
- **New!** Command line interface - download URLs, set save paths, control the queue scheduler
- **New!** Pause and resume the entire session from the tray menu

### Improved
- Download Progress, Download Complete, and Add URL dialogs redesigned to be closer to IDM
- Speed chart in torrent properties improved
- General performance and security improvements
- New icons

---

## Version 0.7.1 Beta - April 25, 2026

- Initial release
