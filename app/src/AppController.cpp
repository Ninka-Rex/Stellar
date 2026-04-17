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

#include "AppController.h"
#include <QQuickWindow>
#include <QIcon>
#include "DownloadItem.h"
#include "AppVersion.h"
#include <QtConcurrent>
#include <QLocalServer>
#include <QLocalSocket>
#include <QUuid>
#include <QDateTime>
#include <QDir>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QDesktopServices>
#include <QNetworkAccessManager>
#include <QNetworkInterface>
#include <QNetworkProxy>
#include <QNetworkProxyFactory>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QUrlQuery>
#include <QDebug>
#include <memory>
#include "AppSettings.h"
#include <utility>
#include "DownloadQueue.h"
#include "DownloadTableModel.h"
#include "CategoryModel.h"
#include "NativeMessagingHost.h"
#include "SystemTrayIcon.h"
#include "DownloadDatabase.h"
#include "GrabberCrawler.h"
#include "GrabberProjectModel.h"
#include "GrabberResultModel.h"
#include "QueueDatabase.h"
#include "QueueModel.h"
#include "YtdlpManager.h"
#include "TorrentFileModel.h"
#include "YtdlpTransfer.h"
#if defined(STELLAR_WINDOWS)
#  include <windows.h>
#  include <shellapi.h>
#endif
#include <QUrl>
#include <QFile>
#include <QFileInfo>
#include <QSaveFile>
#include <QStandardPaths>
#include <QCoreApplication>
#include <QGuiApplication>
#include <QClipboard>
#include <QProcess>
#include <QTimer>
#include <QLocale>
#include <QRegularExpression>
#include <QVersionNumber>
#include <QCryptographicHash>
#include <QTemporaryDir>
#include <QDirIterator>
#include <QFileDevice>
#include <Queue.h>

namespace {
constexpr int kMinimumUpdateCheckIndicatorMs = 3000;
constexpr qint64 kTorrentSpeedHistoryRetentionMs = 24LL * 60LL * 60LL * 1000LL;

QString cleanedYtdlpError(const QString &reason) {
    QString text = reason;
    text.replace(QStringLiteral("\r\n"), QStringLiteral("\n"));
    text.replace(QRegularExpression(QStringLiteral(R"((\r?\n)+null\s*$)")), QString());
    return text.trimmed();
}

QString effectiveTemporaryDirectory(const AppSettings *settings) {
    const QString configured = settings ? settings->temporaryDirectory().trimmed() : QString();
    return configured.isEmpty()
        ? (QStandardPaths::writableLocation(QStandardPaths::TempLocation) + QStringLiteral("/Stellar"))
        : configured;
}

QString writableRuntimeRoot() {
    QString dir = QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation);
    if (dir.isEmpty())
        dir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    if (dir.isEmpty())
        dir = QCoreApplication::applicationDirPath();
    QDir().mkpath(dir);
    return dir;
}

QString writableRuntimeDataDir() {
    const QString dir = writableRuntimeRoot() + QStringLiteral("/data");
    QDir().mkpath(dir);
    return dir;
}

QString writableRuntimeToolsDir() {
    const QString dir = writableRuntimeRoot() + QStringLiteral("/tools");
    QDir().mkpath(dir);
    return dir;
}

QString buildYtdlpProxyUrl(const AppSettings *settings, const QUrl &targetUrl) {
    if (!settings)
        return {};

    auto proxyToUrl = [](const QNetworkProxy &proxy) -> QString {
        if (proxy.type() == QNetworkProxy::NoProxy ||
            proxy.type() == QNetworkProxy::DefaultProxy) {
            return {};
        }

        const QString host = proxy.hostName().trimmed();
        if (host.isEmpty() || proxy.port() <= 0)
            return {};

        const QString scheme = proxy.type() == QNetworkProxy::Socks5Proxy
            ? QStringLiteral("socks5")
            : QStringLiteral("http");

        QUrl url;
        url.setScheme(scheme);
        url.setHost(host);
        url.setPort(proxy.port());
        if (!proxy.user().isEmpty())
            url.setUserName(proxy.user());
        if (!proxy.password().isEmpty())
            url.setPassword(proxy.password());
        return url.toString(QUrl::FullyEncoded);
    };

    switch (settings->proxyType()) {
    case 1: {
        const QNetworkProxyQuery query(targetUrl.isValid() ? targetUrl
                                                           : QUrl(QStringLiteral("http://example.com")));
        const QList<QNetworkProxy> proxies = QNetworkProxyFactory::systemProxyForQuery(query);
        for (const QNetworkProxy &proxy : proxies) {
            const QString proxyUrl = proxyToUrl(proxy);
            if (!proxyUrl.isEmpty())
                return proxyUrl;
        }
        return {};
    }
    case 2:
    case 3: {
        const QString host = settings->proxyHost().trimmed();
        const int port = settings->proxyPort();
        if (host.isEmpty() || port <= 0)
            return {};

        QNetworkProxy proxy(settings->proxyType() == 3
                                ? QNetworkProxy::Socks5Proxy
                                : QNetworkProxy::HttpProxy,
                            host,
                            static_cast<quint16>(port),
                            settings->proxyUsername(),
                            settings->proxyPassword());
        return proxyToUrl(proxy);
    }
    default:
        return {};
    }
}

void applyPerTorrentSpeedLimits(TorrentSessionManager *session, DownloadItem *item) {
    if (!session || !item || !item->isTorrent())
        return;
    session->setPerTorrentDownloadLimit(item->id(), item->perTorrentDownLimitKBps());
    session->setPerTorrentUploadLimit(item->id(), item->perTorrentUpLimitKBps());
}

bool isBareTorrentInfoHash(const QString &value) {
    const QString trimmed = value.trimmed();
    if (trimmed.size() != 40)
        return false;
    for (const QChar ch : trimmed) {
        if (!ch.isDigit() && (ch.toLower() < QLatin1Char('a') || ch.toLower() > QLatin1Char('f')))
            return false;
    }
    return true;
}

bool isLikelyPlaylistOrChannelUrl(const QString &urlStr) {
    const QUrl url = QUrl::fromUserInput(urlStr);
    const QString host = url.host().toLower();
    const QString path = url.path().toLower();
    const QString query = url.query().toLower();
    if (!(host.contains(QStringLiteral("youtube.com")) || host == QStringLiteral("youtu.be")))
        return false;
    return path.contains(QStringLiteral("/@"))
        || path.contains(QStringLiteral("/channel/"))
        || path.contains(QStringLiteral("/c/"))
        || path.contains(QStringLiteral("/user/"))
        || path.contains(QStringLiteral("/playlist"))
        || query.contains(QStringLiteral("list="));
}

QString normalizeTorrentSource(const QString &source) {
    const QString trimmed = source.trimmed();
    if (isBareTorrentInfoHash(trimmed))
        return QStringLiteral("magnet:?xt=urn:btih:%1").arg(trimmed.toLower());
    return trimmed;
}

QString extractDbVersionFromName(const QString &name) {
    static const QRegularExpression re(QStringLiteral("dbip-city-lite-(\\d{4}-\\d{2})\\.mmdb(?:\\.gz)?"),
                                       QRegularExpression::CaseInsensitiveOption);
    const QRegularExpressionMatch m = re.match(name);
    return m.hasMatch() ? m.captured(1) : QString();
}

bool extractGzipToFile(const QString &archivePath, const QString &targetPath, QString *errorText) {
#if defined(Q_OS_WIN)
    const QString inEscaped = QString(archivePath).replace('\'', QStringLiteral("''"));
    const QString outEscaped = QString(targetPath).replace('\'', QStringLiteral("''"));
    QString script = QStringLiteral(
        "$in='%1';"
        "$out='%2';"
        "$src=[System.IO.File]::OpenRead($in);"
        "try {"
        "  $gz=New-Object System.IO.Compression.GzipStream($src,[System.IO.Compression.CompressionMode]::Decompress);"
        "  try {"
        "    $dst=[System.IO.File]::Create($out);"
        "    try { $gz.CopyTo($dst) } finally { $dst.Dispose() }"
        "  } finally { $gz.Dispose() }"
        "} finally { $src.Dispose() }")
        .arg(inEscaped, outEscaped);

    QProcess ps;
    ps.setProgram(QStringLiteral("powershell"));
    ps.setArguments({ QStringLiteral("-NoProfile"),
                      QStringLiteral("-NonInteractive"),
                      QStringLiteral("-Command"),
                      script });
    ps.start();
    if (!ps.waitForFinished()) {
        if (errorText)
            *errorText = QStringLiteral("Failed to run PowerShell for gzip extraction.");
        return false;
    }
    if (ps.exitStatus() != QProcess::NormalExit || ps.exitCode() != 0) {
        const QString stderrText = QString::fromUtf8(ps.readAllStandardError()).trimmed();
        if (errorText)
            *errorText = stderrText.isEmpty()
                ? QStringLiteral("PowerShell gzip extraction failed.")
                : stderrText;
        return false;
    }
    return QFileInfo::exists(targetPath) && QFileInfo(targetPath).size() > 0;
#else
    QProcess gzip;
    gzip.setProgram(QStringLiteral("gzip"));
    gzip.setArguments({ QStringLiteral("-dc"), archivePath });
    gzip.start();
    if (!gzip.waitForFinished()) {
        if (errorText)
            *errorText = QStringLiteral("Failed to run gzip for extraction.");
        return false;
    }
    if (gzip.exitStatus() != QProcess::NormalExit || gzip.exitCode() != 0) {
        const QString stderrText = QString::fromUtf8(gzip.readAllStandardError()).trimmed();
        if (errorText)
            *errorText = stderrText.isEmpty()
                ? QStringLiteral("gzip extraction failed.")
                : stderrText;
        return false;
    }

    const QByteArray mmdbBytes = gzip.readAllStandardOutput();
    if (mmdbBytes.isEmpty()) {
        if (errorText)
            *errorText = QStringLiteral("The downloaded archive did not contain a valid MMDB file.");
        return false;
    }
    QSaveFile out(targetPath);
    if (!out.open(QIODevice::WriteOnly)) {
        if (errorText)
            *errorText = QStringLiteral("Cannot write %1: %2").arg(targetPath, out.errorString());
        return false;
    }
    if (out.write(mmdbBytes) != mmdbBytes.size()) {
        if (errorText)
            *errorText = QStringLiteral("Failed while writing %1.").arg(targetPath);
        out.cancelWriting();
        return false;
    }
    if (!out.commit()) {
        if (errorText)
            *errorText = QStringLiteral("Failed to finalize %1.").arg(targetPath);
        return false;
    }
    return true;
#endif
}

QByteArray fileSha256Hex(const QString &path, QString *errorText) {
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly)) {
        if (errorText)
            *errorText = QStringLiteral("Could not open %1 for hash verification: %2")
                             .arg(path, f.errorString());
        return {};
    }
    return QCryptographicHash::hash(f.readAll(), QCryptographicHash::Sha256).toHex();
}

bool verifyFileSha256(const QString &path, const QString &expectedHex, QString *errorText) {
    const QString normalized = expectedHex.trimmed().toLower();

    // SECURITY: CWE-347 — missing hash must be treated as a verification failure,
    // not a pass.  Returning true for an empty hash would let an attacker serve
    // a tampered update.json with no sha256 field and bypass integrity checks
    // entirely, allowing an unsigned/malicious installer to be launched silently.
    if (normalized.isEmpty()) {
        if (errorText)
            *errorText = QStringLiteral("SHA-256 hash is missing; cannot verify file integrity.");
        return false;
    }
    const QByteArray actual = fileSha256Hex(path, errorText);
    if (actual.isEmpty() && !normalized.isEmpty())
        return false;
    if (QString::fromLatin1(actual).toLower() == normalized)
        return true;
    if (errorText)
        *errorText = QStringLiteral("Hash verification failed for %1.").arg(QFileInfo(path).fileName());
    return false;
}

// Atomically install a single binary from sourcePath to targetPath.
// Uses a temp+backup swap so the target is never left in a partial state.
static bool installBinary(const QString &sourcePath, const QString &targetPath, QString *errorText) {
    const QString tempPath   = targetPath + QStringLiteral(".stellar-new");
    const QString backupPath = targetPath + QStringLiteral(".stellar-bak");
    QFile::remove(tempPath);
    if (!QFile::copy(sourcePath, tempPath)) {
        if (errorText)
            *errorText = QStringLiteral("Could not stage %1 to %2")
                             .arg(QFileInfo(targetPath).fileName(), tempPath);
        QFile::remove(tempPath);
        return false;
    }
    QFile::remove(backupPath);
    if (QFile::exists(targetPath))
        QFile::rename(targetPath, backupPath);
    if (!QFile::rename(tempPath, targetPath)) {
        QFile::remove(tempPath);
        if (QFile::exists(backupPath))
            QFile::rename(backupPath, targetPath); // restore
        if (errorText)
            *errorText = QStringLiteral("Could not install %1 to %2")
                             .arg(QFileInfo(targetPath).fileName(), targetPath);
        return false;
    }
    QFile::remove(backupPath);
#if !defined(Q_OS_WIN)
    QFile f(targetPath);
    f.setPermissions(
        QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner |
        QFileDevice::ReadGroup | QFileDevice::ExeGroup |
        QFileDevice::ReadOther | QFileDevice::ExeOther);
#endif
    return true;
}

// Find the best candidate for a binary named `name` in an extracted directory tree.
// Prefers the "bin/" subdirectory (canonical layout of ffmpeg-release archives).
static QString findBinaryInTree(const QString &root, const QString &name) {
    QString bestBin;
    QString fallback;
    QDirIterator it(root, QStringList{ name }, QDir::Files, QDirIterator::Subdirectories);
    while (it.hasNext()) {
        const QString candidate = it.next();
        const QFileInfo fi(candidate);
#if !defined(Q_OS_WIN)
        if (!fi.isExecutable()) { if (fallback.isEmpty()) fallback = candidate; continue; }
#endif
        if (fi.dir().dirName().toLower() == QLatin1String("bin")) {
            bestBin = candidate;
            break;
        }
        if (fallback.isEmpty()) fallback = candidate;
    }
    return bestBin.isEmpty() ? fallback : bestBin;
}

bool installFfmpegFromPayload(const QString &payloadPath, const QString &targetDir, QString *errorText) {
    const QString lowerName = QFileInfo(payloadPath).fileName().toLower();
#if defined(Q_OS_WIN)
    const QString ffmpegTarget  = QDir(targetDir).filePath(QStringLiteral("ffmpeg.exe"));
    const QString ffprobeTarget = QDir(targetDir).filePath(QStringLiteral("ffprobe.exe"));

    // Bare .exe — single ffmpeg binary (no ffprobe bundled)
    if (lowerName.endsWith(QStringLiteral(".exe")))
        return installBinary(payloadPath, ffmpegTarget, errorText);

    if (!lowerName.endsWith(QStringLiteral(".zip"))) {
        if (errorText)
            *errorText = QStringLiteral("Unsupported FFmpeg archive format: %1").arg(lowerName);
        return false;
    }

    QTemporaryDir tempDir;
    if (!tempDir.isValid()) {
        if (errorText)
            *errorText = QStringLiteral("Could not create temporary directory for FFmpeg extraction.");
        return false;
    }

    const QString inEscaped  = QString(payloadPath).replace('\'', QStringLiteral("''"));
    const QString outEscaped = QString(tempDir.path()).replace('\'', QStringLiteral("''"));
    QProcess ps;
    ps.setProgram(QStringLiteral("powershell"));
    ps.setArguments({ QStringLiteral("-NoProfile"), QStringLiteral("-NonInteractive"),
                      QStringLiteral("-Command"),
                      QStringLiteral("Expand-Archive -LiteralPath '%1' -DestinationPath '%2' -Force")
                          .arg(inEscaped, outEscaped) });
    ps.start();
    if (!ps.waitForFinished() || ps.exitStatus() != QProcess::NormalExit || ps.exitCode() != 0) {
        const QString err = QString::fromUtf8(ps.readAllStandardError()).trimmed();
        if (errorText) *errorText = err.isEmpty() ? QStringLiteral("Could not extract FFmpeg ZIP archive.") : err;
        return false;
    }

    const QString extractedFfmpeg  = findBinaryInTree(tempDir.path(), QStringLiteral("ffmpeg.exe"));
    const QString extractedFfprobe = findBinaryInTree(tempDir.path(), QStringLiteral("ffprobe.exe"));

    if (extractedFfmpeg.isEmpty()) {
        if (errorText) *errorText = QStringLiteral("FFmpeg archive did not contain ffmpeg.exe.");
        return false;
    }
    if (!installBinary(extractedFfmpeg, ffmpegTarget, errorText))
        return false;
    // ffprobe is optional — the archive might not include it (e.g., bare .exe builds).
    // Install it when present; don't fail when absent.
    if (!extractedFfprobe.isEmpty())
        installBinary(extractedFfprobe, ffprobeTarget, nullptr);

    return true;
#else
    const QString ffmpegTarget  = QDir(targetDir).filePath(QStringLiteral("ffmpeg"));
    const QString ffprobeTarget = QDir(targetDir).filePath(QStringLiteral("ffprobe"));

    if (lowerName.endsWith(QStringLiteral(".tar.xz"))
        || lowerName.endsWith(QStringLiteral(".txz"))
        || lowerName.endsWith(QStringLiteral(".tar.gz"))
        || lowerName.endsWith(QStringLiteral(".tgz"))) {
        QTemporaryDir tempDir;
        if (!tempDir.isValid()) {
            if (errorText)
                *errorText = QStringLiteral("Could not create temporary directory for FFmpeg extraction.");
            return false;
        }

        QProcess tar;
        tar.setProgram(QStringLiteral("tar"));
        tar.setArguments({ QStringLiteral("-xf"), payloadPath, QStringLiteral("-C"), tempDir.path() });
        tar.start();
        if (!tar.waitForFinished() || tar.exitStatus() != QProcess::NormalExit || tar.exitCode() != 0) {
            const QString err = QString::fromUtf8(tar.readAllStandardError()).trimmed();
            if (errorText) *errorText = err.isEmpty() ? QStringLiteral("Could not extract FFmpeg archive with tar.") : err;
            return false;
        }

        const QString extractedFfmpeg  = findBinaryInTree(tempDir.path(), QStringLiteral("ffmpeg"));
        const QString extractedFfprobe = findBinaryInTree(tempDir.path(), QStringLiteral("ffprobe"));

        if (extractedFfmpeg.isEmpty()) {
            if (errorText) *errorText = QStringLiteral("FFmpeg archive did not contain an ffmpeg binary.");
            return false;
        }
        if (!installBinary(extractedFfmpeg, ffmpegTarget, errorText))
            return false;
        if (!extractedFfprobe.isEmpty())
            installBinary(extractedFfprobe, ffprobeTarget, nullptr);

    } else if (lowerName.endsWith(QStringLiteral(".gz"))) {
        // Single-binary gzip — no ffprobe in this payload.
        if (!extractGzipToFile(payloadPath, ffmpegTarget, errorText))
            return false;
        QFile f(ffmpegTarget);
        f.setPermissions(
            QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner |
            QFileDevice::ReadGroup | QFileDevice::ExeGroup |
            QFileDevice::ReadOther | QFileDevice::ExeOther);
    } else {
        // Unknown format — treat as a bare ffmpeg binary.
        if (!installBinary(payloadPath, ffmpegTarget, errorText))
            return false;
    }

    return true;
#endif
}
}

void AppController::setWindowIcon(QObject *window, const QString &iconPath) {
    if (auto *qw = qobject_cast<QQuickWindow *>(window))
        qw->setIcon(QIcon(iconPath));
}

void AppController::handleIpcPayload(const QByteArray &json) {
    // Buffer payloads that arrive before QML has wired its signal Connections.
    // Without this, interceptedDownloadRequested (and showWindowRequested) fire
    // into the void and the download is silently lost.
    if (!m_qmlReady) {
        m_pendingIpcPayloads.append(json);
        return;
    }

    const QJsonObject obj = QJsonDocument::fromJson(json).object();
    if (obj.isEmpty()) return;
    const QString type = obj.value(QStringLiteral("type")).toString();
    if (type == QStringLiteral("download")) {
        const QString url      = obj.value(QStringLiteral("url")).toString();
        const QString name     = obj.value(QStringLiteral("filename")).toString();
        const QString cookies  = obj.value(QStringLiteral("cookies")).toString();
        const QString referrer = obj.value(QStringLiteral("referrer")).toString();
        const QString pageUrl  = obj.value(QStringLiteral("pageUrl")).toString();
        if (isTorrentUri(url)) {
            beginTorrentMetadataDownload(url, m_settings->defaultSavePath(),
                                         QString(), QString(), true);
        } else if (isLikelyYtdlpUrl(url)) {
            if (!cookies.isEmpty())  m_pendingCookies[url]   = cookies;
            if (!referrer.isEmpty()) m_pendingReferrers[url] = referrer;
            if (!pageUrl.isEmpty())  m_pendingPageUrls[url]  = pageUrl;
            emit interceptedDownloadRequested(url, name);
        } else if (m_settings->startImmediately()) {
            addUrl(url, {}, {}, {}, true, cookies, referrer, pageUrl);
        } else {
            if (!cookies.isEmpty())  m_pendingCookies[url]   = cookies;
            if (!referrer.isEmpty()) m_pendingReferrers[url] = referrer;
            if (!pageUrl.isEmpty())  m_pendingPageUrls[url]  = pageUrl;
            emit interceptedDownloadRequested(url, name);
        }
    } else if (type == QStringLiteral("focus")) {
        emit showWindowRequested();
    }
}

void AppController::setQmlReady() {
    if (m_qmlReady) return;
    m_qmlReady = true;
    // Drain any IPC payloads that arrived before QML was wired.
    const QList<QByteArray> pending = std::exchange(m_pendingIpcPayloads, {});
    for (const QByteArray &p : pending)
        handleIpcPayload(p);
}

void AppController::checkUrl(const QString &url, QJSValue callback) {
    QNetworkRequest request(QUrl::fromUserInput(url));
    const QString customUserAgent = m_settings ? m_settings->customUserAgent().trimmed() : QString();
    const QString resolvedUserAgent =
        (m_settings && m_settings->useCustomUserAgent() && !customUserAgent.isEmpty())
        ? customUserAgent
        : QStringLiteral("Stellar/%1").arg(QStringLiteral(STELLAR_VERSION));
    request.setHeader(QNetworkRequest::UserAgentHeader, resolvedUserAgent);
    QNetworkReply *reply = m_nam->head(request);
    connect(reply, &QNetworkReply::finished, this, [reply, callback]() {
        bool ok = (reply->error() == QNetworkReply::NoError);
        if (callback.isCallable()) {
            QJSValueList args;
            args << ok;
            callback.call(args);
        }
        reply->deleteLater();
    });
}

AppController::~AppController() {
    // Flush any pending debounced DB write before the object is destroyed.
    if (m_db) m_db->flush();
}

AppController::AppController(QObject *parent) : QObject(parent) {
    // ── 1. Components ────────────────────────────────────────────────────────────
    m_nam           = new QNetworkAccessManager(this);
    m_settings      = new AppSettings(this);
    DownloadItem::configureDateTimeFormat(
        m_settings->lastTryDateStyle(),
        m_settings->lastTryUse24Hour(),
        m_settings->lastTryShowSeconds());
    m_queue         = new DownloadQueue(this);
    m_downloadModel = new DownloadTableModel(this);
    m_categoryModel = new CategoryModel(this);
    m_grabberProjectModel = new GrabberProjectModel(this);
    m_grabberResultModel = new GrabberResultModel(this);
    m_grabberCrawler = new GrabberCrawler(m_nam, this);
    m_nativeHost    = new NativeMessagingHost(this);
    m_tray          = new SystemTrayIcon(this);
    m_db            = new DownloadDatabase(this);
    m_queueDb       = new QueueDatabase(this);
    m_queueModel    = new QueueModel(this);
    m_ytdlpManager  = new YtdlpManager(m_nam, this);
    m_torrentSearchManager = new TorrentSearchManager(m_nam, this);
    m_torrentSession = new TorrentSessionManager(this);
    refreshIpToCityDbInfo();

    // Public IP is fetched after applyProxy() so the request is routed through
    // the configured proxy. fetchPublicIp() is also called from applyProxy() so
    // the map location updates whenever the user switches proxies.

    // ── Proxy ────────────────────────────────────────────────────────────────────
    // Apply once on startup, then re-apply whenever any proxy setting changes.
    // QNetworkProxy::setApplicationProxy is process-wide — every QNetworkAccessManager
    // that does not have its own explicit proxy set inherits it automatically,
    // which covers m_nam (downloads, updates, grabber) and the yt-dlp probe NAM.
    applyProxy();
    auto reconnectProxy = [this]() { applyProxy(); };
    connect(m_settings, &AppSettings::proxyTypeChanged,     this, reconnectProxy);
    connect(m_settings, &AppSettings::proxyHostChanged,     this, reconnectProxy);
    connect(m_settings, &AppSettings::proxyPortChanged,     this, reconnectProxy);
    connect(m_settings, &AppSettings::proxyUsernameChanged, this, reconnectProxy);
    connect(m_settings, &AppSettings::proxyPasswordChanged, this, reconnectProxy);

    m_saveTimer     = new QTimer(this);
    m_saveTimer->setSingleShot(true);
    m_saveTimer->setInterval(500);
    connect(m_saveTimer, &QTimer::timeout, this, &AppController::flushDirty);
    m_recentErrorTimer = new QTimer(this);
    m_recentErrorTimer->setInterval(30000);
    connect(m_recentErrorTimer, &QTimer::timeout, this, &AppController::pruneRecentErrorDownloads);
    m_recentErrorTimer->start();
    m_grabberPersistTimer = new QTimer(this);
    m_grabberPersistTimer->setSingleShot(true);
    m_grabberPersistTimer->setInterval(400);
    connect(m_grabberPersistTimer, &QTimer::timeout, this, &AppController::persistActiveGrabberResults);

    // Forward the queue's active-count change so the QML property App.activeDownloads
    // emits its NOTIFY signal and toolbar/statusbar bindings re-evaluate reactively.
    // Without this connection, activeDownloadsChanged() was declared but never emitted,
    // so "Stop All" never grayed out when all downloads finished.
    connect(m_queue, &DownloadQueue::activeCountChanged,
            this,    &AppController::activeDownloadsChanged);

    // Update tray tooltip every 2 seconds with live download stats.
    // Done in C++ rather than QML so the tray always reflects current state
    // even when no QML binding has re-evaluated recently.
    m_tooltipTimer = new QTimer(this);
    m_tooltipTimer->setInterval(2000);
    connect(m_tooltipTimer, &QTimer::timeout, this, [this] {
        qint64 totalDownSpeed = 0;
        qint64 totalUpSpeed = 0;
        for (DownloadItem *item : m_downloadModel->allItems()) {
            totalDownSpeed += item->speed();
            if (item->isTorrent())
                totalUpSpeed += item->torrentUploadSpeed();
        }

        const int total  = m_downloadModel->allItems().size();
        const int active = m_queue->activeCount();

        QString tip = QStringLiteral("Stellar Download Manager v") + appVersion();
        if (active > 0) {
            auto formatSpeedLine = [](qint64 bytesPerSecond) {
                if (bytesPerSecond >= 1024LL * 1024)
                    return QStringLiteral("%1 MB/s").arg(double(bytesPerSecond) / (1024.0 * 1024.0), 0, 'f', 1);
                return QStringLiteral("%1 KB/s").arg(double(bytesPerSecond) / 1024.0, 0, 'f', 0);
            };
            tip += QStringLiteral("\nDown: %1").arg(formatSpeedLine(totalDownSpeed));
            tip += QStringLiteral("\nUp: %1").arg(formatSpeedLine(totalUpSpeed));
        }
        tip += QStringLiteral("\nDownloads: %1   Running: %2").arg(total).arg(active);
        if (m_tray) m_tray->setToolTip(tip);
    });
    m_tooltipTimer->start();

    m_torrentSpeedHistoryTimer = new QTimer(this);
    m_torrentSpeedHistoryTimer->setInterval(1000);
    connect(m_torrentSpeedHistoryTimer, &QTimer::timeout, this, [this]() {
        const qint64 nowMs = QDateTime::currentMSecsSinceEpoch();
        const qint64 cutoff = nowMs - kTorrentSpeedHistoryRetentionMs;
        QSet<QString> activeIds;
        const auto items = m_downloadModel->allItems();
        for (DownloadItem *item : items) {
            if (!item || !item->isTorrent())
                continue;
            activeIds.insert(item->id());
            auto &series = m_torrentSpeedHistory[item->id()];
            const int down = static_cast<int>(std::max<qint64>(0, item->speed()));
            const int up = static_cast<int>(std::max<qint64>(0, item->torrentUploadSpeed()));
            const bool shouldAppend = series.isEmpty()
                || series.last().downBps != down
                || series.last().upBps != up
                || (nowMs - series.last().timestampMs) >= 10000; // heartbeat every 10s
            if (shouldAppend)
                series.append({ nowMs, down, up });
            while (!series.isEmpty() && series.first().timestampMs < cutoff)
                series.removeFirst();
        }
        for (auto it = m_torrentSpeedHistory.begin(); it != m_torrentSpeedHistory.end();) {
            if (!activeIds.contains(it.key())) {
                it = m_torrentSpeedHistory.erase(it);
            } else {
                ++it;
            }
        }
    });
    m_torrentSpeedHistoryTimer->start();

    // ── 2. IPC Server ──────────────────────────────────────────────────────────
    m_ipcServer = new QLocalServer(this);
    if (!m_ipcServer->listen(QStringLiteral("StellarDownloadManager"))) {
        qDebug() << "[IPC] FAILED to listen on StellarDownloadManager";
    }

    connect(m_ipcServer, &QLocalServer::newConnection, this, [this]() {
        QLocalSocket *sock = m_ipcServer->nextPendingConnection();
        if (!sock) return;
        auto payload = std::make_shared<QByteArray>();
        connect(sock, &QLocalSocket::readyRead, this, [sock, payload]() {
            payload->append(sock->readAll());
        });
        // Also drain in disconnected: when the native host writes and immediately
        // exits, disconnected can fire before readyRead on Windows. QLocalSocket
        // is a byte stream, so readyRead can also surface partial JSON chunks.
        // Accumulate the payload for the lifetime of the connection and parse it
        // once the sender disconnects so we never consume and lose a partial
        // message during cold-start delivery.
        connect(sock, &QLocalSocket::disconnected, this, [this, sock, payload]() {
            if (sock->bytesAvailable() > 0)
                payload->append(sock->readAll());
            if (!payload->isEmpty())
                handleIpcPayload(*payload);
            sock->deleteLater();
        });
    });

    // ── 3. Data & Setup ────────────────────────────────────────────────────────
    if (m_queueDb->open()) {
        const auto queues = m_queueDb->loadAll(this);
        for (Queue *q : queues) m_queueModel->addQueue(q);
    }
    
    if (m_queueModel->queueById("main-download") == nullptr) {
        Queue *mainQueue = new Queue("main-download", this);
        mainQueue->setName("Main download queue");
        mainQueue->setIsDownloadQueue(true);
        m_queueModel->addQueue(mainQueue);
        m_queueDb->save(mainQueue);
    }
    if (m_queueModel->queueById("main-sync") == nullptr) {
        Queue *syncQueue = new Queue("main-sync", this);
        syncQueue->setName("Synchronization queue");
        syncQueue->setIsDownloadQueue(false);
        m_queueModel->addQueue(syncQueue);
        m_queueDb->save(syncQueue);
    }
    if (m_queueModel->queueById("download-limits") == nullptr) {
        Queue *limitsQueue = new Queue("download-limits", this);
        limitsQueue->setName("Download Limits");
        limitsQueue->setIsDownloadQueue(false);
        m_queueModel->addQueue(limitsQueue);
        m_queueDb->save(limitsQueue);
    }

    // ── 4. Connections ──────────────────────────────────────────────────────────
    m_queue->setNam(m_nam);
    m_queue->setSpeedLimitKBps(m_settings->globalSpeedLimitKBps());
    m_queue->setCustomUserAgentEnabled(m_settings->useCustomUserAgent());
    m_queue->setCustomUserAgent(m_settings->customUserAgent());
    m_queue->setTemporaryDirectory(m_settings->temporaryDirectory());
    m_queue->setMaxConnectionsPerHost(m_settings->perHostConnectionLimit());
    m_queue->setCanStartPredicate([this](DownloadItem *item) {
        return canStartDownloadItem(item);
    });
    connect(m_settings, &AppSettings::globalSpeedLimitKBpsChanged, this, [this]() {
        m_queue->setSpeedLimitKBps(m_settings->globalSpeedLimitKBps());
    });
    auto refreshDateFormatting = [this]() {
        DownloadItem::configureDateTimeFormat(
            m_settings->lastTryDateStyle(),
            m_settings->lastTryUse24Hour(),
            m_settings->lastTryShowSeconds());
        for (DownloadItem *item : m_downloadModel->allItems()) {
            if (item)
                item->refreshDateStrings();
        }
    };
    connect(m_settings, &AppSettings::lastTryDateStyleChanged, this, refreshDateFormatting);
    connect(m_settings, &AppSettings::lastTryUse24HourChanged, this, refreshDateFormatting);
    connect(m_settings, &AppSettings::lastTryShowSecondsChanged, this, refreshDateFormatting);
    connect(m_settings, &AppSettings::autoCheckUpdatesChanged, this, [this]() {
        if (!m_settings->autoCheckUpdates()) {
            if (m_updateAvailable) {
                m_updateAvailable = false;
                emit updateAvailableChanged();
            }
            if (!m_updateStatusText.isEmpty()) {
                m_updateStatusText.clear();
                emit updateStatusTextChanged();
            }
        }
    });
    connect(m_settings, &AppSettings::useCustomUserAgentChanged, this, [this]() {
        m_queue->setCustomUserAgentEnabled(m_settings->useCustomUserAgent());
    });
    connect(m_settings, &AppSettings::customUserAgentChanged, this, [this]() {
        m_queue->setCustomUserAgent(m_settings->customUserAgent());
    });
    connect(m_settings, &AppSettings::temporaryDirectoryChanged, this, [this]() {
        m_queue->setTemporaryDirectory(m_settings->temporaryDirectory());
        cleanupTemporaryDirectory();
    });
    connect(m_settings, &AppSettings::perHostConnectionLimitChanged, this, [this]() {
        m_queue->setMaxConnectionsPerHost(m_settings->perHostConnectionLimit());
    });
    m_torrentSession->applySettings(m_settings);
    connect(m_settings, &AppSettings::torrentSettingsChanged, this, [this]() {
        m_torrentSession->applySettings(m_settings);
    });
    connect(m_settings, &AppSettings::torrentSettingsChanged, this, &AppController::torrentBindingStatusTextChanged);
    connect(m_settings, &AppSettings::globalSpeedLimitKBpsChanged, this, [this]() {
        m_torrentSession->applySettings(m_settings);
    });
    connect(m_settings, &AppSettings::globalUploadLimitKBpsChanged, this, [this]() {
        m_torrentSession->applySettings(m_settings);
    });
    connect(m_settings, &AppSettings::customUserAgentChanged, this, [this]() {
        m_torrentSession->applySettings(m_settings);
    });
    connect(m_torrentSession, &TorrentSessionManager::torrentShareLimitReached, this, [this](const QString &id, int action) {
        if (action == 0 || action == 1) {
            pauseDownload(id);
        } else if (action == 2) {
            deleteDownload(id, 0);
        } else if (action == 3) {
            deleteDownload(id, 1);
        }
    });
    connect(m_torrentSession, &TorrentSessionManager::bannedPeersChanged,
            this, &AppController::torrentBannedPeersChanged);
    connect(m_torrentSession, &TorrentSessionManager::torrentFinished, this, [this](const QString &id) {
        auto *item = m_downloadModel->itemById(id);
        if (!item)
            return;
        const bool isPaused = item->statusEnum() == DownloadItem::Status::Paused;
        if (!isPaused)
            item->setStatus(DownloadItem::Status::Seeding);
        scheduleSave(id);
        // Suppress startup noise: restored/stopped torrents can emit a finished
        // alert as session state rehydrates, but that should not trigger a
        // "Download Complete" popup. m_restoredSeedingIds covers the window
        // after m_restoring is cleared but before libtorrent has flushed all
        // its deferred alerts for already-complete torrents.
        const bool isFreshCompletion = !isPaused
                                       && !m_restoring
                                       && !m_restoredSeedingIds.contains(id);
        m_restoredSeedingIds.remove(id); // consume — only suppress once per ID
        if (isFreshCompletion)
            emit downloadCompleted(item);
        emit activeDownloadsChanged();
    });
    connect(m_torrentSession, &TorrentSessionManager::torrentErrored, this, [this](const QString &id, const QString &reason) {
        auto *item = m_downloadModel->itemById(id);
        if (!item)
            return;
        item->setStatus(DownloadItem::Status::Error);
        item->setErrorString(reason);
        scheduleSave(id);
        emit activeDownloadsChanged();
    });

    // ── yt-dlp Manager wiring ─────────────────────────────────────────────────
    // Sync custom binary path from settings on startup and when it changes.
    m_ytdlpManager->setCustomPath(m_settings->ytdlpCustomBinaryPath());
    connect(m_settings, &AppSettings::ytdlpCustomBinaryPathChanged, this, [this]() {
        m_ytdlpManager->setCustomPath(m_settings->ytdlpCustomBinaryPath());
    });
    // Sync custom JS runtime path from settings on startup and when it changes.
    m_ytdlpManager->setCustomJsRuntimePath(m_settings->ytdlpJsRuntimePath());
    connect(m_settings, &AppSettings::ytdlpJsRuntimePathChanged, this, [this]() {
        m_ytdlpManager->setCustomJsRuntimePath(m_settings->ytdlpJsRuntimePath());
    });
    // Check yt-dlp availability and optionally self-update on launch.
    connect(m_ytdlpManager, &YtdlpManager::checkComplete, this, [this]() {
        if (m_settings->ytdlpAutoUpdate() && m_ytdlpManager->available())
            m_ytdlpManager->selfUpdate();
    });
    m_ytdlpManager->checkAvailability();

    // ── Clipboard URL monitoring ───────────────────────────────────────────────
    // When enabled, watch the system clipboard for URLs whose file extensions
    // match the user's monitored extension list (same list as browser interception).
    // We keep track of the last URL we already emitted so repeated clipboard
    // events for the same content don't open multiple dialogs.
    connect(QGuiApplication::clipboard(), &QClipboard::dataChanged, this, [this]() {
        // Skip if the feature is disabled
        if (!m_settings->clipboardMonitorEnabled()) return;

        const QString text = QGuiApplication::clipboard()->text().trimmed();
        if (text.isEmpty()) return;
        // Avoid re-firing for the same clipboard content
        if (text == m_lastClipboardUrl) return;

        // Only react to valid http/https URLs
        QUrl url(text);
        if (!url.isValid() || (url.scheme() != QLatin1String("http") && url.scheme() != QLatin1String("https")))
            return;

        // yt-dlp-compatible sites have no file extension in the URL — check them first.
        // If the URL looks like a supported video site, emit the dedicated signal so
        // QML can open the yt-dlp format picker instead of the regular Add URL dialog.
        if (isLikelyYtdlpUrl(text)) {
            m_lastClipboardUrl = text;
            emit ytdlpClipboardUrlDetected(text);
            return;
        }

        // Extract the file extension from the URL path (ignore query / fragment)
        const QString path = url.path();
        const int dotIdx = path.lastIndexOf('.');
        if (dotIdx < 0) return;
        const QString ext = path.mid(dotIdx + 1).toLower();
        if (ext.isEmpty()) return;

        // Check against the monitored extensions list (same as browser integration)
        if (!m_settings->monitoredExtensions().contains(ext, Qt::CaseInsensitive)) return;

        m_lastClipboardUrl = text;
        emit clipboardUrlDetected(text);
    });
    // Grabber status is surfaced as simple properties so the wizard can stay
    // declarative and only react to high-level crawl lifecycle changes.
    connect(m_grabberCrawler, &GrabberCrawler::progressChanged, this, [this](const QString &statusText) {
        if (m_grabberStatusText == statusText)
            return;
        m_grabberStatusText = statusText;
        emit grabberStatusTextChanged();
        static const QRegularExpression pagesRe(QStringLiteral(R"(across\s+(\d+)\s+pages)"), QRegularExpression::CaseInsensitiveOption);
        static const QRegularExpression foundRe(QStringLiteral(R"(Found\s+(\d+)\s+files)"), QRegularExpression::CaseInsensitiveOption);
        const QRegularExpressionMatch pagesMatch = pagesRe.match(statusText);
        if (pagesMatch.hasMatch()) {
            m_grabberPagesProcessed = pagesMatch.captured(1).toInt();
            m_grabberAdvancedPagesProcessed = m_grabberPagesProcessed;
        }
        const QRegularExpressionMatch foundMatch = foundRe.match(statusText);
        if (foundMatch.hasMatch())
            m_grabberMatchedFiles = foundMatch.captured(1).toInt();
    });
    connect(m_grabberCrawler, &GrabberCrawler::resultsFound, this,
            [this](const QList<GrabberResult> &results) {
        m_grabberResultModel->appendResults(results);
        m_grabberMatchedFiles = m_grabberResultModel->rowCount();
        scheduleGrabberResultsPersist();
    });
    connect(m_grabberCrawler, &GrabberCrawler::resultMetadataUpdated, this, [this](const QString &url, qint64 sizeBytes) {
        m_grabberResultModel->updateResultSize(url, sizeBytes);
        scheduleGrabberResultsPersist();
    });
    connect(m_grabberCrawler, &GrabberCrawler::finished, this, [this](const QVariantList &results) {
        m_grabberBusy = false;
        emit grabberBusyChanged();
        m_grabberResultModel->setResults(results);
        m_grabberMatchedFiles = results.size();
        if (!m_activeGrabberProjectId.isEmpty()) {
            QVariantMap project = m_grabberProjectModel->projectDataById(m_activeGrabberProjectId);
            if (!project.isEmpty()) {
                project[QStringLiteral("lastResults")] = results;
                project[QStringLiteral("lastResultCount")] = results.size();
                project[QStringLiteral("lastExploreFinishedAt")] = QDateTime::currentDateTime().toString(Qt::ISODate);
                m_grabberProjectModel->upsertProject(project);
            }
            m_grabberProjectModel->updateProjectRunState(
                m_activeGrabberProjectId,
                QStringLiteral("Found %1 files").arg(results.size()),
                results.size());
        }
        emit grabberExploreFinished(m_activeGrabberProjectId);
    });
    connect(m_grabberCrawler, &GrabberCrawler::failed, this, [this](const QString &message) {
        m_grabberBusy = false;
        emit grabberBusyChanged();
        m_grabberStatusText = message;
        emit grabberStatusTextChanged();
        emit grabberError(message);
    });
    connect(m_queue, &DownloadQueue::itemAdded, this, [this](DownloadItem *item) {
        m_downloadModel->addItem(item);
        if (!m_restoring) { m_db->save(item); watchItem(item); }
    });
    connect(m_queue, &DownloadQueue::itemRemoved, this, [this](const QString &id) {
        // Check status before removal so we can keep the count accurate
        auto *item = m_downloadModel->itemById(id);
        if (item && item->statusEnum() == DownloadItem::Status::Completed) {
            m_completedCount--;
            emit completedDownloadsChanged();
        }
        m_downloadModel->removeItem(id);
        if (m_recentErrorDownloads.remove(id) > 0)
            emit recentErrorDownloadsChanged();
        m_dirtyIds.remove(id);
        m_lastProgressPersistBytes.remove(id);
        m_lastProgressPersistAt.remove(id);
        m_db->remove(id);
    });
    connect(m_queue, &DownloadQueue::itemCompleted, this, [this](DownloadItem *item) {
        const bool isIpToCityUpdateItem = (item && item->id() == m_pendingIpToCityDbDownloadId);
        const bool isFfmpegUpdateItem = (item && item->id() == m_pendingFfmpegDownloadId);
        m_db->save(item);
        m_dirtyIds.remove(item->id());
        m_queueRetryCounts.remove(item->id());
        m_completedCount++;
        emit completedDownloadsChanged();
        if (item && !item->queueId().isEmpty()) {
            recordQueueTransferSample(item->queueId(), item->doneBytes());
            enforceQueueDownloadLimits(item->queueId());
            Queue *queue = m_queueModel ? m_queueModel->queueById(item->queueId()) : nullptr;
            if (queue) {
                bool queueFinished = true;
                for (DownloadItem *candidate : m_queue->items()) {
                    if (!candidate || candidate->queueId() != item->queueId())
                        continue;
                    if (candidate->statusEnum() == DownloadItem::Status::Queued
                        || candidate->statusEnum() == DownloadItem::Status::Downloading
                        || candidate->statusEnum() == DownloadItem::Status::Assembling) {
                        queueFinished = false;
                        break;
                    }
                }
                if (queueFinished) {
                    if (queue->openFileWhenDone() && !queue->openFilePath().isEmpty())
                        QDesktopServices::openUrl(QUrl::fromLocalFile(queue->openFilePath()));
                    if (queue->turnOffComputerWhenDone()) {
#if defined(Q_OS_WIN)
                        if (queue->forceProcessesToTerminate())
                            QProcess::startDetached(QStringLiteral("shutdown"),
                                                    { QStringLiteral("/s"), QStringLiteral("/f"), QStringLiteral("/t"), QStringLiteral("0") });
                        else
                            shutdownComputer();
#else
                        shutdownComputer();
#endif
                    }
                    if (queue->exitIDMWhenDone())
                        QCoreApplication::quit();
                }
            }
        }
        if (!isIpToCityUpdateItem
            && !isFfmpegUpdateItem
            && !m_pendingFileInfoDownloads.contains(item->id())
            && m_settings->showCompletionNotification()
            && m_tray
            && !isGrabberProjectId(item->category())) {
            const QString name = item->filename().isEmpty()
                ? item->url().fileName()
                : item->filename();
            m_tray->showNotification(QStringLiteral("Download Complete"), name);
        }
        if (!isIpToCityUpdateItem
            && !isFfmpegUpdateItem
            && !m_pendingFileInfoDownloads.contains(item->id()))
            emit downloadCompleted(item);

        if (item && item->id() == m_pendingUpdateDownloadId) {
            const QString installerPath = item->savePath() + QStringLiteral("/") + item->filename();
            QFile installerFile(installerPath);
            if (!installerFile.open(QIODevice::ReadOnly)) {
                emit updateError(QStringLiteral("Stellar downloaded the update, but could not read the installer file."));
            } else {
                const QByteArray actualHash = QCryptographicHash::hash(installerFile.readAll(), QCryptographicHash::Sha256).toHex();
                installerFile.close();

                // SECURITY: CWE-347 — enforce that a non-empty SHA-256 was supplied
                // by the update server before launching the installer.  An empty hash
                // must be treated as a failure (not a pass) so that a tampered
                // update.json with a missing sha256 field cannot silently bypass
                // integrity verification and execute an unsigned binary.
                // verifyFileSha256() now also rejects empty hashes, but this call
                // site is the gate before QProcess::startDetached so we enforce it
                // explicitly here as a defence-in-depth measure.
                const bool hashProvided = !m_pendingUpdateSha256.trimmed().isEmpty();
                const bool hashMatches  = hashProvided &&
                    actualHash.compare(m_pendingUpdateSha256.trimmed().toUtf8(), Qt::CaseInsensitive) == 0;
                if (!hashProvided || !hashMatches) {
                    emit updateError(hashProvided
                        ? QStringLiteral("The downloaded update installer failed hash verification.")
                        : QStringLiteral("The update server did not provide a SHA-256 hash; refusing to launch the installer."));
                } else {
#if defined(Q_OS_WIN)
                    const QStringList args{
                        QStringLiteral("/VERYSILENT"),
                        QStringLiteral("/SUPPRESSMSGBOXES"),
                        QStringLiteral("/NOCANCEL"),
                        QStringLiteral("/CLOSEAPPLICATIONS"),
                        QStringLiteral("/FORCECLOSEAPPLICATIONS"),
                        QStringLiteral("/RESTARTAPPLICATIONS")
                    };
                    if (QProcess::startDetached(installerPath, args))
                        QCoreApplication::quit();
                    else
                        emit updateError(QStringLiteral("Stellar downloaded the update, but could not launch the installer."));
#else
                    m_updateStatusText = QStringLiteral("Update package downloaded: %1").arg(installerPath);
                    emit updateStatusTextChanged();
#endif
                }
            }
            m_pendingUpdateDownloadId.clear();
            m_pendingUpdateInstallerPath.clear();
            m_pendingUpdateSha256.clear();
        }
        if (item && item->id() == m_pendingIpToCityDbDownloadId) {
            const QString dbUpdateId = item->id();
            const QString archivePath = item->savePath() + QStringLiteral("/") + item->filename();
            const QString targetDir = writableRuntimeDataDir();
            QDir().mkpath(targetDir);
            if (m_torrentSession)
                m_torrentSession->releaseGeoDatabaseForUpdate();

            const QString sourceName = item->filename();
            QString targetName = sourceName;
            if (targetName.endsWith(QStringLiteral(".gz"), Qt::CaseInsensitive))
                targetName.chop(3);
            if (targetName.isEmpty())
                targetName = QStringLiteral("dbip-city-lite-2026-04.mmdb");
            const QString targetPath = targetDir + QStringLiteral("/") + targetName;

            bool installOk = false;
            QString failureReason;
            if (sourceName.endsWith(QStringLiteral(".gz"), Qt::CaseInsensitive)) {
                installOk = extractGzipToFile(archivePath, targetPath, &failureReason);
            } else {
                QFile::remove(targetPath);
                installOk = QFile::copy(archivePath, targetPath);
                if (!installOk)
                    failureReason = QStringLiteral("Could not install %1 to %2").arg(sourceName, targetPath);
            }

            m_pendingIpToCityDbDownloadId.clear();
            m_ipToCityDbUpdating = false;
            if (installOk) {
                m_ipToCityDbUpdateStatus = QStringLiteral("IP-to-city database updated successfully.");
                refreshIpToCityDbInfo();
            } else {
                m_ipToCityDbUpdateStatus = failureReason.isEmpty()
                    ? QStringLiteral("IP-to-city database update failed.")
                    : failureReason;
                refreshIpToCityDbInfo();
            }
            QFile::remove(archivePath);
            emit ipToCityDbUpdateStateChanged();
            QTimer::singleShot(0, this, [this, dbUpdateId]() {
                if (!m_downloadModel->itemById(dbUpdateId))
                    return;
                deleteDownloads(QStringList{dbUpdateId}, 0);
            });
        }
        if (item && item->id() == m_pendingFfmpegDownloadId) {
            const QString ffmpegUpdateId = item->id();
            const QString payloadPath = item->savePath() + QStringLiteral("/") + item->filename();
            const QString installDir = writableRuntimeToolsDir();

            QString failureReason;
            const bool installOk = installFfmpegFromPayload(payloadPath, installDir, &failureReason);

            m_pendingFfmpegDownloadId.clear();
            m_ffmpegUpdating = false;
            if (installOk) {
                m_ffmpegUpdateStatus = QStringLiteral("FFmpeg updated successfully.");
                if (m_ytdlpManager)
                    m_ytdlpManager->checkAvailability();
            } else {
                m_ffmpegUpdateStatus = failureReason.isEmpty()
                    ? QStringLiteral("FFmpeg update failed.")
                    : failureReason;
            }
            QFile::remove(payloadPath);
            emit ffmpegUpdateStateChanged();
            QTimer::singleShot(0, this, [this, ffmpegUpdateId]() {
                if (!m_downloadModel->itemById(ffmpegUpdateId))
                    return;
                deleteDownloads(QStringList{ffmpegUpdateId}, 0);
            });
        }
    });
    connect(m_queue, &DownloadQueue::itemFailed, this, [this](DownloadItem *item, const QString &reason) {
        if (!item)
            return;
        if (item->id() == m_pendingIpToCityDbDownloadId) {
            const QString archivePath = item->savePath() + QStringLiteral("/") + item->filename();
            m_pendingIpToCityDbDownloadId.clear();
            m_ipToCityDbUpdating = false;
            m_ipToCityDbUpdateStatus = reason.isEmpty()
                ? QStringLiteral("IP-to-city database update download failed.")
                : QStringLiteral("IP-to-city database update download failed: %1").arg(reason);
            QFile::remove(archivePath);
            emit ipToCityDbUpdateStateChanged();
        }
        if (item->id() == m_pendingFfmpegDownloadId) {
            const QString payloadPath = item->savePath() + QStringLiteral("/") + item->filename();
            m_pendingFfmpegDownloadId.clear();
            m_ffmpegUpdating = false;
            m_ffmpegUpdateStatus = reason.isEmpty()
                ? QStringLiteral("FFmpeg update download failed.")
                : QStringLiteral("FFmpeg update download failed: %1").arg(reason);
            QFile::remove(payloadPath);
            emit ffmpegUpdateStateChanged();
        }
        m_recentErrorDownloads[item->id()] = QDateTime::currentDateTime();
        emit recentErrorDownloadsChanged();
        m_db->save(item);
        m_dirtyIds.remove(item->id());
        Queue *queue = (!item->queueId().isEmpty() && m_queueModel)
            ? m_queueModel->queueById(item->queueId())
            : nullptr;
        // Determine retry limit: queue-specific if available, else global setting.
        int maxRetries = 0;
        if (queue && queue->hasMaxRetries())
            maxRetries = queue->maxRetries();
        else if (m_settings->maxRetries() > 0)
            maxRetries = m_settings->maxRetries();

        const int retries = m_queueRetryCounts.value(item->id(), 0);
        if (maxRetries > 0 && retries < maxRetries) {
            m_queueRetryCounts[item->id()] = retries + 1;
            // Exponential backoff: 2s, 4s, 8s, 16s, ... capped at 60s
            int delayMs = (std::min)(2000 * (1 << retries), 60000);
            QTimer::singleShot(delayMs, this, [this, id = item->id()]() {
                DownloadItem *retryItem = m_downloadModel->itemById(id);
                if (!retryItem || retryItem->statusEnum() != DownloadItem::Status::Error)
                    return;
                retryItem->setStatus(DownloadItem::Status::Queued);
                retryItem->setErrorString({});
                scheduleSave(id);
                m_queue->scheduleNext();
            });
            return;
        }
        m_queueRetryCounts.remove(item->id());
        if (!item->queueId().isEmpty() && item->doneBytes() > 0) {
            recordQueueTransferSample(item->queueId(), item->doneBytes());
            enforceQueueDownloadLimits(item->queueId());
        }
        if (!m_pendingFileInfoDownloads.contains(item->id())
            && m_settings->showErrorNotification()
            && m_tray) {
            const QString name = item->filename().isEmpty()
                ? item->url().fileName()
                : item->filename();
            const QString details = reason.isEmpty() ? QStringLiteral("The download failed.") : reason;
            m_tray->showNotification(QStringLiteral("Download Failed"), QStringLiteral("%1\n%2").arg(name, details));
        }
    });
    connect(m_nativeHost, &NativeMessagingHost::downloadRequested, this, [this](const QString &url, const QString &filename, const QString &referrer, const QString &cookies, int modifierKey) {
        Q_UNUSED(filename);
        // Skip interception if bypass modifier key is active and matches user's configured key
        if (modifierKey > 0 && modifierKey == m_settings->bypassInterceptKey()) {
            return;  // Let the browser download the file
        }
        addUrl(url, {}, {}, {}, true, cookies, referrer);
    });
    connect(m_tray, &SystemTrayIcon::showRequested,        this, &AppController::showWindowRequested);
    connect(m_tray, &SystemTrayIcon::quitRequested,        &QCoreApplication::quit);
    connect(m_tray, &SystemTrayIcon::addUrlRequested,      this, [this]() { emit showWindowRequested(); });
    connect(m_tray, &SystemTrayIcon::githubRequested,       this, &AppController::trayGithubRequested);
    connect(m_tray, &SystemTrayIcon::aboutRequested,        this, &AppController::trayAboutRequested);
    connect(m_tray, &SystemTrayIcon::speedLimiterRequested, this, &AppController::traySpeedLimiterRequested);
    connect(m_tray, &SystemTrayIcon::contextMenuRequested,  this, &AppController::contextMenuRequested);
    
    connect(QCoreApplication::instance(), &QCoreApplication::aboutToQuit, this, [this]() {
        const auto items = m_downloadModel->allItems();
        for (DownloadItem *item : items) {
            if (item && item->isTorrent())
                m_torrentSession->saveResumeData(item->id());
        }
        flushDirty();
    });
    if (m_settings->autoCheckUpdates()) {
        QTimer::singleShot(2500, this, [this]() {
            checkForUpdates(false);
        });
    }

    // ── 5. Finalization ──────────────────────────────────────────────────────────
    QString err = registerNativeHost();
    if (err.isEmpty()) qDebug() << "[NativeHost] registered OK";
    else qDebug() << "[NativeHost] registration FAILED:" << err;

    m_tray->show();

    if (m_db->open()) {
        m_restoring = true;
        const auto items = m_db->loadAll();
        for (int i = 0; i < items.size(); ++i) {
            QTimer::singleShot(i * 16, this, [this, item = items.at(i)]() {
                m_queue->enqueueRestored(item);
                watchItem(item);
                if (item->isTorrent()) {
                    // Record torrents that are already seeding/complete so that
                    // libtorrent's async torrent_finished_alert — which can arrive
                    // after m_restoring is cleared — doesn't trigger a spurious
                    // "Download Complete" popup on startup.
                    const auto s = item->statusEnum();
                    if (s == DownloadItem::Status::Seeding
                            || s == DownloadItem::Status::Completed)
                        m_restoredSeedingIds.insert(item->id());
                    m_torrentSession->restoreTorrent(item);
                    applyPerTorrentSpeedLimits(m_torrentSession, item);
                }
            });
        }
        const int itemCount = static_cast<int>(items.size());
        QTimer::singleShot(itemCount * 16 + 50, this, [this, itemCount]() {
            m_restoring = false;
            // libtorrent alert polling runs every 1 s; give it 12 s after all
            // items are enqueued to deliver any deferred torrent_finished_alert
            // before we stop suppressing completions for restored seeding IDs.
            QTimer::singleShot(itemCount * 16 + 12000, this, [this]() {
                m_restoredSeedingIds.clear();
            });
            // Count completed downloads from the restored items
            m_completedCount = 0;
              for (auto *item : m_downloadModel->allItems())
                  if (item->statusEnum() == DownloadItem::Status::Completed)
                      m_completedCount++;
              emit completedDownloadsChanged();
              checkQueueSchedules();
              for (int i = 0; i < m_queueModel->rowCount(); ++i) {
                  Queue *queue = m_queueModel->queueAt(i);
                  if (queue && queue->startOnIDMStartup() && queue->id() != QStringLiteral("download-limits"))
                      startQueue(queue->id());
              }
              cleanupTemporaryDirectory();
              if (m_settings->speedLimiterOnStartup() && m_settings->globalSpeedLimitKBps() == 0
                      && m_settings->savedSpeedLimitKBps() > 0) {
                  m_settings->setGlobalSpeedLimitKBps(m_settings->savedSpeedLimitKBps());
              }
        });
    } else {
        checkQueueSchedules();
        for (int i = 0; i < m_queueModel->rowCount(); ++i) {
            Queue *queue = m_queueModel->queueAt(i);
            if (queue && queue->startOnIDMStartup() && queue->id() != QStringLiteral("download-limits"))
                startQueue(queue->id());
        }
        if (m_settings->speedLimiterOnStartup() && m_settings->globalSpeedLimitKBps() == 0
                && m_settings->savedSpeedLimitKBps() > 0) {
            m_settings->setGlobalSpeedLimitKBps(m_settings->savedSpeedLimitKBps());
        }
        cleanupTemporaryDirectory();
    }
}

int AppController::activeDownloads() const {
    int count = 0;
    for (DownloadItem *item : m_downloadModel->allItems()) {
        if (!item)
            continue;
        if (item->statusEnum() == DownloadItem::Status::Downloading
            || item->statusEnum() == DownloadItem::Status::Seeding
            || item->statusEnum() == DownloadItem::Status::Assembling)
            ++count;
    }
    return count;
}

QString AppController::torrentBindingStatusText() const {
    if (!m_settings)
        return {};

    const QString bindTarget = m_settings->torrentBindInterface().trimmed();
    if (bindTarget.isEmpty())
        return {};

    const QList<QNetworkInterface> interfaces = QNetworkInterface::allInterfaces();
    for (const QNetworkInterface &iface : interfaces) {
        if (iface.name() != bindTarget)
            continue;

        const QString label = iface.humanReadableName().trimmed().isEmpty()
            ? iface.name()
            : iface.humanReadableName().trimmed();
        return QStringLiteral("🛡️ Bound to %1").arg(label);
    }

    return QStringLiteral("🛡️ Bound to %1").arg(bindTarget);
}

void AppController::setTorrentPortTestState(bool inProgress, const QString &status, const QString &message) {
    if (m_torrentPortTestInProgress == inProgress
        && m_torrentPortTestStatus == status
        && m_torrentPortTestMessage == message) {
        return;
    }

    m_torrentPortTestInProgress = inProgress;
    m_torrentPortTestStatus = status;
    m_torrentPortTestMessage = message;
    emit torrentPortTestChanged();
}

void AppController::setSelectedCategory(const QString &v) {
    if (m_selectedCategory != v) {
        m_selectedCategory = v;
        m_selectedQueue = QString();
        m_downloadModel->setFilterCategory(v);
        emit selectedCategoryChanged();
    }
}

void AppController::setSelectedQueue(const QString &v) {
    if (m_selectedQueue != v) {
        m_selectedQueue = v;
        m_selectedCategory = QString();
        m_downloadModel->setFilterQueue(v);
        emit selectedQueueChanged();
    }
}

DownloadItem *AppController::createDownloadItem(const QString &url, const QString &savePath,
                                                const QString &category, const QString &description,
                                                bool startNow, const QString &cookies,
                                                const QString &referrer, const QString &parentUrl,
                                                const QString &username, const QString &password,
                                                const QString &filenameOverride, const QString &queueId,
                                                bool emitUiSignal) {
    if (url.trimmed().isEmpty())
        return nullptr;

    const QString id = generateId();
    const QUrl qurl = QUrl::fromUserInput(url);
    auto *item = new DownloadItem(id, qurl);

    if (!filenameOverride.isEmpty()) {
        item->setFilename(filenameOverride);
        item->setFilenameManuallySet(true);
    }

    if (!cookies.isEmpty())
        item->setCookies(cookies);
    if (!referrer.isEmpty())
        item->setReferrer(referrer);
    if (!parentUrl.isEmpty())
        item->setParentUrl(parentUrl);
    if (!username.isEmpty())
        item->setUsername(username);
    if (!password.isEmpty())
        item->setPassword(password);

    const QString resolvedCategory = !category.isEmpty()
        ? category
        : m_categoryModel->categoryForUrl(qurl, item->filename());
    item->setCategory(resolvedCategory);

    if (!description.isEmpty())
        item->setDescription(description);
    if (!queueId.isEmpty())
        item->setQueueId(queueId);

    if (!savePath.isEmpty()) {
        item->setSavePath(savePath);
    } else if (m_settings->defaultSavePath().isEmpty()) {
        item->setSavePath(m_categoryModel->savePathForCategory(resolvedCategory));
    } else {
        item->setSavePath(m_settings->defaultSavePath());
    }

    if (startNow)
        m_queue->enqueue(item);
    else
        m_queue->enqueueHeld(item);

    if (emitUiSignal)
        emit downloadAdded(item);
    return item;
}

DownloadItem *AppController::createTorrentItem(const QString &source, const QString &savePath,
                                               const QString &category, const QString &description,
                                               bool startNow, const QString &queueId, bool emitUiSignal,
                                               bool staged) {
    const QString trimmed = source.trimmed();
    if (trimmed.isEmpty())
        return nullptr;

    const QString id = generateId();
    const QUrl qurl = QUrl::fromUserInput(trimmed);
    auto *item = new DownloadItem(id, qurl);
    item->setIsTorrent(true);
    item->setTorrentSource(trimmed);

    const QString filename = trimmed.startsWith(QStringLiteral("magnet:?"), Qt::CaseInsensitive)
        ? QStringLiteral("Magnetized transfer")
        : QFileInfo(trimmed).completeBaseName();
    if (!filename.isEmpty()) {
        item->setFilename(filename);
        item->setFilenameManuallySet(true);
    }

    const QString resolvedCategory = !category.isEmpty()
        ? category
        : QStringLiteral("Other");
    item->setCategory(resolvedCategory);
    item->setDescription(description);
    item->setQueueId(queueId);
    item->setResumeCapable(true);
    const QString resolvedSavePath = savePath.isEmpty()
        ? (m_settings->defaultSavePath().isEmpty()
            ? QStandardPaths::writableLocation(QStandardPaths::DownloadLocation)
            : m_settings->defaultSavePath())
        : savePath;
    item->setSavePath(resolvedSavePath);
    item->setStatus((staged || !startNow) ? DownloadItem::Status::Paused
                                          : DownloadItem::Status::Downloading);

    if (staged) {
        m_pendingTorrentItems[item->id()] = item;
        connect(item, &DownloadItem::torrentChanged, this, [this, item]() {
            if (!item)
                return;
            if (!m_pendingTorrentItems.contains(item->id()))
                return;
            if (!item->torrentHasMetadata())
                return;
            if (m_torrentSession)
                m_torrentSession->pause(item->id());
            item->setStatus(DownloadItem::Status::Paused);
        });
    } else {
        m_queue->enqueueRestored(item);
        watchItem(item);
        m_db->save(item);
        if (emitUiSignal)
            emit downloadAdded(item);
    }
    return item;
}

void AppController::addUrl(const QString &url, const QString &savePath,
                           const QString &category, const QString &description,
                           bool startNow, const QString &cookies,
                           const QString &referrer, const QString &parentUrl,
                           const QString &username, const QString &password,
                           const QString &filenameOverride, const QString &queueId) {
    createDownloadItem(url, savePath, category, description, startNow, cookies,
                       referrer, parentUrl, username, password, filenameOverride,
                       queueId, true);
}

bool AppController::isTorrentUri(const QString &value) const {
    return m_torrentSession && m_torrentSession->isTorrentUri(value);
}

QObject *AppController::downloadById(const QString &id) const {
    if (m_pendingTorrentItems.contains(id))
        return m_pendingTorrentItems.value(id);
    return m_downloadModel->itemById(id);
}

QObject *AppController::torrentFileModel(const QString &id) const {
    return m_torrentSession ? m_torrentSession->fileModel(id) : nullptr;
}

QObject *AppController::torrentPeerModel(const QString &id) const {
    return m_torrentSession ? m_torrentSession->peerModel(id) : nullptr;
}

QObject *AppController::torrentTrackerModel(const QString &id) const {
    return m_torrentSession ? m_torrentSession->trackerModel(id) : nullptr;
}

QVariantList AppController::torrentBannedPeers() const {
    return m_torrentSession ? m_torrentSession->bannedPeers() : QVariantList{};
}

QVariantList AppController::torrentCountryOptions() const {
    QVariantList out;
    QDir flagsDir(QStringLiteral(":/app/qml/flags"));
    QStringList codes = flagsDir.entryList(QStringList() << QStringLiteral("*.svg"), QDir::Files, QDir::Name);
    for (QString code : codes) {
        code.chop(4);
        code = code.trimmed().toUpper();
        if (code.length() != 2)
            continue;
        const QLocale::Territory territory = QLocale::codeToTerritory(QStringView{code});
        QString name;
        if (territory != QLocale::AnyTerritory)
            name = QLocale::territoryToString(territory);
        if (name.isEmpty() || name == QStringLiteral("AnyTerritory"))
            name = code;
        QVariantMap row;
        row.insert(QStringLiteral("code"), code);
        row.insert(QStringLiteral("name"), name);
        out.push_back(row);
    }
    return out;
}

QVariantList AppController::torrentNetworkAdapters() const {
    QVariantList adapters;

    QVariantMap defaultOption;
    defaultOption.insert(QStringLiteral("id"), QString());
    defaultOption.insert(QStringLiteral("name"), QStringLiteral("Default route"));
    defaultOption.insert(QStringLiteral("details"), QStringLiteral("Let the OS choose the active network adapter."));
    adapters.push_back(defaultOption);

    const QList<QNetworkInterface> interfaces = QNetworkInterface::allInterfaces();
    for (const QNetworkInterface &iface : interfaces) {
        const auto flags = iface.flags();
        if (!flags.testFlag(QNetworkInterface::IsUp) ||
            !flags.testFlag(QNetworkInterface::IsRunning) ||
            flags.testFlag(QNetworkInterface::IsLoopBack)) {
            continue;
        }

        QStringList addresses;
        const QList<QNetworkAddressEntry> entries = iface.addressEntries();
        for (const QNetworkAddressEntry &entry : entries) {
            const QHostAddress address = entry.ip();
            if (address.isNull() || address.isLoopback())
                continue;
            if (address.protocol() != QAbstractSocket::IPv4Protocol &&
                address.protocol() != QAbstractSocket::IPv6Protocol) {
                continue;
            }

            addresses.push_back(address.toString());
        }

        if (addresses.isEmpty())
            continue;

        QVariantMap option;
        option.insert(QStringLiteral("id"), iface.name());
        option.insert(QStringLiteral("name"),
                      iface.humanReadableName().trimmed().isEmpty()
                          ? iface.name()
                          : iface.humanReadableName().trimmed());
        option.insert(QStringLiteral("details"), addresses.join(QStringLiteral(", ")));
        adapters.push_back(option);
    }

    return adapters;
}

bool AppController::banTorrentPeer(const QString &downloadId, const QString &endpoint, int port,
                                   const QString &client, const QString &countryCode) {
    if (!m_torrentSession || !m_settings)
        return false;
    QHostAddress host(endpoint.trimmed());
    const QString normalized = host.toString();
    if (normalized.isEmpty())
        return false;
    QStringList bans = m_settings->torrentBannedPeers();
    if (!bans.contains(normalized))
        bans.push_back(normalized);
    bans.removeDuplicates();
    m_settings->setTorrentBannedPeers(bans);
    return m_torrentSession->banPeer(downloadId, normalized, port, client, countryCode);
}

bool AppController::unbanTorrentPeer(const QString &endpoint) {
    if (!m_torrentSession || !m_settings)
        return false;
    QHostAddress host(endpoint.trimmed());
    const QString normalized = host.toString();
    if (normalized.isEmpty())
        return false;
    QStringList bans = m_settings->torrentBannedPeers();
    bans.removeAll(normalized);
    m_settings->setTorrentBannedPeers(bans);
    return m_torrentSession->unbanPeer(normalized);
}

void AppController::testTorrentPort() {
    if (!m_torrentSession || !m_settings) {
        setTorrentPortTestState(false, QStringLiteral("error"),
                                QStringLiteral("Torrent support is unavailable in this build."));
        return;
    }

    const QString externalIp = m_torrentSession->detectedExternalAddress().trimmed();
    const int port = m_settings->torrentListenPort();
    if (externalIp.isEmpty()) {
        setTorrentPortTestState(false, QStringLiteral("error"),
                                QStringLiteral("External IP is not known yet. Start the torrent session and try again."));
        return;
    }
    if (port <= 0 || port > 65535) {
        setTorrentPortTestState(false, QStringLiteral("error"),
                                QStringLiteral("Torrent listen port is not valid."));
        return;
    }

    // respectful cooldown because i'm stealing this service from someone else

    if (m_torrentPortTestCooldown.isValid() && m_torrentPortTestCooldown.elapsed() < 4000) {
        return;
    }

    setTorrentPortTestState(true, QStringLiteral("testing"),
                            QStringLiteral("Testing port %1 on %2...").arg(port).arg(externalIp));
    m_torrentPortTestCooldown.restart();

    QNetworkRequest request(QUrl(QStringLiteral("https://ports.yougetsignal.com/check-port.php")));
    request.setHeader(QNetworkRequest::ContentTypeHeader,
                      QStringLiteral("application/x-www-form-urlencoded; charset=UTF-8"));
    request.setRawHeader("User-Agent",
                         QByteArray("Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:149.0) Gecko/20100101 Firefox/149.0"));
    request.setRawHeader("Accept",
                         QByteArray("text/javascript, text/html, application/xml, text/xml, */*"));
    request.setRawHeader("X-Requested-With", QByteArray("XMLHttpRequest"));
    request.setRawHeader("X-Prototype-Version", QByteArray("1.6.0"));
    request.setRawHeader("Origin", QByteArray("https://www.yougetsignal.com"));
    request.setRawHeader("Referer", QByteArray("https://www.yougetsignal.com/"));

    QUrlQuery form;
    form.addQueryItem(QStringLiteral("remoteAddress"), externalIp);
    form.addQueryItem(QStringLiteral("portNumber"), QString::number(port));
    QNetworkReply *reply = m_nam->post(request, form.query(QUrl::FullyEncoded).toUtf8());

    connect(reply, &QNetworkReply::finished, this, [this, reply, externalIp, port]() {
        const QByteArray body = reply->readAll();
        const QString responseText = QString::fromUtf8(body);
        const QNetworkReply::NetworkError error = reply->error();
        const QString errorText = reply->errorString();
        reply->deleteLater();

        if (error != QNetworkReply::NoError) {
            setTorrentPortTestState(false, QStringLiteral("error"),
                                    QStringLiteral("Port test failed: %1").arg(errorText));
            return;
        }

        const QString lower = responseText.toLower();
        if (lower.contains(QStringLiteral("is open"))) {
            setTorrentPortTestState(false, QStringLiteral("open"),
                                    QStringLiteral("Port %1 is open on %2. Incoming torrent connections should work.")
                                        .arg(port).arg(externalIp));
            return;
        }

        if (lower.contains(QStringLiteral("is closed"))) {
            setTorrentPortTestState(false, QStringLiteral("closed"),
                                    QStringLiteral("Port %1 is closed on %2. Check your firewall, router or VPN port forwarding, and adapter binding.")
                                        .arg(port).arg(externalIp));
            return;
        }

        setTorrentPortTestState(false, QStringLiteral("error"),
                                QStringLiteral("Port test returned an unexpected response."));
    });
}

bool AppController::setTorrentFileWanted(const QString &downloadId, int row, bool wanted) {
    return m_torrentSession ? m_torrentSession->setFileWanted(downloadId, row, wanted) : false;
}

bool AppController::setTorrentFileWantedByIndex(const QString &downloadId, int fileIndex, bool wanted) {
    return m_torrentSession ? m_torrentSession->setFileWantedByFileIndex(downloadId, fileIndex, wanted) : false;
}

bool AppController::setTorrentFileWantedByPath(const QString &downloadId, const QString &path, bool wanted) {
    return m_torrentSession ? m_torrentSession->setFileWantedByPath(downloadId, path, wanted) : false;
}

bool AppController::addTorrentTracker(const QString &downloadId, const QString &url) {
    if (!m_torrentSession)
        return false;
    const bool ok = m_torrentSession->addTracker(downloadId, url);
    if (!ok)
        return false;
    if (DownloadItem *item = m_downloadModel->itemById(downloadId))
        item->setTorrentTrackers(m_torrentSession->trackerUrls(downloadId));
    scheduleSave(downloadId);
    return true;
}

bool AppController::removeTorrentTracker(const QString &downloadId, const QString &url) {
    if (!m_torrentSession)
        return false;
    const bool ok = m_torrentSession->removeTracker(downloadId, url);
    if (!ok)
        return false;
    if (DownloadItem *item = m_downloadModel->itemById(downloadId))
        item->setTorrentTrackers(m_torrentSession->trackerUrls(downloadId));
    scheduleSave(downloadId);
    return true;
}

// Returns true only if name is a single legal filename component — no path
// separators, not a dot-only relative navigation segment.  Callers must pass
// the already-trimmed user input; the check is intentionally strict so that
// subdir/file.mkv, .., or ../other cannot reshape the torrent's path tree.
static bool isSafeFilenameComponent(const QString &name) {
    if (name.isEmpty())
        return false;
    if (name == QLatin1String(".") || name == QLatin1String(".."))
        return false;
    if (name.contains(QLatin1Char('/')) || name.contains(QLatin1Char('\\')))
        return false;
    return true;
}

bool AppController::renameTorrentFile(const QString &downloadId, int fileIndex, const QString &newName) {
    if (!m_torrentSession)
        return false;
    const QString trimmed = newName.trimmed();
    if (!isSafeFilenameComponent(trimmed)) {
        qWarning() << "[Rename] Rejected unsafe filename component:" << newName;
        return false;
    }

    // Apply to libtorrent first, then mirror optimistically in the model.
    // For path-based operations the backend needs the pre-rename path context.
    if (!m_torrentSession->renameTorrentFile(downloadId, fileIndex, trimmed))
        return false;

    if (auto *model = qobject_cast<TorrentFileModel *>(m_torrentSession->fileModel(downloadId))) {
        for (int row = 0; row < model->rowCount(); ++row) {
            if (model->fileIndexAt(row) == fileIndex) {
                model->renameEntry(row, trimmed);
                break;
            }
        }
    }
    return true;
}

bool AppController::renameTorrentPath(const QString &downloadId, const QString &currentPath, const QString &newName) {
    if (!m_torrentSession)
        return false;
    const QString trimmed = newName.trimmed();
    if (!isSafeFilenameComponent(trimmed)) {
        qWarning() << "[Rename] Rejected unsafe filename component:" << newName;
        return false;
    }

    // Apply to libtorrent first so currentPath still matches the pre-rename tree.
    if (!m_torrentSession->renameTorrentPath(downloadId, currentPath, trimmed))
        return false;

    if (auto *model = qobject_cast<TorrentFileModel *>(m_torrentSession->fileModel(downloadId)))
        model->renamePath(currentPath, trimmed);
    return true;
}

void AppController::setTorrentFlags(const QString &downloadId, bool disableDht, bool disablePex, bool disableLsd) {
    if (m_torrentSession)
        m_torrentSession->setTorrentFlags(downloadId, disableDht, disablePex, disableLsd);
}

QString AppController::addMagnetLink(const QString &uri, const QString &savePath,
                                     const QString &category, const QString &description,
                                     bool startNow, const QString &queueId) {
    Q_UNUSED(startNow);
    if (!m_torrentSession || !m_torrentSession->available()) {
        emit errorOccurred(QStringLiteral("Torrent support is unavailable in this build."));
        return {};
    }
    auto *item = createTorrentItem(normalizeTorrentSource(uri), savePath, category, description, true, queueId, false, true);
    if (!item)
        return {};
    if (!m_torrentSession->addMagnet(item, false)) {
        discardTorrentDownload(item->id());
        emit errorOccurred(QStringLiteral("Failed to add magnet link."));
        return {};
    } else {
        applyPerTorrentSpeedLimits(m_torrentSession, item);
    }
    return item->id();
}

QString AppController::addTorrentFile(const QString &filePath, const QString &savePath,
                                      const QString &category, const QString &description,
                                      bool startNow, const QString &queueId) {
    Q_UNUSED(startNow);
    if (!m_torrentSession || !m_torrentSession->available()) {
        emit errorOccurred(QStringLiteral("Torrent support is unavailable in this build."));
        return {};
    }
    auto *item = createTorrentItem(filePath, savePath, category, description, true, queueId, false, true);
    if (!item)
        return {};
    // Staged .torrent adds should not start piece transfer before the metadata
    // dialog is confirmed; metadata is already present in the .torrent file.
    if (!m_torrentSession->addTorrentFile(item, filePath, true)) {
        discardTorrentDownload(item->id());
        emit errorOccurred(QStringLiteral("Failed to add torrent file."));
        return {};
    } else {
        applyPerTorrentSpeedLimits(m_torrentSession, item);
    }
    return item->id();
}

QString AppController::beginTorrentMetadataDownload(const QString &source, const QString &savePath,
                                                    const QString &category, const QString &description,
                                                    bool startWhenReady) {
    const QString trimmed = source.trimmed();
    if (trimmed.isEmpty())
        return {};
    if (!m_torrentSession || !m_torrentSession->available()) {
        emit errorOccurred(QStringLiteral("Torrent support is unavailable in this build."));
        return {};
    }

    QString downloadId;
    if (isTorrentUri(trimmed))
        downloadId = addMagnetLink(trimmed, savePath, category, description, false, {});
    else
        return {};

    if (!downloadId.isEmpty())
        emit torrentMetadataRequested(downloadId, startWhenReady);
    return downloadId;
}

bool AppController::confirmTorrentDownload(const QString &downloadId, const QString &savePath,
                                           const QString &category, const QString &description,
                                           bool startNow, const QString &queueId) {
    auto it = m_pendingTorrentItems.find(downloadId);
    if (it == m_pendingTorrentItems.end())
        return false;

    DownloadItem *item = it.value();
    if (!item)
        return false;

    const QString requestedSavePath = normalizeTorrentSaveDirectory(savePath);
    const QString previousSavePath = item->savePath().trimmed();
    if (!requestedSavePath.isEmpty())
        item->setSavePath(requestedSavePath);
    if (!category.isEmpty())
        item->setCategory(category);
    item->setDescription(description);
    item->setQueueId(queueId);

    m_pendingTorrentItems.erase(it);
    m_queue->enqueueRestored(item);
    watchItem(item);
    m_db->save(item);

    const QString effectiveSavePath = item->savePath().trimmed();
    if (m_torrentSession && !effectiveSavePath.isEmpty()
        && QDir::cleanPath(previousSavePath) != QDir::cleanPath(effectiveSavePath)) {
        // The torrent handle already exists while this item is staged. If the user
        // changed save directory in the metadata dialog we must move storage on the
        // live handle as well, otherwise libtorrent keeps writing to the old path.
        m_torrentSession->moveStorage(downloadId, effectiveSavePath);
    }

    if (!startNow && item->torrentHasMetadata()) {
        m_torrentSession->pause(downloadId);
        item->setStatus(DownloadItem::Status::Paused);
        m_torrentSession->saveResumeData(downloadId);
    } else {
        // Always force a hash recheck on confirmation so pre-existing data in the
        // chosen save directory is discovered before piece download continues.
        m_torrentSession->forceRecheck(downloadId);
        m_torrentSession->resume(item);
        applyPerTorrentSpeedLimits(m_torrentSession, item);
        if (!item->torrentHasMetadata()) {
            QPointer<DownloadItem> guardedItem(item);
            connect(item, &DownloadItem::torrentChanged, this, [this, guardedItem, downloadId]() {
                if (!guardedItem || !guardedItem->torrentHasMetadata())
                    return;
                if (m_torrentSession) {
                    m_torrentSession->forceRecheck(downloadId);
                    m_torrentSession->resume(guardedItem);
                }
            }, Qt::SingleShotConnection);
        }
    }

    emit downloadAdded(item);
    emit activeDownloadsChanged();
    return true;
}

QString AppController::normalizeTorrentSaveDirectory(const QString &path) const {
    QString raw = QDir::fromNativeSeparators(path.trimmed());
    if (raw.isEmpty())
        return raw;
    while (raw.length() > 1 && raw.endsWith(QLatin1Char('/')))
        raw.chop(1);

    QFileInfo info(raw);
    if (info.exists()) {
        if (info.isDir())
            return QDir::cleanPath(info.absoluteFilePath());
        return QDir::cleanPath(info.absolutePath());
    }

    const int sep = raw.lastIndexOf(QLatin1Char('/'));
    if (sep < 0)
        return QDir::cleanPath(raw);
    const QString leaf = raw.mid(sep + 1);
    if (leaf.endsWith(QStringLiteral(".torrent"), Qt::CaseInsensitive))
        return QDir::cleanPath(raw.left(sep));

    // Default to directory semantics for non-existing paths so users can type
    // target folders that don't exist yet.
    return QDir::cleanPath(raw);
}

void AppController::discardTorrentDownload(const QString &downloadId) {
    auto it = m_pendingTorrentItems.find(downloadId);
    if (it == m_pendingTorrentItems.end())
        return;
    DownloadItem *item = it.value();
    m_pendingTorrentItems.erase(it);
    if (item && item->isTorrent())
        m_torrentSession->remove(downloadId, true);
    if (item)
        item->deleteLater();
    m_torrentSpeedHistory.remove(downloadId);
}

QString AppController::beginPendingDownload(const QString &url,
                                            const QString &filenameOverride,
                                            const QString &cookies,
                                            const QString &referrer,
                                            const QString &parentUrl,
                                            const QString &username,
                                            const QString &password) {
    const QString tempDir = m_settings->temporaryDirectory().trimmed();
    DownloadItem *item = createDownloadItem(url, tempDir, {}, {}, true, cookies, referrer,
                                            parentUrl, username, password,
                                            filenameOverride, {}, false);
    if (!item)
        return {};
    m_pendingFileInfoDownloads.insert(item->id());
    return item->id();
}

bool AppController::finalizePendingDownload(const QString &downloadId,
                                            const QString &fullSavePath,
                                            const QString &category,
                                            const QString &description,
                                            bool startNow,
                                            const QString &queueId) {
    DownloadItem *item = m_downloadModel->itemById(downloadId);
    if (!item)
        return false;

    const int sep = qMax(fullSavePath.lastIndexOf(QLatin1Char('/')),
                         fullSavePath.lastIndexOf(QLatin1Char('\\')));
    const QString newSaveDir = sep >= 0 ? fullSavePath.left(sep) : item->savePath();
    const QString newFilename = sep >= 0 ? fullSavePath.mid(sep + 1) : item->filename();
    const QString resolvedCategory = category.isEmpty()
        ? m_categoryModel->categoryForUrl(item->url(), newFilename)
        : category;

    if (item->statusEnum() == DownloadItem::Status::Completed) {
        if (!moveDownloadFile(downloadId, fullSavePath))
            return false;
    } else {
        if (!m_queue->relocateDownload(downloadId, newSaveDir, newFilename))
            return false;
    }

    item->setFilenameManuallySet(true);
    item->setCategory(resolvedCategory);
    item->setDescription(description);
    item->setQueueId(queueId);
    scheduleSave(downloadId);

    if (startNow) {
        if (item->statusEnum() == DownloadItem::Status::Paused)
            m_queue->resume(downloadId);
        m_pendingFileInfoDownloads.remove(downloadId);
        if (item->statusEnum() == DownloadItem::Status::Completed)
            emit downloadCompleted(item);
        else
            emit downloadAdded(item);
    } else {
        if (item->statusEnum() == DownloadItem::Status::Downloading
            || item->statusEnum() == DownloadItem::Status::Queued
            || item->statusEnum() == DownloadItem::Status::Assembling) {
            m_queue->pause(downloadId);
        }
    }
    return true;
}

void AppController::discardPendingDownload(const QString &downloadId) {
    if (downloadId.isEmpty())
        return;
    m_pendingFileInfoDownloads.remove(downloadId);
    m_queue->cancel(downloadId);
}

QObject *AppController::findDuplicateUrl(const QString &url) const {
    const QUrl qurl = QUrl::fromUserInput(url);
    return m_downloadModel->itemByUrl(qurl);
}

QString AppController::generateNumberedFilename(const QString &filename) const {
    const QString base = QFileInfo(filename).completeBaseName();
    const QString ext  = QFileInfo(filename).suffix();
    const QString dotExt = ext.isEmpty() ? QString{} : QStringLiteral(".") + ext;

    int n = 2;
    while (n < 1000) {
        QString candidate = base + QStringLiteral(" (") + QString::number(n) + QStringLiteral(")") + dotExt;
        // Check if any existing item already has this filename
        bool taken = false;
        for (auto *item : m_queue->items()) {
            if (item->filename().compare(candidate, Qt::CaseInsensitive) == 0) {
                taken = true;
                break;
            }
        }
        if (!taken) return candidate;
        ++n;
    }
    return filename; // fallback (should never reach)
}

bool AppController::fileExists(const QString &path) const {
    return QFileInfo::exists(path);
}

void AppController::copyToClipboard(const QString &text) const {
    QGuiApplication::clipboard()->setText(text);
}

void AppController::openExtensionFolder() const {
    // Try installed path first (extensions/firefox next to the binary)
    const QString appDir = QCoreApplication::applicationDirPath();
    const QString installedPath = appDir + QStringLiteral("/extensions/firefox");
    if (QFile::exists(installedPath)) {
        QDesktopServices::openUrl(QUrl::fromLocalFile(installedPath));
        return;
    }
    // Dev build: binary is in build/windows-debug/ — project root is 3 levels up
    const QString devPath = QDir::cleanPath(appDir + QStringLiteral("/../../../extensions/firefox"));
    if (QFile::exists(devPath)) {
        QDesktopServices::openUrl(QUrl::fromLocalFile(devPath));
        return;
    }
    // Final fallback: just open the app directory
    QDesktopServices::openUrl(QUrl::fromLocalFile(appDir));
}

QString AppController::nativeHostManifestPath() const {
#if defined(STELLAR_LINUX)
    // On Linux the app dir may be read-only (e.g. Flatpak /app/bin/).
    // Use a writable user-data directory instead.
    const QString dataDir = QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation);
    QDir().mkpath(dataDir);
    return dataDir + QStringLiteral("/com.stellar.downloadmanager.json");
#else
    // Windows: return the Firefox manifest path for diagnostics/UI.
    return QDir::toNativeSeparators(
        QCoreApplication::applicationDirPath() + QStringLiteral("/com.stellar.downloadmanager.json"));
#endif
}

QString AppController::nativeHostDiagnostics() const {
    QStringList lines;

    const QString manifestPath = nativeHostManifestPath();
    lines << QStringLiteral("Manifest path: ") + manifestPath;

    const bool exists = QFile::exists(manifestPath);
    lines << QStringLiteral("Manifest file exists: ") + (exists ? QStringLiteral("YES") : QStringLiteral("NO"));

    if (exists) {
        QFile f(manifestPath);
        if (f.open(QIODevice::ReadOnly | QIODevice::Text)) {
            lines << QStringLiteral("Manifest contents:");
            lines << QString::fromUtf8(f.readAll());
        } else {
            lines << QStringLiteral("Could not read manifest: ") + f.errorString();
        }
    }

#if defined(STELLAR_WINDOWS)
    const QString chromeManifestPath = QDir::toNativeSeparators(
        QCoreApplication::applicationDirPath() + QStringLiteral("/com.stellar.downloadmanager.chrome.json"));
    lines << QStringLiteral("Chrome manifest path: ") + chromeManifestPath;
    lines << QStringLiteral("Chrome manifest exists: ")
          + (QFile::exists(chromeManifestPath) ? QStringLiteral("YES") : QStringLiteral("NO"));

    const QList<QPair<QString, QString>> regKeys = {
        { QStringLiteral("Chrome"),  QStringLiteral("Software\\Google\\Chrome\\NativeMessagingHosts\\com.stellar.downloadmanager") },
        { QStringLiteral("Firefox"), QStringLiteral("Software\\Mozilla\\NativeMessagingHosts\\com.stellar.downloadmanager") }
    };

    for (const auto &entry : regKeys) {
        HKEY hKey = nullptr;
        LONG res = RegOpenKeyExW(HKEY_CURRENT_USER,
                                 reinterpret_cast<LPCWSTR>(entry.second.utf16()),
                                 0, KEY_QUERY_VALUE, &hKey);
        if (res != ERROR_SUCCESS) {
            lines << entry.first + QStringLiteral(" registry key: NOT FOUND (error %1)").arg(res);
            continue;
        }
        WCHAR buf[MAX_PATH] = {};
        DWORD sz = sizeof(buf);
        DWORD type = 0;
        res = RegQueryValueExW(hKey, L"", nullptr, &type,
                               reinterpret_cast<LPBYTE>(buf), &sz);
        RegCloseKey(hKey);
        if (res == ERROR_SUCCESS)
            lines << entry.first + QStringLiteral(" registry value: ") + QString::fromWCharArray(buf);
        else
            lines << entry.first + QStringLiteral(" registry default value: NOT SET (error %1)").arg(res);
    }
#endif

    return lines.join(QLatin1Char('\n'));
}

QString AppController::registerNativeHost() const {
    const QString manifestPath = nativeHostManifestPath();

#if defined(STELLAR_LINUX)
    // On Linux the executable path used in the manifest depends on whether
    // we are running inside a Flatpak sandbox.  Inside Flatpak,
    // applicationFilePath() returns "/app/bin/Stellar" which is invisible to
    // the host Firefox process.  We write a tiny wrapper script to a
    // host-writable location that calls "flatpak run ..." so Firefox can
    // execute it directly.

    const bool isFlatpak = qEnvironmentVariableIsSet("FLATPAK_ID");
    const QString flatpakId = QString::fromLocal8Bit(qgetenv("FLATPAK_ID"));
    QString hostExePath;  // path Firefox will put in the manifest

    if (isFlatpak) {
        // Write a wrapper script: ~/.local/share/<AppName>/stellar-nm-wrapper.sh
        const QString dataDir = QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation);
        QDir().mkpath(dataDir);
        const QString wrapperPath = dataDir + QStringLiteral("/stellar-nm-wrapper.sh");

        QFile wrapper(wrapperPath);
        if (!wrapper.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text))
            return QStringLiteral("Could not write wrapper script: ") + wrapperPath
                   + QStringLiteral("\nError: ") + wrapper.errorString();
        wrapper.write(QStringLiteral("#!/bin/bash\nexec flatpak run %1 \"$@\"\n")
                      .arg(flatpakId).toUtf8());
        wrapper.close();
        // Make it executable
        wrapper.setPermissions(
            QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner |
            QFileDevice::ReadGroup | QFileDevice::ExeGroup |
            QFileDevice::ReadOther | QFileDevice::ExeOther);
        hostExePath = wrapperPath;
    } else {
        hostExePath = QCoreApplication::applicationFilePath();
    }

    QJsonObject manifest;
    manifest[QStringLiteral("name")]        = QStringLiteral("com.stellar.downloadmanager");
    manifest[QStringLiteral("description")] = QStringLiteral("Stellar Download Manager native messaging host");
    manifest[QStringLiteral("path")]        = hostExePath;
    manifest[QStringLiteral("type")]        = QStringLiteral("stdio");
    manifest[QStringLiteral("allowed_extensions")] = QJsonArray{ QStringLiteral("stellar@stellar.moe") };
    manifest[QStringLiteral("allowed_origins")] = QJsonArray{ QStringLiteral("chrome-extension://kncomdlgkcaamlaaoloncdafbijdfcjo/") };

    const QByteArray json = QJsonDocument(manifest).toJson(QJsonDocument::Indented);

    // Write the manifest source file (used for manual cp instructions).
    {
        QDir().mkpath(QFileInfo(manifestPath).absolutePath());
        QFile f(manifestPath);
        if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate))
            return QStringLiteral("Could not write manifest file: ") + manifestPath
                   + QStringLiteral("\nError: ") + f.errorString();
        f.write(json);
    }

#else
    // Non-Linux: exe path is always the running binary.
    const QString exePath = QDir::toNativeSeparators(QCoreApplication::applicationFilePath());
    const QString chromeManifestPath = QDir::toNativeSeparators(
        QCoreApplication::applicationDirPath() + QStringLiteral("/com.stellar.downloadmanager.chrome.json"));

    QJsonObject firefoxManifest;
    firefoxManifest[QStringLiteral("name")]        = QStringLiteral("com.stellar.downloadmanager");
    firefoxManifest[QStringLiteral("description")] = QStringLiteral("Stellar Download Manager native messaging host");
    firefoxManifest[QStringLiteral("path")]        = exePath;
    firefoxManifest[QStringLiteral("type")]        = QStringLiteral("stdio");
    firefoxManifest[QStringLiteral("allowed_extensions")] = QJsonArray{ QStringLiteral("stellar@stellar.moe") };

    QJsonObject chromeManifest;
    chromeManifest[QStringLiteral("name")]        = QStringLiteral("com.stellar.downloadmanager");
    chromeManifest[QStringLiteral("description")] = QStringLiteral("Stellar Download Manager native messaging host");
    chromeManifest[QStringLiteral("path")]        = exePath;
    chromeManifest[QStringLiteral("type")]        = QStringLiteral("stdio");
    chromeManifest[QStringLiteral("allowed_origins")] = QJsonArray{ QStringLiteral("chrome-extension://kncomdlgkcaamlaaoloncdafbijdfcjo/") };

    const QByteArray firefoxJson = QJsonDocument(firefoxManifest).toJson(QJsonDocument::Indented);
    const QByteArray chromeJson  = QJsonDocument(chromeManifest).toJson(QJsonDocument::Indented);

    QDir().mkpath(QCoreApplication::applicationDirPath());
    {
        QFile f(manifestPath);
        if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate))
            return QStringLiteral("Could not write Firefox native host manifest: ") + manifestPath
                   + QStringLiteral("\nError: ") + f.errorString();
        f.write(firefoxJson);
    }
    {
        QFile f(chromeManifestPath);
        if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate))
            return QStringLiteral("Could not write Chrome native host manifest: ") + chromeManifestPath
                   + QStringLiteral("\nError: ") + f.errorString();
        f.write(chromeJson);
    }
#endif

#if defined(STELLAR_WINDOWS)
    // Chrome and Firefox want different manifest schemas, so register each
    // browser against its own manifest file.
    const QList<QPair<QString, QString>> regTargets = {
        { QStringLiteral("Software\\Google\\Chrome\\NativeMessagingHosts\\com.stellar.downloadmanager"),
          QDir::toNativeSeparators(QCoreApplication::applicationDirPath() + QStringLiteral("/com.stellar.downloadmanager.chrome.json")) },
        { QStringLiteral("Software\\Mozilla\\NativeMessagingHosts\\com.stellar.downloadmanager"),
          manifestPath }
    };

    for (const auto &target : regTargets) {
        const std::wstring wval = reinterpret_cast<const wchar_t *>(target.second.utf16());
        HKEY hKey = nullptr;
        LONG res = RegCreateKeyExW(
            HKEY_CURRENT_USER,
            reinterpret_cast<LPCWSTR>(target.first.utf16()),
            0, nullptr, REG_OPTION_NON_VOLATILE, KEY_SET_VALUE, nullptr,
            &hKey, nullptr);
        if (res != ERROR_SUCCESS || !hKey) {
            return QStringLiteral("Failed to create native host registry key %1 (error %2).\nPlease register manually.")
                .arg(target.first, QString::number(res));
        }

        res = RegSetValueExW(
            hKey, L"", 0, REG_SZ,
            reinterpret_cast<const BYTE *>(wval.c_str()),
            static_cast<DWORD>((wval.size() + 1) * sizeof(wchar_t)));
        RegCloseKey(hKey);

        if (res != ERROR_SUCCESS) {
            return QStringLiteral("Failed to write native host registry value %1 (error %2).\nPlease register manually.")
                .arg(target.first, QString::number(res));
        }
    }
#elif defined(STELLAR_LINUX)
    // Copy manifest to all known Firefox native-messaging-hosts directories.
    // Standard Firefox: ~/.mozilla/native-messaging-hosts/
    // Snap Firefox:     ~/snap/firefox/common/.mozilla/native-messaging-hosts/
    const QStringList mozDirs = {
        QDir::homePath() + QStringLiteral("/.mozilla/native-messaging-hosts"),
        QDir::homePath() + QStringLiteral("/snap/firefox/common/.mozilla/native-messaging-hosts"),
    };

    QString lastError;
    bool anyOk = false;
    for (const QString &mozDir : mozDirs) {
        // Only write to snap path if the snap directory exists (avoids creating
        // snap dirs on systems that don't have snap Firefox).
        if (mozDir.contains(QStringLiteral("/snap/")) &&
            !QDir(QDir::homePath() + QStringLiteral("/snap/firefox")).exists())
            continue;

        if (!QDir().mkpath(mozDir)) {
            lastError = QStringLiteral("Could not create directory: ") + mozDir;
            continue;
        }
        const QString dest = mozDir + QStringLiteral("/com.stellar.downloadmanager.json");
        QFile::remove(dest);
        QFile src(manifestPath);
        if (!src.copy(dest)) {
            lastError = QStringLiteral("Could not copy manifest to: ") + dest
                        + QStringLiteral("\nError: ") + src.errorString();
        } else {
            anyOk = true;
        }
    }

    if (!anyOk)
        return lastError.isEmpty()
               ? QStringLiteral("No Firefox installation directories found.")
               : lastError;
#else
    return QStringLiteral("Automatic registration is not supported on this platform.\nPlease register manually using the instructions below.");
#endif

    return {};  // success
}

void AppController::setPendingCookies(const QString &url, const QString &cookies) {
    if (!cookies.isEmpty())
        m_pendingCookies[url] = cookies;
}

QString AppController::takePendingCookies(const QString &url) {
    return m_pendingCookies.take(url);
}

QString AppController::takePendingReferrer(const QString &url) {
    return m_pendingReferrers.take(url);
}

QString AppController::takePendingPageUrl(const QString &url) {
    return m_pendingPageUrls.take(url);
}

void AppController::deleteAllCompleted(int mode, bool includeSeedingTorrents) {
    QStringList toDelete;
    const auto items = m_downloadModel->allItems();
    for (auto *item : items) {
        if (!item)
            continue;
        if (item->status() == QStringLiteral("Completed")
            || (includeSeedingTorrents && item->isTorrent() && item->status() == QStringLiteral("Seeding"))) {
            toDelete << item->id();
        }
    }
    if (toDelete.isEmpty()) return;
    m_downloadModel->beginBulkRemove();
    for (const QString &id : toDelete)
        deleteDownload(id, mode);
    m_downloadModel->endBulkRemove();
}

void AppController::deleteDownloads(const QStringList &ids, int mode) {
    if (ids.isEmpty()) return;
    const QStringList stableIds = ids;
    m_downloadModel->beginBulkRemove();
    for (const QString &id : stableIds)
        deleteDownload(id, mode);
    m_downloadModel->endBulkRemove();
}

void AppController::pauseAllDownloads() {
    const auto items = m_downloadModel->allItems();
    for (auto *item : items) {
        if (item->status() != QStringLiteral("Downloading") && item->status() != QStringLiteral("Queued"))
            continue;
        if (item->isTorrent()) {
            m_torrentSession->pause(item->id());
            item->setStatus(DownloadItem::Status::Paused);
            scheduleSave(item->id());
        } else if (item->isYtdlp()) {
            auto *worker = m_ytdlpWorkers.value(item->id());
            if (worker) worker->pause();
            else        item->setStatus(DownloadItem::Status::Paused);
        } else {
            m_queue->pause(item->id());
        }
    }
}

void AppController::sortDownloads(const QString &column, bool ascending) {
    m_downloadModel->sortBy(column, ascending);
}

void AppController::setDownloadSpeedLimit(const QString &downloadId, int kbps) {
    // Set on the item itself (for persistence and future starts)
    auto *item = m_downloadModel->itemById(downloadId);
    if (item)
        item->setSpeedLimitKBps(kbps);
    // Also set on active worker if it exists
    m_queue->setDownloadSpeedLimit(downloadId, kbps);
}

void AppController::setTorrentSpeedLimits(const QString &downloadId, int downKBps, int upKBps) {
    auto *item = m_downloadModel->itemById(downloadId);
    if (!item)
        return;
    item->setPerTorrentDownLimitKBps(downKBps);
    item->setPerTorrentUpLimitKBps(upKBps);
    m_torrentSession->setPerTorrentDownloadLimit(downloadId, downKBps);
    m_torrentSession->setPerTorrentUploadLimit(downloadId, upKBps);
    scheduleSave(downloadId);
}

void AppController::setTorrentShareLimits(const QString &downloadId, double ratio, int seedTimeMins, int inactiveTimeMins, int action) {
    auto *item = m_downloadModel->itemById(downloadId);
    if (!item)
        return;
    item->setTorrentShareRatioLimit(ratio);
    item->setTorrentSeedingTimeLimitMins(seedTimeMins);
    item->setTorrentInactiveSeedingTimeLimitMins(inactiveTimeMins);
    item->setTorrentShareLimitAction(action);
    scheduleSave(downloadId);
}

void AppController::notifyInterceptRejected(const QString &url) {
    if (url.isEmpty() || !m_settings->showExceptionsDialog()) return;
    int &count = m_interceptRejectCounts[url];
    ++count;
    if (count >= 2) {
        m_interceptRejectCounts.remove(url);
        emit exceptionDialogRequested(url);
    }
}

void AppController::addExcludedAddress(const QString &pattern) {
    if (pattern.trimmed().isEmpty()) return;
    QStringList list = m_settings->excludedAddresses();
    if (!list.contains(pattern.trimmed())) {
        list.prepend(pattern.trimmed());
        m_settings->setExcludedAddresses(list);
    }
}

void AppController::pauseDownload(const QString &id) {
    auto *item = m_downloadModel->itemById(id);
    if (item && item->isTorrent()) {
        m_torrentSession->pause(id);
        item->setStatus(DownloadItem::Status::Paused);
        m_torrentSession->saveResumeData(id);
        scheduleSave(id);
        emit activeDownloadsChanged();
        return;
    }
    if (item && item->isYtdlp()) {
        auto *worker = m_ytdlpWorkers.value(id);
        if (worker) worker->pause();
        else        item->setStatus(DownloadItem::Status::Paused);
        return;
    }
    m_queue->pause(id);
}

void AppController::resumeDownload(const QString &id) {
    DownloadItem *item = m_downloadModel->itemById(id);
    const bool wasPendingFileInfoDownload = m_pendingFileInfoDownloads.remove(id);

    if (item && item->isTorrent()) {
        m_torrentSession->resume(item);
        applyPerTorrentSpeedLimits(m_torrentSession, item);
        scheduleSave(id);
        emit activeDownloadsChanged();
        return;
    }

    if (item && item->isYtdlp()) {
        // A paused yt-dlp item is resumed by creating a new YtdlpTransfer with
        // resume=true, which passes --continue so yt-dlp picks up the partial file.
        if (item->statusEnum() == DownloadItem::Status::Paused) {
            // ytdlpFormatId stores "<formatId>|<container>|<outputTemplate>"
            // The output template may itself contain '|' in yt-dlp selectors,
            // so split on the FIRST two '|' only.
            const QString stored    = item->ytdlpFormatId();
            const int p1            = stored.indexOf(QLatin1Char('|'));
            const int p2            = p1 >= 0 ? stored.indexOf(QLatin1Char('|'), p1 + 1) : -1;
            const QString formatId  = p1 >= 0 ? stored.left(p1) : stored;
            const QString container = (p1 >= 0 && p2 > p1)
                                      ? stored.mid(p1 + 1, p2 - p1 - 1)
                                      : (p1 >= 0 ? stored.mid(p1 + 1) : QStringLiteral("mp4"));
            const QString tmpl      = p2 >= 0 ? stored.mid(p2 + 1) : QString();
            const YtdlpOptions resumeOpts = YtdlpOptions::fromJson(item->ytdlpExtraOptions());
            startYtdlpWorker(item, formatId, container, /*resume=*/true, tmpl,
                             item->ytdlpPlaylistMode(), 0, resumeOpts);
        }
        return;
    }

    m_queue->resume(id);
    if (wasPendingFileInfoDownload && item && item->queueId().isEmpty())
        emit downloadAdded(item);
}

void AppController::forceRecheckTorrent(const QString &id) {
    auto *item = m_downloadModel->itemById(id);
    if (item && item->isTorrent() && m_torrentSession) {
        m_torrentSession->forceRecheck(id);
    }
}

void AppController::redownload(const QString &id) {
    auto *item = m_downloadModel->itemById(id);
    if (!item) return;

    if (item->isYtdlp()) {
        // For yt-dlp items, abort any running worker then restart from scratch (no resume).
        auto *worker = m_ytdlpWorkers.take(id);
        if (worker) { worker->abort(); worker->deleteLater(); }
        item->setDoneBytes(0);
        item->setTotalBytes(0);
        item->setSpeed(0);
        const QString stored2   = item->ytdlpFormatId();
        const int q1            = stored2.indexOf(QLatin1Char('|'));
        const int q2            = q1 >= 0 ? stored2.indexOf(QLatin1Char('|'), q1 + 1) : -1;
        const QString formatId  = q1 >= 0 ? stored2.left(q1) : stored2;
        const QString container = (q1 >= 0 && q2 > q1)
                                  ? stored2.mid(q1 + 1, q2 - q1 - 1)
                                  : (q1 >= 0 ? stored2.mid(q1 + 1) : QStringLiteral("mp4"));
        const QString tmpl2     = q2 >= 0 ? stored2.mid(q2 + 1) : QString();
        const YtdlpOptions redownloadOpts = YtdlpOptions::fromJson(item->ytdlpExtraOptions());
        startYtdlpWorker(item, formatId, container, /*resume=*/false, tmpl2,
                         item->ytdlpPlaylistMode(), 0, redownloadOpts);
        return;
    }

    if (item->isTorrent()) {
        const QString source = item->torrentSource();
        const QString savePath = item->savePath();
        const QString category = item->category();
        const QString description = item->description();
        const QString queueId = item->queueId();
        deleteDownload(id, 0);
        const QString newId = source.startsWith(QStringLiteral("magnet:?"), Qt::CaseInsensitive)
            ? addMagnetLink(source, savePath, category, description, true, queueId)
            : addTorrentFile(source, savePath, category, description, true, queueId);
        confirmTorrentDownload(newId, savePath, category, description, true, queueId);
        return;
    }

    QString url = item->url().toString();
    QString savePath = item->savePath();
    QString category = item->category();
    QString description = item->description();
    QString cookies = item->cookies();
    QString referrer = item->referrer();
    QString parentUrl = item->parentUrl();
    QString username = item->username();
    QString password = item->password();

    m_queue->cancel(id);

    addUrl(url, savePath, category, description, true, cookies, referrer, parentUrl, username, password);
}

void AppController::deleteDownload(const QString &id, int mode) {
    if (m_pendingTorrentItems.contains(id)) {
        discardTorrentDownload(id);
        return;
    }
    // Capture file path and URL before the item is removed from queue
    QString filePath;
    QString itemUrl;
    QString savePath;
    QString filename;
    bool isCompleted = false;
    bool isTorrent = false;
    bool deleteTorrentPayload = false;
    {
        auto *item = m_downloadModel->itemById(id);
        // Accumulate all-time torrent stats before the item is removed
        if (item && item->isTorrent()) {
            m_settings->accumulateTorrentStats(item->torrentUploaded(), item->torrentDownloaded());
        }
        if (item) {
            itemUrl = item->url().toString();
            savePath = item->savePath();
            filename = item->filename();
            isCompleted = (item->statusEnum() == DownloadItem::Status::Completed);
            isTorrent = item->isTorrent();
            // Guard: only build a deletion path when the filename is a non-empty,
            // single-component name. An empty filename would collapse to the save
            // directory itself; a path-separator in the name could escape the save
            // directory. Either case must never be passed to remove/moveToTrash.
            if (mode > 0 && isCompleted
                    && !filename.isEmpty()
                    && !filename.contains(QLatin1Char('/'))
                    && !filename.contains(QLatin1Char('\\')))
                filePath = savePath + QStringLiteral("/") + filename;
            if (mode > 0 && isTorrent)
                deleteTorrentPayload = true;
        }
    }

    if (isTorrent) {
        // Always let libtorrent delete torrent payload from the actual active
        // storage path. This avoids deleting stale paths from UI metadata when the
        // handle storage directory changed.
        m_torrentSession->remove(id, deleteTorrentPayload);
    }

    // Abort any running yt-dlp worker for this item before cancelling the queue entry
    auto *ytWorker = m_ytdlpWorkers.take(id);
    if (ytWorker) { ytWorker->abort(); ytWorker->deleteLater(); }

    m_queue->cancel(id);
    m_torrentSpeedHistory.remove(id);

    // Clean up temp/part files for non-completed downloads.
    // DownloadQueue::cancel() calls abort() on the active worker (which cleans
    // up), but paused items have no worker so their part/meta files linger.
    if (!isCompleted && !filename.isEmpty()) {
        QString tempDir = m_settings->temporaryDirectory().trimmed();
        if (tempDir.isEmpty()) tempDir = savePath;
        QtConcurrent::run([tempDir, filename]() {
            QDir d(tempDir);
            // Remove meta file
            QFile::remove(tempDir + QStringLiteral("/") + filename + QStringLiteral(".stellar-meta"));
            // Remove all part files matching this filename
            const QStringList filters = { filename + QStringLiteral(".stellar-part-*") };
            const QFileInfoList parts = d.entryInfoList(filters, QDir::Files);
            for (const QFileInfo &fi : parts)
                QFile::remove(fi.absoluteFilePath());
        });
    }

    if (!filePath.isEmpty()) {
        // Run file deletion on a thread pool thread — never block the UI for disk IO.
        const int capturedMode = mode;
        QtConcurrent::run([capturedMode, filePath]() {
            // Defence-in-depth: verify the resolved path is a regular file before
            // touching it. QFile::moveToTrash() can trash entire directories on some
            // platforms, so we must never call it (or remove()) on a path that turned
            // out to be a directory — e.g. because filename was empty and the path
            // collapsed to the save directory.
            const QFileInfo fi(filePath);
            if (!fi.exists() || !fi.isFile()) {
                qWarning() << "[Delete] Refusing to delete non-file path:" << filePath;
                return;
            }
            if (capturedMode == 2)
                QFile::moveToTrash(filePath);
            else
                QFile::remove(filePath);
        });
    }
}

void AppController::openFile(const QString &id) {
    auto *item = m_downloadModel->itemById(id);
    if (!item) return;
    if (item->filename().isEmpty()) {
        QDesktopServices::openUrl(QUrl::fromLocalFile(item->savePath()));
        return;
    }
    QDesktopServices::openUrl(QUrl::fromLocalFile(item->savePath() + QStringLiteral("/") + item->filename()));
}

void AppController::openFolder(const QString &id) {
    auto *item = m_downloadModel->itemById(id);
    if (!item) return;
    QDesktopServices::openUrl(QUrl::fromLocalFile(item->savePath()));
}

void AppController::openFolderSelectFile(const QString &id) {
    auto *item = m_downloadModel->itemById(id);
    if (!item) return;

#if defined(STELLAR_WINDOWS)
    // Multi-file torrents are folder targets; selecting "savePath/filename" is often
    // invalid while downloading and can point to a non-existent path.
    if (item->isTorrent() && !item->torrentIsSingleFile()) {
        QDesktopServices::openUrl(QUrl::fromLocalFile(item->savePath()));
        return;
    }

    // If the filename is unknown (e.g. yt-dlp item where metadata wasn't captured),
    // just open the directory so the user isn't sent to the wrong place.
    if (item->filename().isEmpty()) {
        QDesktopServices::openUrl(QUrl::fromLocalFile(item->savePath()));
        return;
    }
    const QString filePath   = item->savePath() + QLatin1Char('/') + item->filename();
    if (!QFileInfo::exists(filePath)) {
        QDesktopServices::openUrl(QUrl::fromLocalFile(item->savePath()));
        return;
    }
    const QString nativePath = QDir::toNativeSeparators(filePath);

    // explorer.exe /select,<path> — use ShellExecuteW so we don't fight Qt's
    // argument-list quoting, which wraps each element in quotes and breaks
    // the /select,path syntax that explorer expects as one token.
    const std::wstring params = (QStringLiteral("/select,\"") + nativePath + QStringLiteral("\"")).toStdWString();
    ShellExecuteW(nullptr, L"open", L"explorer.exe", params.c_str(), nullptr, SW_SHOWNORMAL);

#else
    if (item->filename().isEmpty()) {
        QDesktopServices::openUrl(QUrl::fromLocalFile(item->savePath()));
        return;
    }
    QDesktopServices::openUrl(QUrl::fromLocalFile(item->savePath()));
#endif
}

void AppController::setDownloadUsername(const QString &id, const QString &username) {
    auto *item = m_downloadModel->itemById(id);
    if (item) { item->setUsername(username); scheduleSave(id); }
}

void AppController::setDownloadPassword(const QString &id, const QString &password) {
    auto *item = m_downloadModel->itemById(id);
    if (item) { item->setPassword(password); scheduleSave(id); }
}

void AppController::setDownloadDescription(const QString &id, const QString &description) {
    auto *item = m_downloadModel->itemById(id);
    if (item) { item->setDescription(description); scheduleSave(id); }
}

bool AppController::moveDownloadFile(const QString &id, const QString &newFilePath) {
    auto *item = m_downloadModel->itemById(id);
    if (!item)
        return false;

    if (item->isTorrent()) {
        const QFileInfo newInfo(newFilePath);
        const QString newDir = newInfo.isDir() ? newInfo.absoluteFilePath() : newInfo.absolutePath();
        if (newDir.isEmpty() || !m_torrentSession || !m_torrentSession->moveStorage(id, newDir))
            return false;
        item->setSavePath(newDir);
        scheduleSave(id);
        return true;
    }

    if (item->status() != QStringLiteral("Completed")) return false;

    const QString oldPath = item->savePath() + QStringLiteral("/") + item->filename();
    const QFileInfo newInfo(newFilePath);
    const QString newDir = newInfo.absolutePath();
    const QString newName = newInfo.fileName();

    QDir().mkpath(newDir);
    if (!QFile::rename(oldPath, newFilePath)) {
        QFile src(oldPath);
        QFile dst(newFilePath);
        if (!src.open(QIODevice::ReadOnly) || !dst.open(QIODevice::WriteOnly))
            return false;
        const qint64 kChunk = 1024 * 1024;
        while (!src.atEnd()) {
            const QByteArray chunk = src.read(kChunk);
            if (chunk.isEmpty() && src.error() != QFile::NoError)
                return false;
            if (dst.write(chunk) != chunk.size())
                return false;
        }
        src.close();
        dst.close();
        QFile::remove(oldPath);
    }

    item->setSavePath(newDir);
    item->setFilename(newName);
    scheduleSave(id);
    return true;
}

void AppController::enableSpeedLimiter() {
    int limit = m_settings->savedSpeedLimitKBps();
    if (limit <= 0) limit = 500;
    m_settings->setGlobalSpeedLimitKBps(limit);
}

void AppController::disableSpeedLimiter() {
    const int current = m_settings->globalSpeedLimitKBps();
    if (current > 0) m_settings->setSavedSpeedLimitKBps(current);
    m_settings->setGlobalSpeedLimitKBps(0);
}

void AppController::copyDownloadFilename(const QString &id) {
    auto *item = m_downloadModel->itemById(id);
    if (item) {
        copyToClipboard(item->filename());
    }
}

QVariantList AppController::torrentSpeedHistory(const QString &downloadId, int maxAgeSeconds, int maxPoints) const {
    const auto it = m_torrentSpeedHistory.constFind(downloadId);
    if (it == m_torrentSpeedHistory.constEnd())
        return {};

    const qint64 nowMs  = QDateTime::currentMSecsSinceEpoch();
    const qint64 cutoff = maxAgeSeconds > 0 ? (nowMs - static_cast<qint64>(maxAgeSeconds) * 1000LL) : 0;
    const auto  &series = it.value();

    // Collect the window of samples that fall within the requested age.
    // Avoid materializing a temporary vector when no decimation is needed.
    int firstIdx = 0;
    if (cutoff > 0) {
        while (firstIdx < series.size() && series[firstIdx].timestampMs < cutoff)
            ++firstIdx;
    }
    const int count = series.size() - firstIdx;
    if (count <= 0)
        return {};

    // When maxPoints is 0 or the series already fits, return every sample.
    if (maxPoints <= 0 || count <= maxPoints) {
        QVariantList out;
        out.reserve(count);
        for (int i = firstIdx; i < series.size(); ++i) {
            const TorrentSpeedSample &s = series[i];
            QVariantMap row;
            row.insert(QStringLiteral("t"),    s.timestampMs);
            row.insert(QStringLiteral("down"), s.downBps);
            row.insert(QStringLiteral("up"),   s.upBps);
            out.push_back(std::move(row));
        }
        return out;
    }

    // Pre-decimate to maxPoints buckets using per-bucket averages.
    // Averaging preserves the real throughput shape — peak-only decimation
    // exaggerates spikes and produces a misleadingly jagged curve.
    QVariantList out;
    out.reserve(maxPoints);
    const double step = static_cast<double>(count) / maxPoints;
    for (int bi = 0; bi < maxPoints; ++bi) {
        const int lo  = firstIdx + static_cast<int>(bi * step);
        const int hi  = firstIdx + std::min(count - 1, static_cast<int>((bi + 1) * step) - 1);
        qint64 sumDown = 0, sumUp = 0;
        int n = 0;
        for (int j = lo; j <= hi; ++j) {
            sumDown += series[j].downBps;
            sumUp   += series[j].upBps;
            ++n;
        }
        if (n == 0) continue;
        // Use the midpoint timestamp of the bucket for accurate time positioning.
        const qint64 midT = series[(lo + hi) / 2].timestampMs;
        QVariantMap row;
        row.insert(QStringLiteral("t"),    midT);
        row.insert(QStringLiteral("down"), static_cast<int>(sumDown / n));
        row.insert(QStringLiteral("up"),   static_cast<int>(sumUp   / n));
        out.push_back(std::move(row));
    }
    return out;
}

void AppController::forceReannounceTorrent(const QString &downloadId, const QStringList &trackerUrls) {
    if (m_torrentSession)
        m_torrentSession->forceReannounce(downloadId, trackerUrls);
}

QVariantList AppController::torrentPieceMap(const QString &downloadId) const {
    if (!m_torrentSession)
        return {};
    return m_torrentSession->torrentPieceMap(downloadId);
}

void AppController::clearTorrentSpeedHistory(const QString &downloadId) {
    m_torrentSpeedHistory.remove(downloadId);
}

QVariantMap AppController::torrentAllTimeStats() const {
    // Sum torrentUploaded/torrentDownloaded from all live torrent items in memory,
    // then add the historical accumulator (from previously deleted items).
    qint64 uploaded   = m_settings->torrentHistoricalUploadedBytes();
    qint64 downloaded = m_settings->torrentHistoricalDownloadedBytes();
    const auto items = m_downloadModel->allItems();
    for (auto *item : items) {
        if (item && item->isTorrent()) {
            uploaded   += item->torrentUploaded();
            downloaded += item->torrentDownloaded();
        }
    }
    double ratio = (downloaded > 0) ? (double(uploaded) / double(downloaded)) : 0.0;
    QVariantMap result;
    result[QStringLiteral("uploadedBytes")]   = QVariant::fromValue(uploaded);
    result[QStringLiteral("downloadedBytes")] = QVariant::fromValue(downloaded);
    result[QStringLiteral("ratio")]           = ratio;
    return result;
}

void AppController::resetTorrentAllTimeStats() {
    // Zero out the historical accumulator. Live item stats are part of the session
    // and cannot be reset from here, so we zero the accumulator that persists them
    // across sessions — next call to torrentAllTimeStats() will only reflect live data.
    m_settings->resetTorrentHistoricalStats();
}

QString AppController::downloadShareLink(const QString &id) const {
    auto *item = m_downloadModel->itemById(id);
    if (!item)
        return {};
    if (!item->isTorrent())
        return item->url().toString();

    const QString source = item->torrentSource().trimmed();
    if (source.startsWith(QStringLiteral("magnet:?"), Qt::CaseInsensitive))
        return source;

    const QString infoHash = item->torrentInfoHash().trimmed();
    if (!infoHash.isEmpty())
        return QStringLiteral("magnet:?xt=urn:btih:%1").arg(infoHash.toLower());

    if (!source.isEmpty())
        return source;
    return item->url().toString();
}

bool AppController::exportTorrentFilesToDirectory(const QStringList &downloadIds, const QString &directoryPath) {
    if (downloadIds.isEmpty()) {
        emit errorOccurred(QStringLiteral("No torrents were selected for export."));
        return false;
    }

    QDir outDir(directoryPath.trimmed());
    if (outDir.path().isEmpty()) {
        emit errorOccurred(QStringLiteral("Please select a destination folder."));
        return false;
    }
    if (!outDir.exists() && !QDir().mkpath(outDir.path())) {
        emit errorOccurred(QStringLiteral("Failed to create export folder: %1").arg(outDir.path()));
        return false;
    }

    auto sanitizeBaseName = [](QString name) {
        name = name.trimmed();
        if (name.isEmpty())
            name = QStringLiteral("torrent");
        static const QRegularExpression invalidChars(QStringLiteral(R"([<>:"/\\|?*\x00-\x1f])"));
        name.replace(invalidChars, QStringLiteral("_"));
        while (name.endsWith(QLatin1Char('.')) || name.endsWith(QLatin1Char(' ')))
            name.chop(1);
        if (name.isEmpty())
            name = QStringLiteral("torrent");
        return name;
    };

    QSet<QString> usedNames;
    int exportedCount = 0;
    int torrentCount = 0;

    for (const QString &id : downloadIds) {
        DownloadItem *item = m_downloadModel->itemById(id);
        if (!item || !item->isTorrent())
            continue;
        ++torrentCount;

        QString baseName = sanitizeBaseName(item->filename());
        if (baseName.compare(QStringLiteral("Magnetized transfer"), Qt::CaseInsensitive) == 0
            && !item->torrentInfoHash().trimmed().isEmpty()) {
            baseName = item->torrentInfoHash().trimmed().toLower();
        }

        QString candidate = baseName;
        int suffix = 2;
        while (usedNames.contains(candidate.toLower()) || QFileInfo::exists(outDir.filePath(candidate + QStringLiteral(".torrent")))) {
            candidate = QStringLiteral("%1 (%2)").arg(baseName).arg(suffix++);
        }
        usedNames.insert(candidate.toLower());
        const QString outputPath = outDir.filePath(candidate + QStringLiteral(".torrent"));

        bool exported = false;
        if (m_torrentSession)
            exported = m_torrentSession->exportTorrentFile(id, outputPath);

        if (!exported) {
            const QString sourcePath = item->torrentSource().trimmed();
            if (!sourcePath.startsWith(QStringLiteral("magnet:?"), Qt::CaseInsensitive)
                && QFileInfo::exists(sourcePath)) {
                exported = QFile::copy(sourcePath, outputPath);
            }
        }

        if (exported)
            ++exportedCount;
    }

    if (torrentCount == 0) {
        emit errorOccurred(QStringLiteral("No torrent downloads are selected."));
        return false;
    }
    if (exportedCount == 0) {
        emit errorOccurred(QStringLiteral("Failed to export selected torrents."));
        return false;
    }
    if (exportedCount < torrentCount) {
        emit errorOccurred(QStringLiteral("Exported %1 of %2 torrents. Some torrents may still be loading metadata.").arg(exportedCount).arg(torrentCount));
    }
    return true;
}

QString AppController::updateMetadataUrl() {
    return QStringLiteral("https://ninka-rex.github.io/Stellar/update.json");
}

QString AppController::updateChangelogUrl() {
    return QStringLiteral("https://ninka-rex.github.io/Stellar/changelog.md");
}

void AppController::setCheckingForUpdates(bool checking) {
    if (m_checkingForUpdates == checking)
        return;
    m_checkingForUpdates = checking;
    emit checkingForUpdatesChanged();
}

void AppController::finishUpdateCheckUi(const std::function<void()> &finishWork) {
    const qint64 elapsed = m_updateCheckStartedAt.isValid()
        ? m_updateCheckStartedAt.msecsTo(QDateTime::currentDateTime())
        : kMinimumUpdateCheckIndicatorMs;
    const int remaining = qMax<qint64>(0, kMinimumUpdateCheckIndicatorMs - elapsed);
    QTimer::singleShot(remaining, this, [this, finishWork]() {
        setCheckingForUpdates(false);
        if (finishWork)
            finishWork();
    });
}

int AppController::compareVersionStrings(const QString &lhs, const QString &rhs) {
    QString normalizedLhs = lhs.trimmed();
    QString normalizedRhs = rhs.trimmed();
    normalizedLhs.remove(QRegularExpression(QStringLiteral("[^0-9\\.]")));
    normalizedRhs.remove(QRegularExpression(QStringLiteral("[^0-9\\.]")));
    const QVersionNumber lv = QVersionNumber::fromString(normalizedLhs);
    const QVersionNumber rv = QVersionNumber::fromString(normalizedRhs);
    return QVersionNumber::compare(lv, rv);
}

void AppController::applyUpdateMetadata(const QVariantMap &map, bool manual) {
    const QString version = map.value(QStringLiteral("version")).toString().trimmed();
    cacheIpToCityDbUpdateUrl(map);
    cacheFfmpegUpdateMetadata(map);
    if (version.isEmpty()) {
        return;
    }

    const bool available = compareVersionStrings(version, appVersion()) > 0;
    if (!available) {
        if (m_updateAvailable) {
            m_updateAvailable = false;
            m_updateVersion.clear();
            m_updateInstallerUrl.clear();
            m_updateSha256.clear();
            m_updateLinuxInstallerUrl.clear();
            m_updateLinuxSha256.clear();
            m_updateChangelog.clear();
            emit updateAvailableChanged();
        }
        if (manual)
            emit updateUpToDate();
        return;
    }

    m_updateVersion = version;
    m_updateLinuxInstallerUrl = map.value(QStringLiteral("linuxInstallerUrl")).toString().trimmed();
    m_updateLinuxSha256 = map.value(QStringLiteral("linuxSha256")).toString().trimmed();
    m_updateInstallerUrl = map.value(QStringLiteral("installerUrl")).toString().trimmed();
    m_updateSha256 = map.value(QStringLiteral("sha256")).toString().trimmed();
#if defined(Q_OS_WIN)
    // On Windows, installerUrl/sha256 are canonical.
#else
    if (!m_updateLinuxInstallerUrl.isEmpty())
        m_updateInstallerUrl = m_updateLinuxInstallerUrl;
    if (!m_updateLinuxSha256.isEmpty())
        m_updateSha256 = m_updateLinuxSha256;
#endif
    m_updateAvailable = true;
    emit updateAvailableChanged();

    const bool shouldShowPassiveUi = m_settings->autoCheckUpdates() || manual;
    if (shouldShowPassiveUi) {
        m_updateStatusText = QStringLiteral("🎊 Update available! (%1)").arg(m_updateVersion);
        emit updateStatusTextChanged();
    } else if (!m_updateStatusText.isEmpty()) {
        m_updateStatusText.clear();
        emit updateStatusTextChanged();
    }

    // Always show the changelog dialog when manually triggered, or on Windows for auto-check.
    // On Linux/macOS there's no installer to offer, but the user can still read the changelog.
    if (manual || (m_settings->autoCheckUpdates() && m_settings->skippedUpdateVersion() != m_updateVersion))
        emit updateDialogRequested();
}

void AppController::checkForUpdates(bool manual) {
    if (m_checkingForUpdates)
        return;

    m_updateCheckManual = manual;
    m_updateCheckStartedAt = QDateTime::currentDateTime();
    m_updateStatusText = QStringLiteral("📡 Checking for updates");
    emit updateStatusTextChanged();
    setCheckingForUpdates(true);

    QNetworkRequest request{QUrl(AppController::updateMetadataUrl())};
    request.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("Stellar/%1").arg(appVersion()));
    QNetworkReply *reply = m_nam->get(request);
    connect(reply, &QNetworkReply::finished, this, [this, reply, manual]() {
        const QByteArray payload = reply->readAll();
        const QString networkError = reply->error() == QNetworkReply::NoError ? QString() : reply->errorString();
        reply->deleteLater();

        if (!networkError.isEmpty()) {
            finishUpdateCheckUi([this]() {
                if (!m_settings->autoCheckUpdates())
                    m_updateStatusText.clear();
                else if (m_updateAvailable)
                    m_updateStatusText = QStringLiteral("🎊 Update available! (%1)").arg(m_updateVersion);
                else
                    m_updateStatusText.clear();
                emit updateStatusTextChanged();
            });
            return;
        }

        const QJsonDocument doc = QJsonDocument::fromJson(payload);
        if (!doc.isObject()) {
            finishUpdateCheckUi([this]() {
                if (!m_settings->autoCheckUpdates())
                    m_updateStatusText.clear();
                else if (m_updateAvailable)
                    m_updateStatusText = QStringLiteral("🎊 Update available! (%1)").arg(m_updateVersion);
                else
                    m_updateStatusText.clear();
                emit updateStatusTextChanged();
            });
            return;
        }

        QVariantMap metadata = doc.object().toVariantMap();
        cacheIpToCityDbUpdateUrl(metadata);
        cacheFfmpegUpdateMetadata(metadata);
        const QString version = metadata.value(QStringLiteral("version")).toString().trimmed();
        const bool available = !version.isEmpty() && compareVersionStrings(version, appVersion()) > 0;
        if (!available) {
            if (manual)
                emit updateUpToDate();
            finishUpdateCheckUi([this]() {
                m_updateAvailable = false;
                m_updateVersion.clear();
                m_updateInstallerUrl.clear();
                m_updateSha256.clear();
                m_updateChangelog.clear();
                emit updateAvailableChanged();
                m_updateStatusText.clear();
                emit updateStatusTextChanged();
            });
            return;
        }

        QNetworkRequest changelogRequest{QUrl(AppController::updateChangelogUrl())};
        changelogRequest.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("Stellar/%1").arg(appVersion()));
        QNetworkReply *changelogReply = m_nam->get(changelogRequest);
        connect(changelogReply, &QNetworkReply::finished, this, [this, changelogReply, manual, metadata]() mutable {
            const QString changelogText = changelogReply->error() == QNetworkReply::NoError
                ? QString::fromUtf8(changelogReply->readAll())
                : QString();
            changelogReply->deleteLater();
            metadata[QStringLiteral("changelog")] = changelogText;
            m_updateChangelog = metadata.value(QStringLiteral("changelog")).toString();
            applyUpdateMetadata(metadata, manual);
            finishUpdateCheckUi([this]() {
                if (!m_settings->autoCheckUpdates())
                    m_updateStatusText.clear();
                else if (m_updateAvailable)
                    m_updateStatusText = QStringLiteral("🎊 Update available! (%1)").arg(m_updateVersion);
                else
                    m_updateStatusText.clear();
                emit updateStatusTextChanged();
            });
        });
    });
}

void AppController::applyProxy() {
    const int type = m_settings->proxyType();

    QNetworkProxy proxy;
    bool active = false;

    // Always disable the system-proxy factory first.  If we leave it enabled
    // while also setting an explicit proxy, Qt may ignore the explicit proxy
    // on some platforms (especially Windows with WinHTTP).
    QNetworkProxyFactory::setUseSystemConfiguration(false);

    switch (type) {
    case 1: { // System proxy — query the OS and apply the first result explicitly.
        // We query manually instead of using setUseSystemConfiguration(true) so
        // that the same resolved proxy is set on m_nam directly (see below).
        const QNetworkProxyQuery q(QUrl(QStringLiteral("http://example.com")));
        const QList<QNetworkProxy> list = QNetworkProxyFactory::systemProxyForQuery(q);
        proxy = (!list.isEmpty() && list.first().type() != QNetworkProxy::NoProxy)
                ? list.first()
                : QNetworkProxy(QNetworkProxy::NoProxy);
        active = (proxy.type() != QNetworkProxy::NoProxy);
        break;
    }
    case 2: // HTTP/HTTPS
        proxy.setType(QNetworkProxy::HttpProxy);
        proxy.setHostName(m_settings->proxyHost());
        proxy.setPort(static_cast<quint16>(m_settings->proxyPort()));
        if (!m_settings->proxyUsername().isEmpty()) {
            proxy.setUser(m_settings->proxyUsername());
            proxy.setPassword(m_settings->proxyPassword());
        }
        active = !m_settings->proxyHost().trimmed().isEmpty();
        break;

    case 3: // SOCKS5
        proxy.setType(QNetworkProxy::Socks5Proxy);
        proxy.setHostName(m_settings->proxyHost());
        proxy.setPort(static_cast<quint16>(m_settings->proxyPort()));
        if (!m_settings->proxyUsername().isEmpty()) {
            proxy.setUser(m_settings->proxyUsername());
            proxy.setPassword(m_settings->proxyPassword());
        }
        active = !m_settings->proxyHost().trimmed().isEmpty();
        break;

    default: // None
        proxy.setType(QNetworkProxy::NoProxy);
        active = false;
        break;
    }

    // Set both the application-wide default AND on m_nam directly.
    // QNetworkAccessManager reads the application proxy at request time, not at
    // construction time, so setApplicationProxy is sufficient for most cases —
    // but setting it on the NAM explicitly guarantees it for all Qt versions.
    QNetworkProxy::setApplicationProxy(proxy);
    m_nam->setProxy(proxy);

    // Forward the same proxy settings to libtorrent so peer connections and
    // tracker announces are also routed through the proxy.
    if (m_torrentSession)
        m_torrentSession->applySettings(m_settings);

    if (m_proxyActive != active) {
        m_proxyActive = active;
        emit proxyActiveChanged();
    }

    // Re-fetch the public IP through the newly active proxy so the swarm map
    // shows the correct exit node location.
    fetchPublicIp();
}

void AppController::fetchPublicIp() {
    if (!m_nam || !m_torrentSession)
        return;
    QNetworkRequest request(QUrl(QStringLiteral("https://api.ipify.org?format=text")));
    request.setAttribute(QNetworkRequest::RedirectPolicyAttribute,
                         QNetworkRequest::NoLessSafeRedirectPolicy);
    request.setHeader(QNetworkRequest::UserAgentHeader,
                      QStringLiteral("Stellar/%1").arg(QStringLiteral(STELLAR_VERSION)));
    request.setTransferTimeout(10000);
    QNetworkReply *reply = m_nam->get(request);
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        const QString ip = QString::fromUtf8(reply->readAll()).trimmed();
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError || ip.isEmpty())
            return;
        QNetworkRequest geoRequest(QUrl(QStringLiteral("https://ipwho.is/%1").arg(ip)));
        geoRequest.setAttribute(QNetworkRequest::RedirectPolicyAttribute,
                                QNetworkRequest::NoLessSafeRedirectPolicy);
        geoRequest.setHeader(QNetworkRequest::UserAgentHeader,
                             QStringLiteral("Stellar/%1").arg(QStringLiteral(STELLAR_VERSION)));
        geoRequest.setTransferTimeout(10000);
        QNetworkReply *geoReply = m_nam->get(geoRequest);
        connect(geoReply, &QNetworkReply::finished, this, [this, geoReply, ip]() {
            const QByteArray payload = geoReply->readAll();
            const bool ok = geoReply->error() == QNetworkReply::NoError;
            geoReply->deleteLater();
            if (!ok) {
                m_torrentSession->setDetectedExternalAddress(ip);
                return;
            }
            const QJsonDocument doc = QJsonDocument::fromJson(payload);
            const QJsonObject obj = doc.object();
            const bool success = obj.value(QStringLiteral("success")).toBool(true);
            const double latitude = obj.value(QStringLiteral("latitude")).toDouble();
            const double longitude = obj.value(QStringLiteral("longitude")).toDouble();
            const bool hasCoordinates = success && (latitude != 0.0 || longitude != 0.0);
            m_torrentSession->setDetectedExternalAddress(ip, latitude, longitude, hasCoordinates);
        });
    });
}

void AppController::testProxy() {
    // Use a lightweight HEAD request to github.com to confirm connectivity.
    // We record the wall-clock time before the request and report latency on
    // success so the user has a concrete signal that the proxy is working.
    QNetworkRequest req{QUrl(QStringLiteral("https://github.com"))};
    req.setHeader(QNetworkRequest::UserAgentHeader,
                  QStringLiteral("Stellar/%1").arg(appVersion()));
    req.setAttribute(QNetworkRequest::RedirectPolicyAttribute,
                     QNetworkRequest::NoLessSafeRedirectPolicy);
    req.setTransferTimeout(10000);

    const qint64 startMs = QDateTime::currentMSecsSinceEpoch();
    QNetworkReply *reply = m_nam->head(req);
    connect(reply, &QNetworkReply::finished, this, [this, reply, startMs]() {
        reply->deleteLater();
        const qint64 elapsed = QDateTime::currentMSecsSinceEpoch() - startMs;
        const QNetworkReply::NetworkError err = reply->error();
        if (err == QNetworkReply::NoError
            || reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).isValid()) {
            emit proxyTestResult(true,
                QStringLiteral("Connected — %1 ms").arg(elapsed));
        } else {
            emit proxyTestResult(false, reply->errorString());
        }
    });
}

void AppController::fetchChangelog() {
    // Fetch the changelog unconditionally — used by "What's New" regardless of update state.
    if (!m_updateChangelog.isEmpty())
        return; // already have it
    QNetworkRequest req{QUrl(AppController::updateChangelogUrl())};
    req.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("Stellar/%1").arg(appVersion()));
    QNetworkReply *reply = m_nam->get(req);
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        if (reply->error() == QNetworkReply::NoError) {
            m_updateChangelog = QString::fromUtf8(reply->readAll());
            emit updateAvailableChanged(); // updateChangelog property uses this NOTIFY
        }
        reply->deleteLater();
    });
}

void AppController::dismissAvailableUpdate() {
    if (!m_updateVersion.isEmpty())
        m_settings->setSkippedUpdateVersion(m_updateVersion);
}

bool AppController::startUpdateInstall() {
    if (!m_updateAvailable || m_updateInstallerUrl.trimmed().isEmpty())
        return false;

    // SECURITY: CWE-345 — validate the installer URL host before downloading.
    // The installerUrl value comes from update.json served over HTTPS, but if
    // that JSON were tampered with (DNS hijack, compromised GitHub Pages account,
    // or a redirect to HTTP) an attacker could point it at an arbitrary host.
    // Allowlisting the host to known GitHub domains ensures the installer binary
    // can only ever be fetched from a source we control, even if the JSON itself
    // is served from a compromised location.
    const QUrl installerQUrl(m_updateInstallerUrl);
    const QString installerHost = installerQUrl.host().toLower();
    static const QStringList kAllowedInstallerHosts = {
        QStringLiteral("github.com"),
        QStringLiteral("objects.githubusercontent.com"),
        QStringLiteral("releases.githubusercontent.com"),
        QStringLiteral("ninka-rex.github.io"),
    };
    if (!kAllowedInstallerHosts.contains(installerHost)) {
        qWarning() << "[Update] Rejected installer URL with untrusted host:" << installerHost;
        emit updateError(QStringLiteral("The update server returned an installer URL from an untrusted host (%1). "
                                        "Update aborted for your safety.").arg(installerHost));
        return false;
    }
    if (installerQUrl.scheme().toLower() != QStringLiteral("https")) {
        qWarning() << "[Update] Rejected non-HTTPS installer URL";
        emit updateError(QStringLiteral("The update installer URL must use HTTPS. Update aborted for your safety."));
        return false;
    }

    const QString tempDir = m_settings->temporaryDirectory().trimmed().isEmpty()
        ? (QStandardPaths::writableLocation(QStandardPaths::TempLocation) + QStringLiteral("/Stellar"))
        : m_settings->temporaryDirectory();
    QDir().mkpath(tempDir);

    const QString filename = QFileInfo(QUrl(m_updateInstallerUrl).path()).fileName().isEmpty()
#if defined(Q_OS_WIN)
        ? QStringLiteral("StellarSetup-%1.exe").arg(m_updateVersion)
#else
        ? QStringLiteral("stellar-%1.deb").arg(m_updateVersion)
#endif
        : QFileInfo(QUrl(m_updateInstallerUrl).path()).fileName();

    DownloadItem *item = createDownloadItem(
        m_updateInstallerUrl,
        tempDir,
        QStringLiteral("Other"),
        QStringLiteral("Stellar update installer"),
        true,
        QString(),
        QString(),
        QString(),
        QString(),
        QString(),
        filename,
        QString(),
        false);
    if (!item)
        return false;

    m_pendingUpdateDownloadId = item->id();
    m_pendingUpdateInstallerPath = tempDir + QStringLiteral("/") + filename;
    m_pendingUpdateSha256 = m_updateSha256;
    return true;
}

void AppController::cacheIpToCityDbUpdateUrl(const QVariantMap &map) {
    const QString url = map.value(QStringLiteral("IPtoCityDB")).toString().trimmed();
    if (url == m_ipToCityDbUpdateUrl)
        return;
    m_ipToCityDbUpdateUrl = url;
    emit ipToCityDbUpdateUrlChanged();
    refreshIpToCityDbInfo();
}

void AppController::cacheFfmpegUpdateMetadata(const QVariantMap &map) {
    auto firstNonEmpty = [&map](const QStringList &keys) -> QString {
        for (const QString &key : keys) {
            const QString value = map.value(key).toString().trimmed();
            if (!value.isEmpty())
                return value;
        }
        return {};
    };

#if defined(Q_OS_WIN)
    const QString url = firstNonEmpty({
        QStringLiteral("ffmpegWindowsUrl"),
        QStringLiteral("windowsFfmpegUrl"),
        QStringLiteral("ffmpegUrl")
    });
#else
    const QString url = firstNonEmpty({
        QStringLiteral("ffmpegLinuxUrl"),
        QStringLiteral("linuxFfmpegUrl"),
        QStringLiteral("ffmpegUrl")
    });
#endif

    // Validate scheme and host before caching the URL so updateFfmpegBinary()
    // can never be pointed at untrusted infrastructure.
    QString validatedUrl;
    if (!url.isEmpty()) {
        const QUrl parsedUrl(url);
        const QString host   = parsedUrl.host().toLower();
        const QString scheme = parsedUrl.scheme().toLower();
        static const QStringList kAllowedFfmpegHosts = {
            QStringLiteral("github.com"),
            QStringLiteral("objects.githubusercontent.com"),
            QStringLiteral("releases.githubusercontent.com"),
            QStringLiteral("ninka-rex.github.io"),
            QStringLiteral("www.gyan.dev"),       // canonical Windows FFmpeg builds
            QStringLiteral("evermeet.cx"),        // canonical macOS FFmpeg builds
            QStringLiteral("johnvansickle.com"),  // canonical Linux static FFmpeg builds
        };
        if (scheme != QStringLiteral("https")) {
            qWarning() << "[FFmpegUpdate] Rejected non-HTTPS FFmpeg URL:" << url;
        } else if (!kAllowedFfmpegHosts.contains(host)) {
            qWarning() << "[FFmpegUpdate] Rejected FFmpeg URL with untrusted host:" << host;
        } else {
            validatedUrl = url;
        }
    }

    if (validatedUrl != m_ffmpegUpdateUrl) {
        m_ffmpegUpdateUrl = validatedUrl;
        emit ffmpegUpdateStateChanged();
    }
}

void AppController::refreshIpToCityDbInfo() {
    if (!m_torrentSession)
        return;
    QVariantMap nextInfo = m_torrentSession->geoDatabaseInfo();

    const qulonglong entryCount = nextInfo.value(QStringLiteral("entryCount")).toULongLong();
    nextInfo.insert(QStringLiteral("entryCountFormatted"),
                    entryCount > 0 ? QLocale().toString(entryCount) : QStringLiteral("Unknown"));

    const QString currentVersion = extractDbVersionFromName(QFileInfo(nextInfo.value(QStringLiteral("path")).toString()).fileName());
    const QString latestVersion = extractDbVersionFromName(QFileInfo(QUrl(m_ipToCityDbUpdateUrl).path()).fileName());
    nextInfo.insert(QStringLiteral("currentVersion"), currentVersion);
    nextInfo.insert(QStringLiteral("latestVersion"), latestVersion);
    if (!currentVersion.isEmpty() && !latestVersion.isEmpty()) {
        nextInfo.insert(QStringLiteral("versionStatus"),
                        currentVersion == latestVersion
                            ? QStringLiteral("%1 (up to date)").arg(currentVersion)
                            : QStringLiteral("%1 (latest: %2)").arg(currentVersion, latestVersion));
    } else if (!currentVersion.isEmpty()) {
        nextInfo.insert(QStringLiteral("versionStatus"), currentVersion);
    } else {
        nextInfo.insert(QStringLiteral("versionStatus"), QStringLiteral("Unknown"));
    }

    if (nextInfo == m_ipToCityDbInfo)
        return;
    m_ipToCityDbInfo = nextInfo;
    emit ipToCityDbInfoChanged();
}

void AppController::updateIpToCityDbFromCachedUrl() {
    if (m_ipToCityDbUpdating)
        return;
    if (m_ipToCityDbUpdateUrl.trimmed().isEmpty()) {
        m_ipToCityDbUpdateStatus = QStringLiteral("No IP-to-city DB URL is cached yet. Run Check for updates first.");
        emit ipToCityDbUpdateStateChanged();
        return;
    }

    const QString tempDir = effectiveTemporaryDirectory(m_settings);
    QDir().mkpath(tempDir);

    QString filename = QFileInfo(QUrl(m_ipToCityDbUpdateUrl).path()).fileName();
    if (filename.isEmpty())
        filename = QStringLiteral("dbip-city-lite-2026-04.mmdb.gz");

    DownloadItem *item = createDownloadItem(
        m_ipToCityDbUpdateUrl,
        tempDir,
        QStringLiteral("Other"),
        QStringLiteral("IP-to-city database update"),
        true,
        QString(),
        QString(),
        QString(),
        QString(),
        QString(),
        filename,
        QString(),
        false);
    if (!item) {
        m_ipToCityDbUpdateStatus = QStringLiteral("Could not create download item for IP-to-city DB update.");
        emit ipToCityDbUpdateStateChanged();
        return;
    }

    m_pendingIpToCityDbDownloadId = item->id();
    m_ipToCityDbUpdating = true;
    m_ipToCityDbUpdateStatus = QStringLiteral("Downloading IP-to-city database update...");
    emit ipToCityDbUpdateStateChanged();
}

void AppController::updateFfmpegBinary() {
    if (m_ffmpegUpdating)
        return;
    if (m_ffmpegUpdateUrl.trimmed().isEmpty()) {
        m_ffmpegUpdateStatus = QStringLiteral("No FFmpeg URL is cached yet. Run Check for updates first.");
        emit ffmpegUpdateStateChanged();
        return;
    }

    const QString tempDir = effectiveTemporaryDirectory(m_settings);
    QDir().mkpath(tempDir);

    QString filename = QFileInfo(QUrl(m_ffmpegUpdateUrl).path()).fileName();
    if (filename.isEmpty()) {
#if defined(Q_OS_WIN)
        filename = QStringLiteral("ffmpeg-update.zip");
#else
        filename = QStringLiteral("ffmpeg-update.tar.xz");
#endif
    }

    DownloadItem *item = createDownloadItem(
        m_ffmpegUpdateUrl,
        tempDir,
        QStringLiteral("Other"),
        QStringLiteral("FFmpeg binary update"),
        true,
        QString(),
        QString(),
        QString(),
        QString(),
        QString(),
        filename,
        QString(),
        false);
    if (!item) {
        m_ffmpegUpdateStatus = QStringLiteral("Could not create download item for FFmpeg update.");
        emit ffmpegUpdateStateChanged();
        return;
    }

    m_pendingFfmpegDownloadId = item->id();
    m_ffmpegUpdating = true;
    m_ffmpegUpdateStatus = QStringLiteral("Downloading FFmpeg update...");
    emit ffmpegUpdateStateChanged();
}


QString AppController::appVersion() const { return QStringLiteral(STELLAR_VERSION); }
QString AppController::buildTime()   const { return QStringLiteral(STELLAR_BUILD_TIME); }
QString AppController::buildTimeFormatted() const {
    // Convert UTC build time to Eastern time with natural language format (12-hour)
    // STELLAR_BUILD_TIME format: "2026-04-09 02:28 UTC"
    const QString buildStr = QStringLiteral(STELLAR_BUILD_TIME);
    QDateTime utcTime = QDateTime::fromString(buildStr.left(16), QStringLiteral("yyyy-MM-dd HH:mm"));
    if (!utcTime.isValid()) return buildStr;
    utcTime.setTimeSpec(Qt::UTC);

    // Convert to Eastern Time (ET = UTC - 5, EDT = UTC - 4)
    // For simplicity, assume daylight saving time based on month
    const int month = utcTime.date().month();
    const int offset = (month >= 3 && month <= 10) ? -4 : -5; // EDT or EST
    const QDateTime etTime = utcTime.addSecs(offset * 3600);

    // Format as natural language: "April 8, 2026 5:18 PM Eastern Daylight Time"
    const QString monthName = QLocale().standaloneMonthName(etTime.date().month(), QLocale::LongFormat);
    const QString ampm = etTime.time().hour() < 12 ? QStringLiteral("AM") : QStringLiteral("PM");
    const int hour12 = etTime.time().hour() % 12;
    const int finalHour = (hour12 == 0) ? 12 : hour12;
    const QString tzName = (offset == -4) ? QStringLiteral("EDT") : QStringLiteral("EST");

    return QString(QStringLiteral("%1 %2, %3 %4:%5 %6 %7"))
        .arg(monthName)
        .arg(etTime.date().day())
        .arg(etTime.date().year())
        .arg(finalHour)
        .arg(etTime.time().minute(), 2, 10, QLatin1Char('0'))
        .arg(ampm)
        .arg(tzName);
}
QString AppController::qtVersion()   const { return QString::fromLatin1(qVersion()); }

QString AppController::clipboardUrl() const {
    const QString text = QGuiApplication::clipboard()->text().trimmed();
    if (text.startsWith(QLatin1String("http://")) || text.startsWith(QLatin1String("https://"))
        || text.startsWith(QLatin1String("ftp://"))
        || text.startsWith(QLatin1String("magnet:?"), Qt::CaseInsensitive)
        || isBareTorrentInfoHash(text)) {
        // Only return the first line in case of multi-line clipboard
        return text.split(QLatin1Char('\n')).first().trimmed();
    }
    return {};
}

int AppController::recentErrorDownloads() const {
    const QDateTime cutoff = QDateTime::currentDateTime().addSecs(-300);
    int count = 0;
    for (auto it = m_recentErrorDownloads.constBegin(); it != m_recentErrorDownloads.constEnd(); ++it) {
        if (it.value().isValid() && it.value() >= cutoff)
            ++count;
    }
    return count;
}

QStringList AppController::queueIds() const {
    QStringList ids;
    if (!m_queueModel) return ids;
    for (int i = 0; i < m_queueModel->rowCount(); ++i) {
        Queue *q = m_queueModel->queueAt(i);
        if (q && q->id() != QStringLiteral("download-limits"))
            ids.append(q->id());
    }
    return ids;
}

QStringList AppController::queueNames() const {
    QStringList names;
    if (!m_queueModel) return names;
    for (int i = 0; i < m_queueModel->rowCount(); ++i) {
        Queue *q = m_queueModel->queueAt(i);
        if (q && q->id() != QStringLiteral("download-limits"))
            names.append(q->name());
    }
    return names;
}

void AppController::setDownloadCategory(const QString &downloadId, const QString &categoryId) {
    auto *item = m_downloadModel->itemById(downloadId);
    if (!item) return;
    item->setCategory(categoryId);
    scheduleSave(downloadId);
}

void AppController::setDownloadQueue(const QString &downloadId, const QString &queueId) {
    auto *item = m_downloadModel->itemById(downloadId);
    if (!item) return;
    item->setQueueId(queueId);
    scheduleSave(downloadId);
}

void AppController::moveUpInQueue(const QString &downloadId) {
    m_queue->moveUp(downloadId);
}

void AppController::moveDownInQueue(const QString &downloadId) {
    m_queue->moveDown(downloadId);
}

void AppController::moveFileToDesktop(const QString &id) {
    auto *item = m_downloadModel->itemById(id);
    if (!item) return;

    const QString sourceFile = item->savePath() + QStringLiteral("/") + item->filename();
    const QString desktopPath = QStandardPaths::writableLocation(QStandardPaths::DesktopLocation);
    QString destFile = desktopPath + QStringLiteral("/") + item->filename();

    // If file already exists on desktop, add a number
    if (QFile::exists(destFile)) {
        const QString base = QFileInfo(item->filename()).completeBaseName();
        const QString ext = QFileInfo(item->filename()).suffix();
        const QString dotExt = ext.isEmpty() ? QString{} : QStringLiteral(".") + ext;

        int n = 2;
        while (n < 1000 && QFile::exists(destFile)) {
            destFile = desktopPath + QStringLiteral("/") + base + QStringLiteral(" (") + QString::number(n) + QStringLiteral(")") + dotExt;
            ++n;
        }
    }

    // Copy file to desktop
    if (QFile::copy(sourceFile, destFile)) {
        qDebug() << "File moved to desktop:" << destFile;
    } else {
        qDebug() << "Failed to move file to desktop";
    }
}

QString AppController::generateId() const {
    return QUuid::createUuid().toString(QUuid::WithoutBraces);
}

void AppController::watchItem(DownloadItem *item) {
    // Schedule a debounced save on any meaningful state change
    const QString id = item->id();
    auto sched = [this, id]() { scheduleSave(id); };
    connect(item, &DownloadItem::statusChanged,    this, sched);
    connect(item, &DownloadItem::statusChanged,    this, &AppController::activeDownloadsChanged);
    connect(item, &DownloadItem::totalBytesChanged, this, sched);
    connect(item, &DownloadItem::doneBytesChanged,  this, sched);
    connect(item, &DownloadItem::resumeCapableChanged, this, sched);
    connect(item, &DownloadItem::savePathChanged,   this, sched);
    connect(item, &DownloadItem::filenameChanged,   this, sched);
    connect(item, &DownloadItem::torrentChanged,    this, sched);
    connect(item, &DownloadItem::torrentStatsChanged, this, sched);
    connect(item, &DownloadItem::doneBytesChanged, this, [this, item]() {
        if (item && !item->queueId().isEmpty())
            enforceQueueDownloadLimits(item->queueId());
    });
    connect(item, &DownloadItem::doneBytesChanged, this, [this, item, id]() {
        if (!item)
            return;
        if (item->statusEnum() != DownloadItem::Status::Downloading
            && item->statusEnum() != DownloadItem::Status::Assembling)
            return;

        const qint64 currentBytes = item->doneBytes();
        const qint64 lastBytes = m_lastProgressPersistBytes.value(id, -1);
        const QDateTime now = QDateTime::currentDateTimeUtc();
        const QDateTime lastAt = m_lastProgressPersistAt.value(id);

        const bool crossedByteThreshold = lastBytes < 0 || (currentBytes - lastBytes) >= (4ll * 1024 * 1024);
        const bool crossedTimeThreshold = !lastAt.isValid() || lastAt.msecsTo(now) >= 2000;
        if (!crossedByteThreshold && !crossedTimeThreshold)
            return;

        m_db->save(item);
        m_dirtyIds.remove(id);
        m_lastProgressPersistBytes[id] = currentBytes;
        m_lastProgressPersistAt[id] = now;
    });
    connect(item, &DownloadItem::queueIdChanged, this, [this, item]() {
        if (item)
            enforceQueueDownloadLimits(item->queueId());
    });
    connect(item, &DownloadItem::statusChanged, this, [this, item, id]() {
        if (item && item->statusEnum() != DownloadItem::Status::Error) {
            if (m_recentErrorDownloads.remove(id) > 0)
                emit recentErrorDownloadsChanged();
        }
        if (!item || item->statusEnum() == DownloadItem::Status::Completed
            || item->statusEnum() == DownloadItem::Status::Error
            || item->statusEnum() == DownloadItem::Status::Paused) {
            m_lastProgressPersistBytes.remove(id);
            m_lastProgressPersistAt.remove(id);
        }
    });
}

void AppController::pruneRecentErrorDownloads() {
    const QDateTime cutoff = QDateTime::currentDateTime().addSecs(-300);
    bool changed = false;
    for (auto it = m_recentErrorDownloads.begin(); it != m_recentErrorDownloads.end(); ) {
        if (!it.value().isValid() || it.value() < cutoff) {
            it = m_recentErrorDownloads.erase(it);
            changed = true;
        } else {
            ++it;
        }
    }
    if (changed)
        emit recentErrorDownloadsChanged();
}

void AppController::scheduleSave(const QString &id) {
    m_dirtyIds.insert(id);
    if (!m_saveTimer->isActive())
        m_saveTimer->start();
}

void AppController::flushDirty() {
    const auto items = m_queue->items();
    for (DownloadItem *item : items) {
        if (m_dirtyIds.contains(item->id())) {
            if (item->isTorrent())
                m_torrentSession->saveResumeData(item->id());
            m_db->save(item);
        }
    }
    m_dirtyIds.clear();
}

void AppController::cleanupTemporaryDirectory()
{
    const QString tempDirPath = effectiveTemporaryDirectory(m_settings);
    if (tempDirPath.isEmpty())
        return;

    QDir tempDir(tempDirPath);
    if (!tempDir.exists())
        return;

    QSet<QString> activePaths;
    for (DownloadItem *item : m_queue->items()) {
        if (!item)
            continue;
        if (item->filename().trimmed().isEmpty())
            continue;
        if (item->statusEnum() == DownloadItem::Status::Completed
            || item->statusEnum() == DownloadItem::Status::Error)
            continue;
        const QString baseName = tempDir.absoluteFilePath(item->filename());
        activePaths.insert(baseName + QStringLiteral(".stellar-meta"));
        for (int i = 0; i < 32; ++i)
            activePaths.insert(baseName + QStringLiteral(".stellar-part-") + QString::number(i));
    }

    const QFileInfoList entries = tempDir.entryInfoList(QDir::Files | QDir::NoDotAndDotDot);
    for (const QFileInfo &entry : entries) {
        const QString filePath = entry.absoluteFilePath();
        const QString fileName = entry.fileName();
        const bool isStellarTemp = fileName.contains(QStringLiteral(".stellar-part-"))
            || fileName.endsWith(QStringLiteral(".stellar-meta"))
            || fileName.endsWith(QStringLiteral(".stellar-pending"));
        if (!isStellarTemp)
            continue;
        if (activePaths.contains(filePath))
            continue;
        QFile::remove(filePath);
    }
}

bool AppController::canStartDownloadItem(DownloadItem *item) const
{
    if (!item)
        return false;

    const QString queueId = item->queueId();
    if (queueId.isEmpty())
        return true;

    Queue *queue = m_queueModel ? m_queueModel->queueById(queueId) : nullptr;
    if (!queue || queue->id() == QStringLiteral("download-limits"))
        return true;

    int activeForQueue = 0;
    for (DownloadItem *candidate : m_queue->items()) {
        if (!candidate || candidate->queueId() != queueId)
            continue;
        if (candidate->statusEnum() == DownloadItem::Status::Downloading
            || candidate->statusEnum() == DownloadItem::Status::Assembling) {
            ++activeForQueue;
        }
    }
    if (queue->maxConcurrentDownloads() > 0 && activeForQueue >= queue->maxConcurrentDownloads())
        return false;

    if (queue->hasDownloadLimits()) {
        const qint64 limitBytes = static_cast<qint64>(queue->downloadLimitMBytes()) * 1024 * 1024;
        if (limitBytes > 0 && queueTransferredBytesInWindow(queueId, queue->downloadLimitHours()) >= limitBytes)
            return false;
    }

    return true;
}

void AppController::pruneQueueTransferHistory(const QString &queueId, int hours) const
{
    if (queueId.isEmpty() || hours <= 0 || !m_queueTransferHistory.contains(queueId))
        return;

    const QDateTime cutoff = QDateTime::currentDateTime().addSecs(-hours * 3600);
    auto &entries = m_queueTransferHistory[queueId];
    while (!entries.isEmpty() && entries.front().first < cutoff)
        entries.removeFirst();
}

qint64 AppController::queueTransferredBytesInWindow(const QString &queueId, int hours) const
{
    if (queueId.isEmpty() || hours <= 0)
        return 0;

    pruneQueueTransferHistory(queueId, hours);

    qint64 total = 0;
    const auto history = m_queueTransferHistory.value(queueId);
    for (const auto &entry : history)
        total += entry.second;

    for (DownloadItem *item : m_queue->items()) {
        if (!item || item->queueId() != queueId)
            continue;
        if (item->statusEnum() == DownloadItem::Status::Completed
            || item->statusEnum() == DownloadItem::Status::Error)
            continue;
        total += item->doneBytes();
    }

    return total;
}

void AppController::recordQueueTransferSample(const QString &queueId, qint64 bytes)
{
    if (queueId.isEmpty() || bytes <= 0)
        return;

    m_queueTransferHistory[queueId].append(qMakePair(QDateTime::currentDateTime(), bytes));
}

void AppController::enforceQueueDownloadLimits(const QString &queueId)
{
    if (queueId.isEmpty() || !m_queueModel)
        return;

    Queue *queue = m_queueModel->queueById(queueId);
    if (!queue || !queue->hasDownloadLimits() || queue->downloadLimitHours() <= 0) {
        m_queueLimitNotifications.remove(queueId);
        return;
    }

    const qint64 limitBytes = static_cast<qint64>(queue->downloadLimitMBytes()) * 1024 * 1024;
    if (limitBytes <= 0) {
        m_queueLimitNotifications.remove(queueId);
        return;
    }

    const qint64 usedBytes = queueTransferredBytesInWindow(queueId, queue->downloadLimitHours());
    if (usedBytes < limitBytes) {
        m_queueLimitNotifications.remove(queueId);
        return;
    }

    stopQueue(queueId);

    if (!m_queueLimitNotifications.contains(queueId)) {
        m_queueLimitNotifications.insert(queueId);
        const QString message = QStringLiteral("%1 reached its %2 MB / %3 hour limit.")
            .arg(queue->name())
            .arg(queue->downloadLimitMBytes())
            .arg(queue->downloadLimitHours());
        if (queue->warnBeforeStopping() && m_tray)
            m_tray->showNotification(QStringLiteral("Queue Limit Reached"), message);
        else
            qDebug() << "[QueueLimit]" << message;
    }
}

QVariantMap AppController::grabberProjectData(const QString &projectId) const
{
    return m_grabberProjectModel ? m_grabberProjectModel->projectDataById(projectId) : QVariantMap{};
}

bool AppController::isGrabberProjectId(const QString &projectId) const
{
    if (!m_grabberProjectModel || projectId.isEmpty())
        return false;
    return !m_grabberProjectModel->projectDataById(projectId).isEmpty();
}

QString AppController::saveGrabberProject(const QVariantMap &projectMap)
{
    if (!m_grabberProjectModel)
        return {};

    QVariantMap copy = projectMap;
    if (copy.value(QStringLiteral("statusText")).toString().isEmpty())
        copy[QStringLiteral("statusText")] = QStringLiteral("Ready");
    return m_grabberProjectModel->upsertProject(copy);
}

void AppController::deleteGrabberProject(const QString &projectId)
{
    if (!m_grabberProjectModel || projectId.isEmpty())
        return;

    m_grabberProjectModel->removeProject(projectId);

    // Reassign existing downloads to "all" semantics once their project bucket
    // disappears, so filtering never points at a dangling project id.
    for (DownloadItem *item : m_downloadModel->allItems()) {
        if (item && item->category() == projectId) {
            item->setCategory(QStringLiteral("all"));
            scheduleSave(item->id());
        }
    }
}

void AppController::runGrabber(const QVariantMap &projectMap)
{
    if (!m_grabberCrawler || !m_grabberProjectModel)
        return;

    QVariantMap copy = projectMap;
    const QString projectId = saveGrabberProject(copy);
    m_activeGrabberProjectId = projectId;
    m_grabberPagesProcessed = 0;
    m_grabberAdvancedPagesProcessed = 0;
    m_grabberMatchedFiles = 0;
    m_grabberBusy = true;
    emit grabberBusyChanged();
    m_grabberStatusText = QStringLiteral("Starting crawl...");
    emit grabberStatusTextChanged();
    m_grabberResultModel->setResults({});
    copy[QStringLiteral("id")] = projectId;
    m_grabberCrawler->start(copy);
}

void AppController::cancelGrabber()
{
    if (!m_grabberCrawler || !m_grabberBusy)
        return;

    m_grabberCrawler->cancel();
    m_grabberBusy = false;
    emit grabberBusyChanged();
    m_grabberStatusText = QStringLiteral("Grabber cancelled");
    emit grabberStatusTextChanged();
}

void AppController::setGrabberResultChecked(int row, bool checked)
{
    if (m_grabberResultModel) {
        m_grabberResultModel->setChecked(row, checked);
        scheduleGrabberResultsPersist();
    }
}

void AppController::setAllGrabberResultsChecked(bool checked)
{
    if (m_grabberResultModel) {
        m_grabberResultModel->setAllChecked(checked);
        scheduleGrabberResultsPersist();
    }
}

int AppController::checkedGrabberResultCount() const
{
    return m_grabberResultModel ? m_grabberResultModel->checkedCount() : 0;
}

void AppController::sortGrabberResults(const QString &column, bool ascending)
{
    if (!m_grabberResultModel)
        return;

    m_grabberResultModel->sortBy(column,
                                 ascending ? Qt::AscendingOrder : Qt::DescendingOrder);
    scheduleGrabberResultsPersist();
}

void AppController::scheduleGrabberResultsPersist()
{
    if (!m_grabberPersistTimer)
        return;
    m_grabberPersistTimer->start();
}

void AppController::persistActiveGrabberResults()
{
    if (!m_grabberProjectModel || !m_grabberResultModel || m_activeGrabberProjectId.isEmpty())
        return;

    QVariantMap project = m_grabberProjectModel->projectDataById(m_activeGrabberProjectId);
    if (project.isEmpty())
        return;

    // Keep the latest results and check-state with the project so scheduled
    // actions and reopened Grabber sessions can reuse the same selection.
    project[QStringLiteral("lastResults")] = m_grabberResultModel->allResults();
    project[QStringLiteral("lastResultCount")] = m_grabberResultModel->rowCount();
    m_grabberProjectModel->upsertProject(project);
}

void AppController::loadGrabberProjectResults(const QString &projectId)
{
    if (!m_grabberResultModel || !m_grabberProjectModel || projectId.isEmpty())
        return;

    const QVariantMap project = m_grabberProjectModel->projectDataById(projectId);
    const QVariantList savedResults = project.value(QStringLiteral("lastResults")).toList();
    m_activeGrabberProjectId = projectId;
    m_grabberResultModel->setResults(savedResults);
    m_grabberMatchedFiles = savedResults.size();
}

QString AppController::resolveGrabberSaveDirectory(const QVariantMap &project,
                                                   const QUrl &url,
                                                   const QString &filename,
                                                   QString *resolvedCategory) const
{
    // Grabber projects can choose a save destination strategy independently of
    // the category bucket used for sidebar grouping.
    const QString saveMode = project.value(QStringLiteral("saveMode"), QStringLiteral("directory")).toString();
    QString categoryId = project.value(QStringLiteral("projectCategoryId")).toString();
    QString targetDir = project.value(QStringLiteral("savePath")).toString().trimmed();

    if (saveMode == QStringLiteral("byCategory")) {
        categoryId = m_categoryModel->categoryForUrl(url, filename);
        targetDir = m_categoryModel->savePathForCategory(categoryId);
    } else if (saveMode == QStringLiteral("selectedCategory")) {
        categoryId = project.value(QStringLiteral("selectedCategoryId")).toString();
        if (categoryId.isEmpty())
            categoryId = QStringLiteral("all");
        targetDir = m_categoryModel->savePathForCategory(categoryId);
    }

    if (targetDir.isEmpty())
        targetDir = QStandardPaths::writableLocation(QStandardPaths::DownloadLocation);

    if (project.value(QStringLiteral("useRelativeSubfolders")).toBool()) {
        QString relativePath = QFileInfo(url.path()).path();
        relativePath.remove(QRegularExpression(QStringLiteral("^/+")));
        if (!relativePath.isEmpty() && relativePath != QStringLiteral(".")) {
            targetDir = QDir(targetDir).filePath(relativePath);
            QDir().mkpath(targetDir);
        }
    }

    if (resolvedCategory)
        *resolvedCategory = categoryId;
    return targetDir;
}

void AppController::downloadGrabberResults(const QString &projectId, bool startNow, const QString &queueId)
{
    if (!m_grabberResultModel)
        return;

    const QVariantMap project = grabberProjectData(projectId);
    QVariantList checked = m_grabberResultModel->checkedResults();
    if (checked.isEmpty()) {
        const QVariantList savedResults = project.value(QStringLiteral("lastResults")).toList();
        for (const QVariant &value : savedResults) {
            const QVariantMap result = value.toMap();
            if (result.value(QStringLiteral("checked"), true).toBool())
                checked.append(result);
        }
    }
    for (const QVariant &value : checked) {
        const QVariantMap result = value.toMap();
        const QString urlString = result.value(QStringLiteral("url")).toString();
        const QString filename = result.value(QStringLiteral("filename")).toString();
        if (urlString.isEmpty())
            continue;

        const QUrl url = QUrl::fromUserInput(urlString);
        QString ignoredResolvedCategory;
        const QString saveDir = resolveGrabberSaveDirectory(project, url, filename, &ignoredResolvedCategory);
        QString finalFilename = filename;
        if (!project.value(QStringLiteral("overwriteExistingFiles")).toBool()) {
            const QFileInfo info(filename);
            const QString base = info.completeBaseName();
            const QString ext = info.suffix().isEmpty() ? QString() : QStringLiteral(".") + info.suffix();
            int suffix = 1;
            while (QFile::exists(QDir(saveDir).filePath(finalFilename))) {
                finalFilename = QStringLiteral("%1_%2%3").arg(base).arg(suffix).arg(ext);
                ++suffix;
            }
        }
        // Grabber projects intentionally keep their own category bucket so the
        // sidebar can show "project folders" independent of normal file-type categories.
        addUrl(urlString, saveDir, projectId, project.value(QStringLiteral("comment")).toString(),
               startNow, {}, {}, {}, {}, {}, finalFilename, queueId);
    }

    if (!projectId.isEmpty() && m_grabberProjectModel) {
        m_grabberProjectModel->updateProjectRunState(
            projectId,
            QStringLiteral("Added %1 downloads").arg(checked.size()),
            m_grabberResultModel->rowCount());
    }
}

void AppController::stopGrabberResultDownloads(const QString &projectId)
{
    if (!m_grabberResultModel)
        return;

    QVariantList checked = m_grabberResultModel->checkedResults();
    if (checked.isEmpty()) {
        const QVariantMap project = grabberProjectData(projectId);
        const QVariantList savedResults = project.value(QStringLiteral("lastResults")).toList();
        for (const QVariant &value : savedResults) {
            const QVariantMap result = value.toMap();
            if (result.value(QStringLiteral("checked"), true).toBool())
                checked.append(result);
        }
    }
    for (const QVariant &value : checked) {
        const QString urlString = value.toMap().value(QStringLiteral("url")).toString();
        if (urlString.isEmpty())
            continue;
        DownloadItem *item = m_downloadModel->itemByUrl(QUrl::fromUserInput(urlString));
        if (item && item->category() == projectId)
            pauseDownload(item->id());
    }
}

QVariantMap AppController::grabberStatistics(const QString &projectId) const
{
    const QVariantMap project = grabberProjectData(projectId);
    const QVariantList savedResults = project.value(QStringLiteral("lastResults")).toList();
    int downloaded = 0;
    int totalForProject = 0;
    for (DownloadItem *item : m_downloadModel->allItems()) {
        if (!item || item->category() != projectId)
            continue;
        ++totalForProject;
        if (item->status() == QStringLiteral("Completed"))
            ++downloaded;
    }

    return QVariantMap{
        { QStringLiteral("status"), m_grabberBusy ? m_grabberStatusText : QStringLiteral("Idle") },
        { QStringLiteral("webPagesProcessed"), m_grabberPagesProcessed },
        { QStringLiteral("advancedPagesProcessed"), m_grabberAdvancedPagesProcessed },
        { QStringLiteral("filesTotal"), savedResults.size() },
        { QStringLiteral("filesExplored"), savedResults.size() },
        { QStringLiteral("filesMatched"), m_grabberMatchedFiles },
        { QStringLiteral("filesDownloaded"), downloaded },
        { QStringLiteral("projectDownloads"), totalForProject }
    };
}

void AppController::saveGrabberProjectSchedule(const QString &projectId, const QVariantMap &scheduleMap)
{
    if (!m_grabberProjectModel || projectId.isEmpty())
        return;

    QVariantMap project = m_grabberProjectModel->projectDataById(projectId);
    if (project.isEmpty())
        return;
    project[QStringLiteral("schedule")] = scheduleMap;
    m_grabberProjectModel->upsertProject(project);
}

QString AppController::readTextResource(const QString &path) const
{
    QString resolvedPath = path;
    if (resolvedPath.startsWith(QStringLiteral("qrc:/")))
        resolvedPath = QStringLiteral(":") + resolvedPath.mid(4);

    QFile file(resolvedPath);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        if (resolvedPath == QStringLiteral(":/qt/qml/com/stellar/app/tips.txt")
            || resolvedPath == QStringLiteral(":/tips.txt")) {
            const QString localPath = QCoreApplication::applicationDirPath()
                + QDir::separator()
                + QStringLiteral("tips.txt");
            file.setFileName(localPath);
        }
    }

    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        return QString();

    return QString::fromUtf8(file.readAll());
}

void AppController::createQueue(const QString &name)
{
    if (name.trimmed().isEmpty()) return;
    QString queueId = QStringLiteral("queue-") + QString::number(QDateTime::currentMSecsSinceEpoch());
    Queue *q = new Queue(queueId, this);
    q->setName(name);
    q->setIsDownloadQueue(true);
    m_queueModel->addQueue(q);
    m_queueDb->save(q);
}

void AppController::deleteQueue(const QString &queueId)
{
    if (queueId == QStringLiteral("main-download")) return; // protect main queue
    // Remove all downloads from this queue so they're unqueued
    for (auto *item : m_downloadModel->allItems()) {
        if (item && item->queueId() == queueId) {
            item->setQueueId("");
        }
    }
    m_queueDb->remove(queueId);
    m_queueModel->removeQueue(queueId);
}

void AppController::saveQueues()
{
    for (int i = 0; i < m_queueModel->rowCount(); ++i) {
        Queue *q = m_queueModel->queueAt(i);
        if (q) m_queueDb->save(q);
    }
    m_queueDb->flush();
}

void AppController::startQueue(const QString &queueId)
{
    Queue *q = m_queueModel->queueById(queueId);
    if (!q || queueId == QStringLiteral("download-limits")) return;

    // Mark as recently run for periodic schedules
    m_lastQueueRun[queueId] = QDateTime::currentDateTime();

    // Resume torrent items explicitly via TorrentSessionManager; non-torrent items
    // are moved to Queued and started by DownloadQueue::scheduleNext().
    int queuedCount = 0;
    for (DownloadItem *item : m_queue->items()) {
        if (!item || item->queueId() != queueId)
            continue;
        const bool pausedOrQueued = item->status() == QStringLiteral("Paused")
            || item->status() == QStringLiteral("Queued");
        if (!pausedOrQueued)
            continue;

        if (item->isTorrent()) {
            if (canStartDownloadItem(item))
                resumeDownload(item->id());
            continue;
        }

        if (item->status() != QStringLiteral("Queued"))
            item->setStatus(DownloadItem::Status::Queued);
        ++queuedCount;
    }

    // Now trigger scheduleNext to start up to maxConcurrent downloads
    m_queue->scheduleNext();

    qDebug() << "Starting queue" << queueId << q->name() << "- queued" << queuedCount << "downloads";
}

void AppController::setTrayTooltip(const QString &tip) {
    if (m_tray) m_tray->setToolTip(tip);
}

void AppController::stopQueue(const QString &queueId)
{
    Queue *q = m_queueModel->queueById(queueId);
    if (!q || queueId == QStringLiteral("download-limits")) return;

    // Pause all active/queued items in this queue through the unified pause path.
    // For torrents this is required so libtorrent is paused as well.
    int stoppedCount = 0;
    for (DownloadItem *item : m_queue->items()) {
        if (!item || item->queueId() != queueId)
            continue;
        const QString status = item->status();
        if (status == QStringLiteral("Downloading")
                || status == QStringLiteral("Queued")
                || status == QStringLiteral("Checking")
                || status == QStringLiteral("Moving")
                || status == QStringLiteral("Seeding")) {
            pauseDownload(item->id());
            ++stoppedCount;
        }
    }

    qDebug() << "Stopping queue" << queueId << q->name() << "- paused" << stoppedCount << "downloads";
}

bool AppController::shutdownComputer() const
{
#if defined(Q_OS_WIN)
    return QProcess::startDetached(QStringLiteral("shutdown"),
                                   { QStringLiteral("/s"), QStringLiteral("/t"), QStringLiteral("0") });
#elif defined(Q_OS_LINUX)
    if (QProcess::startDetached(QStringLiteral("systemctl"),
                                { QStringLiteral("poweroff") })) {
        return true;
    }
    return QProcess::startDetached(QStringLiteral("shutdown"),
                                   { QStringLiteral("-h"), QStringLiteral("now") });
#else
    return false;
#endif
}

int AppController::minutesUntilNextQueue() const
{
    return calculateMinutesUntilNextQueue();
}

int AppController::calculateMinutesUntilNextQueue() const
{
    int minutesMin = 999999;

    for (int i = 0; i < m_queueModel->rowCount(); ++i) {
        Queue *q = m_queueModel->queueAt(i);
        if (!q || q->id() == QStringLiteral("download-limits"))
            continue;

        // Check if this queue has a start time configured
        if (!q->hasStartTime())
            continue;

        // Try both HH:mm and HH:mm:ss AM/PM formats
        QTime scheduleTime = QTime::fromString(q->startTime(), QStringLiteral("HH:mm:ss AP"));
        if (!scheduleTime.isValid()) {
            scheduleTime = QTime::fromString(q->startTime(), QStringLiteral("HH:mm"));
        }
        if (!scheduleTime.isValid()) {
            continue;
        }

        QDateTime now = QDateTime::currentDateTime();
        QDateTime nextRun;

        if (q->startOnce()) {
            // One-time schedule: next run is today at the specified time
            nextRun = QDateTime(now.date(), scheduleTime);
            if (nextRun <= now) {
                // Time has passed today, no more runs for this queue
                continue;
            }
        } else if (q->startDaily()) {
            // Daily schedule: check if today is in the startDays list
            QStringList days = q->startDays();
            QString todayName = now.toString(QStringLiteral("dddd")).toLower();
            QString dayAbbrev = todayName.left(3).toLower();  // "mon", "tue", etc.

            bool shouldRunToday = false;
            for (const QString &day : days) {
                if (day.toLower().startsWith(dayAbbrev)) {
                    shouldRunToday = true;
                    break;
                }
            }

            if (shouldRunToday) {
                nextRun = QDateTime(now.date(), scheduleTime);
                if (nextRun <= now) {
                    // Time has passed today, check tomorrow
                    nextRun = nextRun.addDays(1);
                    // Check if tomorrow is in the schedule
                    QString tomorrowName = nextRun.toString(QStringLiteral("dddd")).toLower();
                    QString tomorrowAbbrev = tomorrowName.left(3).toLower();
                    bool tomorrowIsScheduled = false;
                    for (const QString &day : days) {
                        if (day.toLower().startsWith(tomorrowAbbrev)) {
                            tomorrowIsScheduled = true;
                            break;
                        }
                    }
                    if (!tomorrowIsScheduled)
                        continue;
                }
            } else {
                // Today is not a scheduled day, find next scheduled day
                for (int d = 1; d <= 7; ++d) {
                    QDateTime candidate = now.addDays(d);
                    QString dayName = candidate.toString(QStringLiteral("dddd")).toLower();
                    QString dayAbb = dayName.left(3).toLower();
                    bool isScheduled = false;
                    for (const QString &day : days) {
                        if (day.toLower().startsWith(dayAbb)) {
                            isScheduled = true;
                            break;
                        }
                    }
                    if (isScheduled) {
                        nextRun = QDateTime(candidate.date(), scheduleTime);
                        break;
                    }
                }
                if (!nextRun.isValid())
                    continue;
            }
        } else {
            // Periodic schedule (synchronization queue)
            if (!q->hasStartAgainEvery())
                continue;

            int intervalSecs = q->startAgainEveryHours() * 3600 + q->startAgainEveryMins() * 60;
            if (intervalSecs <= 0)
                continue;

            // Get last run time or use now if never run
            QDateTime lastRun = m_lastQueueRun.value(q->id(), now.addSecs(-intervalSecs));
            nextRun = lastRun.addSecs(intervalSecs);

            if (nextRun <= now) {
                // Time to run this periodic queue now
                minutesMin = 0;
                continue;
            }
        }

        // Calculate minutes until this queue should run
        if (nextRun.isValid()) {
            int mins = now.secsTo(nextRun) / 60;
            if (mins >= 0 && mins < minutesMin)
                minutesMin = mins;
        }
    }

    return minutesMin == 999999 ? 0 : minutesMin;
}

void AppController::checkQueueSchedules()
{
    int prevMinutes = calculateMinutesUntilNextQueue();

    QDateTime now = QDateTime::currentDateTime();

    for (int i = 0; i < m_queueModel->rowCount(); ++i) {
        Queue *q = m_queueModel->queueAt(i);
        if (!q || q->id() == QStringLiteral("download-limits"))
            continue;

        if (!q->hasStartTime())
            continue;

        // Try both HH:mm:ss AM/PM and HH:mm formats
        QTime scheduleTime = QTime::fromString(q->startTime(), QStringLiteral("HH:mm:ss AP"));
        if (!scheduleTime.isValid()) {
            scheduleTime = QTime::fromString(q->startTime(), QStringLiteral("HH:mm"));
        }
        if (!scheduleTime.isValid())
            continue;

        bool shouldStart = false;

        if (q->startOnce()) {
            // One-time schedule
            QDateTime nextRun = QDateTime(now.date(), scheduleTime);
            // Allow a 5-minute window (2.5 before and after)
            if (nextRun >= now.addSecs(-300) && nextRun <= now.addSecs(300)) {
                shouldStart = true;
            }
        } else if (q->startDaily()) {
            // Daily schedule: check if today is in the list
            QStringList days = q->startDays();
            QString todayName = now.toString(QStringLiteral("dddd")).toLower();
            QString dayAbbrev = todayName.left(3).toLower();

            bool isDayMatch = false;
            for (const QString &day : days) {
                if (day.toLower().startsWith(dayAbbrev)) {
                    isDayMatch = true;
                    break;
                }
            }

            if (isDayMatch) {
                int nowMins = now.time().hour() * 60 + now.time().minute();
                int scheduleMins = scheduleTime.hour() * 60 + scheduleTime.minute();
                // Start if within 5 minutes of scheduled time (wider tolerance for missed checks)
                if (qAbs(nowMins - scheduleMins) <= 2) {
                    shouldStart = true;
                }
            }
        } else {
            // Periodic (synchronization queue)
            if (!q->hasStartAgainEvery())
                continue;

            int intervalSecs = q->startAgainEveryHours() * 3600 + q->startAgainEveryMins() * 60;
            if (intervalSecs <= 0)
                continue;

            QDateTime lastRun = m_lastQueueRun.value(q->id(), now.addSecs(-intervalSecs - 300));
            QDateTime nextRun = lastRun.addSecs(intervalSecs);

            if (nextRun <= now && now.secsTo(nextRun) > -300) {
                shouldStart = true;
            }
        }

        if (shouldStart) {
            startQueue(q->id());
        }

        // Check if queue should stop
        if (q->hasStopTime()) {
            QTime stopTime = QTime::fromString(q->stopTime(), QStringLiteral("HH:mm"));
            if (stopTime.isValid()) {
                int nowMins = now.time().hour() * 60 + now.time().minute();
                int stopMins = stopTime.hour() * 60 + stopTime.minute();
                if (qAbs(nowMins - stopMins) <= 2) {
                    stopQueue(q->id());
                }
            }
        }
    }

    if (m_grabberProjectModel && !m_grabberBusy) {
        const QDateTime now = QDateTime::currentDateTime();
        for (const GrabberProject &project : m_grabberProjectModel->projects()) {
            const QVariantMap projectMap = project.config.toVariantMap();
            const QVariantMap schedule = projectMap.value(QStringLiteral("schedule")).toMap();
            if (!schedule.value(QStringLiteral("enabled")).toBool())
                continue;

            const QString mode = schedule.value(QStringLiteral("mode"), QStringLiteral("once")).toString();
            const QTime startTime = QTime::fromString(schedule.value(QStringLiteral("startTime")).toString(), QStringLiteral("hh:mm AP"));
            if (!startTime.isValid())
                continue;

            const QDateTime lastRun = QDateTime::fromString(projectMap.value(QStringLiteral("lastScheduledRunAt")).toString(), Qt::ISODate);
            bool shouldRun = false;

            if (mode == QStringLiteral("periodic")) {
                const int everyHours = schedule.value(QStringLiteral("everyHours"), 2).toInt();
                const int everyMinutes = schedule.value(QStringLiteral("everyMinutes"), 0).toInt();
                const int intervalSecs = everyHours * 3600 + everyMinutes * 60;
                if (intervalSecs > 0) {
                    const QDateTime effectiveLastRun = lastRun.isValid() ? lastRun : now.addSecs(-intervalSecs - 60);
                    shouldRun = effectiveLastRun.secsTo(now) >= intervalSecs;
                }
            } else {
                QDateTime scheduled = QDateTime(now.date(), startTime);
                if (scheduled > now)
                    continue;

                if (mode == QStringLiteral("daily")) {
                    const QStringList days = schedule.value(QStringLiteral("days")).toStringList();
                    const QString today = now.toString(QStringLiteral("dddd"));
                    shouldRun = days.isEmpty() || days.contains(today);
                    if (shouldRun && lastRun.isValid() && lastRun.date() == now.date())
                        shouldRun = false;
                } else {
                    const QDate targetDate = QDate::fromString(schedule.value(QStringLiteral("date")).toString(), Qt::ISODate);
                    shouldRun = targetDate.isValid() && targetDate == now.date() && (!lastRun.isValid());
                }
            }

            if (!shouldRun)
            {
                if (schedule.value(QStringLiteral("stopEnabled")).toBool()) {
                    const QTime stopTime = QTime::fromString(schedule.value(QStringLiteral("stopTime")).toString(), QStringLiteral("hh:mm AP"));
                    if (stopTime.isValid()) {
                        const int nowMins = now.time().hour() * 60 + now.time().minute();
                        const int stopMins = stopTime.hour() * 60 + stopTime.minute();
                        if (qAbs(nowMins - stopMins) <= 2)
                            stopGrabberResultDownloads(project.id);
                    }
                }
                continue;
            }

            QVariantMap updatedProject = projectMap;
            updatedProject[QStringLiteral("lastScheduledRunAt")] = now.toString(Qt::ISODate);
            m_grabberProjectModel->upsertProject(updatedProject);
            const QString scheduledAction = schedule.value(QStringLiteral("action"), QStringLiteral("exploreOnly")).toString();
            if (scheduledAction == QStringLiteral("downloadChecked")) {
                loadGrabberProjectResults(project.id);
                downloadGrabberResults(project.id, true);
            } else {
                if (scheduledAction == QStringLiteral("exploreAndDownload"))
                    updatedProject[QStringLiteral("startDownloadingImmediately")] = true;
                runGrabber(updatedProject);
            }
            break;
        }
    }

    int currentMinutes = calculateMinutesUntilNextQueue();
    if (currentMinutes != prevMinutes) {
        emit minutesUntilNextQueueChanged();
    }
}

// ── yt-dlp public API ─────────────────────────────────────────────────────────

// Table of domain fragments that yt-dlp reliably supports.  Checked against the
// URL host after stripping the "www." prefix so both "youtube.com" and
// "www.youtube.com" are matched by a single entry.
static const QStringList kYtdlpDomains = {
    QStringLiteral("youtube.com"),
    QStringLiteral("youtu.be"),
    QStringLiteral("vimeo.com"),
    QStringLiteral("twitter.com"),
    QStringLiteral("x.com"),
    QStringLiteral("instagram.com"),
    QStringLiteral("facebook.com"),
    QStringLiteral("fb.watch"),
    QStringLiteral("tiktok.com"),
    QStringLiteral("twitch.tv"),
    QStringLiteral("dailymotion.com"),
    QStringLiteral("reddit.com"),
    QStringLiteral("streamable.com"),
    QStringLiteral("soundcloud.com"),
    QStringLiteral("bandcamp.com"),
    QStringLiteral("bilibili.com"),
    QStringLiteral("nicovideo.jp"),
    QStringLiteral("rumble.com"),
    QStringLiteral("odysee.com"),
    QStringLiteral("bitchute.com"),
    QStringLiteral("brighteon.com"),
    QStringLiteral("mixcloud.com"),
    QStringLiteral("ted.com"),
    QStringLiteral("bbc.co.uk"),
    QStringLiteral("cnn.com"),
};

bool AppController::isLikelyYtdlpUrl(const QString &urlStr) const {
    const QUrl url(urlStr);
    if (!url.isValid()) return false;
    if (url.scheme() != QLatin1String("http") && url.scheme() != QLatin1String("https"))
        return false;

    // Strip leading "www." so entries in kYtdlpDomains don't need both variants.
    QString host = url.host().toLower();
    if (host.startsWith(QLatin1String("www.")))
        host = host.mid(4);
    const QString path = url.path().toLower();

    // Never treat obvious static assets or API transport endpoints as media URLs.
    if (path.contains(QLatin1String("/api/"))
        || path.contains(QLatin1String("/_/"))
        || path.startsWith(QLatin1String("/s/"))
        || path.startsWith(QLatin1String("/yts/"))
        || path.startsWith(QLatin1String("/images/"))
        || path.endsWith(QLatin1String(".mp3"))
        || path.endsWith(QLatin1String(".m4a"))
        || path.endsWith(QLatin1String(".mp4"))
        || path.endsWith(QLatin1String(".webm"))
        || path.endsWith(QLatin1String(".m3u8"))
        || path.endsWith(QLatin1String(".ts"))
        || path.endsWith(QLatin1String(".json"))
        || path.endsWith(QLatin1String(".js"))
        || path.endsWith(QLatin1String(".css"))
        || path.endsWith(QLatin1String(".jpg"))
        || path.endsWith(QLatin1String(".jpeg"))
        || path.endsWith(QLatin1String(".png"))
        || path.endsWith(QLatin1String(".webp"))
        || path.endsWith(QLatin1String(".svg"))
        || path.endsWith(QLatin1String(".ico")))
        return false;

    // YouTube requires content-style URL shapes; host-only matching is too broad.
    if (host == QLatin1String("youtube.com") || host.endsWith(QLatin1String(".youtube.com"))) {
        const bool looksLikeContent = path == QLatin1String("/watch")
            || path.startsWith(QLatin1String("/shorts/"))
            || path.startsWith(QLatin1String("/live/"))
            || path.startsWith(QLatin1String("/playlist"))
            || path.startsWith(QLatin1String("/clip/"))
            || path.startsWith(QLatin1String("/embed/"))
            || path.startsWith(QLatin1String("/@"));
        return looksLikeContent;
    }
    if (host == QLatin1String("youtu.be")) {
        const QString p = path.trimmed();
        return p.length() > 1 && p != QLatin1String("/");
    }

    for (const QString &domain : kYtdlpDomains) {
        if (host == domain || host.endsWith(QLatin1Char('.') + domain))
            return true;
    }
    return false;
}

QString AppController::beginYtdlpInfo(const QString &url, const QString &cookiesBrowser) {
    if (!m_ytdlpManager->available()) {
        const QString probeId = QUuid::createUuid().toString(QUuid::WithoutBraces);
        emit ytdlpInfoFailed(probeId, url,
            QStringLiteral("yt-dlp is not installed. Please download it in Settings → Video Downloader."));
        return probeId;
    }

    const QString probeId = QUuid::createUuid().toString(QUuid::WithoutBraces);

    // Run yt-dlp metadata probe without downloading media.
    // For channel/playlist URLs, only inspect the first entry so probing remains fast.
    const bool isPlaylistLike = isLikelyPlaylistOrChannelUrl(url);
    auto *proc = new QProcess(this);
    proc->setProgram(m_ytdlpManager->binaryPath());
    QStringList args = {
        QStringLiteral("--ignore-config"),
        QStringLiteral("--dump-single-json"),
        QStringLiteral("--no-warnings"),
    };
    if (isPlaylistLike) {
        args << QStringLiteral("--yes-playlist")
             << QStringLiteral("--playlist-items")
             << QStringLiteral("1");
    } else {
        args << QStringLiteral("--no-playlist");
    }
    if (!cookiesBrowser.isEmpty()) {
        args << QStringLiteral("--cookies-from-browser") << cookiesBrowser.toLower();
        // Logged-in YouTube probes use the default client set (tv_downgraded,web_safari
        // for free accounts), which supports cookie authentication.
        // web_creator is excluded because it requires a PO token for format retrieval and
        // would hide formats rather than expose them.
        // formats=missing_pot,incomplete exposes the full quality list in the picker UI;
        // the real transfer omits this flag so POT-requiring formats are filtered out.
        args << QStringLiteral("--extractor-args")
             << QStringLiteral("youtube:player_client=default,-web_creator;formats=missing_pot,incomplete");
    }
    // The probe only needs metadata plus the formats array; do not validate a
    // concrete downloadable selector here. Ask for every format, including ones
    // that are currently incomplete/unplayable, so the UI can still present a
    // quality list and let the real transfer decide what is actually available.
    args << QStringLiteral("--allow-unplayable-formats")
         << QStringLiteral("-f") << QStringLiteral("all");
    // Without ffmpeg, yt-dlp's default selector (bestvideo*+bestaudio) cannot merge
    // separate DASH streams and raises "Requested format is not available". Through a
    // VPN or proxy YouTube often serves DASH-only — passing ffmpeg location fixes this.
    const QString ffmpegPath = m_ytdlpManager->ffmpegPath();
    if (!ffmpegPath.isEmpty())
        args << QStringLiteral("--ffmpeg-location") << ffmpegPath;
    // JS runtime for EJS n-challenge solving — same as the actual transfer.
    // Without this the probe also gets throttled URLs / storyboard-only formats.
    const QString jsRtPath = m_ytdlpManager->jsRuntimePath();
    const QString jsRtName = m_ytdlpManager->jsRuntimeName();
    if (!jsRtPath.isEmpty() && !jsRtName.isEmpty())
        args << QStringLiteral("--js-runtimes") << (jsRtName + QLatin1Char(':') + jsRtPath);
    const QString proxyUrl = buildYtdlpProxyUrl(m_settings, QUrl::fromUserInput(url));
    if (!proxyUrl.isEmpty())
        args << QStringLiteral("--proxy") << proxyUrl;
    args << url;
    proc->setArguments(args);
    proc->setProcessChannelMode(QProcess::SeparateChannels);

    qDebug() << "[YtdlpProbe] starting:" << proc->program() << args;

    m_ytdlpProbes[probeId] = { proc, url, QByteArray() };

    connect(proc, &QProcess::readyReadStandardOutput, this, [this, probeId, proc]() {
        auto it = m_ytdlpProbes.find(probeId);
        if (it == m_ytdlpProbes.end())
            return;
        it->output += proc->readAllStandardOutput();
    });

    // Accumulate stderr and log lines as they arrive.
    connect(proc, &QProcess::readyReadStandardError, this, [this, probeId, proc]() {
        const QByteArray data = proc->readAllStandardError();
        auto it = m_ytdlpProbes.find(probeId);
        if (it != m_ytdlpProbes.end())
            it->stderrOutput += data;
#ifdef Q_OS_WIN
        const QString text = QString::fromLocal8Bit(data).trimmed();
#else
        const QString text = QString::fromUtf8(data).trimmed();
#endif
        if (!text.isEmpty())
            qDebug() << "[YtdlpProbe]" << text;
    });

    connect(proc, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, [this, probeId, url, proc, isPlaylistLike](int exitCode, QProcess::ExitStatus) {
        auto it = m_ytdlpProbes.find(probeId);
        if (it == m_ytdlpProbes.end()) {
            proc->deleteLater();
            return;
        }
        QByteArray raw = it->output;
        raw += proc->readAllStandardOutput();
        QByteArray stderrAccum = it->stderrOutput;
        m_ytdlpProbes.erase(it);

        qDebug() << "[YtdlpProbe] finished, exitCode:" << exitCode
                 << "stdout bytes:" << raw.size();

        if (exitCode != 0) {
            // stderr was accumulated by readyReadStandardError into stderrAccum.
            const QByteArray stderrBytes = stderrAccum;
#ifdef Q_OS_WIN
            QString errOutput = QString::fromLocal8Bit(stderrBytes).trimmed();
#else
            QString errOutput = QString::fromUtf8(stderrBytes).trimmed();
#endif
            if (errOutput.isEmpty()) {
                // Fallback: stdout (may be "null" or partial JSON — strip it)
#ifdef Q_OS_WIN
                errOutput = QString::fromLocal8Bit(raw).trimmed();
#else
                errOutput = QString::fromUtf8(raw).trimmed();
#endif
                if (errOutput == QLatin1String("null")) errOutput.clear();
            }
            qDebug() << "[YtdlpProbe] error:" << errOutput;
            proc->deleteLater();
            emit ytdlpInfoFailed(probeId, url,
                errOutput.isEmpty()
                    ? QStringLiteral("yt-dlp exited with code %1").arg(exitCode)
                    : errOutput);
            return;
        }

        proc->deleteLater();

        const QJsonDocument doc = QJsonDocument::fromJson(raw);
        if (!doc.isObject()) {
            emit ytdlpInfoFailed(probeId, url,
                QStringLiteral("yt-dlp returned invalid JSON (output length: %1)").arg(raw.size()));
            return;
        }

        const QJsonObject root = doc.object();
        QJsonObject mediaObject = root;
        QString title = root.value(QLatin1String("title")).toString();
        if (isPlaylistLike) {
            const QJsonArray entries = root.value(QLatin1String("entries")).toArray();
            if (!entries.isEmpty() && entries.first().isObject()) {
                mediaObject = entries.first().toObject();
            }
            const QString channelName = root.value(QLatin1String("channel")).toString();
            const QString uploaderName = root.value(QLatin1String("uploader")).toString();
            const QString playlistTitle = root.value(QLatin1String("title")).toString();
            if (!channelName.isEmpty())
                title = channelName;
            else if (!uploaderName.isEmpty())
                title = uploaderName;
            else if (!playlistTitle.isEmpty())
                title = playlistTitle;
        }

        // ── Build format list ─────────────────────────────────────────────────
        // We expose one entry per distinct video-height bucket plus an "audio only"
        // option.  Each entry carries enough metadata for the QML picker to show a
        // useful label and let the user make an informed choice.
        const QJsonArray formatsJson = mediaObject.value(QLatin1String("formats")).toArray();

        // Collect the best-quality format for each height bucket.
        // Key: height (0 = audio-only).  Value: best format object seen so far.
        QMap<int, QJsonObject> bestByHeight;
        QJsonObject bestAudioOnly;
        QJsonObject bestOverall;
        int bestOverallHeight = 0;

        for (const QJsonValue &fv : formatsJson) {
            const QJsonObject f = fv.toObject();
            const QString vcodec = f.value(QLatin1String("vcodec")).toString();
            const QString acodec = f.value(QLatin1String("acodec")).toString();
            const bool hasVideo = (!vcodec.isEmpty() && vcodec != QLatin1String("none"));
            const bool hasAudio = (!acodec.isEmpty() && acodec != QLatin1String("none"));

            if (!hasVideo && !hasAudio) continue;

            int height = hasVideo ? f.value(QLatin1String("height")).toInt(0) : 0;
            // Some YouTube clients (TV, DASH responses) omit the height field.
            // Fall back to parsing it from the "resolution" string ("WxH" or "HxW").
            if (height == 0 && hasVideo) {
                const QString res = f.value(QLatin1String("resolution")).toString();
                const int xIdx = res.indexOf(QLatin1Char('x'));
                if (xIdx >= 0) {
                    const int w = res.left(xIdx).toInt();
                    const int h2 = res.mid(xIdx + 1).toInt();
                    // resolution is always "width x height" in yt-dlp
                    height = (h2 > 0) ? h2 : w;
                }
                // Also try format_note which yt-dlp sets to e.g. "1080p" or "720p60"
                if (height == 0) {
                    static const QRegularExpression kNoteRe(QStringLiteral(R"((\d{3,4})p)"));
                    const QString note = f.value(QLatin1String("format_note")).toString();
                    const QRegularExpressionMatch m2 = kNoteRe.match(note);
                    if (m2.hasMatch()) height = m2.captured(1).toInt();
                }
            }
            const QString formatIdValue = f.value(QLatin1String("format_id")).toString();
            if (formatIdValue.isEmpty())
                continue;

            // Keep the entry with the highest total bitrate for each bucket.
            const double tbr = f.value(QLatin1String("tbr")).toDouble(0.0);
            if (!bestByHeight.contains(height) ||
                tbr > bestByHeight[height].value(QLatin1String("tbr")).toDouble(0.0)) {
                bestByHeight[height] = f;
            }
            if (!hasVideo && hasAudio
                && (bestAudioOnly.isEmpty()
                    || tbr > bestAudioOnly.value(QLatin1String("tbr")).toDouble(0.0))) {
                bestAudioOnly = f;
            }
            if (hasVideo && (bestOverall.isEmpty()
                || height > bestOverallHeight
                || (height == bestOverallHeight
                    && tbr > bestOverall.value(QLatin1String("tbr")).toDouble(0.0)))) {
                bestOverall = f;
                bestOverallHeight = height;
            }
        }

        // Convert to QVariantList in descending resolution order.
        QVariantList formats;

        // Standard height buckets in descending order; anything else is omitted
        // because yt-dlp's "bestvideo+bestaudio/best" selector is preferable.
        const QList<int> orderedHeights = {2160, 1440, 1080, 720, 480, 360, 240, 144, 0};
        for (int h : orderedHeights) {
            if (!bestByHeight.contains(h)) continue;
            const QJsonObject &f = bestByHeight[h];
            const QString exactFormatId = f.value(QLatin1String("format_id")).toString();
            const QString vcodec = f.value(QLatin1String("vcodec")).toString();
            const QString acodec = f.value(QLatin1String("acodec")).toString();
            const bool hasVideo = (!vcodec.isEmpty() && vcodec != QLatin1String("none"));
            const bool hasAudio = (!acodec.isEmpty() && acodec != QLatin1String("none"));

            QString label;
            QString formatId;
            if (h == 0) {
                // Audio-only bucket
                label    = QStringLiteral("Audio only (best)");
                formatId = !bestAudioOnly.isEmpty()
                    ? bestAudioOnly.value(QLatin1String("format_id")).toString()
                    : exactFormatId;
            } else {
                label = QStringLiteral("%1p").arg(h);
                // Use a height-capped quality selector rather than an exact format ID.
                // Exact IDs from a missing_pot/incomplete probe often require a PO token
                // to download (even with browser cookies), so the transfer would fail with
                // "Requested format is not available".  A height-based selector lets yt-dlp
                // pick the best actually-downloadable stream at or below that resolution.
                formatId = QStringLiteral("bestvideo[height<=%1]+bestaudio/b[height<=%1]").arg(h);
            }

            // Add file size if known
            const qint64 filesize = static_cast<qint64>(
                f.value(QLatin1String("filesize")).toDouble(0.0));
            const qint64 filesizeApprox = static_cast<qint64>(
                f.value(QLatin1String("filesize_approx")).toDouble(0.0));
            const qint64 size = filesize > 0 ? filesize : filesizeApprox;

            QVariantMap entry;
            entry[QStringLiteral("id")]       = formatId;
            entry[QStringLiteral("label")]    = label;
            entry[QStringLiteral("ext")]      = f.value(QLatin1String("ext")).toString();
            entry[QStringLiteral("width")]    = f.value(QLatin1String("width")).toInt(0);
            entry[QStringLiteral("height")]   = h;
            entry[QStringLiteral("fps")]      = f.value(QLatin1String("fps")).toInt(0);
            entry[QStringLiteral("tbr")]      = f.value(QLatin1String("tbr")).toDouble(0.0);
            entry[QStringLiteral("vcodec")]   = f.value(QLatin1String("vcodec")).toString();
            entry[QStringLiteral("acodec")]   = f.value(QLatin1String("acodec")).toString();
            entry[QStringLiteral("filesize")] = size;
            formats.append(entry);
        }

        // Always expose at least one concrete selectable entry when the probe
        // succeeded. Logged-in YouTube responses sometimes lack the canonical
        // height buckets we display above, which otherwise leaves the dialog
        // blank even though yt-dlp returned a usable formats array.
        // "Best quality" entry: always use the generic yt-dlp selector rather than an
        // exact format ID.  Probe-derived IDs often come from missing_pot/incomplete
        // formats that require a PO token to download even with browser cookies.
        // bv*+ba/b means: best video combined with best audio, fallback to best muxed.
        const bool hasBestEntry = !bestOverall.isEmpty() || !bestAudioOnly.isEmpty();
        if (hasBestEntry) {
            QJsonObject bestEntrySource = bestOverall.isEmpty() ? bestAudioOnly : bestOverall;
            QVariantMap best;
            best[QStringLiteral("id")] = QStringLiteral("bv*+ba/b");
            best[QStringLiteral("label")] = QStringLiteral("Best quality");
            best[QStringLiteral("ext")] = bestEntrySource.value(QLatin1String("ext")).toString(QStringLiteral("mp4"));
            best[QStringLiteral("width")] = bestEntrySource.value(QLatin1String("width")).toInt(0);
            best[QStringLiteral("height")] = bestOverallHeight;
            best[QStringLiteral("fps")] = bestEntrySource.value(QLatin1String("fps")).toInt(0);
            best[QStringLiteral("tbr")] = bestEntrySource.value(QLatin1String("tbr")).toDouble(0.0);
            best[QStringLiteral("vcodec")] = bestEntrySource.value(QLatin1String("vcodec")).toString();
            best[QStringLiteral("acodec")] = bestEntrySource.value(QLatin1String("acodec")).toString();
            best[QStringLiteral("filesize")] = static_cast<qint64>(0);

            // Always prepend "Best quality" — it uses a generic selector distinct
            // from all the height-based selectors in the list, so it's never a dup.
            formats.prepend(best);
        }

        emit ytdlpInfoReady(probeId, url, title, formats);
    });

    connect(proc, &QProcess::errorOccurred, this, [this, probeId, url, proc](QProcess::ProcessError) {
        if (!m_ytdlpProbes.contains(probeId)) {
            proc->deleteLater();
            return;
        }
        m_ytdlpProbes.remove(probeId);
        const QString reason = proc->errorString().isEmpty()
            ? QStringLiteral("Failed to start yt-dlp")
            : proc->errorString();
        proc->deleteLater();
        emit ytdlpInfoFailed(probeId, url, reason);
    });

    proc->start();
    return probeId;
}

void AppController::cancelYtdlpInfo(const QString &probeId) {
    auto it = m_ytdlpProbes.find(probeId);
    if (it == m_ytdlpProbes.end()) return;

    QProcess *proc = it.value().process;
    m_ytdlpProbes.erase(it);

    if (proc) {
        disconnect(proc, nullptr, this, nullptr);
        proc->kill();
        proc->waitForFinished(2000);
        proc->deleteLater();
    }
}

void AppController::finalizeYtdlpDownload(const QString &url,
                                           const QString &saveDir,
                                           const QString &category,
                                           const QString &formatId,
                                           const QString &containerFormat,
                                           bool uniqueFilename,
                                           const QString &videoTitle,
                                           bool playlistMode,
                                           int  maxItems,
                                           const QVariantMap &extraOptions) {
    // Create the DownloadItem here — not before.  This is intentionally later than
    // the regular HTTP flow (which creates the item as soon as the URL is submitted)
    // so that yt-dlp downloads only appear in the list once the user has confirmed
    // the format choice.  That avoids a ghost "Watch" entry showing up with a blank
    // icon while the YtdlpDialog is open.
    const QString id   = generateId();
    const QUrl    qurl = QUrl::fromUserInput(url);
    auto *item = new DownloadItem(id, qurl);

    item->setSavePath(saveDir);
    item->setFilename(QString());
    item->setIsYtdlp(true);
    item->setYtdlpPlaylistMode(playlistMode);

    const QString resolvedCategory = category.isEmpty()
        ? m_categoryModel->categoryForUrl(qurl, QString())
        : category;
    item->setCategory(resolvedCategory);

    const QString container = containerFormat.isEmpty() ? QStringLiteral("mp4") : containerFormat;

    // When the user chose "Add Numbered", compute a collision-free output template
    // using the video title already known from the --dump-json probe.
    // Scan the save directory for any file whose base name matches the title and
    // find the first unused _2/_3/_N suffix.  Pure filesystem check — no extra
    // yt-dlp subprocess needed.
    QString outputTemplate = QStringLiteral("%(title)s.%(ext)s");
    if (uniqueFilename && !videoTitle.isEmpty()) {
        QDir dir(saveDir);
        dir.mkpath(saveDir);

        const QFileInfoList allFiles = dir.entryInfoList(QDir::Files | QDir::NoDotAndDotDot);
        auto baseExists = [&](const QString &b) {
            for (const QFileInfo &f : allFiles)
                if (f.completeBaseName().compare(b, Qt::CaseInsensitive) == 0)
                    return true;
            return false;
        };

        if (baseExists(videoTitle)) {
            int n = 2;
            while (baseExists(videoTitle + QLatin1Char('_') + QString::number(n)))
                ++n;
            outputTemplate = videoTitle + QLatin1Char('_') + QString::number(n)
                             + QStringLiteral(".%(ext)s");
        }
        // else no collision — default template is fine
    }

    // In playlist mode use a per-uploader subfolder so each channel's videos land
    // together: "uploader/title.ext".  This matches what yt-dlp normally does for
    // channel/playlist downloads and avoids collisions between channels.
    if (playlistMode && outputTemplate == QStringLiteral("%(title)s.%(ext)s"))
        outputTemplate = QStringLiteral("%(uploader)s/%(title)s.%(ext)s");

    // Store "formatId|container|outputTemplate" so resume/redownload can replay
    // the same settings (keeps numbered names consistent on retry).
    item->setYtdlpFormatId(formatId + QLatin1Char('|') + container
                           + QLatin1Char('|') + outputTemplate);

    // Enqueue the item (triggers m_downloadModel->addItem via itemAdded signal),
    // persist it, and notify the UI.  The queue's scheduleNext() skips yt-dlp
    // items so this won't try to start a SegmentedTransfer.
    // Convert QML-supplied options map to a typed struct, then serialise to JSON
    // so the options survive an app restart and can be replayed on resume.
    const YtdlpOptions opts = YtdlpOptions::fromVariantMap(extraOptions);
    const QString optsJson  = opts.toJson();
    if (!optsJson.isEmpty())
        item->setYtdlpExtraOptions(optsJson);

    m_queue->enqueueHeld(item);
    m_db->save(item);
    watchItem(item);
    emit downloadAdded(item);

    startYtdlpWorker(item, formatId, container, /*resume=*/false, outputTemplate,
                     playlistMode, maxItems, opts);
}

void AppController::startYtdlpDownload(const QString &downloadId, const QString &formatId,
                                        const QString &containerFormat) {
    auto *item = m_downloadModel->itemById(downloadId);
    if (!item) return;

    item->setIsYtdlp(true);
    item->setYtdlpPlaylistMode(false);
    const QString container = containerFormat.isEmpty() ? QStringLiteral("mp4") : containerFormat;
    item->setYtdlpFormatId(formatId + QLatin1Char('|') + container);
    startYtdlpWorker(item, formatId, container, /*resume=*/false);
}

void AppController::downloadYtdlpBinary() {
    m_ytdlpManager->downloadBinary();
}

void AppController::stopActiveYtdlpBatch() {
    if (m_activeYtdlpBatchId.isEmpty())
        return;
    m_lastYtdlpBatchId = m_activeYtdlpBatchId;
    auto *worker = m_ytdlpWorkers.value(m_activeYtdlpBatchId);
    auto *item = m_downloadModel->itemById(m_activeYtdlpBatchId);
    if (worker) {
        worker->pause();
        worker->deleteLater();
        m_ytdlpWorkers.remove(m_activeYtdlpBatchId);
    }
    if (item) {
        item->setStatus(DownloadItem::Status::Paused);
        scheduleSave(item->id());
    }
    m_activeYtdlpBatchId.clear();
    m_activeYtdlpBatchLabel.clear();
    emit ytdlpBatchChanged();
    emit activeDownloadsChanged();
}

void AppController::resumeLastYtdlpBatch() {
    if (m_lastYtdlpBatchId.isEmpty())
        return;
    auto *item = m_downloadModel->itemById(m_lastYtdlpBatchId);
    if (!item || !item->isYtdlp())
        return;
    resumeDownload(m_lastYtdlpBatchId);
}

// ── yt-dlp internal helpers ───────────────────────────────────────────────────

// Look for ffmpeg next to the yt-dlp binary first (bundled install), then fall
// back to an empty string meaning "let yt-dlp search PATH itself".
bool AppController::retryYtdlpWithBrowserCookies(const QString &downloadId, const QString &browser) {
    auto *item = m_downloadModel->itemById(downloadId);
    if (!item || !item->isYtdlp())
        return false;

    const QString normalizedBrowser = normalizeYtdlpBrowserName(browser);
    if (normalizedBrowser.isEmpty())
        return false;

    const QString stored = item->ytdlpFormatId();
    const int p1 = stored.indexOf(QLatin1Char('|'));
    const int p2 = p1 >= 0 ? stored.indexOf(QLatin1Char('|'), p1 + 1) : -1;
    const QString formatId = p1 >= 0 ? stored.left(p1) : stored;
    const QString container = (p1 >= 0 && p2 > p1)
        ? stored.mid(p1 + 1, p2 - p1 - 1)
        : (p1 >= 0 ? stored.mid(p1 + 1) : QStringLiteral("mp4"));
    const QString outputTemplate = p2 >= 0 ? stored.mid(p2 + 1) : QString();

    YtdlpOptions opts = YtdlpOptions::fromJson(item->ytdlpExtraOptions());
    opts.cookiesFromBrowser = normalizedBrowser;
    item->setYtdlpExtraOptions(opts.toJson());
    item->setErrorString({});
    item->setDoneBytes(0);
    item->setTotalBytes(0);
    item->setSpeed(0);
    item->setStatus(DownloadItem::Status::Queued);
    scheduleSave(downloadId);

    startYtdlpWorker(item, formatId, container, /*resume=*/false, outputTemplate,
                     item->ytdlpPlaylistMode(), 0, opts);
    return true;
}

QString AppController::detectFfmpegPath(const QString &ytdlpBinaryPath) {
    const QString dir = ytdlpBinaryPath.isEmpty()
        ? writableRuntimeToolsDir()
        : QFileInfo(ytdlpBinaryPath).absolutePath();
#if defined(Q_OS_WIN)
    const QString candidate = dir + QStringLiteral("/ffmpeg.exe");
#else
    const QString candidate = dir + QStringLiteral("/ffmpeg");
#endif
    if (QFile::exists(candidate))
        return candidate;
    return {};  // let yt-dlp find system ffmpeg via PATH
}

void AppController::startYtdlpWorker(DownloadItem *item, const QString &formatId,
                                      const QString &containerFormat, bool resume,
                                      const QString &outputTemplate,
                                      bool playlistMode, int maxItems,
                                      const YtdlpOptions &options) {
    if (!item) return;

    // Abort any existing worker for this item (e.g., a stale one from a previous run).
    auto *existing = m_ytdlpWorkers.take(item->id());
    if (existing) { existing->abort(); existing->deleteLater(); }

    const QString saveDir    = item->savePath();

    // Ensure the destination directory exists before handing it to yt-dlp.
    if (!saveDir.isEmpty())
        QDir().mkpath(saveDir);

    // Show Downloading immediately so the UI never briefly flashes a stale status
    // (e.g. Completed from a previous run) while the pre-flight probe is running.
    item->setStatus(DownloadItem::Status::Downloading);
    item->setErrorString({});

    // Prefer the path YtdlpManager already resolved (next to yt-dlp binary or PATH).
    const QString ffmpegPath = m_ytdlpManager->ffmpegPath().isEmpty()
                               ? detectFfmpegPath(m_ytdlpManager->binaryPath())
                               : m_ytdlpManager->ffmpegPath();
    const QString resolvedTemplate = outputTemplate.isEmpty()
        ? QStringLiteral("%(title)s.%(ext)s") : outputTemplate;

    // yt-dlp runs out-of-process, so it must receive an explicit proxy URL.
    const QString proxyUrl = buildYtdlpProxyUrl(m_settings, item->url());

    auto *worker = new YtdlpTransfer(item, m_ytdlpManager->binaryPath(),
                                     formatId, containerFormat, saveDir, ffmpegPath,
                                     m_settings ? m_settings->globalSpeedLimitKBps() : 0,
                                     resume, resolvedTemplate, proxyUrl,
                                     playlistMode, maxItems, options,
                                     m_ytdlpManager->jsRuntimePath(),
                                     m_ytdlpManager->jsRuntimeName(),
                                     this);
    m_ytdlpWorkers[item->id()] = worker;
    if (playlistMode) {
        m_activeYtdlpBatchId = item->id();
        m_lastYtdlpBatchId = item->id();
        m_activeYtdlpBatchLabel = item->url().toString();
        m_activeYtdlpBatchItems.clear();
        emit ytdlpBatchChanged();
    }

    connect(worker, &YtdlpTransfer::playlistItemStarted, this,
            [this, item](int index, int total, const QString &title) {
        if (!item || item->id() != m_activeYtdlpBatchId || index <= 0)
            return;
        while (m_activeYtdlpBatchItems.size() < total) {
            QVariantMap blank;
            blank[QStringLiteral("index")] = m_activeYtdlpBatchItems.size() + 1;
            blank[QStringLiteral("title")] = QStringLiteral("Item %1").arg(m_activeYtdlpBatchItems.size() + 1);
            blank[QStringLiteral("status")] = QStringLiteral("Queued");
            blank[QStringLiteral("progress")] = 0.0;
            m_activeYtdlpBatchItems.append(blank);
        }
        QVariantMap row = m_activeYtdlpBatchItems[index - 1].toMap();
        row[QStringLiteral("index")] = index;
        if (!title.trimmed().isEmpty())
            row[QStringLiteral("title")] = title.trimmed();
        row[QStringLiteral("status")] = QStringLiteral("Downloading");
        m_activeYtdlpBatchItems[index - 1] = row;
        emit ytdlpBatchChanged();
    });
    connect(worker, &YtdlpTransfer::playlistItemProgress, this,
            [this, item](int index, double percent) {
        if (!item || item->id() != m_activeYtdlpBatchId || index <= 0 || index > m_activeYtdlpBatchItems.size())
            return;
        QVariantMap row = m_activeYtdlpBatchItems[index - 1].toMap();
        row[QStringLiteral("progress")] = percent;
        row[QStringLiteral("status")] = percent >= 99.5 ? QStringLiteral("Completed")
                                                        : QStringLiteral("Downloading");
        m_activeYtdlpBatchItems[index - 1] = row;
        emit ytdlpBatchChanged();
    });
    connect(worker, &YtdlpTransfer::playlistItemFinished, this,
            [this, item](int index) {
        if (!item || item->id() != m_activeYtdlpBatchId || index <= 0 || index > m_activeYtdlpBatchItems.size())
            return;
        QVariantMap row = m_activeYtdlpBatchItems[index - 1].toMap();
        row[QStringLiteral("status")] = QStringLiteral("Completed");
        row[QStringLiteral("progress")] = 100.0;
        m_activeYtdlpBatchItems[index - 1] = row;
        emit ytdlpBatchChanged();
    });

    const QString id = item->id();
    connect(worker, &YtdlpTransfer::finished, this, [this, id]() {
        onYtdlpWorkerFinished(id);
    });
    connect(worker, &YtdlpTransfer::failed, this, [this, id](const QString &reason) {
        onYtdlpWorkerFailed(id, reason);
    });

    worker->start();
    emit activeDownloadsChanged();
}

void AppController::onYtdlpWorkerFinished(const QString &id) {
    auto *worker = m_ytdlpWorkers.take(id);
    if (worker) worker->deleteLater();

    auto *item = m_downloadModel->itemById(id);
    if (item) {
        scheduleSave(id);
        emit downloadCompleted(item);
    }
    if (id == m_activeYtdlpBatchId) {
        m_activeYtdlpBatchId.clear();
        m_activeYtdlpBatchLabel.clear();
        emit ytdlpBatchChanged();
    }
    emit activeDownloadsChanged();
}

bool AppController::ytdlpErrorSuggestsCookies(const QString &reason) {
    const QString text = cleanedYtdlpError(reason).toLower();
    return text.contains(QStringLiteral("sign in to confirm"))
        || text.contains(QStringLiteral("use --cookies-from-browser"))
        || text.contains(QStringLiteral("cookies are needed"))
        || text.contains(QStringLiteral("members-only"))
        || text.contains(QStringLiteral("age-restricted"))
        || text.contains(QStringLiteral("this video is private"))
        || text.contains(QStringLiteral("login required"))
        || text.contains(QStringLiteral("authentication required"));
}

QString AppController::normalizeYtdlpBrowserName(const QString &browser) {
    const QString key = browser.trimmed().toLower();
    if (key == QLatin1String("chrome") || key == QLatin1String("firefox")
        || key == QLatin1String("edge") || key == QLatin1String("brave")
        || key == QLatin1String("opera") || key == QLatin1String("vivaldi")
        || key == QLatin1String("safari")) {
        return key;
    }
    return {};
}

QString AppController::preferredBrowserFromReason(const QString &reason) {
    const QString text = cleanedYtdlpError(reason).toLower();
    static const QStringList browsers = {
        QStringLiteral("firefox"),
        QStringLiteral("chrome"),
        QStringLiteral("edge"),
        QStringLiteral("brave"),
        QStringLiteral("opera"),
        QStringLiteral("vivaldi"),
        QStringLiteral("safari"),
    };
    for (const QString &browser : browsers) {
        if (text.contains(browser))
            return browser;
    }
    return {};
}

void AppController::onYtdlpWorkerFailed(const QString &id, const QString &reason) {
    auto *worker = m_ytdlpWorkers.take(id);
    if (worker) worker->deleteLater();

    auto *item = m_downloadModel->itemById(id);
    if (item) {
        item->setStatus(DownloadItem::Status::Error);
        const QString cleanedReason = cleanedYtdlpError(reason);
        if (!cleanedReason.isEmpty())
            item->setErrorString(cleanedReason);
        scheduleSave(id);
        if (ytdlpErrorSuggestsCookies(cleanedReason)) {
            emit ytdlpCookieRetryRequested(id, cleanedReason,
                                           preferredBrowserFromReason(cleanedReason));
        }
    }
    if (id == m_activeYtdlpBatchId) {
        m_activeYtdlpBatchId.clear();
        m_activeYtdlpBatchLabel.clear();
        emit ytdlpBatchChanged();
    }
    emit activeDownloadsChanged();
}
