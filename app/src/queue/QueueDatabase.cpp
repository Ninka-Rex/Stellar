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

#include "QueueDatabase.h"
#include "StellarPaths.h"
#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QJsonArray>
#include <QJsonObject>
#include <QDebug>

QueueDatabase::QueueDatabase(QObject *parent) : QObject(parent) {}

bool QueueDatabase::open() {
    m_filePath = StellarPaths::queuesFile();
    return true;
}

QList<Queue *> QueueDatabase::loadAll(QObject *parentForQueues)
{
    QList<Queue *> result;
    m_entries.clear();

    QFile f(m_filePath);
    if (!f.exists()) return result;
    if (!f.open(QIODevice::ReadOnly)) {
        qWarning() << "QueueDatabase: cannot read" << m_filePath;
        return result;
    }

    const QJsonDocument doc = QJsonDocument::fromJson(f.readAll());
    f.close();
    if (!doc.isArray()) return result;

    const QJsonArray arr = doc.array();
    bool migrated = false;
    for (const QJsonValue &val : arr) {
        const QJsonObject obj = val.toObject();
        const QString id = obj[QLatin1String("id")].toString();
        if (id.isEmpty()) continue;

        const QVariantMap entry = obj.toVariantMap();

        // Legacy "download-limits" pseudo-queue held the global download
        // limits. Extract its fields for AppController to move into
        // AppSettings and drop the entry from the file.
        if (id == QLatin1String("download-limits")) {
            m_takenGlobalLimits = entry;
            migrated = true;
            continue;
        }

        Queue *queue = Queue::fromVariantMap(id, entry, parentForQueues);
        if (entry.value(QStringLiteral("version"), 1).toInt() < 2) {
            migrated = true;
            m_entries[id] = queue->toVariantMap();
        } else {
            m_entries[id] = entry;
        }
        result.append(queue);
    }
    if (migrated)
        writeToDisk();
    return result;
}

void QueueDatabase::save(Queue *queue)
{
    if (!queue) return;
    m_entries[queue->id()] = queue->toVariantMap();
    writeToDisk();
}

void QueueDatabase::remove(const QString &queueId)
{
    m_entries.remove(queueId);
    writeToDisk();
}

void QueueDatabase::flush()
{
    writeToDisk();
}

void QueueDatabase::writeToDisk()
{
    QJsonArray arr;
    for (const auto &entry : m_entries) {
        arr.append(QJsonObject::fromVariantMap(entry));
    }

    QFile f(m_filePath);
    if (!f.open(QIODevice::WriteOnly)) {
        qWarning() << "QueueDatabase: cannot write to" << m_filePath;
        return;
    }
    f.write(QJsonDocument(arr).toJson(QJsonDocument::Indented));
    f.close();
}
