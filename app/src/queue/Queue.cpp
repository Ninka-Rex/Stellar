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
#include <QStringList>

Queue::Queue(const QString &id, QObject *parent)
    : QObject(parent), m_id(id)
{
}

QVariantMap Queue::toVariantMap() const
{
    QVariantMap m;
    m["version"] = 2;
    m["id"] = m_id;
    m["name"] = m_name;
    m["startOnAppStartup"] = m_startOnAppStartup;
    m["scheduleMode"] = m_scheduleMode;
    m["startTimeMinutes"] = m_startTimeMinutes;
    m["scheduleDaysMask"] = m_scheduleDaysMask;
    m["intervalHours"] = m_intervalHours;
    m["intervalMinutes"] = m_intervalMinutes;
    m["hasStopTime"] = m_hasStopTime;
    m["stopTimeMinutes"] = m_stopTimeMinutes;
    m["hasMaxRetries"] = m_hasMaxRetries;
    m["maxRetries"] = m_maxRetries;
    m["maxConcurrentDownloads"] = m_maxConcurrentDownloads;
    m["maxConcurrentTorrents"] = m_maxConcurrentTorrents;
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

namespace {

// Legacy v1 stored clock times as strings like "11:00:00 PM".
int parseLegacyTimeString(const QString &s, int fallbackMinutes)
{
    QTime t = QTime::fromString(s, QStringLiteral("h:mm:ss AP"));
    if (!t.isValid())
        t = QTime::fromString(s, QStringLiteral("h:mm AP"));
    if (!t.isValid())
        t = QTime::fromString(s, QStringLiteral("HH:mm:ss"));
    if (!t.isValid())
        t = QTime::fromString(s, QStringLiteral("HH:mm"));
    if (!t.isValid())
        return fallbackMinutes;
    return t.hour() * 60 + t.minute();
}

// Legacy v1 stored startDays as English day names.
int parseLegacyDayNames(const QStringList &names)
{
    static const struct { const char *name; int bit; } table[] = {
        {"Monday", 0}, {"Tuesday", 1}, {"Wednesday", 2}, {"Thursday", 3},
        {"Friday", 4}, {"Saturday", 5}, {"Sunday", 6},
    };
    int mask = 0;
    for (const QString &n : names) {
        for (const auto &e : table) {
            if (n.compare(QLatin1String(e.name), Qt::CaseInsensitive) == 0) {
                mask |= (1 << e.bit);
                break;
            }
        }
    }
    return mask == 0 ? 0x7F : mask;
}

} // namespace

Queue *Queue::fromVariantMap(const QString &id, const QVariantMap &map, QObject *parent)
{
    Queue *q = new Queue(id, parent);
    q->m_name = map.value(QStringLiteral("name"), QStringLiteral("Untitled Queue")).toString();

    const int version = map.value(QStringLiteral("version"), 1).toInt();
    if (version >= 2) {
        q->m_startOnAppStartup = map.value(QStringLiteral("startOnAppStartup"), false).toBool();
        q->m_scheduleMode = qBound(0, map.value(QStringLiteral("scheduleMode"), int(NoSchedule)).toInt(), int(Interval));
        q->m_startTimeMinutes = qBound(0, map.value(QStringLiteral("startTimeMinutes"), 23 * 60).toInt(), 24 * 60 - 1);
        q->m_scheduleDaysMask = map.value(QStringLiteral("scheduleDaysMask"), 0x7F).toInt() & 0x7F;
        q->m_intervalHours = qMax(0, map.value(QStringLiteral("intervalHours"), 2).toInt());
        q->m_intervalMinutes = qBound(0, map.value(QStringLiteral("intervalMinutes"), 0).toInt(), 59);
        q->m_hasStopTime = map.value(QStringLiteral("hasStopTime"), false).toBool();
        q->m_stopTimeMinutes = qBound(0, map.value(QStringLiteral("stopTimeMinutes"), 7 * 60 + 30).toInt(), 24 * 60 - 1);
        q->m_maxConcurrentTorrents = qMax(1, map.value(QStringLiteral("maxConcurrentTorrents"), 2).toInt());
    } else {
        // v1 migration: string times, name-list days, and the
        // hasStartTime/startOnce/startDaily/hasStartAgainEvery flag soup.
        q->m_startOnAppStartup = map.value(QStringLiteral("startOnIDMStartup"), false).toBool();
        q->m_startTimeMinutes = parseLegacyTimeString(
            map.value(QStringLiteral("startTime")).toString(), 23 * 60);
        q->m_scheduleDaysMask = parseLegacyDayNames(
            map.value(QStringLiteral("startDays")).toStringList());
        q->m_intervalHours = qMax(0, map.value(QStringLiteral("startAgainEveryHours"), 2).toInt());
        q->m_intervalMinutes = qBound(0, map.value(QStringLiteral("startAgainEveryMins"), 0).toInt(), 59);
        q->m_hasStopTime = map.value(QStringLiteral("hasStopTime"), false).toBool();
        q->m_stopTimeMinutes = parseLegacyTimeString(
            map.value(QStringLiteral("stopTime")).toString(), 7 * 60 + 30);

        const bool hasStartTime = map.value(QStringLiteral("hasStartTime"), false).toBool();
        const bool startDaily = map.value(QStringLiteral("startDaily"), false).toBool();
        if (map.value(QStringLiteral("hasStartAgainEvery"), false).toBool())
            q->m_scheduleMode = Interval;
        else if (hasStartTime && startDaily)
            q->m_scheduleMode = Daily;
        else if (hasStartTime)
            q->m_scheduleMode = Once;
        else
            q->m_scheduleMode = NoSchedule;
    }

    q->m_hasMaxRetries = map.value(QStringLiteral("hasMaxRetries"), false).toBool();
    q->m_maxRetries = map.value(QStringLiteral("maxRetries"), 10).toInt();
    q->m_maxConcurrentDownloads = qMax(1, map.value(QStringLiteral("maxConcurrentDownloads"), 3).toInt());
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
