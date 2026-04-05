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

#include "Queue.h"

Queue::Queue(const QString &id, QObject *parent)
    : QObject(parent), m_id(id)
{
}

QVariantMap Queue::toVariantMap() const
{
    QVariantMap m;
    m["id"] = m_id;
    m["name"] = m_name;
    m["isDownloadQueue"] = m_isDownloadQueue;
    m["startOnIDMStartup"] = m_startOnIDMStartup;
    m["hasStartTime"] = m_hasStartTime;
    m["startTime"] = m_startTime;
    m["startOnce"] = m_startOnce;
    m["startDaily"] = m_startDaily;
    m["startDays"] = m_startDays;
    m["hasStartAgainEvery"] = m_hasStartAgainEvery;
    m["startAgainEveryHours"] = m_startAgainEveryHours;
    m["startAgainEveryMins"] = m_startAgainEveryMins;
    m["hasStopTime"] = m_hasStopTime;
    m["stopTime"] = m_stopTime;
    m["hasMaxRetries"] = m_hasMaxRetries;
    m["maxRetries"] = m_maxRetries;
    m["maxConcurrentDownloads"] = m_maxConcurrentDownloads;
    m["openFileWhenDone"] = m_openFileWhenDone;
    m["openFilePath"] = m_openFilePath;
    m["exitIDMWhenDone"] = m_exitIDMWhenDone;
    m["turnOffComputerWhenDone"] = m_turnOffComputerWhenDone;
    m["forceProcessesToTerminate"] = m_forceProcessesToTerminate;
    m["hasDownloadLimits"] = m_hasDownloadLimits;
    m["downloadLimitMBytes"] = m_downloadLimitMBytes;
    m["downloadLimitHours"] = m_downloadLimitHours;
    m["warnBeforeStopping"] = m_warnBeforeStopping;
    return m;
}

Queue *Queue::fromVariantMap(const QString &id, const QVariantMap &map, QObject *parent)
{
    Queue *q = new Queue(id, parent);
    q->m_name = map.value(QStringLiteral("name"), QStringLiteral("Untitled Queue")).toString();
    q->m_isDownloadQueue = map.value(QStringLiteral("isDownloadQueue"), true).toBool();
    q->m_startOnIDMStartup = map.value(QStringLiteral("startOnIDMStartup"), false).toBool();
    q->m_hasStartTime = map.value(QStringLiteral("hasStartTime"), false).toBool();
    q->m_startTime = map.value(QStringLiteral("startTime"), QStringLiteral("11:00:00 PM")).toString();
    q->m_startOnce = map.value(QStringLiteral("startOnce"), true).toBool();
    q->m_startDaily = map.value(QStringLiteral("startDaily"), false).toBool();
    q->m_startDays = map.value(QStringLiteral("startDays"), QStringList{"Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"}).toStringList();
    q->m_hasStartAgainEvery = map.value(QStringLiteral("hasStartAgainEvery"), false).toBool();
    q->m_startAgainEveryHours = map.value(QStringLiteral("startAgainEveryHours"), 2).toInt();
    q->m_startAgainEveryMins = map.value(QStringLiteral("startAgainEveryMins"), 0).toInt();
    q->m_hasStopTime = map.value(QStringLiteral("hasStopTime"), false).toBool();
    q->m_stopTime = map.value(QStringLiteral("stopTime"), QStringLiteral("7:30:00 AM")).toString();
    q->m_hasMaxRetries = map.value(QStringLiteral("hasMaxRetries"), false).toBool();
    q->m_maxRetries = map.value(QStringLiteral("maxRetries"), 10).toInt();
    q->m_maxConcurrentDownloads = map.value(QStringLiteral("maxConcurrentDownloads"), 1).toInt();
    q->m_openFileWhenDone = map.value(QStringLiteral("openFileWhenDone"), false).toBool();
    q->m_openFilePath = map.value(QStringLiteral("openFilePath"), QString()).toString();
    q->m_exitIDMWhenDone = map.value(QStringLiteral("exitIDMWhenDone"), false).toBool();
    q->m_turnOffComputerWhenDone = map.value(QStringLiteral("turnOffComputerWhenDone"), false).toBool();
    q->m_forceProcessesToTerminate = map.value(QStringLiteral("forceProcessesToTerminate"), false).toBool();
    q->m_hasDownloadLimits = map.value(QStringLiteral("hasDownloadLimits"), false).toBool();
    q->m_downloadLimitMBytes = map.value(QStringLiteral("downloadLimitMBytes"), 200).toInt();
    q->m_downloadLimitHours = map.value(QStringLiteral("downloadLimitHours"), 5).toInt();
    q->m_warnBeforeStopping = map.value(QStringLiteral("warnBeforeStopping"), true).toBool();
    return q;
}
