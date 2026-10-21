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
#include <QUrl>
#include <QRegularExpression>
#include <functional>
#include "DownloadItem.h"

class QNetworkAccessManager;
class Transfer;

class DownloadQueue : public QObject {
    Q_OBJECT
    Q_PROPERTY(int activeCount   READ activeCount   NOTIFY activeCountChanged)
    Q_PROPERTY(int segmentsPerDownload READ segmentsPerDownload WRITE setSegmentsPerDownload NOTIFY segmentsPerDownloadChanged)

public:
    explicit DownloadQueue(QObject *parent = nullptr);

    int  segmentsPerDownload() const { return m_segmentsPerDownload; }
    void setSegmentsPerDownload(int v);

    int  activeCount() const;

    void setNam(QNetworkAccessManager *nam) { m_nam = nam; }
    void setSpeedLimitKBps(int kbps);
    void setCustomUserAgentEnabled(bool enabled);
    void setCustomUserAgent(const QString &userAgent);
    void setTemporaryDirectory(const QString &path);
    void setMaxConnectionsPerHost(int v);
    // The default per-host connection count and per-server wildcard overrides.
    // These supersede the old fixed segments/perHost cap: the effective number
    // of connections for a download is resolved from its URL at start time.
    void setDefaultConnLimit(int v);
    void setPerServerConnLimits(const QString &json);
    Q_INVOKABLE void setDownloadSpeedLimit(const QString &id, int kbps);
    Q_INVOKABLE bool relocateDownload(const QString &id, const QString &newSavePath, const QString &newFilename);

    Q_INVOKABLE void enqueue(DownloadItem *item);
    Q_INVOKABLE void enqueueHeld(DownloadItem *item);      // add as Paused, don't start
    void             enqueueRestored(DownloadItem *item);  // add preserving existing status
    void             enqueueSilent(DownloadItem *item);    // add + start, but do NOT emit itemAdded
    Q_INVOKABLE void pause(const QString &id);
    Q_INVOKABLE void resume(const QString &id);
    Q_INVOKABLE void cancel(const QString &id);
    // Requests a scheduling pass from QueueScheduler (via scheduleRequested).
    // Kept as a method so the many internal call sites after status changes
    // and worker completions stay unchanged.
    Q_INVOKABLE void scheduleNext();
    // Spawns a transfer worker for a Queued HTTP/FTP item. Eligibility (caps,
    // queue limits, ordering) is decided by QueueScheduler — this only manages
    // the worker lifecycle.
    void startItem(DownloadItem *item);

    const QList<DownloadItem *> &items() const { return m_items; }
    DownloadItem *itemById(const QString &id) const {
        for (auto *item : m_items) if (item->id() == id) return item;
        return nullptr;
    }

signals:
    void scheduleRequested();
    void activeCountChanged();
    void segmentsPerDownloadChanged();
    void itemAdded(DownloadItem *item);
    void itemRemoved(const QString &id);
    void itemCompleted(DownloadItem *item);
    // retryable == false: the failure can't be cured by retrying (e.g. the
    // antivirus quarantined the file), so the auto-retry policy must skip it.
    void itemFailed(DownloadItem *item, const QString &reason, bool retryable);
    void itemFileDeleted(DownloadItem *item);
    void queueChanged();

private:
    void onWorkerFinished(const QString &id);
    void onWorkerFailed(const QString &id, const QString &reason);
    // Resolve the connection count for a URL: first matching per-server exception
    // (by protocol + host wildcard), else the global default. Clamped [1,32].
    int  resolveConnLimitForUrl(const QUrl &url) const;

    struct ServerConnRule {
        bool    matchFullUrl{false}; // pattern had a scheme → match full URL, else host
        QRegularExpression re;       // precompiled wildcard (case-insensitive)
        int     conns{8};
    };
    QList<ServerConnRule> m_serverConnRules;
    int m_defaultConnLimit{8};

    QList<DownloadItem *>             m_items;
    QHash<QString, Transfer*> m_workers;
    QNetworkAccessManager             *m_nam{nullptr};
    int m_segmentsPerDownload{8};
    int m_speedLimitKBps{0};
    bool m_useCustomUserAgent{false};
    QString m_customUserAgent;
    QString m_temporaryDirectory;
    int m_maxConnectionsPerHost{8};
};
