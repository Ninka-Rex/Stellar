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
#include <QSettings>
#include <QStandardPaths>

class AppSettings : public QObject {
    Q_OBJECT
    Q_PROPERTY(int     maxConcurrent        READ maxConcurrent        WRITE setMaxConcurrent        NOTIFY maxConcurrentChanged)
    Q_PROPERTY(int     segmentsPerDownload  READ segmentsPerDownload  WRITE setSegmentsPerDownload  NOTIFY segmentsPerDownloadChanged)
    Q_PROPERTY(QString defaultSavePath      READ defaultSavePath      WRITE setDefaultSavePath      NOTIFY defaultSavePathChanged)
    Q_PROPERTY(int     globalSpeedLimitKBps READ globalSpeedLimitKBps WRITE setGlobalSpeedLimitKBps NOTIFY globalSpeedLimitKBpsChanged)
    Q_PROPERTY(bool    minimizeToTray       READ minimizeToTray       WRITE setMinimizeToTray       NOTIFY minimizeToTrayChanged)
    Q_PROPERTY(bool    closeToTray          READ closeToTray          WRITE setCloseToTray          NOTIFY closeToTrayChanged)
    Q_PROPERTY(int     maxRetries           READ maxRetries           WRITE setMaxRetries           NOTIFY maxRetriesChanged)
    Q_PROPERTY(int     connectionTimeoutSecs READ connectionTimeoutSecs WRITE setConnectionTimeoutSecs NOTIFY connectionTimeoutSecsChanged)
    Q_PROPERTY(QStringList monitoredExtensions READ monitoredExtensions WRITE setMonitoredExtensions NOTIFY monitoredExtensionsChanged)
    Q_PROPERTY(QStringList excludedSites      READ excludedSites       WRITE setExcludedSites       NOTIFY excludedSitesChanged)
    Q_PROPERTY(QStringList excludedAddresses  READ excludedAddresses   WRITE setExcludedAddresses   NOTIFY excludedAddressesChanged)
    Q_PROPERTY(bool showExceptionsDialog      READ showExceptionsDialog WRITE setShowExceptionsDialog NOTIFY showExceptionsDialogChanged)
    Q_PROPERTY(bool showTips                  READ showTips             WRITE setShowTips             NOTIFY showTipsChanged)
    // 0=Ask, 1=AddNumbered, 2=Overwrite, 3=Resume
    Q_PROPERTY(int  duplicateAction  READ duplicateAction  WRITE setDuplicateAction  NOTIFY duplicateActionChanged)
    Q_PROPERTY(bool startImmediately      READ startImmediately      WRITE setStartImmediately      NOTIFY startImmediatelyChanged)
    Q_PROPERTY(bool speedLimiterOnStartup READ speedLimiterOnStartup WRITE setSpeedLimiterOnStartup NOTIFY speedLimiterOnStartupChanged)
    Q_PROPERTY(int  savedSpeedLimitKBps  READ savedSpeedLimitKBps  WRITE setSavedSpeedLimitKBps  NOTIFY savedSpeedLimitKBpsChanged)
    Q_PROPERTY(bool showDownloadComplete READ showDownloadComplete WRITE setShowDownloadComplete NOTIFY showDownloadCompleteChanged)

public:
    explicit AppSettings(QObject *parent = nullptr);

    static QStringList defaultMonitoredExtensions();
    static QStringList defaultExcludedSites();
    static QStringList defaultExcludedAddresses();

    int     maxConcurrent()        const { return m_maxConcurrent; }
    int     segmentsPerDownload()  const { return m_segmentsPerDownload; }
    QString defaultSavePath()      const { return m_defaultSavePath; }
    int     globalSpeedLimitKBps() const { return m_globalSpeedLimitKBps; }
    bool    minimizeToTray()       const { return m_minimizeToTray; }
    bool    closeToTray()          const { return m_closeToTray; }
    int     maxRetries()           const { return m_maxRetries; }
    int     connectionTimeoutSecs() const { return m_connectionTimeoutSecs; }
    QStringList monitoredExtensions() const { return m_monitoredExtensions; }
    QStringList excludedSites()       const { return m_excludedSites; }
    QStringList excludedAddresses()   const { return m_excludedAddresses; }
    bool        showExceptionsDialog() const { return m_showExceptionsDialog; }
    bool        showTips()            const { return m_showTips; }
    int  duplicateAction() const { return m_duplicateAction; }
    bool startImmediately()       const { return m_startImmediately; }
    bool speedLimiterOnStartup()  const { return m_speedLimiterOnStartup; }
    int  savedSpeedLimitKBps()    const { return m_savedSpeedLimitKBps; }
    bool showDownloadComplete()   const { return m_showDownloadComplete; }

    void setMaxConcurrent(int v);
    void setSegmentsPerDownload(int v);
    void setDefaultSavePath(const QString &v);
    void setGlobalSpeedLimitKBps(int v);
    void setMinimizeToTray(bool v);
    void setCloseToTray(bool v);
    void setMaxRetries(int v);
    void setConnectionTimeoutSecs(int v);
    void setMonitoredExtensions(const QStringList &v);
    void setExcludedSites(const QStringList &v);
    void setExcludedAddresses(const QStringList &v);
    void setShowExceptionsDialog(bool v);
    void setShowTips(bool v);
    void setDuplicateAction(int v);
    void setStartImmediately(bool v);
    void setSpeedLimiterOnStartup(bool v);
    void setSavedSpeedLimitKBps(int v);
    void setShowDownloadComplete(bool v);

    Q_INVOKABLE void save();
    Q_INVOKABLE void load();

signals:
    void maxConcurrentChanged();
    void segmentsPerDownloadChanged();
    void defaultSavePathChanged();
    void globalSpeedLimitKBpsChanged();
    void minimizeToTrayChanged();
    void closeToTrayChanged();
    void maxRetriesChanged();
    void connectionTimeoutSecsChanged();
    void monitoredExtensionsChanged();
    void excludedSitesChanged();
    void excludedAddressesChanged();
    void showExceptionsDialogChanged();
    void showTipsChanged();
    void duplicateActionChanged();
    void startImmediatelyChanged();
    void speedLimiterOnStartupChanged();
    void savedSpeedLimitKBpsChanged();
    void showDownloadCompleteChanged();

private:
    int     m_maxConcurrent{3};
    int     m_segmentsPerDownload{8};
    QString m_defaultSavePath;
    int     m_globalSpeedLimitKBps{0};
    bool    m_minimizeToTray{true};
    bool    m_closeToTray{true};
    int     m_maxRetries{3};
    int     m_connectionTimeoutSecs{30};
    QStringList m_monitoredExtensions;
    QStringList m_excludedSites;
    QStringList m_excludedAddresses;
    bool        m_showExceptionsDialog{true};
    bool        m_showTips{true};
    int         m_duplicateAction{0};
    bool        m_startImmediately{false};
    bool        m_speedLimiterOnStartup{false};
    int         m_savedSpeedLimitKBps{500};
    bool        m_showDownloadComplete{true};

    QSettings m_settings;

};
