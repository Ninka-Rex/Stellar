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
#include <QSet>
#include <QSortFilterProxyModel>
#include <QString>

class DownloadItem;

// The "files in this queue" view: filters the shared download model down to
// one queue's items and keeps them sorted by queueOrder. QML-instantiable —
// the Queues window creates one and binds queueId to the selected queue.
class QueueItemsProxyModel : public QSortFilterProxyModel {
    Q_OBJECT
    Q_PROPERTY(QString queueId READ queueId WRITE setQueueId NOTIFY queueIdChanged)
    Q_PROPERTY(int count READ count NOTIFY countChanged)

public:
    explicit QueueItemsProxyModel(QObject *parent = nullptr);

    QString queueId() const { return m_queueId; }
    void setQueueId(const QString &id);
    int count() const { return rowCount(); }

    void setSourceModel(QAbstractItemModel *model) override;

signals:
    void queueIdChanged();
    void countChanged();

protected:
    bool filterAcceptsRow(int sourceRow, const QModelIndex &sourceParent) const override;
    bool lessThan(const QModelIndex &left, const QModelIndex &right) const override;

private:
    DownloadItem *itemForRow(int sourceRow) const;
    void hookRows(int first, int last);

    QString m_queueId;
    QSet<DownloadItem *> m_hookedItems;
};
