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
#include <QAbstractListModel>
#include <QList>
#include "Queue.h"

class QueueModel : public QAbstractListModel {
    Q_OBJECT
public:
    enum Role {
        QueueRole = Qt::UserRole + 1,
        IdRole,
        NameRole
    };

    explicit QueueModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    void addQueue(Queue *queue);
    void removeQueue(const QString &queueId);
    Q_INVOKABLE Queue *queueAt(int row) const;
    Queue *queueById(const QString &id) const;
    Queue *queueByName(const QString &name) const;
    int indexOfQueue(const QString &queueId) const;

    QStringList queueNames() const;  // all queue names for combobox/menu
    QStringList queueIds() const;    // all queue IDs in order

private:
    QList<Queue *> m_queues;
};
