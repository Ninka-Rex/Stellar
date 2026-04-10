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

class SegmentedTransfer : public QObject {
    Q_OBJECT

public:
    static constexpr int kDefaultSegments = 8;
    static constexpr qint64 kMinSegmentSize = 512 * 1024; // 512 KB

    explicit SegmentedTransfer(DownloadItem *item,
                               QNetworkAccessManager *nam,
                               int segments = kDefaultSegments,
                               QObject *parent = nullptr);
    ~SegmentedTransfer();

    Q_INVOKABLE void start();
    Q_INVOKABLE void pause();
    Q_INVOKABLE void resume();
    Q_INVOKABLE void abort();
    Q_INVOKABLE bool relocateOutput(const QString &newSavePath, const QString &newFilename);

    void setSpeedLimitKBps(int kbps);
    void setCustomUserAgentEnabled(bool enabled);
    void setCustomUserAgent(const QString &userAgent);
    void setTemporaryDirectory(const QString &path);


signals:
    void started();
    void progressChanged(qint64 done, qint64 total, qint64 speedBps);
    void finished();
    void failed(const QString &reason);

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
        QByteArray pending;      // buffered bytes waiting to be flushed (throttled mode)
        bool networkDone{false}; // reply finished but pending not yet flushed
    };

    void sendHeadRequest();
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
    static QString parseContentDispositionFilename(const QByteArray &header);
    bool isGoogleDriveUrl(const QUrl &url) const;
    void handleGDriveConfirmPage(const QByteArray &html);
    void applyRequestHeaders(QNetworkRequest &req, const QUrl &url) const;

    DownloadItem          *m_item{nullptr};
    QNetworkAccessManager *m_nam{nullptr};
    int                    m_segmentCount;
    bool                   m_paused{false};
    bool                   m_cancelled{false};
    bool                   m_resumeCapable{false};
    int                    m_speedLimitKBps{0};
    bool                   m_gdriveIntercepting{false};
    QByteArray             m_gdriveHtmlBuf;

    QList<Segment>  m_segments;
    QTimer         *m_progressTimer{nullptr};
    qint64          m_lastReceived{0};
    bool            m_useCustomUserAgent{false};
    QString         m_customUserAgent;
    QString         m_temporaryDirectory;

    // HEAD reply kept alive until processed
    QNetworkReply  *m_headReply{nullptr};
};
