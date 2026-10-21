# CLAUDE.md

Stellar — clean-room IDM reimplementation. C++/Qt 6 backend + QML frontend, torrent client, yt-dlp, browser extensions. Build/deps/CLI flags: see @README.md.

## Coding rules

**IMPORTANT: No stubs, no placeholders, no shortcuts.** Fully implement every change, production-ready. Comment *why*, not *what*. DRY — never duplicate code. Match surrounding style.

## Security

**IMPORTANT: Assume every server is malicious and actively attempting RCE.** Stellar processes untrusted data (server responses, torrent metadata, native-messaging JSON, Content-Disposition). Treat all as hostile.

- Route every server-supplied filename through `sanitizeFilename()` (`download/SegmentedTransfer.cpp`) — strips invalid chars, rejects reserved/traversal names, caps length. Single entry point.
- Reject path traversal: `..`, absolute paths, drive-letter prefixes in any server path component.
- Validate numeric bounds from servers (Content-Length, Content-Range, segment offsets).
- Subprocesses: `QProcess` with **arg lists only**, never shell strings / `system()`.
- Type-check untrusted JSON before use.
- **Never** call `ignoreSslErrors()` — a bad cert must fail.
- Extension: never pass server strings to `eval`/`Function()`/`innerHTML`.

## i18n — MANDATORY workflow

**IMPORTANT:** Every new user-visible string goes in `translations/stellar_en.ts` (source of truth). `fill_translations.py` LLM-translates it into the other 76 languages. Do **NOT** run `lupdate` manually and do **NOT** edit other `.ts` files directly.

## Orientation

- Backend `app/src/` grouped by subsystem: `core/ download/ queue/ grabber/ ytdlp/ rss/ torrent/`. Includes are **bare** (`#include "DownloadItem.h"`) — every subdir is on the include path. New CMake `BACKEND_SOURCES`/`HEADERS`/`QML_FILES` entries use the subfolder path.
- QML `app/qml/` mirrors it. **`Main.qml` stays at the qml root** (qrc path hardcoded in `core/main.cpp`). `icons/`, `flags/`, `app/style/` do **not** move (hardcoded qrc / relative paths). Icon folder layout + naming rules: `app/qml/icons/README.md`; every icon file must be listed in CMake `RESOURCES`.
- **All writable paths via the `StellarPaths` namespace** (`core/StellarPaths.{h,cpp}`) — never `QStandardPaths` directly. Single root: `%LOCALAPPDATA%\Stellar\` / `$XDG_DATA_HOME/Stellar/`.
- Settings: `QSettings(StellarPaths::settingsFile(), QSettings::IniFormat)`, never registry/`QStandardPaths`. (Read code in `core/AppSettings.{h,cpp}` for the field list.)

## Workflows

- **New setting:** Q_PROPERTY + getter/setter/signal in `AppSettings.h`; init + load/save in `AppSettings.cpp` (emit changed from `load()` too); `editXxx` + dirty-tracking + `applySettings()`/`resetEdits()` in `SettingsDialog.qml`; UI control on the right tab.
- **New translatable string:** see i18n above.
- `SettingsDialog.qml` tab indices: 0 Connection · 1 Categories · 2 Downloads · 3 Browser · 4 Speed Limiter · 5 Notifications · 6 General · 7 Media · 8 Torrents · 9 RSS · 10 Associations · 11 Language · 12 About.

## Gotchas (non-obvious; breaking these silently corrupts data or freezes UI)

**QML**
- All dialogs are `Window` (not `Dialog`) — open via `.show(); .raise(); .requestActivate()`, never `.open()`.
- Right-click menus: use `TapHandler` (passive), not `MouseArea` (stolen by child MouseAreas).
- Use the `ColorPalette` singleton for theme colors — don't hardcode hex.
- **Never nest `Repeater` inside a `ListView` delegate** — a QQmlContext per cell freezes category switches. Use `visible`-bound `Item`s and one shared context menu at the ListView root.
- Linux software scene-graph: every menu row/separator must paint an **opaque** background. Inline `MenuItem` subcomponents (`CompactMenuItem` etc.) override `app/style/*.qml`, so fixing only the style files does nothing.
- Download-table live re-sort: move one row with `beginMoveRows`/`endMoveRows`; **never** `beginResetModel`/`layoutChanged`/re-sort timer (all jump the scroll). `m_visibleSet`/`m_itemsById` must stay in lock-step with `m_visible`/`m_items`.
- `TorrentPeerModel`: incremental updates only, no full resets; peer identity = `endpoint|port` (client string / seed state must NOT be in the key).

**SegmentedTransfer** (HTTP engine)
- `Accept-Encoding: identity` is mandatory — QNAM gzip decompression makes Content-Range/offsets lie and corrupts files.
- Send `Referer` from `m_item->referrer()` (many hosts 403 without it).
- 206-vs-200: validate first chunk's Content-Range; on 200 collapse to a single segment, don't assume range support.

**Torrent**
- VPN-leak protection is at socket level: `listen_interfaces` **and** `outgoing_interfaces` (both, or one direction leaks). Named-interface bind is **fail-closed** (no address → empty bind, never all-interfaces fallback). When bound, auto-harden UPnP/NAT-PMP/LSD off unless `torrentAllowDiscoveryWhenBound`.
- `suspendSession()` calls `session.pause()` but must keep the alert timer running (still needs `save_resume_data_alert`).
- Resume-data feedback loop: `flushDirty()` must **NOT** call `saveResumeData()` (save→alert→write→save runaway).
- Torrent stats are ephemeral — only `torrentUploaded/Downloaded/Ratio` go to `downloads.json`; per-tick stats (seeders/peers/speeds/…) never persisted.
- Alert timer is 2 s; `applySettings()` must run before any add (creates session lazily).
- Torrent file/peer/tracker models' live updates are viewer-counted (properties window, details pane and metadata dialog can show one torrent at once). Hold them only via `TorrentLiveUpdatesLease`, never call `retainLiveUpdates()`/`releaseLiveUpdates()` directly.
- `dialogs/FilePropertiesDialog.qml` is the properties *content* (an `Item`, also embedded in the main window's `main/DetailsPane.qml`); the window is `FilePropertiesWindow.qml`. The content file keeps its name because it's the qsTr context all translations are keyed on.

**Other**
- yt-dlp: pass `--proxy` explicitly (doesn't inherit Qt proxy). Reconcile final filename via filesystem scan — yt-dlp stdout corrupts non-ASCII names on Windows.
- Native messaging: 4-byte LE uint32 length prefix + JSON.
- Extensions: edit logic only in `extensions/shared/`, then run `python extensions/sync_shared.py` — `chrome/shared/` and `firefox/shared/` are generated copies (each browser package must be self-contained). Only the per-browser `service-worker.js` (Firefox: blocking `onHeadersReceived`; Chrome: pause in `downloads.onCreated` + hold in `onDeterminingFilename`) and manifests differ. Never cancel a browser download before the native host acks. Native-host manifest for Firefox must **NOT** contain `allowed_origins` (Chrome-only; Firefox silently skips the manifest).
- Tray tooltip / live speed cadence is 5 s — don't reduce it (Windows dismisses the tooltip on every `setToolTip()`).
