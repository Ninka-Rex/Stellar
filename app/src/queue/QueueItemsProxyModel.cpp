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

#include "QueueItemsProxyModel.h"
#include "DownloadItem.h"
#include "DownloadTableModel.h"

QueueItemsProxyModel::QueueItemsProxyModel(QObject *parent)
    : QSortFilterProxyModel(parent)
{
    setDynamicSortFilter(true);
    // Sorting is by queueOrder (lessThan below); the column is irrelevant.
    sort(0);
    connect(this, &QAbstractItemModel::rowsInserted, this, &QueueItemsProxyModel::countChanged);
    connect(this, &QAbstractItemModel::rowsRemoved, this, &QueueItemsProxyModel::countChanged);
    connect(this, &QAbstractItemModel::modelReset, this, &QueueItemsProxyModel::countChanged);
}

void QueueItemsProxyModel::setQueueId(const QString &id)
{
    if (m_queueId == id)
        return;
    m_queueId = id;
    invalidateRowsFilter();
    emit queueIdChanged();
    emit countChanged();
}

void QueueItemsProxyModel::setSourceModel(QAbstractItemModel *model)
{
    QSortFilterProxyModel::setSourceModel(model);
    if (!model)
        return;
    hookRows(0, model->rowCount() - 1);
    connect(model, &QAbstractItemModel::rowsInserted, this,
            [this](const QModelIndex &, int first, int last) { hookRows(first, last); });
    // Bulk restore uses beginResetModel — re-hook everything afterwards.
    connect(model, &QAbstractItemModel::modelReset, this,
            [this] { hookRows(0, sourceModel()->rowCount() - 1); });
}

DownloadItem *QueueItemsProxyModel::itemForRow(int sourceRow) const
{
    if (!sourceModel())
        return nullptr;
    const QModelIndex idx = sourceModel()->index(sourceRow, 0);
    return idx.data(DownloadTableModel::ItemRole).value<DownloadItem *>();
}

// queueId/queueOrder changes don't flow through the source model's dataChanged
// (they aren't table columns), so watch the items directly. Qt::UniqueConnection
// doesn't work with lambdas (asserts in debug builds), hence the explicit
// hooked-set bookkeeping.
void QueueItemsProxyModel::hookRows(int first, int last)
{
    for (int row = first; row <= last; ++row) {
        DownloadItem *item = itemForRow(row);
        if (!item || m_hookedItems.contains(item))
            continue;
        m_hookedItems.insert(item);
        connect(item, &QObject::destroyed, this, [this, item] {
            m_hookedItems.remove(item);
        });
        connect(item, &DownloadItem::queueIdChanged, this, [this] {
            invalidateRowsFilter();
            emit countChanged();
        });
        connect(item, &DownloadItem::queueOrderChanged, this, [this] {
            invalidate();
        });
    }
}

bool QueueItemsProxyModel::filterAcceptsRow(int sourceRow, const QModelIndex &sourceParent) const
{
    Q_UNUSED(sourceParent);
    DownloadItem *item = itemForRow(sourceRow);
    return item && item->queueId() == m_queueId;
}

bool QueueItemsProxyModel::lessThan(const QModelIndex &left, const QModelIndex &right) const
{
    DownloadItem *a = left.data(DownloadTableModel::ItemRole).value<DownloadItem *>();
    DownloadItem *b = right.data(DownloadTableModel::ItemRole).value<DownloadItem *>();
    if (!a || !b)
        return false;
    if (a->queueOrder() != b->queueOrder())
        return a->queueOrder() < b->queueOrder();
    // Stable fallback for unassigned (-1) orders: source row order.
    return left.row() < right.row();
}
