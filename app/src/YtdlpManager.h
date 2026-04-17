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
#include <QObject>
#include <QString>
#include <QProcess>
#include <QNetworkAccessManager>
#include <QNetworkReply>

// YtdlpManager manages the yt-dlp standalone binary lifecycle: discovery,
// version checking, downloading from GitHub releases, and self-updating.
//
// Binary search order:
//   1. Custom path set via setCustomPath() (user preference from settings)
//   2. Next to the application executable (bundled install)
//   3. Bare binary name — OS PATH lookup (system-installed yt-dlp)
//
// All network and process operations are async; results are communicated
// via signals so the UI never blocks.
class YtdlpManager : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool    available        READ available        NOTIFY availableChanged)
    Q_PROPERTY(QString version          READ version          NOTIFY versionChanged)
    Q_PROPERTY(bool    downloading      READ downloading      NOTIFY downloadingChanged)
    Q_PROPERTY(int     downloadProgress READ downloadProgress NOTIFY downloadProgressChanged)
    Q_PROPERTY(QString statusText       READ statusText       NOTIFY statusTextChanged)
    // True if ffmpeg is found next to yt-dlp or on PATH (required for HD mp4 merging)
    Q_PROPERTY(bool    ffmpegAvailable  READ ffmpegAvailable  NOTIFY ffmpegAvailableChanged)
    Q_PROPERTY(QString ffmpegPath       READ ffmpegPath       NOTIFY ffmpegAvailableChanged)
    // JavaScript runtime for yt-dlp's EJS YouTube challenge solver.
    // yt-dlp bundles the EJS scripts in its .exe but needs an external runtime
    // (Deno, Node.js, Bun, or QuickJS) to execute them.
    Q_PROPERTY(bool    jsRuntimeAvailable READ jsRuntimeAvailable NOTIFY jsRuntimeChanged)
    Q_PROPERTY(QString jsRuntimePath      READ jsRuntimePath      NOTIFY jsRuntimeChanged)
    Q_PROPERTY(QString jsRuntimeName      READ jsRuntimeName      NOTIFY jsRuntimeChanged)

public:
    explicit YtdlpManager(QNetworkAccessManager *nam, QObject *parent = nullptr);

    // ── Accessors ────────────────────────────────────────────────────────────────
    bool    available()        const { return m_available; }
    QString version()          const { return m_version; }
    bool    downloading()      const { return m_downloading; }
    int     downloadProgress() const { return m_downloadProgress; }
    QString statusText()       const { return m_statusText; }
    bool    ffmpegAvailable()  const { return m_ffmpegAvailable; }
    QString ffmpegPath()       const { return m_ffmpegPath; }
    bool    jsRuntimeAvailable() const { return !m_jsRuntimePath.isEmpty(); }
    // Resolved path to the runtime binary (may be user-overridden via setCustomJsRuntimePath).
    QString jsRuntimePath()    const { return m_jsRuntimePath; }
    // Short name for --js-runtimes: "deno", "node", "bun", or "quickjs".
    QString jsRuntimeName()    const { return m_jsRuntimeName; }

    // Override the JS runtime location. Pass empty to re-run auto-detection.
    void    setCustomJsRuntimePath(const QString &path);

    // Returns the resolved path to the yt-dlp executable.
    // The file may not yet exist (e.g., before downloadBinary() is called).
    QString binaryPath() const;

    // Override the binary location. Pass an empty string to reset to auto-detect.
    void    setCustomPath(const QString &path);
    QString customPath() const { return m_customPath; }

    // ── Actions ──────────────────────────────────────────────────────────────────

    // Asynchronously check whether the binary is accessible and retrieve its
    // version string.  Emits availableChanged(), versionChanged(), statusTextChanged(),
    // and checkComplete() when done.
    Q_INVOKABLE void checkAvailability();

    // Download the latest yt-dlp release binary from GitHub into the app directory.
    // Emits downloadProgressChanged() during the transfer and updateComplete() on finish.
    Q_INVOKABLE void downloadBinary();

    // Ask yt-dlp to update itself (runs "yt-dlp -U").
    // Falls back to downloadBinary() if the binary is not currently available.
    Q_INVOKABLE void selfUpdate();

    // Abort any in-flight binary download.
    Q_INVOKABLE void cancelDownload();

signals:
    void availableChanged();
    void versionChanged();
    void downloadingChanged();
    void downloadProgressChanged();
    void statusTextChanged();
    void ffmpegAvailableChanged();
    void jsRuntimeChanged();

    // Emitted after checkAvailability() completes (regardless of outcome).
    void checkComplete();

    // Emitted after downloadBinary() or selfUpdate() finishes.
    // success=true means the binary is now present and functional.
    void updateComplete(bool success, const QString &message);

private slots:
    void onVersionProcessFinished(int exitCode, QProcess::ExitStatus status);
    void onVersionProcessError(QProcess::ProcessError err);
    void onBinaryDownloadProgress(qint64 received, qint64 total);
    void onBinaryDownloadFinished();
    void onSelfUpdateFinished(int exitCode, QProcess::ExitStatus status);

private:
    QString resolvedBinaryPath() const;  // internal: apply search order
    void    setStatusText(const QString &text);
    void    setAvailable(bool v);
    void    setVersion(const QString &v);
    // Scan PATH and app directory for a usable JS runtime; sets m_jsRuntimePath/Name.
    void    detectJsRuntime();

    QNetworkAccessManager *m_nam{nullptr};
    QString                m_customPath;
    bool                   m_available{false};
    QString                m_version;
    bool                   m_downloading{false};
    bool                   m_ffmpegAvailable{false};
    QString                m_ffmpegPath;
    QString                m_jsRuntimePath;  // resolved path to JS runtime binary
    QString                m_jsRuntimeName;  // "deno", "node", "bun", or "quickjs"
    QString                m_customJsRuntimePath; // user override, empty = auto
    int                    m_downloadProgress{0};
    QString                m_statusText;

    // SHA-512 hex digest fetched from GitHub's SHA2-512SUMS file before the
    // binary download starts; verified in onBinaryDownloadFinished().
    QString m_expectedSha512;

    QProcess      *m_versionProcess{nullptr};    // running --version probe
    QProcess      *m_selfUpdateProcess{nullptr}; // running -U self-update
    QNetworkReply *m_downloadReply{nullptr};     // in-flight binary download
    QNetworkReply *m_sumsReply{nullptr};         // in-flight SHA2-512SUMS fetch
};
