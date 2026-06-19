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
#include <QNetworkAccessManager>
#include <QNetworkRequest>
#include <QNetworkReply>
#include <QFile>
#include <QTimer>
#include <QList>
#include <QVariantMap>
#include <atomic>
#include <memory>
#include "DownloadItem.h"
#include "Transfer.h"

class QThread;

class SegmentedTransfer : public Transfer {
    Q_OBJECT

public:
    static constexpr int kDefaultSegments        = 8;
    static constexpr qint64 kMinSegmentSize      = 512 * 1024;       // 512 KB
    static constexpr int kMaxSegmentRetries      = 4;                // per segment: 1s/2s/4s/8s backoff
    static constexpr int kStallTimeoutMs         = 30'000;           // bytes must arrive within this window
    static constexpr qint64 kStealThresholdBytes = 32 * 1024 * 1024; // only steal if victim has >32 MB left (avoids end-game micro-split thrash on fast links)
    static constexpr int kMaxDynamicSegments     = 32;               // hard cap on segment count

    // Progress tick cadence and derived sliding-window sizes
    static constexpr int kTickIntervalMs         = 250;              // onProgressTick fires every 250 ms
    static constexpr int kSpeedWindowTicks       = 120;              // 30 s history  (120 × 250 ms)
    static constexpr int kDisplayWindowTicks     = 8;                // 2 s display   (8 × 250 ms)
    static constexpr int kMetaSaveIntervalTicks  = 20;               // save every 5 s (20 × 250 ms)

    // Throttle read-buffer sizing
    static constexpr int kReadBufferSeconds      = 4;                // QNAM buffer = N seconds of budget/seg
    static constexpr qint64 kMinReadBufferBytes  = 128 * 1024;       // floor so low-rate/many-seg don't starve

    // Async disk-writer sizing. Streaming writes go to a dedicated writer
    // thread; when the disk can't keep up with the network the queue fills to
    // this cap, reads stop, QNAM's bounded read buffer fills, and TCP
    // backpressure slows the server — instead of QFile::write() blocking the
    // GUI thread for seconds ("Not Responding" at >1 GB/s on localhost).
    static constexpr qint64 kMaxQueuedWriteBytes      = 64LL * 1024 * 1024;  // 64 MB in-flight cap
    static constexpr qint64 kUnthrottledReadBufferBytes = 16LL * 1024 * 1024; // per-reply QNAM buffer

    explicit SegmentedTransfer(DownloadItem *item,
                               QNetworkAccessManager *nam,
                               int segments = kDefaultSegments,
                               QObject *parent = nullptr);
    ~SegmentedTransfer();

    Q_INVOKABLE void start() override;
    Q_INVOKABLE void pause() override;
    Q_INVOKABLE void resume() override;
    Q_INVOKABLE void abort() override;
    Q_INVOKABLE bool relocateOutput(const QString &newSavePath, const QString &newFilename) override;

    void setSpeedLimitKBps(int kbps) override;
    void setCustomUserAgentEnabled(bool enabled) override;
    void setCustomUserAgent(const QString &userAgent) override;
    void setTemporaryDirectory(const QString &path) override;
    void setMaxConnectionsPerHost(int v) override;

    // Parse Content-Disposition header for filename (RFC 5987 + plain).
    // Returns empty string if no filename found. Public so probeFileInfo() can
    // extract filenames from HEAD responses without a full SegmentedTransfer.
    static QString parseContentDispositionFilename(const QByteArray &header);

    // started(), progressChanged(), finished(), failed(), fileDeletedWarning()
    // are inherited from Transfer — do not redeclare (MOC would emit duplicates).

private:
    struct Segment {
        int index{0};
        qint64 startOffset{0};
        qint64 endOffset{0};    // inclusive
        qint64 received{0};     // bytes written to disk
        QString partPath;
        QFile *file{nullptr};
        QNetworkReply *reply{nullptr};
        bool done{false};
        QByteArray pending;      // tail bytes from onSegmentFinished in throttled mode
        bool networkDone{false}; // reply finished but pending not yet flushed
        int    retryCount{0};    // number of retries attempted for this segment
        int    lastHttpStatus{0}; // last HTTP status seen on this segment (for retry-exhaustion message)
        qint64 lastByteTime{0};  // QDateTime::currentMSecsSinceEpoch() of last received byte
        qint64 lastTickReceived{0}; // seg.received snapshot at previous progress tick
        double speedBps{0.0};       // EMA-smoothed per-connection speed (bytes/sec)
        // Gave up as an "excess" connection the server wouldn't accept (refused/
        // reset with zero bytes ever received) while other segments stayed healthy.
        // Shown as "Disconnected" in the UI; NOT retried and does NOT fail the
        // whole download. Its byte range is covered by the surviving connections
        // via maybeStealWork()/pending-range redistribution.
        bool   disconnected{false};
        // True after maybeStealWork() has shortened this segment's endOffset
        // and handed the second half to a new dynamic segment. Used by the UI
        // to flag the slot as "stolen from" (red marker on the progress bar)
        // instead of mistakenly displaying it as Complete once the shortened
        // range fills.
        bool   stolenFrom{false};
        // UI slot this segment should appear in. The connections-list dialog
        // shows m_segmentCount fixed rows; dynamic segments inherit the slot
        // of the segment they were spawned from, so the row "recycles" to the
        // newer connection rather than accumulating completed/stolen rows.
        int    uiSlot{-1};
        // Bytes actually flushed to disk by the writer thread (or by the
        // synchronous throttled path). `received` counts bytes accepted from
        // the network — it can run ahead of `flushed` by up to
        // kMaxQueuedWriteBytes while writes are queued. saveMeta() persists
        // flushed (never received) so a crash mid-queue can't leave the meta
        // claiming bytes the part file doesn't have. shared_ptr so writer-thread
        // jobs outliving a segment-list rebuild touch valid memory.
        std::shared_ptr<std::atomic<qint64>> flushed{std::make_shared<std::atomic<qint64>>(0)};
    };

    void sendHeadRequest(const QUrl &overrideUrl = QUrl());
    void onHeadFinished(QNetworkReply *reply);
    void setupSegments(qint64 totalBytes, bool resumeCapable);
    void startAllSegments();
    // Connection ramp-up (IDM/aria2-style): open ONE lead segment first; only
    // after the server proves it accepts the connection and delivers bytes do we
    // open the rest. Prevents a startup "thundering herd" against connection-
    // limited servers — without it, every segment opens at t=0, all but the one
    // or two the server tolerates fail near-simultaneously before any is
    // established, hasHealthyProgress() is false for all of them, and they
    // retry-spam through the full backoff ladder instead of cleanly dropping to
    // "Disconnected".
    void startRamped();
    // Called once the lead connection has confirmed bytes (or on resume when a
    // segment already has data): opens every remaining pending segment up to the
    // per-host cap, in one shot, now that a healthy connection is guaranteed.
    void unlockRamp();
    void startSegment(Segment &seg);
    void onSegmentReadyRead(int index);
    void onSegmentFinished(int index);
    void onProgressTick();
    void mergeAndFinish();
    void cleanupPartFiles();
    void deleteMetaFile();

    bool saveMeta();
    bool loadMeta();
    QString tempBaseDirectory() const;
    QString metaPath() const;
    QString partPath(int index) const;

    void updateSegmentDataOnItem();
    void updateFilenameFromReply(QNetworkReply *reply);
    // Parse an HTML interstitial ("click to download" / virus-scan / confirmation
    // page) for the real download target and re-drive the download against it.
    // Host-agnostic: covers Google Drive's confirmation page and any similar
    // gateway. Same-domain gated before re-requesting (see sameRegisteredDomain).
    void handleInterstitialPage(const QByteArray &html);
    // Extract the real download URL from an HTML interstitial body. Tries, in
    // order: <meta http-equiv="refresh">, the first plausible <form action>, then
    // the first download-hinting <a href>. Returns an invalid QUrl if none found.
    // Relative URLs are resolved against the item URL; caller must still apply the
    // same-domain security gate.
    QUrl extractInterstitialTarget(const QByteArray &html) const;
    // True when two URLs share the same registered domain (eTLD+1) and scheme.
    // Used as a security gate before following any URL parsed out of a server
    // response or query string, so credentialed requests never go off-host.
    static bool sameRegisteredDomain(const QUrl &a, const QUrl &b);
    // True when the URL path's extension implies a binary file but the server
    // answers with text/html and no Content-Disposition attachment — i.e. an
    // HTML page (login wall, viewer wrapper, error page) masquerading as the
    // requested binary. Used to recover or fail instead of saving garbage.
    bool looksLikeHtmlMasqueradingAsBinary(const QUrl &url,
                                           const QString &contentTypeLower,
                                           const QByteArray &contentDisposition) const;
    // Attempt to recover the real file when a masquerade is detected: scan the
    // original URL's query for a same-domain value pointing at the expected
    // file (e.g. iframeUrlOverride) and re-drive the download against it.
    // Returns true if a recovery HEAD was issued (caller must return).
    bool tryRecoverMasqueradedUrl(const QString &expectedExt);
    static QString htmlMasqueradeError();
    // True when the URL path carries no file extension (e.g. "/uc?id=...",
    // "/download?file=..."). Extensionless cloud-download endpoints are the ones
    // that gate behind an HTML interstitial and/or a browser User-Agent, so this
    // drives the interstitial trigger and UA choice without any host allowlist.
    static bool urlHasNoExtension(const QUrl &url);
    void applyRequestHeaders(QNetworkRequest &req, const QUrl &url) const;
    void applyReplyReadBufferSize(QNetworkReply *reply);
    void retrySegment(int index, int extraDelayMs = 0);
    void fallbackToSingleSegment();
    bool maybeStealWork(int freedUiSlot = -1);
    void startNextPendingSegment();
    void seedCookieJar();
    // True if at least one segment is still a live, non-disconnected worker that
    // can carry the download forward (active reply, or already has bytes and isn't
    // done). Used to decide whether a refused/failed connection can be silently
    // dropped as "excess" instead of failing the whole download.
    bool hasHealthyProgress(int excludeIndex = -1) const;
    // Mark a segment as a silently-dropped excess connection and re-cover its
    // outstanding byte range with the surviving connections.
    void markSegmentDisconnected(int index);

    // --- Async disk writer -------------------------------------------------
    // Streaming segment writes run on a dedicated thread so a slow/saturated
    // disk never blocks the GUI thread. All ops on one segment's QFile are
    // FIFO-ordered through the writer's event queue; the main thread must call
    // flushDiskWrites() before touching a part file directly (reopen, seek,
    // delete, rename, merge).
    void ensureDiskWriter();
    void enqueueSegmentWrite(Segment &seg, QByteArray data);
    // Blocking barrier: returns once every queued write/close has executed.
    // Bounded by kMaxQueuedWriteBytes of disk time; no-op when no writer.
    void flushDiskWrites();
    // Close a segment's file ordered after its queued writes (direct close
    // when no writer thread exists).
    void closeSegmentFile(Segment &seg);
    void onAsyncWriteFailed(const QString &error);

    DownloadItem          *m_item{nullptr};
    QNetworkAccessManager *m_nam{nullptr};
    int                    m_segmentCount;
    bool                   m_paused{false};
    bool                   m_cancelled{false};
    bool                   m_resumeCapable{false};
    int                    m_speedLimitKBps{0};
    bool                   m_htmlIntercepting{false};
    QByteArray             m_htmlInterceptBuf;
    bool                   m_recoveryAttempted{false}; // guards single masquerade-recovery retry
    // Set when a response looks like an HTML interstitial standing in for a binary
    // download (text/html, no Content-Disposition, extensionless or binary-ext
    // URL). Drives the browser-UA choice and the HTML-intercept / auth-wall logic.
    // Reset at the start of every run. Replaces the old GDrive host allowlist.
    bool                   m_expectInterstitial{false};

    QList<Segment>  m_segments;
    QTimer         *m_progressTimer{nullptr};
    qint64          m_lastReceived{0};
    QList<qint64>   m_speedSamples;   // per-tick byte deltas, max 120 entries (30 s)
    int             m_ticksSinceMetaSave{0}; // periodic meta save counter
    bool            m_useCustomUserAgent{false};
    QString         m_customUserAgent;
    QString         m_temporaryDirectory;
    QString         m_etag;
    QString         m_lastModified;
    int             m_maxConnectionsPerHost{8};
    // Ramp gate: false until the lead connection has confirmed it is receiving
    // bytes. While false only one segment is allowed to be open; unlockRamp()
    // opens the rest. See startRamped().
    bool            m_rampUnlocked{false};

    // HEAD reply kept alive until processed
    QNetworkReply  *m_headReply{nullptr};

    // Async disk writer state. m_writerObj lives in m_writerThread; jobs are
    // posted with QMetaObject::invokeMethod. m_queuedWriteBytes is the
    // backpressure gauge (incremented at enqueue on the main thread,
    // decremented by the writer after each write).
    QThread             *m_writerThread{nullptr};
    QObject             *m_writerObj{nullptr};
    std::atomic<qint64>  m_queuedWriteBytes{0};
    std::atomic<bool>    m_writerFailed{false};   // writer-side: skip writes after first error
    bool                 m_writerFailureHandled{false}; // main-thread: emit failed() once

    // Final URL after redirect chain, used for segment GETs when it differs from
    // m_item->url() (e.g. after following an HTML interstitial / confirmation
    // page to the real file). Reset to empty on each fresh start(); populated by
    // onHeadFinished() or by the range-upgrade path in onSegmentReadyRead().
    QUrl            m_effectiveUrl;
};
