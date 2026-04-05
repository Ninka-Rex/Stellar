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
#include <QStringList>
#include <QDateTime>
#include <QTime>

class Queue : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString id              READ id              CONSTANT)
    Q_PROPERTY(QString name            READ name            WRITE setName        NOTIFY nameChanged)
    Q_PROPERTY(bool isDownloadQueue    READ isDownloadQueue WRITE setIsDownloadQueue NOTIFY typeChanged)
    Q_PROPERTY(bool startOnIDMStartup  READ startOnIDMStartup WRITE setStartOnIDMStartup NOTIFY startOnIDMStartupChanged)
    Q_PROPERTY(bool hasStartTime       READ hasStartTime    WRITE setHasStartTime NOTIFY startTimeChanged)
    Q_PROPERTY(QString startTime       READ startTime       WRITE setStartTime   NOTIFY startTimeChanged)
    Q_PROPERTY(bool startOnce          READ startOnce       WRITE setStartOnce   NOTIFY scheduleTypeChanged)
    Q_PROPERTY(bool startDaily         READ startDaily      WRITE setStartDaily  NOTIFY scheduleTypeChanged)
    Q_PROPERTY(QStringList startDays   READ startDays       WRITE setStartDays   NOTIFY startDaysChanged)
    Q_PROPERTY(bool hasStartAgainEvery READ hasStartAgainEvery WRITE setHasStartAgainEvery NOTIFY periodChanged)
    Q_PROPERTY(int startAgainEveryHours READ startAgainEveryHours WRITE setStartAgainEveryHours NOTIFY periodChanged)
    Q_PROPERTY(int startAgainEveryMins  READ startAgainEveryMins  WRITE setStartAgainEveryMins  NOTIFY periodChanged)
    Q_PROPERTY(bool hasStopTime        READ hasStopTime     WRITE setHasStopTime NOTIFY stopTimeChanged)
    Q_PROPERTY(QString stopTime        READ stopTime        WRITE setStopTime    NOTIFY stopTimeChanged)
    Q_PROPERTY(bool hasMaxRetries      READ hasMaxRetries   WRITE setHasMaxRetries NOTIFY maxRetriesChanged)
    Q_PROPERTY(int maxRetries          READ maxRetries      WRITE setMaxRetries  NOTIFY maxRetriesChanged)
    Q_PROPERTY(int maxConcurrentDownloads READ maxConcurrentDownloads WRITE setMaxConcurrentDownloads NOTIFY maxConcurrentChanged)
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
    explicit Queue(const QString &id, QObject *parent = nullptr);

    // Core properties
    QString id() const { return m_id; }
    QString name() const { return m_name; }
    void setName(const QString &v) { if (m_name != v) { m_name = v; emit nameChanged(); } }

    // Queue type
    bool isDownloadQueue() const { return m_isDownloadQueue; }
    void setIsDownloadQueue(bool v) { if (m_isDownloadQueue != v) { m_isDownloadQueue = v; emit typeChanged(); } }

    // Startup
    bool startOnIDMStartup() const { return m_startOnIDMStartup; }
    void setStartOnIDMStartup(bool v) { if (m_startOnIDMStartup != v) { m_startOnIDMStartup = v; emit startOnIDMStartupChanged(); } }

    // Start time controls
    bool hasStartTime() const { return m_hasStartTime; }
    void setHasStartTime(bool v) { if (m_hasStartTime != v) { m_hasStartTime = v; emit startTimeChanged(); } }
    QString startTime() const { return m_startTime; }
    void setStartTime(const QString &v) { if (m_startTime != v) { m_startTime = v; emit startTimeChanged(); } }

    // Schedule type
    bool startOnce() const { return m_startOnce; }
    void setStartOnce(bool v) { if (m_startOnce != v) { m_startOnce = v; if (v) m_startDaily = false; emit scheduleTypeChanged(); } }
    bool startDaily() const { return m_startDaily; }
    void setStartDaily(bool v) { if (m_startDaily != v) { m_startDaily = v; if (v) m_startOnce = false; emit scheduleTypeChanged(); } }

    QStringList startDays() const { return m_startDays; }
    void setStartDays(const QStringList &v) { if (m_startDays != v) { m_startDays = v; emit startDaysChanged(); } }

    // Periodic sync (synchronization queue only)
    bool hasStartAgainEvery() const { return m_hasStartAgainEvery; }
    void setHasStartAgainEvery(bool v) { if (m_hasStartAgainEvery != v) { m_hasStartAgainEvery = v; emit periodChanged(); } }
    int startAgainEveryHours() const { return m_startAgainEveryHours; }
    void setStartAgainEveryHours(int v) { if (m_startAgainEveryHours != v) { m_startAgainEveryHours = v; emit periodChanged(); } }
    int startAgainEveryMins() const { return m_startAgainEveryMins; }
    void setStartAgainEveryMins(int v) { if (m_startAgainEveryMins != v) { m_startAgainEveryMins = v; emit periodChanged(); } }

    // Stop time
    bool hasStopTime() const { return m_hasStopTime; }
    void setHasStopTime(bool v) { if (m_hasStopTime != v) { m_hasStopTime = v; emit stopTimeChanged(); } }
    QString stopTime() const { return m_stopTime; }
    void setStopTime(const QString &v) { if (m_stopTime != v) { m_stopTime = v; emit stopTimeChanged(); } }

    // Retry
    bool hasMaxRetries() const { return m_hasMaxRetries; }
    void setHasMaxRetries(bool v) { if (m_hasMaxRetries != v) { m_hasMaxRetries = v; emit maxRetriesChanged(); } }
    int maxRetries() const { return m_maxRetries; }
    void setMaxRetries(int v) { if (m_maxRetries != v) { m_maxRetries = v; emit maxRetriesChanged(); } }

    // Concurrency
    int maxConcurrentDownloads() const { return m_maxConcurrentDownloads; }
    void setMaxConcurrentDownloads(int v) { if (m_maxConcurrentDownloads != v) { m_maxConcurrentDownloads = v; emit maxConcurrentChanged(); } }

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
    void typeChanged();
    void startOnIDMStartupChanged();
    void startTimeChanged();
    void scheduleTypeChanged();
    void startDaysChanged();
    void periodChanged();
    void stopTimeChanged();
    void maxRetriesChanged();
    void maxConcurrentChanged();
    void postActionChanged();
    void downloadLimitsChanged();

private:
    QString m_id;
    QString m_name = "Untitled Queue";
    bool m_isDownloadQueue = true;
    bool m_startOnIDMStartup = false;

    bool m_hasStartTime = false;
    QString m_startTime = "11:00:00 PM";

    bool m_startOnce = true;
    bool m_startDaily = false;
    QStringList m_startDays = {"Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"};

    bool m_hasStartAgainEvery = false;
    int m_startAgainEveryHours = 2;
    int m_startAgainEveryMins = 0;

    bool m_hasStopTime = false;
    QString m_stopTime = "7:30:00 AM";

    bool m_hasMaxRetries = false;
    int m_maxRetries = 10;

    int m_maxConcurrentDownloads = 1;

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
