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
#include "FileNameUtils.h"
#include "AppVersion.h"
#include <QIODevice>
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
#include <QUrlQuery>
#include <QTimer>
#include <QDateTime>
#include <QSslError>
#include <QStringList>
#include <QSet>
#include <QNetworkCookieJar>
#include <QNetworkCookie>
#include <algorithm>
#include <cstring>
#include <limits>
#include <QDebug>

#ifdef Q_OS_LINUX
#include <fcntl.h>   // fallocate
#include <cerrno>    // errno
#endif

// Memory-map window size, shared by the assembly loop in mergeAndFinish().
// (mappedRangeCopy in FileNameUtils.h uses its own internal copy.)
static constexpr qint64 kMapWindow = 256LL * 1024 * 1024;

static const QString kUserAgent =
    QStringLiteral("Stellar/%1").arg(QStringLiteral(STELLAR_VERSION));
static const QString kBrowserUserAgent =
    QStringLiteral("Mozilla/5.0 (Windows NT 10.0; Win64; x64) Stellar/%1").arg(QStringLiteral(STELLAR_VERSION));

namespace {
// File extensions that are never legitimately served as text/html. If the URL
// path ends in one of these but the server answers text/html (with no
// Content-Disposition), the response is an HTML page masquerading as the file
// (login wall, JS viewer wrapper, error page). HTML/text-family extensions
// (html, htm, xml, svg, rss, atom, txt, json, csv, js, css) are deliberately
// excluded — they can legitimately be text/html and must not trip the guard.
const QSet<QString> &binaryExtensions() {
    static const QSet<QString> kExts = {
        QStringLiteral("pdf"),  QStringLiteral("zip"),  QStringLiteral("exe"),
        QStringLiteral("dmg"),  QStringLiteral("msi"),  QStringLiteral("iso"),
        QStringLiteral("mp4"),  QStringLiteral("mkv"),  QStringLiteral("avi"),
        QStringLiteral("mov"),  QStringLiteral("mp3"),  QStringLiteral("flac"),
        QStringLiteral("wav"),  QStringLiteral("7z"),   QStringLiteral("rar"),
        QStringLiteral("gz"),   QStringLiteral("bz2"),  QStringLiteral("xz"),
        QStringLiteral("tar"),  QStringLiteral("deb"),  QStringLiteral("rpm"),
        QStringLiteral("apk"),  QStringLiteral("pkg"),  QStringLiteral("bin"),
        QStringLiteral("img"),  QStringLiteral("doc"),  QStringLiteral("docx"),
        QStringLiteral("xls"),  QStringLiteral("xlsx"), QStringLiteral("ppt"),
        QStringLiteral("pptx"), QStringLiteral("epub"), QStringLiteral("mobi"),
        QStringLiteral("wasm"),
    };
    return kExts;
}

QString resolvedUserAgent(bool useCustomUserAgent, const QString &customUserAgent, bool browserStyleFallback) {
    const QString trimmedCustomUserAgent = customUserAgent.trimmed();
    if (useCustomUserAgent && !trimmedCustomUserAgent.isEmpty())
        return trimmedCustomUserAgent;

    return browserStyleFallback ? kBrowserUserAgent : kUserAgent;
}

// Returns false for strings that are clearly not a real filename (no extension,
// too long an extension, non-alphanumeric extension). Used to distinguish a URL
// path segment like "x64" from a genuine filename like "file.zip".
static bool isPlausibleFilename(const QString &name) {
    if (name.isEmpty() || name == QStringLiteral("download"))
        return false;
    int dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length() - 1)
        return false;
    const QString ext = name.mid(dot + 1);
    if (ext.length() > 10)
        return false;
    for (const QChar &ch : ext) {
        if (!ch.isLetterOrNumber() && ch != '_')
            return false;
    }
    return true;
}

}

// ── Shared helpers (external linkage; declared in FileNameUtils.h) ────────────
// Moved out of the anonymous namespace above so FtpTransfer can link against the
// same single implementation rather than duplicating it.

bool copyFileContents(QIODevice &src, QIODevice &dst, qint64 maxBytes,
                      QString *errorOut) {
    static constexpr qint64 kChunkSize = 1024 * 1024;
    qint64 remaining = maxBytes;
    while (maxBytes < 0 || remaining > 0) {
        const qint64 toRead = (maxBytes < 0) ? kChunkSize : std::min(remaining, kChunkSize);
        const QByteArray chunk = src.read(toRead);
        if (chunk.isEmpty()) break;
        if (dst.write(chunk) != chunk.size()) {
            if (errorOut)
                *errorOut = dst.errorString();
            return false;
        }
        if (maxBytes >= 0) remaining -= chunk.size();
    }
    return true;
}

bool mappedRangeCopy(QFile &src, qint64 srcOff, qint64 size,
                     QFile &dst, qint64 dstOff, QString *errorOut)
{
    static constexpr qint64 kMapWindow = 256LL * 1024 * 1024;
    qint64 remaining = size;
    while (remaining > 0) {
        const qint64 window = std::min(remaining, kMapWindow);
        uchar *srcPtr = src.map(srcOff, window);
        if (!srcPtr) {
            if (src.seek(srcOff) && dst.seek(dstOff))
                return copyFileContents(src, dst, window, errorOut);
            if (errorOut)
                *errorOut = QStringLiteral("Cannot map source at %1: %2")
                    .arg(srcOff).arg(src.errorString());
            return false;
        }
        uchar *dstPtr = dst.map(dstOff, window);
        if (!dstPtr) {
            src.unmap(srcPtr);
            if (errorOut)
                *errorOut = QStringLiteral("Cannot map output at %1: %2")
                    .arg(dstOff).arg(dst.errorString());
            return false;
        }
        std::memcpy(dstPtr, srcPtr, static_cast<size_t>(window));
        src.unmap(srcPtr);
        dst.unmap(dstPtr);
        srcOff += window;
        dstOff += window;
        remaining -= window;
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

    // Collapse path-traversal sequences — "." and ".." are never valid filename
    // components and could escape the save directory on unusual path-join paths.
    if (out == QLatin1String(".") || out == QLatin1String(".."))
        out = QStringLiteral("download");

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

SegmentedTransfer::SegmentedTransfer(DownloadItem *item,
                                     QNetworkAccessManager *nam,
                                     int segments,
                                     QObject *parent)
    : Transfer(parent), m_item(item), m_nam(nam), m_segmentCount(segments)
{
    m_progressTimer = new QTimer(this);
    m_progressTimer->setInterval(kTickIntervalMs);
    connect(m_progressTimer, &QTimer::timeout, this, &SegmentedTransfer::onProgressTick);
}

SegmentedTransfer::~SegmentedTransfer() {
    // Disconnect before aborting — abort() emits finished() synchronously, which
    // would invoke onSegmentFinished() and touch m_segments while we're iterating it.
    m_progressTimer->stop();
    if (m_headReply) {
        m_headReply->disconnect(this);
        m_headReply->abort();
        m_headReply->deleteLater();
        m_headReply = nullptr;
    }
    for (auto &seg : m_segments) {
        if (seg.reply) {
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
}

void SegmentedTransfer::start() {
    m_paused    = false;
    m_cancelled = false;

    seedCookieJar();
    m_item->setLastTryAt(QDateTime::currentDateTime());

    m_effectiveUrl = QUrl(); // reset on every fresh start
    m_recoveryAttempted = false; // allow one masquerade-recovery retry per run
    m_expectInterstitial = false; // content-driven; re-evaluated from this run's responses

    qDebug() << "[ST] start() url=" << m_item->url().toString()
             << "extensionless=" << urlHasNoExtension(m_item->url())
             << "hasCookies=" << !m_item->cookies().isEmpty()
             << "cookieLen=" << m_item->cookies().size();

    // Discard stale non-resumable metas (single-segment downloads with no Range
    // guarantee — produced by old code or by an interstitial-page fallback that
    // may have buffered HTML bytes into the part file). Valid range-based metas
    // (resumeCapable == true) are preserved so partially-downloaded files survive
    // restarts and hard kills. Host-agnostic: a non-resumable single-segment meta
    // is equally untrustworthy regardless of which server produced it.
    {
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
    // Use a browser-style User-Agent when we already know this is an HTML
    // interstitial flow, or — before the first response, when we don't yet know —
    // when the URL is extensionless. Extensionless cloud-download endpoints
    // (e.g. "/uc?id=...") are the ones that tend to gate on a browser UA.
    const bool browserStyleUa = m_expectInterstitial || urlHasNoExtension(url);
    req.setHeader(
        QNetworkRequest::UserAgentHeader,
        resolvedUserAgent(m_useCustomUserAgent, m_customUserAgent, browserStyleUa));
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

    // SECURITY: credential-bearing headers must only travel to the registered
    // domain of the original download URL. `url` is the destination — after a
    // HEAD redirect it becomes m_effectiveUrl, which a hostile server can point
    // at any host (Qt's NoLessSafeRedirectPolicy permits cross-host redirects).
    // Without this gate, a 302 to attacker.example would leak the item's
    // Basic-auth credentials and Referer. The NAM cookie jar is already
    // domain-scoped by Qt, so only the raw-Cookie fallback needs the same gate.
    const bool sameDomain = m_item && sameRegisteredDomain(url, m_item->url());

    // Cookies are injected into the NAM's cookie jar by seedCookieJar()
    // so they survive redirect chains.  Only fall back to the raw header
    // if the jar is unavailable (should never happen in practice).
    if (m_item && sameDomain && !m_item->cookies().isEmpty() && (!m_nam || !m_nam->cookieJar()))
        req.setRawHeader("Cookie", stripCrlf(m_item->cookies()));

    // Referer: critical for hotlink-protected hosters.  Stored on the item
    // by the browser extension but was previously never sent — major gap.
    if (m_item && sameDomain && !m_item->referrer().isEmpty())
        req.setRawHeader("Referer", stripCrlf(m_item->referrer()));

    if (m_item && sameDomain && !m_item->username().isEmpty()) {
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

    m_item->setContentType(contentType);

    // Interstitial detection (host-agnostic): the server answered text/html with
    // no Content-Disposition attachment for an *extensionless* URL (e.g.
    // "/uc?id=...", "/download?file=..."). That is the signature of a "click to
    // download" / virus-scan / confirmation gateway page standing in for the real
    // file. Fall back to a single streaming GET so onSegmentReadyRead can sniff
    // the HTML and follow it to the real download (handleInterstitialPage).
    //
    // Restricted to extensionless URLs so legitimate HTML/text downloads
    // (".html", ".txt", ".svg", ...) are never intercepted; the binary-extension
    // masquerade case is handled by the fail-fast guard below instead, since
    // there we have a concrete expected file and a possible query-param recovery.
    const QByteArray cdHeader = reply->rawHeader("Content-Disposition");
    const QByteArray cdLower = cdHeader.toLower();
    const bool serverAssertsFile = cdLower.contains("attachment") || cdLower.contains("filename");
    const bool isHtml = contentType.contains(QStringLiteral("text/html"));
    if (isHtml && !serverAssertsFile && urlHasNoExtension(m_item->url())) {
        reply->deleteLater();
        m_headReply = nullptr;
        m_resumeCapable = false;
        m_item->setResumeCapable(false);
        m_expectInterstitial = true;
        m_htmlIntercepting = true;
        setupSegments(0, false);
        saveMeta();
        startAllSegments();
        m_progressTimer->start();
        emit started();
        return;
    }

    // General guard (any site): the URL path implies a binary file but the
    // server answered text/html with no Content-Disposition attachment — an
    // HTML page (login wall, viewer wrapper, error/consent page) standing in
    // for the requested file. Fail fast before any part file is created so we
    // never persist garbage as e.g. a .pdf. Checked AFTER the extensionless
    // interstitial intercept above (which returns first); binary-extension URLs
    // cannot reach that branch, so they land here for masquerade recovery/fail.
    if (looksLikeHtmlMasqueradingAsBinary(m_item->url(), contentType,
                                          reply->rawHeader("Content-Disposition"))) {
        const QString expectedExt = QFileInfo(m_item->url().path()).suffix().toLower();
        // Tear down this reply before recovery: tryRecover -> sendHeadRequest
        // reassigns m_headReply, so it must be null here.
        reply->deleteLater();
        m_headReply = nullptr;
        // Some sites (e.g. iShares) carry the real file path in a query param
        // (iframeUrlOverride). Try once to recover it before giving up.
        if (!m_recoveryAttempted && tryRecoverMasqueradedUrl(expectedExt))
            return; // recovery HEAD now in flight; re-enters onHeadFinished
        const QString msg = htmlMasqueradeError();
        m_item->setErrorString(msg);
        m_item->setStatus(DownloadItem::Status::Error);
        emit failed(msg);
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
    // (e.g. a HEAD may redirect to a CDN URL that accepts Range requests).
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
        seg.uiSlot      = 0;
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
            seg.uiSlot      = i;
            m_segments.append(seg);
        }
    }

    // Publish the freshly-built layout to the UI immediately so the
    // connections list / progress visualizer renders all slots up front
    // instead of waiting for the first byte-tick to populate them.
    updateSegmentDataOnItem();
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
    // Open part file for reading and writing (needed for pre-allocation and
    // memory-mapped I/O).  ReadWrite gives us explicit control over the write
    // cursor; Append would force all writes to end-of-file regardless of seek.
    if (!seg.file) {
        seg.file = new QFile(longPath(seg.partPath));
    }
    if (!seg.file->isOpen()) {
        if (!seg.file->open(QIODevice::ReadWrite)) {
            emit failed(QStringLiteral("Cannot open part file: %1 (%2)")
                        .arg(seg.partPath, seg.file->errorString()));
            return;
        }

        if (seg.endOffset >= 0) {
            // Known segment size: pre-allocate the full range so the filesystem
            // can reserve contiguous space up front.  On Windows, QFile::resize()
            // calls SetEndOfFile (NTFS lazy-zero-fill, no I/O overhead).  On
            // Linux, ftruncate creates a sparse file; fallocate() below converts
            // it to a physically-allocated file in one metadata operation.
            const qint64 expectedSize = seg.endOffset - seg.startOffset + 1;

            if (seg.file->resize(expectedSize)) {
#ifdef Q_OS_LINUX
                int fd = seg.file->handle();
                if (fd >= 0) {
                    int ret = fallocate(fd, 0, 0, static_cast<off_t>(expectedSize));
                    if (ret != 0 && errno != EOPNOTSUPP && errno != ENOSYS
                        && errno != EINVAL) {
                        qDebug() << "[ST] segment" << seg.index
                                 << "fallocate failed (non-fatal):"
                                 << strerror(errno);
                    }
                }
#endif
                if (seg.received > 0) {
                    if (!seg.file->seek(seg.received)) {
                        emit failed(QStringLiteral("Cannot seek in part file: %1 (%2)")
                                    .arg(seg.partPath, seg.file->errorString()));
                        return;
                    }
                } else {
                    seg.file->seek(0);
                }
            } else {
                // resize() failed (FAT32 >4GB, network drive, etc.).
                // Fall back to Append mode — pre-allocation is an optimisation,
                // not a correctness requirement.
                qDebug() << "[ST] segment" << seg.index
                         << "pre-allocation failed:" << seg.file->errorString()
                         << "— falling back to Append";
                seg.file->close();
                if (!seg.file->open(QIODevice::Append)) {
                    emit failed(QStringLiteral("Cannot open part file: %1 (%2)")
                                .arg(seg.partPath, seg.file->errorString()));
                    return;
                }
            }
        } else {
            // Unknown segment size (endOffset == -1): cannot pre-allocate.
            // For resumed segments, advance the write cursor past existing data.
            if (seg.received > 0) {
                if (!seg.file->seek(seg.received)) {
                    emit failed(QStringLiteral("Cannot seek in part file: %1 (%2)")
                                .arg(seg.partPath, seg.file->errorString()));
                    return;
                }
            }
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

    // Without setReadBufferSize, QNAM drains the entire kernel socket buffer into
    // userspace RAM on every readyRead regardless of how much the app reads.
    // Setting it makes QNAM set downstreamLimited=true so it stops calling
    // socket->read() once its internal buffer is full — actual TCP backpressure.
    applyReplyReadBufferSize(seg.reply);

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

    // Auth-wall / off-domain redirect check (host-agnostic): if a reply's final
    // URL has left the registered domain of the original download AND the body
    // sniffs as HTML, the server redirected us to a sign-in or error page on an
    // identity provider (e.g. an "accounts.*" login wall) instead of the file.
    // Abort all connections immediately so we don't save an HTML login page as
    // file data. Parts and meta are intentionally left on disk so the user can
    // re-add the download from the browser (with fresh cookies) and resume from
    // where it stopped.
    if (!sameRegisteredDomain(seg.reply->url(), m_item->url())) {
        const QByteArray peeked = seg.reply->peek(512).trimmed();
        const QByteArray peekLower = peeked.toLower();
        const bool bodyIsHtml = peekLower.contains("<html") || peekLower.contains("<!doctype");
        if (bodyIsHtml) {
            const QString redirectHost = seg.reply->url().host();
            m_progressTimer->stop();
            for (auto &s : m_segments) {
                if (s.reply) { s.reply->disconnect(this); s.reply->abort(); s.reply->deleteLater(); s.reply = nullptr; }
                if (s.file)  { s.file->close(); }
            }
            m_htmlIntercepting = false;
            m_htmlInterceptBuf.clear();
            emit failed(tr("The server redirected to a sign-in or error page (%1) instead of "
                           "the file. Re-add the download from your browser (right-click → "
                           "Download with Stellar) to refresh authentication, then resume — "
                           "your partial download will be reused.").arg(redirectHost));
            return;
        }
    }

    // HTML interstitial interception: buffer the first chunk to sniff content type
    if (m_htmlIntercepting && index == 0) {
        // Note: an off-domain auth-wall redirect is already caught by the
        // domain-departure check above, so we only reach here for same-domain
        // responses (the real file, or a same-site confirmation page).
        qDebug() << "[HTMLIntercept] readyRead, replyHost=" << seg.reply->url().host() << "bufSize=" << m_htmlInterceptBuf.size();

        // Cap the sniff buffer: confirmation pages are at most a few KB.
        // Stop reading once we have enough to decide, and abort if a server
        // keeps sending past the limit (OOM guard against a malicious host).
        static constexpr qint64 kHtmlInterceptMaxBytes = 64 * 1024; // 64 KB
        if (m_htmlInterceptBuf.size() < kHtmlInterceptMaxBytes) {
            QByteArray data = seg.reply->readAll();
            m_htmlInterceptBuf.append(data);
        }
        if (m_htmlInterceptBuf.size() >= kHtmlInterceptMaxBytes) {
            qDebug() << "[HTMLIntercept] buffer limit reached — treating as real file";
            m_htmlIntercepting = false;
            m_htmlInterceptBuf.clear();
            seg.reply->disconnect(this);
            seg.reply->abort();
            seg.reply->deleteLater();
            seg.reply = nullptr;
            if (seg.file) { seg.file->close(); QFile::remove(seg.partPath); delete seg.file; seg.file = nullptr; }
            fallbackToSingleSegment();
            return;
        }

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
    // post-interstitial restart to the real file, CDNs that ignore HEAD, etc.
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
            seg.lastByteTime = 0;
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
                // Require at least one digit between each delimiter to prevent
                // malformed headers (e.g. "bytes 100-50/1000") from yielding
                // a zero-length mid() that silently parses as 0.
                if (space > 0 && dash > space + 1 && slash > dash + 1) {
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

    if (m_speedLimitKBps > 0) {
        // Throttled: don't read here — onProgressTick pulls exactly budgetPerSeg
        // bytes per tick directly from the reply. Reading eagerly would download
        // the whole file into RAM instantly regardless of the speed limit.
        return;
    }

    QByteArray data = seg.reply->readAll();
    if (data.isEmpty()) return;

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

    // HTML interstitial interception: response finished while still intercepting
    // means the entire response is small (a confirmation page or an off-domain
    // auth/error redirect).
    if (m_htmlIntercepting && index == 0) {
        // Off-domain redirect = sign-in / error page on another registered domain.
        const bool isAuthRedirect = !sameRegisteredDomain(seg.reply->url(), m_item->url());
        const QString redirectHost = seg.reply->url().host();

        if (seg.reply->bytesAvailable() > 0)
            m_htmlInterceptBuf.append(seg.reply->readAll());
        QNetworkReply::NetworkError err = seg.reply->error();
        seg.reply->deleteLater();
        seg.reply = nullptr;
        if (seg.file) { seg.file->close(); QFile::remove(seg.partPath); }

        if (err != QNetworkReply::NoError) {
            emit failed(tr("The download request failed."));
            return;
        }

        if (isAuthRedirect) {
            m_htmlIntercepting = false;
            m_htmlInterceptBuf.clear();
            emit failed(tr("The server redirected to a sign-in or error page (%1) instead of "
                           "the file. Re-add the download from your browser (right-click → "
                           "Download with Stellar) to refresh authentication, then resume — "
                           "your partial download will be reused.").arg(redirectHost));
            return;
        }

        // Small response — check if it's an interstitial page
        QByteArray head = m_htmlInterceptBuf.left(512).trimmed();
        if (head.contains("<html") || head.contains("<!DOCTYPE") || head.contains("<!doctype")) {
            handleInterstitialPage(m_htmlInterceptBuf);
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

    // Read any remaining bytes the network delivered before finishing.
    // In throttled mode, onProgressTick has been reading budgetPerSeg bytes per
    // tick directly from the reply; only a partial tick's worth can be left here.
    if (seg.reply->bytesAvailable() > 0) {
        QByteArray data = seg.reply->readAll();
        if (!data.isEmpty()) {
            if (m_speedLimitKBps > 0) {
                seg.pending.append(data); // small tail; drained by onProgressTick
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
        if (seg.endOffset < seg.startOffset) {
            qDebug() << "[ST] segment" << index << "invalid range (endOffset < startOffset) — aborting";
            m_item->setStatus(DownloadItem::Status::Error);
            emit failed(QStringLiteral("Internal error: degenerate segment range"));
            return;
        }
        qint64 expected = seg.endOffset - seg.startOffset + 1;
        if (seg.received < expected) {
            qDebug() << "[ST] segment" << index << "short:"
                     << seg.received << "of" << expected << "— retrying";
            if (seg.file) seg.file->close();
            retrySegment(index);
            return;
        }
    }

    seg.retryCount = 0;
    seg.done = true;
    if (seg.file) seg.file->close();

    // Completed segments keep their own UI slot so the dialog can continue
    // showing them as fully filled even if a replacement connection starts.
    maybeStealWork(-1);

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

    // Throttled: pull exactly one tick's worth of bytes from live replies.
    // Budget is the total allowed bytes this tick; segments that have nothing
    // available (e.g. newly started dynamic segments) yield their share back
    // to the pool so active segments can consume the full quota.
    if (m_speedLimitKBps > 0) {
        qint64 totalBudget = (qint64)m_speedLimitKBps * 1024 * kTickIntervalMs / 1000;

        // First pass: drain each segment up to an equal share, collect leftover.
        int busySegs = 0;
        for (const auto &seg : m_segments)
            if (!seg.done) ++busySegs;

        if (busySegs > 0) {
            qint64 sharePerSeg = std::max((qint64)1, totalBudget / busySegs);
            qint64 remaining = totalBudget;

            // Lambda to write data to a segment's file, returns false on disk error.
            auto writeToDisk = [&](Segment &seg, const QByteArray &data) -> bool {
                qint64 w = seg.file->write(data);
                if (w != data.size()) {
                    QString err = seg.file->errorString();
                    qDebug() << "[ST] throttled disk write failed:" << err;
                    m_progressTimer->stop();
                    m_item->setStatus(DownloadItem::Status::Error);
                    emit failed(QStringLiteral("Disk write failed: %1").arg(err));
                    return false;
                }
                seg.received += w;
                seg.lastByteTime = QDateTime::currentMSecsSinceEpoch();
                remaining -= w;
                return true;
            };

            // First pass: give each segment up to its share.
            for (auto &seg : m_segments) {
                if (seg.done || !seg.file || remaining <= 0) continue;

                qint64 cap = std::min(sharePerSeg, remaining);
                qint64 wrote = 0;

                if (seg.reply && !seg.networkDone) {
                    qint64 toRead = std::min(seg.reply->bytesAvailable(), cap);
                    if (toRead > 0) {
                        QByteArray data = seg.reply->read(toRead);
                        if (!data.isEmpty()) {
                            if (!writeToDisk(seg, data)) return;
                            wrote = data.size();
                        }
                    }
                }

                // Drain tail bytes buffered when reply finished mid-tick.
                if (seg.networkDone && !seg.pending.isEmpty()) {
                    qint64 toWrite = std::min((qint64)seg.pending.size(), cap - wrote);
                    if (toWrite > 0) {
                        QByteArray chunk = seg.pending.left((int)toWrite);
                        if (!writeToDisk(seg, chunk)) return;
                        seg.pending.remove(0, (int)toWrite);
                    }
                }
            }

            // Second pass: redistribute leftover budget to segments that still
            // have data, so inactive/new segments don't starve the total rate.
            if (remaining > 0) {
                for (auto &seg : m_segments) {
                    if (seg.done || !seg.file || remaining <= 0) continue;

                    if (seg.reply && !seg.networkDone) {
                        qint64 toRead = std::min(seg.reply->bytesAvailable(), remaining);
                        if (toRead > 0) {
                            QByteArray data = seg.reply->read(toRead);
                            if (!data.isEmpty()) {
                                if (!writeToDisk(seg, data)) return;
                            }
                        }
                    }

                    if (seg.networkDone && !seg.pending.isEmpty()) {
                        qint64 toWrite = std::min((qint64)seg.pending.size(), remaining);
                        if (toWrite > 0) {
                            QByteArray chunk = seg.pending.left((int)toWrite);
                            if (!writeToDisk(seg, chunk)) return;
                            seg.pending.remove(0, (int)toWrite);
                        }
                    }
                }
            }

            for (auto &seg : m_segments) {
                if (seg.done || !seg.file) continue;
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

    // Maintain sliding window of per-tick byte deltas
    m_speedSamples.append(delta);
    if (m_speedSamples.size() > kSpeedWindowTicks)
        m_speedSamples.removeFirst();

    // Display speed: short window to prevent wild UI jumps on bursty connections
    int displayN = std::min((int)m_speedSamples.size(), kDisplayWindowTicks);
    qint64 displaySum = 0;
    for (int i = (int)m_speedSamples.size() - displayN; i < (int)m_speedSamples.size(); ++i)
        displaySum += m_speedSamples[i];
    static constexpr int kTicksPerSecond = 1000 / kTickIntervalMs;
    qint64 speedBps = displayN > 0 ? (displaySum * kTicksPerSecond / displayN) : 0;
    m_item->setSpeed(speedBps);

    // ETA speed: full window (all samples) — stable enough to give a calm countdown
    {
        qint64 sum = 0;
        for (qint64 s : m_speedSamples) sum += s;
        qint64 etaSpeedBps = !m_speedSamples.isEmpty()
            ? (sum * kTicksPerSecond / (int)m_speedSamples.size()) : 0;
        m_item->setEtaSpeed(etaSpeedBps);
    }

    if (delta > 0)
        updateSegmentDataOnItem();

    // Checkpoint the meta file every ~5 s so an ungraceful exit loses at
    // most 5 s of progress instead of the entire download.  loadMeta()
    // already clamps to actual part-file size, so this is strictly a
    // safety net for the in-memory state.
    if (++m_ticksSinceMetaSave >= kMetaSaveIntervalTicks) {
        m_ticksSinceMetaSave = 0;
        saveMeta();
    }

    emit progressChanged(totalReceived, m_item->totalBytes(), speedBps);
}

void SegmentedTransfer::updateSegmentDataOnItem() {
    // Keep enough UI slots to show every connection that has existed so far.
    // Completed ranges should stay visible as fully-filled blue bars instead of
    // being recycled back to gray when a new connection steals more work later.
    //
    // Only reserve the full configured per-host count for resume-capable
    // transfers, where those slots legitimately fill as maybeStealWork() spawns
    // segments. A non-resumable transfer is single-segment and would otherwise
    // show a row of phantom "Waiting..." connections that never activate.
    int slotCount = (m_resumeCapable && m_segmentCount > 0) ? m_segmentCount : 1;
    for (const auto &seg : m_segments) {
        if (seg.uiSlot >= 0)
            slotCount = qMax(slotCount, seg.uiSlot + 1);
    }
    QVariantList list;
    list.reserve(qsizetype(slotCount));
    for (int i = 0; i < slotCount; ++i) {
        QVariantMap m;
        m[QStringLiteral("startByte")] = qint64(0);
        m[QStringLiteral("endByte")]   = qint64(-1);
        m[QStringLiteral("received")]  = qint64(0);
        m[QStringLiteral("info")]      = QStringLiteral("Waiting...");
        list.append(m);
    }
    for (const auto &seg : m_segments) {
        if (seg.uiSlot < 0 || seg.uiSlot >= slotCount) continue;
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
        list[seg.uiSlot] = m;
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
            [this, watcher, outPath]() {
        watcher->deleteLater();
        const QString err = watcher->result();
        if (!err.isEmpty()) {
            m_item->setStatus(DownloadItem::Status::Error);
            emit failed(err);
            return;
        }
        cleanupPartFiles();
        deleteMetaFile();

        // Backstop for HTML masquerading as the file when it slips past the
        // HEAD-time guard (server only reveals text/html on GET, or the bytes
        // were streamed via the m_htmlIntercepting single-segment path).
        //
        // Generic case: hosts that delete the file between HEAD and GET return a
        // small HTML error page — sniff only when < 50 KB to avoid touching real
        // downloads. But when the URL clearly expected a binary and its stored
        // content-type was text/html (e.g. a 52 KB JS viewer wrapper), the page
        // can exceed 50 KB, so lift the size cap for that case only.
        const bool expectedBinaryMismatch = looksLikeHtmlMasqueradingAsBinary(
            m_item->url(), m_item->contentType(),
            QByteArray() /* Content-Disposition not retained post-finish */);
        const qint64 sniffThreshold = expectedBinaryMismatch
            ? std::numeric_limits<qint64>::max()
            : (50 * 1024);
        QFileInfo fi(outPath);
        if (fi.size() > 0 && fi.size() < sniffThreshold) {
            QFile f(outPath);
            if (f.open(QIODevice::ReadOnly)) {
                const QByteArray head = f.read(512).trimmed();
                f.close();
                // Require explicit HTML markers — startsWith('<') alone matches SVG,
                // XML, RSS, ATOM and other valid small XML-family downloads.
                // Only fire on unambiguous HTML: <html tag or <!DOCTYPE html declaration.
                const QByteArray lower = head.toLower();
                bool looksLikeHtml = lower.startsWith("<!doctype html")
                    || lower.startsWith("<html");
                if (looksLikeHtml) {
                    // Remove the useless HTML file — the download is effectively failed.
                    QFile::remove(outPath);
                    m_item->setStatus(DownloadItem::Status::Error);
                    if (expectedBinaryMismatch) {
                        // Server sent an HTML page in place of the binary; the file
                        // exists, so the "no longer exists" warning would be wrong.
                        // Use the accurate masquerade message.
                        const QString msg = htmlMasqueradeError();
                        m_item->setErrorString(msg);
                        emit failed(msg);
                    } else {
                        m_item->setErrorString(QStringLiteral("The file no longer exists on the server."));
                        emit fileDeletedWarning();
                    }
                    return;
                }
            }
        }

        m_item->setStatus(DownloadItem::Status::Completed);
        emit finished();
    });

    auto *itemPtr = m_item;
    watcher->setFuture(QtConcurrent::run([singleNoRange, parts, outPath, itemPtr, totalForAssembly]() -> QString {
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
            // Fall back to memory-mapped copy + delete.
            QFile src(partSrc);
            if (!src.open(QIODevice::ReadOnly))
                return QStringLiteral("Cannot open part file for reading: %1 (%2)")
                    .arg(partSrc, src.errorString());

            QFile dst(outPath);
            if (!dst.open(QIODevice::ReadWrite | QIODevice::Truncate))
                return QStringLiteral("Cannot create output file: %1 (%2)")
                    .arg(outPath, dst.errorString());

            const qint64 srcSize = src.size();
            dst.resize(srcSize);

            QString mapErr;
            if (!mappedRangeCopy(src, 0, srcSize, dst, 0, &mapErr)) {
                dst.close();
                QFile::remove(outPath);
                return mapErr;
            }
            reportProgress(srcSize);
            dst.close();
            QFile::remove(partSrc);
            return {};
        }

        // Multi-segment: assemble in startOffset order via memory-mapped copy.
        // Pre-size the output file so the mapping covers the full range.
        QFile outFile(outPath);
        if (!outFile.open(QIODevice::ReadWrite | QIODevice::Truncate))
            return QStringLiteral("Cannot create output file: %1 (%2)")
                .arg(outPath, outFile.errorString());

        if (totalForAssembly > 0 && !outFile.resize(totalForAssembly))
            return QStringLiteral("Cannot pre-allocate output file: %1 (%2)")
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

            const qint64 partSize = partFile.size();
            qint64 partOff = 0;
            qint64 outOff  = part.startOffset;
            qint64 remaining = partSize;

            while (remaining > 0) {
                const qint64 window = std::min(remaining, kMapWindow);
                QString mapErr;
                if (!mappedRangeCopy(partFile, partOff, window,
                                     outFile, outOff, &mapErr))
                {
                    partFile.close();
                    outFile.close();
                    QFile::remove(outPath);
                    return mapErr;
                }
                partOff   += window;
                outOff    += window;
                remaining -= window;
                written   += window;
                reportProgress(written);
            }
            partFile.close();
        }

        outFile.close();
        if (outFile.error() != QFileDevice::NoError)
            return QStringLiteral("Output file error after assembly: %1")
                .arg(outFile.errorString());

        return {};
    }));
}

void SegmentedTransfer::updateFilenameFromReply(QNetworkReply *reply) {
    if (!reply || !m_item) return;

    QString filename = parseContentDispositionFilename(
        reply->rawHeader("Content-Disposition"));

    // Only fall back to the URL path when we have no plausible filename yet.
    // If the item already has a real filename (e.g. a redownload with
    // "file.zip"), a server-side redirect to an error/deletion page would
    // otherwise overwrite it with something like "already-downloaded". But if
    // the current filename is just a URL path segment guess ("x64", "latest"),
    // allow the redirect URL to supply the real name.
    if (filename.isEmpty() && !m_item->isFilenameManuallySet()
        && !isPlausibleFilename(m_item->filename())) {
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

    // Part and meta files are keyed on the download ID, not the filename, so
    // no on-disk renames are needed when the filename changes mid-download.
    m_item->setFilename(filename);
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
    // Strip surrounding quotes only when both are present and the string is
    // long enough to contain content between them.
    if (val.size() >= 2 && val.startsWith('"') && val.endsWith('"'))
        val = val.mid(1, val.size() - 2);
    return QString::fromUtf8(val);
}

bool SegmentedTransfer::urlHasNoExtension(const QUrl &url) {
    // QUrl::path() excludes the query string, so "/uc?id=..." yields "/uc"
    // (no suffix) and "/file.zip?x=1" yields suffix "zip". An empty suffix means
    // the last path segment carries no ".ext" — the shape of cloud-download
    // gateway endpoints (e.g. "/uc", "/download", "/d/<id>").
    return QFileInfo(url.path()).suffix().isEmpty();
}

bool SegmentedTransfer::looksLikeHtmlMasqueradingAsBinary(
        const QUrl &url, const QString &contentTypeLower,
        const QByteArray &contentDisposition) const {
    // QUrl::path() excludes the query string, so "file.pdf?stream=reg" yields
    // suffix "pdf". suffix() is the text after the final '.', already without
    // the query. Empty/extensionless paths (e.g. "/download?id=1") yield "".
    const QString ext = QFileInfo(url.path()).suffix().toLower();
    if (!binaryExtensions().contains(ext))
        return false;

    // Substring match tolerates parameters like "text/html;charset=UTF-8".
    if (!contentTypeLower.contains(QStringLiteral("text/html")))
        return false;

    // If the server explicitly asserts a download (attachment / filename=), it
    // is claiming this IS the file to save — trust that and do not trip, even
    // with a text/html content-type. A hostile server abusing this merely gets
    // the normal download path, where existing Content-Disposition path-
    // traversal guards still apply.
    const QByteArray cdLower = contentDisposition.toLower();
    if (cdLower.contains("attachment") || cdLower.contains("filename"))
        return false;

    return true;
}

QString SegmentedTransfer::htmlMasqueradeError() {
    return tr("Server returned an HTML page instead of the expected file. "
              "The link may require opening in a browser or may have expired. "
              "Nothing was saved.");
}

bool SegmentedTransfer::sameRegisteredDomain(const QUrl &a, const QUrl &b) {
    // Derive eTLD+1 using a hardcoded set of known multi-label public suffixes.
    // Qt has no public PSL API; the naive last-two-labels approach misidentifies
    // co.uk, com.au, github.io etc. as registrable domains, letting unrelated
    // tenants on the same public suffix compare equal and receive each other's
    // cookies, credentials, or Referer headers.
    static const QSet<QString> multiLabelTlds = {
        // ccTLD second-levels (common)
        QStringLiteral("co.uk"),  QStringLiteral("org.uk"),  QStringLiteral("me.uk"),
        QStringLiteral("net.uk"), QStringLiteral("ltd.uk"),  QStringLiteral("plc.uk"),
        QStringLiteral("co.nz"),  QStringLiteral("net.nz"),  QStringLiteral("org.nz"),
        QStringLiteral("co.za"),  QStringLiteral("net.za"),  QStringLiteral("org.za"),
        QStringLiteral("com.au"), QStringLiteral("net.au"),  QStringLiteral("org.au"),
        QStringLiteral("edu.au"), QStringLiteral("gov.au"),  QStringLiteral("asn.au"),
        QStringLiteral("com.br"), QStringLiteral("net.br"),  QStringLiteral("org.br"),
        QStringLiteral("com.ar"), QStringLiteral("net.ar"),  QStringLiteral("org.ar"),
        QStringLiteral("com.mx"), QStringLiteral("net.mx"),  QStringLiteral("org.mx"),
        QStringLiteral("com.tr"), QStringLiteral("net.tr"),  QStringLiteral("org.tr"),
        QStringLiteral("co.jp"),  QStringLiteral("ne.jp"),   QStringLiteral("or.jp"),
        QStringLiteral("co.in"),  QStringLiteral("net.in"),  QStringLiteral("org.in"),
        QStringLiteral("co.kr"),  QStringLiteral("ne.kr"),   QStringLiteral("or.kr"),
        QStringLiteral("com.cn"), QStringLiteral("net.cn"),  QStringLiteral("org.cn"),
        QStringLiteral("com.hk"), QStringLiteral("net.hk"),  QStringLiteral("org.hk"),
        QStringLiteral("com.sg"), QStringLiteral("net.sg"),  QStringLiteral("org.sg"),
        QStringLiteral("com.tw"), QStringLiteral("net.tw"),  QStringLiteral("org.tw"),
        // Hosting platforms (each subdomain is a distinct tenant)
        QStringLiteral("github.io"),       QStringLiteral("gitlab.io"),
        QStringLiteral("vercel.app"),      QStringLiteral("netlify.app"),
        QStringLiteral("pages.dev"),       QStringLiteral("workers.dev"),
        QStringLiteral("web.app"),         QStringLiteral("firebaseapp.com"),
        QStringLiteral("azurewebsites.net"),QStringLiteral("azurestaticapps.net"),
        QStringLiteral("onrender.com"),    QStringLiteral("fly.dev"),
        QStringLiteral("railway.app"),     QStringLiteral("pythonanywhere.com"),
    };

    auto registeredDomain = [](const QString &host) -> QString {
        const QStringList parts = host.split(QLatin1Char('.'));
        if (parts.size() < 2) return host;
        // Check if last three labels form a known multi-label TLD (e.g. co.uk).
        if (parts.size() >= 3) {
            const QString twoLabel = parts.at(parts.size() - 2) + QLatin1Char('.') + parts.last();
            if (multiLabelTlds.contains(twoLabel))
                return parts.at(parts.size() - 3) + QLatin1Char('.') + twoLabel;
        }
        return parts.at(parts.size() - 2) + QLatin1Char('.') + parts.last();
    };

    if (a.scheme() != b.scheme())
        return false;
    return registeredDomain(a.host().toLower()) == registeredDomain(b.host().toLower());
}

bool SegmentedTransfer::tryRecoverMasqueradedUrl(const QString &expectedExt) {
    if (expectedExt.isEmpty() || !binaryExtensions().contains(expectedExt))
        return false;

    const QUrl original = m_item->url();
    const QUrlQuery query(original);

    // Scan query values for one that points at the real file. Param-name-
    // agnostic so it covers iShares' iframeUrlOverride and any similar pattern.
    // FullyDecoded so percent-encoded paths (e.g. %2Fus%2F...pdf) are usable.
    QUrl candidate;
    const auto items = query.queryItems(QUrl::FullyDecoded);
    for (const auto &kv : items) {
        const QString value = kv.second;
        if (value.isEmpty())
            continue;
        QUrl c(value);
        if (c.isRelative())
            c = original.resolved(c); // absolute path "/us/...pdf" resolves against host
        if (!c.isValid())
            continue;
        // Require the exact expected extension so we don't grab an unrelated
        // binary-looking param, and the same registered domain + scheme so we
        // never issue a credentialed request off-host (rejects javascript:/
        // data:/file: and other-host absolute URLs).
        if (QFileInfo(c.path()).suffix().toLower() != expectedExt)
            continue;
        if (!sameRegisteredDomain(original, c))
            continue;
        candidate = c;
        break; // first valid wins
    }

    if (!candidate.isValid())
        return false;

    qDebug() << "[Recovery] HTML masquerade detected; retrying real file URL:" << candidate;
    m_recoveryAttempted = true;   // guard BEFORE re-HEAD so a second masquerade fails for real
    m_effectiveUrl = candidate;   // segment GETs target the recovered URL
    sendHeadRequest(candidate);   // reuses range / multi-segment / filename detection
    return true;
}

void SegmentedTransfer::handleInterstitialPage(const QByteArray &html) {
    qDebug() << "[HTMLIntercept] handling interstitial page, size:" << html.size();

    const QUrl newUrl = extractInterstitialTarget(html);

    qDebug() << "[HTMLIntercept] parsed interstitial page, newUrl:" << newUrl;
    if (!newUrl.isValid()) {
        qDebug() << "[HTMLIntercept] FAILED to parse, first 2000 bytes:" << html.left(2000);
        emit failed(tr("The download page did not contain a usable download link."));
        return;
    }

    // SECURITY: the URL parsed from HTML must share the registered domain of the
    // original download URL before we issue a credentialed request to it. A
    // spoofed or compromised interstitial could point at an attacker-controlled
    // host; without this check, cookies and Basic-auth would follow. We compare
    // registered domain (eTLD+1) so subdomains of the same site are accepted
    // (e.g. drive.google.com → drive.usercontent.google.com) while unrelated
    // hosts are rejected outright.
    if (!sameRegisteredDomain(m_item->url(), newUrl)) {
        qWarning() << "[HTMLIntercept] target URL rejected — domain mismatch:"
                   << newUrl.host() << "vs original" << m_item->url().host();
        emit failed(tr("The download page pointed to an unexpected host — download aborted for security."));
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
    applyReplyReadBufferSize(seg.reply);
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

QUrl SegmentedTransfer::extractInterstitialTarget(const QByteArray &html) const {
    const QString page = QString::fromUtf8(html);

    // Resolve a raw href/action string into an absolute URL against the item URL,
    // unescaping HTML entities first. Returns an invalid QUrl on empty input.
    auto resolve = [this](QString raw) -> QUrl {
        raw = raw.trimmed();
        if (raw.isEmpty())
            return {};
        raw.replace(QStringLiteral("&amp;"), QStringLiteral("&"));
        QUrl u(raw);
        if (u.isRelative())
            u = m_item->url().resolved(u);
        return u;
    };

    // Extract the value of attribute `attr` ("href"/"action"/"name"/"value")
    // starting the search at `from`, but not past `limit` (use to confine the
    // search to a single tag so a missing attribute doesn't borrow the next
    // tag's). Tolerates single or double quotes around the value.
    auto attrValueAt = [&page](const QString &attr, int from, int limit = -1) -> QString {
        if (limit < 0) limit = page.size();
        int eq = page.indexOf(attr + QStringLiteral("="), from);
        if (eq < 0 || eq >= limit)
            return {};
        int vstart = eq + attr.size() + 1;
        if (vstart >= page.size())
            return {};
        const QChar quote = page.at(vstart);
        if (quote == u'"' || quote == u'\'') {
            int vend = page.indexOf(quote, vstart + 1);
            if (vend > vstart)
                return page.mid(vstart + 1, vend - vstart - 1);
        }
        return {};
    };

    // 1) <meta http-equiv="refresh" content="N; url=...">  — a very common
    //    interstitial redirect, host-agnostic.
    {
        int metaIdx = page.indexOf(QStringLiteral("http-equiv"), 0, Qt::CaseInsensitive);
        while (metaIdx >= 0) {
            // Confirm it's a refresh directive, then pull the content= value.
            int tagStart = page.lastIndexOf('<', metaIdx);
            int tagEnd = page.indexOf('>', metaIdx);
            if (tagStart >= 0 && tagEnd > tagStart) {
                const QString tag = page.mid(tagStart, tagEnd - tagStart + 1);
                if (tag.contains(QStringLiteral("refresh"), Qt::CaseInsensitive)) {
                    const QString content = attrValueAt(QStringLiteral("content"), tagStart);
                    const int urlPos = content.indexOf(QStringLiteral("url="), 0, Qt::CaseInsensitive);
                    if (urlPos >= 0) {
                        const QUrl u = resolve(content.mid(urlPos + 4));
                        if (u.isValid())
                            return u;
                    }
                }
            }
            metaIdx = page.indexOf(QStringLiteral("http-equiv"), metaIdx + 1, Qt::CaseInsensitive);
        }
    }

    // 2) First <form ... action="..."> — the modern Google Drive confirmation
    //    page and most "click to download" gateways submit a form. We take the
    //    first form's action regardless of its id/class (the old code hardcoded
    //    id="download-form"). Crucially we also merge the form's hidden <input>
    //    name/value pairs into the action's query string: confirmation forms
    //    carry the tokens that turn a bare endpoint into a real download (e.g.
    //    confirm=t, uuid=..., export=download). Submitting the action *without*
    //    them yields a slow fallback and a missing Content-Disposition (so the
    //    file saves under the URL's last path segment instead of its real name).
    //    The same-domain gate in the caller is the security backstop against a
    //    hostile form action.
    {
        int formIdx = page.indexOf(QStringLiteral("<form"), 0, Qt::CaseInsensitive);
        if (formIdx >= 0) {
            QUrl u = resolve(attrValueAt(QStringLiteral("action"), formIdx));
            if (u.isValid()) {
                // Bound the scan to this form element so we don't pull inputs from
                // an unrelated later form. Missing </form> → scan to end of page.
                int formEnd = page.indexOf(QStringLiteral("</form"), formIdx, Qt::CaseInsensitive);
                if (formEnd < 0) formEnd = page.size();

                QUrlQuery query(u);
                int inputIdx = page.indexOf(QStringLiteral("<input"), formIdx, Qt::CaseInsensitive);
                while (inputIdx >= 0 && inputIdx < formEnd) {
                    int tagEnd = page.indexOf('>', inputIdx);
                    if (tagEnd < 0 || tagEnd > formEnd) break;
                    const QString name = attrValueAt(QStringLiteral("name"), inputIdx, tagEnd);
                    if (!name.isEmpty()) {
                        // value= may be absent (e.g. <input name="x">) → empty value.
                        QString value = attrValueAt(QStringLiteral("value"), inputIdx, tagEnd);
                        value.replace(QStringLiteral("&amp;"), QStringLiteral("&"));
                        // Don't clobber a param the action URL already carries.
                        if (!query.hasQueryItem(name))
                            query.addQueryItem(name, value);
                    }
                    inputIdx = page.indexOf(QStringLiteral("<input"), tagEnd + 1, Qt::CaseInsensitive);
                }
                u.setQuery(query);
                return u;
            }
        }
    }

    // 3) First download-hinting <a ... href="...">. We scan anchors and accept the
    //    first whose tag or href hints a download (id/class/text mentioning
    //    "download"/"confirm", or an href carrying confirm=/export=download).
    //    Generalizes the old id="uc-download-link" match.
    {
        int aIdx = page.indexOf(QStringLiteral("<a "), 0, Qt::CaseInsensitive);
        while (aIdx >= 0) {
            int tagEnd = page.indexOf('>', aIdx);
            if (tagEnd < 0)
                break;
            const QString openTag = page.mid(aIdx, tagEnd - aIdx + 1);
            const QString href = attrValueAt(QStringLiteral("href"), aIdx);
            const QString hrefLower = href.toLower();
            const QString tagLower = openTag.toLower();
            const bool hints =
                tagLower.contains(QStringLiteral("download")) ||
                tagLower.contains(QStringLiteral("confirm")) ||
                hrefLower.contains(QStringLiteral("confirm=")) ||
                hrefLower.contains(QStringLiteral("export=download"));
            if (hints) {
                const QUrl u = resolve(href);
                if (u.isValid())
                    return u;
            }
            aIdx = page.indexOf(QStringLiteral("<a "), tagEnd + 1, Qt::CaseInsensitive);
        }
    }

    return {};
}

// Sets the QNAM internal read-buffer cap on a reply so that QNAM stops draining
// the kernel socket once its buffer is full, creating real TCP backpressure.
// Must be called immediately after reply creation and whenever the limit changes.
void SegmentedTransfer::applyReplyReadBufferSize(QNetworkReply *reply) {
    if (!reply) return;
    if (m_speedLimitKBps <= 0) {
        reply->setReadBufferSize(0); // unlimited
        return;
    }
    int activeSegs = 0;
    for (const auto &s : m_segments) if (!s.done) ++activeSegs;
    if (activeSegs < 1) activeSegs = 1;
    qint64 bufSize = qMax((qint64)m_speedLimitKBps * 1024 * kReadBufferSeconds / activeSegs,
                          kMinReadBufferBytes);
    reply->setReadBufferSize(bufSize);
}

void SegmentedTransfer::setSpeedLimitKBps(int kbps) {
    int oldLimit = m_speedLimitKBps;
    m_speedLimitKBps = kbps;

    // Update read-buffer cap on all live replies so backpressure takes effect now.
    for (auto &seg : m_segments)
        applyReplyReadBufferSize(seg.reply);

    // Transitioning throttled → unlimited: discard pending buffers.
    // The network replies are still active — new data arriving via
    // onSegmentReadyRead will now go straight to disk (since kbps==0).
    // Discarding pending means those bytes will be re-received from the
    // server (the reply is already positioned past them, so we actually
    // need to flush to avoid a gap).  Flush pending to disk here.
    if (oldLimit > 0 && kbps == 0) {
        for (auto &seg : m_segments) {
            // Flush any tail bytes that arrived while throttled and were held
            // in seg.pending waiting for the tick to drain them.
            if (!seg.pending.isEmpty() && seg.file) {
                seg.file->write(seg.pending);
                seg.received += seg.pending.size();
                seg.pending.clear();
            }
            // Drain whatever the reply has buffered in QNAM — now that we're
            // unlimited, read it all directly to disk.
            if (seg.reply && seg.file && !seg.networkDone) {
                qint64 avail = seg.reply->bytesAvailable();
                if (avail > 0) {
                    QByteArray data = seg.reply->readAll();
                    seg.file->write(data);
                    seg.received += data.size();
                }
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
        if (seg.networkDone && !seg.done && seg.endOffset >= seg.startOffset &&
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
        const QString newPartPath = longPath(newSavePath + QStringLiteral("/") + m_item->id()
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
                    seg.file->open(QIODevice::ReadWrite);
                return false;
            }
        }

        if (seg.file)
            seg.file->setFileName(newPartPath);
        if (wasOpen && seg.file) {
            if (!seg.file->open(QIODevice::ReadWrite)) {
                qDebug() << "[ST] relocateOutput: cannot reopen segment"
                         << seg.index << seg.file->errorString();
                return false;
            }
            if (seg.endOffset >= 0 && !seg.done) {
                const qint64 expectedSize = seg.endOffset - seg.startOffset + 1;
                seg.file->resize(expectedSize);
            }
            if (seg.received > 0)
                seg.file->seek(seg.received);
        }
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
        if (m_cancelled || m_paused) return;
        if (index < 0 || index >= m_segments.size()) return;
        // The segment list may have been rebuilt (e.g. fallback to single segment)
        // between scheduling and firing — skip if this slot is already done or
        // has an active reply (restarted by another path).
        const auto &seg = m_segments[index];
        if (seg.done || seg.reply) return;
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
bool SegmentedTransfer::maybeStealWork(int freedUiSlot) {
    Q_UNUSED(freedUiSlot);
    if (m_cancelled || m_paused) return false;
    if (!m_resumeCapable) return false;
    if (m_segments.size() >= kMaxDynamicSegments) return false;

    // Count currently active connections — don't exceed the per-host cap.
    int activeCount = 0;
    for (const auto &seg : m_segments)
        if (!seg.done && seg.reply) ++activeCount;
    if (activeCount >= m_maxConnectionsPerHost) return false;

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
    if (victimIdx < 0 || victimRemaining < kStealThresholdBytes) return false;

    auto &victim = m_segments[victimIdx];
    qint64 pos     = victim.startOffset + victim.received;
    qint64 oldEnd  = victim.endOffset;

    // Recompute remaining from live fields rather than the loop's snapshot to
    // guard against corrupt resume metadata where endOffset drifted since the
    // loop ran.  If the range is degenerate, bail out — do not create an
    // invalid segment.
    qint64 liveRemaining = oldEnd - pos + 1;
    if (liveRemaining < kStealThresholdBytes) return false;

    qint64 mid = pos + liveRemaining / 2;
    // Clamp: mid must leave at least one byte in each half.
    mid = qBound(pos + 1, mid, oldEnd - 1);

    qDebug() << "[ST] stealing: splitting segment" << victimIdx
             << "range" << pos << "-" << oldEnd << "at" << mid
             << "(" << victimRemaining << "bytes remaining)";

    // Abort the victim cleanly — its file is still valid up to `received`.
    victim.reply->disconnect(this);
    victim.reply->abort();
    victim.reply->deleteLater();
    victim.reply = nullptr;
    if (victim.file && victim.file->isOpen()) victim.file->close();

    // Shrink the victim to the first half. The victim keeps its own UI slot —
    // it's still actively downloading (just a smaller range now).
    victim.endOffset  = mid - 1;
    victim.retryCount = 0;   // fresh retry budget for the shortened range
    victim.lastByteTime = 0;

    // Create a new segment for the second half. Give it a fresh UI slot so
    // completed connections remain visible instead of being recycled away.
    Segment ns;
    ns.index       = m_segments.size();
    ns.startOffset = mid;
    ns.endOffset   = oldEnd;
    ns.received    = 0;
    ns.partPath    = partPath(ns.index);
    int nextUiSlot = 0;
    for (const auto &seg : m_segments)
        nextUiSlot = qMax(nextUiSlot, seg.uiSlot + 1);
    ns.uiSlot = nextUiSlot;
    m_segments.append(ns);

    // Persist the new layout BEFORE any network I/O happens, so a crash
    // between splitting and starting leaves a recoverable state on disk.
    saveMeta();

    // Restart the victim and fire up the new connection.
    startSegment(m_segments[victimIdx]);
    startSegment(m_segments.last());

    // Reapply buffer sizes on all replies — activeSegs just increased so the
    // per-segment share changed. Old replies need their cap updated too.
    if (m_speedLimitKBps > 0) {
        for (auto &seg : m_segments)
            applyReplyReadBufferSize(seg.reply);
    }
    return true;
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

    // Sweep orphaned part files for this download ID — covers dynamic-segmentation
    // index gaps (e.g. resumed at 8 segments but prior session had 12).
    const QString dir = tempBaseDirectory();
    const QString prefix = m_item->id() + QStringLiteral(".stellar-part-");
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
    // Keyed on download ID (not filename) so two simultaneous downloads of
    // identically-named files (e.g. "index.html") never share part/meta files.
    return longPath(tempBaseDirectory() + QStringLiteral("/") + m_item->id() + QStringLiteral(".stellar-meta"));
}

QString SegmentedTransfer::partPath(int index) const {
    return longPath(tempBaseDirectory() + QStringLiteral("/") + m_item->id()
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
    if (segs.size() > kMaxDynamicSegments) return false;

    m_segments.clear();
    qint64 done = 0;
    for (int i = 0; i < segs.size(); ++i) {
        QJsonObject s = segs[i].toObject();
        Segment seg;
        seg.index       = i;
        seg.startOffset = s[QStringLiteral("startOffset")].toVariant().toLongLong();
        seg.endOffset   = s[QStringLiteral("endOffset")].toVariant().toLongLong();
        seg.partPath    = partPath(i);
        // Persisted metas predate the uiSlot field; assign one based on the
        // segment's index so the connections-list UI shows a row for every
        // restored segment instead of leaving them all as "Waiting…".
        // Dynamic-stolen segments (i >= m_segmentCount) inherit -1 and only
        // re-acquire a slot if maybeStealWork() spawns them again.
        seg.uiSlot      = (i < m_segmentCount) ? i : -1;
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

    // Surface the restored segment layout immediately so the progress dialog
    // shows real bytes/per-connection rows instead of placeholder "Waiting…"
    // entries while the first byte-tick is still pending.
    updateSegmentDataOnItem();

    return true;
}
