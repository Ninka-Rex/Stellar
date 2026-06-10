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
    static int statusSortKey(const QString &status);

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
    static QString formatSize(qint64 bytes);
    static QString formatSpeed(qint64 bps);
};
