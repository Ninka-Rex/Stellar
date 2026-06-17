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
#include <algorithm>
#include <QSet>

// ─── Live re-sort invariant ───────────────────────────────────────────────────
//
// `m_visible` is kept sorted at all times under the active sort column. When
// a row's data changes (status transition or per-tick stat update), the
// handlers below preserve that invariant by *moving exactly one row* to its
// new sorted position via beginMoveRows/endMoveRows — never by re-sorting the
// whole list with layoutChanged or beginResetModel.
//
// This matters because of how QML ListView reacts to each kind of model
// notification:
//
//   • beginResetModel → ListView tears down all delegates and scrolls to the
//     top. The user loses scroll position and any partially-rendered state.
//
//   • layoutAboutToBeChanged/layoutChanged → ListView re-anchors the viewport
//     to its currentIndex's delegate (or some other heuristic if currentIndex
//     is unset). When a row's rank shifts dramatically (e.g. a torrent's
//     upload speed jumps from 0 to 1 MB/s and it's the new #1 sorted by
//     upspeed), this re-anchor drags the viewport with it — producing a
//     visible "list jumps to the bottom for one frame, then back" flash even
//     when the user wasn't focused on the row that moved.
//
//   • beginMoveRows/endMoveRows → ListView animates that single delegate
//     from row A to row B. No re-anchor. Scroll position is untouched.
//
// Because each handler can only be entered after the previous one finished
// (Qt signals are direct-connected and synchronous within a single thread),
// the "list was sorted before this change" precondition holds: the only
// possibly-out-of-order row after a single value change is the row whose
// value changed. Bubble-walking that one row to its correct slot is O(d)
// where d is how far it shifted, and emits exactly one move notification.
// ─────────────────────────────────────────────────────────────────────────────

DownloadTableModel::DownloadTableModel(QObject *parent)
    : QAbstractTableModel(parent) {
}

DownloadItem *DownloadTableModel::topAnchor(DownloadItem *item) const {
    if (!item || item->parentId().isEmpty())
        return item;
    DownloadItem *parent = m_itemsById.value(item->parentId(), nullptr);
    return parent ? parent : item;  // orphaned child falls back to itself
}

bool DownloadTableModel::hiddenByCollapse(DownloadItem *item) const {
    if (!item || item->parentId().isEmpty())
        return false;
    DownloadItem *parent = m_itemsById.value(item->parentId(), nullptr);
    return parent && !parent->treeExpanded();
}

int DownloadTableModel::treeCompare(DownloadItem *a, DownloadItem *b,
                                    const QString &column, bool ascending) const {
    DownloadItem *anchorA = topAnchor(a);
    DownloadItem *anchorB = topAnchor(b);

    // Different groups: order by their top-level anchors under the active column.
    if (anchorA != anchorB)
        return compareItems(anchorA, anchorB, column, ascending);

    // Same group. A container always precedes its own children.
    const bool aIsAnchor = (a == anchorA);
    const bool bIsAnchor = (b == anchorB);
    if (aIsAnchor != bIsAnchor)
        return aIsAnchor ? -1 : 1;

    // Two children of the same container: keep stable birth order (added time,
    // then id) so siblings never reshuffle as their stats change.
    if (a->addedAt() != b->addedAt())
        return a->addedAt() < b->addedAt() ? -1 : 1;
    return a->id() < b->id() ? -1 : (a->id() > b->id() ? 1 : 0);
}

void DownloadTableModel::setExpanded(const QString &containerId, bool expanded) {
    DownloadItem *container = m_itemsById.value(containerId, nullptr);
    if (!container || container->treeExpanded() == expanded)
        return;

    container->setTreeExpanded(expanded);

    // Rebuild m_visible from scratch under a full model reset. Surgical
    // insert/remove of the child block is fragile: rapid expand/collapse combined
    // with the live re-sort (onItemChanged / flushVolatileSort can move the
    // container or a child the same frame) repeatedly desynced the row count from
    // the begin/end*Rows signals and crashed deep inside Qt's view machinery
    // (access violation in Qt6Core during delegate refresh). A reset is O(n) but
    // expand/collapse is a deliberate, infrequent user action — correctness wins.
    // matchesFilter() already excludes children of a collapsed container via
    // hiddenByCollapse(), so this naturally adds/removes the right rows.
    QList<DownloadItem *> rebuilt;
    rebuilt.reserve(m_items.size());
    const bool showAll = (m_filterCategory == QStringLiteral("all") && m_filterQueue.isNull());
    for (DownloadItem *it : m_items) {
        if (showAll ? !hiddenByCollapse(it) : matchesFilter(it))
            rebuilt.append(it);
    }
    std::sort(rebuilt.begin(), rebuilt.end(), [this](DownloadItem *a, DownloadItem *b) {
        return treeCompare(a, b, m_sortColumn, m_sortAscending) < 0;
    });

    beginResetModel();
    m_visible = rebuilt;
    rebuildVisibleSet();
    endResetModel();
}

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

void DownloadTableModel::connectItemSignals(DownloadItem *item) {
    connect(item, &DownloadItem::filenameChanged,   this, &DownloadTableModel::onItemChanged);
    connect(item, &DownloadItem::totalBytesChanged, this, &DownloadTableModel::onItemChanged);
    connect(item, &DownloadItem::statusChanged,      this, &DownloadTableModel::onItemChanged);
    connect(item, &DownloadItem::errorStringChanged, this, &DownloadTableModel::onItemChanged);
    connect(item, &DownloadItem::torrentChanged,     this, &DownloadTableModel::onItemChanged);
    connect(item, &DownloadItem::categoryChanged,    this, &DownloadTableModel::onItemChanged);
    connect(item, &DownloadItem::queueIdChanged,     this, &DownloadTableModel::onItemChanged);
    connect(item, &DownloadItem::lastTryAtChanged,   this, &DownloadTableModel::onItemChanged);
    connect(item, &DownloadItem::doneBytesChanged,    this, &DownloadTableModel::onItemProgressChanged);
    connect(item, &DownloadItem::speedChanged,        this, &DownloadTableModel::onItemProgressChanged);
    connect(item, &DownloadItem::torrentStatsChanged, this, &DownloadTableModel::onItemProgressChanged);
}

void DownloadTableModel::rebuildVisibleSet() {
    m_visibleSet = QSet<DownloadItem *>(m_visible.begin(), m_visible.end());
}

void DownloadTableModel::addItem(DownloadItem *item) {
    m_items.append(item);
    m_itemsById.insert(item->id(), item);
    if (m_bulkAdding)
        return;

    connectItemSignals(item);

    // Add to visible if it matches current filter
    if (matchesFilter(item)) {
        // Find insert position based on current sort
        int insertPos = m_visible.size();
        for (int i = 0; i < m_visible.size(); ++i) {
            if (treeCompare(m_visible.at(i), item, m_sortColumn, m_sortAscending) > 0) {
                insertPos = i;
                break;
            }
        }
        beginInsertRows({}, insertPos, insertPos);
        m_visible.insert(insertPos, item);
        m_visibleSet.insert(item);
        endInsertRows();
    }
}

void DownloadTableModel::removeItem(const QString &id) {
    for (int i = 0; i < m_items.size(); ++i) {
        if (m_items[i]->id() == id) {
            DownloadItem *item = m_items[i];
            item->disconnect(this);
            // Drop any dangling reference: a stale pointer left in m_volatileDirty
            // would be dereferenced by the next flushVolatileSort (use-after-free).
            m_volatileDirty.remove(item);
            m_items.removeAt(i);
            m_itemsById.remove(id);
            int visRow = m_visible.indexOf(item);
            if (visRow >= 0) {
                if (m_bulkRemoving) {
                    // Deferred — model will be reset in endBulkRemove()
                    m_visible.removeAt(visRow);
                } else {
                    beginRemoveRows({}, visRow, visRow);
                    m_visible.removeAt(visRow);
                    endRemoveRows();
                }
                m_visibleSet.remove(item);
            }
            return;
        }
    }
}

void DownloadTableModel::beginBulkRemove() {
    m_bulkRemoving = true;
    beginResetModel();
}

void DownloadTableModel::endBulkRemove() {
    m_bulkRemoving = false;
    endResetModel();
}

void DownloadTableModel::beginBulkAdd() {
    m_bulkAdding = true;
}

void DownloadTableModel::endBulkAdd() {
    m_bulkAdding = false;

    for (DownloadItem *item : m_items)
        connectItemSignals(item);

    m_visible.clear();
    m_visible.reserve(m_items.size());
    for (DownloadItem *item : m_items) {
        if (matchesFilter(item))
            m_visible.append(item);
    }
    std::sort(m_visible.begin(), m_visible.end(),
        [this](DownloadItem *a, DownloadItem *b) {
            return treeCompare(a, b, m_sortColumn, m_sortAscending) < 0;
        });
    rebuildVisibleSet();

    beginResetModel();
    endResetModel();
}

DownloadItem *DownloadTableModel::itemAt(int row) const {
    return (row >= 0 && row < m_visible.size()) ? m_visible[row] : nullptr;
}

int DownloadTableModel::rowForId(const QString &id) const {
    DownloadItem *item = itemById(id);
    return item ? m_visible.indexOf(item) : -1;
}

DownloadItem *DownloadTableModel::itemById(const QString &id) const {
    return m_itemsById.value(id, nullptr);
}

DownloadItem *DownloadTableModel::itemByUrl(const QUrl &url) const {
    for (auto *item : m_items)
        if (item->url() == url) return item;
    return nullptr;
}

void DownloadTableModel::setFilterCategory(const QString &filter) {
    if (m_filterCategory == filter && m_filterQueue.isNull()) return;
    m_filterCategory = filter;
    m_filterQueue = QString(); // null, not empty — matchesFilter checks isNull()

    QList<DownloadItem*> newVisible;
    if (m_filterCategory == QStringLiteral("all")) {
        // "all" shows every item EXCEPT children hidden under a collapsed
        // container — otherwise switching categories silently re-expands them
        // (and then re-expanding duplicates the rows already in m_visible).
        newVisible.reserve(m_items.size());
        for (auto *item : m_items) {
            if (!hiddenByCollapse(item)) newVisible.append(item);
        }
    } else {
        newVisible.reserve(m_items.size());
        for (auto *item : m_items) {
            if (matchesFilter(item)) newVisible.append(item);
        }
    }
    std::sort(newVisible.begin(), newVisible.end(), [&](DownloadItem *a, DownloadItem *b) {
        return treeCompare(a, b, m_sortColumn, m_sortAscending) < 0;
    });

    if (newVisible == m_visible) return;

    beginResetModel();
    m_visible = newVisible;
    rebuildVisibleSet();
    endResetModel();
}

void DownloadTableModel::setFilterQueue(const QString &filter) {
    if (m_filterQueue == filter && m_filterCategory.isNull()) return;

    m_filterQueue = filter;
    m_filterCategory = QString(); // null, not empty

    QList<DownloadItem *> newVisible;
    newVisible.reserve(m_items.size());
    for (auto *item : m_items) {
        if (matchesFilter(item)) newVisible.append(item);
    }
    std::sort(newVisible.begin(), newVisible.end(), [&](DownloadItem *a, DownloadItem *b) {
        return treeCompare(a, b, m_sortColumn, m_sortAscending) < 0;
    });

    if (newVisible == m_visible) return;

    beginResetModel();
    m_visible = newVisible;
    rebuildVisibleSet();
    endResetModel();
}

void DownloadTableModel::sortBy(const QString &column, bool ascending) {
    m_sortColumn = column;
    m_sortAscending = ascending;
    if (m_visible.isEmpty()) return;

    // Sort the visible list with the hierarchy-aware comparator so channel
    // children stay grouped under their container regardless of sort column.
    // (treeCompare delegates per-column logic to compareItems — single source.)
    std::sort(m_visible.begin(), m_visible.end(), [&](DownloadItem *a, DownloadItem *b) {
        return treeCompare(a, b, column, ascending) < 0;
    });

    // Simple approach: emit dataChanged for the entire range since rows haven't changed
    emit dataChanged(index(0, 0), index(m_visible.size() - 1, ColCount - 1));
}

bool DownloadTableModel::matchesFilter(DownloadItem *item) const {
    // A child of a collapsed container is never visible, regardless of category.
    if (hiddenByCollapse(item))
        return false;

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

    // Torrent section filters
    if (m_filterCategory == QStringLiteral("torrent_all"))
        return item->isTorrent();
    if (m_filterCategory == QStringLiteral("torrent_downloading"))
        return item->isTorrent() && item->status() == QStringLiteral("Downloading");
    if (m_filterCategory == QStringLiteral("torrent_seeding"))
        return item->isTorrent() && item->status() == QStringLiteral("Seeding");
    if (m_filterCategory == QStringLiteral("torrent_stopped"))
        return item->isTorrent() && item->status() == QStringLiteral("Paused");
    if (m_filterCategory == QStringLiteral("torrent_active"))
        // Active = currently transferring data (download or upload speed > 0)
        return item->isTorrent() && (item->speed() > 0 || item->torrentUploadSpeed() > 0);
    if (m_filterCategory == QStringLiteral("torrent_inactive"))
        // Inactive = not paused/completed but no data flowing
        return item->isTorrent()
            && item->status() != QStringLiteral("Paused")
            && item->status() != QStringLiteral("Completed")
            && item->speed() == 0
            && item->torrentUploadSpeed() == 0;
    if (m_filterCategory == QStringLiteral("torrent_checking"))
        return item->isTorrent() && item->status() == QStringLiteral("Checking");
    if (m_filterCategory == QStringLiteral("torrent_moving"))
        return item->isTorrent() && item->status() == QStringLiteral("Moving");

    return item->category() == m_filterCategory;
}

void DownloadTableModel::rebuildVisible() {
    QList<DownloadItem*> newVisible;

    if (m_filterCategory == QStringLiteral("all") && m_filterQueue.isNull()) {
        newVisible.reserve(m_items.size());
        for (auto *item : m_items) {
            if (!hiddenByCollapse(item)) newVisible.append(item);
        }
    } else {
        newVisible.reserve(m_items.size());
        for (auto *item : m_items) {
            if (matchesFilter(item)) newVisible.append(item);
        }
    }
    std::sort(newVisible.begin(), newVisible.end(), [&](DownloadItem *a, DownloadItem *b) {
        return treeCompare(a, b, m_sortColumn, m_sortAscending) < 0;
    });

    if (m_visible != newVisible) {
        m_visible = newVisible;
        rebuildVisibleSet();
        emit layoutChanged();
    }
}


void DownloadTableModel::onItemChanged() {
    auto *item = qobject_cast<DownloadItem *>(sender());
    if (!item) return;

    bool shouldBeVisible = matchesFilter(item);
    int visRow = m_visible.indexOf(item);

    if (shouldBeVisible && visRow < 0) {
        // Item now matches filter — insert it at the correct sorted position.
        int insertPos;
        if (!item->parentId().isEmpty() || item->isChannelContainer()) {
            // Grouped item: position by the hierarchy-aware comparator so children
            // land inside their container's block, not by raw m_items order.
            insertPos = m_visible.size();
            for (int i = 0; i < m_visible.size(); ++i) {
                if (treeCompare(m_visible[i], item, m_sortColumn, m_sortAscending) > 0) {
                    insertPos = i;
                    break;
                }
            }
        } else {
            // Plain row: keep the cheap m_items-order walk (m_visibleSet = O(1)).
            insertPos = 0;
            for (int i = 0; i < m_items.size(); ++i) {
                if (m_items[i] == item) break;
                if (m_visibleSet.contains(m_items[i])) ++insertPos;
            }
        }
        beginInsertRows({}, insertPos, insertPos);
        m_visible.insert(insertPos, item);
        m_visibleSet.insert(item);
        endInsertRows();
    } else if (!shouldBeVisible && visRow >= 0) {
        beginRemoveRows({}, visRow, visRow);
        m_visible.removeAt(visRow);
        m_visibleSet.remove(item);
        endRemoveRows();
    } else if (shouldBeVisible && visRow >= 0) {
        // A container moving must carry its whole child block, which the single-row
        // bubble below can't express. Re-sort the grouped list and emit a minimal
        // diff instead (same jump-free technique as flushVolatileSort).
        if (item->isChannelContainer()) {
            const QList<DownloadItem *> before = m_visible;
            std::stable_sort(m_visible.begin(), m_visible.end(),
                [this](DownloadItem *a, DownloadItem *b) {
                    return treeCompare(a, b, m_sortColumn, m_sortAscending) < 0;
                });
            if (before == m_visible) {
                emit dataChanged(index(visRow, 0), index(visRow, ColCount - 1));
                return;
            }
            int lo = 0;
            while (lo < before.size() && before[lo] == m_visible[lo]) ++lo;
            int hi = before.size() - 1;
            while (hi > lo && before[hi] == m_visible[hi]) --hi;
            emit dataChanged(index(lo, 0), index(hi, ColCount - 1), {ItemRole});
            return;
        }

        // Bubble the changed row to its correct sorted position using
        // move semantics — see the matching block in onItemProgressChanged
        // for the rationale (avoid layoutChanged-induced scroll snaps).
        int targetRow = visRow;
        while (targetRow > 0
               && treeCompare(m_visible[targetRow - 1], item, m_sortColumn, m_sortAscending) > 0) {
            --targetRow;
        }
        while (targetRow < m_visible.size() - 1
               && treeCompare(item, m_visible[targetRow + 1], m_sortColumn, m_sortAscending) > 0) {
            ++targetRow;
        }

        if (targetRow != visRow) {
            const int destinationChild = (targetRow > visRow) ? targetRow + 1 : targetRow;
            // beginMoveRows rejects an illegal move (dest inside [src, src+1]) by
            // returning false; proceeding to mutate m_visible anyway would desync the
            // row count from the view and crash inside Qt. Bail to a safe dataChanged.
            if (beginMoveRows(QModelIndex(), visRow, visRow,
                              QModelIndex(), destinationChild)) {
                DownloadItem *moved = m_visible.takeAt(visRow);
                m_visible.insert(targetRow, moved);
                endMoveRows();
                emit dataChanged(index(targetRow, 0), index(targetRow, ColCount - 1));
            } else {
                emit dataChanged(index(visRow, 0), index(visRow, ColCount - 1));
            }
        } else {
            emit dataChanged(index(visRow, 0), index(visRow, ColCount - 1));
        }
    }
}

void DownloadTableModel::onItemProgressChanged() {
    auto *item = qobject_cast<DownloadItem *>(sender());
    if (!item) return;

    // Set of columns whose values change every tick for many rows at once
    // (upspeed, ratio, uploaded, …). Sorting by one of these uses the coalesced
    // re-sort path (flushVolatileSort) rather than the single-row bubble in
    // onItemChanged, which would leave the table permanently mis-sorted because
    // each tick only fixes the last row to emit.
    static const QSet<QString> kVolatileSortCols = {
        QStringLiteral("downspeed"), QStringLiteral("speed"),
        QStringLiteral("upspeed"),   QStringLiteral("progress"),
        QStringLiteral("timeleft"),  QStringLiteral("ratio"),
        QStringLiteral("uploaded"),  QStringLiteral("downloaded"),
        QStringLiteral("seeders"),   QStringLiteral("peers"),
        QStringLiteral("status")  // doneBytes secondary sort within Downloading
    };
    const bool volatileSort = kVolatileSortCols.contains(m_sortColumn);

    // Speed-based filters (torrent_active / torrent_inactive) depend on upload/download
    // speed, which changes every tick. Only invoke the expensive onItemChanged() path
    // when membership actually flips — otherwise fall through to the volatile sort
    // path below so active-tab rows re-sort when sorted by speed columns.
    if (m_filterCategory == QStringLiteral("torrent_active")
        || m_filterCategory == QStringLiteral("torrent_inactive")) {
        const bool shouldBeVisible = matchesFilter(item);
        if (shouldBeVisible != m_visibleSet.contains(item)) {
            // Membership changed — full insert/remove path.
            onItemChanged();
            return;
        }
        if (!shouldBeVisible)
            return;
        // Item stays visible — fall through to volatile sort logic below.
    }

    // Hot path while seeding: mark the item dirty without any O(n) lookup.
    // flushVolatileSort() is called synchronously by AppController after the
    // full torrent batch update completes (via torrentBatchUpdated), so sort +
    // dataChanged happen in the same frame as the value update.
    if (volatileSort) {
        if (m_visibleSet.contains(item))
            m_volatileDirty.insert(item);
        return;
    }

    // Non-volatile sort column: only HTTP progress signals reach here. We need
    // the real row index to emit a targeted dataChanged for that one row.
    const int visRow = m_visible.indexOf(item);
    if (visRow < 0) return;

    // Skip per-tick repaint when the window is hidden — no visible delegate to
    // update, and the queued dataChanged would have to be flushed all at once on
    // restore. setUiActive(true) repaints the whole table instead.
    if (!m_uiActive) return;

    emit dataChanged(index(visRow, ColProgress), index(visRow, ColTimeLeft));
}

void DownloadTableModel::flushVolatileSort() {
    if (m_volatileDirty.isEmpty() || m_visible.size() < 2) {
        m_volatileDirty.clear();
        return;
    }
    // Re-sort entire visible list in one stable pass.
    // We deliberately avoid layoutAboutToBeChanged/layoutChanged — per CLAUDE.md,
    // layoutChanged causes QML ListView to re-anchor to currentIndex, producing
    // visible scroll jumps, and with reuseItems:true delegates don't reliably
    // re-bind after layout changes.
    //
    // Snapshot the order before sorting so we can detect whether any rows
    // actually moved. The common case while seeding is that speeds jitter but
    // ranks don't flip — then there is nothing to repaint: cell *values* update
    // through the delegates' direct bindings to DownloadItem properties, with no
    // dataChanged needed. Emitting a full-table dataChanged every tick regardless
    // was the dominant per-tick cost (re-evaluates every binding in every row and
    // triggers the QML selection-state recompute).
    const QList<DownloadItem *> before = m_visible;
    std::stable_sort(m_visible.begin(), m_visible.end(),
        [this](DownloadItem *a, DownloadItem *b) {
            return treeCompare(a, b, m_sortColumn, m_sortAscending) < 0;
        });
    m_volatileDirty.clear();

    if (before == m_visible)
        return;  // order unchanged — nothing to re-anchor

    // Keep the list ordered while hidden, but defer the repaint to setUiActive(true).
    if (!m_uiActive)
        return;

    // Only the rows in [lo, hi] changed identity; re-anchoring just those
    // delegates (and only the ItemRole, the only role the delegate consumes)
    // rebinds them to the correctly-positioned DownloadItem* without resetting
    // the model or destroying delegates.
    int lo = 0;
    while (lo < before.size() && before[lo] == m_visible[lo])
        ++lo;
    int hi = before.size() - 1;
    while (hi > lo && before[hi] == m_visible[hi])
        --hi;
    emit dataChanged(index(lo, 0), index(hi, ColCount - 1), {ItemRole});
}

void DownloadTableModel::setUiActive(bool active) {
    if (m_uiActive == active) return;
    m_uiActive = active;
    if (!active || m_visible.isEmpty()) return;

    // Becoming visible again: the visible list was kept sorted while hidden but
    // no dataChanged was emitted. Re-sort once (volatile values changed under us)
    // and repaint the whole table in a single pass.
    std::stable_sort(m_visible.begin(), m_visible.end(),
        [this](DownloadItem *a, DownloadItem *b) {
            return treeCompare(a, b, m_sortColumn, m_sortAscending) < 0;
        });
    m_volatileDirty.clear();
    // Single catch-up repaint of the whole table — values genuinely went stale
    // while hidden. Restrict to ItemRole (the only role the delegate reads) so
    // re-binding each row's item pointer cascades through its property bindings.
    emit dataChanged(index(0, 0), index(m_visible.size() - 1, ColCount - 1), {ItemRole});
}

int DownloadTableModel::statusSortKey(const QString &status) {
    if (status == QStringLiteral("Checking"))     return 0;
    if (status == QStringLiteral("Downloading"))  return 1;
    if (status == QStringLiteral("Seeding"))      return 2;
    if (status == QStringLiteral("Assembling"))   return 3;
    if (status == QStringLiteral("Queued"))       return 4;
    if (status == QStringLiteral("Paused"))       return 5;
    if (status == QStringLiteral("Failed"))       return 6;
    if (status == QStringLiteral("Completed"))    return 7;
    return 8;
}

int DownloadTableModel::compareItems(DownloadItem *a, DownloadItem *b, const QString &column, bool ascending) const {
    // For torrent-specific columns, always rank non-torrent items after torrent items
    // regardless of sort direction so HTTP downloads don't pollute torrent rankings.
    static const QStringList torrentCols = {
        QStringLiteral("seeders"), QStringLiteral("peers"), QStringLiteral("ratio"),
        QStringLiteral("uploaded"), QStringLiteral("downloaded"), QStringLiteral("upspeed")
    };
    if (torrentCols.contains(column)) {
        if (a->isTorrent() != b->isTorrent())
            return a->isTorrent() ? -1 : 1;  // torrent always ranks above non-torrent
    }

    int cmpResult = 0;
    if (column == QStringLiteral("name"))
        cmpResult = a->filename().toLower().compare(b->filename().toLower());
    else if (column == QStringLiteral("size"))
        cmpResult = a->totalBytes() < b->totalBytes() ? -1 : (a->totalBytes() > b->totalBytes() ? 1 : 0);
    else if (column == QStringLiteral("status")) {
        // Status sort has a fixed ordering (Downloading always first) that must not
        // be reversed by the ascending/descending flag — so return early, bypassing
        // the `ascending ? cmpResult : -cmpResult` flip at line 550.
        int sk = statusSortKey(a->status()) - statusSortKey(b->status());
        if (sk != 0)
            return sk;
        // Within two Downloading HTTP items, most-downloaded first (always descending).
        if (a->status() == QStringLiteral("Downloading")
                && !a->isTorrent() && !b->isTorrent()) {
            int dc = a->doneBytes() > b->doneBytes() ? -1
                   : a->doneBytes() < b->doneBytes() ?  1 : 0;
            if (dc != 0) return dc;
        }
        // Tie-break by id for stability.
        return a->id() < b->id() ? -1 : (a->id() > b->id() ? 1 : 0);
    }
    else if (column == QStringLiteral("timeleft"))
        cmpResult = a->timeLeft().compare(b->timeLeft());
    else if (column == QStringLiteral("speed") || column == QStringLiteral("downspeed"))
        cmpResult = a->speed() < b->speed() ? -1 : (a->speed() > b->speed() ? 1 : 0);
    else if (column == QStringLiteral("upspeed"))
        cmpResult = a->torrentUploadSpeed() < b->torrentUploadSpeed() ? -1 : (a->torrentUploadSpeed() > b->torrentUploadSpeed() ? 1 : 0);
    else if (column == QStringLiteral("added"))
        cmpResult = a->addedAt() < b->addedAt() ? -1 : (a->addedAt() > b->addedAt() ? 1 : 0);
    else if (column == QStringLiteral("saveto"))
        cmpResult = a->savePath().toLower().compare(b->savePath().toLower());
    else if (column == QStringLiteral("description"))
        cmpResult = a->description().toLower().compare(b->description().toLower());
    else if (column == QStringLiteral("referrer"))
        cmpResult = a->referrer().toLower().compare(b->referrer().toLower());
    else if (column == QStringLiteral("parenturl"))
        cmpResult = a->parentUrl().toLower().compare(b->parentUrl().toLower());
    else if (column == QStringLiteral("lasttry"))
        cmpResult = a->lastTryAt() < b->lastTryAt() ? -1 : (a->lastTryAt() > b->lastTryAt() ? 1 : 0);
    else if (column == QStringLiteral("seeders"))
        cmpResult = a->torrentListSeeders() < b->torrentListSeeders() ? -1 : (a->torrentListSeeders() > b->torrentListSeeders() ? 1 : 0);
    else if (column == QStringLiteral("peers"))
        cmpResult = a->torrentListPeers() < b->torrentListPeers() ? -1 : (a->torrentListPeers() > b->torrentListPeers() ? 1 : 0);
    else if (column == QStringLiteral("queue"))
        cmpResult = a->queueId().compare(b->queueId());
    else if (column == QStringLiteral("ratio"))
        cmpResult = a->torrentRatio() < b->torrentRatio() ? -1 : (a->torrentRatio() > b->torrentRatio() ? 1 : 0);
    else if (column == QStringLiteral("uploaded"))
        cmpResult = a->torrentUploaded() < b->torrentUploaded() ? -1 : (a->torrentUploaded() > b->torrentUploaded() ? 1 : 0);
    else if (column == QStringLiteral("downloaded"))
        cmpResult = a->torrentDownloaded() < b->torrentDownloaded() ? -1 : (a->torrentDownloaded() > b->torrentDownloaded() ? 1 : 0);
    else
        cmpResult = a->addedAt() < b->addedAt() ? -1 : (a->addedAt() > b->addedAt() ? 1 : 0);

    if (cmpResult != 0) return ascending ? cmpResult : -cmpResult;
    return a->id() < b->id() ? -1 : (a->id() > b->id() ? 1 : 0);
}

QString DownloadTableModel::formatSize(qint64 bytes) {
    static constexpr double kKB = 1024.0;
    static constexpr double kMB = kKB * 1024.0;
    static constexpr double kGB = kMB * 1024.0;
    if (bytes < 1024) return QStringLiteral("%1 B").arg(bytes);
    if (bytes < kMB)  return QStringLiteral("%1 KB").arg(bytes / kKB, 0, 'f', 1);
    if (bytes < kGB)  return QStringLiteral("%1 MB").arg(bytes / kMB, 0, 'f', 1);
    return                  QStringLiteral("%1 GB").arg(bytes / kGB, 0, 'f', 1);
}

QString DownloadTableModel::formatSpeed(qint64 bps) {
    if (bps < 1000)         return QStringLiteral("%1 B/s").arg(bps);
    if (bps < 1000000)      return QStringLiteral("%1 KB/s").arg(bps / 1000.0, 0, 'f', 1);
    return                         QStringLiteral("%1 MB/s").arg(bps / 1000000.0, 0, 'f', 1);
}
