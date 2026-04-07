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

#include "FileIconImageProvider.h"
#include <QFileIconProvider>
#include <QFileInfo>
#include <QIcon>
#include <QPixmap>

FileIconImageProvider::FileIconImageProvider()
    : QQuickImageProvider(QQuickImageProvider::Pixmap)
{}

QPixmap FileIconImageProvider::requestPixmap(const QString &id,
                                              QSize *size,
                                              const QSize &requestedSize)
{
    // id may be a full path (e.g. "C:/Downloads/tool.exe") or just a filename.
    // If the file exists on disk, ask the OS for its actual icon — this gives
    // EXEs their embedded custom icon instead of the generic executable icon.
    // Otherwise fall back to extension-based lookup (cached).
    const int sz = requestedSize.isValid() ? qMax(requestedSize.width(), requestedSize.height()) : 32;
    QFileIconProvider provider;
    QFileInfo fi(id);

    if (fi.exists()) {
        // Real file — OS returns the embedded icon (e.g. custom EXE icon).
        // Cache by full path so different EXEs get their own icons.
        if (!m_pathCache.contains(id)) {
            const QIcon icon = provider.icon(fi);
            m_pathCache[id] = icon.pixmap(sz, sz);
        }
        QPixmap px = m_pathCache[id];
        if (requestedSize.isValid() && !px.isNull())
            px = px.scaled(requestedSize, Qt::KeepAspectRatio, Qt::SmoothTransformation);
        if (size) *size = px.size();
        return px;
    }

    // File doesn't exist yet — use extension-based generic icon (cached).
    const QString ext = fi.suffix().toLower();
    const QString cacheKey = ext.isEmpty() ? QStringLiteral("__noext__") : ext;

    if (!m_cache.contains(cacheKey)) {
        const QString dummy = ext.isEmpty() ? QStringLiteral("file") : (QStringLiteral("file.") + ext);
        const QIcon icon = provider.icon(QFileInfo(dummy));
        m_cache[cacheKey] = icon.pixmap(sz, sz);
    }

    QPixmap px = m_cache[cacheKey];
    if (requestedSize.isValid() && !px.isNull())
        px = px.scaled(requestedSize, Qt::KeepAspectRatio, Qt::SmoothTransformation);
    if (size) *size = px.size();
    return px;
}
