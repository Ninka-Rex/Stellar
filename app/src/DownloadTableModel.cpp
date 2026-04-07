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

#include "DownloadTableModel.h"

DownloadTableModel::DownloadTableModel(QObject *parent)
    : QAbstractTableModel(parent) {}

int DownloadTableModel::rowCount(const QModelIndex &parent) const {
    return parent.isValid() ? 0 : m_visible.size();
}

int DownloadTableModel::columnCount(const QModelIndex &parent) const {
    return parent.isValid() ? 0 : ColCount;
}

QVariant DownloadTableModel::data(const QModelIndex &index, int role) const {
    if (!index.isValid() || index.row() >= m_visible.size()) return {};
    DownloadItem *item = m_visible.at(index.row());

    if (role == ItemRole) return QVariant::fromValue(item);
    if (role == ProgressRole) return item->progress();

    if (role == Qt::DisplayRole) {
        switch (index.column()) {
        case ColFilename: return item->filename();
        case ColSize:     return item->totalBytes() > 0 ? formatSize(item->totalBytes()) : QStringLiteral("--");
        case ColProgress: return QString::number(qRound(item->progress() * 100)) + QStringLiteral("%");
        case ColSpeed:    return item->status() == QStringLiteral("Downloading") ? formatSpeed(item->speed()) : QStringLiteral("--");
        case ColStatus:   return item->errorString().isEmpty()
                              ? item->status()
                              : QStringLiteral("Error: %1").arg(item->errorString());
        case ColTimeLeft: return item->timeLeft();
        }
    }
    return {};
}

QVariant DownloadTableModel::headerData(int section, Qt::Orientation orientation, int role) const {
    if (orientation != Qt::Horizontal || role != Qt::DisplayRole) return {};
    switch (section) {
    case ColFilename: return QStringLiteral("File Name");
    case ColSize:     return QStringLiteral("Size");
    case ColProgress: return QStringLiteral("Progress");
    case ColSpeed:    return QStringLiteral("Speed");
    case ColStatus:   return QStringLiteral("Status");
    case ColTimeLeft: return QStringLiteral("Time Left");
    }
    return {};
}

QHash<int, QByteArray> DownloadTableModel::roleNames() const {
    auto roles = QAbstractTableModel::roleNames();
    roles[ProgressRole] = "progress";
    roles[ItemRole]     = "item";
    return roles;
}

void DownloadTableModel::addItem(DownloadItem *item) {
    m_items.append(item);
    
    // Relay item change signals to model updates
    connect(item, &DownloadItem::filenameChanged,  this, &DownloadTableModel::onItemChanged);
    connect(item, &DownloadItem::totalBytesChanged,this, &DownloadTableModel::onItemChanged);
    connect(item, &DownloadItem::doneBytesChanged, this, &DownloadTableModel::onItemChanged);
    connect(item, &DownloadItem::speedChanged,     this, &DownloadTableModel::onItemChanged);
    connect(item, &DownloadItem::statusChanged,     this, &DownloadTableModel::onItemChanged);
    connect(item, &DownloadItem::errorStringChanged,this, &DownloadTableModel::onItemChanged);

    sortBy(m_sortColumn, m_sortAscending);
}

void DownloadTableModel::removeItem(const QString &id) {
    for (int i = 0; i < m_items.size(); ++i) {
        if (m_items[i]->id() == id) {
            DownloadItem *item = m_items[i];
            item->disconnect(this);
            m_items.removeAt(i);
            int visRow = m_visible.indexOf(item);
            if (visRow >= 0) {
                beginRemoveRows({}, visRow, visRow);
                m_visible.removeAt(visRow);
                endRemoveRows();
            }
            return;
        }
    }
}

DownloadItem *DownloadTableModel::itemAt(int row) const {
    return (row >= 0 && row < m_visible.size()) ? m_visible[row] : nullptr;
}

DownloadItem *DownloadTableModel::itemById(const QString &id) const {
    for (auto *item : m_items)
        if (item->id() == id) return item;
    return nullptr;
}

DownloadItem *DownloadTableModel::itemByUrl(const QUrl &url) const {
    for (auto *item : m_items)
        if (item->url() == url) return item;
    return nullptr;
}

void DownloadTableModel::setFilterCategory(const QString &filter) {
    if (m_filterCategory == filter && m_filterQueue.isNull()) return;
    m_filterCategory = filter;
    m_filterQueue.clear();
    rebuildVisible();
}

void DownloadTableModel::setFilterQueue(const QString &filter) {
    if (m_filterQueue == filter && m_filterCategory.isNull()) return;
    m_filterQueue = filter;
    m_filterCategory.clear();
    rebuildVisible();
}

void DownloadTableModel::sortBy(const QString &column, bool ascending) {
    m_sortColumn = column;
    m_sortAscending = ascending;
    auto cmp = [&](DownloadItem *a, DownloadItem *b) -> bool {
        bool result = false;
        if (column == QStringLiteral("name"))
            result = a->filename().toLower() < b->filename().toLower();
        else if (column == QStringLiteral("size"))
            result = a->totalBytes() < b->totalBytes();
        else if (column == QStringLiteral("status"))
            result = a->status() < b->status();
        else if (column == QStringLiteral("timeleft"))
            result = a->timeLeft() < b->timeLeft();
        else if (column == QStringLiteral("speed"))
            result = a->speed() < b->speed();
        else if (column == QStringLiteral("added"))
            result = a->addedAt() < b->addedAt();
        else if (column == QStringLiteral("saveto"))
            result = a->savePath().toLower() < b->savePath().toLower();
        else if (column == QStringLiteral("description"))
            result = a->description().toLower() < b->description().toLower();
        else if (column == QStringLiteral("referrer"))
            result = a->referrer().toLower() < b->referrer().toLower();
        else if (column == QStringLiteral("parenturl"))
            result = a->parentUrl().toLower() < b->parentUrl().toLower();
        else if (column == QStringLiteral("lasttry"))
            result = a->lastTryAt() < b->lastTryAt();
        else
            result = a->addedAt() < b->addedAt();

        return ascending ? result : !result;
    };
    std::sort(m_items.begin(), m_items.end(), cmp);
    rebuildVisible();
}

bool DownloadTableModel::matchesFilter(DownloadItem *item) const {
    if (!m_filterQueue.isNull()) {
        if (m_filterQueue == QStringLiteral("queue_any")) {
            return !item->queueId().isEmpty();
        }
        return item->queueId() == m_filterQueue;
    }

    if (m_filterCategory == QStringLiteral("all")) return true;
    if (m_filterCategory == QStringLiteral("status_active"))
        return item->status() != QStringLiteral("Completed");
    if (m_filterCategory == QStringLiteral("status_completed"))
        return item->status() == QStringLiteral("Completed");
    return item->category() == m_filterCategory;
}

void DownloadTableModel::rebuildVisible() {
    beginResetModel();
    m_visible.clear();
    for (auto *item : m_items)
        if (matchesFilter(item)) m_visible.append(item);
    endResetModel();
}

void DownloadTableModel::onItemChanged() {
    auto *item = qobject_cast<DownloadItem *>(sender());
    if (!item) return;

    bool shouldBeVisible = matchesFilter(item);
    int visRow = m_visible.indexOf(item);

    if (shouldBeVisible && visRow < 0) {
        // Item now matches filter — insert it at the correct position
        int insertPos = 0;
        for (int i = 0; i < m_items.size(); ++i) {
            if (m_items[i] == item) break;
            if (m_visible.contains(m_items[i])) ++insertPos;
        }
        beginInsertRows({}, insertPos, insertPos);
        m_visible.insert(insertPos, item);
        endInsertRows();
    } else if (!shouldBeVisible && visRow >= 0) {
        beginRemoveRows({}, visRow, visRow);
        m_visible.removeAt(visRow);
        endRemoveRows();
    } else if (shouldBeVisible && visRow >= 0) {
        emit dataChanged(index(visRow, 0), index(visRow, ColCount - 1));
    }
}

QString DownloadTableModel::formatSize(qint64 bytes) {
    if (bytes < 1024)       return QStringLiteral("%1 B").arg(bytes);
    if (bytes < 1<<20)      return QStringLiteral("%1 KB").arg(bytes / 1024.0, 0, 'f', 1);
    if (bytes < 1<<30)      return QStringLiteral("%1 MB").arg(bytes / (1<<20), 0, 'f', 1);
    return                         QStringLiteral("%1 GB").arg(bytes / double(1<<30), 0, 'f', 2);
}

QString DownloadTableModel::formatSpeed(qint64 bps) {
    if (bps < 1024)    return QStringLiteral("%1 B/s").arg(bps);
    if (bps < 1<<20)   return QStringLiteral("%1 KB/s").arg(bps / 1024.0, 0, 'f', 1);
    return                    QStringLiteral("%1 MB/s").arg(bps / double(1<<20), 0, 'f', 1);
}
