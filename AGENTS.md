# OpenCode Instructions: Stellar Download Manager

## 🏗️ Build & Run
- **Root-only**: Run all CMake commands from the **project root** (`downloadmanager/`), not `build/`.
- **Build**: `cmake --preset windows-debug` then `cmake --build --preset windows-debug`
- **Linux Equivalents**: `cmake --preset linux-debug` then `cmake --build --preset linux-debug`
- **Run**: `./build/windows-debug/Stellar.exe`
- **QML Console Debugging**: Set `WIN32_EXECUTABLE FALSE` in `CMakeLists.txt` to get a console window for QML engine errors. Restore to `TRUE` after debugging.
- **Adding files**: Update `CMakeLists.txt` (`QML_FILES`, `BACKEND_SOURCES`, `BACKEND_HEADERS`). If adding `.c` files, add `C` to the `project(LANGUAGES CXX)` line.
- **Testing**: No automated tests exist. Build and test manually via the UI.

## 🏛️ Architecture & Constraints
- **Strict Layers**: QML -> `App` (Context Property) -> `AppController` (Facade). No upward references.
- **QML Interface**: `App` is the **only** C++ object directly exposed to QML. QML mutations must route through `AppController` (e.g., `DownloadTableModel` is read-only).
- **Qt Usage**:
  - Uses `QGuiApplication`. **NEVER** `#include <QApplication>` or use `QWidget`/`QMenu`. (Tray context menu is a standalone QML `Window`).
  - Persistence uses JSON (`QJsonDocument`). **NEVER** add `Qt6::Sql`.
  - Only **one** shared `QNetworkAccessManager` is allowed (owned by `AppController`).
- **Browser Extension IPC**: Extensions send a JSON message via native messaging, which forwards to `AppController` via IPC. Cookies are passed to QML and retrieved via `App.takePendingCookies()`.

## ⚠️ Domain Quirks & Gotchas
- **Speed Throttling**: When pausing a download, **discard** `seg.pending` (do not flush it). Flushing on pause causes the download to appear near-complete on resume, breaking the token-bucket throttle.
- **Google Drive Resumes**: When `Content-Disposition` changes the filename mid-download, you **must** rename the actual `.stellar-part-X` file on disk and update `seg.file` before updating `seg.partPath`. Otherwise, `mergeAndFinish` renames a non-existent file and drops data.
- **Settings State**: In `SettingsDialog.qml`, edit properties must use plain defaults (e.g., `property int editFoo: 0`). Using live bindings (`App.settings.foo`) breaks the "Apply" button by keeping `settingsChanged` falsely evaluated.
- **Queue Deletion**: Removing a queue only clears the assignment (`queueId=""`). Never delete the actual download item from queue-management UI.
- **Native OS Drag & Drop**: QML's built-in Drag-and-Drop has MIME limitations. For dragging files to Explorer, instantiate `FileDragDropHelper` and call `startDrag(filePath)`.

## 📝 Conventions
- **License**: Every new `.cpp`, `.h`, and `.qml` file MUST begin with the GNU GPL v3.0 header (Copyright (C) 2026 Ninka_).