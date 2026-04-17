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
#include <QProcess>
#include <QString>
#include <QByteArray>
#include <QHash>
#include <QDateTime>
#include <QVariantMap>
#include <QJsonDocument>
#include <QJsonObject>
#include "DownloadItem.h"

// Extra per-download options forwarded to yt-dlp as CLI flags.
// Defaults produce the same behaviour as the original single-video download.
struct YtdlpOptions {
    // ── Subtitles ─────────────────────────────────────────────────────────────
    bool    writeSubs           = false;   // --write-subs
    bool    writeAutoSubs       = false;   // --write-auto-subs
    QString subLangs            = QStringLiteral("en");  // --sub-langs
    bool    embedSubs           = false;   // --embed-subs (mp4/mkv/webm only)

    // ── Post-processing ───────────────────────────────────────────────────────
    bool    embedThumbnail      = false;   // --embed-thumbnail
    bool    embedMetadata       = false;   // --embed-metadata
    bool    sponsorBlock        = false;   // --sponsorblock-remove default

    // ── Filters / access ─────────────────────────────────────────────────────
    QString dateAfter;                     // --dateafter YYYYMMDD
    QString cookiesFromBrowser;            // --cookies-from-browser <browser>

    // ── Output extras ─────────────────────────────────────────────────────────
    bool    writeDescription    = false;   // --write-description
    bool    writeThumbnailFile  = false;   // --write-thumbnail (write to disk)
    bool    splitChapters       = false;   // --split-chapters (requires ffmpeg)
    QString downloadSections;             // --download-sections (e.g. "*00:30-02:45")

    // ── Playlist extras ───────────────────────────────────────────────────────
    bool    playlistRandom      = false;   // --playlist-random
    bool    liveFromStart       = false;   // --live-from-start
    bool    useArchive          = false;   // --download-archive <saveDir>/yt-dlp-archive.txt

    // ── Rate limit override ───────────────────────────────────────────────────
    // 0 = inherit global speed limit; > 0 = override for this download only.
    int     rateLimitKBps       = 0;

    // ── Serialisation (for resume persistence via DownloadItem) ───────────────
    QString toJson() const {
        QJsonObject o;
        if (writeSubs)           o[QLatin1String("writeSubs")]          = true;
        if (writeAutoSubs)       o[QLatin1String("writeAutoSubs")]      = true;
        if (!subLangs.isEmpty() && subLangs != QLatin1String("en"))
                                 o[QLatin1String("subLangs")]           = subLangs;
        if (embedSubs)           o[QLatin1String("embedSubs")]          = true;
        if (embedThumbnail)      o[QLatin1String("embedThumbnail")]     = true;
        if (embedMetadata)       o[QLatin1String("embedMetadata")]      = true;
        if (sponsorBlock)        o[QLatin1String("sponsorBlock")]       = true;
        if (!dateAfter.isEmpty())           o[QLatin1String("dateAfter")]          = dateAfter;
        if (!cookiesFromBrowser.isEmpty())  o[QLatin1String("cookiesFromBrowser")] = cookiesFromBrowser;
        if (writeDescription)    o[QLatin1String("writeDescription")]   = true;
        if (writeThumbnailFile)  o[QLatin1String("writeThumbnailFile")] = true;
        if (splitChapters)       o[QLatin1String("splitChapters")]      = true;
        if (!downloadSections.isEmpty())    o[QLatin1String("downloadSections")]   = downloadSections;
        if (playlistRandom)      o[QLatin1String("playlistRandom")]     = true;
        if (liveFromStart)       o[QLatin1String("liveFromStart")]      = true;
        if (useArchive)          o[QLatin1String("useArchive")]         = true;
        if (rateLimitKBps > 0)   o[QLatin1String("rateLimitKBps")]     = rateLimitKBps;
        return o.isEmpty() ? QString() : QString::fromUtf8(QJsonDocument(o).toJson(QJsonDocument::Compact));
    }

    static YtdlpOptions fromJson(const QString &json) {
        YtdlpOptions opts;
        if (json.isEmpty()) return opts;
        const QJsonObject o = QJsonDocument::fromJson(json.toUtf8()).object();
        opts.writeSubs          = o[QLatin1String("writeSubs")].toBool();
        opts.writeAutoSubs      = o[QLatin1String("writeAutoSubs")].toBool();
        opts.subLangs           = o[QLatin1String("subLangs")].toString(QStringLiteral("en"));
        opts.embedSubs          = o[QLatin1String("embedSubs")].toBool();
        opts.embedThumbnail     = o[QLatin1String("embedThumbnail")].toBool();
        opts.embedMetadata      = o[QLatin1String("embedMetadata")].toBool();
        opts.sponsorBlock       = o[QLatin1String("sponsorBlock")].toBool();
        opts.dateAfter          = o[QLatin1String("dateAfter")].toString();
        opts.cookiesFromBrowser = o[QLatin1String("cookiesFromBrowser")].toString();
        opts.writeDescription   = o[QLatin1String("writeDescription")].toBool();
        opts.writeThumbnailFile = o[QLatin1String("writeThumbnailFile")].toBool();
        opts.splitChapters      = o[QLatin1String("splitChapters")].toBool();
        opts.downloadSections   = o[QLatin1String("downloadSections")].toString();
        opts.playlistRandom     = o[QLatin1String("playlistRandom")].toBool();
        opts.liveFromStart      = o[QLatin1String("liveFromStart")].toBool();
        opts.useArchive         = o[QLatin1String("useArchive")].toBool();
        opts.rateLimitKBps      = o[QLatin1String("rateLimitKBps")].toInt(0);
        return opts;
    }

    // Build a YtdlpOptions from a QVariantMap passed by QML.
    static YtdlpOptions fromVariantMap(const QVariantMap &m) {
        YtdlpOptions opts;
        opts.writeSubs          = m.value(QStringLiteral("writeSubs")).toBool();
        opts.writeAutoSubs      = m.value(QStringLiteral("writeAutoSubs")).toBool();
        opts.subLangs           = m.value(QStringLiteral("subLangs"), QStringLiteral("en")).toString();
        opts.embedSubs          = m.value(QStringLiteral("embedSubs")).toBool();
        opts.embedThumbnail     = m.value(QStringLiteral("embedThumbnail")).toBool();
        opts.embedMetadata      = m.value(QStringLiteral("embedMetadata")).toBool();
        opts.sponsorBlock       = m.value(QStringLiteral("sponsorBlock")).toBool();
        opts.dateAfter          = m.value(QStringLiteral("dateAfter")).toString();
        opts.cookiesFromBrowser = m.value(QStringLiteral("cookiesFromBrowser")).toString();
        opts.writeDescription   = m.value(QStringLiteral("writeDescription")).toBool();
        opts.writeThumbnailFile = m.value(QStringLiteral("writeThumbnailFile")).toBool();
        opts.splitChapters      = m.value(QStringLiteral("splitChapters")).toBool();
        opts.downloadSections   = m.value(QStringLiteral("downloadSections")).toString();
        opts.playlistRandom     = m.value(QStringLiteral("playlistRandom")).toBool();
        opts.liveFromStart      = m.value(QStringLiteral("liveFromStart")).toBool();
        opts.useArchive         = m.value(QStringLiteral("useArchive")).toBool();
        opts.rateLimitKBps      = m.value(QStringLiteral("rateLimitKBps")).toInt();
        return opts;
    }
};

// YtdlpTransfer drives a single yt-dlp subprocess to download a video or
// audio track.  It reads yt-dlp's stdout line by line, parses the progress
// output, and keeps the associated DownloadItem up-to-date in real time
// (bytes downloaded, download speed, status).
//
// Signal interface mirrors SegmentedTransfer so AppController can handle
// both worker types with the same connection code.
//
// Two-pass downloads (video stream + audio stream → merged by ffmpeg) are
// handled transparently: progress from completed phases is accumulated and
// added to the current-phase progress so the overall percentage is smooth
// from 0 to 100 across both passes.
//
// Pause/resume model:
//   pause()  — kills the subprocess; the DownloadItem status is set to Paused.
//              The partial file remains on disk; yt-dlp can resume it.
//   resume() — provided for API symmetry.  In practice, AppController deletes
//              the old transfer and creates a new one with resume=true, which
//              passes --continue to yt-dlp so it picks up where it left off.
//   abort()  — kills the subprocess without changing item status (used when
//              the download is being deleted entirely).
class YtdlpTransfer : public QObject {
    Q_OBJECT

public:
    // item            – DownloadItem this transfer drives; must outlive the transfer.
    // ytdlpPath       – Absolute path to the yt-dlp executable.
    // formatSel       – yt-dlp format selector, e.g. "bestvideo+bestaudio/best".
    // containerFormat – Output container: "mp4", "mkv", "webm", "mp3", "m4a", etc.
    //                   Audio containers (mp3/m4a/opus/flac/wav) trigger
    //                   --extract-audio instead of --merge-output-format.
    // saveDir         – Directory where the output file will be written.
    // ffmpegPath      – Optional path to ffmpeg; empty means rely on system PATH.
    // resume          – If true, passes --continue so yt-dlp resumes a partial file.
    // jsRuntimePath   – Optional path to a JS runtime (deno/node/bun/qjs) needed
    //                   for yt-dlp's EJS YouTube n-challenge solver.  Empty = no
    //                   --js-runtimes flag; yt-dlp will attempt Deno auto-detection.
    // jsRuntimeName   – Short runtime name passed to --js-runtimes: "deno", "node",
    //                   "bun", or "quickjs".  Ignored when jsRuntimePath is empty.
    explicit YtdlpTransfer(DownloadItem *item,
                           const QString    &ytdlpPath,
                           const QString    &formatSel,
                           const QString    &containerFormat,
                           const QString    &saveDir,
                           const QString    &ffmpegPath      = {},
                           int               speedLimitKBps  = 0,
                           bool              resume          = false,
                           const QString    &outputTemplate  = {},
                           const QString    &proxyUrl        = {},
                           bool              playlistMode    = false,
                           int               maxItems        = 0,
                           const YtdlpOptions &options       = {},
                           const QString    &jsRuntimePath   = {},
                           const QString    &jsRuntimeName   = {},
                           QObject          *parent          = nullptr);
    ~YtdlpTransfer() override;

    void start();
    void pause();   // kills the process; item status → Paused
    void abort();   // kills the process; does not change item status

signals:
    void started();
    // done and total are overall bytes (across all download phases).
    // speedBps is the instantaneous speed in bytes/second.
    void progressChanged(qint64 done, qint64 total, qint64 speedBps);
    void finished();                    // yt-dlp exited 0 — file is complete
    void failed(const QString &reason); // non-zero exit or process error
    void playlistItemStarted(int index, int total, const QString &title);
    void playlistItemProgress(int index, double percent);
    void playlistItemFinished(int index);

private slots:
    void onReadyReadStdout();
    void onProcessFinished(int exitCode, QProcess::ExitStatus exitStatus);
    void onProcessError(QProcess::ProcessError err);

private:
    // Dispatch a single, complete line of yt-dlp stdout.
    void handleLine(const QString &line);

    // Parse a "[download] X% of Y.YYUnit at S.SS Unit/s ETA …" line.
    // Returns true if the line was recognized as a progress line and processed.
    bool tryParseProgressLine(const QString &line);

    // Convert a yt-dlp size token (value + unit) to bytes.
    // Units: B, KiB, MiB, GiB, TiB (and SI variants KB, MB, GB).
    static qint64 parseSizeToBytes(double value, const QString &unit);

    DownloadItem *m_item{nullptr};
    QProcess     *m_process{nullptr};
    QString       m_ytdlpPath;
    QString       m_formatSel;
    QString       m_containerFormat;
    QString       m_saveDir;
    QString       m_ffmpegPath;
    int           m_speedLimitKBps{0};
    bool          m_resume{false};
    QString       m_outputTemplate;
    QString       m_proxyUrl;   // e.g. "http://host:port" or "socks5://host:port", empty = no proxy
    bool          m_playlistMode{false};  // true → download all items in a playlist/channel
    int           m_maxItems{0};          // 0 = unlimited; N = only first N items
    YtdlpOptions  m_options;              // extra per-download flags
    QString       m_jsRuntimePath;       // path to JS runtime for EJS n-challenge solving
    QString       m_jsRuntimeName;       // "deno", "node", "bun", or "quickjs"
    bool          m_aborted{false};

    // Accumulation buffer for incomplete stdout lines.
    QByteArray    m_lineBuf;
    // All non-progress lines collected for error reporting.
    QStringList   m_allLines;

    // ── Multi-phase progress tracking ────────────────────────────────────────
    // yt-dlp downloads video and audio as separate passes when the best quality
    // format requires merging.  We track each phase independently and produce
    // a single smooth progress arc across all phases.
    //
    // Phase transition detection: when the reported percentage drops from >90 %
    // back to near 0 %, a new download phase has started (audio after video).

    // Snapshot of save-directory files taken just before the process starts.
    // Maps filename → size-in-bytes at launch time.  The fallback filename
    // reconciliation at completion uses this to restrict candidates to files
    // that are genuinely new (not in snapshot) or grew since launch (resume),
    // rather than any file touched within a broad recent-time window.
    QHash<QString, qint64> m_preLaunchSnapshot;

    qint64 m_accumulatedBytes{0};   // bytes from fully-completed phases
    qint64 m_currentPhaseDone{0};   // bytes received in the running phase
    qint64 m_currentPhaseTotal{0};  // total bytes announced for the running phase
    double m_lastPercent{0.0};      // last percentage seen in the running phase
    bool   m_seenFullPhase{false};  // true once the first 100 % has been seen
    int    m_playlistCurrentIndex{0};
    int    m_playlistTotalItems{0};
};
