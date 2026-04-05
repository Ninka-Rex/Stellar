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

#include "QueueModel.h"

QueueModel::QueueModel(QObject *parent) : QAbstractListModel(parent) {}

int QueueModel::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid()) return 0;
    return m_queues.size();
}

QVariant QueueModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_queues.size()) return {};

    Queue *q = m_queues.at(index.row());

    switch (role) {
    case Qt::DisplayRole:
    case NameRole:
        return q->name();
    case IdRole:
        return q->id();
    case QueueRole:
        return QVariant::fromValue(q);
    default:
        return {};
    }
}

QHash<int, QByteArray> QueueModel::roleNames() const
{
    return {
        {Qt::DisplayRole, "display"},
        {QueueRole, "queue"},
        {IdRole, "queueId"},
        {NameRole, "queueName"}
    };
}

void QueueModel::addQueue(Queue *queue)
{
    if (!queue) return;
    beginInsertRows({}, m_queues.size(), m_queues.size());
    m_queues.append(queue);
    endInsertRows();
}

void QueueModel::removeQueue(const QString &queueId)
{
    for (int i = 0; i < m_queues.size(); ++i) {
        if (m_queues[i]->id() == queueId) {
            beginRemoveRows({}, i, i);
            m_queues.removeAt(i);
            endRemoveRows();
            return;
        }
    }
}

Queue *QueueModel::queueAt(int row) const
{
    if (row < 0 || row >= m_queues.size()) return nullptr;
    return m_queues.at(row);
}

Queue *QueueModel::queueById(const QString &id) const
{
    for (Queue *q : m_queues) {
        if (q->id() == id) return q;
    }
    return nullptr;
}

Queue *QueueModel::queueByName(const QString &name) const
{
    for (Queue *q : m_queues) {
        if (q->name() == name) return q;
    }
    return nullptr;
}

int QueueModel::indexOfQueue(const QString &queueId) const
{
    for (int i = 0; i < m_queues.size(); ++i) {
        if (m_queues[i]->id() == queueId) return i;
    }
    return -1;
}

QStringList QueueModel::queueNames() const
{
    QStringList names;
    for (Queue *q : m_queues) names.append(q->name());
    return names;
}

QStringList QueueModel::queueIds() const
{
    QStringList ids;
    for (Queue *q : m_queues) ids.append(q->id());
    return ids;
}
