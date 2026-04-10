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

#include <QQuickAsyncImageProvider>
#include <QFileIconProvider>
#include <QHash>
#include <QPixmap>
#include <QIcon>
#include <QFileInfo>
#include <QRunnable>
#include <QThreadPool>
#include <QMutex>
#ifdef Q_OS_WIN
#  include <objbase.h>
#endif

// Shared icon cache — accessed by worker threads, protected by mutex.
// Keyed by full path (for existing files) or "__ext__<ext>" (for extension fallback).
struct IconCache {
    QMutex mutex;
    QHash<QString, QPixmap> cache;
    QFileIconProvider iconProvider;

    static IconCache &instance() {
        static IconCache s;
        return s;
    }

    // Populate common extensions at startup so first renders are instant.
    void preload()
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
        QMutexLocker locker(&mutex);
        for (const QString &ext : commonExts) {
            const QString key = QStringLiteral("__ext__") + ext;
            if (!cache.contains(key)) {
                const QIcon icon = iconProvider.icon(QFileInfo(QStringLiteral("file.") + ext));
                cache.insert(key, icon.pixmap(32, 32));
            }
        }
        const QString noExtKey = QStringLiteral("__ext____noext__");
        if (!cache.contains(noExtKey)) {
            cache.insert(noExtKey, iconProvider.icon(QFileInfo(QStringLiteral("file"))).pixmap(32, 32));
        }
    }

    QPixmap get(const QString &cleanId, int sz)
    {
        // 1. Full-path cache — hit means we already fetched the real icon for this file.
        {
            QMutexLocker locker(&mutex);
            auto it = cache.constFind(cleanId);
            if (it != cache.constEnd())
                return scaled(it.value(), sz);
        }

        // 2. Filesystem check BEFORE extension cache — existing files (e.g. completed
        //    EXE downloads with custom embedded icons) must be looked up by full path.
        //    Checking extension cache first would return the generic EXE icon instead.
        QFileInfo fi(cleanId);
        if (fi.exists()) {
            const QIcon icon = iconProvider.icon(fi);  // SHGetFileInfo — needs COM STA
            const QPixmap px = icon.pixmap(32, 32);
            {
                QMutexLocker locker(&mutex);
                cache.insert(cleanId, px);
            }
            return scaled(px, sz);
        }

        // 3. Extension cache — only reached for files that don't exist yet (in-progress
        //    or paused downloads). Safe to use generic icon here.
        const int dotPos = cleanId.lastIndexOf(QLatin1Char('.'));
        const QString ext = (dotPos >= 0) ? cleanId.mid(dotPos + 1).toLower() : QString();
        const QString extKey = QStringLiteral("__ext__") + (ext.isEmpty() ? QStringLiteral("__noext__") : ext);
        {
            QMutexLocker locker(&mutex);
            auto it = cache.constFind(extKey);
            if (it != cache.constEnd())
                return scaled(it.value(), sz);
        }

        // 4. Generate and cache extension icon.
        const QString dummy = ext.isEmpty() ? QStringLiteral("file") : (QStringLiteral("file.") + ext);
        const QIcon icon = iconProvider.icon(QFileInfo(dummy));
        const QPixmap px = icon.pixmap(32, 32);
        {
            QMutexLocker locker(&mutex);
            cache.insert(extKey, px);
        }
        return scaled(px, sz);
    }

private:
    IconCache() = default;

    static QPixmap scaled(const QPixmap &src, int sz) {
        if (sz == 32 || src.isNull()) return src;
        return src.scaled(sz, sz, Qt::KeepAspectRatio, Qt::SmoothTransformation);
    }
};

// Async response object — does the actual work on a thread pool thread.
class FileIconResponse : public QQuickImageResponse, public QRunnable
{
public:
    FileIconResponse(const QString &id, const QSize &requestedSize)
        : m_id(id), m_requestedSize(requestedSize)
    {
        setAutoDelete(false);
    }

    QQuickTextureFactory *textureFactory() const override
    {
        return QQuickTextureFactory::textureFactoryForImage(m_image);
    }

    void run() override
    {
        // QFileIconProvider::icon() calls SHGetFileInfo on Windows, which requires
        // COM to be initialized as STA on the calling thread. Thread pool threads
        // don't have COM initialized by default — without this, real file icons
        // (e.g. custom EXE icons) silently fall back to the generic shell icon.
#ifdef Q_OS_WIN
        CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
#endif

        // Strip query string (e.g. "?c=1") used to bust QML's image cache
        const int qmark = m_id.indexOf(QLatin1Char('?'));
        const QString cleanId = qmark >= 0 ? m_id.left(qmark) : m_id;

        const int sz = m_requestedSize.isValid()
                       ? qMax(m_requestedSize.width(), m_requestedSize.height())
                       : 32;

        const QPixmap px = IconCache::instance().get(cleanId, sz);
        m_image = px.toImage();

#ifdef Q_OS_WIN
        CoUninitialize();
#endif
        emit finished();
    }

private:
    QString  m_id;
    QSize    m_requestedSize;
    QImage   m_image;
};

class FileIconImageProvider : public QQuickAsyncImageProvider
{
public:
    explicit FileIconImageProvider()
    {
        IconCache::instance().preload();
    }

    QQuickImageResponse *requestImageResponse(const QString &id, const QSize &requestedSize) override
    {
        auto *response = new FileIconResponse(id, requestedSize);
        QThreadPool::globalInstance()->start(response);
        return response;
    }
};
