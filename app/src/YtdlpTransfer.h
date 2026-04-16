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
#include "DownloadItem.h"

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
    explicit YtdlpTransfer(DownloadItem *item,
                           const QString &ytdlpPath,
                           const QString &formatSel,
                           const QString &containerFormat,
                           const QString &saveDir,
                           const QString &ffmpegPath      = {},
                           int            speedLimitKBps  = 0,
                           bool           resume          = false,
                           const QString &outputTemplate  = {},
                           const QString &proxyUrl        = {},
                           bool           playlistMode    = false,
                           int            maxItems        = 0,
                           QObject       *parent          = nullptr);
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
