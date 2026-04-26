# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Coding Standard

**Fully implement all changes** — no shortcuts, no stubs, no placeholders. Code must be production-ready. Comment *why* not *what*; explain non-obvious parts but avoid over-commenting.

## Build & Development

**Build the project (quick start):**
```bash
cmake --preset windows-debug    # or linux-debug
cmake --build --preset windows-debug
# Output: build/windows-debug/Stellar.exe (or platform-specific)
```

**Manual configuration (if presets fail):**
```bash
cmake -B build -S . -G "Ninja Multi-Config" -DCMAKE_PREFIX_PATH=<Qt6_install_path>
cmake --build build --config Debug
```

Note: Builds use Ninja generator; ensure `ninja` is in PATH. On Windows, MSVC 2022 or later is required.

**Install Qt6:**
- Windows: Download from https://www.qt.io/ or use `vcpkg install qt6`
- Linux: `sudo apt install qt6-base-dev qt6-declarative-dev`

**Optional: libtorrent support**
- A vendored source tree at `third_party/libtorrent-rasterbar-2.0.12` is included and auto-detected by CMake — no install needed. To use an external install instead: set `LIBTORRENT_SOURCE_DIR`, `LIBTORRENT_ROOT`, or `LibtorrentRasterbar_DIR`. Set `ENABLE_LIBTORRENT=OFF` to disable entirely. CMake sets `STELLAR_HAS_LIBTORRENT=1` when found; without it, torrent/magnet downloads are disabled but everything else works.

**Key build files:**
- `CMakeLists.txt` - Qt6/CMake configuration. Resources (icons, tips.txt, QML files) must be listed in the `qt_add_qml_module()` section
- Build output: `build/windows-debug/` (or platform-specific)

## Architecture

**Backend (C++, Qt 6):**
- `app/src/StellarPaths.{h,cpp}` - **Single source of truth for every on-disk path.** All writable data lives under one root: `%LOCALAPPDATA%\Stellar\` (Windows) / `$XDG_DATA_HOME/Stellar/` (Linux). Sub-directories: `data/` (JSON databases), `resume/` (per-torrent fast-resume blobs), `plugins/search/` (torrent search plugins), `bin/` (yt-dlp/ffmpeg), `geo/` (MaxMindDB), `cache/` (Qt RHI pipeline + QML bytecode caches). **Any new file path must go through this namespace** — never use `QStandardPaths` directly for writable app data. `migrateIfNeeded()` runs once at startup to move data from the legacy `StellarDownloadManager/` layout.
- `app/src/AppController.{h,cpp}` - Main application logic, signals/slots, settings integration
- `app/src/AppSettings.{h,cpp}` - Persistent settings via `QSettings` in INI format at `StellarPaths::settingsFile()`. **Not** native registry or `QStandardPaths` — always use `QSettings(StellarPaths::settingsFile(), QSettings::IniFormat)` when opening settings outside `AppSettings` (e.g. in `main.cpp` native messaging handler).
- `app/src/DownloadTableModel.{h,cpp}` - QAbstractTableModel for downloads, filter/sort, custom roles
- `app/src/DownloadQueue.{h,cpp}` - Queue state machine, scheduleNext() orchestrates concurrent downloads
- `app/src/DownloadItem.{h,cpp}` - Single download state (progress, speed, segments, metadata)
- `app/src/SegmentedTransfer.{h,cpp}` - Multi-segment HTTP download engine (range requests, reassembly)
- `app/src/CategoryModel.{h,cpp}` - QAbstractListModel for categories, drag-reorder support
- `app/src/Queue.{h,cpp}` / `QueueDatabase.{h,cpp}` / `QueueModel.{h,cpp}` - Named download queues with persistence and QML list model
- `app/src/DownloadDatabase.{h,cpp}` - JSON persistence for download list (`StellarPaths::downloadsFile()`). Torrent fast-resume blobs are stored in separate `resume/<id>.resume` files — never inline in `downloads.json`. Writes are debounced via a 500 ms `QSaveFile`-based timer.
- `app/src/NativeMessagingHost.{h,cpp}` - Browser extension IPC (length-prefixed JSON over stdin/stdout)
- `app/src/SystemTrayIcon.{h,cpp}` - Tray icon; right-click → context menu, double-click → show window
- `app/src/FileIconImageProvider.{h}` - QQuickAsyncImageProvider for file-type icons; caches by full path then extension; requires COM STA init per thread on Windows
- `app/src/FileDragDropHelper.{h,cpp}` - Exposes drag-initiation to QML for dragging files out of the app
- `app/src/YtdlpManager.{h,cpp}` - Manages the yt-dlp binary: auto-detection, download/update, version checking. Also detects a JS runtime (Deno, Node.js, Bun, or QuickJS) via `detectJsRuntime()`; exposes `jsRuntimeAvailable`, `jsRuntimePath`, `jsRuntimeName` properties. The JS runtime path can be user-overridden via `setCustomJsRuntimePath()` / `AppSettings::ytdlpJsRuntimePath`.
- `app/src/YtdlpTransfer.{h,cpp}` - Drives a single yt-dlp subprocess; parses stdout progress lines; handles multi-phase video+audio downloads with accumulated progress across phases. Passes `--js-runtimes <name>` to yt-dlp when a JS runtime is detected.
- `app/src/TorrentSessionManager.{h,cpp}` - Wraps libtorrent session (optional; enabled when `STELLAR_HAS_LIBTORRENT` is defined). Handles magnet/torrent-file adds, pause/resume/remove, save-resume-data, and exposes per-download `TorrentFileModel`, `TorrentPeerModel`, `TorrentTrackerModel` instances. `available()` returns false when built without libtorrent so callers degrade gracefully. Alert polling runs on a 1 s `QTimer`; `post_torrent_updates()` drives status refreshes. Also manages share-limit enforcement (`checkShareLimits()`), geo-IP lookup via optional MaxMindDB (`STELLAR_HAS_MAXMINDDB`), network interface binding (`torrentBindInterface` setting), and peer banning (manual + auto-ban rules via `banPeer()`/`unbanPeer()`, `bannedPeers()`, `refreshPeerBanRules()`).
- `app/src/TorrentSearchManager.{h,cpp}` - Torrent search subsystem. Uses Python search plugins (stored in `pluginDirectory()`) to search torrent indexes. Auto-detects Python at startup. Plugins are installed from `.py` files or URLs. Exposes `TorrentSearchPluginModel` and `TorrentSearchResultModel` to QML. `search(query)` spawns a Python subprocess and streams JSON results. `resolveResultLink(row, preferMagnet)` extracts the magnet/torrent URL from a result.
- `app/src/TorrentSearchPluginModel.{h,cpp}` / `TorrentSearchResultModel.{h,cpp}` - List models for the search plugin list and live search results respectively.
- `app/src/TorrentFileModel.{h,cpp}` - Tree-structured `QAbstractListModel` for torrent files. Internally stores a folder/file node tree; `m_visibleRows` is a flat list of expanded nodes. Supports `toggleExpanded()` for folder collapse, `setWanted()`/`applyWantedRecursive()` to include/exclude files, and `updateProgress()` for live byte-level progress. `setLiveUpdatesEnabled(false)` suspends all updates (used when the dialog is hidden).
- `app/src/TorrentPeerModel.{h,cpp}` - Incremental-update `QAbstractListModel` for peers. Peer identity is `endpoint|port` only — client/seed-state are not part of the key. Uses a grace-tick system (`kPeerRemovalGraceTicks = 3`) so briefly-absent peers don't flicker in/out. Exposes `setStructuralUpdatesDeferred(true)` to suppress row inserts/removes while the user is scrolling (only data-changed signals fire); deferred structural updates flush when set back to false. Also carries local-node location properties (`localLatitude/Longitude`, `localIp`, `localPort`, `localCountryCode`) for the world-map overlay.
- `app/src/TorrentTrackerModel.{h,cpp}` - Simple list model for tracker entries; each entry carries URL, status, tier, seeder/peer counts, geo coordinates, and country code for map display.
- `cmake/GenerateBuildTime.cmake` - Runs at build time (not configure time) via `add_custom_target`; writes `AppBuildTime.h` with accurate UTC timestamp
- `cmake/FindLibtorrentRasterbar.cmake` - CMake find-module for the optional libtorrent-rasterbar dependency; sets `STELLAR_HAS_LIBTORRENT`

**QML Frontend:**
- `app/qml/Main.qml` - Root window, tips system, tray integration, menu bar with `CompactMenuItem` component, speed schedule timer logic (`runSpeedScheduleCheck()`), `whatsNewDialog` window
- `app/qml/DownloadTable.qml` - Main download list with multi-select, column definitions, drag-drop to categories
- `app/qml/Sidebar.qml` - Category list, queue list, section drag-reorder, insert-line visual feedback
- `app/qml/SettingsDialog.qml` - Tabbed settings with Apply/Cancel, dirty tracking. Tab indices: 0=Connection, 1=Categories, 2=Downloads, 3=Browser, 4=Speed Limiter, 5=Notifications, 6=General, 7=Media, 8=Torrents, 9=About
- `app/qml/YtdlpDialog.qml` - Video format/quality picker shown when a yt-dlp URL is intercepted
- `app/qml/SchedulerDialog.qml` - Queue scheduler window (separate from settings); start/stop times, day selection, concurrency, shutdown actions
- `app/qml/DownloadProgressDialog.qml` - Per-download details, segment breakdown, speed limit override
- `app/qml/DownloadCompleteDialog.qml` - Shown after a download finishes; allows opening, revealing in folder, or drag-out of the completed file. Controlled by `AppSettings::showDownloadComplete`.
- `app/qml/DownloadFileInfoDialog.qml` - Shown while file metadata is being fetched (pending download state); lets the user confirm save path before the download starts.
- `app/qml/FilePropertiesDialog.qml` - Properties window for any download (HTTP/FTP/torrent). For torrents: shows info hash, transfer stats, per-torrent speed limits, and an inline peer-info popup. Includes right-click rename context menu for files with `TapHandler` pattern. Peer rows have a hover "info" button that opens `peerInfoDialog` (inline `Popup`, not a separate `Window`).
- `app/qml/TorrentMetadataDialog.qml` - Torrent-specific details window (files, peers, trackers tabs); only shown when opening properties on torrent/magnet downloads. Uses `TapHandler` for right-click file rename
- `app/qml/Toolbar.qml` / `app/qml/ToolbarBtn.qml` / `app/qml/ToolbarDropdown.qml` - Toolbar; all buttons are `width:84, height:62`
- `app/qml/DlgButton.qml` - **Shared button component** used by all dialogs. Props: `primary` (blue), `destructive` (red), default = secondary (grey). Always use this instead of inline `Button` styling.
- Other dialogs: `AddUrlDialog.qml`, `BatchDownloadDialog.qml`, etc.

**Grabber Subsystem (web crawler):**
- `app/src/GrabberCrawler.{h,cpp}` - Async BFS web crawler using `QNetworkAccessManager`; crawls pages up to a configured depth, extracts file links matching include/exclude wildcard patterns, then probes file sizes via HEAD requests (up to 4 concurrent). Emits `resultFound` per file and `finished` when done.
- `app/src/GrabberProjectModel.{h,cpp}` - `QAbstractListModel` for saved crawl projects; persists to a JSON file on disk (`projectsFilePath()`). Use `upsertProject()` / `removeProject()` / `moveProject()` from QML.
- `app/src/GrabberResultModel.{h,cpp}` - `QAbstractListModel` that holds live crawl results for one run; fed by `GrabberCrawler` signals.
- `app/qml/GrabberDialog.qml` - Main grabber UI (project list + run controls).
- Other `Grabber*.qml` dialogs: settings, filters, schedule, results, statistics, project picker.

**Browser Extensions:**
- `extensions/shared/{interceptor.js, messaging.js}` - Shared download detection, filter matching, settings sync
- `extensions/chrome/{service-worker.js, content.js}` - Chrome MV3 implementation, modifier key tracking
- `extensions/firefox/{service-worker.js, content.js}` - Firefox implementation (same logic, `browser` API instead of `chrome`)

**Configuration:**
- `tips.txt` - One tip per line, displayed in status bar (cycles every 6 hours)
- `packaging/flatpak/` - Flatpak manifest

## Key Patterns & Concepts

**Q_PROPERTY & Signals:**
- Backend settings use `Q_PROPERTY()` with NOTIFY signals → auto-update QML bindings
- Example: `Q_PROPERTY(int globalSpeedLimitKBps READ globalSpeedLimitKBps WRITE setGlobalSpeedLimitKBps NOTIFY globalSpeedLimitKBpsChanged)`

**Q_INVOKABLE:**
- Expose C++ methods to QML: `Q_INVOKABLE DownloadItem *itemAt(int row) const;`
- Used for DownloadTableModel methods (filter, sort, itemAt) and AppController (download management)

**QAbstractTableModel & QAbstractListModel:**
- DownloadTableModel: `rowCount()`, `columnCount()`, `data()`, `headerData()` with custom roles (ItemRole, ProgressRole)
- Emit `dataChanged()`, `beginResetModel()`/`endResetModel()` for filter/sort operations
- ModelIndex column maps to enum Column (ColFilename, ColSize, ColProgress, etc.)

**QML MouseArea & Event Stealing:**
- Overlapping MouseAreas can steal events from underlying handlers
- Solution: Use `preventStealing: false` to release control, `Qt.callLater()` for deferred state cleanup
- Capture variables before deferred callback: `var dragFrom = root._catDragFrom` (QML scope issues)

**Native Messaging Protocol:**
- JSON messages: `{ type: "download", url, filename, referrer, cookies, modifierKey }`
- Length-prefixed: 4-byte little-endian uint32 + JSON bytes
- Browser extension detects `modifierKey` (0=none, 1=alt, 2=ctrl, 3=shift) to bypass interception

**Settings Synchronization:**
- AppSettings reads/writes QSettings file (Windows: registry fallback)
- Browser extension caches settings for 5 seconds, syncs on demand from native host
- New settings must be added to: AppSettings.h (Q_PROPERTY, getter, setter, signal), AppSettings.cpp (load/save), SettingsDialog.qml (UI + dirty tracking)
- `launchOnStartup` writes to `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` on Windows or `~/.config/autostart/stellar.desktop` on Linux via `applyStartupRegistration()`

**Pending Download Flow (two-step add):**
- `beginPendingDownload()` — fetches file info (name, size, type) and returns a `downloadId`; download is held in limbo
- `finalizePendingDownload()` — confirms save path/category/queue and starts it; call `discardPendingDownload()` to cancel

**yt-dlp Download Flow (video/audio URLs):**
- `AppController::isLikelyYtdlpUrl(url)` — heuristic check; if true, Main.qml opens `YtdlpDialog` instead of `AddUrlDialog`
- `YtdlpDialog` emits `downloadRequested(url, formatId, containerFormat, saveDir, outputTemplate)` — no pending item is created beforehand
- `AppController::finalizeYtdlpDownload()` creates the `DownloadItem` itself (avoids ghost entries), then calls `startYtdlpWorker()`
- `YtdlpTransfer` passes `--proxy <url>` explicitly to yt-dlp since yt-dlp doesn't inherit Qt's application proxy
- When `YtdlpManager::jsRuntimeAvailable()` is true, `YtdlpTransfer` adds `--js-runtimes <name>` to the yt-dlp command so sites requiring a JS runtime (e.g. YouTube PO token extraction) work automatically
- Filename is reconciled post-download via filesystem scan (`QDir::entryInfoList` sorted by time) because yt-dlp stdout may have CP1252/UTF-8 encoding issues on Windows that corrupt non-ASCII filenames

**Proxy:**
- `AppSettings::proxyType` — 0=None, 1=System, 2=HTTP/HTTPS, 3=SOCKS5
- `AppController::applyProxy()` — called at startup and on every proxy setting change; sets both `QNetworkProxy::setApplicationProxy()` and `m_nam->setProxy()` directly (the latter is required — setting only the application proxy is not always picked up by an already-constructed NAM)
- `App.proxyActive` Q_PROPERTY drives the `🌐 Proxy enabled` status bar indicator

**Speed Limiter Scheduler:**
- Rules stored as JSON in `AppSettings::speedScheduleJson` — array of `{ days[], onHour, onMinute, onAmPm, offHour, offMinute, offAmPm, limitKBps }`
- `runSpeedScheduleCheck()` in `Main.qml` evaluates rules every 60 s (timer) AND immediately when `speedScheduleEnabled` or `speedScheduleJson` changes via `Connections`
- Overnight ranges handled: if `onTime > offTime`, the active window wraps midnight

**Clipboard Monitoring:**
- Enabled via `AppSettings::clipboardMonitorEnabled`; `AppController` connects to `QClipboard::dataChanged`
- Filters by `monitoredExtensions`; emits `clipboardUrlDetected(url)` signal (deduplicated via `m_lastClipboardUrl`)
- `Main.qml` catches the signal and opens `AddUrlDialog` with `titleOverride` set

**Download State Machine:**
- Status: Queued → Downloading → Paused/Completed/Failed
- Speed limiter, resume, and segmentation all thread-safe via Qt signals/slots
- DownloadQueue manages concurrency (maxConcurrent), calls SegmentedTransfer::start()

## SegmentedTransfer Engine Invariants

These are non-obvious rules the engine depends on. Breaking any of them silently corrupts downloads or hangs the UI.

**Mandatory request headers** (`applyRequestHeaders()`):
- `Accept-Encoding: identity` is **required**. Qt's QNAM auto-decompresses gzip, which makes `Content-Range` and byte offsets lie — range math breaks and files end up truncated or corrupted. Never remove this header.
- `Referer` is sent from `m_item->referrer()` when set (browser extension captures it). Many hosts (Rapidgator, image CDNs) 403 without it.
- HEAD requests use `req.setTransferTimeout(15'000)` so a dead host can't hang the item in the Queued state forever.

**Per-segment retry** (`retrySegment`, `kMaxSegmentRetries = 4`):
- Exponential backoff 1s/2s/4s/8s, honoring `Retry-After` when the server sends it.
- 4xx (except 408/429) = permanent, fails the segment immediately. 408/429/5xx = retriable.
- `Segment::retryCount` resets only on successful completion.

**Stall detection** (`onProgressTick`, `kStallTimeoutMs = 30'000`):
- Every segment stamps `lastByteTime` on readyRead. If no bytes arrive within 30s, the tick aborts+retries that segment. This is the *only* thing catching half-open TCP connections — do not remove.

**206 vs 200 fallback** (`onSegmentReadyRead`):
- First chunk validates `Content-Range`: `start` must equal the segment's expected start and `total` must equal `m_item->totalBytes()`.
- If the server returns 200 instead of 206 (ignored the Range header), `fallbackToSingleSegment()` collapses to one segment starting from 0. Don't try to "fix" this by assuming range support.

**Content-length verification** (`onSegmentFinished`):
- A segment is only marked `done` when `received >= expectedLen`. Early EOF is treated as failure and retried. This is what catches silent truncation on flaky CDNs.

**Dynamic segmentation** (`maybeStealWork`, IDM's signature feature):
- When a segment finishes, the slowest remaining segment (with ≥ `kStealThresholdBytes = 2 MB` left) is aborted, its `endOffset` shrunk to the midpoint, and a new segment appended for the second half.
- `saveMeta()` **must** be called before `startSegment()` on the new segment — otherwise a crash in the window between split and meta write loses bytes on resume.
- Hard cap: `kMaxDynamicSegments = 32`.

**mergeAndFinish**:
- Part files must be sorted by `startOffset` before concatenation. Dynamic segmentation means segment index order ≠ byte order. Don't iterate `m_segments` directly when merging.

**Speed / ETA sliding windows** (`onProgressTick`):
- `m_speedSamples` is a per-tick byte-delta ring (tick = 250 ms, max 120 entries = 30 s).
- **Display speed** = average of the last 8 samples (≈ 2 s) → `m_item->setSpeed()`. Anything shorter jitters between 1 B/s and 50 MB/s on bursty connections.
- **ETA speed** = average of the full 120-sample window → `m_item->setEtaSpeed()`. `DownloadItem::timeLeft()` prefers `m_etaSpeed` over `m_speed` specifically so the time-remaining display doesn't swing when display speed does.
- Pause/abort/finish must clear `m_speedSamples` and call `setEtaSpeed(0)` — otherwise a resumed download shows ghost stats from the previous session.

**Periodic meta save**:
- `saveMeta()` runs every 20 progress ticks (≈ 5 s) via `m_ticksSinceMetaSave`. This bounds crash/power-loss data loss to 5 s per segment.

**Filename sanitization**:
- `sanitizeFilename()` in `SegmentedTransfer.cpp` is the **single** entry point. It strips Windows-invalid chars (`<>:"/\|?*`), rejects reserved names (CON, PRN, LPT1–9, etc.), strips trailing dots/spaces, and caps length at 200 bytes (leaves room for `.stellar-part-N` suffixes under NAME_MAX 255). Any new path that accepts a server-supplied filename must go through this function — Content-Disposition parsing in particular.

**Part file cleanup**:
- `cleanupPartFiles()` globs `*.stellar-part-*` in addition to removing tracked segments, so orphans from aborted dynamic segmentation don't accumulate.

**TLS errors**:
- Every reply connects `sslErrors` for logging. We do **not** call `ignoreSslErrors()` — a broken cert should fail the segment, not silently proceed.

## Download Persistence Invariants

**Save triggers (`AppController::watchItem`):**
- `scheduleSave(id)` is intentionally **not** connected to `doneBytesChanged` or `torrentStatsChanged` — both fire every libtorrent/progress tick and would cause continuous disk writes.
- HTTP progress is persisted by a throttled lambda on `doneBytesChanged`: saves every 4 MB or 2 s, only while status is `Downloading`/`Assembling`.
- Torrent upload/download counters are flushed by `m_torrentStatsFlushTimer` (every 2 minutes) via `AppController::flushTorrentStats()` — only writes when values actually changed.
- `torrentResumeDataChanged` (a dedicated signal separate from `torrentChanged`) writes the `.resume` blob directly to `StellarPaths::resumeFile(id)` via a `QSaveFile`. It must **never** call `scheduleSave` or `flushDirty` — those call `TorrentSessionManager::saveResumeData()`, which would request a new blob and create a feedback loop.

**Resume-data feedback loop (do not reintroduce):**
`flushDirty()` must NOT call `m_torrentSession->saveResumeData()`. Doing so causes: save → saveResumeData → libtorrent alert → `setTorrentResumeData()` → `torrentResumeDataChanged` → write `.resume` file (fine) AND `torrentChanged` → `scheduleSave` → `flushDirty` again — one write per second indefinitely.

**Torrent stats that are NOT persisted** (ephemeral, do not add to `DownloadDatabase::save()`):
`torrentSeeders`, `torrentPeers`, `torrentUploadSpeed`, `torrentAvailability`, `torrentPiecesDone/Total`, `torrentActiveTimeSecs`, `torrentSeedingTimeSecs`, `torrentWastedBytes`, `torrentConnections`. Only `torrentUploaded`, `torrentDownloaded`, and `torrentRatio` are written to `downloads.json`.

## QML Event Handling Patterns

**Right-click context menus — use `TapHandler`, not `MouseArea`:**
When multiple handlers exist in a delegate (expand toggle, checkbox, etc.), use `TapHandler` for right-click detection instead of `MouseArea`. `TapHandler` is *passive* and won't be blocked by child `MouseArea` instances:

```qml
TapHandler {
    acceptedButtons: Qt.RightButton
    onTapped: {
        if (!fd.isFolder) {
            menu.popup()
        }
    }
}
```

If using `MouseArea` for other interactions, always specify `acceptedButtons: Qt.LeftButton` to prevent it from intercepting right-clicks.

**Window size changes during component swap:**
When switching between different layouts/components (e.g., torrent vs HTTP properties), defer window size changes with `Qt.callLater()` until after the `Loader` component swap completes:

```qml
onItemChanged: {
    // ... state updates ...
    Qt.callLater(function() { _applySize() })  // After Loader swap completes
}
```

This prevents stale geometry from the previous component.

## QML Model Scroll Preservation

When a `ListView` model is replaced on every live update from a `QVariantList` Q_PROPERTY (for example `DownloadItem::segmentData`), QML performs a full model reset and the view jumps. A next-frame `contentY` restore can still show a visible "jump up then back down" jitter.

Pattern used in `DownloadProgressDialog.qml` segment list � replicate for similar high-frequency lists:
- Keep a stable `ListModel` bound to the `ListView`.
- Update rows in place (`set`, `remove`, `append`) instead of replacing the whole model each tick.
- While user scrolling is active (`moving` / `flicking` / `dragging`), defer structural updates and apply only the latest pending snapshot on `onMovementEnded`.
- In `ListModel` delegates, bind to role names directly (e.g. `received`, `info`) rather than `modelData.role`.

## Torrent Peer List Live Updates

The torrent peer list in `FilePropertiesDialog.qml` is especially sensitive to model resets because libtorrent refreshes peer state continuously. If `TorrentPeerModel` uses `beginResetModel()/endResetModel()` for ordinary live updates, the QML `ListView` will jump back to the top every second, tooltips will disappear, and active scrolling will feel jittery or fight the user.

Rules for `app/src/TorrentPeerModel.cpp`:
- Do not use full model resets for normal peer refreshes when the peer set can be updated incrementally.
- Prefer row-level `beginInsertRows()/endInsertRows()` and `beginRemoveRows()/endRemoveRows()` for peers entering/leaving.
- If only data changed, keep row identity stable and emit `dataChanged()` instead of rebuilding the model.
- If order changes, prefer `layoutAboutToBeChanged()/layoutChanged()` over a reset.
- Sorting must be deterministic and stable. Use `std::stable_sort()` and a tie-breaker based on peer identity (`endpoint|port`) so equal client names do not randomly reshuffle between updates.
- Peer identity is `endpoint|port` only — client string and seed state are NOT part of the key; they change mid-session and must not cause remove/insert churn.
- `kPeerRemovalGraceTicks = 3`: a peer absent from one libtorrent refresh is kept for 3 ticks before removal, preventing flicker on intermittent peers.
- `setStructuralUpdatesDeferred(true)` mode: while the user is scrolling, row inserts/removes are queued in `m_pendingEntries`; only `dataChanged` fires. Flush happens automatically when set back to false.

This is what fixed the peer list jumping-to-top bug: the model was changed from reset-style live updates to stable incremental updates with deterministic ordering.

## Live Re-sort of the Download Table

`DownloadTableModel::m_visible` is kept sorted at all times under the active sort column. When a row's data changes — status transition (`onItemChanged`) or per-tick stat update like upload speed (`onItemProgressChanged`) — the model must preserve sort order without disturbing the user's scroll position.

**Rule**: when a single row's value crosses a neighbour's value, move just that row to its new sorted position with `beginMoveRows()/endMoveRows()`. Do **not** use `beginResetModel()`, `layoutAboutToBeChanged()/layoutChanged()`, or a re-sort timer.

Why each alternative is wrong for this list:
- `beginResetModel` tears down delegates and scrolls the view to the top.
- `layoutChanged` causes QML's `ListView` to re-anchor the viewport to its `currentIndex`'s delegate. When that delegate's row shifts dramatically (e.g. a torrent's upload speed jumps and it becomes the new #1 sorted by upspeed), the viewport gets dragged with it — visible as the list "jumping to the bottom for one frame, then back to the top" when a row's rank changes. No combination of `Qt.callLater` snapshot/restore on `contentY`, clearing `currentIndex`, or `positionViewAtIndex` reliably suppresses this flash. Don't try to paper over it; just don't emit `layoutChanged` for single-row reordering.
- A coalescing re-sort timer (e.g. fire `layoutChanged` every 2 s instead of per-tick) makes the sort feel laggy *and* still produces the scroll jump when it does fire.

Implementation in `DownloadTableModel::onItemProgressChanged` and `onItemChanged`:
1. Bubble the changed row up or down through `m_visible` until both neighbour comparisons are satisfied. Bubbling works because the precondition "list was sorted before this change" holds — only the changed row can be out of place.
2. Emit one `beginMoveRows`/`endMoveRows` describing exactly that single move. Mind Qt's destination convention: when moving down, the destination index is the row index *one past* where the row will end up; when moving up, it's the natural index.
3. Emit `dataChanged` for the row at its new position so the displayed value (the very change that triggered the re-sort) actually renders.

`kVolatileSortCols` enumerates which sort columns trigger this check: `downspeed`, `speed`, `upspeed`, `progress`, `timeleft`, `ratio`, `uploaded`, `downloaded`, `seeders`, `peers`. Stable columns (`name`, `size`, `status`, `saveto`, etc.) skip the bubble entirely — their value doesn't change on stat ticks, so a row's position is still correct.

This is **different from the rule for `TorrentPeerModel`** above. The peer list permits `layoutChanged` because the entire peer set is recomputed every tick from libtorrent; the download list does not, because individual `DownloadItem` rows are stable and only one row's value changes at a time.

## Torrent Security & Peer Banning

- **Manual bans** (`banPeer(downloadId, endpoint, port, client, reason)`): adds peer to `m_bannedPeers` (persisted via `AppSettings::torrentBannedPeers`) and immediately calls libtorrent's `set_ip_filter()`. `unbanPeer(endpoint)` removes from both.
- **Auto-ban rules** (configured via `AppSettings::torrentAutoBanAbusivePeers` / `torrentAutoBanMediaPlayerPeers`): evaluated on each libtorrent peer alert in `matchAutoBanRule()`; matched peers are added to `m_temporaryBannedPeers` (session-only, not persisted). Temporary bans are cleared via `clearTemporaryPeerBans()`.
- **Encryption** (`AppSettings::torrentEncryptionMode`): 0=Prefer, 1=Require, 2=Allow (plaintext only). Passed to libtorrent's `pe_settings` in `applySettings()`.
- `bannedPeers()` returns a `QVariantList` for QML; `bannedPeersChanged()` signal fires on any change to the ban set.
- `refreshPeerBanRules(settings)` re-reads auto-ban flags and reapplies the IP filter — call after settings change.

## Torrent Search Subsystem

- `TorrentSearchManager` is exposed as `App.torrentSearchManager` (Q_PROPERTY on `AppController`).
- Plugins are `.py` files stored in `pluginDirectory()` (platform-specific app data dir). Bundled plugins are copied on first run via `ensureBundledPluginsInstalled()`.
- `pythonAvailable` is false when no Python interpreter is found on PATH or in the app directory — search is disabled in that state; `statusText` explains why.
- `search(query)` spawns the plugin runner script as a `QProcess`, streams JSON lines to `TorrentSearchResultModel`. `clearResults()` resets the result model.
- Plugin enable/disable state is stored in `AppSettings` under a key returned by `disabledPluginsKey()`.
- `installPluginFromFile(path)` / `installPluginFromUrl(url)` copy/download a `.py` file into the plugin directory and call `refreshPlugins()`.

## Torrent Session Manager Invariants

- `applySettings()` must be called before any `addMagnet()`/`addTorrentFile()` — it creates the libtorrent session lazily via `ensureSession()` and starts the alert timer.
- `restoreTorrent()` is the entry point for re-adding persisted downloads on app restart; it reads `item->torrentSource()` to decide magnet vs. .torrent file.
- **Share limits** (`checkShareLimits()`): evaluated every alert tick for seeding torrents. Per-item limits take precedence over global defaults from `AppSettings`. Limit types: ratio (`torrentDefaultShareRatio`), total seeding time (`torrentDefaultSeedingTimeMins`), inactive seeding time (`torrentDefaultInactiveSeedingTimeMins`). Action on limit (`torrentDefaultShareLimitAction`) is forwarded via `torrentShareLimitReached` signal; AppController decides what to do (pause, remove, etc.).
- **Geo-IP** (`ensureGeoDb()`): lazily opens a MaxMindDB database (requires `STELLAR_HAS_MAXMINDDB` compile flag). DB is searched in the app directory. Results are cached per IP in `GeoDbState::cache`. Without MaxMindDB, geo fields are empty — no fallback.
- **Network binding** (`torrentBindInterface` setting): resolved to actual IP addresses via `QNetworkInterface`; supports both interface names and human-readable display names. Passed to libtorrent's `listen_interfaces` setting.
- **Torrent settings** all share one `torrentSettingsChanged` signal; `AppController` connects to it and calls `torrentSession->applySettings()` on every change. Settings: `torrentEnableDht/Lsd/Upnp/NatPmp`, `torrentListenPort` (default 6881), `torrentConnectionsLimit`, `torrentDownloadLimitKBps`/`torrentUploadLimitKBps`, share-limit defaults, `torrentCustomUserAgent`, `torrentBindInterface`, `torrentEncryptionMode`, `torrentAutoBanAbusivePeers`, `torrentAutoBanMediaPlayerPeers`.
- **Sidebar torrent subcategories** are ordered by `AppSettings::torrentSubcatOrder` (Q_PROPERTY). Valid IDs: `torrent_downloading`, `torrent_seeding`, `torrent_stopped`, `torrent_active`, `torrent_inactive`, `torrent_checking`, `torrent_moving`.
- **Force recheck** (`AppController::forceRecheckTorrent()`, `TorrentSessionManager::forceRecheck()`): Calls libtorrent's `handle.force_recheck()` to verify local data integrity. Blocks exist on the download (pause, resume, delete) during verification. Accessible via "Verify Local Data" button in FilePropertiesDialog transfer stats section.

## Live Speed & Count Properties

`AppController` exposes aggregate live stats as Q_PROPERTYs for QML bindings:
- `App.totalDownSpeed` / `App.totalUpSpeed` — total bytes/sec across all active downloads (including torrent upload). Updated every 5 s by `m_tooltipTimer`.
- `App.seedingCount` — number of torrents currently in Seeding state.

These are intentionally updated on the same 5-second cadence as the tray tooltip (not per-tick) to avoid hammering QML bindings. `StatusBar.qml` and `Main.qml` title bind to these directly. Do not reduce the cadence without understanding the tray tooltip hover-dismiss issue (Windows dismisses the tooltip on every `setToolTip()` call).

## Common Workflows

**Adding a new named queue:**
1. Insert row into `QueueDatabase` (persisted in SQLite)
2. `QueueModel` auto-refreshes from DB signal
3. `DownloadQueue` picks up the new queue via `AppController::reloadQueues()`
4. Sidebar.qml renders queues from `queueModel` — no QML changes needed unless adding UI actions

**Adding a new setting:**
1. Add Q_PROPERTY + getter/setter/signal to AppSettings.h
2. Add member variable initialization, load/save to AppSettings.cpp (emit the changed signal from `load()` too)
3. Add `editXxx` property + dirty-tracking expression to `settingsChanged` in SettingsDialog.qml
4. Add to `applySettings()` and `resetEdits()` in SettingsDialog.qml
5. Add UI control to the appropriate tab

**Modifying download list filtering:**
- Edit DownloadTableModel::matchesFilter() (backend logic)
- Call setFilterCategory() or setFilterQueue() (triggers beginResetModel/endResetModel)
- Update DownloadTable.qml delegation/visibility

**QML drag-drop patterns:**
- Repeater delegates: capture state before handlers end (`var dragFrom = root._dragState`)
- Use Qt.callLater() with captured variables for cleanup (avoids scope/re-entrancy issues)
- MouseArea.preventStealing controls event propagation

**Browser extension debugging:**
- Chrome: chrome://extensions → Details → view errors
- Firefox: about:debugging → Extensions → Stellar
- Native host communication errors: check browser console and Stellar app logs

## Tips System

- Tips are loaded from `tips.txt` (embedded as QML module resource)
- Displayed in status bar (bottom), rotates every 6 hours
- User can manually cycle with "next >>" button or close with "✕"
- Setting persisted in AppSettings.showTips

## QML Performance Rules

**Never nest a Repeater inside a ListView delegate.** Each Repeater item creates a QQmlContext per model row — K items × N rows = K×N contexts created on every model reset. This caused a 2–3 second freeze when switching categories. Instead:
- Use hardcoded `Item` elements with `visible` bindings for column visibility
- Use a **single shared context menu** instance at the ListView root level with a `property var _ctxItem` pointer; never put a `Menu` inside the delegate

**`reuseItems: true`** on ListView helps only when the pool already has items (same category re-entry). It does not help switching from an empty category — the pool is empty and all delegates are created fresh.

**QQmlContext cost**: allocating one QQmlContext costs ~10 ms. With 15 rows and a 7-column Repeater that was ~105 contexts × 10 ms = >1 second just in context allocation.

## QML UI Conventions

**Dark theme palette** (use consistently across all dialogs):
- Window/card backgrounds: `#1e1e1e` (dialogs), `#1b1b1b` (inputs), `#252525` (panels)
- Borders: `#3a3a3a` default, `#4488dd` on focus
- Text: `#e0e0e0` primary, `#aaaaaa` secondary, `#666666` disabled
- Accent blue: `#4488dd`; active pill/selection: `#1a3a6a` bg / `#4488dd` border
- Info note boxes: `#1a2030` bg / `#2a3050` border / `#8899bb` text

**Compact time inputs** (used in speed limiter scheduler and queue scheduler):
- Pattern: `Rectangle { width:50; height:26; radius:2; color:"#1b1b1b"; border.color: field.activeFocus ? "#4488dd" : "#3a3a3a" }` containing a `TextInput`
- AM/PM: `ComboBox` with `implicitWidth:62; implicitHeight:26`, custom `contentItem`/`background`/`indicator` (▼ at 8px)

**Menu bar items**: defined as `component CompactMenuItem: MenuItem` inside the `MenuBar` in `Main.qml`. All top-level `Menu` elements use `delegate: CompactMenuItem; implicitWidth: 200; topPadding: 0; bottomPadding: 0`. Submenus need the same three properties.

**All dialogs are `Window`** (not `Dialog`) — use `.show(); .raise(); .requestActivate()` to open, never `.open()`.

**FilePropertiesDialog patterns** (HTTP vs Torrent):
- Window size changes are deferred via `Qt.callLater()` in `onItemChanged` to let the `Loader` component swap complete first (prevents UI corruption when switching between HTTP and torrent properties)
- General tab consolidates related information into visual cards (`#1e1e1e` background, `#2d2d2d` border, 3px radius)
- Torrent Info, Save Location, and Transfer Stats sections separated by horizontal dividers
- Transfer Stats GridLayout uses tight spacing (8px column, 4px row) with labels in secondary color (`#8899aa`) and values in primary color (`#c8c8c8`)
- "Verify Local Data" button placed at bottom-right of Transfer Stats for integrity checking
- File list delegates use `TapHandler` for right-click rename to avoid event interception by expand/checkbox MouseAreas

## Update System

- `AppController::checkForUpdates(bool manual)` — fetches `updateMetadataUrl()` JSON; on success fetches changelog separately
- `finishUpdateCheckUi()` enforces a 3-second minimum spinner display so the "Checking…" state is visible; the "no update" dialog fires immediately when the response arrives (before the spinner clears)
- On Windows: auto-check shows `updateAvailableDialog` with "Update Now" button (`startUpdateInstall()` downloads the `.exe` as a regular download item then launches it)
- On Linux/macOS: update dialog opens on manual check but "Update Now" is hidden (`visible: Qt.platform.os === "windows"`)
- `fetchChangelog()` — fetches changelog unconditionally regardless of update state; used by the "What's New" link in About

## AppSettings Persistence Patterns

When adding a new persistent field to `AppSettings`:
1. Add member + getter to `AppSettings.h`
2. Load in `AppSettings::load()` with a sensible default
3. Save in `AppSettings::save()`
4. For **one-time-init fields** (e.g. `installDate`, `totalStartups`): write and `sync()` immediately inside `load()` on first run — do not rely on a later `save()` call.
5. For **accumulator fields** (e.g. `totalUptimeSecs`): provide a dedicated `accumulateXxx()` method that increments and calls `save()`; do not wire them to any signal that fires frequently.

## StatusBar Signal Routing

`StatusBar.qml` is a separate file and cannot reference dialog IDs from `Main.qml` directly. The pattern used throughout:
- Declare a `signal` on `StatusBar` (e.g. `signal statisticsRequested()`)
- Emit it from the `MouseArea` inside `StatusBar`
- Handle it in `Main.qml` at the `StatusBar { }` instantiation site with `onStatisticsRequested: { ... }`

## Session vs. All-Time Transfer Bytes

`DownloadItem::torrentUploaded` / `torrentDownloaded` and `doneBytes` are **all persisted to `downloads.json`** and restored on startup — they are NOT session-only. To compute true session-only transfer:
- Snapshot the sum of all restored torrent byte values after DB restore completes (inside the `m_restoring = false` callback in `AppController`)
- Store as `m_sessionBaselineUploaded` / `m_sessionBaselineDownloaded`
- Session bytes = current live sum − baseline (clamped to 0)
- Never use HTTP `doneBytes` for session stats — it reflects the full historical download size.

## QML Fixed-Size Dialogs

For dialogs that should not be resizable, use:
```qml
flags: Qt.Window | Qt.WindowCloseButtonHint | Qt.WindowTitleHint | Qt.MSWindowsFixedSizeDialogHint
```
To size the window exactly to content with no dead space, bind `height` to the implicit height of the root layout item (e.g. `height: mainCol.implicitHeight + 16`) and anchor the layout to three sides (`left`, `right`, `top`) rather than `fill: parent`.

## File Organization Notes

- All C++ headers use `#pragma once` (not include guards)
- QML files named for their root element (e.g., `AddUrlDialog.qml` contains `Window { id: root }`)
- CMakeLists.txt sections are ordered: sources, headers, QML files, resources
- Icons in `app/qml/icons/` (SVG and ICO formats)
- `THIRD-PARTY-NOTICES.txt` — required for LGPL/GPL compliance; bundled by installer and referenced in About tab
