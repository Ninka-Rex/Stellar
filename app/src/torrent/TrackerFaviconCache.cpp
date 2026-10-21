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

#include "TrackerFaviconCache.h"

#include "AppSettings.h"
#include "StellarPaths.h"

#include <QBuffer>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QHostAddress>
#include <QImage>
#include <QImageReader>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QRegularExpression>
#include <QUrl>

#include <memory>

namespace {
// The icon server is untrusted: everything about a response is bounded
// before any byte reaches an image decoder.
constexpr qint64 kMaxIconBytes = 256 * 1024;
constexpr int kMaxIconDimension = 512;
constexpr int kStoredSize = 32;
constexpr int kTimeoutMs = 10000;
constexpr int kMaxConcurrent = 4;
// A host with no usable favicon isn't asked again for a week.
constexpr qint64 kMissRetrySecs = 7 * 24 * 3600;
} // namespace

TrackerFaviconCache::TrackerFaviconCache(QNetworkAccessManager *nam, AppSettings *settings, QObject *parent)
    : QObject(parent), m_nam(nam), m_settings(settings), m_dir(StellarPaths::trackerIconCacheDir()) {}

QString TrackerFaviconCache::hostOf(const QString &trackerUrl) {
    const QUrl url(trackerUrl.trimmed(), QUrl::StrictMode);
    const QString scheme = url.scheme().toLower();
    if (!url.isValid() || (scheme != QLatin1String("http") && scheme != QLatin1String("https")
                           && scheme != QLatin1String("udp") && scheme != QLatin1String("ws")
                           && scheme != QLatin1String("wss")))
        return {};
    const QString host = url.host().toLower();
    // Plain DNS names and IPv4 only: keeps the cache file name trivially safe
    // and skips link-local / bracketed IPv6 oddities.
    static const QRegularExpression kHost(QStringLiteral("^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*$"));
    if (host.isEmpty() || host.size() > 253 || !kHost.match(host).hasMatch())
        return {};
    return host;
}

QString TrackerFaviconCache::iconPath(const QString &host) const {
    return m_dir + QLatin1Char('/') + host + QStringLiteral(".png");
}

QString TrackerFaviconCache::missPath(const QString &host) const {
    return m_dir + QLatin1Char('/') + host + QStringLiteral(".miss");
}

QString TrackerFaviconCache::iconFor(const QString &trackerUrl) {
    if (!m_settings || !m_settings->torrentTrackerFavicons())
        return {};
    const QString host = hostOf(trackerUrl);
    if (host.isEmpty())
        return {};

    const auto known = m_known.constFind(host);
    if (known != m_known.constEnd())
        return known.value();

    const QString png = iconPath(host);
    if (QFileInfo::exists(png)) {
        const QString url = QUrl::fromLocalFile(png).toString();
        m_known.insert(host, url);
        return url;
    }
    const QFileInfo miss(missPath(host));
    if (miss.exists() && miss.lastModified().secsTo(QDateTime::currentDateTime()) < kMissRetrySecs) {
        m_known.insert(host, QString());
        return {};
    }

    if (!m_pending.contains(host)) {
        Job job;
        job.host = host;
        job.candidates << QStringLiteral("https://%1/favicon.ico").arg(host)
                       << QStringLiteral("http://%1/favicon.ico").arg(host);
        // tracker.example.org often has no site of its own; example.org does.
        const QStringList labels = host.split(QLatin1Char('.'));
        if (labels.size() > 2 && QHostAddress(host).isNull()) {
            const QString base = labels.mid(labels.size() - 2).join(QLatin1Char('.'));
            job.candidates << QStringLiteral("https://%1/favicon.ico").arg(base);
        }
        m_pending.insert(host);
        m_queue.enqueue(job);
        startNext();
    }
    return {};
}

void TrackerFaviconCache::startNext() {
    while (m_active < kMaxConcurrent && !m_queue.isEmpty()) {
        ++m_active;
        tryCandidate(m_queue.dequeue());
    }
}

void TrackerFaviconCache::tryCandidate(Job job) {
    if (job.candidates.isEmpty()) {
        finishJob(job.host, false);
        return;
    }
    QNetworkRequest request(QUrl(job.candidates.takeFirst()));
    request.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::NoLessSafeRedirectPolicy);
    request.setMaximumRedirectsAllowed(3);
    request.setTransferTimeout(kTimeoutMs);
    QNetworkReply *reply = m_nam->get(request);

    auto tooLarge = std::make_shared<bool>(false);
    connect(reply, &QNetworkReply::downloadProgress, reply, [reply, tooLarge](qint64 received, qint64 total) {
        if (received > kMaxIconBytes || total > kMaxIconBytes) {
            *tooLarge = true;
            reply->abort();
        }
    });
    connect(reply, &QNetworkReply::finished, this, [this, reply, job, tooLarge]() {
        reply->deleteLater();
        if (*tooLarge || reply->error() != QNetworkReply::NoError) {
            tryCandidate(job);
            return;
        }
        QByteArray data = reply->read(kMaxIconBytes);
        QBuffer buffer(&data);
        buffer.open(QIODevice::ReadOnly);
        QImageReader reader(&buffer);
        // Only plain bitmap favicon formats; the format is sniffed from the
        // bytes, not trusted from Content-Type or the URL.
        static const QSet<QByteArray> kFormats{ "ico", "png", "bmp", "gif", "jpeg", "jpg" };
        const QSize size = reader.size();
        if (!reader.canRead() || !kFormats.contains(reader.format().toLower())
            || !size.isValid() || size.width() > kMaxIconDimension || size.height() > kMaxIconDimension) {
            tryCandidate(job);
            return;
        }
        QImage image = reader.read();
        if (image.isNull()) {
            tryCandidate(job);
            return;
        }
        // Re-encoded at a fixed size, so only our own PNG ever reaches the UI.
        image = image.scaled(kStoredSize, kStoredSize, Qt::KeepAspectRatio, Qt::SmoothTransformation);
        if (!image.save(iconPath(job.host), "PNG")) {
            finishJob(job.host, false);
            return;
        }
        QFile::remove(missPath(job.host));
        finishJob(job.host, true);
    });
}

void TrackerFaviconCache::finishJob(const QString &host, bool success) {
    --m_active;
    m_pending.remove(host);
    if (success) {
        m_known.insert(host, QUrl::fromLocalFile(iconPath(host)).toString());
    } else {
        m_known.insert(host, QString());
        QFile marker(missPath(host));
        if (marker.open(QIODevice::WriteOnly | QIODevice::Truncate))
            marker.close();
    }
    ++m_revision;
    emit revisionChanged();
    startNext();
}
