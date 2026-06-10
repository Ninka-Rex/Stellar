# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Coding Standard

**Fully implement all changes** — no stubs, no placeholders. Production-ready. Comment *why* not *what*. **DRY** — never duplicate code.

## Security

**Assume every server is malicious and actively attempting RCE.** Stellar processes untrusted data from arbitrary servers. Treat all as hostile.

- **Sanitize all server-supplied strings** before use as filenames, paths, shell args, or display text. Route through `sanitizeFilename()`.
- **No shell expansion.** `QProcess` with arg lists, never `QProcess::startDetached(command_string)` or `system()`.
- **Validate numeric bounds** from server responses (Content-Length, Content-Range start/end/total, segment offsets).
- **Reject path traversal.** Strip/reject `..`, absolute paths, drive-letter prefixes in any server filename/path component.
- **JSON from untrusted sources** (native messaging, server responses, torrent metadata): check types before use.
- **Never call `ignoreSslErrors()`** — a bad cert must fail.
- **No `eval`-equivalent in JS** (extension): never pass server strings to `eval`, `Function()`, `innerHTML`.

## Architecture

**Backend (C++, Qt 6):**

Source is grouped by subsystem under `app/src/`: `core/` (app/controller, settings, paths, tray, native messaging, drag-drop, icon provider, network, cookies, data portability), `download/` (item, queue, models, transfers, database, category, media metadata), `queue/` (named queues), `grabber/`, `ytdlp/`, `rss/`, `torrent/`. Includes stay **bare** (`#include "DownloadItem.h"`) — every subdir is on the include path via `target_include_directories`. QML under `app/qml/` mirrors this: `main/`, `components/`, `dialogs/`, `grabber/`, `ytdlp/`, `rss/`, `torrent/`, `singletons/`; **`Main.qml` stays at the qml root** (its qrc path is hardcoded in `core/main.cpp`). `icons/`, `flags/`, `app/style/` do **not** move — referenced by hardcoded qrc paths in C++ and by relative `icons/…` paths in QML. New CMake `BACKEND_SOURCES`/`BACKEND_HEADERS`/`QML_FILES` entries must use the subfolder path.

- `app/src/core/StellarPaths.{h,cpp}` — **Single source of truth for every on-disk path.** All writable data under one root: `%LOCALAPPDATA%\Stellar\` (Windows) / `$XDG_DATA_HOME/Stellar/` (Linux). Sub-dirs: `data/` (JSON DBs), `resume/` (fast-resume blobs), `plugins/search/`, `bin/` (yt-dlp/ffmpeg), `geo/` (MaxMindDB), `cache/` (Qt RHI pipeline + QML bytecode). **Any new path must go through this namespace** — never `QStandardPaths` directly for writable app data. `migrateIfNeeded()` runs once at startup, moves data from legacy `StellarDownloadManager/` layout.
- `app/src/core/AppController.{h,cpp}` — Main app logic, signals/slots, settings integration.
- `app/src/core/AppSettings.{h,cpp}` — Settings via `QSettings` INI at `StellarPaths::settingsFile()`. **Not** registry/`QStandardPaths` — always use `QSettings(StellarPaths::settingsFile(), QSettings::IniFormat)` when opening settings outside `AppSettings` (e.g. `main.cpp` native messaging handler).
- `app/src/download/DownloadTableModel.{h,cpp}` — QAbstractTableModel for downloads, filter/sort, custom roles
- `app/src/download/DownloadQueue.{h,cpp}` — Queue state machine, `scheduleNext()` orchestrates concurrent downloads
- `app/src/download/DownloadItem.{h,cpp}` — Single download state (progress, speed, segments, metadata)
- `app/src/download/SegmentedTransfer.{h,cpp}` — Multi-segment HTTP download engine (range requests, reassembly)
- `app/src/download/CategoryModel.{h,cpp}` — QAbstractListModel for categories, drag-reorder support
- `app/src/queue/Queue.{h,cpp}` / `app/src/queue/QueueDatabase.{h,cpp}` / `app/src/queue/QueueModel.{h,cpp}` — Named download queues with persistence and QML list model
- `app/src/download/DownloadDatabase.{h,cpp}` — JSON persistence for download list (`StellarPaths::downloadsFile()`). Fast-resume blobs in separate `resume/<id>.resume` files — never inline. Writes debounced via 500 ms `QSaveFile` timer.
- `app/src/core/NativeMessagingHost.{h,cpp}` — Extension IPC (length-prefixed JSON over stdin/stdout).
- `app/src/core/SystemTrayIcon.{h,cpp}` — Tray icon; right-click → menu, double-click → show window.
- `app/src/core/FileIconImageProvider.{h}` — QQuickAsyncImageProvider for file-type icons; caches by full path then extension; needs per-thread COM STA init on Windows.
- `app/src/core/FileDragDropHelper.{h,cpp}` — Exposes drag-initiation to QML for dragging files out.
- `app/src/ytdlp/YtdlpManager.{h,cpp}` — yt-dlp binary: auto-detect, download/update, version check. Detects JS runtime (Deno/Node/Bun/QuickJS) via `detectJsRuntime()`; exposes `jsRuntimeAvailable/Path/Name`. User override via `setCustomJsRuntimePath()` / `AppSettings::ytdlpJsRuntimePath`.
- `app/src/ytdlp/YtdlpTransfer.{h,cpp}` — Drives single yt-dlp subprocess; parses stdout progress; multi-phase video+audio with accumulated progress. Passes `--js-runtimes <name>` when JS runtime detected.
- `app/src/torrent/TorrentSessionManager.{h,cpp}` — Wraps libtorrent session (optional; `STELLAR_HAS_LIBTORRENT`). Magnet/torrent-file adds, pause/resume/remove, save-resume-data; exposes per-download `TorrentFileModel`/`TorrentPeerModel`/`TorrentTrackerModel`. `available()` false when built without libtorrent. Alert polling on 1 s `QTimer`; `post_torrent_updates()` drives status refreshes. Also: share-limit enforcement (`checkShareLimits()`), geo-IP via optional MaxMindDB (`STELLAR_HAS_MAXMINDDB`), interface binding (`torrentBindInterface`), peer banning (`banPeer()`/`unbanPeer()`, `bannedPeers()`, `refreshPeerBanRules()`).
- `app/src/torrent/TorrentSearchManager.{h,cpp}` — Torrent search. Python `.py` plugins in `pluginDirectory()`; auto-detects Python at startup; installable from file or URL. Exposes `TorrentSearchPluginModel`/`TorrentSearchResultModel`. `search(query)` spawns Python subprocess, streams JSON. `resolveResultLink(row, preferMagnet)` extracts magnet/torrent URL.
- `app/src/torrent/TorrentSearchPluginModel.{h,cpp}` / `app/src/torrent/TorrentSearchResultModel.{h,cpp}` — List models for plugin list and live search results.
- `app/src/torrent/TorrentFileModel.{h,cpp}` — Tree `QAbstractListModel` for torrent files. `m_visibleRows` = flat list of expanded nodes. `toggleExpanded()`, `setWanted()`/`applyWantedRecursive()`, `updateProgress()`. `setLiveUpdatesEnabled(false)` suspends updates when dialog hidden.
- `app/src/torrent/TorrentPeerModel.{h,cpp}` — Incremental peer model. Identity = `endpoint|port`. Grace-tick (`kPeerRemovalGraceTicks=3`) prevents flicker. `setStructuralUpdatesDeferred(true)` suppresses insert/remove while scrolling. Carries local-node location for map overlay.
- `app/src/torrent/TorrentTrackerModel.{h,cpp}` — Tracker entries: URL, status, tier, seeder/peer counts, geo coords, country code.
- `cmake/GenerateBuildTime.cmake` — `add_custom_target` at build; writes `AppBuildTime.h` (UTC timestamp).
- `cmake/FindLibtorrentRasterbar.cmake` — find-module for optional libtorrent; sets `STELLAR_HAS_LIBTORRENT`.

**QML Frontend:**
- `app/qml/Main.qml` — Root window, tips, tray, menu bar (stays at qml root) (`CompactMenuItem`), speed schedule timer (`runSpeedScheduleCheck()`), `whatsNewDialog`.
- `app/qml/main/DownloadTable.qml` — Download list: multi-select, columns, drag-drop to categories.
- `app/qml/main/Sidebar.qml` — Category/queue lists, section drag-reorder, insert-line feedback.
- `app/qml/dialogs/SettingsDialog.qml` — Tabbed, Apply/Cancel, dirty tracking. Tabs: 0=Connection, 1=Categories, 2=Downloads, 3=Browser, 4=Speed Limiter, 5=Notifications, 6=General, 7=Media, 8=Torrents, 10=Associations, 11=Language, 12=About (see i18n note).
- `app/qml/ytdlp/YtdlpDialog.qml` — Video format/quality picker for intercepted yt-dlp URLs.
- `app/qml/dialogs/SchedulerDialog.qml` — Queue scheduler: start/stop times, days, concurrency, shutdown actions.
- `app/qml/dialogs/DownloadProgressDialog.qml` — Per-download details, segment breakdown, speed override.
- `app/qml/dialogs/DownloadCompleteDialog.qml` — After finish: open/reveal/drag-out. `AppSettings::showDownloadComplete`.
- `app/qml/dialogs/DownloadFileInfoDialog.qml` — Pending-state metadata fetch; confirm save path before start.
- `app/qml/dialogs/FilePropertiesDialog.qml` — Properties for any download (HTTP/FTP/torrent). Torrents: info hash, transfer stats, per-torrent speed limits, inline peer-info popup. Right-click rename via `TapHandler`. Peer rows hover "info" → `peerInfoDialog` (inline `Popup`).
- `app/qml/torrent/TorrentMetadataDialog.qml` — Torrent details (files/peers/trackers tabs); `TapHandler` for right-click file rename.
- `app/qml/main/Toolbar.qml` / `app/qml/components/ToolbarBtn.qml` / `app/qml/components/ToolbarDropdown.qml` — all buttons `width:84, height:62`.
- `app/qml/components/DlgButton.qml` — **Shared dialog button**. Props: `primary` (blue), `destructive` (red), default secondary (grey). Use instead of inline `Button` styling.
- Other dialogs: `AddUrlDialog.qml`, `BatchDownloadDialog.qml`, etc.

**Grabber Subsystem:**
- `app/src/grabber/GrabberCrawler.{h,cpp}` — Async BFS crawler via `QNetworkAccessManager`; crawls to depth, extracts links matching include/exclude wildcards, probes sizes via HEAD (4 concurrent). Emits `resultFound`/`finished`.
- `app/src/grabber/GrabberProjectModel.{h,cpp}` — saved crawl projects; JSON-persisted (`projectsFilePath()`). `upsertProject()`/`removeProject()`/`moveProject()`.
- `app/src/grabber/GrabberResultModel.{h,cpp}` — live crawl results fed by `GrabberCrawler` signals.
- `app/qml/grabber/GrabberDialog.qml` + other `app/qml/grabber/Grabber*.qml` (settings, filters, schedule, results, statistics, project picker).

**Browser Extensions:**
- `extensions/chrome/` — Chrome MV3. `service-worker.js`, `content.js`, `page-bridge.js` (blob-URL resolver injected into page), `popup.{html,js}`, `manifest.json` (+ `manifest.store.json` for Web Store), `icons/`, `shared/{interceptor.js, messaging.js}` (download detection, filter matching, settings sync, native-host messaging). Service worker `import`s from `./shared/`.
- `extensions/firefox/` — Firefox (`browser` API instead of `chrome`). `service-worker.js`, `content.js`, `popup.{html,js}`, `manifest.json`, `icons/`, `firefox.zip` + `repack.bat`. **No `shared/` dir** — Firefox inlines chrome's `messaging.js`/`interceptor.js` directly in `service-worker.js`. When editing shared logic change BOTH `chrome/shared/messaging.js` (an `export`) AND the matching inline function in `firefox/service-worker.js`.
- **Multi-link selection ("Download all links with Stellar"):** `content.js` (both) exposes `collectSelectedLinks()` — walks `window.getSelection()`, resolves hrefs against page base, filters to http/https/ftp/magnet/.torrent, returns `[{url,text}]`; answered via `collectSelectedLinks` `runtime.onMessage` handler. `stellar-download-links` context menu (`contexts:["selection"]`) queries active tab content script, sends `importLinks` native message (`requestImportLinks` chrome / inline firefox). Native host (`main.cpp`) forwards over local socket + drop-files for cold-start replay, same as `download`. `AppController::handleIpcPayload` validates each link (type-check + scheme allow-list — untrusted) and emits `importLinksRequested(QVariantList)`; `Main.qml` opens `BatchDownloadListDialog` with `isImport=true`.

**Configuration:** `tips.txt` — one tip per line, status bar, cycles every 6 hours.

## Key Patterns & Concepts

**Q_PROPERTY & Signals:** backend settings use `Q_PROPERTY()` with NOTIFY → auto-update QML bindings. E.g. `Q_PROPERTY(int globalSpeedLimitKBps READ ... WRITE ... NOTIFY globalSpeedLimitKBpsChanged)`.

**Q_INVOKABLE:** expose C++ to QML, e.g. `Q_INVOKABLE DownloadItem *itemAt(int row) const;` (DownloadTableModel filter/sort/itemAt, AppController download mgmt).

**QAbstractTableModel/ListModel:** DownloadTableModel implements `rowCount`/`columnCount`/`data`/`headerData` with custom roles (ItemRole, ProgressRole). Emit `dataChanged()`, `beginResetModel`/`endResetModel` for filter/sort. Column maps to enum (ColFilename, ColSize, ColProgress...).

**QML MouseArea event stealing:** overlapping MouseAreas steal events. Use `preventStealing: false` to release, `Qt.callLater()` for deferred cleanup, capture vars before callback (`var dragFrom = root._catDragFrom`).

**Native Messaging Protocol:** JSON `{ type:"download", url, filename, referrer, cookies, modifierKey }`. Length-prefixed: 4-byte LE uint32 + JSON. `modifierKey` (0=none,1=alt,2=ctrl,3=shift) bypasses interception.

**Native Messaging Host Registration (Linux):**
- `AppController::registerNativeHost()` writes manifests to all known Firefox dirs. Called deferred (`singleShot(0)`) so its disk/registry writes don't block first paint.
- **Firefox manifest must NOT contain `allowed_origins`** — Firefox silently skips manifests with that Chrome-only field ("No such native application"). Firefox-only manifest without it; Chrome gets its own.
- **Flatpak Firefox** (`~/.var/app/org.mozilla.firefox/` exists): sandbox can't execute binaries outside its app-data dir. Fix: wrapper script at `~/.var/app/org.mozilla.firefox/stellar-nm-host` calling `exec flatpak-spawn --host <binary> "$@"`, manifest `path` points at wrapper. `flatpak-spawn` available in sandbox at `/usr/bin/flatpak-spawn`.
- Flatpak Firefox also needs `org.freedesktop.Flatpak=talk` D-Bus permission: `flatpak override --user --talk-name=org.freedesktop.Flatpak org.mozilla.firefox`. Without it `flatpak-spawn --host` is blocked. `sandboxedFirefoxIssue()` detects; `grantFlatpakFirefoxNativeMessagingPermission()` grants.
- Firefox "Internal UUID" in about:debugging is NOT the native-messaging ID — that's always `gecko.id` from the extension manifest (`stellar@stellar.moe`).

**Settings Synchronization:**
- AppSettings reads/writes QSettings file (Windows: registry fallback).
- Browser extension caches settings 5 s, syncs on demand from native host.
- New settings go in: AppSettings.h (Q_PROPERTY, getter, setter, signal), AppSettings.cpp (load/save), SettingsDialog.qml (UI + dirty tracking).
- `launchOnStartup` → `HKCU\...\CurrentVersion\Run` (Windows) or `~/.config/autostart/stellar.desktop` (Linux) via `applyStartupRegistration()`.

**Pending Download Flow (two-step add):** `beginPendingDownload()` fetches file info (name/size/type), returns `downloadId`, holds in limbo. `finalizePendingDownload()` confirms save path/category/queue + starts; `discardPendingDownload()` cancels.

**yt-dlp Download Flow:**
- `AppController::isLikelyYtdlpUrl(url)` — heuristic; if true, Main.qml opens `YtdlpDialog` not `AddUrlDialog`.
- `YtdlpDialog` emits `downloadRequested(url, formatId, containerFormat, saveDir, outputTemplate)` — no pending item created.
- `AppController::finalizeYtdlpDownload()` creates the `DownloadItem` itself (avoids ghost entries), then `startYtdlpWorker()`.
- `YtdlpTransfer` passes `--proxy <url>` explicitly — yt-dlp doesn't inherit Qt app proxy.
- When `jsRuntimeAvailable()`, adds `--js-runtimes <name>` for JS-requiring sites (YouTube PO token).
- Filename reconciled post-download via filesystem scan (`QDir::entryInfoList` by time) — yt-dlp stdout has CP1252/UTF-8 issues on Windows corrupting non-ASCII names.

**Proxy:**
- `AppSettings::proxyType` — 0=None, 1=System, 2=HTTP/HTTPS, 3=SOCKS5.
- `AppController::applyProxy()` — startup + every proxy change; sets both `QNetworkProxy::setApplicationProxy()` and `m_nam->setProxy()` directly (latter required — app proxy not always picked up by already-constructed NAM).
- `App.proxyActive` drives status bar indicator.

**Speed Limiter Scheduler:**
- Rules in `AppSettings::speedScheduleJson` — array of `{ days[], onHour, onMinute, onAmPm, offHour, offMinute, offAmPm, limitKBps }`.
- `runSpeedScheduleCheck()` in `Main.qml` runs every 60 s AND immediately on `speedScheduleEnabled`/`speedScheduleJson` change. Overnight: if `onTime > offTime`, window wraps midnight.

**Clipboard Monitoring:** `clipboardMonitorEnabled` → `AppController` connects `QClipboard::dataChanged`. Filters by `monitoredExtensions`, emits `clipboardUrlDetected(url)` (dedup via `m_lastClipboardUrl`); `Main.qml` opens `AddUrlDialog` with `titleOverride`.

**Download State Machine:** Queued → Downloading → Paused/Completed/Failed. Speed limiter, resume, segmentation thread-safe via Qt signals/slots. DownloadQueue manages concurrency (maxConcurrent), calls `SegmentedTransfer::start()`.

## SegmentedTransfer Engine Invariants

Non-obvious rules. Breaking any silently corrupts downloads or hangs UI.

**Mandatory request headers** (`applyRequestHeaders()`):
- `Accept-Encoding: identity` **required**. QNAM auto-decompresses gzip → `Content-Range` and byte offsets lie, range math breaks, files corrupted. Never remove.
- `Referer` from `m_item->referrer()` when set. Many hosts (Rapidgator, image CDNs) 403 without it.
- HEAD uses `req.setTransferTimeout(15'000)` so a dead host can't hang the item in Queued.

**Per-segment retry** (`retrySegment`, `kMaxSegmentRetries = 4`): exponential backoff 1/2/4/8 s, honoring `Retry-After`. 4xx (except 408/429) = permanent, fails immediately; 408/429/5xx = retriable. `Segment::retryCount` resets only on success.

**Stall detection** (`onProgressTick`, `kStallTimeoutMs = 30'000`): each segment stamps `lastByteTime` on readyRead. No bytes in 30 s → tick aborts+retries. Only thing catching half-open TCP connections — do not remove.

**206 vs 200 fallback** (`onSegmentReadyRead`): first chunk validates `Content-Range` — `start` must equal segment start, `total` must equal `m_item->totalBytes()`. Server returns 200 not 206 → `fallbackToSingleSegment()` collapses to one segment from 0. Don't "fix" by assuming range support.

**Content-length verification** (`onSegmentFinished`): segment marked `done` only when `received >= expectedLen`. Early EOF = failure + retry. Catches silent truncation on flaky CDNs.

**Dynamic segmentation** (`maybeStealWork`, IDM signature):
- On segment finish, slowest remaining (≥ `kStealThresholdBytes = 2 MB` left) is aborted, `endOffset` shrunk to midpoint, new segment appended for second half.
- `saveMeta()` **must** run before `startSegment()` on the new segment — crash in the split→meta-write window loses bytes on resume.
- Hard cap `kMaxDynamicSegments = 32`.

**mergeAndFinish**: sort part files by `startOffset` before concatenation — segment index order ≠ byte order with dynamic segmentation. Don't iterate `m_segments` directly.

**Speed / ETA sliding windows** (`onProgressTick`):
- `m_speedSamples` = per-tick byte-delta ring (tick 250 ms, max 120 = 30 s).
- **Display speed** = avg last 8 samples (≈ 2 s) → `setSpeed()`. Shorter = jitter on bursty connections.
- **ETA speed** = avg full 120-sample window → `setEtaSpeed()`. `timeLeft()` prefers `m_etaSpeed` so time-remaining doesn't swing with display speed.
- Pause/abort/finish must clear `m_speedSamples` and `setEtaSpeed(0)` — else resumed download shows ghost stats.

**Periodic meta save**: `saveMeta()` every 20 ticks (≈ 5 s) via `m_ticksSinceMetaSave`. Bounds crash/power-loss loss to 5 s per segment.

**Filename sanitization**: `sanitizeFilename()` in `download/SegmentedTransfer.cpp` = **single entry point**. Strips Windows-invalid chars (`<>:"/\|?*`), rejects reserved names (CON, PRN, LPT1–9...), strips trailing dots/spaces, caps at 200 bytes (room for `.stellar-part-N` under NAME_MAX 255). Any server-supplied filename must go through this — Content-Disposition especially.

**Part file cleanup**: `cleanupPartFiles()` globs `*.stellar-part-*` plus tracked segments, so orphans from aborted dynamic segmentation don't accumulate.

**TLS errors**: every reply connects `sslErrors` for logging. Do **not** call `ignoreSslErrors()` — broken cert must fail segment.

## Download Persistence Invariants

**Save triggers (`AppController::watchItem`):**
- `scheduleSave(id)` **not** wired to `doneBytesChanged`/`torrentStatsChanged` — both fire every tick (continuous writes).
- HTTP progress: throttled lambda on `doneBytesChanged`, every 4 MB or 2 s, only while `Downloading`/`Assembling`.
- Torrent up/down counters flushed by `m_torrentStatsFlushTimer` (2 min) via `flushTorrentStats()` — writes only when values changed.
- `torrentResumeDataChanged` writes `.resume` blob to `StellarPaths::resumeFile(id)` via `QSaveFile`. **Never** call `scheduleSave`/`flushDirty` — they call `saveResumeData()`, creating a feedback loop.

**Resume-data feedback loop (do not reintroduce):** `flushDirty()` must NOT call `saveResumeData()`. Loop: save → saveResumeData → alert → `setTorrentResumeData()` → `torrentResumeDataChanged` → write `.resume` (fine) AND `torrentChanged` → `scheduleSave` → `flushDirty` again — one write/sec forever.

**Torrent stats NOT persisted** (ephemeral, never add to `DownloadDatabase::save()`): `torrentSeeders/Peers/UploadSpeed/Availability/PiecesDone/Total/ActiveTimeSecs/SeedingTimeSecs/WastedBytes/Connections`. Only `torrentUploaded/Downloaded/Ratio` written to `downloads.json`.

## QML Event Handling Patterns

**Right-click menus — use `TapHandler`, not `MouseArea`:** `TapHandler` is passive, not blocked by child `MouseArea`:

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

If using `MouseArea` elsewhere, set `acceptedButtons: Qt.LeftButton` to prevent right-click interception.

**Window size changes during component swap:** defer with `Qt.callLater()` until after `Loader` swap completes:

```qml
onItemChanged: {
    // ... state updates ...
    Qt.callLater(function() { _applySize() })  // After Loader swap completes
}
```

## QML Model Scroll Preservation

When `ListView` model replaced every update from a `QVariantList` Q_PROPERTY (e.g. `DownloadItem::segmentData`), QML does full reset + view jumps; next-frame `contentY` restore still jitters.

Pattern from `DownloadProgressDialog.qml` — for high-frequency lists:
- Keep stable `ListModel` bound to `ListView`; update rows in place (`set`/`remove`/`append`), don't replace whole model.
- While scrolling (`moving`/`flicking`/`dragging`) defer structural updates; apply latest snapshot on `onMovementEnded`.
- In delegates bind role names directly (`received`, `info`), not `modelData.role`.

## Torrent Peer List Live Updates

Peer list in `FilePropertiesDialog.qml` sensitive to resets — libtorrent refreshes peers continuously, full resets jump `ListView` to top every second.

Rules for `app/src/torrent/TorrentPeerModel.cpp`:
- No full resets for normal refreshes when set can update incrementally; `beginInsertRows`/`beginRemoveRows` for peers entering/leaving.
- Data-only changes: keep row identity stable, emit `dataChanged()`. Order changes: prefer `layoutAboutToBeChanged()/layoutChanged()` over reset.
- Deterministic stable sort: `std::stable_sort()` tie-broken on identity (`endpoint|port`). Peer identity = `endpoint|port` only — client string and seed state NOT in key (change mid-session, must not cause churn).
- `kPeerRemovalGraceTicks = 3`: peer absent one refresh kept 3 ticks.
- `setStructuralUpdatesDeferred(true)`: inserts/removes queued in `m_pendingEntries` while scrolling; only `dataChanged` fires; flush on false.

Fixed jump-to-top bug: reset-style → stable incremental updates with deterministic ordering.

## Live Re-sort of the Download Table

`DownloadTableModel::m_visible` kept sorted at all times. When row data changes, model must preserve sort order without disturbing scroll position.

**Rule**: when single row's value crosses a neighbour's, move just that row with `beginMoveRows()/endMoveRows()`. Do **not** use `beginResetModel()`, `layoutAboutToBeChanged()/layoutChanged()`, or re-sort timer.

Why alternatives are wrong:
- `beginResetModel` tears down delegates, scrolls to top.
- `layoutChanged` re-anchors viewport to `currentIndex` delegate; when that row shifts far, viewport drags with it — "jumps to bottom one frame, then back to top". `Qt.callLater` snapshot/restore, clearing `currentIndex`, `positionViewAtIndex` don't reliably suppress it. Don't emit `layoutChanged` for single-row reordering.
- Coalescing re-sort timer (`layoutChanged` every 2 s) feels laggy AND still jumps.

Implementation in `DownloadTableModel::onItemProgressChanged`/`onItemChanged`:
1. Bubble changed row up/down through `m_visible` until both neighbour comparisons satisfied (precondition: sorted before change).
2. One `beginMoveRows`/`endMoveRows` for that move. Qt destination convention: moving down, destination = index *one past* where row ends up; moving up = natural index.
3. `dataChanged` for row at new position so value renders.

`kVolatileSortCols`: `downspeed`, `speed`, `upspeed`, `progress`, `timeleft`, `ratio`, `uploaded`, `downloaded`, `seeders`, `peers`, `status`. Stable columns (`name`, `size`, `saveto`...) skip bubble.

**`flushVolatileSort` must NOT emit a full-table `dataChanged` every tick.** Delegates bind directly to `DownloadItem` properties, so cell values update with no `dataChanged` — the emit is only needed to re-anchor delegates whose row *identity* changed. Skip it entirely when the sort didn't reorder; otherwise emit `{ItemRole}` only, over the changed `[lo,hi]` range. A full-range all-roles emit re-evaluates every binding in every row + triggers the QML selection recompute, and was the dominant seeding-time CPU cost.

**`m_visibleSet` / `m_itemsById` must stay in lock-step with `m_visible` / `m_items`** in every mutation path. They replaced `indexOf`/linear `itemById` that ran per-tick per-torrent (O(n²) while seeding).

**Different from `TorrentPeerModel`.** Peer list permits `layoutChanged` (whole peer set recomputed every tick); download list doesn't — rows stable, only one value changes at a time.

## Torrent Security & Peer Banning

- **Manual bans** (`banPeer(downloadId, endpoint, port, client, reason)`): adds to `m_bannedPeers` (persisted via `AppSettings::torrentBannedPeers`), calls `set_ip_filter()`. `unbanPeer(endpoint)` removes from both.
- **Auto-ban** (`torrentAutoBanAbusivePeers`/`torrentAutoBanMediaPlayerPeers`): evaluated per peer alert in `matchAutoBanRule()` → `m_temporaryBannedPeers` (session-only). Cleared via `clearTemporaryPeerBans()`.
- **Encryption** (`torrentEncryptionMode`): 0=Prefer, 1=Require, 2=Allow. Passed to `pe_settings` in `applySettings()`.
- `bannedPeers()` → `QVariantList`; `bannedPeersChanged()` on any change. `refreshPeerBanRules(settings)` re-reads flags + reapplies IP filter — call after settings change.

## Torrent Search Subsystem

- `App.torrentSearchManager` (Q_PROPERTY). Plugins = `.py` in `pluginDirectory()`; bundled copied on first run via `ensureBundledPluginsInstalled()`. `pythonAvailable` false when no Python on PATH/app dir — search disabled, `statusText` explains.
- **`refreshRuntimeState()` runs `detectPython()` on a worker thread** (`QtConcurrent::run` → `QFutureWatcher`). It spawns child processes with multi-second timeouts; calling it synchronously in the ctor stalled startup 2-3 s. Keep it off the main thread.
- `search(query)` spawns runner `QProcess`, streams JSON to `TorrentSearchResultModel`; `clearResults()` resets. Enable/disable in `AppSettings` under `disabledPluginsKey()`. `installPluginFromFile(path)`/`installPluginFromUrl(url)` copy/download `.py`, `refreshPlugins()`.

## Torrent Session Manager Invariants

- `applySettings()` must run before any `addMagnet()`/`addTorrentFile()` — creates session lazily via `ensureSession()`, starts alert timer.
- `restoreTorrent()` — re-adds persisted downloads on restart; `item->torrentSource()` decides magnet vs. .torrent.
- **Add path is split** (`addTorrentInternal` + `finalizeTorrentAdd`). Interactive adds are synchronous (`add_torrent`) so the metadata dialog populates without an alert round-trip. **Restore adds are async** (`async_add_torrent`, avoids a per-torrent session round-trip that serialised cold-start): the `DownloadItem*` rides `params.userdata`, the `add_torrent_alert` branch recovers it and calls `finalizeTorrentAdd`. So at restore time the handle does **not** exist yet — anything needing it (per-torrent speed limits) must live in `finalizeTorrentAdd`, not the restore loop.
- **Pending-pause race (VPN-leak critical):** a `pause()` before the async add lands only sets `m_pausedIds` (handle still invalid). `finalizeTorrentAdd` must honour `m_pausedIds` even when `startPaused` was false — else `torrentStopOnStartup` fails to pause a restored seeding torrent and it leaks around the VPN.
- **`m_staticMetadataApplied`:** torrent_info-derived fields (name, hash, comment, web seeds…) are applied once per torrent in `updateItemFromStatus`, not every tick — the per-tick string/`QLocale` conversions × N seeding torrents were wasted CPU.
- **Share limits** (`checkShareLimits()`): every alert tick for seeding torrents. Per-item limits override global defaults. Types: ratio (`torrentDefaultShareRatio`), seeding time (`...SeedingTimeMins`), inactive seeding time (`...InactiveSeedingTimeMins`). Action (`torrentDefaultShareLimitAction`) forwarded via `torrentShareLimitReached`; AppController decides.
- **Geo-IP** (`ensureGeoDb()`): lazily opens MaxMindDB (`STELLAR_HAS_MAXMINDDB`) in app dir, cached per IP in `GeoDbState::cache`. Without it geo fields empty — no fallback.
- **Network binding** (`torrentBindInterface`): see "Torrent Network Binding" below. Bound IPs resolved via `QNetworkInterface`, passed to `listen_interfaces` **and** `outgoing_interfaces`.
- **Torrent settings** share one `torrentSettingsChanged`; `AppController` calls `applySettings()` on every change. Settings: `torrentEnableDht/Lsd/Upnp/NatPmp`, `torrentListenPort` (6881), `torrentConnectionsLimit`, `torrentDownload/UploadLimitKBps`, share-limit defaults, `torrentCustomUserAgent`, `torrentBindInterface`, `torrentAllowDiscoveryWhenBound`, `torrentEncryptionMode`, `torrentAutoBanAbusive/MediaPlayerPeers`.
- **Sidebar subcategories** ordered by `AppSettings::torrentSubcatOrder`. IDs: `torrent_downloading`, `torrent_seeding`, `torrent_stopped`, `torrent_active`, `torrent_inactive`, `torrent_checking`, `torrent_moving`.
- **Force recheck** (`AppController::forceRecheckTorrent()`, `TorrentSessionManager::forceRecheck()`): `handle.force_recheck()`; "Verify Local Data" button in FilePropertiesDialog transfer stats.

## Torrent Network Binding & Leak Protection

Security-sensitive. Goal: torrent traffic never leaks the real IP around a VPN. Enforced at **socket level** via libtorrent `listen_interfaces` + `outgoing_interfaces` (both required — pinning one leaks the other direction), not by monitoring. **One user-facing control**, qBittorrent-style, in `AppSettings::torrentBindInterface`:

- **Empty = "Any interface"** (default): unbound. Traffic follows OS system route like every other app — already goes through VPN when VPN is the default route. Never fail-closed. No VPN auto-detection.
- **Named adapter** (e.g. `WindscribeWireGuard`): hard-bound to that interface only. If it disconnects, torrents are **paused**, not rerouted — fail-closed. `TorrentSessionManager::configureSession()`: `boundToInterface = !torrentBindInterface().isEmpty()`.

**Fail-closed binding:** a named interface with no usable address binds to **empty** `listen_interfaces`/`outgoing_interfaces` (no traffic), never the all-interfaces fallback. The `0.0.0.0`/`[::]` fallback in `applyInterfaceBinding()` (empty-`bindAddrs` branch) is **fail-open**, reachable only in the unbound "Any interface" case.

**Auto-harden when bound** (`hardenDiscovery` = `boundToInterface && !torrentAllowDiscoveryWhenBound`): force-disable **UPnP, NAT-PMP, LSD** even if user toggles are on. UPnP/NAT-PMP map ports via the LAN gateway (off-VPN, exposes listen port); LSD broadcasts to LAN; all leak around the tunnel. **Stricter than qBittorrent**, which never couples these to binding. `torrentAllowDiscoveryWhenBound` (default false, advanced) lets power users on a trusted LAN adapter opt back in. When unbound, `torrentEnableUpnp/NatPmp/Lsd` always honoured. DHT stays user-controlled (routes over bound interface, maps no LAN port). Surfaced via `AppController::torrentBindingHardened`.

**IPv6 rides the VPN.** `interfaceBindAddresses()` returns v4 and v6 of the bound interface; `applyInterfaceBinding()` binds both. A v4-only VPN yields a v4-only bind, never an all-interfaces `[::]` catch-all that would leak native IPv6.

**Suspend/recover** (`AppController::reconcileTorrentBindState()`, every 5 s via `m_tooltipTimer`, plus startup + on `torrentSettingsChanged`): only a **named** interface suspends. Wall-clock debounce: record `m_torrentBindUnavailableSinceMs` when adapter first goes unavailable; suspend only after `kBindSuspendGraceMs` (15 s). VPN adapters flap `IsUp`/`IsRunning` and drop their IP for a tick during keepalive/rekey; suspending on a single false reading drops all peers → **speed sawtooth** (original bug). Grace is wall-clock, NOT tick count, so it doesn't depend on the 5 s timer interval. Recovery immediate: `applySettings()` (rebind to fresh VPN IP) then `unsuspendSession()`. "Any interface" never suspends.

**`suspendSession()` keeps the alert timer running.** Calls `session.pause()` (stops peer traffic — the leak guard) but must **not** stop `m_alertTimer`: the alert loop still processes `save_resume_data_alert` (else crash during suspend loses recent resume data), `checkShareLimits`, UI status. `post_torrent_updates()` on a paused-but-valid session is safe.

## Live Speed & Count Properties

`AppController` Q_PROPERTYs:
- `App.totalDownSpeed`/`totalUpSpeed` — total B/s across active downloads (incl. torrent upload). Every 5 s by `m_tooltipTimer`.
- `App.seedingCount` — torrents in Seeding state.

5 s cadence (same as tray tooltip), not per-tick. `StatusBar.qml` and `Main.qml` title bind directly. Don't reduce cadence — Windows dismisses the tray tooltip on every `setToolTip()` (hover-dismiss issue).

## Common Workflows

**New named queue:** insert row into `QueueDatabase` (SQLite) → `QueueModel` auto-refreshes from DB signal → `DownloadQueue` picks up via `AppController::reloadQueues()` → Sidebar.qml renders from `queueModel` (no QML changes unless adding actions).

**New setting:** Q_PROPERTY+getter/setter/signal in AppSettings.h; member init + load/save in AppSettings.cpp (emit changed from `load()` too); `editXxx` + dirty-tracking in `settingsChanged`, plus `applySettings()`/`resetEdits()` in SettingsDialog.qml; UI control on right tab.

**Download list filtering:** edit `DownloadTableModel::matchesFilter()`; call `setFilterCategory()`/`setFilterQueue()` (triggers reset); update DownloadTable.qml visibility.

**Extension debugging:** Chrome chrome://extensions → Details → errors; Firefox about:debugging → Extensions → Stellar; native host errors in browser console + Stellar logs.

## Tips System

- Loaded from `tips.txt` (embedded QML module resource), shown in status bar, rotates every 6 hours. Cycle "next >>" / close "✕". Persisted in `AppSettings.showTips`.

## QML Performance Rules

**Never nest Repeater inside ListView delegate.** Each Repeater item creates a QQmlContext per row — K items × N rows = K×N contexts per reset. Caused 2–3 s freeze switching categories. Instead:
- Hardcoded `Item` elements with `visible` bindings for column visibility.
- **Single shared context menu** at ListView root with `property var _ctxItem`; never `Menu` inside delegate.

**`reuseItems: true`** helps only when pool already has items — not when switching from empty category (pool empty, all delegates fresh).

**QQmlContext cost** ~10 ms each. 15 rows × 7-col Repeater = ~105 contexts = >1 s just in allocation.

## QML UI Conventions

**Dark theme palette:**
- Backgrounds: `#1e1e1e` (dialogs), `#1b1b1b` (inputs), `#252525` (panels). Borders: `#3a3a3a` default, `#4488dd` focus.
- Text: `#e0e0e0` primary, `#aaaaaa` secondary, `#666666` disabled. Accent `#4488dd`; active pill: `#1a3a6a` bg / `#4488dd` border. Info notes: `#1a2030` bg / `#2a3050` border / `#8899bb` text.

**Compact time inputs** (schedulers): `Rectangle { width:50; height:26; radius:2; color:"#1b1b1b"; border.color: field.activeFocus ? "#4488dd" : "#3a3a3a" }` wrapping `TextInput`. AM/PM: `ComboBox` `implicitWidth:62; implicitHeight:26`, custom `contentItem`/`background`/`indicator` (▼ at 8px).

**Menu bar items**: `component CompactMenuItem: MenuItem` inside `MenuBar` in `Main.qml`. All top-level `Menu` use `delegate: CompactMenuItem; implicitWidth: 200; topPadding: 0; bottomPadding: 0`. Submenus need same three. Rows **must paint opaque background** — see "Linux Software-Backend Menus".

**All dialogs are `Window`** (not `Dialog`) — open via `.show(); .raise(); .requestActivate()`, never `.open()`.

**FilePropertiesDialog patterns:**
- Window size changes deferred via `Qt.callLater()` in `onItemChanged` (prevents corruption switching HTTP/torrent).
- General tab uses cards (`#1e1e1e` bg, `#2d2d2d` border, 3px radius); Torrent Info / Save Location / Transfer Stats split by dividers.
- Transfer Stats GridLayout: 8px col / 4px row; labels `#8899aa`, values `#c8c8c8`; "Verify Local Data" bottom-right.
- File list delegates use `TapHandler` for right-click rename.

## Linux Software-Backend Menus (transparency fix)

Without usable hardware OpenGL the app runs on the Qt Quick software scene graph (`selectWorkingGraphicsBackend()` in `main.cpp`; VirtualBox/SVGA3D has no GLX FBConfig). There the Menu's background node doesn't reliably composite, so any `MenuItem` with `"transparent"` background shows the window straight through.

**Rule:** every menu row and separator **must paint an OPAQUE background**. `ColorPalette.menuBg` for rows, `ColorPalette.selectionBg` when highlighted.

Applies to the inline `MenuItem` subcomponents the real menus define — `CompactMenuItem` (`Main.qml`), `CtxMenuItem`/`ColCheckMenuItem` (`DownloadTable.qml`) — **not** just `app/style/MenuItem.qml`. **Inline definitions override the custom style**, so fixing only the style file does nothing. Original bug: edits to `app/style/*.qml` the actual menus never used.

**Not the cause (don't reintroduce):** Material elevation shadow ShaderEffect layer, `Popup.Window` vs `Popup.Item`. `popupType: T.Popup.Item` in `app/style/Menu.qml` is correct but didn't fix transparency — opaque row backgrounds did.

Style ships via hand-authored qmldir + `qt_add_resources` under `/qt/qml/Stellar`: `Menu.qml`, `MenuItem.qml`, `MenuSeparator.qml`. Style `MenuSeparator` is opaque so bare `MenuSeparator{}` covered app-wide.

## Internationalisation (i18n)

**Architecture:** Qt Linguist (`tr()`/`qsTr()`). Translator loaded at startup before the QML engine so `qsTr()` in component construction resolves.

**Adding new strings — mandatory workflow:** every new user-visible string goes in `translations/stellar_en.ts`. `fill_translations.py` reads it, LLM-translates into all 76 other languages. Do **not** run `lupdate` manually; do **not** edit other `.ts` files directly.

**Files:**
- `translations/stellar_en.ts` — **source of truth**. Add every new `tr()`/`qsTr()` string here.
- `.qm` compiled at build by `qt_add_translations()` in `CMakeLists.txt` (needs `Qt6LinguistTools`; guarded `if(Qt6LinguistTools_FOUND)`).
- Embedded as resources under `:/i18n/` → loaded `:/i18n/stellar_<locale>`.

**Setting:** `AppSettings::uiLanguage` — persisted locale (`""` = English, `"fr"` = French). Loaded/saved in `load()`/`save()`.

**Runtime:** `AppController::applyUiLanguage(locale)` removes old translator, installs new, calls `setUiLanguage()`. From `main.cpp` before QML loads, and `SettingsDialog::applySettings()` on change.

**Settings tab:** Language is index **11** (between Associations=10 and About=12). `pageLanguage: 11`, `pageAbout: 12`; `settingsPageAbout` in `Main.qml` is **12**.

**Adding a language:** add `translations/stellar_XX.ts` (copy fr.ts, set `language="xx_XX"`); add to `qt_add_translations(TS_FILES ...)`; add `LangOption { langCode:"xx"; langLabel:"..."; langNative:"..." }` to Language tab; `lupdate`, translate, rebuild.

## Update System

- `checkForUpdates(bool manual)` — fetches `updateMetadataUrl()` JSON, then changelog separately. `finishUpdateCheckUi()`; "no update" fires immediately on response.
- Windows: auto-check shows `updateAvailableDialog` "Update Now" (`startUpdateInstall()` downloads `.exe` as regular item, launches). Linux/macOS: dialog on manual check, "Update Now" hidden (`visible: Qt.platform.os === "windows"`).
- `fetchChangelog()` — unconditional; "What's New" in About.

## AppSettings Persistence Patterns

New persistent field: add member+getter to `AppSettings.h`; load in `load()` with default; save in `save()`. Plus:
- **One-time-init fields** (`installDate`, `totalStartups`): write and `sync()` immediately in `load()` on first run — don't rely on later `save()`.
- **Accumulator fields** (`totalUptimeSecs`): dedicated `accumulateXxx()` that increments + `save()`; don't wire to frequently-firing signals.

## StatusBar Signal Routing

`StatusBar.qml` can't reference dialog IDs in `Main.qml`. Pattern: declare `signal` on `StatusBar` (e.g. `statisticsRequested()`), emit from `MouseArea`, handle in `Main.qml` at the `StatusBar { onStatisticsRequested: ... }` instantiation.

## Session vs. All-Time Transfer Bytes

`DownloadItem::torrentUploaded`/`torrentDownloaded` and `doneBytes` are **all persisted to `downloads.json`** and restored on startup — NOT session-only. For true session-only transfer:
- Snapshot sum of restored torrent bytes after DB restore (in `m_restoring = false` callback).
- Store as `m_sessionBaselineUploaded`/`m_sessionBaselineDownloaded`.
- Session bytes = live sum − baseline (clamped to 0).
- Never use HTTP `doneBytes` for session stats — reflects full historical size.

## QML Fixed-Size Dialogs

Non-resizable: `flags: Qt.Window | Qt.WindowCloseButtonHint | Qt.WindowTitleHint | Qt.MSWindowsFixedSizeDialogHint`. Size to content: bind `height` to root layout implicit height (`mainCol.implicitHeight + 16`), anchor layout to three sides (`left`/`right`/`top`), not `fill: parent`.

## File Organization Notes

- C++ headers use `#pragma once`. QML files named for root element (`AddUrlDialog.qml` → `Window { id: root }`). CMakeLists.txt order: sources, headers, QML, resources. Icons in `app/qml/icons/` (SVG/ICO). `THIRD-PARTY-NOTICES.txt` — LGPL/GPL compliance, bundled by installer, referenced in About.