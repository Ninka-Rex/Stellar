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

#include "DownloadQueue.h"
#include "SegmentedTransfer.h"
#include <algorithm>

DownloadQueue::DownloadQueue(QObject *parent) : QObject(parent) {}

void DownloadQueue::setMaxConcurrent(int v) {
    if (m_maxConcurrent != v) {
        m_maxConcurrent = v;
        emit maxConcurrentChanged();
        scheduleNext();
    }
}

void DownloadQueue::setSegmentsPerDownload(int v) {
    if (m_segmentsPerDownload != v) {
        m_segmentsPerDownload = v;
        emit segmentsPerDownloadChanged();
    }
}

void DownloadQueue::setSpeedLimitKBps(int kbps) {
    m_speedLimitKBps = kbps;
    // Apply global limit to workers that don't have a per-download limit
    for (auto it = m_workers.begin(); it != m_workers.end(); ++it) {
        const QString &id = it.key();
        DownloadItem *item = nullptr;
        for (auto *i : m_items) {
            if (i->id() == id) { item = i; break; }
        }
        // Per-download limit takes priority over global
        if (item && item->speedLimitKBps() > 0)
            continue;
        it.value()->setSpeedLimitKBps(kbps);
    }
}

void DownloadQueue::setCustomUserAgentEnabled(bool enabled) {
    if (m_useCustomUserAgent == enabled)
        return;

    m_useCustomUserAgent = enabled;
    for (auto *worker : m_workers)
        worker->setCustomUserAgentEnabled(enabled);
}

void DownloadQueue::setCustomUserAgent(const QString &userAgent) {
    if (m_customUserAgent == userAgent)
        return;

    m_customUserAgent = userAgent;
    for (auto *worker : m_workers)
        worker->setCustomUserAgent(userAgent);
}

void DownloadQueue::setTemporaryDirectory(const QString &path) {
    if (m_temporaryDirectory == path)
        return;

    m_temporaryDirectory = path;
    for (auto *worker : m_workers)
        worker->setTemporaryDirectory(path);
}

void DownloadQueue::setMaxConnectionsPerHost(int v) {
    if (m_maxConnectionsPerHost == v)
        return;

    m_maxConnectionsPerHost = v;
    for (auto *worker : m_workers)
        worker->setMaxConnectionsPerHost(v);
}

void DownloadQueue::setCanStartPredicate(std::function<bool(DownloadItem *)> predicate) {
    m_canStartPredicate = std::move(predicate);
}

void DownloadQueue::setDownloadSpeedLimit(const QString &id, int kbps) {
    auto *worker = m_workers.value(id);
    if (worker)
        worker->setSpeedLimitKBps(kbps);
}

bool DownloadQueue::relocateDownload(const QString &id, const QString &newSavePath, const QString &newFilename) {
    for (auto *item : m_items) {
        if (!item || item->id() != id)
            continue;

        auto *worker = m_workers.value(id, nullptr);
        if (worker)
            return worker->relocateOutput(newSavePath, newFilename);

        item->setSavePath(newSavePath);
        item->setFilename(newFilename);
        return true;
    }
    return false;
}

int DownloadQueue::activeCount() const {
    int n = 0;
    for (auto *item : m_items)
        if (item->status() == QStringLiteral("Downloading") || item->status() == QStringLiteral("Assembling...")) ++n;
    return n;
}

void DownloadQueue::enqueue(DownloadItem *item) {
    item->setParent(this);
    m_items.append(item);
    connect(item, &DownloadItem::statusChanged, this, [this]{ emit activeCountChanged(); scheduleNext(); });
    connect(item, QOverload<int>::of(&DownloadItem::speedLimitKBpsChanged), this, [this, item](int kbps) {
        auto *worker = m_workers.value(item->id());
        if (worker) worker->setSpeedLimitKBps(kbps);
    });
    emit itemAdded(item);
    emit queueChanged();
    scheduleNext();
}

void DownloadQueue::enqueueHeld(DownloadItem *item) {
    item->setParent(this);
    item->setStatus(DownloadItem::Status::Paused);
    m_items.append(item);
    connect(item, &DownloadItem::statusChanged, this, [this]{ emit activeCountChanged(); scheduleNext(); });
    connect(item, QOverload<int>::of(&DownloadItem::speedLimitKBpsChanged), this, [this, item](int kbps) {
        auto *worker = m_workers.value(item->id());
        if (worker) worker->setSpeedLimitKBps(kbps);
    });
    emit itemAdded(item);
    emit queueChanged();
    // Do NOT call scheduleNext — item stays Paused until user resumes
}

void DownloadQueue::enqueueRestored(DownloadItem *item) {
    // Like enqueueHeld but does NOT touch status — preserves Completed, Error, Paused, etc.
    item->setParent(this);
    m_items.append(item);
    connect(item, &DownloadItem::statusChanged, this, [this]{ emit activeCountChanged(); scheduleNext(); });
    connect(item, QOverload<int>::of(&DownloadItem::speedLimitKBpsChanged), this, [this, item](int kbps) {
        auto *worker = m_workers.value(item->id());
        if (worker) worker->setSpeedLimitKBps(kbps);
    });
    emit itemAdded(item);
    emit queueChanged();
}

void DownloadQueue::pause(const QString &id) {
    for (auto *item : m_items) {
        if (item->id() == id && (item->status() == QStringLiteral("Downloading")
                                 || item->status() == QStringLiteral("Queued"))) {
            auto *worker = m_workers.value(id, nullptr);
            if (worker) {
                worker->pause(); // worker sets status to Paused
            } else {
                item->setStatus(DownloadItem::Status::Paused);
            }
            break;
        }
    }
}

void DownloadQueue::resume(const QString &id) {
    for (auto *item : m_items) {
        if (item->id() == id && item->status() == QStringLiteral("Paused")) {
            auto *worker = m_workers.value(id, nullptr);
            if (worker) {
                worker->resume(); // worker sets status back to Downloading
            } else {
                item->setStatus(DownloadItem::Status::Queued);
                scheduleNext();
            }
            break;
        }
    }
}

void DownloadQueue::cancel(const QString &id) {
    for (int i = 0; i < m_items.size(); ++i) {
        if (m_items[i]->id() == id) {
            auto *worker = m_workers.take(id);
            if (worker) {
                worker->abort();
                worker->deleteLater();
            }
            DownloadItem *item = m_items.takeAt(i);
            emit itemRemoved(id);
            emit queueChanged();
            item->deleteLater();
            scheduleNext();
            return;
        }
    }
}

void DownloadQueue::moveUp(const QString &id) {
    for (int i = 1; i < m_items.size(); ++i) {
        if (m_items[i]->id() == id) {
            m_items.swapItemsAt(i, i - 1);
            emit queueChanged();
            return;
        }
    }
}

void DownloadQueue::moveDown(const QString &id) {
    for (int i = 0; i < m_items.size() - 1; ++i) {
        if (m_items[i]->id() == id) {
            m_items.swapItemsAt(i, i + 1);
            emit queueChanged();
            return;
        }
    }
}

void DownloadQueue::scheduleNext() {
    if (!m_nam) {
        emit activeCountChanged();
        return;
    }

    int current = activeCount();

    for (auto *item : m_items) {
        if (current >= m_maxConcurrent) break;
        if (item->statusEnum() != DownloadItem::Status::Queued) continue;
        // Alternate backends are managed outside DownloadQueue.
        if (item->isYtdlp() || item->isTorrent()) continue;
        if (m_canStartPredicate && !m_canStartPredicate(item)) continue;

        // Only DownloadQueue may call setStatus(Downloading)
        item->setStatus(DownloadItem::Status::Downloading);

        auto *worker = new SegmentedTransfer(item, m_nam, m_segmentsPerDownload, this);
        // Use per-download limit if set, otherwise use global limit
        int speedLimit = item->speedLimitKBps() > 0 ? item->speedLimitKBps() : m_speedLimitKBps;
        worker->setSpeedLimitKBps(speedLimit);
        worker->setCustomUserAgentEnabled(m_useCustomUserAgent);
        worker->setCustomUserAgent(m_customUserAgent);
        worker->setTemporaryDirectory(m_temporaryDirectory);
        worker->setMaxConnectionsPerHost(m_maxConnectionsPerHost);
        m_workers[item->id()] = worker;

        const QString id = item->id();
        connect(worker, &SegmentedTransfer::finished, this, [this, id]() {
            onWorkerFinished(id);
        });
        connect(worker, &SegmentedTransfer::failed, this, [this, id](const QString &reason) {
            onWorkerFailed(id, reason);
        });

        worker->start();
        ++current;
    }

    emit activeCountChanged();
}

void DownloadQueue::onWorkerFinished(const QString &id) {
    auto *worker = m_workers.take(id);
    if (worker) worker->deleteLater();
    // Notify that this item completed
    for (auto *item : m_items) {
        if (item->id() == id) {
            emit itemCompleted(item);
            break;
        }
    }
    emit activeCountChanged();
    scheduleNext();
}

void DownloadQueue::onWorkerFailed(const QString &id, const QString &reason) {
    // Find item and set Error status
    for (auto *item : m_items) {
        if (item->id() == id) {
            item->setStatus(DownloadItem::Status::Error);
            if (!reason.isEmpty())
                item->setErrorString(reason);
            emit itemFailed(item, reason);
            break;
        }
    }
    auto *worker = m_workers.take(id);
    if (worker) worker->deleteLater();
    emit activeCountChanged();
    scheduleNext();
}
