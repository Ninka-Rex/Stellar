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
#include <QAbstractTableModel>
#include <QHash>
#include <QList>
#include <QSet>
#include "DownloadItem.h"

class DownloadTableModel : public QAbstractTableModel {
    Q_OBJECT
public:
    enum Column {
        ColFilename = 0,
        ColSize,
        ColProgress,
        ColSpeed,
        ColStatus,
        ColTimeLeft,
        ColCount
    };
    Q_ENUM(Column)

    enum Role {
        ProgressRole = Qt::UserRole + 1,
        ItemRole
    };

    explicit DownloadTableModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = {}) const override;
    int columnCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QVariant headerData(int section, Qt::Orientation orientation, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    void addItem(DownloadItem *item);
    void removeItem(const QString &id);
    void beginBulkRemove();
    void endBulkRemove();
    void beginBulkAdd();
    void endBulkAdd();
    Q_INVOKABLE DownloadItem *itemAt(int row) const;
    Q_INVOKABLE int rowForId(const QString &id) const;
    Q_INVOKABLE DownloadItem *itemById(const QString &id) const;
    DownloadItem *itemByUrl(const QUrl &url) const;

    Q_INVOKABLE void setFilterCategory(const QString &filter);
    Q_INVOKABLE void setFilterQueue(const QString &filter);
    Q_INVOKABLE void sortBy(const QString &column, bool ascending);
    // Expand/collapse a channel-container's child rows. Inserts/removes the
    // contiguous child block without resetting the model.
    Q_INVOKABLE void setExpanded(const QString &containerId, bool expanded);
    QList<DownloadItem *> allItems() const { return m_items; }

public slots:
    void flushVolatileSort();

    // Suspends per-tick dataChanged emissions when the main window is hidden
    // (close-to-tray / minimized). While inactive the visible list and filter
    // membership stay correct, but no high-frequency dataChanged churn is
    // pushed into the QML scene — that backlog is what froze the GUI for
    // several seconds on restore when many torrents were seeding. On
    // reactivation one full re-sort + dataChanged repaints the whole table.
    void setUiActive(bool active);
    bool uiActive() const { return m_uiActive; }

private slots:
    void onItemChanged();
    void onItemProgressChanged();
    void rebuildVisible();

private:
    void connectItemSignals(DownloadItem *item);
    // Rebuilds m_visibleSet from m_visible after a wholesale m_visible rebuild
    // (filter change, bulk add). Incremental insert/remove paths update the set
    // directly rather than calling this.
    void rebuildVisibleSet();
    bool matchesFilter(DownloadItem *item) const;
    int compareItems(DownloadItem *a, DownloadItem *b, const QString &column, bool ascending) const;
    // Hierarchy-aware comparator: orders top-level rows by the active column, but
    // keeps each container's children contiguously beneath it (parent first, then
    // children in birth order). Used by every sort site so groups never split.
    int treeCompare(DownloadItem *a, DownloadItem *b, const QString &column, bool ascending) const;
    // Top-level anchor for grouping: the item itself, or its parent container.
    DownloadItem *topAnchor(DownloadItem *item) const;
    // True when the item is a child whose container is collapsed (so it must hide).
    bool hiddenByCollapse(DownloadItem *item) const;
    static int statusSortKey(const QString &status);
    // Emits dataChanged({ItemRole}) for each contiguous run of rows whose item
    // differs between `before` and the current m_visible, instead of one span
    // covering everything between the first and last changed row. Two distant
    // rows swapping (common with a volatile sort column) then repaints just
    // those 2 rows rather than every row between them. Falls back to a single
    // [lo, hi] span when the runs are too fragmented for that to pay off.
    // Precondition: before.size() == m_visible.size().
    void emitReanchorDiff(const QList<DownloadItem *> &before);
    // Marks the pre-hide row order snapshot (see m_orderAtDeactivate) stale.
    // Called at every structural change site so setUiActive(true) falls back
    // to a full-table repaint instead of diffing against an order the view
    // never actually saw (rows since inserted/removed/reset invalidate it).
    void invalidateUiSnapshot();
    static constexpr int kMaxReanchorRuns = 8;

    QList<DownloadItem *> m_items;
    QList<DownloadItem *> m_visible;
    // O(1) companions to the lists above, kept in lock-step:
    //   m_visibleSet — membership test for the visible list, replacing the
    //                  O(n) m_visible.indexOf() that ran ~3× per torrent per
    //                  alert tick (O(n²) while seeding many torrents).
    //   m_itemsById  — id→item lookup for itemById(), called per selected row
    //                  on every selection-state recompute in the QML table.
    QSet<DownloadItem *>           m_visibleSet;
    QHash<QString, DownloadItem *> m_itemsById;
    QString               m_filterCategory{QStringLiteral("all")};
    QString               m_filterQueue;
    QString               m_sortColumn{QStringLiteral("added")};
    bool                  m_sortAscending{true};
    bool                  m_bulkRemoving{false};
    bool                  m_bulkAdding{false};
    bool                  m_uiActive{true};
    QSet<DownloadItem *>  m_volatileDirty;
    // Snapshot of m_visible's order at the moment the window was hidden, used
    // by setUiActive(true) to repaint only the rows whose identity actually
    // changed while hidden instead of the whole table. Invalidated by any
    // structural change (insert/remove/move/reset) while hidden, since those
    // already update the view's row mapping directly.
    QList<DownloadItem *> m_orderAtDeactivate;
    bool                  m_orderSnapshotValid{false};
    static QString formatSize(qint64 bytes);
    static QString formatSpeed(qint64 bps);
};
