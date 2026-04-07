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
#include <QQuickImageProvider>
#include <QHash>
#include <QPixmap>

// Resolves "image://fileicon/<path-or-filename>" to the OS file-type icon.
// If the path points to an existing file, the actual embedded icon is returned
// (e.g. a custom EXE icon).  Otherwise a generic extension-based icon is used.
// Results are cached: per-extension for generic lookups, per-path for real files.
class FileIconImageProvider : public QQuickImageProvider
{
public:
    FileIconImageProvider();

    QPixmap requestPixmap(const QString &id, QSize *size,
                          const QSize &requestedSize) override;

private:
    QHash<QString, QPixmap> m_cache;      // extension → pixmap (generic)
    QHash<QString, QPixmap> m_pathCache;  // full path → pixmap (real file icons)
};
