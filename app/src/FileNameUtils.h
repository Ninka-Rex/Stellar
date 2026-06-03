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

class QIODevice;
class QFile;

// Shared filename / path / file-copy helpers. Defined in SegmentedTransfer.cpp.
// Both the HTTP (SegmentedTransfer) and FTP (FtpTransfer) engines route every
// server-supplied filename through sanitizeFilename() — the single sanitize
// entry point mandated by the project security rules.

// Strip characters invalid in filenames on Windows (and problematic on FAT/NTFS),
// reject reserved device names, collapse "."/"..", strip trailing dots/spaces,
// and cap length to leave room for ".stellar-part-NN" suffixes. Never returns empty.
QString sanitizeFilename(const QString &in);

// On Windows, prefix absolute paths approaching MAX_PATH (260) with \\?\ so the
// long-path API is used. No-op elsewhere or for short paths.
QString longPath(const QString &path);

// Stream up to maxBytes (or until EOF when maxBytes < 0) from src to dst.
// Returns false and sets *errorOut on a write failure.
bool copyFileContents(QIODevice &src, QIODevice &dst, qint64 maxBytes = -1,
                      QString *errorOut = nullptr);

// Memory-map-assisted copy of `size` bytes from src[srcOff] to dst[dstOff],
// falling back to streaming when mapping fails. Returns false on error.
bool mappedRangeCopy(QFile &src, qint64 srcOff, qint64 size,
                     QFile &dst, qint64 dstOff, QString *errorOut = nullptr);
