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
#include <QObject>
#include <QList>
#include <QString>
#include <QMap>
#include "Queue.h"

// Persists queues to a JSON file.
// File location: QStandardPaths::AppDataLocation / "queues.json"
class QueueDatabase : public QObject {
    Q_OBJECT
public:
    explicit QueueDatabase(QObject *parent = nullptr);

    bool open();

    QList<Queue *> loadAll(QObject *parentForQueues = nullptr);
    void save(Queue *queue);
    void remove(const QString &queueId);
    void flush();

private:
    void writeToDisk();
    QString m_filePath;

    // In-memory mirror of every queue, keyed by id
    QMap<QString, QVariantMap> m_entries;
};
