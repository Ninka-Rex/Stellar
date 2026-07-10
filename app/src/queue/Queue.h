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
#include <QString>
#include <QDateTime>
#include <QTime>

class Queue : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString id              READ id              CONSTANT)
    Q_PROPERTY(QString name            READ name            WRITE setName        NOTIFY nameChanged)
    Q_PROPERTY(bool startOnAppStartup  READ startOnAppStartup WRITE setStartOnAppStartup NOTIFY startOnAppStartupChanged)
    Q_PROPERTY(int scheduleMode        READ scheduleMode    WRITE setScheduleMode NOTIFY scheduleChanged)
    Q_PROPERTY(int startTimeMinutes    READ startTimeMinutes WRITE setStartTimeMinutes NOTIFY scheduleChanged)
    Q_PROPERTY(int scheduleDaysMask    READ scheduleDaysMask WRITE setScheduleDaysMask NOTIFY scheduleChanged)
    Q_PROPERTY(int intervalHours       READ intervalHours   WRITE setIntervalHours NOTIFY scheduleChanged)
    Q_PROPERTY(int intervalMinutes     READ intervalMinutes WRITE setIntervalMinutes NOTIFY scheduleChanged)
    Q_PROPERTY(bool hasStopTime        READ hasStopTime     WRITE setHasStopTime NOTIFY scheduleChanged)
    Q_PROPERTY(int stopTimeMinutes     READ stopTimeMinutes WRITE setStopTimeMinutes NOTIFY scheduleChanged)
    Q_PROPERTY(bool hasMaxRetries      READ hasMaxRetries   WRITE setHasMaxRetries NOTIFY maxRetriesChanged)
    Q_PROPERTY(int maxRetries          READ maxRetries      WRITE setMaxRetries  NOTIFY maxRetriesChanged)
    Q_PROPERTY(int maxConcurrentDownloads READ maxConcurrentDownloads WRITE setMaxConcurrentDownloads NOTIFY maxConcurrentChanged)
    Q_PROPERTY(int maxConcurrentTorrents READ maxConcurrentTorrents WRITE setMaxConcurrentTorrents NOTIFY maxConcurrentChanged)
    Q_PROPERTY(bool openFileWhenDone   READ openFileWhenDone WRITE setOpenFileWhenDone NOTIFY postActionChanged)
    Q_PROPERTY(QString openFilePath    READ openFilePath    WRITE setOpenFilePath NOTIFY postActionChanged)
    Q_PROPERTY(bool exitIDMWhenDone    READ exitIDMWhenDone WRITE setExitIDMWhenDone NOTIFY postActionChanged)
    Q_PROPERTY(bool turnOffComputerWhenDone READ turnOffComputerWhenDone WRITE setTurnOffComputerWhenDone NOTIFY postActionChanged)
    Q_PROPERTY(bool forceProcessesToTerminate READ forceProcessesToTerminate WRITE setForceProcessesToTerminate NOTIFY postActionChanged)
    Q_PROPERTY(bool hasDownloadLimits READ hasDownloadLimits WRITE setHasDownloadLimits NOTIFY downloadLimitsChanged)
    Q_PROPERTY(int downloadLimitMBytes READ downloadLimitMBytes WRITE setDownloadLimitMBytes NOTIFY downloadLimitsChanged)
    Q_PROPERTY(int downloadLimitHours READ downloadLimitHours WRITE setDownloadLimitHours NOTIFY downloadLimitsChanged)
    Q_PROPERTY(bool warnBeforeStopping READ warnBeforeStopping WRITE setWarnBeforeStopping NOTIFY downloadLimitsChanged)

public:
    // How (and whether) the queue starts on its own. Once fires at the next
    // occurrence of startTimeMinutes and then reverts itself to NoSchedule.
    enum ScheduleMode {
        NoSchedule = 0,
        Once       = 1,
        Daily      = 2,
        Interval   = 3,
    };
    Q_ENUM(ScheduleMode)

    explicit Queue(const QString &id, QObject *parent = nullptr);

    // Core properties
    QString id() const { return m_id; }
    QString name() const { return m_name; }
    void setName(const QString &v) { if (m_name != v) { m_name = v; emit nameChanged(); } }

    // Startup
    bool startOnAppStartup() const { return m_startOnAppStartup; }
    void setStartOnAppStartup(bool v) { if (m_startOnAppStartup != v) { m_startOnAppStartup = v; emit startOnAppStartupChanged(); } }

    // Schedule
    int scheduleMode() const { return m_scheduleMode; }
    void setScheduleMode(int v) { if (m_scheduleMode != v) { m_scheduleMode = v; emit scheduleChanged(); } }
    int startTimeMinutes() const { return m_startTimeMinutes; }
    void setStartTimeMinutes(int v) { v = qBound(0, v, 24 * 60 - 1); if (m_startTimeMinutes != v) { m_startTimeMinutes = v; emit scheduleChanged(); } }
    // Bit (Qt::DayOfWeek - 1): bit 0 = Monday ... bit 6 = Sunday
    int scheduleDaysMask() const { return m_scheduleDaysMask; }
    void setScheduleDaysMask(int v) { v &= 0x7F; if (m_scheduleDaysMask != v) { m_scheduleDaysMask = v; emit scheduleChanged(); } }
    int intervalHours() const { return m_intervalHours; }
    void setIntervalHours(int v) { v = qMax(0, v); if (m_intervalHours != v) { m_intervalHours = v; emit scheduleChanged(); } }
    int intervalMinutes() const { return m_intervalMinutes; }
    void setIntervalMinutes(int v) { v = qBound(0, v, 59); if (m_intervalMinutes != v) { m_intervalMinutes = v; emit scheduleChanged(); } }

    // Stop time
    bool hasStopTime() const { return m_hasStopTime; }
    void setHasStopTime(bool v) { if (m_hasStopTime != v) { m_hasStopTime = v; emit scheduleChanged(); } }
    int stopTimeMinutes() const { return m_stopTimeMinutes; }
    void setStopTimeMinutes(int v) { v = qBound(0, v, 24 * 60 - 1); if (m_stopTimeMinutes != v) { m_stopTimeMinutes = v; emit scheduleChanged(); } }

    // Retry
    bool hasMaxRetries() const { return m_hasMaxRetries; }
    void setHasMaxRetries(bool v) { if (m_hasMaxRetries != v) { m_hasMaxRetries = v; emit maxRetriesChanged(); } }
    int maxRetries() const { return m_maxRetries; }
    void setMaxRetries(int v) { if (m_maxRetries != v) { m_maxRetries = v; emit maxRetriesChanged(); } }

    // Concurrency
    int maxConcurrentDownloads() const { return m_maxConcurrentDownloads; }
    void setMaxConcurrentDownloads(int v) { v = qMax(1, v); if (m_maxConcurrentDownloads != v) { m_maxConcurrentDownloads = v; emit maxConcurrentChanged(); } }
    int maxConcurrentTorrents() const { return m_maxConcurrentTorrents; }
    void setMaxConcurrentTorrents(int v) { v = qMax(1, v); if (m_maxConcurrentTorrents != v) { m_maxConcurrentTorrents = v; emit maxConcurrentChanged(); } }

    // Post-completion actions
    bool openFileWhenDone() const { return m_openFileWhenDone; }
    void setOpenFileWhenDone(bool v) { if (m_openFileWhenDone != v) { m_openFileWhenDone = v; emit postActionChanged(); } }
    QString openFilePath() const { return m_openFilePath; }
    void setOpenFilePath(const QString &v) { if (m_openFilePath != v) { m_openFilePath = v; emit postActionChanged(); } }

    bool exitIDMWhenDone() const { return m_exitIDMWhenDone; }
    void setExitIDMWhenDone(bool v) { if (m_exitIDMWhenDone != v) { m_exitIDMWhenDone = v; emit postActionChanged(); } }

    bool turnOffComputerWhenDone() const { return m_turnOffComputerWhenDone; }
    void setTurnOffComputerWhenDone(bool v) { if (m_turnOffComputerWhenDone != v) { m_turnOffComputerWhenDone = v; emit postActionChanged(); } }

    bool forceProcessesToTerminate() const { return m_forceProcessesToTerminate; }
    void setForceProcessesToTerminate(bool v) { if (m_forceProcessesToTerminate != v) { m_forceProcessesToTerminate = v; emit postActionChanged(); } }

    // Download limits
    bool hasDownloadLimits() const { return m_hasDownloadLimits; }
    void setHasDownloadLimits(bool v) { if (m_hasDownloadLimits != v) { m_hasDownloadLimits = v; emit downloadLimitsChanged(); } }
    int downloadLimitMBytes() const { return m_downloadLimitMBytes; }
    void setDownloadLimitMBytes(int v) { if (m_downloadLimitMBytes != v) { m_downloadLimitMBytes = v; emit downloadLimitsChanged(); } }
    int downloadLimitHours() const { return m_downloadLimitHours; }
    void setDownloadLimitHours(int v) { if (m_downloadLimitHours != v) { m_downloadLimitHours = v; emit downloadLimitsChanged(); } }
    bool warnBeforeStopping() const { return m_warnBeforeStopping; }
    void setWarnBeforeStopping(bool v) { if (m_warnBeforeStopping != v) { m_warnBeforeStopping = v; emit downloadLimitsChanged(); } }

    // Serialize to/from QVariantMap
    QVariantMap toVariantMap() const;
    static Queue *fromVariantMap(const QString &id, const QVariantMap &map, QObject *parent = nullptr);

signals:
    void nameChanged();
    void startOnAppStartupChanged();
    void scheduleChanged();
    void maxRetriesChanged();
    void maxConcurrentChanged();
    void postActionChanged();
    void downloadLimitsChanged();

private:
    QString m_id;
    QString m_name = "Untitled Queue";
    bool m_startOnAppStartup = false;

    int m_scheduleMode = NoSchedule;
    int m_startTimeMinutes = 23 * 60;      // 11:00 PM
    int m_scheduleDaysMask = 0x7F;         // all days
    int m_intervalHours = 2;
    int m_intervalMinutes = 0;

    bool m_hasStopTime = false;
    int m_stopTimeMinutes = 7 * 60 + 30;   // 7:30 AM

    bool m_hasMaxRetries = false;
    int m_maxRetries = 10;

    int m_maxConcurrentDownloads = 3;
    int m_maxConcurrentTorrents = 2;

    bool m_openFileWhenDone = false;
    QString m_openFilePath;
    bool m_exitIDMWhenDone = false;
    bool m_turnOffComputerWhenDone = false;
    bool m_forceProcessesToTerminate = false;

    bool m_hasDownloadLimits = false;
    int m_downloadLimitMBytes = 200;
    int m_downloadLimitHours = 5;
    bool m_warnBeforeStopping = true;
};
