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
#include <QFileIconProvider>
#include <QHash>
#include <QPixmap>
#include <QIcon>
#include <QFileInfo>

class FileIconImageProvider : public QQuickImageProvider
{
public:
    explicit FileIconImageProvider()
        : QQuickImageProvider(QQuickImageProvider::Pixmap)
    {
        generateFastIcons();
    }

    QPixmap requestPixmap(const QString &id, QSize *size, const QSize &requestedSize) override
    {
        const int sz = requestedSize.isValid() ? qMax(requestedSize.width(), requestedSize.height()) : 32;

        // Strip query string (e.g. "?c=1") appended by QML to bust its image cache
        // when a download completes and we need to switch from the extension-based
        // placeholder to the real on-disk file icon.
        const int qmark = id.indexOf(QLatin1Char('?'));
        const QString cleanId = qmark >= 0 ? id.left(qmark) : id;

        auto returnPixmap = [&](const QPixmap &src) -> QPixmap {
            QPixmap px = src;
            if (requestedSize.isValid() && !px.isNull())
                px = px.scaled(requestedSize, Qt::KeepAspectRatio, Qt::SmoothTransformation);
            if (size) *size = px.size();
            return px;
        };

        // Fast path: return from cache without filesystem access
        {
            auto it = m_pathCache.constFind(cleanId);
            if (it != m_pathCache.constEnd())
                return returnPixmap(it.value());
        }

        // CRITICAL: Check filesystem FIRST for real files - this gets custom EXE icons
        QFileInfo fi(cleanId);
        if (fi.exists()) {
            const QIcon icon = m_iconProvider.icon(fi);
            const QPixmap px = icon.pixmap(sz, sz);
            m_pathCache.insert(cleanId, px);
            return returnPixmap(px);
        }

        // File doesn't exist yet (still downloading) — use extension-based icon
        const int dotPos = cleanId.lastIndexOf(QLatin1Char('.'));
        const QString ext = (dotPos >= 0) ? cleanId.mid(dotPos + 1).toLower() : QString();
        const QString cacheKey = ext.isEmpty() ? QStringLiteral("__noext__") : ext;

        // Check extension cache
        {
            auto it = m_extCache.constFind(cacheKey);
            if (it != m_extCache.constEnd())
                return returnPixmap(it.value());
        }

        // Use fast pre-computed icon for extension
        auto fastIt = m_fastIcons.constFind(cacheKey);
        if (fastIt != m_fastIcons.constEnd()) {
            m_extCache.insert(cacheKey, fastIt.value());
            return returnPixmap(fastIt.value());
        }

        // Fallback: generate and cache
        const QString dummy = ext.isEmpty() ? QStringLiteral("file") : (QStringLiteral("file.") + ext);
        const QIcon icon = m_iconProvider.icon(QFileInfo(dummy));
        const QPixmap px = icon.pixmap(sz, sz);
        m_extCache.insert(cacheKey, px);
        return returnPixmap(px);
    }

private:
    void generateFastIcons()
    {
        const QStringList commonExts = {
            QStringLiteral("exe"), QStringLiteral("zip"), QStringLiteral("rar"),
            QStringLiteral("7z"), QStringLiteral("tar"), QStringLiteral("gz"),
            QStringLiteral("pdf"), QStringLiteral("doc"), QStringLiteral("docx"),
            QStringLiteral("xls"), QStringLiteral("xlsx"), QStringLiteral("ppt"),
            QStringLiteral("pptx"), QStringLiteral("txt"), QStringLiteral("rtf"),
            QStringLiteral("jpg"), QStringLiteral("jpeg"), QStringLiteral("png"),
            QStringLiteral("gif"), QStringLiteral("bmp"), QStringLiteral("svg"),
            QStringLiteral("mp3"), QStringLiteral("wav"), QStringLiteral("flac"),
            QStringLiteral("mp4"), QStringLiteral("avi"), QStringLiteral("mkv"),
            QStringLiteral("mov"), QStringLiteral("html"), QStringLiteral("htm"),
            QStringLiteral("css"), QStringLiteral("js"), QStringLiteral("json"),
            QStringLiteral("xml"), QStringLiteral("py"), QStringLiteral("cpp"),
            QStringLiteral("h"), QStringLiteral("c"), QStringLiteral("java"),
            QStringLiteral("jar"), QStringLiteral("msi"), QStringLiteral("deb"),
            QStringLiteral("rpm"), QStringLiteral("dmg"), QStringLiteral("iso")
        };

        const int sz = 32;
        for (const QString &ext : commonExts) {
            const QString dummy = QStringLiteral("file.") + ext;
            const QIcon icon = m_iconProvider.icon(QFileInfo(dummy));
            m_fastIcons.insert(ext, icon.pixmap(sz, sz));
        }
        m_fastIcons.insert(QStringLiteral("__noext__"), m_iconProvider.icon(QFileInfo(QStringLiteral("file"))).pixmap(sz, sz));
    }

    QFileIconProvider m_iconProvider;
    QHash<QString, QPixmap> m_fastIcons;
    QHash<QString, QPixmap> m_extCache;
    QHash<QString, QPixmap> m_pathCache;
};