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
#include <QList>
#include <QHash>
#include <QString>
#include <functional>
#include "DownloadItem.h"

class QNetworkAccessManager;
class SegmentedTransfer;

class DownloadQueue : public QObject {
    Q_OBJECT
    Q_PROPERTY(int maxConcurrent READ maxConcurrent WRITE setMaxConcurrent NOTIFY maxConcurrentChanged)
    Q_PROPERTY(int activeCount   READ activeCount   NOTIFY activeCountChanged)
    Q_PROPERTY(int segmentsPerDownload READ segmentsPerDownload WRITE setSegmentsPerDownload NOTIFY segmentsPerDownloadChanged)

public:
    explicit DownloadQueue(QObject *parent = nullptr);

    int  maxConcurrent() const { return m_maxConcurrent; }
    void setMaxConcurrent(int v);

    int  segmentsPerDownload() const { return m_segmentsPerDownload; }
    void setSegmentsPerDownload(int v);

    int  activeCount() const;

    void setNam(QNetworkAccessManager *nam) { m_nam = nam; }
    void setSpeedLimitKBps(int kbps);
    void setCustomUserAgentEnabled(bool enabled);
    void setCustomUserAgent(const QString &userAgent);
    void setTemporaryDirectory(const QString &path);
    void setMaxConnectionsPerHost(int v);
    void setCanStartPredicate(std::function<bool(DownloadItem *)> predicate);
    Q_INVOKABLE void setDownloadSpeedLimit(const QString &id, int kbps);
    Q_INVOKABLE bool relocateDownload(const QString &id, const QString &newSavePath, const QString &newFilename);

    Q_INVOKABLE void enqueue(DownloadItem *item);
    Q_INVOKABLE void enqueueHeld(DownloadItem *item);      // add as Paused, don't start
    void             enqueueRestored(DownloadItem *item);  // add preserving existing status
    Q_INVOKABLE void pause(const QString &id);
    Q_INVOKABLE void resume(const QString &id);
    Q_INVOKABLE void cancel(const QString &id);
    Q_INVOKABLE void moveUp(const QString &id);
    Q_INVOKABLE void moveDown(const QString &id);
    Q_INVOKABLE void scheduleNext();  // Manually trigger scheduling (used by queue controller)

    const QList<DownloadItem *> &items() const { return m_items; }

signals:
    void maxConcurrentChanged();
    void activeCountChanged();
    void segmentsPerDownloadChanged();
    void itemAdded(DownloadItem *item);
    void itemRemoved(const QString &id);
    void itemCompleted(DownloadItem *item);
    void itemFailed(DownloadItem *item, const QString &reason);
    void itemFileDeleted(DownloadItem *item);
    void queueChanged();

private:
    void onWorkerFinished(const QString &id);
    void onWorkerFailed(const QString &id, const QString &reason);

    QList<DownloadItem *>             m_items;
    QHash<QString, SegmentedTransfer*> m_workers;
    QNetworkAccessManager             *m_nam{nullptr};
    int m_maxConcurrent{3};
    int m_segmentsPerDownload{8};
    int m_speedLimitKBps{0};
    bool m_useCustomUserAgent{false};
    QString m_customUserAgent;
    QString m_temporaryDirectory;
    int m_maxConnectionsPerHost{8};
    std::function<bool(DownloadItem *)> m_canStartPredicate;
};
