// Stellar Download Manager
// Copyright (C) 2026 Ninka_
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.

#pragma once
#include <QString>

// ── StellarPaths ─────────────────────────────────────────────────────────────
//
// Single source of truth for every on-disk path Stellar uses.
//
// All writable application data lives under one root directory:
//
//   Windows : %LOCALAPPDATA%\Stellar\          (e.g. C:\Users\Alice\AppData\Local\Stellar\)
//   Linux   : $XDG_DATA_HOME/Stellar/          (e.g. /home/alice/.local/share/Stellar/)
//
// Layout
// ──────
//   <root>/
//   ├── settings.ini              ← all QSettings (INI on every platform)
//   ├── data/
//   │   ├── downloads.json        ← download list (no inline resume blobs)
//   │   ├── queues.json
//   │   ├── categories.json
//   │   └── grabber_projects.json
//   ├── resume/
//   │   └── <download-id>.resume  ← one bencoded libtorrent resume blob per torrent
//   ├── plugins/
//   │   ├── search/               ← torrent search plugins (*.py)
//   │   └── torrent_search_runner.py
//   ├── bin/
//   │   ├── yt-dlp[.exe]
//   │   ├── ffmpeg[.exe]
//   │   └── ffprobe[.exe]
//   ├── geo/
//   │   └── dbip-city-lite-*.mmdb
//   └── cache/
//       ├── qtpipelinecache-*         ← RHI shader pipeline cache (Qt 6.5+)
//       └── qmlcache/                 ← QML bytecode cache
//
// Migration
// ─────────
// On first launch after upgrading from the old layout
// (%APPDATA%\StellarDownloadManager\StellarDownloadManager\ on Windows,
// $XDG_DATA_HOME/StellarDownloadManager/ on Linux) the runtime calls
// StellarPaths::migrateIfNeeded() which silently moves every recognised file
// to its new location and removes the old directory tree.
//
// All paths are returned as clean forward-slash strings regardless of platform.
// Use QDir::toNativeSeparators() only at the point of display or OS API calls.

namespace StellarPaths {

// ── Root ─────────────────────────────────────────────────────────────────────

// The one writable root directory for all Stellar data.
// Created on first call if it does not exist.
QString root();

// ── Sub-directories ───────────────────────────────────────────────────────────

// <root>/data/    — JSON databases (downloads, queues, categories, grabber)
QString dataDir();

// <root>/resume/  — per-torrent libtorrent fast-resume blobs
QString resumeDir();

// <root>/plugins/ — search runner script and plugin sub-directories
QString pluginsDir();

// <root>/plugins/search/  — user torrent-search plugins (*.py files)
QString searchPluginsDir();

// <root>/bin/     — yt-dlp, ffmpeg, ffprobe binaries
QString binDir();

// <root>/geo/     — MaxMindDB geo-IP databases
QString geoDir();

// <root>/cache/   — Qt RHI pipeline cache and QML bytecode cache
QString cacheDir();

// ── Individual files ──────────────────────────────────────────────────────────

// <root>/settings.ini  — all QSettings stored as INI (cross-platform)
QString settingsFile();

// <root>/data/downloads.json
QString downloadsFile();

// <root>/data/queues.json
QString queuesFile();

// <root>/data/grabber_projects.json
QString grabberProjectsFile();

// <root>/data/rss_feeds.json
QString rssFeedsFile();

// <root>/data/rss_rules.json
QString rssRulesFile();

// <root>/plugins/torrent_search_runner.py
QString searchRunnerFile();

// <root>/resume/<id>.resume  — fast-resume blob for one torrent download
QString resumeFile(const QString &downloadId);

// ── Migration ─────────────────────────────────────────────────────────────────

// Silently migrates data from the legacy layout to the current one.
// Safe to call on every startup — is a no-op once migration is complete.
void migrateIfNeeded();

} // namespace StellarPaths
