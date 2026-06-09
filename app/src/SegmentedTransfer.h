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
#include "DownloadItem.h"
#include "Transfer.h"

class SegmentedTransfer : public Transfer {
    Q_OBJECT

public:
    static constexpr int kDefaultSegments        = 8;
    static constexpr qint64 kMinSegmentSize      = 512 * 1024;       // 512 KB
    static constexpr int kMaxSegmentRetries      = 4;                // per segment: 1s/2s/4s/8s backoff
    static constexpr int kStallTimeoutMs         = 30'000;           // bytes must arrive within this window
    static constexpr qint64 kStealThresholdBytes = 2 * 1024 * 1024; // only steal if victim has >2 MB left
    static constexpr int kMaxDynamicSegments     = 32;               // hard cap on segment count

    // Progress tick cadence and derived sliding-window sizes
    static constexpr int kTickIntervalMs         = 250;              // onProgressTick fires every 250 ms
    static constexpr int kSpeedWindowTicks       = 120;              // 30 s history  (120 × 250 ms)
    static constexpr int kDisplayWindowTicks     = 8;                // 2 s display   (8 × 250 ms)
    static constexpr int kMetaSaveIntervalTicks  = 20;               // save every 5 s (20 × 250 ms)

    // Throttle read-buffer sizing
    static constexpr int kReadBufferSeconds      = 4;                // QNAM buffer = N seconds of budget/seg
    static constexpr qint64 kMinReadBufferBytes  = 128 * 1024;       // floor so low-rate/many-seg don't starve

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
        qint64 lastByteTime{0};  // QDateTime::currentMSecsSinceEpoch() of last received byte
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
    };

    void sendHeadRequest(const QUrl &overrideUrl = QUrl());
    void onHeadFinished(QNetworkReply *reply);
    void setupSegments(qint64 totalBytes, bool resumeCapable);
    void startAllSegments();
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

    // HEAD reply kept alive until processed
    QNetworkReply  *m_headReply{nullptr};

    // Final URL after redirect chain, used for segment GETs when it differs from
    // m_item->url() (e.g. after following an HTML interstitial / confirmation
    // page to the real file). Reset to empty on each fresh start(); populated by
    // onHeadFinished() or by the range-upgrade path in onSegmentReadyRead().
    QUrl            m_effectiveUrl;
};
