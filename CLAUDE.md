# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Coding Standard

**Fully implement all changes** — no shortcuts, no stubs, no placeholders. Production-ready. Comment *why* not *what*; explain non-obvious parts, avoid over-commenting.

**DRY** — do not repeat yourself. Extract shared logic; never duplicate code.

## Security

**Assume every server is malicious and actively attempting RCE.** Stellar processes untrusted data from arbitrary servers (HTTP headers, Content-Disposition, HTML, JSON, torrent metadata, magnet URIs, yt-dlp output, native messaging). Treat all of it as hostile input.

Rules:
- **Sanitize all server-supplied strings** before use as filenames, paths, shell arguments, or display text. Route through `sanitizeFilename()` for anything touching the filesystem. Never construct paths by concatenating server data directly.
- **No shell expansion.** Use `QProcess` with argument lists, never `QProcess::startDetached(command_string)` or `system()`. Never interpolate server data into a command string.
- **Validate all numeric bounds** from server responses (Content-Length, Content-Range start/end/total, segment offsets). Reject values that would cause out-of-bounds writes, negative sizes, or arithmetic overflow.
- **Reject path traversal.** Strip or reject `..`, absolute paths, and drive-letter prefixes in any server-supplied filename or path component.
- **JSON from untrusted sources** (native messaging, server responses, torrent metadata): check types before use — never assume a field is the expected type.
- **Never call `ignoreSslErrors()`** — a bad cert must fail, not silently proceed.
- **No `eval`-equivalent in JS** (browser extension): never pass server-controlled strings to `eval`, `Function()`, or `innerHTML`.
- When in doubt, reject and fail the download rather than proceeding with unvalidated data.

## Build & Development

**Quick start:**
```bash
cmake --preset windows-debug    # or linux-debug
cmake --build --preset windows-debug
# Output: build/windows-debug/Stellar.exe (or platform-specific)
```

**Manual (if presets fail):**
```bash
cmake -B build -S . -G "Ninja Multi-Config" -DCMAKE_PREFIX_PATH=<Qt6_install_path>
cmake --build build --config Debug
```

Ninja generator required; `ninja` must be in PATH. Windows needs MSVC 2022+.

**Qt6 install:**
- Windows: https://www.qt.io/ or `vcpkg install qt6`
- Linux: `sudo apt install qt6-base-dev qt6-declarative-dev`

**libtorrent (optional):**
Vendored at `third_party/libtorrent-rasterbar-2.0.12`, auto-detected by CMake. Override: set `LIBTORRENT_SOURCE_DIR`, `LIBTORRENT_ROOT`, or `LibtorrentRasterbar_DIR`. Disable: `ENABLE_LIBTORRENT=OFF`. CMake sets `STELLAR_HAS_LIBTORRENT=1` when found; without it, torrent/magnet downloads disabled, everything else works.

**Key build files:**
- `CMakeLists.txt` — Qt6/CMake config. Resources (icons, tips.txt, QML) must be listed in `qt_add_qml_module()`
- Output: `build/windows-debug/` (or platform-specific)

## Architecture

**Backend (C++, Qt 6):**
- `app/src/StellarPaths.{h,cpp}` — **Single source of truth for every on-disk path.** All writable data under one root: `%LOCALAPPDATA%\Stellar\` (Windows) / `$XDG_DATA_HOME/Stellar/` (Linux). Sub-dirs: `data/` (JSON DBs), `resume/` (per-torrent fast-resume blobs), `plugins/search/` (torrent search plugins), `bin/` (yt-dlp/ffmpeg), `geo/` (MaxMindDB), `cache/` (Qt RHI pipeline + QML bytecode). **Any new path must go through this namespace** — never use `QStandardPaths` directly for writable app data. `migrateIfNeeded()` runs once at startup to move data from legacy `StellarDownloadManager/` layout.
- `app/src/AppController.{h,cpp}` — Main app logic, signals/slots, settings integration
- `app/src/AppSettings.{h,cpp}` — Persistent settings via `QSettings` in INI format at `StellarPaths::settingsFile()`. **Not** native registry or `QStandardPaths` — always use `QSettings(StellarPaths::settingsFile(), QSettings::IniFormat)` when opening settings outside `AppSettings` (e.g. in `main.cpp` native messaging handler).
- `app/src/DownloadTableModel.{h,cpp}` — QAbstractTableModel for downloads, filter/sort, custom roles
- `app/src/DownloadQueue.{h,cpp}` — Queue state machine, `scheduleNext()` orchestrates concurrent downloads
- `app/src/DownloadItem.{h,cpp}` — Single download state (progress, speed, segments, metadata)
- `app/src/SegmentedTransfer.{h,cpp}` — Multi-segment HTTP download engine (range requests, reassembly)
- `app/src/CategoryModel.{h,cpp}` — QAbstractListModel for categories, drag-reorder support
- `app/src/Queue.{h,cpp}` / `QueueDatabase.{h,cpp}` / `QueueModel.{h,cpp}` — Named download queues with persistence and QML list model
- `app/src/DownloadDatabase.{h,cpp}` — JSON persistence for download list (`StellarPaths::downloadsFile()`). Torrent fast-resume blobs stored in separate `resume/<id>.resume` files — never inline in `downloads.json`. Writes debounced via 500 ms `QSaveFile`-based timer.
- `app/src/NativeMessagingHost.{h,cpp}` — Browser extension IPC (length-prefixed JSON over stdin/stdout)
- `app/src/SystemTrayIcon.{h,cpp}` — Tray icon; right-click → context menu, double-click → show window
- `app/src/FileIconImageProvider.{h}` — QQuickAsyncImageProvider for file-type icons; caches by full path then extension; requires COM STA init per thread on Windows
- `app/src/FileDragDropHelper.{h,cpp}` — Exposes drag-initiation to QML for dragging files out of app
- `app/src/YtdlpManager.{h,cpp}` — Manages yt-dlp binary: auto-detection, download/update, version check. Detects JS runtime (Deno, Node.js, Bun, or QuickJS) via `detectJsRuntime()`; exposes `jsRuntimeAvailable`, `jsRuntimePath`, `jsRuntimeName`. Path can be user-overridden via `setCustomJsRuntimePath()` / `AppSettings::ytdlpJsRuntimePath`.
- `app/src/YtdlpTransfer.{h,cpp}` — Drives single yt-dlp subprocess; parses stdout progress; handles multi-phase video+audio downloads with accumulated progress across phases. Passes `--js-runtimes <name>` when JS runtime detected.
- `app/src/TorrentSessionManager.{h,cpp}` — Wraps libtorrent session (optional; enabled when `STELLAR_HAS_LIBTORRENT` defined). Handles magnet/torrent-file adds, pause/resume/remove, save-resume-data, exposes per-download `TorrentFileModel`, `TorrentPeerModel`, `TorrentTrackerModel`. `available()` returns false when built without libtorrent. Alert polling runs on 1 s `QTimer`; `post_torrent_updates()` drives status refreshes. Also manages share-limit enforcement (`checkShareLimits()`), geo-IP via optional MaxMindDB (`STELLAR_HAS_MAXMINDDB`), network interface binding (`torrentBindInterface`), peer banning (manual + auto-ban via `banPeer()`/`unbanPeer()`, `bannedPeers()`, `refreshPeerBanRules()`).
- `app/src/TorrentSearchManager.{h,cpp}` — Torrent search subsystem. Python search plugins in `pluginDirectory()`. Auto-detects Python at startup. Plugins installed from `.py` files or URLs. Exposes `TorrentSearchPluginModel` and `TorrentSearchResultModel` to QML. `search(query)` spawns Python subprocess, streams JSON results. `resolveResultLink(row, preferMagnet)` extracts magnet/torrent URL.
- `app/src/TorrentSearchPluginModel.{h,cpp}` / `TorrentSearchResultModel.{h,cpp}` — List models for plugin list and live search results.
- `app/src/TorrentFileModel.{h,cpp}` — Tree-structured `QAbstractListModel` for torrent files. `m_visibleRows` = flat list of expanded nodes. Supports `toggleExpanded()`, `setWanted()`/`applyWantedRecursive()`, `updateProgress()`. `setLiveUpdatesEnabled(false)` suspends all updates (used when dialog hidden).
- `app/src/TorrentPeerModel.{h,cpp}` — Incremental-update `QAbstractListModel` for peers. Identity = `endpoint|port` only. Grace-tick system (`kPeerRemovalGraceTicks = 3`) prevents flicker. `setStructuralUpdatesDeferred(true)` suppresses row inserts/removes while user scrolls; flushes when reset to false. Carries local-node location props for world-map overlay.
- `app/src/TorrentTrackerModel.{h,cpp}` — Simple list model for tracker entries; each carries URL, status, tier, seeder/peer counts, geo coords, country code for map display.
- `cmake/GenerateBuildTime.cmake` — Runs at build time via `add_custom_target`; writes `AppBuildTime.h` with accurate UTC timestamp
- `cmake/FindLibtorrentRasterbar.cmake` — CMake find-module for optional libtorrent-rasterbar; sets `STELLAR_HAS_LIBTORRENT`

**QML Frontend:**
- `app/qml/Main.qml` — Root window, tips system, tray integration, menu bar with `CompactMenuItem`, speed schedule timer (`runSpeedScheduleCheck()`), `whatsNewDialog`
- `app/qml/DownloadTable.qml` — Main download list with multi-select, column definitions, drag-drop to categories
- `app/qml/Sidebar.qml` — Category list, queue list, section drag-reorder, insert-line visual feedback
- `app/qml/SettingsDialog.qml` — Tabbed settings with Apply/Cancel, dirty tracking. Tab indices: 0=Connection, 1=Categories, 2=Downloads, 3=Browser, 4=Speed Limiter, 5=Notifications, 6=General, 7=Media, 8=Torrents, 9=About
- `app/qml/YtdlpDialog.qml` — Video format/quality picker shown when yt-dlp URL intercepted
- `app/qml/SchedulerDialog.qml` — Queue scheduler window; start/stop times, day selection, concurrency, shutdown actions
- `app/qml/DownloadProgressDialog.qml` — Per-download details, segment breakdown, speed limit override
- `app/qml/DownloadCompleteDialog.qml` — Shown after download finishes; open, reveal, or drag-out. Controlled by `AppSettings::showDownloadComplete`.
- `app/qml/DownloadFileInfoDialog.qml` — Shown while file metadata fetched (pending state); user confirms save path before download starts.
- `app/qml/FilePropertiesDialog.qml` — Properties window for any download (HTTP/FTP/torrent). Torrents: info hash, transfer stats, per-torrent speed limits, inline peer-info popup. Right-click rename via `TapHandler`. Peer rows have hover "info" button opening `peerInfoDialog` (inline `Popup`, not `Window`).
- `app/qml/TorrentMetadataDialog.qml` — Torrent details (files, peers, trackers tabs); shown for torrent/magnet properties. `TapHandler` for right-click file rename.
- `app/qml/Toolbar.qml` / `app/qml/ToolbarBtn.qml` / `app/qml/ToolbarDropdown.qml` — Toolbar; all buttons `width:84, height:62`
- `app/qml/DlgButton.qml` — **Shared button component** for all dialogs. Props: `primary` (blue), `destructive` (red), default = secondary (grey). Always use instead of inline `Button` styling.
- Other dialogs: `AddUrlDialog.qml`, `BatchDownloadDialog.qml`, etc.

**Grabber Subsystem:**
- `app/src/GrabberCrawler.{h,cpp}` — Async BFS web crawler via `QNetworkAccessManager`; crawls to configured depth, extracts file links matching include/exclude wildcards, probes sizes via HEAD (4 concurrent). Emits `resultFound` per file, `finished` when done.
- `app/src/GrabberProjectModel.{h,cpp}` — `QAbstractListModel` for saved crawl projects; persists to JSON (`projectsFilePath()`). Use `upsertProject()` / `removeProject()` / `moveProject()` from QML.
- `app/src/GrabberResultModel.{h,cpp}` — `QAbstractListModel` for live crawl results; fed by `GrabberCrawler` signals.
- `app/qml/GrabberDialog.qml` — Main grabber UI (project list + run controls).
- Other `Grabber*.qml` dialogs: settings, filters, schedule, results, statistics, project picker.

**Browser Extensions:**
- `extensions/shared/{interceptor.js, messaging.js}` — Shared download detection, filter matching, settings sync
- `extensions/chrome/{service-worker.js, content.js}` — Chrome MV3, modifier key tracking
- `extensions/firefox/{service-worker.js, content.js}` — Firefox (`browser` API instead of `chrome`)

**Configuration:**
- `tips.txt` — One tip per line, displayed in status bar (cycles every 6 hours)

## Key Patterns & Concepts

**Q_PROPERTY & Signals:**
- Backend settings use `Q_PROPERTY()` with NOTIFY signals → auto-update QML bindings
- Example: `Q_PROPERTY(int globalSpeedLimitKBps READ globalSpeedLimitKBps WRITE setGlobalSpeedLimitKBps NOTIFY globalSpeedLimitKBpsChanged)`

**Q_INVOKABLE:**
- Expose C++ methods to QML: `Q_INVOKABLE DownloadItem *itemAt(int row) const;`
- Used for DownloadTableModel (filter, sort, itemAt) and AppController (download management)

**QAbstractTableModel & QAbstractListModel:**
- DownloadTableModel: `rowCount()`, `columnCount()`, `data()`, `headerData()` with custom roles (ItemRole, ProgressRole)
- Emit `dataChanged()`, `beginResetModel()`/`endResetModel()` for filter/sort
- ModelIndex column maps to enum Column (ColFilename, ColSize, ColProgress, etc.)

**QML MouseArea & Event Stealing:**
- Overlapping MouseAreas can steal events from underlying handlers
- Solution: `preventStealing: false` to release control, `Qt.callLater()` for deferred state cleanup
- Capture variables before deferred callback: `var dragFrom = root._catDragFrom`

**Native Messaging Protocol:**
- JSON messages: `{ type: "download", url, filename, referrer, cookies, modifierKey }`
- Length-prefixed: 4-byte little-endian uint32 + JSON bytes
- `modifierKey` (0=none, 1=alt, 2=ctrl, 3=shift) bypasses interception

**Native Messaging Host Registration (Linux):**
- `AppController::registerNativeHost()` writes manifests to all known Firefox dirs
- **Firefox manifest must NOT contain `allowed_origins`** — Firefox silently skips manifests with that Chrome-only field, producing "No such native application". Always write a Firefox-only manifest object without it; Chrome gets its own separate manifest
- **Flatpak Firefox** (`~/.var/app/org.mozilla.firefox/` exists): sandbox cannot execute binaries outside its own app-data dir. Solution: write a wrapper script at `~/.var/app/org.mozilla.firefox/stellar-nm-host` that calls `exec flatpak-spawn --host <binary> "$@"`, point the manifest `path` at the wrapper. `flatpak-spawn` is available inside Firefox's sandbox at `/usr/bin/flatpak-spawn`
- Flatpak Firefox also needs `org.freedesktop.Flatpak=talk` D-Bus permission: `flatpak override --user --talk-name=org.freedesktop.Flatpak org.mozilla.firefox`. Without it, `flatpak-spawn --host` is blocked. `sandboxedFirefoxIssue()` detects this; `grantFlatpakFirefoxNativeMessagingPermission()` grants it
- Firefox's "Internal UUID" in about:debugging is NOT the extension ID used for `allowed_extensions` matching — the ID for native messaging is always the `gecko.id` from the extension manifest (`stellar@stellar.moe`)

**Settings Synchronization:**
- AppSettings reads/writes QSettings file (Windows: registry fallback)
- Browser extension caches settings 5 s, syncs on demand from native host
- New settings must go in: AppSettings.h (Q_PROPERTY, getter, setter, signal), AppSettings.cpp (load/save), SettingsDialog.qml (UI + dirty tracking)
- `launchOnStartup` writes to `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` (Windows) or `~/.config/autostart/stellar.desktop` (Linux) via `applyStartupRegistration()`

**Pending Download Flow (two-step add):**
- `beginPendingDownload()` — fetches file info (name, size, type), returns `downloadId`; download held in limbo
- `finalizePendingDownload()` — confirms save path/category/queue, starts it; `discardPendingDownload()` cancels

**yt-dlp Download Flow:**
- `AppController::isLikelyYtdlpUrl(url)` — heuristic check; if true, Main.qml opens `YtdlpDialog` instead of `AddUrlDialog`
- `YtdlpDialog` emits `downloadRequested(url, formatId, containerFormat, saveDir, outputTemplate)` — no pending item created beforehand
- `AppController::finalizeYtdlpDownload()` creates `DownloadItem` itself (avoids ghost entries), then calls `startYtdlpWorker()`
- `YtdlpTransfer` passes `--proxy <url>` explicitly — yt-dlp doesn't inherit Qt's application proxy
- When `YtdlpManager::jsRuntimeAvailable()` true, `YtdlpTransfer` adds `--js-runtimes <name>` for sites requiring JS runtime (e.g. YouTube PO token extraction)
- Filename reconciled post-download via filesystem scan (`QDir::entryInfoList` sorted by time) — yt-dlp stdout may have CP1252/UTF-8 encoding issues on Windows corrupting non-ASCII filenames

**Proxy:**
- `AppSettings::proxyType` — 0=None, 1=System, 2=HTTP/HTTPS, 3=SOCKS5
- `AppController::applyProxy()` — called at startup and on every proxy change; sets both `QNetworkProxy::setApplicationProxy()` and `m_nam->setProxy()` directly (latter required — application proxy not always picked up by already-constructed NAM)
- `App.proxyActive` Q_PROPERTY drives status bar indicator

**Speed Limiter Scheduler:**
- Rules in `AppSettings::speedScheduleJson` — array of `{ days[], onHour, onMinute, onAmPm, offHour, offMinute, offAmPm, limitKBps }`
- `runSpeedScheduleCheck()` in `Main.qml` evaluates every 60 s AND immediately when `speedScheduleEnabled` or `speedScheduleJson` changes
- Overnight ranges handled: if `onTime > offTime`, active window wraps midnight

**Clipboard Monitoring:**
- Enabled via `AppSettings::clipboardMonitorEnabled`; `AppController` connects to `QClipboard::dataChanged`
- Filters by `monitoredExtensions`; emits `clipboardUrlDetected(url)` (deduplicated via `m_lastClipboardUrl`)
- `Main.qml` catches signal, opens `AddUrlDialog` with `titleOverride` set

**Download State Machine:**
- Status: Queued → Downloading → Paused/Completed/Failed
- Speed limiter, resume, segmentation all thread-safe via Qt signals/slots
- DownloadQueue manages concurrency (maxConcurrent), calls `SegmentedTransfer::start()`

## SegmentedTransfer Engine Invariants

Non-obvious rules the engine depends on. Breaking any silently corrupts downloads or hangs UI.

**Mandatory request headers** (`applyRequestHeaders()`):
- `Accept-Encoding: identity` **required**. Qt's QNAM auto-decompresses gzip, making `Content-Range` and byte offsets lie — range math breaks, files truncated or corrupted. Never remove.
- `Referer` sent from `m_item->referrer()` when set. Many hosts (Rapidgator, image CDNs) 403 without it.
- HEAD requests use `req.setTransferTimeout(15'000)` so dead host can't hang item in Queued state.

**Per-segment retry** (`retrySegment`, `kMaxSegmentRetries = 4`):
- Exponential backoff 1s/2s/4s/8s, honoring `Retry-After` when server sends it.
- 4xx (except 408/429) = permanent, fails segment immediately. 408/429/5xx = retriable.
- `Segment::retryCount` resets only on successful completion.

**Stall detection** (`onProgressTick`, `kStallTimeoutMs = 30'000`):
- Every segment stamps `lastByteTime` on readyRead. No bytes in 30s → tick aborts+retries. Only thing catching half-open TCP connections — do not remove.

**206 vs 200 fallback** (`onSegmentReadyRead`):
- First chunk validates `Content-Range`: `start` must equal segment's expected start, `total` must equal `m_item->totalBytes()`.
- Server returns 200 instead of 206 → `fallbackToSingleSegment()` collapses to one segment from 0. Don't try to "fix" by assuming range support.

**Content-length verification** (`onSegmentFinished`):
- Segment only marked `done` when `received >= expectedLen`. Early EOF = failure + retry. Catches silent truncation on flaky CDNs.

**Dynamic segmentation** (`maybeStealWork`, IDM's signature feature):
- When segment finishes, slowest remaining (with ≥ `kStealThresholdBytes = 2 MB` left) is aborted, `endOffset` shrunk to midpoint, new segment appended for second half.
- `saveMeta()` **must** be called before `startSegment()` on new segment — crash in window between split and meta write loses bytes on resume.
- Hard cap: `kMaxDynamicSegments = 32`.

**mergeAndFinish**:
- Part files must be sorted by `startOffset` before concatenation. Dynamic segmentation means segment index order ≠ byte order. Don't iterate `m_segments` directly when merging.

**Speed / ETA sliding windows** (`onProgressTick`):
- `m_speedSamples` = per-tick byte-delta ring (tick = 250 ms, max 120 entries = 30 s).
- **Display speed** = avg of last 8 samples (≈ 2 s) → `m_item->setSpeed()`. Shorter = jitter on bursty connections.
- **ETA speed** = avg of full 120-sample window → `m_item->setEtaSpeed()`. `DownloadItem::timeLeft()` prefers `m_etaSpeed` over `m_speed` so time-remaining doesn't swing with display speed.
- Pause/abort/finish must clear `m_speedSamples` and call `setEtaSpeed(0)` — resumed download otherwise shows ghost stats.

**Periodic meta save**:
- `saveMeta()` runs every 20 progress ticks (≈ 5 s) via `m_ticksSinceMetaSave`. Bounds crash/power-loss data loss to 5 s per segment.

**Filename sanitization**:
- `sanitizeFilename()` in `SegmentedTransfer.cpp` = **single entry point**. Strips Windows-invalid chars (`<>:"/\|?*`), rejects reserved names (CON, PRN, LPT1–9, etc.), strips trailing dots/spaces, caps at 200 bytes (leaves room for `.stellar-part-N` suffixes under NAME_MAX 255). Any new path accepting server-supplied filename must go through this — Content-Disposition parsing in particular.

**Part file cleanup**:
- `cleanupPartFiles()` globs `*.stellar-part-*` in addition to removing tracked segments, so orphans from aborted dynamic segmentation don't accumulate.

**TLS errors**:
- Every reply connects `sslErrors` for logging. Do **not** call `ignoreSslErrors()` — broken cert must fail segment, not silently proceed.

## Download Persistence Invariants

**Save triggers (`AppController::watchItem`):**
- `scheduleSave(id)` intentionally **not** connected to `doneBytesChanged` or `torrentStatsChanged` — both fire every tick and would cause continuous disk writes.
- HTTP progress persisted by throttled lambda on `doneBytesChanged`: saves every 4 MB or 2 s, only while status is `Downloading`/`Assembling`.
- Torrent upload/download counters flushed by `m_torrentStatsFlushTimer` (every 2 minutes) via `AppController::flushTorrentStats()` — only writes when values actually changed.
- `torrentResumeDataChanged` writes `.resume` blob directly to `StellarPaths::resumeFile(id)` via `QSaveFile`. Must **never** call `scheduleSave` or `flushDirty` — those call `TorrentSessionManager::saveResumeData()`, which would request new blob and create feedback loop.

**Resume-data feedback loop (do not reintroduce):**
`flushDirty()` must NOT call `m_torrentSession->saveResumeData()`. Causes: save → saveResumeData → libtorrent alert → `setTorrentResumeData()` → `torrentResumeDataChanged` → write `.resume` (fine) AND `torrentChanged` → `scheduleSave` → `flushDirty` again — one write per second indefinitely.

**Torrent stats NOT persisted** (ephemeral, do not add to `DownloadDatabase::save()`):
`torrentSeeders`, `torrentPeers`, `torrentUploadSpeed`, `torrentAvailability`, `torrentPiecesDone/Total`, `torrentActiveTimeSecs`, `torrentSeedingTimeSecs`, `torrentWastedBytes`, `torrentConnections`. Only `torrentUploaded`, `torrentDownloaded`, `torrentRatio` written to `downloads.json`.

## QML Event Handling Patterns

**Right-click context menus — use `TapHandler`, not `MouseArea`:**
`TapHandler` is *passive*, won't be blocked by child `MouseArea` instances:

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

If using `MouseArea` for other interactions, always specify `acceptedButtons: Qt.LeftButton` to prevent right-click interception.

**Window size changes during component swap:**
Defer with `Qt.callLater()` until after `Loader` component swap completes:

```qml
onItemChanged: {
    // ... state updates ...
    Qt.callLater(function() { _applySize() })  // After Loader swap completes
}
```

## QML Model Scroll Preservation

When `ListView` model replaced on every live update from `QVariantList` Q_PROPERTY (e.g. `DownloadItem::segmentData`), QML does full model reset and view jumps. Next-frame `contentY` restore can still show visible jitter.

Pattern from `DownloadProgressDialog.qml` — replicate for similar high-frequency lists:
- Keep stable `ListModel` bound to `ListView`.
- Update rows in place (`set`, `remove`, `append`) instead of replacing whole model each tick.
- While user scrolling (`moving` / `flicking` / `dragging`), defer structural updates; apply latest pending snapshot on `onMovementEnded`.
- In `ListModel` delegates, bind to role names directly (e.g. `received`, `info`) rather than `modelData.role`.

## Torrent Peer List Live Updates

Peer list in `FilePropertiesDialog.qml` especially sensitive to model resets — libtorrent refreshes peer state continuously. Full resets cause `ListView` to jump to top every second.

Rules for `app/src/TorrentPeerModel.cpp`:
- No full model resets for normal peer refreshes when peer set can be updated incrementally.
- Prefer `beginInsertRows()/endInsertRows()` and `beginRemoveRows()/endRemoveRows()` for peers entering/leaving.
- Data-only changes: keep row identity stable, emit `dataChanged()`.
- Order changes: prefer `layoutAboutToBeChanged()/layoutChanged()` over reset.
- Sorting must be deterministic and stable. Use `std::stable_sort()` with tie-breaker on peer identity (`endpoint|port`).
- Peer identity = `endpoint|port` only — client string and seed state are NOT part of key; they change mid-session and must not cause remove/insert churn.
- `kPeerRemovalGraceTicks = 3`: peer absent from one refresh kept 3 ticks before removal.
- `setStructuralUpdatesDeferred(true)`: row inserts/removes queued in `m_pendingEntries` while user scrolls; only `dataChanged` fires. Flush when reset to false.

This fixed the peer list jumping-to-top bug: changed from reset-style to stable incremental updates with deterministic ordering.

## Live Re-sort of the Download Table

`DownloadTableModel::m_visible` kept sorted at all times. When row data changes, model must preserve sort order without disturbing scroll position.

**Rule**: when single row's value crosses a neighbour's, move just that row with `beginMoveRows()/endMoveRows()`. Do **not** use `beginResetModel()`, `layoutAboutToBeChanged()/layoutChanged()`, or re-sort timer.

Why each alternative is wrong:
- `beginResetModel` tears down delegates, scrolls view to top.
- `layoutChanged` causes QML `ListView` to re-anchor viewport to `currentIndex` delegate. When that delegate's row shifts dramatically, viewport gets dragged with it — visible as "jumping to bottom for one frame, then back to top". No combination of `Qt.callLater` snapshot/restore, clearing `currentIndex`, or `positionViewAtIndex` reliably suppresses this. Don't paper over it; don't emit `layoutChanged` for single-row reordering.
- Coalescing re-sort timer (e.g. `layoutChanged` every 2 s) makes sort feel laggy AND still produces scroll jump.

Implementation in `DownloadTableModel::onItemProgressChanged` and `onItemChanged`:
1. Bubble changed row up or down through `m_visible` until both neighbour comparisons satisfied. Works because precondition "list was sorted before change" holds.
2. Emit one `beginMoveRows`/`endMoveRows` for exactly that single move. Note Qt's destination convention: moving down, destination = row index *one past* where row ends up; moving up = natural index.
3. Emit `dataChanged` for row at new position so displayed value actually renders.

`kVolatileSortCols`: `downspeed`, `speed`, `upspeed`, `progress`, `timeleft`, `ratio`, `uploaded`, `downloaded`, `seeders`, `peers`. Stable columns (`name`, `size`, `status`, `saveto`, etc.) skip bubble entirely.

**Different from `TorrentPeerModel` rule above.** Peer list permits `layoutChanged` because entire peer set recomputed every tick; download list does not — individual `DownloadItem` rows are stable, only one row's value changes at a time.

## Torrent Security & Peer Banning

- **Manual bans** (`banPeer(downloadId, endpoint, port, client, reason)`): adds to `m_bannedPeers` (persisted via `AppSettings::torrentBannedPeers`), immediately calls libtorrent's `set_ip_filter()`. `unbanPeer(endpoint)` removes from both.
- **Auto-ban rules** (`AppSettings::torrentAutoBanAbusivePeers` / `torrentAutoBanMediaPlayerPeers`): evaluated per libtorrent peer alert in `matchAutoBanRule()`; matched peers → `m_temporaryBannedPeers` (session-only, not persisted). Cleared via `clearTemporaryPeerBans()`.
- **Encryption** (`AppSettings::torrentEncryptionMode`): 0=Prefer, 1=Require, 2=Allow (plaintext only). Passed to libtorrent's `pe_settings` in `applySettings()`.
- `bannedPeers()` returns `QVariantList` for QML; `bannedPeersChanged()` fires on any change.
- `refreshPeerBanRules(settings)` re-reads auto-ban flags, reapplies IP filter — call after settings change.

## Torrent Search Subsystem

- `TorrentSearchManager` exposed as `App.torrentSearchManager` (Q_PROPERTY on `AppController`).
- Plugins = `.py` files in `pluginDirectory()`. Bundled plugins copied on first run via `ensureBundledPluginsInstalled()`.
- `pythonAvailable` false when no Python found on PATH or in app dir — search disabled; `statusText` explains why.
- `search(query)` spawns plugin runner script as `QProcess`, streams JSON lines to `TorrentSearchResultModel`. `clearResults()` resets result model.
- Plugin enable/disable state in `AppSettings` under key from `disabledPluginsKey()`.
- `installPluginFromFile(path)` / `installPluginFromUrl(url)` copy/download `.py` into plugin dir, call `refreshPlugins()`.

## Torrent Session Manager Invariants

- `applySettings()` must be called before any `addMagnet()`/`addTorrentFile()` — creates libtorrent session lazily via `ensureSession()`, starts alert timer.
- `restoreTorrent()` — entry point for re-adding persisted downloads on restart; reads `item->torrentSource()` to decide magnet vs. .torrent file.
- **Share limits** (`checkShareLimits()`): evaluated every alert tick for seeding torrents. Per-item limits take precedence over global defaults from `AppSettings`. Limit types: ratio (`torrentDefaultShareRatio`), total seeding time (`torrentDefaultSeedingTimeMins`), inactive seeding time (`torrentDefaultInactiveSeedingTimeMins`). Action on limit (`torrentDefaultShareLimitAction`) forwarded via `torrentShareLimitReached` signal; AppController decides (pause, remove, etc.).
- **Geo-IP** (`ensureGeoDb()`): lazily opens MaxMindDB (requires `STELLAR_HAS_MAXMINDDB`). DB searched in app directory. Results cached per IP in `GeoDbState::cache`. Without MaxMindDB, geo fields empty — no fallback.
- **Network binding** (`torrentBindInterface`): see "Torrent Network Binding & Leak Protection" below. Bound interface IPs resolved via `QNetworkInterface`, passed to libtorrent's `listen_interfaces` **and** `outgoing_interfaces`.
- **Torrent settings** all share one `torrentSettingsChanged` signal; `AppController` calls `torrentSession->applySettings()` on every change. Settings: `torrentEnableDht/Lsd/Upnp/NatPmp`, `torrentListenPort` (default 6881), `torrentConnectionsLimit`, `torrentDownloadLimitKBps`/`torrentUploadLimitKBps`, share-limit defaults, `torrentCustomUserAgent`, `torrentBindInterface`, `torrentAllowDiscoveryWhenBound`, `torrentEncryptionMode`, `torrentAutoBanAbusivePeers`, `torrentAutoBanMediaPlayerPeers`.
- **Sidebar torrent subcategories** ordered by `AppSettings::torrentSubcatOrder`. Valid IDs: `torrent_downloading`, `torrent_seeding`, `torrent_stopped`, `torrent_active`, `torrent_inactive`, `torrent_checking`, `torrent_moving`.
- **Force recheck** (`AppController::forceRecheckTorrent()`, `TorrentSessionManager::forceRecheck()`): calls libtorrent's `handle.force_recheck()` to verify local data. Accessible via "Verify Local Data" button in FilePropertiesDialog transfer stats.

## Torrent Network Binding & Leak Protection

Security-sensitive. Goal: torrent traffic never leaks the real IP around a VPN. Enforced at the **socket level** via libtorrent `listen_interfaces` + `outgoing_interfaces` (both required — pinning only one leaks the other direction), not by monitoring. **One user-facing control**, qBittorrent-style, in `AppSettings::torrentBindInterface`:

- **Empty = "Any interface"** (default): unbound. Torrent traffic follows the OS system route, exactly like every other app — which means it already goes through the VPN when the VPN is the active/default route. Never fail-closed. No VPN auto-detection or guessing.
- **Named adapter** (e.g. `WindscribeWireGuard`): hard-bound to that interface only. If it goes away (VPN disconnects), torrents are **paused**, not rerouted — fail-closed. Decided in `TorrentSessionManager::configureSession()`: `boundToInterface = !torrentBindInterface().isEmpty()`.

**Fail-closed binding:** a named interface that currently has no usable address binds to **empty** `listen_interfaces`/`outgoing_interfaces` (no traffic), never the all-interfaces fallback. The `0.0.0.0`/`[::]` fallback in `applyInterfaceBinding()` (empty-`bindAddrs` branch) is **fail-open** and reachable only in the unbound "Any interface" case.

**Auto-harden when bound** (`hardenDiscovery` = `boundToInterface && !torrentAllowDiscoveryWhenBound`): force-disable **UPnP, NAT-PMP, and LSD** even if the user's own toggles are on. UPnP/NAT-PMP map ports via the LAN gateway (off-VPN, exposing the listen port); LSD broadcasts to the LAN; all leak around the tunnel. This is **stricter than qBittorrent**, which never couples these to binding (it leaves them to the user toggle and only documents "turn these off for VPN" — see `SessionImpl::enablePortMapping`/`disablePortMapping`, driven solely by the port-forwarding preference). The `torrentAllowDiscoveryWhenBound` setting (default false, advanced checkbox) lets power users binding to a trusted LAN adapter opt back in. When unbound, the user's `torrentEnableUpnp/NatPmp/Lsd` are always honoured. DHT stays user-controlled (routes over the bound interface, maps no LAN port). Surfaced to QML via `AppController::torrentBindingHardened`.

**IPv6 rides the VPN.** `interfaceBindAddresses()` returns both v4 and v6 of the bound interface; `applyInterfaceBinding()` binds both — so when the VPN provides an IPv6 address, torrent IPv6 goes through the VPN. A v4-only VPN simply yields a v4-only bind and never falls back to an all-interfaces `[::]` catch-all that would leak native IPv6.

**Suspend/recover** (`AppController::reconcileTorrentBindState()`, driven every 5 s by `m_tooltipTimer`, plus startup and on `torrentSettingsChanged`): only a **named** interface suspends. Wall-clock debounce: record `m_torrentBindUnavailableSinceMs` when the adapter first goes unavailable; suspend only after it stays unavailable for `kBindSuspendGraceMs` (15 s). VPN adapters flap their `IsUp`/`IsRunning` flag and drop their IP for a tick during keepalive/rekey; suspending on a single false reading drops all peers → **speed sawtooth** (the original bug). Grace is wall-clock, NOT a tick count, so it doesn't silently depend on the 5 s timer's interval. Recovery is immediate: on return, `applySettings()` (rebind to the fresh VPN IP) then `unsuspendSession()`. "Any interface" never suspends.

**`suspendSession()` keeps the alert timer running.** It calls `session.pause()` (stops peer traffic — the leak guard) but must **not** stop `m_alertTimer`: the alert loop still processes `save_resume_data_alert` (else a crash during a suspend window loses recent resume data), `checkShareLimits`, and UI status. `post_torrent_updates()` on a paused-but-valid session is safe.

## Live Speed & Count Properties

`AppController` exposes aggregate live stats as Q_PROPERTYs:
- `App.totalDownSpeed` / `App.totalUpSpeed` — total bytes/sec across all active downloads (including torrent upload). Updated every 5 s by `m_tooltipTimer`.
- `App.seedingCount` — torrents currently in Seeding state.

Intentionally on 5-second cadence, same as tray tooltip — not per-tick. `StatusBar.qml` and `Main.qml` title bind to these directly. Do not reduce cadence without understanding tray tooltip hover-dismiss issue (Windows dismisses tooltip on every `setToolTip()` call).

## Common Workflows

**Adding new named queue:**
1. Insert row into `QueueDatabase` (persisted in SQLite)
2. `QueueModel` auto-refreshes from DB signal
3. `DownloadQueue` picks up new queue via `AppController::reloadQueues()`
4. Sidebar.qml renders from `queueModel` — no QML changes needed unless adding UI actions

**Adding new setting:**
1. Add Q_PROPERTY + getter/setter/signal to AppSettings.h
2. Add member init, load/save to AppSettings.cpp (emit changed signal from `load()` too)
3. Add `editXxx` property + dirty-tracking to `settingsChanged` in SettingsDialog.qml
4. Add to `applySettings()` and `resetEdits()` in SettingsDialog.qml
5. Add UI control to appropriate tab

**Modifying download list filtering:**
- Edit `DownloadTableModel::matchesFilter()` (backend logic)
- Call `setFilterCategory()` or `setFilterQueue()` (triggers beginResetModel/endResetModel)
- Update DownloadTable.qml delegation/visibility

**QML drag-drop patterns:**
- Repeater delegates: capture state before handlers end (`var dragFrom = root._dragState`)
- Use `Qt.callLater()` with captured variables for cleanup
- `MouseArea.preventStealing` controls event propagation

**Browser extension debugging:**
- Chrome: chrome://extensions → Details → view errors
- Firefox: about:debugging → Extensions → Stellar
- Native host errors: check browser console and Stellar app logs

## Tips System

- Tips loaded from `tips.txt` (embedded as QML module resource)
- Displayed in status bar, rotates every 6 hours
- User can cycle with "next >>" or close with "✕"
- Setting persisted in `AppSettings.showTips`

## QML Performance Rules

**Never nest Repeater inside ListView delegate.** Each Repeater item creates QQmlContext per model row — K items × N rows = K×N contexts on every model reset. Caused 2–3 second freeze when switching categories. Instead:
- Hardcoded `Item` elements with `visible` bindings for column visibility
- **Single shared context menu** instance at ListView root with `property var _ctxItem` pointer; never put `Menu` inside delegate

**`reuseItems: true`** on ListView helps only when pool already has items. Doesn't help switching from empty category — pool empty, all delegates created fresh.

**QQmlContext cost**: ~10 ms each. 15 rows × 7-column Repeater = ~105 contexts × 10 ms = >1 second just in context allocation.

## QML UI Conventions

**Dark theme palette:**
- Window/card backgrounds: `#1e1e1e` (dialogs), `#1b1b1b` (inputs), `#252525` (panels)
- Borders: `#3a3a3a` default, `#4488dd` on focus
- Text: `#e0e0e0` primary, `#aaaaaa` secondary, `#666666` disabled
- Accent blue: `#4488dd`; active pill/selection: `#1a3a6a` bg / `#4488dd` border
- Info note boxes: `#1a2030` bg / `#2a3050` border / `#8899bb` text

**Compact time inputs** (speed limiter scheduler, queue scheduler):
- Pattern: `Rectangle { width:50; height:26; radius:2; color:"#1b1b1b"; border.color: field.activeFocus ? "#4488dd" : "#3a3a3a" }` containing `TextInput`
- AM/PM: `ComboBox` with `implicitWidth:62; implicitHeight:26`, custom `contentItem`/`background`/`indicator` (▼ at 8px)

**Menu bar items**: `component CompactMenuItem: MenuItem` inside `MenuBar` in `Main.qml`. All top-level `Menu` use `delegate: CompactMenuItem; implicitWidth: 200; topPadding: 0; bottomPadding: 0`. Submenus need same three properties. Menu rows **must paint an opaque background** — see "Linux Software-Backend Menus".

**All dialogs are `Window`** (not `Dialog`) — use `.show(); .raise(); .requestActivate()` to open, never `.open()`.

**FilePropertiesDialog patterns:**
- Window size changes deferred via `Qt.callLater()` in `onItemChanged` (prevents UI corruption when switching HTTP/torrent properties)
- General tab uses visual cards (`#1e1e1e` bg, `#2d2d2d` border, 3px radius)
- Torrent Info, Save Location, Transfer Stats separated by horizontal dividers
- Transfer Stats GridLayout: 8px column spacing, 4px row; labels `#8899aa`, values `#c8c8c8`
- "Verify Local Data" at bottom-right of Transfer Stats
- File list delegates use `TapHandler` for right-click rename

## Linux Software-Backend Menus (transparency fix)

On machines without usable hardware OpenGL the app runs on the Qt Quick software scene graph (selected in-process by `selectWorkingGraphicsBackend()` in `main.cpp`; VirtualBox/SVGA3D has no GLX FBConfig for any Qt surface format). There the Menu's own background node does not reliably composite, so any `MenuItem` whose background is `"transparent"` shows the window straight through.

**Rule:** every menu row and separator **must paint an OPAQUE background**. Use `ColorPalette.menuBg` (theme-aware) for rows, `ColorPalette.selectionBg` when highlighted.

This applies to the inline `MenuItem` subcomponents that the real menus define — `CompactMenuItem` (`Main.qml`), `CtxMenuItem` / `ColCheckMenuItem` (`DownloadTable.qml`) — **not** just `app/style/MenuItem.qml`. **Inline component definitions override the custom style**, so fixing only the style file does nothing for these menus. That was the original bug: edits to `app/style/*.qml` that the actual menus never used.

**Not the cause (superseded theories, don't reintroduce):** the Material elevation shadow ShaderEffect layer, and `Popup.Window` vs `Popup.Item`. `popupType: T.Popup.Item` is set in `app/style/Menu.qml` and is correct (in-overlay, single window) but did not by itself fix transparency — opaque row backgrounds did.

Style additions ship via a hand-authored qmldir + `qt_add_resources` under `/qt/qml/Stellar` (see `CMakeLists.txt`): `Menu.qml`, `MenuItem.qml`, `MenuSeparator.qml`. The style `MenuSeparator` is opaque so all bare `MenuSeparator{}` call sites are covered app-wide.

## Internationalisation (i18n)

**Architecture:** Qt Linguist system (`tr()` / `qsTr()`). Translator loaded at startup before the QML engine so all `qsTr()` calls in component construction resolve correctly.

**Adding new strings — mandatory workflow:**
Every new user-visible string must be added to `translations/stellar_en.ts`. `fill_translations.py` reads that file and uses an LLM to auto-translate into all 76 other languages. Do **not** run `lupdate` manually; do **not** edit other `.ts` files directly.

**Files:**
- `translations/stellar_en.ts` — **source of truth** for all translatable strings. Add every new `tr()`/`qsTr()` string here.
- `.qm` files compiled at build time by `qt_add_translations()` in `CMakeLists.txt` (requires `Qt6LinguistTools`; guarded with `if(Qt6LinguistTools_FOUND)`).
- Embedded as Qt resources under prefix `:/i18n/` → loaded as `:/i18n/stellar_<locale>`.

**Setting:** `AppSettings::uiLanguage` — persisted locale code (e.g. `""` = English default, `"fr"` = French). Loaded in `AppSettings::load()`, saved in `save()`.

**Applying at runtime:** `AppController::applyUiLanguage(locale)` — removes old translator, installs new one, calls `setUiLanguage()`. Called from `main.cpp` before QML engine loads (startup), and from `SettingsDialog::applySettings()` when user changes language.

**Settings tab:** Language tab is index **11** in `SettingsDialog.qml` (between Associations=10 and About=12). `pageLanguage: 11`, `pageAbout: 12`. `settingsPageAbout` in `Main.qml` is **12**.

**Adding a new language:**
1. Add `translations/stellar_XX.ts` (copy fr.ts, set `language="xx_XX"`)
2. Add to `qt_add_translations(TS_FILES ...)` in `CMakeLists.txt`
3. Add a `LangOption { langCode: "xx"; langLabel: "..."; langNative: "..." }` in the Language tab of `SettingsDialog.qml`
4. Run `lupdate`, translate `<translation>` elements, rebuild

**Restart required:** QML strings are resolved at component construction time; changing the translator at runtime doesn't retranslate existing QML elements. The Language tab shows a note and the user must restart. The setting is persisted immediately.

## Update System

- `AppController::checkForUpdates(bool manual)` — fetches `updateMetadataUrl()` JSON; on success fetches changelog separately
- `finishUpdateCheckUi()` enforces 3-second minimum spinner display; "no update" dialog fires immediately when response arrives
- Windows: auto-check shows `updateAvailableDialog` with "Update Now" (`startUpdateInstall()` downloads `.exe` as regular download item, launches it)
- Linux/macOS: update dialog opens on manual check but "Update Now" hidden (`visible: Qt.platform.os === "windows"`)
- `fetchChangelog()` — fetches changelog unconditionally regardless of update state; used by "What's New" in About

## AppSettings Persistence Patterns

When adding new persistent field:
1. Add member + getter to `AppSettings.h`
2. Load in `AppSettings::load()` with sensible default
3. Save in `AppSettings::save()`
4. **One-time-init fields** (e.g. `installDate`, `totalStartups`): write and `sync()` immediately inside `load()` on first run — don't rely on later `save()`.
5. **Accumulator fields** (e.g. `totalUptimeSecs`): dedicated `accumulateXxx()` method that increments and calls `save()`; don't wire to frequently-firing signals.

## StatusBar Signal Routing

`StatusBar.qml` cannot reference dialog IDs from `Main.qml` directly. Pattern:
- Declare `signal` on `StatusBar` (e.g. `signal statisticsRequested()`)
- Emit from `MouseArea` inside `StatusBar`
- Handle in `Main.qml` at `StatusBar { }` instantiation with `onStatisticsRequested: { ... }`

## Session vs. All-Time Transfer Bytes

`DownloadItem::torrentUploaded` / `torrentDownloaded` and `doneBytes` are **all persisted to `downloads.json`** and restored on startup — NOT session-only. To compute true session-only transfer:
- Snapshot sum of all restored torrent byte values after DB restore completes (inside `m_restoring = false` callback in `AppController`)
- Store as `m_sessionBaselineUploaded` / `m_sessionBaselineDownloaded`
- Session bytes = current live sum − baseline (clamped to 0)
- Never use HTTP `doneBytes` for session stats — reflects full historical download size.

## QML Fixed-Size Dialogs

For non-resizable dialogs:
```qml
flags: Qt.Window | Qt.WindowCloseButtonHint | Qt.WindowTitleHint | Qt.MSWindowsFixedSizeDialogHint
```
Size window to content: bind `height` to implicit height of root layout (e.g. `height: mainCol.implicitHeight + 16`), anchor layout to three sides (`left`, `right`, `top`) not `fill: parent`.

## File Organization Notes

- All C++ headers use `#pragma once` (not include guards)
- QML files named for root element (e.g., `AddUrlDialog.qml` contains `Window { id: root }`)
- CMakeLists.txt sections ordered: sources, headers, QML files, resources
- Icons in `app/qml/icons/` (SVG and ICO formats)
- `THIRD-PARTY-NOTICES.txt` — required for LGPL/GPL compliance; bundled by installer, referenced in About tab