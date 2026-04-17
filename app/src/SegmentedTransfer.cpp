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
#include <QtConcurrent/QtConcurrent>
#include <QFutureWatcher>
#include <QNetworkRequest>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QDir>
#include <QFileInfo>
#include <QSaveFile>
#include <QUrl>
#include <QTimer>
#include <QDateTime>
#include <QSslError>
#include <QStringList>
#include <QSet>
#include <QNetworkCookieJar>
#include <QNetworkCookie>
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

bool copyFileContents(QIODevice &src, QIODevice &dst) {
    static constexpr qint64 kChunkSize = 1024 * 1024;
    while (!src.atEnd()) {
        const QByteArray chunk = src.read(kChunkSize);
        if (chunk.isEmpty())
            return false;
        if (dst.write(chunk) != chunk.size())
            return false;
    }
    return true;
}

// Strip characters that are invalid in filenames on Windows (and also
// problematic on Linux if the file is later copied to a FAT/NTFS drive).
// The caller owns uniqueness — this function only cares about legality.
QString sanitizeFilename(const QString &in) {
    if (in.isEmpty())
        return QStringLiteral("download");

    static const QString kInvalid = QStringLiteral("<>:\"/\\|?*");
    QString out;
    out.reserve(in.size());
    for (QChar c : in) {
        if (c.unicode() < 0x20 || kInvalid.contains(c))
            out.append(QLatin1Char('_'));
        else
            out.append(c);
    }

    // Windows silently strips trailing spaces/dots; doing it ourselves
    // keeps the on-disk name consistent with what we think it is, which
    // matters for the part-file→output-file rename path.
    while (!out.isEmpty() && (out.endsWith(QLatin1Char(' ')) || out.endsWith(QLatin1Char('.'))))
        out.chop(1);

    // Reserved device names on Windows (CON, PRN, AUX, NUL, COM1-9, LPT1-9)
    // are rejected even with an extension, so prefix an underscore.
    static const QSet<QString> kReserved = {
        QStringLiteral("CON"), QStringLiteral("PRN"), QStringLiteral("AUX"), QStringLiteral("NUL"),
        QStringLiteral("COM1"), QStringLiteral("COM2"), QStringLiteral("COM3"),
        QStringLiteral("COM4"), QStringLiteral("COM5"), QStringLiteral("COM6"),
        QStringLiteral("COM7"), QStringLiteral("COM8"), QStringLiteral("COM9"),
        QStringLiteral("LPT1"), QStringLiteral("LPT2"), QStringLiteral("LPT3"),
        QStringLiteral("LPT4"), QStringLiteral("LPT5"), QStringLiteral("LPT6"),
        QStringLiteral("LPT7"), QStringLiteral("LPT8"), QStringLiteral("LPT9"),
    };
    QString base = out;
    const int dot = base.indexOf(QLatin1Char('.'));
    if (dot > 0) base = base.left(dot);
    if (kReserved.contains(base.toUpper()))
        out.prepend(QLatin1Char('_'));

    // Hard cap length to keep room for the ".stellar-part-NN" suffix on
    // systems with a 255-byte NAME_MAX (ext4, NTFS, APFS all cap at 255).
    static constexpr int kMaxNameLen = 200;
    if (out.size() > kMaxNameLen) {
        const int dotPos = out.lastIndexOf(QLatin1Char('.'));
        if (dotPos > 0 && (out.size() - dotPos) <= 16) {
            // Preserve extension
            const QString ext = out.mid(dotPos);
            out = out.left(kMaxNameLen - ext.size()) + ext;
        } else {
            out.truncate(kMaxNameLen);
        }
    }

    return out.isEmpty() ? QStringLiteral("download") : out;
}

// Prefix paths with \\?\ on Windows when they approach the 260-char MAX_PATH
// limit.  This disables Win32 path parsing and allows up to ~32 K characters.
// The path must be absolute and use native (backslash) separators.
QString longPath(const QString &path) {
#ifdef Q_OS_WIN
    if (path.size() > 240) {
        QString native = QDir::toNativeSeparators(QDir::cleanPath(path));
        if (!native.startsWith(QStringLiteral("\\\\?\\")))
            return QStringLiteral("\\\\?\\") + native;
        return native;
    }
#endif
    return path;
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

    seedCookieJar();
    m_item->setLastTryAt(QDateTime::currentDateTime());

    m_effectiveUrl = QUrl(); // reset on every fresh start

    qDebug() << "[ST] start() url=" << m_item->url().toString()
             << "isConfirmPage=" << isConfirmPageUrl(m_item->url())
             << "hasCookies=" << !m_item->cookies().isEmpty()
             << "cookieLen=" << m_item->cookies().size();

    // Google Drive: only discard stale non-resumable metas (single-segment downloads
    // produced by old code or confirmation-page fallbacks that may contain HTML bytes).
    // Valid range-based metas (resumeCapable == true) are preserved so partially-
    // downloaded files survive restarts and hard kills.
    if (isConfirmPageUrl(m_item->url())) {
        bool hasValidRangeMeta = false;
        QFile mf(metaPath());
        if (mf.exists() && mf.open(QIODevice::ReadOnly)) {
            QJsonDocument doc = QJsonDocument::fromJson(mf.readAll());
            mf.close();
            hasValidRangeMeta = doc.object()[QStringLiteral("resumeCapable")].toBool(false);
        }
        if (!hasValidRangeMeta) {
            QFile::remove(metaPath());
            QFile::remove(partPath(0));
        }
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
        resolvedUserAgent(m_useCustomUserAgent, m_customUserAgent, isConfirmPageUrl(url)));
    req.setAttribute(QNetworkRequest::RedirectPolicyAttribute,
                     QNetworkRequest::NoLessSafeRedirectPolicy);

    // CRITICAL: force identity encoding.  Qt's NAM transparently decompresses
    // gzip/deflate responses, which silently breaks byte-range math — the
    // server sends compressed bytes matching our Range header, but we see
    // decompressed bytes on the reply, so `received` no longer corresponds
    // to byte offsets on the server and segments assemble into garbage.
    req.setRawHeader("Accept-Encoding", "identity");

    // Look more like a browser.  Many filehosters (Rapidgator, Uploaded, etc.)
    // reject requests missing Accept / Accept-Language.
    req.setRawHeader("Accept", "*/*");
    req.setRawHeader("Accept-Language", "en-US,en;q=0.9");

    // SECURITY: CRLF header injection (CWE-113).
    // Qt's setRawHeader() does not validate header values for embedded CRLF
    // sequences.  Both cookies and referrer originate from the browser
    // extension (untrusted external input).  A value containing "\r\n" would
    // split the HTTP request and let an attacker inject arbitrary headers,
    // potentially poisoning shared caches or bypassing server-side checks.
    // Strip CR, LF, and NUL before touching any header derived from
    // extension-supplied data.
    auto stripCrlf = [](const QString &s) -> QByteArray {
        QString out;
        out.reserve(s.size());
        for (const QChar c : s) {
            if (c != u'\r' && c != u'\n' && c != u'\0')
                out.append(c);
        }
        return out.toUtf8();
    };

    // Cookies are injected into the NAM's cookie jar by seedCookieJar()
    // so they survive redirect chains.  Only fall back to the raw header
    // if the jar is unavailable (should never happen in practice).
    if (m_item && !m_item->cookies().isEmpty() && (!m_nam || !m_nam->cookieJar()))
        req.setRawHeader("Cookie", stripCrlf(m_item->cookies()));

    // Referer: critical for hotlink-protected hosters.  Stored on the item
    // by the browser extension but was previously never sent — major gap.
    if (m_item && !m_item->referrer().isEmpty())
        req.setRawHeader("Referer", stripCrlf(m_item->referrer()));

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

void SegmentedTransfer::setMaxConnectionsPerHost(int v) {
    m_maxConnectionsPerHost = qBound(1, v, kMaxDynamicSegments);
}

void SegmentedTransfer::seedCookieJar() {
    if (!m_item || m_item->cookies().isEmpty() || !m_nam) return;
    auto *jar = m_nam->cookieJar();
    if (!jar) return;

    QList<QNetworkCookie> cookies;
    const QByteArray raw = m_item->cookies().toUtf8();
    for (const QByteArray &pair : raw.split(';')) {
        QByteArray trimmed = pair.trimmed();
        int eq = trimmed.indexOf('=');
        if (eq > 0) {
            QNetworkCookie c(trimmed.left(eq), trimmed.mid(eq + 1));
            c.setDomain(m_item->url().host());
            c.setPath(QStringLiteral("/"));
            cookies.append(c);
        }
    }
    jar->setCookiesFromUrl(cookies, m_item->url());
}

void SegmentedTransfer::startNextPendingSegment() {
    int active = 0;
    for (const auto &seg : m_segments)
        if (!seg.done && seg.reply) ++active;
    if (active >= m_maxConnectionsPerHost) return;

    for (auto &seg : m_segments) {
        if (!seg.done && !seg.reply) {
            startSegment(seg);
            return;
        }
    }
}

void SegmentedTransfer::sendHeadRequest(const QUrl &overrideUrl) {
    const QUrl targetUrl = overrideUrl.isValid() ? overrideUrl : m_item->url();
    QNetworkRequest req(targetUrl);
    applyRequestHeaders(req, targetUrl);
    req.setTransferTimeout(15'000); // 15 s — don't hang forever on a dead server

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
    bool needsHtmlIntercept = isConfirmPageUrl(m_item->url()) && contentType.contains(QStringLiteral("text/html"));
    if (needsHtmlIntercept) {
        reply->deleteLater();
        m_headReply = nullptr;
        m_resumeCapable = false;
        m_item->setResumeCapable(false);
        m_htmlIntercepting = true;
        setupSegments(0, false);
        saveMeta();
        startAllSegments();
        m_progressTimer->start();
        emit started();
        return;
    }

    // Capture entity validators for If-Range on resume.
    m_etag = QString::fromUtf8(reply->rawHeader("ETag"));
    m_lastModified = QString::fromUtf8(reply->rawHeader("Last-Modified"));

    m_resumeCapable = (acceptRanges.trimmed().compare(QStringLiteral("bytes"), Qt::CaseInsensitive) == 0
                       && contentLength > 0);

    if (contentLength > 0)
        m_item->setTotalBytes(contentLength);

    m_item->setResumeCapable(m_resumeCapable);

    // Extract filename from Content-Disposition if present
    updateFilenameFromReply(reply);

    // Track the final URL after redirects so segment GETs go to the right host
    // (e.g. GDrive HEAD may redirect to a CDN URL that accepts Range requests).
    m_effectiveUrl = reply->url();
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

    int started = 0;
    for (auto &seg : m_segments) {
        if (started >= m_maxConnectionsPerHost) break;
        if (!seg.done) {
            startSegment(seg);
            ++started;
        }
    }
}

void SegmentedTransfer::startSegment(Segment &seg) {
    // Open part file for appending
    if (!seg.file) {
        seg.file = new QFile(longPath(seg.partPath));
    }
    if (!seg.file->isOpen()) {
        if (!seg.file->open(QIODevice::Append)) {
            emit failed(QStringLiteral("Cannot open part file: %1").arg(seg.partPath));
            return;
        }
    }

    // Use the effective URL (final URL after redirects) when available.
    // Falls back to the item URL so existing resume paths continue to work.
    const QUrl requestUrl = m_effectiveUrl.isValid() ? m_effectiveUrl : m_item->url();
    QNetworkRequest req(requestUrl);
    applyRequestHeaders(req, requestUrl);

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

        // If-Range: if we're resuming a partially-downloaded segment and we
        // have a server entity tag, tell the server "give me the range only
        // if the resource still matches; otherwise send the whole file".
        // This catches the case where a file changed server-side between
        // pause and resume — without it we'd silently splice old+new bytes.
        if (seg.received > 0) {
            if (!m_etag.isEmpty())
                req.setRawHeader("If-Range", m_etag.toUtf8());
            else if (!m_lastModified.isEmpty())
                req.setRawHeader("If-Range", m_lastModified.toUtf8());
        }
    }

    seg.lastByteTime = QDateTime::currentMSecsSinceEpoch();
    seg.reply = m_nam->get(req);

    int idx = seg.index;
    connect(seg.reply, &QNetworkReply::readyRead, this, [this, idx]() {
        onSegmentReadyRead(idx);
    });
    connect(seg.reply, &QNetworkReply::finished, this, [this, idx]() {
        onSegmentFinished(idx);
    });
    // Surface TLS errors into the log + errorString so users can diagnose
    // obscure hoster issues instead of seeing "Network error on segment N".
    connect(seg.reply, &QNetworkReply::sslErrors, this,
            [this, idx](const QList<QSslError> &errors) {
        QStringList msgs;
        for (const QSslError &e : errors) msgs << e.errorString();
        const QString joined = msgs.join(QStringLiteral("; "));
        qDebug() << "[ST] segment" << idx << "TLS errors:" << joined;
        if (m_item) m_item->setErrorString(QStringLiteral("TLS: ") + joined);
    });
}

void SegmentedTransfer::onSegmentReadyRead(int index) {
    if (index < 0 || index >= m_segments.size()) return;
    auto &seg = m_segments[index];
    if (!seg.reply || !seg.file) return;

    // GDrive auth check: if any segment (including Range-based resume segments)
    // ends up at accounts.google.com the session cookie has expired.  Abort all
    // connections immediately so we don't save an HTML login page as file data.
    // Parts and meta are intentionally left on disk so the user can re-add the
    // download from the browser (with fresh cookies) and resume from where it stopped.
    if (isConfirmPageUrl(m_item->url())) {
        const QString replyHost = seg.reply->url().host().toLower();
        if (replyHost.contains(QStringLiteral("accounts.google.com"))) {
            m_progressTimer->stop();
            for (auto &s : m_segments) {
                if (s.reply) { s.reply->disconnect(this); s.reply->abort(); s.reply->deleteLater(); s.reply = nullptr; }
                if (s.file)  { s.file->close(); }
            }
            m_htmlIntercepting = false;
            m_htmlInterceptBuf.clear();
            emit failed(QStringLiteral("Google Drive session expired. Re-add the download from your browser (right-click → Download with Stellar) to refresh authentication, then resume — your partial download will be reused."));
            return;
        }
    }

    // Google Drive HTML interception: buffer the first chunk to sniff content type
    if (m_htmlIntercepting && index == 0) {
        // Note: accounts.google.com auth-wall is already caught by the top-level
        // GDrive auth check above, so we only reach here for non-auth responses.
        qDebug() << "[HTMLIntercept] readyRead, replyHost=" << seg.reply->url().host() << "bufSize=" << m_htmlInterceptBuf.size();

        QByteArray data = seg.reply->readAll();
        m_htmlInterceptBuf.append(data);

        // Check Content-Disposition header — if present, it's the real file
        QByteArray cd = seg.reply->rawHeader("Content-Disposition");
        bool hasContentDisp = !cd.isEmpty() && cd.contains("filename");

        // Sniff the first bytes for HTML
        QByteArray head = m_htmlInterceptBuf.left(512).trimmed();
        bool looksLikeHtml = head.contains("<html") || head.contains("<!DOCTYPE") || head.contains("<!doctype");

        if (hasContentDisp || (!looksLikeHtml && m_htmlInterceptBuf.size() > 512)) {
            // Real file detected — check range support before committing to single-segment.
            m_htmlIntercepting = false;
            updateFilenameFromReply(seg.reply);
            qint64 cl = seg.reply->header(QNetworkRequest::ContentLengthHeader).toLongLong();
            const QString acceptRanges = QString::fromUtf8(seg.reply->rawHeader("Accept-Ranges")).trimmed();
            const bool rangeCapable = (acceptRanges.compare(QStringLiteral("bytes"), Qt::CaseInsensitive) == 0
                                       && cl > (qint64)kMinSegmentSize * m_segmentCount);
            if (rangeCapable) {
                // Abort the streaming GET and restart with proper Range segments.
                // The sniff buffer is discarded — negligible loss vs the gain of
                // parallel connections covering the entire file.
                m_effectiveUrl = seg.reply->url();
                m_etag = QString::fromUtf8(seg.reply->rawHeader("ETag"));
                m_lastModified = QString::fromUtf8(seg.reply->rawHeader("Last-Modified"));
                seg.reply->disconnect(this);
                seg.reply->abort();
                seg.reply->deleteLater();
                seg.reply = nullptr;
                if (seg.file) { seg.file->close(); QFile::remove(seg.partPath); delete seg.file; seg.file = nullptr; }
                m_htmlInterceptBuf.clear();
                m_resumeCapable = true;
                m_item->setResumeCapable(true);
                m_item->setTotalBytes(cl);
                setupSegments(cl, true);
                saveMeta();
                startAllSegments();
                return;
            }
            // Not range-capable (or file too small) — continue as single segment.
            if (cl > 0) m_item->setTotalBytes(cl);
            qint64 wrote = seg.file->write(m_htmlInterceptBuf);
            if (wrote != m_htmlInterceptBuf.size()) {
                m_item->setStatus(DownloadItem::Status::Error);
                emit failed(QStringLiteral("Disk write failed: %1").arg(seg.file->errorString()));
                return;
            }
            seg.received += wrote;
            m_htmlInterceptBuf.clear();
        }
        // Otherwise keep buffering until finished (confirmation pages are small)
        return;
    }

    // Universal range-upgrade: when a non-ranged single-segment GET returns its
    // first bytes and the server announces Accept-Ranges: bytes with a known
    // Content-Length, abort and restart as multi-segment.  This catches any site
    // where HEAD was skipped or failed but the actual GET supports ranges — the
    // GDrive confirmation-page restart, CDNs that ignore HEAD, etc.
    if (!m_htmlIntercepting
        && m_segments.size() == 1 && seg.endOffset < 0
        && seg.received == 0 && seg.pending.isEmpty()) {
        const QString acceptRanges = QString::fromUtf8(seg.reply->rawHeader("Accept-Ranges")).trimmed();
        const qint64 cl = seg.reply->header(QNetworkRequest::ContentLengthHeader).toLongLong();
        if (acceptRanges.compare(QStringLiteral("bytes"), Qt::CaseInsensitive) == 0
            && cl > (qint64)kMinSegmentSize * m_segmentCount) {
            updateFilenameFromReply(seg.reply);
            m_effectiveUrl = seg.reply->url();
            m_etag = QString::fromUtf8(seg.reply->rawHeader("ETag"));
            m_lastModified = QString::fromUtf8(seg.reply->rawHeader("Last-Modified"));
            seg.reply->disconnect(this);
            seg.reply->abort();
            seg.reply->deleteLater();
            seg.reply = nullptr;
            if (seg.file) { seg.file->close(); QFile::remove(seg.partPath); delete seg.file; seg.file = nullptr; }
            m_resumeCapable = true;
            m_item->setResumeCapable(true);
            m_item->setTotalBytes(cl);
            setupSegments(cl, true);
            saveMeta();
            startAllSegments();
            return;
        }
    }

    seg.lastByteTime = QDateTime::currentMSecsSinceEpoch();

    // On the very first data from segment 0, try to pick up the filename
    // from Content-Disposition (many servers only send it on GET, not HEAD).
    if (index == 0 && seg.received == 0 && seg.pending.isEmpty()) {
        updateFilenameFromReply(seg.reply);
    }

    // First-byte validation for ranged segments -------------------------
    //   1. 206 vs 200: if the server ignored Range and returned 200 to
    //      every segment, all segments would write the full file → garbage.
    //      Fall back to a single non-ranged connection.
    //   2. Content-Range total must match our known total.  If it doesn't,
    //      the file changed server-side since we probed — abort rather
    //      than splice mismatched bytes together.
    //   3. Content-Range start must equal our expected `from`.  Some
    //      proxies silently adjust ranges; catching this avoids corrupted
    //      offsets downstream.
    if (seg.endOffset >= 0 && seg.received == 0) {
        const int httpStatus = seg.reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();

        if (httpStatus == 200 && m_segments.size() > 1) {
            qDebug() << "[ST] segment" << index << "got 200 instead of 206 — server ignores Range; falling back to single segment";
            fallbackToSingleSegment();
            return;
        }

        if (httpStatus == 206) {
            const QByteArray cr = seg.reply->rawHeader("Content-Range");
            // Expected form: "bytes <start>-<end>/<total>"
            if (!cr.isEmpty()) {
                int slash = cr.lastIndexOf('/');
                int dash  = cr.indexOf('-');
                int space = cr.indexOf(' ');
                if (space > 0 && dash > space && slash > dash) {
                    bool okStart = false, okTotal = false;
                    qint64 start = cr.mid(space + 1, dash - space - 1).trimmed().toLongLong(&okStart);
                    QByteArray totalBa = cr.mid(slash + 1).trimmed();
                    qint64 total = (totalBa == "*") ? -1 : totalBa.toLongLong(&okTotal);

                    const qint64 expectedStart = seg.startOffset + seg.received;
                    if (okStart && start != expectedStart) {
                        qDebug() << "[ST] segment" << index << "Content-Range start mismatch:"
                                 << start << "vs expected" << expectedStart;
                        m_item->setStatus(DownloadItem::Status::Error);
                        emit failed(QStringLiteral("Server returned wrong byte range"));
                        return;
                    }
                    if (okTotal && total > 0 && m_item->totalBytes() > 0 && total != m_item->totalBytes()) {
                        qDebug() << "[ST] segment" << index << "total size changed server-side:"
                                 << total << "vs expected" << m_item->totalBytes();
                        m_item->setStatus(DownloadItem::Status::Error);
                        emit failed(QStringLiteral("File on server changed size during download"));
                        return;
                    }
                }
            }
        }
    }

    QByteArray data = seg.reply->readAll();
    if (data.isEmpty()) return;

    if (m_speedLimitKBps > 0) {
        seg.pending.append(data);
    } else {
        qint64 wrote = seg.file->write(data);
        if (wrote != data.size()) {
            // Disk full, permission denied, I/O error — fatal.  Abort
            // everything; retrying won't help if the disk is full.
            QString err = seg.file->errorString();
            qDebug() << "[ST] disk write failed on segment" << index << ":" << err;
            m_item->setStatus(DownloadItem::Status::Error);
            emit failed(QStringLiteral("Disk write failed: %1").arg(err));
            return;
        }
        seg.received += wrote;
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
    if (m_htmlIntercepting && index == 0) {
        QString replyHost = seg.reply->url().host().toLower();
        bool isAuthRedirect = replyHost.contains(QStringLiteral("accounts.google.com"));

        if (seg.reply->bytesAvailable() > 0)
            m_htmlInterceptBuf.append(seg.reply->readAll());
        QNetworkReply::NetworkError err = seg.reply->error();
        seg.reply->deleteLater();
        seg.reply = nullptr;
        if (seg.file) { seg.file->close(); QFile::remove(seg.partPath); }

        if (err != QNetworkReply::NoError) {
            emit failed(QStringLiteral("Google Drive request failed"));
            return;
        }

        if (isAuthRedirect) {
            m_htmlIntercepting = false;
            m_htmlInterceptBuf.clear();
            emit failed(QStringLiteral("Google Drive session expired. Re-add the download from your browser (right-click → Download with Stellar) to refresh authentication, then resume — your partial download will be reused."));
            return;
        }

        // Small response — check if it's a confirmation page
        QByteArray head = m_htmlInterceptBuf.left(512).trimmed();
        if (head.contains("<html") || head.contains("<!DOCTYPE") || head.contains("<!doctype")) {
            handleConfirmPage(m_htmlInterceptBuf);
        } else {
            // Small non-HTML response — write it as the file
            m_htmlIntercepting = false;
            if (!seg.file) seg.file = new QFile(seg.partPath);
            if (seg.file->open(QIODevice::WriteOnly)) {
                seg.file->write(m_htmlInterceptBuf);
                seg.received = m_htmlInterceptBuf.size();
                seg.file->close();
            }
            m_htmlInterceptBuf.clear();
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
    int httpStatus = seg.reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    QByteArray retryAfterHdr = seg.reply->rawHeader("Retry-After");
    seg.reply->deleteLater();
    seg.reply = nullptr;

    // --- Error / status classification ---------------------------------
    // Retriable: transport errors, 5xx, 408, 429 (with Retry-After honored).
    // Permanent: 4xx (except 408/429) — retrying is pointless.
    // Success:   2xx with error==NoError, AND received matches expected.
    auto isPermanentHttp = [](int s) {
        return s >= 400 && s < 500 && s != 408 && s != 429;
    };
    auto isRetriableHttp = [](int s) {
        return s == 408 || s == 429 || (s >= 500 && s < 600);
    };

    if (err != QNetworkReply::NoError && err != QNetworkReply::OperationCanceledError) {
        if (seg.file) seg.file->close();
        if (httpStatus > 0 && isPermanentHttp(httpStatus)) {
            m_item->setStatus(DownloadItem::Status::Error);
            emit failed(QStringLiteral("HTTP %1 on segment %2 — not retriable")
                        .arg(httpStatus).arg(index + 1));
            return;
        }
        // Honor Retry-After (seconds form only — the HTTP-date form is rare
        // and Qt's parser doesn't expose it cleanly here).
        int extraDelayMs = 0;
        if (!retryAfterHdr.isEmpty()) {
            bool ok = false;
            int seconds = retryAfterHdr.trimmed().toInt(&ok);
            if (ok && seconds > 0 && seconds < 600)
                extraDelayMs = seconds * 1000;
        }
        retrySegment(index, extraDelayMs);
        return;
    }

    // Some servers return 4xx/5xx with err==NoError (they just close cleanly
    // after sending an HTML error body).  Catch that here.
    if (httpStatus >= 400) {
        if (seg.file) seg.file->close();
        if (isPermanentHttp(httpStatus)) {
            m_item->setStatus(DownloadItem::Status::Error);
            emit failed(QStringLiteral("HTTP %1 on segment %2 — not retriable")
                        .arg(httpStatus).arg(index + 1));
            return;
        }
        if (isRetriableHttp(httpStatus)) {
            int extraDelayMs = 0;
            if (!retryAfterHdr.isEmpty()) {
                bool ok = false;
                int seconds = retryAfterHdr.trimmed().toInt(&ok);
                if (ok && seconds > 0 && seconds < 600)
                    extraDelayMs = seconds * 1000;
            }
            retrySegment(index, extraDelayMs);
            return;
        }
    }

    // Throttled with unflushed data: let onProgressTick drain pending before marking done
    if (m_speedLimitKBps > 0 && !seg.pending.isEmpty()) {
        seg.networkDone = true;
        return;
    }

    // --- Content-length verification -----------------------------------
    // For ranged segments, `received` must match the expected segment size,
    // otherwise the server closed early and we'd silently produce a truncated
    // file.  Retry instead of marking done.
    if (seg.endOffset >= 0) {
        qint64 expected = seg.endOffset - seg.startOffset + 1;
        if (seg.received < expected) {
            qDebug() << "[ST] segment" << index << "short:"
                     << seg.received << "of" << expected << "— retrying";
            if (seg.file) seg.file->close();
            retrySegment(index);
            return;
        }
    }

    seg.done = true;
    if (seg.file) seg.file->close();

    // Dynamic segmentation: we have a free connection — try to steal work
    // from the slowest remaining segment.  This is the key IDM behavior.
    maybeStealWork();

    // If there are segments waiting due to per-host connection cap, start one.
    startNextPendingSegment();

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
                    qint64 wrote = seg.file->write(seg.pending.constData(), toWrite);
                    if (wrote != toWrite) {
                        QString err = seg.file->errorString();
                        qDebug() << "[ST] throttled disk write failed:" << err;
                        m_progressTimer->stop();
                        m_item->setStatus(DownloadItem::Status::Error);
                        emit failed(QStringLiteral("Disk write failed: %1").arg(err));
                        return;
                    }
                    seg.received += wrote;
                    seg.pending.remove(0, (int)wrote);
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

    // Stall detection: if a live reply hasn't delivered any bytes within the
    // stall window, the connection is likely hung — kill it and retry.
    {
        qint64 now = QDateTime::currentMSecsSinceEpoch();
        for (int i = 0; i < m_segments.size(); ++i) {
            auto &seg = m_segments[i];
            if (seg.done || !seg.reply || seg.lastByteTime == 0) continue;
            if (now - seg.lastByteTime > kStallTimeoutMs) {
                qDebug() << "[ST] segment" << i << "stalled (" << (now - seg.lastByteTime) << "ms) — retrying";
                seg.reply->disconnect(this);
                seg.reply->abort();
                seg.reply->deleteLater();
                seg.reply = nullptr;
                if (seg.file) seg.file->close();
                retrySegment(i);
            }
        }
    }

    qint64 totalReceived = 0;
    for (const auto &seg : m_segments) {
        totalReceived += seg.received;
    }

    m_item->setDoneBytes(totalReceived);

    qint64 delta = totalReceived - m_lastReceived;
    m_lastReceived = totalReceived;

    // Maintain sliding window of per-tick byte deltas (max 120 ticks = 30 s at 250 ms/tick)
    m_speedSamples.append(delta);
    if (m_speedSamples.size() > 120)
        m_speedSamples.removeFirst();

    // Display speed: 2-second window (last 8 ticks) — prevents wild jumps in the UI
    int displayN = std::min((int)m_speedSamples.size(), 8);
    qint64 displaySum = 0;
    for (int i = (int)m_speedSamples.size() - displayN; i < (int)m_speedSamples.size(); ++i)
        displaySum += m_speedSamples[i];
    qint64 speedBps = displayN > 0 ? (displaySum * 4 / displayN) : 0;
    m_item->setSpeed(speedBps);

    // ETA speed: 30-second window (all samples) — stable enough to give a calm countdown
    {
        qint64 sum = 0;
        for (qint64 s : m_speedSamples) sum += s;
        qint64 etaSpeedBps = !m_speedSamples.isEmpty() ? (sum * 4 / (int)m_speedSamples.size()) : 0;
        m_item->setEtaSpeed(etaSpeedBps);
    }

    updateSegmentDataOnItem();

    // Checkpoint the meta file every ~5 s so an ungraceful exit loses at
    // most 5 s of progress instead of the entire download.  loadMeta()
    // already clamps to actual part-file size, so this is strictly a
    // safety net for the in-memory state.
    if (++m_ticksSinceMetaSave >= 20) {  // 20 × 250 ms = 5 s
        m_ticksSinceMetaSave = 0;
        saveMeta();
    }

    emit progressChanged(totalReceived, m_item->totalBytes(), speedBps);
}

void SegmentedTransfer::updateSegmentDataOnItem() {
    QVariantList list;
    for (const auto &seg : m_segments) {
        // Dynamic segments (index >= m_segmentCount) are implementation details —
        // they steal work from existing slots and should not add new rows to the UI.
        // The victim segment's row still reflects its own progress; the new segment's
        // bytes contribute to the overall progress bar but don't need their own row.
        if (seg.index >= m_segmentCount) continue;

        QVariantMap m;
        m[QStringLiteral("startByte")] = seg.startOffset;
        m[QStringLiteral("endByte")]   = seg.endOffset;
        m[QStringLiteral("received")]  = seg.received;
        if (seg.done)
            m[QStringLiteral("info")] = QStringLiteral("Complete");
        else if (seg.reply)
            m[QStringLiteral("info")] = QStringLiteral("Receiving data...");
        else
            m[QStringLiteral("info")] = QStringLiteral("Waiting...");
        list.append(m);
    }
    m_item->setSegmentData(list);
}

void SegmentedTransfer::mergeAndFinish() {
    // Check write access to the save directory before attempting assembly.
    // Catches missing permissions on Windows (ACLs) and Linux (read-only mounts)
    // before we spin up the worker thread and fail deep in I/O with a cryptic error.
    {
        const QString saveDir = m_item->savePath();
        QFileInfo dirInfo(saveDir);
        if (!dirInfo.isDir()) {
            QDir().mkpath(saveDir);
            dirInfo.refresh();
        }
        if (!dirInfo.isWritable()) {
            m_item->setStatus(DownloadItem::Status::Error);
            emit failed(QStringLiteral("No write permission for download directory: %1")
                        .arg(saveDir));
            return;
        }
    }

    m_item->setStatus(DownloadItem::Status::Assembling);

    // Reset doneBytes to 0 so the progress bar shows assembly progress from
    // scratch (0 → totalBytes) rather than staying pinned at 100%.
    qint64 totalForAssembly = m_item->totalBytes();
    m_item->setDoneBytes(0);
    m_speedSamples.clear();
    m_item->setSpeed(0);
    m_item->setEtaSpeed(0);

    QString outPath = longPath(m_item->savePath() + QStringLiteral("/") + m_item->filename());

    // Collect part paths in byte order before leaving the main thread.
    // Dynamic segmentation can append segments out of array order; sort by
    // startOffset so the concatenated file is correct.
    struct PartInfo { QString path; qint64 startOffset; };
    QList<PartInfo> parts;
    parts.reserve(static_cast<int>(m_segments.size()));

    bool singleNoRange = (m_segments.size() == 1 && m_segments[0].endOffset < 0);
    if (singleNoRange) {
        QString partSrc = m_segments[0].partPath;
        if (!QFile::exists(partSrc) && m_segments[0].file)
            partSrc = m_segments[0].file->fileName();
        parts.append({ partSrc, 0 });
    } else {
        for (const auto &seg : m_segments)
            parts.append({ seg.partPath, seg.startOffset });
        std::sort(parts.begin(), parts.end(),
                  [](const PartInfo &a, const PartInfo &b) {
                      return a.startOffset < b.startOffset;
                  });
    }

    // Run the file concatenation off the main thread so the UI stays live and
    // the "Assembling..." status is actually visible.
    auto *watcher = new QFutureWatcher<QString>(this);

    connect(watcher, &QFutureWatcher<QString>::finished, this,
            [this, watcher]() {
        watcher->deleteLater();
        const QString err = watcher->result();
        if (!err.isEmpty()) {
            m_item->setStatus(DownloadItem::Status::Error);
            emit failed(err);
            return;
        }
        cleanupPartFiles();
        deleteMetaFile();
        m_item->setStatus(DownloadItem::Status::Completed);
        emit finished();
    });

    auto *itemPtr = m_item;
    watcher->setFuture(QtConcurrent::run([singleNoRange, parts, outPath, itemPtr, totalForAssembly]() -> QString {
        static constexpr qint64 kChunkSize = 1024 * 1024; // 1 MB copy chunks
        // Reports current assembled-bytes count to the main thread via a queued
        // invocation — safe to call from the worker thread.
        auto reportProgress = [&](qint64 written) {
            QMetaObject::invokeMethod(itemPtr, [itemPtr, written]() {
                itemPtr->setDoneBytes(written);
            }, Qt::QueuedConnection);
        };

        if (singleNoRange) {
            // Fast path: rename in place — atomic, so we jump straight to 100%.
            const QString &partSrc = parts[0].path;
            if (QFile::rename(partSrc, outPath)) {
                reportProgress(totalForAssembly);
                return {};
            }

            // Rename failed (cross-device or permission denied on destination).
            // Fall back to copy+delete with progress reporting.
            QFile src(partSrc);
            if (!src.open(QIODevice::ReadOnly))
                return QStringLiteral("Cannot open part file for reading: %1 (%2)")
                    .arg(partSrc, src.errorString());

            QFile dst(outPath);
            if (!dst.open(QIODevice::WriteOnly | QIODevice::Truncate))
                return QStringLiteral("Cannot create output file: %1 (%2)")
                    .arg(outPath, dst.errorString());

            qint64 written = 0;
            while (!src.atEnd()) {
                const QByteArray chunk = src.read(kChunkSize);
                if (chunk.isEmpty()) break;
                if (dst.write(chunk) != chunk.size()) {
                    const QString err = dst.errorString();
                    dst.close();
                    QFile::remove(outPath);
                    return QStringLiteral("Write failed while assembling: %1").arg(err);
                }
                written += chunk.size();
                reportProgress(written);
            }
            dst.close();
            QFile::remove(partSrc);
            return {};
        }

        // Multi-segment: concatenate in startOffset order with per-chunk progress.
        QFile outFile(outPath);
        if (!outFile.open(QIODevice::WriteOnly | QIODevice::Truncate))
            return QStringLiteral("Cannot create output file: %1 (%2)")
                .arg(outPath, outFile.errorString());

        qint64 written = 0;
        for (const auto &part : parts) {
            QFile partFile(part.path);
            if (!partFile.open(QIODevice::ReadOnly)) {
                outFile.close();
                QFile::remove(outPath);
                return QStringLiteral("Cannot open part file for reading: %1 (%2)")
                    .arg(part.path, partFile.errorString());
            }
            while (!partFile.atEnd()) {
                const QByteArray chunk = partFile.read(kChunkSize);
                if (chunk.isEmpty()) break;
                if (outFile.write(chunk) != chunk.size()) {
                    const QString err = outFile.errorString();
                    partFile.close();
                    outFile.close();
                    QFile::remove(outPath);
                    return QStringLiteral("Write failed while assembling: %1").arg(err);
                }
                written += chunk.size();
                reportProgress(written);
            }
            partFile.close();
        }

        outFile.close();
        if (outFile.error() != QFileDevice::NoError)
            return QStringLiteral("Output file error after assembly: %1").arg(outFile.errorString());

        return {};
    }));
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

    if (filename.isEmpty() || m_item->isFilenameManuallySet()) return;

    // Strip filesystem-illegal characters before doing any compare or rename.
    // The old code compared a raw server-supplied filename against the
    // item's filename, which meant an invalid filename could get past the
    // equality check and then fail at rename time.
    filename = sanitizeFilename(filename);

    // SECURITY: Path traversal via Content-Disposition (CWE-22).
    // sanitizeFilename() strips characters illegal on Windows/Linux but does
    // NOT strip directory separators that survive as '..' components (e.g.
    // "../../evil.exe" contains only dots and letters, all of which are
    // legal).  A malicious server can write files outside the save directory
    // by sending:  Content-Disposition: attachment; filename="../../evil.exe"
    // Taking only the basename discards any directory component the server
    // tried to inject, whether encoded or plain.
    filename = QFileInfo(filename).fileName();
    if (filename == m_item->filename()) return;

    // Rename part files on disk before updating the stored filename, so the
    // file objects and seg.partPath stay consistent with what's actually on disk.
    QString oldMeta = metaPath();
    for (auto &seg : m_segments) {
        QString oldPart = seg.partPath;
        // Compute what the new partPath will be (based on the new filename)
        QString newPart = longPath(m_item->savePath() + QStringLiteral("/") + filename
                          + QStringLiteral(".stellar-part-") + QString::number(seg.index));
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

    // Try RFC 5987 extended value (filename*=charset'language'encoded) first.
    // SECURITY: CWE-20 — validate that the charset field claims UTF-8 before
    // calling QUrl::fromPercentEncoding (which always decodes as UTF-8).
    // Silently accepting ISO-8859-1 or windows-1251 would produce mojibake for
    // bytes ≥ 0x80, potentially resulting in corrupt filenames on disk.
    // If the charset is anything other than UTF-8 we fall through to the plain
    // filename= field which is unambiguously interpreted as UTF-8/Latin-1.
    int starIdx = header.indexOf("filename*=");
    if (starIdx >= 0) {
        QByteArray val = header.mid(starIdx + 10).trimmed();
        // Format: charset'language'encoded-value
        int q1 = val.indexOf('\'');
        if (q1 >= 0) {
            const QByteArray charset = val.left(q1).trimmed().toLower();
            int q2 = val.indexOf('\'', q1 + 1);
            if (q2 >= 0 && (charset == "utf-8" || charset == "utf8")) {
                val = val.mid(q2 + 1);
                int semi = val.indexOf(';');
                if (semi >= 0) val = val.left(semi);
                QString decoded = QUrl::fromPercentEncoding(val.trimmed());
                if (!decoded.isEmpty())
                    return decoded;
            }
            // Non-UTF-8 charset claimed — fall through to plain filename=
        }
    }

    // Plain filename="value" or filename=value
    int idx = header.indexOf("filename=");
    if (idx < 0)
        return {};
    QByteArray val = header.mid(idx + 9).trimmed();
    int semi = val.indexOf(';');
    if (semi >= 0) val = val.left(semi);
    val = val.trimmed();
    // Strip quotes
    if (val.startsWith('"') && val.endsWith('"'))
        val = val.mid(1, val.size() - 2);
    return QString::fromUtf8(val);
}

bool SegmentedTransfer::isConfirmPageUrl(const QUrl &url) const {
    const QString host = url.host().toLower();
    return host.endsWith(QStringLiteral("drive.google.com")) ||
           host.endsWith(QStringLiteral("drive.usercontent.google.com"));
}

void SegmentedTransfer::handleConfirmPage(const QByteArray &html) {
    qDebug() << "[HTMLIntercept] handling confirmation page, size:" << html.size();
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

    qDebug() << "[HTMLIntercept] parsed confirmation page, newUrl:" << newUrl;
    if (!newUrl.isValid()) {
        // Can't parse confirmation page — deliver what we got (the HTML)
        // and let it finish as-is; user will see a bad file.
        qDebug() << "[HTMLIntercept] FAILED to parse, first 2000 bytes:" << html.left(2000);
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
    m_htmlIntercepting = false;
    m_htmlInterceptBuf.clear();
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
    m_speedSamples.clear();
    m_item->setStatus(DownloadItem::Status::Paused);
    m_item->setSpeed(0);
    m_item->setEtaSpeed(0);
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
        const QString newPartPath = longPath(newSavePath + QStringLiteral("/") + newFilename
            + QStringLiteral(".stellar-part-") + QString::number(seg.index));
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

    m_speedSamples.clear();

    cleanupPartFiles();
    deleteMetaFile();

    // Don't access m_item here — it may be about to be deleted by DownloadQueue::cancel().
    // The item's final state will be set by whoever is calling abort().
}

// Retry a single segment after an error or stall, with exponential backoff.
// Once kMaxSegmentRetries is exceeded the whole download is failed.
// extraDelayMs lets the caller add a Retry-After delay on top of the backoff.
void SegmentedTransfer::retrySegment(int index, int extraDelayMs) {
    if (m_cancelled || m_paused || index < 0 || index >= m_segments.size()) return;
    auto &seg = m_segments[index];

    if (seg.retryCount >= kMaxSegmentRetries) {
        m_item->setStatus(DownloadItem::Status::Error);
        emit failed(QStringLiteral("Segment %1 failed after %2 retries").arg(index + 1).arg(kMaxSegmentRetries));
        return;
    }

    int delayMs = 1000 * (1 << seg.retryCount) + extraDelayMs; // 1 s, 2 s, 4 s, 8 s (+ Retry-After)
    ++seg.retryCount;

    qDebug() << "[ST] segment" << index << "scheduling retry" << seg.retryCount << "in" << delayMs << "ms";
    m_item->setDescription(QStringLiteral("Segment %1 retrying (attempt %2)…").arg(index + 1).arg(seg.retryCount));

    QTimer::singleShot(delayMs, this, [this, index]() {
        if (m_cancelled || m_paused || index >= m_segments.size()) return;
        m_item->setDescription({});
        startSegment(m_segments[index]);
    });
}

// Dynamic segmentation (IDM-style): when a segment finishes, check whether
// any other segment still has a significant amount of work left.  If so,
// split its remaining range in half and spawn a new segment for the second
// half, keeping all connections busy until the very end of the download.
//
// Only safe on range-capable servers, and only if we haven't already
// exploded into an absurd number of segments.
void SegmentedTransfer::maybeStealWork() {
    if (m_cancelled || m_paused) return;
    if (!m_resumeCapable) return;
    if (m_segments.size() >= kMaxDynamicSegments) return;

    // Count currently active connections — don't exceed the per-host cap.
    int activeCount = 0;
    for (const auto &seg : m_segments)
        if (!seg.done && seg.reply) ++activeCount;
    if (activeCount >= m_maxConnectionsPerHost) return;

    // Pick the segment with the most bytes still to fetch.
    int victimIdx = -1;
    qint64 victimRemaining = 0;
    for (int i = 0; i < m_segments.size(); ++i) {
        const auto &seg = m_segments[i];
        if (seg.done || !seg.reply || seg.endOffset < 0) continue;
        qint64 pos = seg.startOffset + seg.received;
        qint64 remaining = seg.endOffset - pos + 1;
        if (remaining > victimRemaining) {
            victimRemaining = remaining;
            victimIdx = i;
        }
    }
    if (victimIdx < 0 || victimRemaining < kStealThresholdBytes) return;

    auto &victim = m_segments[victimIdx];
    qint64 pos     = victim.startOffset + victim.received;
    qint64 oldEnd  = victim.endOffset;
    qint64 mid     = pos + victimRemaining / 2;

    qDebug() << "[ST] stealing: splitting segment" << victimIdx
             << "range" << pos << "-" << oldEnd << "at" << mid
             << "(" << victimRemaining << "bytes remaining)";

    // Abort the victim cleanly — its file is still valid up to `received`.
    victim.reply->disconnect(this);
    victim.reply->abort();
    victim.reply->deleteLater();
    victim.reply = nullptr;
    if (victim.file && victim.file->isOpen()) victim.file->close();

    // Shrink the victim to the first half.
    victim.endOffset  = mid - 1;
    victim.retryCount = 0;   // fresh retry budget for the shortened range
    victim.lastByteTime = 0;

    // Create a new segment for the second half.
    Segment ns;
    ns.index       = m_segments.size();
    ns.startOffset = mid;
    ns.endOffset   = oldEnd;
    ns.received    = 0;
    ns.partPath    = partPath(ns.index);
    m_segments.append(ns);

    // Persist the new layout BEFORE any network I/O happens, so a crash
    // between splitting and starting leaves a recoverable state on disk.
    saveMeta();

    // Restart the victim and fire up the new connection.
    startSegment(m_segments[victimIdx]);
    startSegment(m_segments.last());
}

// Called when a server ignores our Range header and returns 200 for every segment.
// We abort everything and restart as a single non-ranged connection.
void SegmentedTransfer::fallbackToSingleSegment() {
    if (m_cancelled || m_paused) return;

    m_progressTimer->stop();

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
    m_speedSamples.clear();
    m_lastReceived = 0;

    m_resumeCapable = false;
    m_item->setResumeCapable(false);
    m_item->setDoneBytes(0);
    m_item->setTotalBytes(0);

    setupSegments(0, false);
    saveMeta();
    startAllSegments();
    m_progressTimer->start();
}

void SegmentedTransfer::cleanupPartFiles() {
    // Remove every part file we currently know about.
    for (const auto &seg : m_segments) {
        QFile::remove(seg.partPath);
    }

    // Also sweep any orphaned `*.stellar-part-*` files matching the current
    // filename.  Dynamic segmentation can leave gaps in the index space
    // (e.g. we resumed at 8 segments but a prior session had 12), and a
    // stale filename change would leave the old parts dangling too.
    const QString dir = tempBaseDirectory();
    const QString prefix = m_item->filename() + QStringLiteral(".stellar-part-");
    QDir d(dir);
    const QStringList filters = { prefix + QStringLiteral("*") };
    const QFileInfoList stragglers = d.entryInfoList(filters, QDir::Files | QDir::NoDotAndDotDot);
    for (const QFileInfo &fi : stragglers) {
        QFile::remove(fi.absoluteFilePath());
    }
}

void SegmentedTransfer::deleteMetaFile() {
    QFile::remove(metaPath());
}

QString SegmentedTransfer::metaPath() const {
    return longPath(tempBaseDirectory() + QStringLiteral("/") + m_item->filename() + QStringLiteral(".stellar-meta"));
}

QString SegmentedTransfer::partPath(int index) const {
    return longPath(tempBaseDirectory() + QStringLiteral("/") + m_item->filename()
           + QStringLiteral(".stellar-part-") + QString::number(index));
}

QString SegmentedTransfer::tempBaseDirectory() const {
    return m_temporaryDirectory.trimmed().isEmpty() ? m_item->savePath() : m_temporaryDirectory.trimmed();
}

bool SegmentedTransfer::saveMeta() {
    QJsonObject root;
    // Fully-encoded form is stable across Qt versions and survives
    // round-tripping through the JSON parser.
    root[QStringLiteral("url")]           = QString::fromUtf8(m_item->url().toEncoded());
    root[QStringLiteral("totalBytes")]    = m_item->totalBytes();
    root[QStringLiteral("resumeCapable")] = m_resumeCapable;
    if (!m_etag.isEmpty())
        root[QStringLiteral("etag")] = m_etag;
    if (!m_lastModified.isEmpty())
        root[QStringLiteral("lastModified")] = m_lastModified;

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
    QSaveFile f(metaPath());
    if (!f.open(QIODevice::WriteOnly)) return false;
    if (f.write(QJsonDocument(root).toJson(QJsonDocument::Compact)) < 0)
        return false;
    return f.commit();
}

bool SegmentedTransfer::loadMeta() {
    QFile f(metaPath());
    if (!f.exists() || !f.open(QIODevice::ReadOnly)) return false;

    QJsonDocument doc = QJsonDocument::fromJson(f.readAll());
    f.close();
    if (doc.isNull()) return false;

    QJsonObject root = doc.object();
    const QString metaUrl = root[QStringLiteral("url")].toString();
    const QString itemUrl = QString::fromUtf8(m_item->url().toEncoded());
    if (!metaUrl.isEmpty() && metaUrl != itemUrl)
        return false;

    qint64 totalBytes = root[QStringLiteral("totalBytes")].toVariant().toLongLong();
    if (totalBytes <= 0)
        return false;
    m_item->setTotalBytes(totalBytes);

    m_etag = root[QStringLiteral("etag")].toString();
    m_lastModified = root[QStringLiteral("lastModified")].toString();

    QJsonArray segs = root[QStringLiteral("segments")].toArray();
    if (segs.isEmpty()) return false;

    m_segments.clear();
    qint64 done = 0;
    for (int i = 0; i < segs.size(); ++i) {
        QJsonObject s = segs[i].toObject();
        Segment seg;
        seg.index       = i;
        seg.startOffset = s[QStringLiteral("startOffset")].toVariant().toLongLong();
        seg.endOffset   = s[QStringLiteral("endOffset")].toVariant().toLongLong();
        seg.partPath    = partPath(i);
        if (seg.startOffset < 0)
            return false;
        if (seg.endOffset >= 0 && seg.endOffset < seg.startOffset)
            return false;

        const qint64 expectedLength = seg.endOffset >= 0
            ? (seg.endOffset - seg.startOffset + 1)
            : totalBytes;
        if (expectedLength < 0)
            return false;

        const qint64 savedReceived = s[QStringLiteral("received")].toVariant().toLongLong();
        const QFileInfo partInfo(seg.partPath);
        const qint64 actualSize = partInfo.exists() ? partInfo.size() : 0;
        seg.received = std::clamp(actualSize, 0ll, expectedLength);
        if (savedReceived > seg.received) {
            qDebug() << "[ST] loadMeta clamped" << seg.partPath
                     << "from" << savedReceived << "to" << seg.received;
        }
        seg.done = (seg.received >= expectedLength && expectedLength > 0);
        done += seg.received;
        m_segments.append(seg);
    }

    if (done > totalBytes)
        return false;

    m_resumeCapable = !m_segments.isEmpty();
    m_item->setResumeCapable(m_resumeCapable);

    m_lastReceived = done;
    m_item->setDoneBytes(done);

    saveMeta();

    return true;
}
