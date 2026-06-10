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

// ── DataPortability ──────────────────────────────────────────────────────────
//
// Bundles every user-data file Stellar owns into a single, self-describing
// backup file, and restores such a file onto a (possibly fresh) install.
//
// Container format (.stellarbackup) — one JSON document:
//
//   {
//     "stellar_export_version": 1,
//     "app_version": "0.1.0",
//     "created": "2026-05-31T12:00:00Z",
//     "files": {
//       "settings.ini":        "<base64>",
//       "data/downloads.json": "<base64>",
//       "resume/<id>.resume":  "<base64>",
//       ...
//     }
//   }
//
// Every key under "files" is a path relative to StellarPaths::root(); on import
// the bytes are written back to "<root>/<key>".  Only Qt-core classes are used
// (no archive library is available, and libtorrent is optional) so the format
// stays buildable in every configuration.
//
// Regenerable data (cache/, bin/, geo/) is deliberately excluded — the app
// re-creates or re-downloads it on demand.

namespace DataPortability {

struct Result {
    bool    ok = false;
    QString error;          // human-readable, empty when ok
};

// Current container schema version. Bump on incompatible format changes.
constexpr int kExportVersion = 1;

// Collect every user-data file and write the backup container to destPath.
// The caller is responsible for flushing in-memory state to disk first.
Result exportTo(const QString &destPath);

// Read and validate a backup container, then write every embedded file back
// under StellarPaths::root(). When backupExisting is true the current data
// tree is copied to a timestamped sibling directory before anything is
// overwritten. The application must be restarted afterwards for the restored
// data to take effect.
Result importFrom(const QString &srcPath, bool backupExisting);

} // namespace DataPortability
