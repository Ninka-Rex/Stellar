# Stellar Download Manager - Changelog

---

## Version 0.10.5 Beta - June 19, 2026

### Improved
- Polished download complete dialog
- Tweaked icon sizes to be more consistent

### Fixed
- yt-dlp dialog quality picker dropdown not working
- Channel downloads not working

---

## Version 0.10.4 Beta - June 15, 2026

### New
- Bittorrent anonymous mode - hides your user agent and peer ID, not IP

### Improved
- Optimized the download engine to smoothly handle downloads up to 20 Gbps
- Download engine handling of 429 errors
- Improved handling of trackerless torrents and downloads via infohash

### Fixed
- Chromium browser integration not working on Linux
- Fixed a bug where delete and confirm buttons sometimes wouldn't show in the Delete dialog
- Fixed minor UI issues

---

## Version 0.10.3 Beta - June 11, 2026

FIREFOX USERS: Please update your browser extension! (Help > Browser Integration > Browser Extensions)

CHROME USERS: Please allow more time for Google to approve the update!

### New
- DHT now turns off when no torrents are active, no connections to bootstrap nodes

### Improved
- Refactored the Grabber to be more polished and consistent with the rest of the program

### Fixed
- Fixed missing translations in the torrent search engine
- Fixed some text not being wrapped in settings when using a foreign language
- Fixed open file / open folder buttons not working on Linux

---

## Version 0.10.2 Beta - June 11, 2026

FIREFOX USERS: Please update your browser extension!

CHROME USERS: Please allow more time for Google to approve the update!

You shouldn't be using Google Chrome anyway.

### New
- Batch download selected files in your browser by highlighting all links > Download with Stellar
- Status bar: click the speed limiter to open speed limiter settings
- Added polish to the batch download dialog
- Added Tasks > Add Batch URLs from Clipboard
- Added instructions to README.md on how to audit the browser extension code yourself

### Improved
- Improved the auto-updater to be more polished and verbose
- Greatly improved startup time, tons of optimizations to reduce CPU usage
- Updated Chrome and Firefox extensions to intercept downloads more accurately
- Updated libtorrent to 2.0.13

### Fixed
- Fixed minor security issues found by Claude Fable 5
- Selected downloads or torrents stay highlighted even if they move position in the file list during sorting
- Fixed an issue where duplicate downloads wouldn't be assigned numbered filenames
- Detatched the duplicate download dialog from the main window, so it doesn't open after an intercept
- Search box not being theme-aware
- Yt-dlp downloads not getting overwritten when asked to

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
