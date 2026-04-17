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
#include <QCryptographicHash>
#include <QFile>
#include <QFileInfo>
#include <QDir>
#include <QNetworkRequest>
#include <QProcess>
#include <QStandardPaths>
#include <QDebug>

namespace {
QString writableToolRoot() {
    QString dir = QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation);
    if (dir.isEmpty())
        dir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    if (dir.isEmpty())
        dir = QCoreApplication::applicationDirPath();
    dir += QLatin1String("/tools");
    QDir().mkpath(dir);
    return dir;
}
}

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

// SECURITY: CWE-494 — yt-dlp publishes a SHA2-512SUMS file alongside each
// release binary.  We fetch it first and verify the downloaded binary before
// making it executable.  Without this check, a MITM (DNS hijack, rogue CDN
// node, or GitHub account compromise) could serve a malicious binary that
// would be silently written to disk and immediately executed via
// checkAvailability().  Fetching both artefacts over TLS from the same host
// under Qt's NoLessSafeRedirectPolicy means an attacker must compromise the
// HTTPS channel or the release artefacts simultaneously — feasible for a
// nation-state, but eliminates the easy passive MITM case.
static const QLatin1String kSumsUrl(
    "https://github.com/yt-dlp/yt-dlp/releases/latest/download/SHA2-512SUMS");

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

    // 2. Writable app-local tool install (preferred for self-updates on Linux)
    const QString writable = writableToolRoot() + QLatin1Char('/') + kBinaryName;
    if (QFile::exists(writable))
        return writable;

    // 3. Bundled binary next to the application executable
    const QString appDir = QCoreApplication::applicationDirPath();
    const QString bundled = appDir + QLatin1Char('/') + kBinaryName;
    if (QFile::exists(bundled))
        return bundled;

    // 4. Fall back to the bare name so the OS will search PATH
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

void YtdlpManager::setCustomJsRuntimePath(const QString &path) {
    if (m_customJsRuntimePath == path) return;
    m_customJsRuntimePath = path;
    detectJsRuntime();
}

// Search for a JS runtime binary in the given directory.
// Fills outPath and outName on success; returns true.
static bool findRuntimeInDir(const QString &dir,
                              QString &outPath, QString &outName)
{
    struct Candidate { const char *exe; const char *name; };
#if defined(Q_OS_WIN)
    static const Candidate kCandidates[] = {
        { "deno.exe",   "deno"    },
        { "node.exe",   "node"    },
        { "bun.exe",    "bun"     },
        { "qjs.exe",    "quickjs" },
        { nullptr, nullptr }
    };
#else
    static const Candidate kCandidates[] = {
        { "deno",    "deno"    },
        { "node",    "node"    },
        { "nodejs",  "node"    },
        { "bun",     "bun"     },
        { "qjs",     "quickjs" },
        { nullptr, nullptr }
    };
#endif
    for (int i = 0; kCandidates[i].exe; ++i) {
        const QString p = dir + QLatin1Char('/') + QLatin1String(kCandidates[i].exe);
        if (QFile::exists(p)) {
            outPath = QDir::toNativeSeparators(p);
            outName = QLatin1String(kCandidates[i].name);
            return true;
        }
    }
    return false;
}

void YtdlpManager::detectJsRuntime() {
    QString path, name;

    // 1. User-supplied override takes absolute precedence.
    if (!m_customJsRuntimePath.trimmed().isEmpty()) {
        const QFileInfo fi(m_customJsRuntimePath.trimmed());
        if (fi.exists() && fi.isFile()) {
            // Derive the runtime name from the binary filename.
            const QString base = fi.baseName().toLower();
            if (base.startsWith(QLatin1String("deno")))         name = QStringLiteral("deno");
            else if (base.startsWith(QLatin1String("node")))    name = QStringLiteral("node");
            else if (base.startsWith(QLatin1String("bun")))     name = QStringLiteral("bun");
            else if (base.startsWith(QLatin1String("qjs")))     name = QStringLiteral("quickjs");
            else                                                 name = base;
            path = QDir::toNativeSeparators(m_customJsRuntimePath.trimmed());
        }
        // Custom path set but invalid — don't fall back to auto-detection; the user
        // explicitly configured something, so surface the "not found" state.
        goto done;
    }

    // 2. Same directory as the yt-dlp binary (bundled install).
    {
        const QString ytdlpDir = QFileInfo(resolvedBinaryPath()).absolutePath();
        if (findRuntimeInDir(ytdlpDir, path, name)) goto done;
    }

    // 3. App executable directory.
    if (findRuntimeInDir(QCoreApplication::applicationDirPath(), path, name)) goto done;

    // 4. Writable tool root (where we also download yt-dlp itself).
    if (findRuntimeInDir(writableToolRoot(), path, name)) goto done;

    // 5. System PATH — try each candidate name.
    {
        static const struct { const char *exe; const char *rname; } kPathNames[] = {
            { "deno",   "deno"    },
            { "node",   "node"    },
#if !defined(Q_OS_WIN)
            { "nodejs", "node"    },
#endif
            { "bun",    "bun"     },
            { "qjs",    "quickjs" },
            { nullptr, nullptr }
        };
        for (int i = 0; kPathNames[i].exe; ++i) {
            const QString found = QStandardPaths::findExecutable(QLatin1String(kPathNames[i].exe));
            if (!found.isEmpty()) {
                path = found;
                name = QLatin1String(kPathNames[i].rname);
                goto done;
            }
        }
    }

done:
    if (path != m_jsRuntimePath || name != m_jsRuntimeName) {
        m_jsRuntimePath = path;
        m_jsRuntimeName = name;
        emit jsRuntimeChanged();
        if (!path.isEmpty())
            qDebug() << "[YtdlpManager] JS runtime:" << name << "->" << path;
        else
            qDebug() << "[YtdlpManager] No JS runtime found (yt-dlp YouTube n-challenge will fail)";
    }
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

// Check whether both ffmpeg and ffprobe exist in the given directory.
// Returns the path to ffmpeg if found there, empty string otherwise.
// *outHasFfprobe is set accordingly (only meaningful when return is non-empty).
static QString probeDir(const QString &dir, bool *outHasFfprobe) {
#if defined(Q_OS_WIN)
    static const QLatin1String kFfmpeg("ffmpeg.exe");
    static const QLatin1String kFfprobe("ffprobe.exe");
#else
    static const QLatin1String kFfmpeg("ffmpeg");
    static const QLatin1String kFfprobe("ffprobe");
#endif
    const QString ff = dir + QLatin1Char('/') + kFfmpeg;
    if (!QFile::exists(ff)) return {};
    *outHasFfprobe = QFile::exists(dir + QLatin1Char('/') + kFfprobe);
    return QDir::toNativeSeparators(ff);
}

// Find the best ffmpeg installation for passing to yt-dlp's --ffmpeg-location.
//
// yt-dlp derives the search directory for ALL post-processing tools (ffmpeg,
// ffprobe, ffplay, …) from the parent directory of whatever path is passed to
// --ffmpeg-location.  If ffprobe is absent from that directory, post-processing
// steps that need it (thumbnail embedding, chapter modification) will fail even
// if ffprobe is available elsewhere on PATH.
//
// Strategy:
//   1. Search candidate directories in priority order; return the first one
//      that has BOTH ffmpeg and ffprobe.
//   2. If no co-located pair is found, check whether ffprobe exists on PATH;
//      if so, return empty — letting yt-dlp fall back to PATH search for both
//      tools (only safe when ffmpeg is also reachable via PATH).
//   3. Last resort: return ffmpeg-alone path so at least merging works.
static QString findFfmpeg(const QString &ytdlpBinaryPath) {
#if defined(Q_OS_WIN)
    static const QLatin1String kFfmpegExe("ffmpeg.exe");
    static const QLatin1String kFfprobeExe("ffprobe.exe");
#else
    static const QLatin1String kFfmpegExe("ffmpeg");
    static const QLatin1String kFfprobeExe("ffprobe");
#endif

    QString ffmpegOnlyFallback;  // ffmpeg found but ffprobe absent — kept as last resort

    auto tryDir = [&](const QString &dir) -> QString {
        bool hasFfprobe = false;
        const QString ff = probeDir(dir, &hasFfprobe);
        if (ff.isEmpty()) return {};
        if (hasFfprobe)   return ff;
        if (ffmpegOnlyFallback.isEmpty()) ffmpegOnlyFallback = ff;
        return {};
    };

    // 1. Same directory as yt-dlp binary (bundled install)
    if (!ytdlpBinaryPath.isEmpty()) {
        if (const QString r = tryDir(QFileInfo(ytdlpBinaryPath).absolutePath()); !r.isEmpty()) return r;
    }

    // 2. Writable tool root (where Stellar self-downloads yt-dlp)
    if (const QString r = tryDir(writableToolRoot()); !r.isEmpty()) return r;

    // 3. Flatpak ffmpeg-full extension
    if (const QString r = tryDir(QStringLiteral("/app/lib/ffmpeg")); !r.isEmpty()) return r;

    // 4. System PATH — ffmpeg's directory might also contain ffprobe
    {
        const QString pathFfmpeg = QStandardPaths::findExecutable(QString(kFfmpegExe));
        if (!pathFfmpeg.isEmpty()) {
            if (const QString r = tryDir(QFileInfo(pathFfmpeg).absolutePath()); !r.isEmpty()) return r;
        }
    }

    // No co-located ffmpeg+ffprobe pair found anywhere.
    // If ffprobe IS available on PATH independently, return empty so that
    // yt-dlp resolves both tools from PATH rather than being locked to a
    // directory that only has ffmpeg (which would shadow the PATH ffprobe).
    const QString pathFfprobe = QStandardPaths::findExecutable(QString(kFfprobeExe));
    if (!pathFfprobe.isEmpty()) {
        // ffprobe is on PATH; check whether ffmpeg is also on PATH — if so,
        // returning empty is safe (yt-dlp will pick up both from PATH).
        const QString pathFfmpeg2 = QStandardPaths::findExecutable(QString(kFfmpegExe));
        if (!pathFfmpeg2.isEmpty())
            return {};  // let yt-dlp use PATH for the full suite
        // ffprobe on PATH but ffmpeg is NOT; pass ffprobe's directory as the
        // location so yt-dlp at least finds ffprobe (ffmpeg from PATH will be
        // missing but that situation is unusual and the user will see an error).
        return QDir::toNativeSeparators(pathFfprobe);
    }

    // Last resort: ffmpeg-only location — merging works, ffprobe-dependent
    // post-processing (chapter modification, some thumbnail embedding) will fail.
    return ffmpegOnlyFallback;
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

        // Detect JS runtime for yt-dlp EJS YouTube n-challenge solver.
        detectJsRuntime();
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

    const QString appDir  = writableToolRoot();
    const QString destPath = appDir + QLatin1Char('/') + kBinaryName;

    if (!QDir().mkpath(appDir)) {
        const QString err = QStringLiteral("Cannot write to app directory: %1").arg(appDir);
        setStatusText(err);
        emit updateComplete(false, err);
        return;
    }

    m_downloading      = true;
    m_expectedSha512.clear();
    m_downloadProgress = 0;
    emit downloadingChanged();
    emit downloadProgressChanged();

    // Step 1: fetch the SHA2-512SUMS manifest from the same GitHub release.
    // The binary download starts only after we have the expected hash (step 2
    // below), so we can verify the binary before making it executable.
    setStatusText(QStringLiteral("Fetching yt-dlp checksum…"));
    QNetworkRequest sumsReq{QUrl(QString(kSumsUrl))};
    sumsReq.setAttribute(QNetworkRequest::RedirectPolicyAttribute,
                         QNetworkRequest::NoLessSafeRedirectPolicy);
    m_sumsReply = m_nam->get(sumsReq);
    m_sumsReply->setProperty("destPath", destPath);

    connect(m_sumsReply, &QNetworkReply::finished, this, [this]() {
        auto *sumsReply = qobject_cast<QNetworkReply *>(sender());
        if (!sumsReply) return;
        const QString destPath = sumsReply->property("destPath").toString();

        if (sumsReply->error() != QNetworkReply::NoError) {
            // SECURITY: CWE-494 — fail closed.  A MITM can trivially block the
            // SUMS request (TCP RST, 404, timeout) to bypass hash verification
            // and serve a malicious binary.  We refuse to proceed rather than
            // installing an unverified binary.
            const QString err = QStringLiteral("Could not fetch SHA2-512SUMS: %1. "
                "Aborting to prevent installing an unverified binary.")
                .arg(sumsReply->errorString());
            qWarning() << "[YtdlpManager]" << err;
            sumsReply->deleteLater();
            m_sumsReply  = nullptr;
            m_downloading = false;
            emit downloadingChanged();
            setStatusText(err);
            emit updateComplete(false, err);
            return;
        } else {
            // Parse "hash  filename" lines; find the entry for our binary.
            const QByteArray sumsData = sumsReply->readAll();
            for (const QByteArray &line : sumsData.split('\n')) {
                const QByteArray trimmed = line.trimmed();
                if (trimmed.isEmpty()) continue;
                // Format: "<sha512hex>  <filename>" (two spaces)
                const int sep = trimmed.indexOf("  ");
                if (sep < 0) continue;
                const QByteArray filename = trimmed.mid(sep + 2).trimmed();
                if (filename == kBinaryName) {
                    m_expectedSha512 = QString::fromLatin1(trimmed.left(sep).trimmed().toLower());
                    qDebug() << "[YtdlpManager] Expected SHA-512:" << m_expectedSha512;
                    break;
                }
            }
            if (m_expectedSha512.isEmpty()) {
                // SECURITY: CWE-494 — fail closed. A malformed or tampered manifest
                // that simply omits our binary name must not be treated as "no check
                // needed". Proceeding without a known-good hash would let an attacker
                // serve an arbitrary binary by publishing a manifest that doesn't
                // list our file.
                const QString err = QStringLiteral(
                    "yt-dlp binary name not found in SHA2-512SUMS manifest. "
                    "Aborting to prevent installing an unverified binary.");
                qWarning() << "[YtdlpManager]" << err;
                sumsReply->deleteLater();
                m_sumsReply   = nullptr;
                m_downloading = false;
                emit downloadingChanged();
                setStatusText(err);
                emit updateComplete(false, err);
                return;
            }
        }

        sumsReply->deleteLater();
        m_sumsReply = nullptr;

        // Step 2: now download the binary itself.
        setStatusText(QStringLiteral("Downloading yt-dlp…"));
        QNetworkRequest req{QUrl(QString(kDownloadUrl))};
        req.setAttribute(QNetworkRequest::RedirectPolicyAttribute,
                         QNetworkRequest::NoLessSafeRedirectPolicy);
        m_downloadReply = m_nam->get(req);
        m_downloadReply->setProperty("destPath", destPath);
        connect(m_downloadReply, &QNetworkReply::downloadProgress,
                this, &YtdlpManager::onBinaryDownloadProgress);
        connect(m_downloadReply, &QNetworkReply::finished,
                this, &YtdlpManager::onBinaryDownloadFinished);
    });
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

    // SECURITY: CWE-494 — verify SHA-512 before writing to disk.
    // m_expectedSha512 was fetched from GitHub's SHA2-512SUMS file for this
    // release (see downloadBinary()).  We abort if the hash is absent (the
    // manifest parsing already prevents reaching here without one, but this
    // is a belt-and-suspenders guard) or if it doesn't match — a mismatch
    // means the download was corrupted or tampered with in transit.
    if (m_expectedSha512.isEmpty()) {
        const QString err = QStringLiteral(
            "yt-dlp binary integrity check skipped — no expected hash. "
            "Aborting to prevent installing an unverified binary.");
        qWarning() << "[YtdlpManager]" << err;
        setStatusText(err);
        emit updateComplete(false, err);
        return;
    }
    {
        const QString actualSha512 = QString::fromLatin1(
            QCryptographicHash::hash(data, QCryptographicHash::Sha512).toHex().toLower());
        if (actualSha512 != m_expectedSha512) {
            const QString err = QStringLiteral(
                "yt-dlp binary failed SHA-512 verification. "
                "The download may have been tampered with. Aborting.");
            qWarning() << "[YtdlpManager]" << err;
            setStatusText(err);
            emit updateComplete(false, err);
            return;
        }
        qDebug() << "[YtdlpManager] SHA-512 verified OK.";
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
    // Abort the SUMS fetch if it's still in flight (step 1 of downloadBinary).
    if (m_sumsReply) {
        m_sumsReply->abort();
        m_sumsReply->deleteLater();
        m_sumsReply = nullptr;
    }
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
