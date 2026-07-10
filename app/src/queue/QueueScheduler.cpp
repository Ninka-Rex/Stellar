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

#include "QueueScheduler.h"
#include "AppSettings.h"
#include "DownloadItem.h"
#include "DownloadQueue.h"
#include "Queue.h"
#include "QueueModel.h"
#include <QMap>
#include <QTimer>
#include <algorithm>

QueueScheduler::QueueScheduler(QueueModel *queues, DownloadQueue *transfers,
                               AppSettings *settings, QObject *parent)
    : QObject(parent), m_queues(queues), m_transfers(transfers), m_settings(settings)
{
}

void QueueScheduler::schedule()
{
    if (m_passPending || m_suspended)
        return;
    m_passPending = true;
    QTimer::singleShot(0, this, [this] {
        m_passPending = false;
        if (!m_suspended)
            runPass();
    });
}

void QueueScheduler::setSuspended(bool suspended)
{
    if (m_suspended == suspended)
        return;
    m_suspended = suspended;
    if (!suspended)
        schedule();
}

// Pending or in-flight — anything that means the queue is not done yet.
// Seeding is deliberately NOT busy: a torrent that finished downloading
// releases its slot and must not hold up post-queue actions.
bool QueueScheduler::isBusy(const DownloadItem *item)
{
    switch (item->statusEnum()) {
    case DownloadItem::Status::Queued:
    case DownloadItem::Status::Checking:
    case DownloadItem::Status::Downloading:
    case DownloadItem::Status::Moving:
    case DownloadItem::Status::Assembling:
        return true;
    default:
        return false;
    }
}

// Occupying a concurrency slot right now.
bool QueueScheduler::isActive(const DownloadItem *item)
{
    switch (item->statusEnum()) {
    case DownloadItem::Status::Checking:
    case DownloadItem::Status::Downloading:
    case DownloadItem::Status::Moving:
    case DownloadItem::Status::Assembling:
        return true;
    default:
        return false;
    }
}

bool QueueScheduler::underLimits(const QString &queueId) const
{
    if (!m_windowUsage)
        return true;
    if (!queueId.isEmpty()) {
        Queue *q = m_queues->queueById(queueId);
        if (q && q->hasDownloadLimits()) {
            const qint64 limit = qint64(q->downloadLimitMBytes()) * 1024 * 1024;
            if (m_windowUsage(queueId, q->downloadLimitHours()) >= limit)
                return false;
        }
    }
    if (m_settings->globalDownloadLimitEnabled()) {
        const qint64 limit = qint64(m_settings->globalDownloadLimitMBytes()) * 1024 * 1024;
        if (m_windowUsage(QString(), m_settings->globalDownloadLimitHours()) >= limit)
            return false;
    }
    return true;
}

bool QueueScheduler::canStart(DownloadItem *item) const
{
    if (!item)
        return false;

    int gDown = 0, gTor = 0, qDown = 0, qTor = 0;
    const QString queueId = item->queueId();
    for (DownloadItem *it : m_transfers->items()) {
        if (!isActive(it))
            continue;
        if (it->isTorrent()) {
            ++gTor;
            if (it->queueId() == queueId) ++qTor;
        } else {
            ++gDown;
            if (it->queueId() == queueId) ++qDown;
        }
    }

    if (item->isTorrent()) {
        if (gTor >= m_settings->maxConcurrentTorrents())
            return false;
    } else {
        if (gDown >= m_settings->maxConcurrent())
            return false;
    }
    if (!queueId.isEmpty()) {
        Queue *q = m_queues->queueById(queueId);
        if (q) {
            if (item->isTorrent() ? (qTor >= q->maxConcurrentTorrents())
                                  : (qDown >= q->maxConcurrentDownloads()))
                return false;
        }
    }
    return underLimits(queueId);
}

void QueueScheduler::runPass()
{
    const QList<DownloadItem *> &items = m_transfers->items();

    // Global active counts and per-queue groupings in one sweep.
    int gDown = 0, gTor = 0;
    QMap<QString, QPair<int, int>> queueActive;    // queueId -> (downloads, torrents)
    QMap<QString, QList<DownloadItem *>> candidates;
    QSet<QString> busyNow;

    for (DownloadItem *item : items) {
        const QString qid = item->queueId();
        if (isBusy(item))
            busyNow.insert(qid);
        if (isActive(item)) {
            auto &counts = queueActive[qid];
            if (item->isTorrent()) { ++gTor; ++counts.second; }
            else                   { ++gDown; ++counts.first; }
        } else if (item->statusEnum() == DownloadItem::Status::Queued) {
            candidates[qid].append(item);
        }
    }

    const int gDownCap = m_settings->maxConcurrent();
    const int gTorCap = m_settings->maxConcurrentTorrents();

    for (auto it = candidates.begin(); it != candidates.end(); ++it) {
        const QString &qid = it.key();
        Queue *queue = qid.isEmpty() ? nullptr : m_queues->queueById(qid);
        // Unqueued items are gated only by the global caps.
        const int qDownCap = queue ? queue->maxConcurrentDownloads() : gDownCap;
        const int qTorCap = queue ? queue->maxConcurrentTorrents() : gTorCap;

        if (!underLimits(qid))
            continue;

        QList<DownloadItem *> &list = it.value();
        std::stable_sort(list.begin(), list.end(),
                         [](const DownloadItem *a, const DownloadItem *b) {
                             return a->queueOrder() < b->queueOrder();
                         });

        auto &counts = queueActive[qid];
        for (DownloadItem *item : list) {
            if (item->isTorrent()) {
                if (gTor >= gTorCap || counts.second >= qTorCap)
                    continue;
                if (m_startTorrent) {
                    m_startTorrent(item);
                    ++gTor;
                    ++counts.second;
                }
            } else if (item->isYtdlp()) {
                if (gDown >= gDownCap || counts.first >= qDownCap)
                    continue;
                if (m_startYtdlp) {
                    m_startYtdlp(item);
                    ++gDown;
                    ++counts.first;
                }
            } else {
                if (gDown >= gDownCap || counts.first >= qDownCap)
                    continue;
                m_transfers->startItem(item);
                ++gDown;
                ++counts.first;
            }
            busyNow.insert(qid);
        }
    }

    // Fire drained on the busy → idle transition (real queues only — the
    // unqueued "" group has no post-queue actions).
    const QSet<QString> drained = m_busyQueues - busyNow;
    m_busyQueues = busyNow;
    for (const QString &qid : drained) {
        if (!qid.isEmpty())
            emit queueDrained(qid);
    }
}
