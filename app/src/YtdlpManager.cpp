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

#include "YtdlpManager.h"
#include <QCoreApplication>
#include <QFile>
#include <QFileInfo>
#include <QDir>
#include <QNetworkRequest>
#include <QProcess>
#include <QStandardPaths>
#include <QDebug>

// ── Platform-specific binary name and download URL ───────────────────────────
#if defined(Q_OS_WIN)
static const QLatin1String kBinaryName("yt-dlp.exe");
static const QLatin1String kDownloadUrl(
    "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe");
#else
static const QLatin1String kBinaryName("yt-dlp");
static const QLatin1String kDownloadUrl(
    "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp");
#endif

YtdlpManager::YtdlpManager(QNetworkAccessManager *nam, QObject *parent)
    : QObject(parent), m_nam(nam)
{
}

// ── Binary path resolution ────────────────────────────────────────────────────

QString YtdlpManager::resolvedBinaryPath() const {
    // 1. User-supplied custom path (validated: must exist and be executable)
    if (!m_customPath.isEmpty()) {
        const QFileInfo fi(m_customPath);
        if (fi.exists() && fi.isExecutable())
            return m_customPath;
    }

    // 2. Bundled binary next to the application executable
    const QString appDir = QCoreApplication::applicationDirPath();
    const QString bundled = appDir + QLatin1Char('/') + kBinaryName;
    if (QFile::exists(bundled))
        return bundled;

    // 3. Fall back to the bare name so the OS will search PATH
    return QString(kBinaryName);
}

QString YtdlpManager::binaryPath() const {
    return resolvedBinaryPath();
}

void YtdlpManager::setCustomPath(const QString &path) {
    if (m_customPath == path) return;
    m_customPath = path;
    // Re-probe with the new path immediately
    checkAvailability();
}

// ── Availability check ────────────────────────────────────────────────────────

void YtdlpManager::checkAvailability() {
    // Cancel any previous in-flight version check
    if (m_versionProcess) {
        disconnect(m_versionProcess, nullptr, this, nullptr);
        m_versionProcess->kill();
        m_versionProcess->deleteLater();
        m_versionProcess = nullptr;
    }

    setStatusText(QStringLiteral("Checking for yt-dlp..."));

    m_versionProcess = new QProcess(this);
    m_versionProcess->setProgram(resolvedBinaryPath());
    m_versionProcess->setArguments({ QStringLiteral("--version") });
    m_versionProcess->setProcessChannelMode(QProcess::MergedChannels);

    connect(m_versionProcess,
            QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, &YtdlpManager::onVersionProcessFinished);
    connect(m_versionProcess, &QProcess::errorOccurred,
            this, &YtdlpManager::onVersionProcessError);

    m_versionProcess->start();
}

// Look for ffmpeg.exe / ffmpeg next to yt-dlp first, then on system PATH.
// Returns the full path if found, or an empty string if not.
static QString findFfmpeg(const QString &ytdlpBinaryPath) {
#if defined(Q_OS_WIN)
    const QString name = QStringLiteral("ffmpeg.exe");
#else
    const QString name = QStringLiteral("ffmpeg");
#endif
    // 1. Same directory as yt-dlp (bundled / AppImage install)
    if (!ytdlpBinaryPath.isEmpty()) {
        const QString candidate = QFileInfo(ytdlpBinaryPath).absolutePath() + QLatin1Char('/') + name;
        if (QFile::exists(candidate))
            return QDir::toNativeSeparators(candidate);
    }
    // 2. Flatpak ffmpeg-full extension (/app/lib/ffmpeg/ffmpeg)
    {
        const QString flatpakFf = QStringLiteral("/app/lib/ffmpeg/") + name;
        if (QFile::exists(flatpakFf))
            return flatpakFf;
    }
    // 3. System PATH
    const QString onPath = QStandardPaths::findExecutable(name);
    return onPath;
}

void YtdlpManager::onVersionProcessFinished(int exitCode, QProcess::ExitStatus exitStatus) {
    auto *proc = qobject_cast<QProcess *>(sender());
    const QString output = proc ? QString::fromUtf8(proc->readAll()).trimmed() : QString();
    if (proc) { proc->deleteLater(); m_versionProcess = nullptr; }

    if (exitCode == 0 && exitStatus == QProcess::NormalExit && !output.isEmpty()) {
        setAvailable(true);
        setVersion(output);

        // Detect ffmpeg so the UI can warn the user if it's missing.
        const QString ff = findFfmpeg(resolvedBinaryPath());
        const bool ffOk  = !ff.isEmpty();
        if (ffOk != m_ffmpegAvailable || ff != m_ffmpegPath) {
            m_ffmpegAvailable = ffOk;
            m_ffmpegPath      = ff;
            emit ffmpegAvailableChanged();
        }

        if (ffOk) {
            setStatusText(QStringLiteral("yt-dlp %1 — ffmpeg found (%2)").arg(output, ff));
        } else {
            setStatusText(QStringLiteral(
                "yt-dlp %1 — ffmpeg NOT found. HD downloads require ffmpeg. "
                "Drop ffmpeg.exe next to yt-dlp.exe or install ffmpeg to PATH.").arg(output));
        }
    } else {
        setAvailable(false);
        setVersion(QString());
        if (m_ffmpegAvailable) {
            m_ffmpegAvailable = false;
            m_ffmpegPath.clear();
            emit ffmpegAvailableChanged();
        }
        setStatusText(QStringLiteral("yt-dlp not found. Click \"Download yt-dlp\" to install it."));
    }
    emit checkComplete();
}

void YtdlpManager::onVersionProcessError(QProcess::ProcessError err) {
    Q_UNUSED(err)
    auto *proc = qobject_cast<QProcess *>(sender());
    if (proc) { proc->deleteLater(); m_versionProcess = nullptr; }

    setAvailable(false);
    setVersion(QString());
    setStatusText(QStringLiteral("yt-dlp not found. Click \"Download yt-dlp\" to install it."));
    emit checkComplete();
}

// ── Binary download ───────────────────────────────────────────────────────────

void YtdlpManager::downloadBinary() {
    if (m_downloading) return;  // already in progress

    const QString appDir  = QCoreApplication::applicationDirPath();
    const QString destPath = appDir + QLatin1Char('/') + kBinaryName;

    if (!QDir().mkpath(appDir)) {
        const QString err = QStringLiteral("Cannot write to app directory: %1").arg(appDir);
        setStatusText(err);
        emit updateComplete(false, err);
        return;
    }

    m_downloading      = true;
    m_downloadProgress = 0;
    emit downloadingChanged();
    emit downloadProgressChanged();
    setStatusText(QStringLiteral("Downloading yt-dlp…"));

    const QUrl downloadUrl{QString(kDownloadUrl)};
    QNetworkRequest req{downloadUrl};
    // Follow GitHub's redirect chain (HTTP → HTTPS → CDN)
    req.setAttribute(QNetworkRequest::RedirectPolicyAttribute,
                     QNetworkRequest::NoLessSafeRedirectPolicy);

    m_downloadReply = m_nam->get(req);
    // Store destination path so the finished slot knows where to write
    m_downloadReply->setProperty("destPath", destPath);

    connect(m_downloadReply, &QNetworkReply::downloadProgress,
            this, &YtdlpManager::onBinaryDownloadProgress);
    connect(m_downloadReply, &QNetworkReply::finished,
            this, &YtdlpManager::onBinaryDownloadFinished);
}

void YtdlpManager::onBinaryDownloadProgress(qint64 received, qint64 total) {
    if (total > 0) {
        m_downloadProgress = static_cast<int>(received * 100 / total);
        emit downloadProgressChanged();
        setStatusText(QStringLiteral("Downloading yt-dlp… %1%").arg(m_downloadProgress));
    }
}

void YtdlpManager::onBinaryDownloadFinished() {
    auto *reply = qobject_cast<QNetworkReply *>(sender());
    if (!reply) return;

    const QString destPath = reply->property("destPath").toString();

    m_downloading = false;
    emit downloadingChanged();

    if (reply->error() != QNetworkReply::NoError) {
        const QString err = reply->errorString();
        reply->deleteLater();
        m_downloadReply = nullptr;
        setStatusText(QStringLiteral("Download failed: %1").arg(err));
        emit updateComplete(false, err);
        return;
    }

    const QByteArray data = reply->readAll();
    reply->deleteLater();
    m_downloadReply = nullptr;

    if (data.isEmpty()) {
        const QString err = QStringLiteral("Download failed: server returned an empty response.");
        setStatusText(err);
        emit updateComplete(false, err);
        return;
    }

    // Write the binary to disk
    QFile file(destPath);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        const QString err = QStringLiteral("Cannot write %1: %2")
                                .arg(destPath, file.errorString());
        setStatusText(err);
        emit updateComplete(false, err);
        return;
    }
    file.write(data);
    file.close();

#if !defined(Q_OS_WIN)
    // On Linux/macOS the binary must be made executable after writing
    file.setPermissions(
        QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner |
        QFileDevice::ReadGroup | QFileDevice::ExeGroup  |
        QFileDevice::ReadOther | QFileDevice::ExeOther);
#endif

    m_downloadProgress = 100;
    emit downloadProgressChanged();

    qDebug() << "[YtdlpManager] Binary written to" << destPath;

    // Confirm the binary actually works before declaring success
    checkAvailability();
    emit updateComplete(true, QStringLiteral("yt-dlp downloaded successfully."));
}

void YtdlpManager::cancelDownload() {
    if (m_downloadReply) {
        m_downloadReply->abort();
        m_downloadReply->deleteLater();
        m_downloadReply = nullptr;
    }
    if (m_downloading) {
        m_downloading = false;
        emit downloadingChanged();
        setStatusText(QStringLiteral("Download cancelled."));
    }
}

// ── Self-update ───────────────────────────────────────────────────────────────

void YtdlpManager::selfUpdate() {
    // If the binary is not present, do a full download instead
    if (!m_available) {
        downloadBinary();
        return;
    }
    if (m_selfUpdateProcess) {
        disconnect(m_selfUpdateProcess, nullptr, this, nullptr);
        m_selfUpdateProcess->kill();
        m_selfUpdateProcess->deleteLater();
        m_selfUpdateProcess = nullptr;
    }

    setStatusText(QStringLiteral("Updating yt-dlp…"));
    m_downloading      = true;
    m_downloadProgress = 0;
    emit downloadingChanged();
    emit downloadProgressChanged();

    m_selfUpdateProcess = new QProcess(this);
    m_selfUpdateProcess->setProgram(resolvedBinaryPath());
    m_selfUpdateProcess->setArguments({ QStringLiteral("-U") });
    m_selfUpdateProcess->setProcessChannelMode(QProcess::MergedChannels);

    connect(m_selfUpdateProcess,
            QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, &YtdlpManager::onSelfUpdateFinished);

    m_selfUpdateProcess->start();
}

void YtdlpManager::onSelfUpdateFinished(int exitCode, QProcess::ExitStatus exitStatus) {
    auto *proc = qobject_cast<QProcess *>(sender());
    if (proc) { proc->deleteLater(); m_selfUpdateProcess = nullptr; }

    m_downloading = false;
    emit downloadingChanged();

    if (exitCode == 0 && exitStatus == QProcess::NormalExit) {
        // Re-probe version so the UI reflects the new version string
        checkAvailability();
        emit updateComplete(true, QStringLiteral("yt-dlp updated successfully."));
    } else {
        setStatusText(QStringLiteral("Update failed. Try clicking \"Download yt-dlp\" instead."));
        emit updateComplete(false, QStringLiteral("yt-dlp self-update exited with code %1.").arg(exitCode));
    }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

void YtdlpManager::setStatusText(const QString &text) {
    if (m_statusText != text) {
        m_statusText = text;
        emit statusTextChanged();
    }
}

void YtdlpManager::setAvailable(bool v) {
    if (m_available != v) {
        m_available = v;
        emit availableChanged();
    }
}

void YtdlpManager::setVersion(const QString &v) {
    if (m_version != v) {
        m_version = v;
        emit versionChanged();
    }
}
