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
#include <QSet>
#include <QString>
#include <functional>

class AppSettings;
class DownloadItem;
class DownloadQueue;
class QueueModel;

// The single scheduling authority. Decides which Queued items may start —
// HTTP/FTP, torrents and yt-dlp alike — enforcing global and per-queue
// concurrency caps plus rolling-window download limits, in per-queue
// queueOrder. Engine-specific start mechanics stay where they live today:
// HTTP/FTP workers are spawned by DownloadQueue::startItem(); torrent and
// yt-dlp starts go through callbacks installed by AppController.
class QueueScheduler : public QObject {
    Q_OBJECT
public:
    QueueScheduler(QueueModel *queues, DownloadQueue *transfers,
                   AppSettings *settings, QObject *parent = nullptr);

    void setStartTorrentCallback(std::function<void(DownloadItem *)> cb) { m_startTorrent = std::move(cb); }
    void setStartYtdlpCallback(std::function<void(DownloadItem *)> cb) { m_startYtdlp = std::move(cb); }
    // Rolling-window transfer accounting lives in AppController; empty queueId
    // queries the global (all-queues) window.
    void setWindowUsageCallback(std::function<qint64(const QString &queueId, int hours)> cb) { m_windowUsage = std::move(cb); }

    // Coalesced: any number of calls in one event-loop turn produce a single
    // pass. Status changes during bulk restore fire this per item, so the
    // scheduler stays suspended until AppController finishes restoring.
    void schedule();
    void setSuspended(bool suspended);

    // Whether the item may start right now under all caps and limits.
    bool canStart(DownloadItem *item) const;

signals:
    // The queue transitioned from having pending/active work to having none.
    void queueDrained(const QString &queueId);

private:
    void runPass();
    static bool isBusy(const DownloadItem *item);
    static bool isActive(const DownloadItem *item);
    bool underLimits(const QString &queueId) const;

    QueueModel *m_queues;
    DownloadQueue *m_transfers;
    AppSettings *m_settings;
    std::function<void(DownloadItem *)> m_startTorrent;
    std::function<void(DownloadItem *)> m_startYtdlp;
    std::function<qint64(const QString &, int)> m_windowUsage;

    // Queues (by id; "" = unqueued items) that had busy items on the last
    // pass — the drained signal fires on the busy → idle transition.
    QSet<QString> m_busyQueues;
    bool m_passPending = false;
    bool m_suspended = false;
};
