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
#include "Transfer.h"
#include "DownloadItem.h"
#include <QString>
#include <QList>
#include <QByteArray>
#include <QHostAddress>
#include <QUrl>

class QFile;
class QTimer;
class QSslSocket;
class FtpControl;

// Pure-Qt FTP / FTPS (explicit AUTH TLS) download engine. Implements RFC 959
// directly on QTcpSocket / QSslSocket — no external library. Mirrors
// SegmentedTransfer's behaviour and on-disk conventions (.stellar-part-N parts,
// .stellar-meta resume file, sliding-window speed, stall/retry) so the rest of
// the app treats HTTP and FTP downloads identically through the Transfer base.
//
// Treats every server as hostile: all numeric replies (SIZE, REST ack, passive
// port) are validated and bounds-checked; the passive data connection is always
// dialled to the control connection's peer IP (only the advertised port is
// trusted) to defeat PASV-bounce / FXP; server-supplied filenames go through
// sanitizeFilename(); command arguments containing CR/LF are rejected.
class FtpTransfer : public Transfer {
    Q_OBJECT

public:
    static constexpr qint64 kMinSegmentSize  = 1 * 1024 * 1024; // 1 MB — below this, single connection
    static constexpr int    kMaxSegments     = 8;               // hard cap on parallel data connections
    static constexpr int    kCommandTimeoutMs = 30'000;         // per-command reply deadline

    explicit FtpTransfer(DownloadItem *item, int segments, QObject *parent = nullptr);
    ~FtpTransfer() override;

    void start()  override;
    void pause()  override;
    void resume() override;
    void abort()  override;
    bool relocateOutput(const QString &newSavePath, const QString &newFilename) override;

    void setSpeedLimitKBps(int kbps)               override;
    void setTemporaryDirectory(const QString &path) override;
    void setMaxConnectionsPerHost(int v)           override;
    // setCustomUserAgent* inherit Transfer's no-op defaults (not applicable to FTP).

private:
    // One downloaded byte range, backed by a .stellar-part-N file and driven by
    // its own FtpControl connection (FTP allows only one RETR per control channel).
    struct Segment {
        int         index{0};
        qint64      startOffset{0};
        qint64      endOffset{-1};   // inclusive; -1 = unknown length (stream to EOF)
        qint64      received{0};     // bytes written to disk
        QString     partPath;
        QFile      *file{nullptr};
        FtpControl *conn{nullptr};
        bool        done{false};
        int         retryCount{0};
        qint64      lastByteTime{0};
        int         uiSlot{-1};
    };

    // ── Connection orchestration ────────────────────────────────────────────
    void beginPrimary();                       // first control conn: login + SIZE probe
    void onPrimaryReady(qint64 totalBytes, bool restMaybe, FtpControl *primary);
    void setupSegments(qint64 totalBytes, bool multi);
    bool openSegmentFile(Segment &seg);        // open/seek the part file; fail on error
    void bindSegmentConnection(int index);     // wire an FtpControl's signals to us
    void startSegment(Segment &seg);           // fresh login + retrieve for a segment
    void startPendingSegments();               // bring up extra parallel conns lazily
    void onSegmentData(int index);             // unlimited-mode readyRead pump
    void onSegmentComplete(int index);         // 226/250 received for a segment
    void onSegmentError(int index, const QString &reason, bool transient);
    void collapseToSingleConnection();         // parallelism refused → fall back
    void checkAllDone();                        // finish when every segment is done

    // ── Progress / lifecycle ────────────────────────────────────────────────
    void onProgressTick();
    void retrySegment(int index, int extraDelayMs = 0);
    void mergeAndFinish();
    void failTransfer(const QString &reason);
    void teardownSegment(Segment &seg, bool deleteFile);
    void teardownAll();

    // ── Persistence (shared conventions with SegmentedTransfer) ─────────────
    bool saveMeta();
    bool loadMeta();
    QString tempBaseDirectory() const;
    QString metaPath() const;
    QString partPath(int index) const;
    void cleanupPartFiles();
    void deleteMetaFile();
    void updateSegmentDataOnItem();

    // ── Helpers ─────────────────────────────────────────────────────────────
    QString remotePath() const;                // server-side RETR/SIZE path (validated)
    QString deriveFilename() const;            // local filename via sanitizeFilename()
    bool    isSecure() const;                  // ftps:// → explicit AUTH TLS

    DownloadItem *m_item{nullptr};
    int     m_segmentCount{1};
    int     m_maxConnectionsPerHost{8};
    int     m_speedLimitKBps{0};
    QString m_temporaryDirectory;

    bool    m_paused{false};
    bool    m_cancelled{false};
    bool    m_resumeCapable{false};
    bool    m_restSupported{false};
    bool    m_failed{false};

    QHostAddress m_controlPeer;   // authoritative host for every data connection
    quint16      m_port{21};

    QList<Segment> m_segments;
    int     m_nextSegmentToStart{0};

    QTimer *m_progressTimer{nullptr};
    qint64  m_lastReceived{0};
    QList<qint64> m_speedSamples;
    int     m_ticksSinceMetaSave{0};
};
