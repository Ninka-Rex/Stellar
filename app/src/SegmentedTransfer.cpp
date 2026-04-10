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

#include "SegmentedTransfer.h"
#include "AppVersion.h"
#include <QNetworkRequest>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QDir>
#include <QFileInfo>
#include <QUrl>
#include <algorithm>
#include <QDebug>

static const QString kUserAgent =
    QStringLiteral("Stellar/%1").arg(QStringLiteral(STELLAR_VERSION));
static const QString kBrowserUserAgent =
    QStringLiteral("Mozilla/5.0 (Windows NT 10.0; Win64; x64) Stellar/%1").arg(QStringLiteral(STELLAR_VERSION));

namespace {
QString resolvedUserAgent(bool useCustomUserAgent, const QString &customUserAgent, bool browserStyleFallback) {
    const QString trimmedCustomUserAgent = customUserAgent.trimmed();
    if (useCustomUserAgent && !trimmedCustomUserAgent.isEmpty())
        return trimmedCustomUserAgent;

    return browserStyleFallback ? kBrowserUserAgent : kUserAgent;
}
}

SegmentedTransfer::SegmentedTransfer(DownloadItem *item,
                                     QNetworkAccessManager *nam,
                                     int segments,
                                     QObject *parent)
    : QObject(parent), m_item(item), m_nam(nam), m_segmentCount(segments)
{
    m_progressTimer = new QTimer(this);
    m_progressTimer->setInterval(250);
    connect(m_progressTimer, &QTimer::timeout, this, &SegmentedTransfer::onProgressTick);
}

SegmentedTransfer::~SegmentedTransfer() {
    // Abort any active replies to avoid dangling pointers
    if (m_headReply) {
        m_headReply->abort();
        m_headReply->deleteLater();
    }
    for (auto &seg : m_segments) {
        if (seg.reply) {
            seg.reply->abort();
            seg.reply->deleteLater();
        }
        if (seg.file) {
            seg.file->close();
            delete seg.file;
        }
    }
    m_progressTimer->stop();
}

void SegmentedTransfer::start() {
    m_paused    = false;
    m_cancelled = false;

    m_item->setLastTryAt(QDateTime::currentDateTime());

    qDebug() << "[ST] start() url=" << m_item->url().toString()
             << "isGDrive=" << isGoogleDriveUrl(m_item->url())
             << "hasCookies=" << !m_item->cookies().isEmpty()
             << "cookieLen=" << m_item->cookies().size();

    // Google Drive doesn't reliably respond to HEAD — skip straight to GET
    // with HTML interception so we can detect confirmation pages.
    // Also skip loadMeta() for GDrive: previous attempts may have saved
    // meta/part files containing HTML garbage that we'd blindly resume.
    if (isGoogleDriveUrl(m_item->url())) {
        // Remove any stale part/meta files from previous (possibly bad) attempts
        QFile::remove(metaPath());
        QFile::remove(partPath(0));
        m_gdriveIntercepting = true;
        m_resumeCapable = false;
        m_item->setResumeCapable(false);
        setupSegments(0, false);
        saveMeta();
        startAllSegments();
        m_progressTimer->start();
        emit started();
        return;
    }

    // Try to resume from existing meta
    if (loadMeta()) {
        startAllSegments();
        m_progressTimer->start();
        emit started();
        return;
    }

    // Fresh start: HEAD request
    sendHeadRequest();
}

// Apply standard headers (UA, cookies, redirects) to any outgoing request.
void SegmentedTransfer::applyRequestHeaders(QNetworkRequest &req, const QUrl &url) const {
    req.setHeader(
        QNetworkRequest::UserAgentHeader,
        resolvedUserAgent(m_useCustomUserAgent, m_customUserAgent, isGoogleDriveUrl(url)));
    req.setAttribute(QNetworkRequest::RedirectPolicyAttribute,
                     QNetworkRequest::NoLessSafeRedirectPolicy);
    if (m_item && !m_item->cookies().isEmpty())
        req.setRawHeader("Cookie", m_item->cookies().toUtf8());
    if (m_item && !m_item->username().isEmpty()) {
        const QByteArray credentials =
            (m_item->username() + QLatin1Char(':') + m_item->password()).toUtf8().toBase64();
        req.setRawHeader("Authorization", QByteArray("Basic ") + credentials);
    }
}

void SegmentedTransfer::setCustomUserAgentEnabled(bool enabled) {
    m_useCustomUserAgent = enabled;
}

void SegmentedTransfer::setCustomUserAgent(const QString &userAgent) {
    m_customUserAgent = userAgent;
}

void SegmentedTransfer::setTemporaryDirectory(const QString &path) {
    m_temporaryDirectory = path;
}

void SegmentedTransfer::sendHeadRequest() {
    QNetworkRequest req(m_item->url());
    applyRequestHeaders(req, m_item->url());

    m_headReply = m_nam->head(req);
    connect(m_headReply, &QNetworkReply::finished, this, [this]() {
        onHeadFinished(m_headReply);
    });
}

void SegmentedTransfer::onHeadFinished(QNetworkReply *reply) {
    if (m_cancelled || !m_item) {
        reply->deleteLater();
        m_headReply = nullptr;
        return;
    }

    if (reply->error() != QNetworkReply::NoError) {
        // HEAD failed — fall back to single-connection GET without range
        reply->deleteLater();
        m_headReply = nullptr;
        m_resumeCapable = false;
        m_item->setResumeCapable(false);
        setupSegments(0, false);
        saveMeta();
        startAllSegments();
        m_progressTimer->start();
        emit started();
        return;
    }

    qint64 contentLength = reply->header(QNetworkRequest::ContentLengthHeader).toLongLong();
    QString contentType = reply->header(QNetworkRequest::ContentTypeHeader).toString().toLower();
    QString acceptRanges = reply->rawHeader("Accept-Ranges");

    // Google Drive may return text/html (virus-scan confirmation page).
    // Fall back to single GET so we can detect and handle the HTML in onSegmentReadyRead.
    bool gdriveHtml = isGoogleDriveUrl(m_item->url()) && contentType.contains(QStringLiteral("text/html"));
    if (gdriveHtml) {
        reply->deleteLater();
        m_headReply = nullptr;
        m_resumeCapable = false;
        m_item->setResumeCapable(false);
        m_gdriveIntercepting = true;
        setupSegments(0, false);
        saveMeta();
        startAllSegments();
        m_progressTimer->start();
        emit started();
        return;
    }

    m_resumeCapable = (acceptRanges.trimmed().compare(QStringLiteral("bytes"), Qt::CaseInsensitive) == 0
                       && contentLength > 0);

    if (contentLength > 0)
        m_item->setTotalBytes(contentLength);

    m_item->setResumeCapable(m_resumeCapable);

    // Extract filename from Content-Disposition if present
    updateFilenameFromReply(reply);

    reply->deleteLater();
    m_headReply = nullptr;

    setupSegments(contentLength, m_resumeCapable);
    saveMeta();
    startAllSegments();
    m_progressTimer->start();
    emit started();
}

void SegmentedTransfer::setupSegments(qint64 totalBytes, bool resumeCapable) {
    m_segments.clear();

    int segCount = 1;
    if (resumeCapable && totalBytes > (qint64)kMinSegmentSize * m_segmentCount) {
        segCount = m_segmentCount;
    }

    if (totalBytes <= 0 || !resumeCapable) {
        // Single segment, no Range header
        Segment seg;
        seg.index       = 0;
        seg.startOffset = 0;
        seg.endOffset   = -1; // unknown
        seg.received    = 0;
        seg.partPath    = partPath(0);
        m_segments.append(seg);
    } else {
        qint64 segSize = totalBytes / segCount;
        for (int i = 0; i < segCount; ++i) {
            Segment seg;
            seg.index       = i;
            seg.startOffset = i * segSize;
            seg.endOffset   = (i == segCount - 1) ? totalBytes - 1 : (i + 1) * segSize - 1;
            seg.received    = 0;
            seg.partPath    = partPath(i);
            m_segments.append(seg);
        }
    }
}

void SegmentedTransfer::startAllSegments() {
    // Ensure save path dir exists
    QDir().mkpath(m_item->savePath());

    for (auto &seg : m_segments) {
        if (!seg.done) {
            startSegment(seg);
        }
    }
}

void SegmentedTransfer::startSegment(Segment &seg) {
    // Open part file for appending
    if (!seg.file) {
        seg.file = new QFile(seg.partPath);
    }
    if (!seg.file->isOpen()) {
        if (!seg.file->open(QIODevice::Append)) {
            emit failed(QStringLiteral("Cannot open part file: %1").arg(seg.partPath));
            return;
        }
    }

    QNetworkRequest req(m_item->url());
    applyRequestHeaders(req, m_item->url());

    // Set Range header if applicable
    if (seg.endOffset >= 0) {
        qint64 from = seg.startOffset + seg.received;
        qint64 to   = seg.endOffset;
        // If we already have all the bytes for this segment, mark done and skip
        if (from > to) {
            seg.done = true;
            if (seg.file) seg.file->close();
            return;
        }
        req.setRawHeader("Range", QStringLiteral("bytes=%1-%2").arg(from).arg(to).toUtf8());
    }

    seg.reply = m_nam->get(req);

    int idx = seg.index;
    connect(seg.reply, &QNetworkReply::readyRead, this, [this, idx]() {
        onSegmentReadyRead(idx);
    });
    connect(seg.reply, &QNetworkReply::finished, this, [this, idx]() {
        onSegmentFinished(idx);
    });
}

void SegmentedTransfer::onSegmentReadyRead(int index) {
    if (index < 0 || index >= m_segments.size()) return;
    auto &seg = m_segments[index];
    if (!seg.reply || !seg.file) return;

    // Google Drive HTML interception: buffer the first chunk to sniff content type
    if (m_gdriveIntercepting && index == 0) {
        // If redirected to accounts.google.com, it's an auth wall — fail immediately
        QString replyHost = seg.reply->url().host().toLower();
        qDebug() << "[GDrive] readyRead, replyHost=" << replyHost << "bufSize=" << m_gdriveHtmlBuf.size();
        if (replyHost.contains(QStringLiteral("accounts.google.com"))) {
            qDebug() << "[GDrive] auth wall detected";
            seg.reply->disconnect(this);
            seg.reply->abort();
            seg.reply->deleteLater();
            seg.reply = nullptr;
            if (seg.file) { seg.file->close(); QFile::remove(seg.partPath); }
            m_gdriveIntercepting = false;
            m_gdriveHtmlBuf.clear();
            emit failed(QStringLiteral("Google Drive requires sign-in. Right-click the link in your browser and use \"Download with Stellar\" so the extension can pass your login cookies."));
            return;
        }

        QByteArray data = seg.reply->readAll();
        m_gdriveHtmlBuf.append(data);

        // Check Content-Disposition header — if present, it's the real file
        QByteArray cd = seg.reply->rawHeader("Content-Disposition");
        bool hasContentDisp = !cd.isEmpty() && cd.contains("filename");

        // Sniff the first bytes for HTML
        QByteArray head = m_gdriveHtmlBuf.left(512).trimmed();
        bool looksLikeHtml = head.contains("<html") || head.contains("<!DOCTYPE") || head.contains("<!doctype");

        if (hasContentDisp || (!looksLikeHtml && m_gdriveHtmlBuf.size() > 512)) {
            // Real file — flush buffer to disk and switch to normal mode
            m_gdriveIntercepting = false;
            updateFilenameFromReply(seg.reply);
            qint64 cl = seg.reply->header(QNetworkRequest::ContentLengthHeader).toLongLong();
            if (cl > 0) m_item->setTotalBytes(cl);

            seg.file->write(m_gdriveHtmlBuf);
            seg.received += m_gdriveHtmlBuf.size();
            m_gdriveHtmlBuf.clear();
        }
        // Otherwise keep buffering until finished (confirmation pages are small)
        return;
    }

    // On the very first data from segment 0, try to pick up the filename
    // from Content-Disposition (many servers only send it on GET, not HEAD).
    if (index == 0 && seg.received == 0 && seg.pending.isEmpty()) {
        updateFilenameFromReply(seg.reply);
    }

    QByteArray data = seg.reply->readAll();
    if (data.isEmpty()) return;

    if (m_speedLimitKBps > 0) {
        seg.pending.append(data);
    } else {
        seg.file->write(data);
        seg.received += data.size();
    }
}

void SegmentedTransfer::onSegmentFinished(int index) {
    if (index < 0 || index >= m_segments.size() || !m_item) return;
    auto &seg = m_segments[index];
    if (!seg.reply) return;

    if (m_cancelled || m_paused) {
        seg.reply->deleteLater();
        seg.reply = nullptr;
        if (seg.file) seg.file->close();
        return;
    }

    // Google Drive HTML interception: response finished while still intercepting
    // means the entire response is small (confirmation page or auth redirect)
    if (m_gdriveIntercepting && index == 0) {
        QString replyHost = seg.reply->url().host().toLower();
        bool isAuthRedirect = replyHost.contains(QStringLiteral("accounts.google.com"));

        if (seg.reply->bytesAvailable() > 0)
            m_gdriveHtmlBuf.append(seg.reply->readAll());
        QNetworkReply::NetworkError err = seg.reply->error();
        seg.reply->deleteLater();
        seg.reply = nullptr;
        if (seg.file) { seg.file->close(); QFile::remove(seg.partPath); }

        if (err != QNetworkReply::NoError) {
            emit failed(QStringLiteral("Google Drive request failed"));
            return;
        }

        if (isAuthRedirect) {
            m_gdriveIntercepting = false;
            m_gdriveHtmlBuf.clear();
            emit failed(QStringLiteral("Google Drive requires sign-in. Right-click the link in your browser and use \"Download with Stellar\" so the extension can pass your login cookies."));
            return;
        }

        // Small response — check if it's a confirmation page
        QByteArray head = m_gdriveHtmlBuf.left(512).trimmed();
        if (head.contains("<html") || head.contains("<!DOCTYPE") || head.contains("<!doctype")) {
            handleGDriveConfirmPage(m_gdriveHtmlBuf);
        } else {
            // Small non-HTML response — write it as the file
            m_gdriveIntercepting = false;
            if (!seg.file) seg.file = new QFile(seg.partPath);
            if (seg.file->open(QIODevice::WriteOnly)) {
                seg.file->write(m_gdriveHtmlBuf);
                seg.received = m_gdriveHtmlBuf.size();
                seg.file->close();
            }
            m_gdriveHtmlBuf.clear();
            seg.done = true;
            m_progressTimer->stop();
            mergeAndFinish();
        }
        return;
    }

    // Read any remaining bytes the network delivered before finishing
    if (seg.reply->bytesAvailable() > 0) {
        QByteArray data = seg.reply->readAll();
        if (!data.isEmpty()) {
            if (m_speedLimitKBps > 0) {
                seg.pending.append(data);
            } else if (seg.file) {
                seg.file->write(data);
                seg.received += data.size();
            }
        }
    }

    QNetworkReply::NetworkError err = seg.reply->error();
    seg.reply->deleteLater();
    seg.reply = nullptr;

    if (err != QNetworkReply::NoError && err != QNetworkReply::OperationCanceledError) {
        if (seg.file) seg.file->close();
        m_item->setStatus(DownloadItem::Status::Error);
        emit failed(QStringLiteral("Network error on segment %1").arg(index));
        return;
    }

    // Throttled with unflushed data: let onProgressTick drain pending before marking done
    if (m_speedLimitKBps > 0 && !seg.pending.isEmpty()) {
        seg.networkDone = true;
        return;
    }

    seg.done = true;
    if (seg.file) seg.file->close();

    bool allDone = true;
    for (const auto &s : m_segments) {
        if (!s.done) { allDone = false; break; }
    }
    if (allDone) {
        m_progressTimer->stop();
        mergeAndFinish();
    }
}

void SegmentedTransfer::onProgressTick() {
    if (!m_item) return;

    // Throttled: flush a budget's worth of pending data to disk each tick
    if (m_speedLimitKBps > 0) {
        int busySegs = 0;
        for (const auto &seg : m_segments)
            if (!seg.done) ++busySegs;

        if (busySegs > 0) {
            qint64 budgetPerSeg = ((qint64)m_speedLimitKBps * 1024 / 4) / busySegs;
            if (budgetPerSeg < 1) budgetPerSeg = 1;

            for (auto &seg : m_segments) {
                if (seg.done || !seg.file) continue;

                qint64 toWrite = std::min((qint64)seg.pending.size(), budgetPerSeg);
                if (toWrite > 0) {
                    seg.file->write(seg.pending.constData(), toWrite);
                    seg.received += toWrite;
                    seg.pending.remove(0, (int)toWrite);
                }

                if (seg.networkDone && seg.pending.isEmpty()) {
                    seg.done = true;
                    if (seg.file) seg.file->close();
                }
            }

            bool allDone = true;
            for (const auto &s : m_segments)
                if (!s.done) { allDone = false; break; }
            if (allDone) {
                m_progressTimer->stop();
                mergeAndFinish();
                return;
            }
        }
    }

    qint64 totalReceived = 0;
    for (const auto &seg : m_segments) {
        totalReceived += seg.received;
    }

    m_item->setDoneBytes(totalReceived);

    qint64 delta = totalReceived - m_lastReceived;
    qint64 speedBps = delta * 4; // divide by 0.25s → multiply by 4
    m_item->setSpeed(speedBps);
    m_lastReceived = totalReceived;

    updateSegmentDataOnItem();

    emit progressChanged(totalReceived, m_item->totalBytes(), speedBps);
}

void SegmentedTransfer::updateSegmentDataOnItem() {
    QVariantList list;
    for (const auto &seg : m_segments) {
        QVariantMap m;
        m[QStringLiteral("startByte")] = seg.startOffset;
        m[QStringLiteral("endByte")]   = seg.endOffset;
        m[QStringLiteral("received")]  = seg.received;
        if (seg.done)
            m[QStringLiteral("info")] = QStringLiteral("Complete");
        else if (seg.reply)
            m[QStringLiteral("info")] = QStringLiteral("Downloading...");
        else
            m[QStringLiteral("info")] = QStringLiteral("Waiting...");
        list.append(m);
    }
    m_item->setSegmentData(list);
}

void SegmentedTransfer::mergeAndFinish() {
    m_item->setStatus(DownloadItem::Status::Assembling);

    // Final progress update
    qint64 totalReceived = 0;
    for (const auto &seg : m_segments) totalReceived += seg.received;
    m_item->setDoneBytes(totalReceived);
    m_item->setSpeed(0);

    QString outPath = m_item->savePath() + QStringLiteral("/") + m_item->filename();

    // If single segment with no range, rename the part file to the final name
    if (m_segments.size() == 1 && m_segments[0].endOffset < 0) {
        QString partSrc = m_segments[0].partPath;
        // If the expected part file doesn't exist (e.g. filename changed mid-download
        // and the rename above didn't run), fall back to whatever the QFile was
        // actually opened with.
        if (!QFile::exists(partSrc) && m_segments[0].file)
            partSrc = m_segments[0].file->fileName();

        if (!QFile::rename(partSrc, outPath)) {
            // Cross-device or locked: copy then delete
            QFile src(partSrc);
            QFile dst(outPath);
            if (src.open(QIODevice::ReadOnly) && dst.open(QIODevice::WriteOnly)) {
                const qint64 kChunk = 1024 * 1024;
                while (!src.atEnd()) dst.write(src.read(kChunk));
            }
            QFile::remove(partSrc);
        }
    } else {
        QFile outFile(outPath);
        if (!outFile.open(QIODevice::WriteOnly)) {
            emit failed(QStringLiteral("Cannot create output file: %1").arg(outPath));
            return;
        }
        for (const auto &seg : m_segments) {
            QFile partFile(seg.partPath);
            if (partFile.open(QIODevice::ReadOnly)) {
                outFile.write(partFile.readAll());
                partFile.close();
            }
        }
        outFile.close();
    }

    cleanupPartFiles();
    deleteMetaFile();

    m_item->setStatus(DownloadItem::Status::Completed);
    emit finished();
}

void SegmentedTransfer::updateFilenameFromReply(QNetworkReply *reply) {
    if (!reply || !m_item) return;

    QString filename = parseContentDispositionFilename(
        reply->rawHeader("Content-Disposition"));

    if (filename.isEmpty()) {
        QUrl finalUrl = reply->url();
        QString pathName = QFileInfo(finalUrl.path()).fileName();
        if (!pathName.isEmpty() && pathName != QStringLiteral("download"))
            filename = pathName;
    }

    if (filename.isEmpty() || filename == m_item->filename() || m_item->isFilenameManuallySet()) return;

    // Rename part files on disk before updating the stored filename, so the
    // file objects and seg.partPath stay consistent with what's actually on disk.
    QString oldMeta = metaPath();
    for (auto &seg : m_segments) {
        QString oldPart = seg.partPath;
        // Compute what the new partPath will be (based on the new filename)
        QString newPart = m_item->savePath() + QStringLiteral("/") + filename
                          + QStringLiteral(".stellar-part-") + QString::number(seg.index);
        if (oldPart == newPart) continue;

        if (QFile::exists(oldPart)) {
            // Close the file if open, rename on disk, then reopen at new path
            bool wasOpen = seg.file && seg.file->isOpen();
            if (wasOpen) seg.file->close();
            QFile::rename(oldPart, newPart);
            if (seg.file) {
                seg.file->setFileName(newPart);
                if (wasOpen) seg.file->open(QIODevice::Append);
            }
        }
        seg.partPath = newPart;
    }

    m_item->setFilename(filename);

    // Rename the meta file if it exists
    if (QFile::exists(oldMeta))
        QFile::rename(oldMeta, metaPath());
}

QString SegmentedTransfer::parseContentDispositionFilename(const QByteArray &header) {
    if (header.isEmpty()) return {};

    qDebug() << "[parseContentDispositionFilename] raw header:" << header;

    // Try RFC 5987 filename*=UTF-8''encoded_name first
    int starIdx = header.indexOf("filename*=");
    if (starIdx >= 0) {
        QByteArray val = header.mid(starIdx + 10).trimmed();
        // Strip encoding prefix up to the second single-quote
        int q1 = val.indexOf('\'');
        if (q1 >= 0) {
            int q2 = val.indexOf('\'', q1 + 1);
            if (q2 >= 0)
                val = val.mid(q2 + 1);
        }
        // May be terminated by ;
        int semi = val.indexOf(';');
        if (semi >= 0) val = val.left(semi);
        QString decoded = QUrl::fromPercentEncoding(val.trimmed());
        if (!decoded.isEmpty()) {
            qDebug() << "[parseContentDispositionFilename] RFC 5987 filename:" << decoded;
            return decoded;
        }
    }

    // Plain filename="value" or filename=value
    int idx = header.indexOf("filename=");
    if (idx < 0) {
        qDebug() << "[parseContentDispositionFilename] no filename= found";
        return {};
    }
    QByteArray val = header.mid(idx + 9).trimmed();
    // May be terminated by ;
    int semi = val.indexOf(';');
    if (semi >= 0) val = val.left(semi);
    val = val.trimmed();
    // Strip quotes
    if (val.startsWith('"') && val.endsWith('"'))
        val = val.mid(1, val.size() - 2);
    QString result = QString::fromUtf8(val);
    qDebug() << "[parseContentDispositionFilename] plain filename:" << result;
    return result;
}

bool SegmentedTransfer::isGoogleDriveUrl(const QUrl &url) const {
    const QString host = url.host().toLower();
    return host.endsWith(QStringLiteral("drive.google.com")) ||
           host.endsWith(QStringLiteral("drive.usercontent.google.com"));
}

void SegmentedTransfer::handleGDriveConfirmPage(const QByteArray &html) {
    qDebug() << "[GDrive] handling confirmation page, size:" << html.size();
    // Google Drive virus-scan confirmation page contains a form that
    // POSTs (or links) to the real download.  We look for the form action
    // URL or a direct download link.
    //
    // Common patterns:
    //   <form id="download-form" action="URL" method="POST">
    //   <a id="uc-download-link" ... href="URL">
    //
    // We also inject a cookie header (NID) that Google may expect after
    // the confirmation.  The simplest fix is to append &confirm=t to
    // the original URL — some GDrive endpoints honour it, some don't.
    // If the HTML contains a form action URL, use that instead.

    QString page = QString::fromUtf8(html);

    // Try to extract form action URL
    QUrl newUrl;
    int formIdx = page.indexOf(QStringLiteral("id=\"download-form\""));
    if (formIdx < 0) formIdx = page.indexOf(QStringLiteral("id=\"downloadForm\""));
    if (formIdx >= 0) {
        int actionIdx = page.indexOf(QStringLiteral("action=\""), formIdx);
        if (actionIdx >= 0) {
            actionIdx += 8;
            int endIdx = page.indexOf('"', actionIdx);
            if (endIdx > actionIdx) {
                QString actionUrl = page.mid(actionIdx, endIdx - actionIdx);
                actionUrl.replace(QStringLiteral("&amp;"), QStringLiteral("&"));
                newUrl = QUrl(actionUrl);
                if (newUrl.isRelative())
                    newUrl = m_item->url().resolved(newUrl);
            }
        }
    }

    // Fallback: look for uc-download-link href
    if (!newUrl.isValid()) {
        int linkIdx = page.indexOf(QStringLiteral("id=\"uc-download-link\""));
        if (linkIdx >= 0) {
            int hrefIdx = page.indexOf(QStringLiteral("href=\""), linkIdx);
            if (hrefIdx >= 0) {
                hrefIdx += 6;
                int endIdx = page.indexOf('"', hrefIdx);
                if (endIdx > hrefIdx) {
                    QString linkUrl = page.mid(hrefIdx, endIdx - hrefIdx);
                    linkUrl.replace(QStringLiteral("&amp;"), QStringLiteral("&"));
                    newUrl = QUrl(linkUrl);
                    if (newUrl.isRelative())
                        newUrl = m_item->url().resolved(newUrl);
                }
            }
        }
    }

    qDebug() << "[GDrive] parsed confirmation page, newUrl:" << newUrl;
    if (!newUrl.isValid()) {
        // Can't parse confirmation page — deliver what we got (the HTML)
        // and let it finish as-is; user will see a bad file.
        qDebug() << "[GDrive] FAILED to parse, first 2000 bytes:" << html.left(2000);
        emit failed(QStringLiteral("Google Drive returned a confirmation page that could not be parsed"));
        return;
    }

    // Clean up current segments
    for (auto &seg : m_segments) {
        if (seg.reply) {
            seg.reply->disconnect(this);
            seg.reply->abort();
            seg.reply->deleteLater();
            seg.reply = nullptr;
        }
        if (seg.file) {
            seg.file->close();
            QFile::remove(seg.partPath);
            delete seg.file;
            seg.file = nullptr;
        }
    }
    m_segments.clear();
    m_progressTimer->stop();

    // Restart download with the real URL
    m_gdriveIntercepting = false;
    m_gdriveHtmlBuf.clear();
    m_item->setDoneBytes(0);
    m_item->setTotalBytes(0);

    // Use a GET-based probe instead of HEAD for the real URL
    m_resumeCapable = false;
    m_item->setResumeCapable(false);
    setupSegments(0, false);
    // Override the URL on the request (item URL stays as original for display)
    auto &seg = m_segments[0];
    seg.file = new QFile(seg.partPath);
    if (!seg.file->open(QIODevice::WriteOnly)) {
        emit failed(QStringLiteral("Cannot open part file: %1").arg(seg.partPath));
        return;
    }

    QNetworkRequest req(newUrl);
    applyRequestHeaders(req, newUrl);

    seg.reply = m_nam->get(req);
    connect(seg.reply, &QNetworkReply::readyRead, this, [this]() {
        onSegmentReadyRead(0);
    });
    connect(seg.reply, &QNetworkReply::finished, this, [this]() {
        onSegmentFinished(0);
    });

    saveMeta();
    m_lastReceived = 0;
    m_progressTimer->start();
}

void SegmentedTransfer::setSpeedLimitKBps(int kbps) {
    int oldLimit = m_speedLimitKBps;
    m_speedLimitKBps = kbps;

    // Transitioning throttled → unlimited: discard pending buffers.
    // The network replies are still active — new data arriving via
    // onSegmentReadyRead will now go straight to disk (since kbps==0).
    // Discarding pending means those bytes will be re-received from the
    // server (the reply is already positioned past them, so we actually
    // need to flush to avoid a gap).  Flush pending to disk here.
    if (oldLimit > 0 && kbps == 0) {
        for (auto &seg : m_segments) {
            if (!seg.pending.isEmpty() && seg.file) {
                seg.file->write(seg.pending);
                seg.received += seg.pending.size();
                seg.pending.clear();
            }
            if (seg.networkDone && !seg.done) {
                seg.done = true;
                if (seg.file) seg.file->close();
            }
        }
        bool allDone = true;
        for (const auto &s : m_segments)
            if (!s.done) { allDone = false; break; }
        if (allDone && !m_paused && !m_cancelled) {
            m_progressTimer->stop();
            mergeAndFinish();
        }
    }
    // Transitioning unlimited → throttled: nothing special needed.
    // onSegmentReadyRead will start buffering to pending on the next call.
}

void SegmentedTransfer::pause() {
    if (m_paused || !m_item) return;
    m_paused = true;

    m_progressTimer->stop();

    for (int i = 0; i < m_segments.size(); ++i) {
        auto &seg = m_segments[i];
        // Discard pending data — it was received at full network speed and
        // only sat in RAM.  On resume the segment re-downloads from where
        // the *disk file* left off (seg.received only counts disk writes),
        // which keeps the user's throttle rate intact.
        seg.pending.clear();

        if (seg.reply) {
            seg.reply->disconnect(this);
            seg.reply->abort();
            seg.reply->deleteLater();
            seg.reply = nullptr;
        }
        // Mark done only if all bytes are truly on disk
        if (seg.networkDone && !seg.done && seg.endOffset >= 0 &&
            seg.received >= (seg.endOffset - seg.startOffset + 1)) {
            seg.done = true;
        }
        seg.networkDone = false;
        if (seg.file) seg.file->close();
    }

    saveMeta();
    m_item->setStatus(DownloadItem::Status::Paused);
    m_item->setSpeed(0);
}

void SegmentedTransfer::resume() {
    if (!m_paused) return;
    m_paused = false;

    for (auto &seg : m_segments) {
        if (!seg.done) {
            if (seg.file && seg.file->isOpen()) seg.file->close();
            startSegment(seg);
        }
    }

    // Check if all segments were already complete (flushed during pause)
    bool allDone = true;
    for (const auto &s : m_segments)
        if (!s.done) { allDone = false; break; }

    if (allDone) {
        mergeAndFinish();
        return;
    }

    m_lastReceived = m_item->doneBytes();
    m_progressTimer->start();
    m_item->setStatus(DownloadItem::Status::Downloading);
}

bool SegmentedTransfer::relocateOutput(const QString &newSavePath, const QString &newFilename) {
    if (!m_item)
        return false;

    const QString oldMeta = metaPath();
    const QString oldSavePath = m_item->savePath();
    const QString oldFilename = m_item->filename();

    if (oldSavePath == newSavePath && oldFilename == newFilename)
        return true;

    QDir().mkpath(newSavePath);

    for (auto &seg : m_segments) {
        const QString newPartPath = newSavePath + QStringLiteral("/") + newFilename
            + QStringLiteral(".stellar-part-") + QString::number(seg.index);
        if (seg.partPath == newPartPath)
            continue;

        const QString oldPartPath = seg.partPath;
        const bool wasOpen = seg.file && seg.file->isOpen();
        if (wasOpen)
            seg.file->close();

        if (QFile::exists(oldPartPath)) {
            if (!QFile::rename(oldPartPath, newPartPath)) {
                if (wasOpen && seg.file)
                    seg.file->open(QIODevice::Append);
                return false;
            }
        }

        if (seg.file)
            seg.file->setFileName(newPartPath);
        if (wasOpen && seg.file)
            seg.file->open(QIODevice::Append);
        seg.partPath = newPartPath;
    }

    m_item->setSavePath(newSavePath);
    m_item->setFilename(newFilename);

    if (QFile::exists(oldMeta))
        QFile::rename(oldMeta, metaPath());

    saveMeta();
    return true;
}

void SegmentedTransfer::abort() {
    m_cancelled = true;
    m_progressTimer->stop();

    // Also stop the HEAD reply if still in flight
    if (m_headReply) {
        m_headReply->disconnect(this);
        m_headReply->abort();
        m_headReply->deleteLater();
        m_headReply = nullptr;
    }

    for (auto &seg : m_segments) {
        if (seg.reply) {
            // Disconnect FIRST so the synchronous `finished` signal from abort()
            // does not re-enter onSegmentFinished and null seg.reply under us.
            seg.reply->disconnect(this);
            seg.reply->abort();
            seg.reply->deleteLater();
            seg.reply = nullptr;
        }
        if (seg.file) {
            seg.file->close();
            delete seg.file;
            seg.file = nullptr;
        }
    }

    cleanupPartFiles();
    deleteMetaFile();

    // Don't access m_item here — it may be about to be deleted by DownloadQueue::cancel().
    // The item's final state will be set by whoever is calling abort().
}

void SegmentedTransfer::cleanupPartFiles() {
    for (const auto &seg : m_segments) {
        QFile::remove(seg.partPath);
    }
}

void SegmentedTransfer::deleteMetaFile() {
    QFile::remove(metaPath());
}

QString SegmentedTransfer::metaPath() const {
    return tempBaseDirectory() + QStringLiteral("/") + m_item->filename() + QStringLiteral(".stellar-meta");
}

QString SegmentedTransfer::partPath(int index) const {
    return tempBaseDirectory() + QStringLiteral("/") + m_item->filename()
           + QStringLiteral(".stellar-part-") + QString::number(index);
}

QString SegmentedTransfer::tempBaseDirectory() const {
    return m_temporaryDirectory.trimmed().isEmpty() ? m_item->savePath() : m_temporaryDirectory.trimmed();
}

bool SegmentedTransfer::saveMeta() {
    QJsonObject root;
    root[QStringLiteral("url")]        = m_item->url().toString();
    root[QStringLiteral("totalBytes")] = m_item->totalBytes();

    QJsonArray segs;
    for (const auto &seg : m_segments) {
        QJsonObject s;
        s[QStringLiteral("startOffset")] = seg.startOffset;
        s[QStringLiteral("endOffset")]   = seg.endOffset;
        s[QStringLiteral("received")]    = seg.received;
        s[QStringLiteral("done")]        = seg.done;
        segs.append(s);
    }
    root[QStringLiteral("segments")] = segs;

    QDir().mkpath(tempBaseDirectory());
    QFile f(metaPath());
    if (!f.open(QIODevice::WriteOnly)) return false;
    f.write(QJsonDocument(root).toJson(QJsonDocument::Compact));
    return true;
}

bool SegmentedTransfer::loadMeta() {
    QFile f(metaPath());
    if (!f.exists() || !f.open(QIODevice::ReadOnly)) return false;

    QJsonDocument doc = QJsonDocument::fromJson(f.readAll());
    f.close();
    if (doc.isNull()) return false;

    QJsonObject root = doc.object();
    qint64 totalBytes = root[QStringLiteral("totalBytes")].toVariant().toLongLong();
    if (totalBytes > 0) m_item->setTotalBytes(totalBytes);

    QJsonArray segs = root[QStringLiteral("segments")].toArray();
    if (segs.isEmpty()) return false;

    m_segments.clear();
    for (int i = 0; i < segs.size(); ++i) {
        QJsonObject s = segs[i].toObject();
        Segment seg;
        seg.index       = i;
        seg.startOffset = s[QStringLiteral("startOffset")].toVariant().toLongLong();
        seg.endOffset   = s[QStringLiteral("endOffset")].toVariant().toLongLong();
        seg.received    = s[QStringLiteral("received")].toVariant().toLongLong();
        seg.done        = s[QStringLiteral("done")].toBool();
        seg.partPath    = partPath(i);
        m_segments.append(seg);
    }

    m_resumeCapable = (segs.size() > 0 && totalBytes > 0);
    m_item->setResumeCapable(m_resumeCapable);

    // Calculate already-done bytes
    qint64 done = 0;
    for (const auto &seg : m_segments) done += seg.received;
    m_lastReceived = done;
    m_item->setDoneBytes(done);

    return true;
}
