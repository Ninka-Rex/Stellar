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
#include <QDate>

class AppSettings : public QObject {
    Q_OBJECT
    Q_PROPERTY(int     maxConcurrent        READ maxConcurrent        WRITE setMaxConcurrent        NOTIFY maxConcurrentChanged)
    Q_PROPERTY(int     segmentsPerDownload  READ segmentsPerDownload  WRITE setSegmentsPerDownload  NOTIFY segmentsPerDownloadChanged)
    Q_PROPERTY(QString defaultSavePath      READ defaultSavePath      WRITE setDefaultSavePath      NOTIFY defaultSavePathChanged)
    Q_PROPERTY(QString temporaryDirectory   READ temporaryDirectory   WRITE setTemporaryDirectory   NOTIFY temporaryDirectoryChanged)
    Q_PROPERTY(QString torrentCustomSavePath READ torrentCustomSavePath WRITE setTorrentCustomSavePath NOTIFY torrentCustomSavePathChanged)
    Q_PROPERTY(bool torrentUseCustomSavePathByDefault READ torrentUseCustomSavePathByDefault WRITE setTorrentUseCustomSavePathByDefault NOTIFY torrentCustomSavePathByDefaultChanged)
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
    Q_PROPERTY(bool showCompletionNotification READ showCompletionNotification WRITE setShowCompletionNotification NOTIFY showCompletionNotificationChanged)
    Q_PROPERTY(bool showErrorNotification READ showErrorNotification WRITE setShowErrorNotification NOTIFY showErrorNotificationChanged)
    Q_PROPERTY(bool showFinishedCount   READ showFinishedCount   WRITE setShowFinishedCount   NOTIFY showFinishedCountChanged)
    Q_PROPERTY(bool speedInTrayTooltip  READ speedInTrayTooltip  WRITE setSpeedInTrayTooltip  NOTIFY speedInTrayTooltipChanged)
    Q_PROPERTY(bool speedInTitleBar     READ speedInTitleBar     WRITE setSpeedInTitleBar     NOTIFY speedInTitleBarChanged)
    Q_PROPERTY(bool speedInStatusBar    READ speedInStatusBar    WRITE setSpeedInStatusBar    NOTIFY speedInStatusBarChanged)
    Q_PROPERTY(bool estimatedOnlineUsersInStatusBar READ estimatedOnlineUsersInStatusBar WRITE setEstimatedOnlineUsersInStatusBar NOTIFY estimatedOnlineUsersInStatusBarChanged)
    Q_PROPERTY(bool ratioInStatusBar    READ ratioInStatusBar    WRITE setRatioInStatusBar    NOTIFY ratioInStatusBarChanged)
    Q_PROPERTY(bool showPublicIpInStatusBar READ showPublicIpInStatusBar WRITE setShowPublicIpInStatusBar NOTIFY showPublicIpInStatusBarChanged)
    Q_PROPERTY(bool startDownloadWhileFileInfo READ startDownloadWhileFileInfo WRITE setStartDownloadWhileFileInfo NOTIFY startDownloadWhileFileInfoChanged)
    Q_PROPERTY(bool showQueueSelectionOnDownloadLater READ showQueueSelectionOnDownloadLater WRITE setShowQueueSelectionOnDownloadLater NOTIFY showQueueSelectionOnDownloadLaterChanged)
    Q_PROPERTY(bool showQueueSelectionOnBatchDownload READ showQueueSelectionOnBatchDownload WRITE setShowQueueSelectionOnBatchDownload NOTIFY showQueueSelectionOnBatchDownloadChanged)
    Q_PROPERTY(bool useCustomUserAgent READ useCustomUserAgent WRITE setUseCustomUserAgent NOTIFY useCustomUserAgentChanged)
    Q_PROPERTY(QString customUserAgent READ customUserAgent WRITE setCustomUserAgent NOTIFY customUserAgentChanged)
    Q_PROPERTY(QString downloadTableColumns READ downloadTableColumns WRITE setDownloadTableColumns NOTIFY downloadTableColumnsChanged)
    Q_PROPERTY(int grabberFilesToExploreAtOnce READ grabberFilesToExploreAtOnce WRITE setGrabberFilesToExploreAtOnce NOTIFY grabberFilesToExploreAtOnceChanged)
    Q_PROPERTY(int grabberFilesToDownloadAtOnce READ grabberFilesToDownloadAtOnce WRITE setGrabberFilesToDownloadAtOnce NOTIFY grabberFilesToDownloadAtOnceChanged)
    Q_PROPERTY(bool grabberUseLinkTextAsDescription READ grabberUseLinkTextAsDescription WRITE setGrabberUseLinkTextAsDescription NOTIFY grabberUseLinkTextAsDescriptionChanged)
    Q_PROPERTY(bool grabberUseAdvancedProcessing READ grabberUseAdvancedProcessing WRITE setGrabberUseAdvancedProcessing NOTIFY grabberUseAdvancedProcessingChanged)
    Q_PROPERTY(QString grabberIncludeFiltersJson READ grabberIncludeFiltersJson WRITE setGrabberIncludeFiltersJson NOTIFY grabberIncludeFiltersJsonChanged)
    Q_PROPERTY(QString grabberExcludeFiltersJson READ grabberExcludeFiltersJson WRITE setGrabberExcludeFiltersJson NOTIFY grabberExcludeFiltersJsonChanged)
    // Ordered list of sidebar section IDs — determines the top-to-bottom display order.
    // Valid IDs: "downloads", "unfinished", "finished", "queues", "torrents"
    Q_PROPERTY(QStringList sidebarOrder READ sidebarOrder WRITE setSidebarOrder NOTIFY sidebarOrderChanged)
    // Ordered list of torrent subcategory IDs within the Torrents section.
    // Valid IDs: "torrent_downloading", "torrent_seeding", "torrent_stopped",
    //            "torrent_active", "torrent_inactive", "torrent_checking", "torrent_moving"
    Q_PROPERTY(QStringList torrentSubcatOrder READ torrentSubcatOrder WRITE setTorrentSubcatOrder NOTIFY torrentSubcatOrderChanged)
    // Modifier key to bypass download interception: 0=None, 1=Alt, 2=Ctrl, 3=Shift
    Q_PROPERTY(int bypassInterceptKey READ bypassInterceptKey WRITE setBypassInterceptKey NOTIFY bypassInterceptKeyChanged)
    // Launch Stellar automatically when the OS starts
    Q_PROPERTY(bool launchOnStartup READ launchOnStartup WRITE setLaunchOnStartup NOTIFY launchOnStartupChanged)
    // Clipboard URL monitoring — detects URLs matching monitored file types
    Q_PROPERTY(bool clipboardMonitorEnabled READ clipboardMonitorEnabled WRITE setClipboardMonitorEnabled NOTIFY clipboardMonitorEnabledChanged)
    // Double-click action in download list: 0=Properties, 1=OpenFile, 2=OpenFolder
    Q_PROPERTY(int  doubleClickAction READ doubleClickAction WRITE setDoubleClickAction NOTIFY doubleClickActionChanged)
    // Speed limiter scheduler — JSON array of schedule rules
    Q_PROPERTY(bool    speedScheduleEnabled READ speedScheduleEnabled WRITE setSpeedScheduleEnabled NOTIFY speedScheduleEnabledChanged)
    Q_PROPERTY(QString speedScheduleJson    READ speedScheduleJson    WRITE setSpeedScheduleJson    NOTIFY speedScheduleJsonChanged)
    Q_PROPERTY(bool autoCheckUpdates READ autoCheckUpdates WRITE setAutoCheckUpdates NOTIFY autoCheckUpdatesChanged)
    Q_PROPERTY(QString skippedUpdateVersion READ skippedUpdateVersion WRITE setSkippedUpdateVersion NOTIFY skippedUpdateVersionChanged)
    Q_PROPERTY(int lastTryDateStyle READ lastTryDateStyle WRITE setLastTryDateStyle NOTIFY lastTryDateStyleChanged)
    Q_PROPERTY(bool lastTryUse24Hour READ lastTryUse24Hour WRITE setLastTryUse24Hour NOTIFY lastTryUse24HourChanged)
    Q_PROPERTY(bool lastTryShowSeconds READ lastTryShowSeconds WRITE setLastTryShowSeconds NOTIFY lastTryShowSecondsChanged)
    Q_PROPERTY(int mainWindowX      READ mainWindowX      WRITE setMainWindowX      NOTIFY mainWindowXChanged)
    Q_PROPERTY(int mainWindowY      READ mainWindowY      WRITE setMainWindowY      NOTIFY mainWindowYChanged)
    Q_PROPERTY(int mainWindowWidth READ mainWindowWidth WRITE setMainWindowWidth NOTIFY mainWindowWidthChanged)
    Q_PROPERTY(int mainWindowHeight READ mainWindowHeight WRITE setMainWindowHeight NOTIFY mainWindowHeightChanged)
    // yt-dlp integration
    Q_PROPERTY(QString ytdlpCustomBinaryPath READ ytdlpCustomBinaryPath WRITE setYtdlpCustomBinaryPath NOTIFY ytdlpCustomBinaryPathChanged)
    Q_PROPERTY(bool    ytdlpAutoUpdate       READ ytdlpAutoUpdate       WRITE setYtdlpAutoUpdate       NOTIFY ytdlpAutoUpdateChanged)
    // Path to a JS runtime for yt-dlp's EJS YouTube challenge solver (deno/node/bun/qjs).
    // Empty = auto-detect from PATH and app directory.
    Q_PROPERTY(QString ytdlpJsRuntimePath    READ ytdlpJsRuntimePath    WRITE setYtdlpJsRuntimePath    NOTIFY ytdlpJsRuntimePathChanged)
    Q_PROPERTY(bool    torrentEnableDht READ torrentEnableDht WRITE setTorrentEnableDht NOTIFY torrentSettingsChanged)
    Q_PROPERTY(bool    torrentEnableLsd READ torrentEnableLsd WRITE setTorrentEnableLsd NOTIFY torrentSettingsChanged)
    Q_PROPERTY(bool    torrentEnableUpnp READ torrentEnableUpnp WRITE setTorrentEnableUpnp NOTIFY torrentSettingsChanged)
    Q_PROPERTY(bool    torrentEnableNatPmp READ torrentEnableNatPmp WRITE setTorrentEnableNatPmp NOTIFY torrentSettingsChanged)
    Q_PROPERTY(bool    torrentEnablePex READ torrentEnablePex WRITE setTorrentEnablePex NOTIFY torrentSettingsChanged)
    Q_PROPERTY(int     torrentListenPort READ torrentListenPort WRITE setTorrentListenPort NOTIFY torrentSettingsChanged)
    Q_PROPERTY(int     torrentConnectionsLimit READ torrentConnectionsLimit WRITE setTorrentConnectionsLimit NOTIFY torrentSettingsChanged)
    Q_PROPERTY(int     torrentConnectionsLimitPerTorrent READ torrentConnectionsLimitPerTorrent WRITE setTorrentConnectionsLimitPerTorrent NOTIFY torrentSettingsChanged)
    Q_PROPERTY(int     torrentUploadSlotsLimit READ torrentUploadSlotsLimit WRITE setTorrentUploadSlotsLimit NOTIFY torrentSettingsChanged)
    Q_PROPERTY(int     torrentUploadSlotsLimitPerTorrent READ torrentUploadSlotsLimitPerTorrent WRITE setTorrentUploadSlotsLimitPerTorrent NOTIFY torrentSettingsChanged)
    Q_PROPERTY(int     torrentProtocol READ torrentProtocol WRITE setTorrentProtocol NOTIFY torrentSettingsChanged)
    Q_PROPERTY(int     torrentDownloadLimitKBps READ torrentDownloadLimitKBps WRITE setTorrentDownloadLimitKBps NOTIFY torrentSettingsChanged)
    Q_PROPERTY(int     torrentUploadLimitKBps READ torrentUploadLimitKBps WRITE setTorrentUploadLimitKBps NOTIFY torrentSettingsChanged)
    Q_PROPERTY(int     globalUploadLimitKBps READ globalUploadLimitKBps WRITE setGlobalUploadLimitKBps NOTIFY globalUploadLimitKBpsChanged)
    Q_PROPERTY(double  torrentDefaultShareRatio READ torrentDefaultShareRatio WRITE setTorrentDefaultShareRatio NOTIFY torrentSettingsChanged)
    Q_PROPERTY(int     torrentDefaultSeedingTimeMins READ torrentDefaultSeedingTimeMins WRITE setTorrentDefaultSeedingTimeMins NOTIFY torrentSettingsChanged)
    Q_PROPERTY(int     torrentDefaultInactiveSeedingTimeMins READ torrentDefaultInactiveSeedingTimeMins WRITE setTorrentDefaultInactiveSeedingTimeMins NOTIFY torrentSettingsChanged)
    Q_PROPERTY(int     torrentDefaultShareLimitAction READ torrentDefaultShareLimitAction WRITE setTorrentDefaultShareLimitAction NOTIFY torrentSettingsChanged)
    Q_PROPERTY(QString torrentCustomUserAgent READ torrentCustomUserAgent WRITE setTorrentCustomUserAgent NOTIFY torrentSettingsChanged)
    Q_PROPERTY(QString torrentBindInterface READ torrentBindInterface WRITE setTorrentBindInterface NOTIFY torrentSettingsChanged)
    Q_PROPERTY(QStringList torrentBannedPeers READ torrentBannedPeers WRITE setTorrentBannedPeers NOTIFY torrentSettingsChanged)
    Q_PROPERTY(QString torrentBlockedPeerUserAgents READ torrentBlockedPeerUserAgents WRITE setTorrentBlockedPeerUserAgents NOTIFY torrentSettingsChanged)
    Q_PROPERTY(QStringList torrentBlockedPeerCountries READ torrentBlockedPeerCountries WRITE setTorrentBlockedPeerCountries NOTIFY torrentSettingsChanged)
    Q_PROPERTY(bool torrentAutoBanAbusivePeers READ torrentAutoBanAbusivePeers WRITE setTorrentAutoBanAbusivePeers NOTIFY torrentSettingsChanged)
    Q_PROPERTY(bool torrentAutoBanMediaPlayerPeers READ torrentAutoBanMediaPlayerPeers WRITE setTorrentAutoBanMediaPlayerPeers NOTIFY torrentSettingsChanged)
    // Encryption mode: 0=Prefer (default), 1=Require, 2=Allow (disable encryption)
    Q_PROPERTY(int  torrentEncryptionMode READ torrentEncryptionMode WRITE setTorrentEncryptionMode NOTIFY torrentSettingsChanged)
    // Proxy — 0=None, 1=System, 2=HTTP/HTTPS, 3=SOCKS5
    // Per-host connection limit — caps concurrent segments to a single server (some ban >4)
    Q_PROPERTY(int     perHostConnectionLimit READ perHostConnectionLimit WRITE setPerHostConnectionLimit NOTIFY perHostConnectionLimitChanged)
    Q_PROPERTY(int     proxyType     READ proxyType     WRITE setProxyType     NOTIFY proxyTypeChanged)
    Q_PROPERTY(QString proxyHost     READ proxyHost     WRITE setProxyHost     NOTIFY proxyHostChanged)
    Q_PROPERTY(int     proxyPort     READ proxyPort     WRITE setProxyPort     NOTIFY proxyPortChanged)
    Q_PROPERTY(QString proxyUsername READ proxyUsername WRITE setProxyUsername NOTIFY proxyUsernameChanged)
    Q_PROPERTY(QString proxyPassword READ proxyPassword WRITE setProxyPassword NOTIFY proxyPasswordChanged)
    // RSS settings
    Q_PROPERTY(bool    rssEnabled           READ rssEnabled           WRITE setRssEnabled           NOTIFY rssEnabledChanged)
    Q_PROPERTY(int     rssRefreshIntervalMins READ rssRefreshIntervalMins WRITE setRssRefreshIntervalMins NOTIFY rssRefreshIntervalMinsChanged)
    Q_PROPERTY(int     rssSameHostDelayMs   READ rssSameHostDelayMs   WRITE setRssSameHostDelayMs   NOTIFY rssSameHostDelayMsChanged)
    Q_PROPERTY(int     rssMaxArticlesPerFeed READ rssMaxArticlesPerFeed WRITE setRssMaxArticlesPerFeed NOTIFY rssMaxArticlesPerFeedChanged)
    Q_PROPERTY(bool    rssAutoDownloadEnabled READ rssAutoDownloadEnabled WRITE setRssAutoDownloadEnabled NOTIFY rssAutoDownloadEnabledChanged)
    Q_PROPERTY(bool    rssSmartFilterRepack READ rssSmartFilterRepack WRITE setRssSmartFilterRepack NOTIFY rssSmartFilterRepackChanged)
    Q_PROPERTY(QString rssSmartFiltersJson  READ rssSmartFiltersJson  WRITE setRssSmartFiltersJson  NOTIFY rssSmartFiltersJsonChanged)
    Q_PROPERTY(QString rssDownloadRulesJson READ rssDownloadRulesJson WRITE setRssDownloadRulesJson NOTIFY rssDownloadRulesJsonChanged)

public:
    explicit AppSettings(QObject *parent = nullptr);

    static QStringList defaultMonitoredExtensions();
    static QStringList defaultExcludedSites();
    static QStringList defaultExcludedAddresses();

    int     maxConcurrent()        const { return m_maxConcurrent; }
    int     segmentsPerDownload()  const { return m_segmentsPerDownload; }
    QString defaultSavePath()      const { return m_defaultSavePath; }
    QString temporaryDirectory()   const { return m_temporaryDirectory; }
    QString torrentCustomSavePath() const { return m_torrentCustomSavePath; }
    bool torrentUseCustomSavePathByDefault() const { return m_torrentUseCustomSavePathByDefault; }
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
    bool showCompletionNotification() const { return m_showCompletionNotification; }
    bool showErrorNotification() const { return m_showErrorNotification; }
    bool showFinishedCount()      const { return m_showFinishedCount; }
    bool speedInTrayTooltip()     const { return m_speedInTrayTooltip; }
    bool speedInTitleBar()        const { return m_speedInTitleBar; }
    bool speedInStatusBar()       const { return m_speedInStatusBar; }
    bool estimatedOnlineUsersInStatusBar() const { return m_estimatedOnlineUsersInStatusBar; }
    bool ratioInStatusBar()       const { return m_ratioInStatusBar; }
    bool showPublicIpInStatusBar() const { return m_showPublicIpInStatusBar; }
    bool startDownloadWhileFileInfo() const { return m_startDownloadWhileFileInfo; }
    bool showQueueSelectionOnDownloadLater() const { return m_showQueueSelectionOnDownloadLater; }
    bool showQueueSelectionOnBatchDownload() const { return m_showQueueSelectionOnBatchDownload; }
    bool useCustomUserAgent()     const { return m_useCustomUserAgent; }
    QString customUserAgent()     const { return m_customUserAgent; }
    QString downloadTableColumns() const { return m_downloadTableColumns; }
    int grabberFilesToExploreAtOnce() const { return m_grabberFilesToExploreAtOnce; }
    int grabberFilesToDownloadAtOnce() const { return m_grabberFilesToDownloadAtOnce; }
    bool grabberUseLinkTextAsDescription() const { return m_grabberUseLinkTextAsDescription; }
    bool grabberUseAdvancedProcessing() const { return m_grabberUseAdvancedProcessing; }
    QString grabberIncludeFiltersJson() const { return m_grabberIncludeFiltersJson; }
    QString grabberExcludeFiltersJson() const { return m_grabberExcludeFiltersJson; }
    QStringList sidebarOrder()         const { return m_sidebarOrder; }
    QStringList torrentSubcatOrder()   const { return m_torrentSubcatOrder; }
    int  bypassInterceptKey()         const { return m_bypassInterceptKey; }
    bool launchOnStartup()            const { return m_launchOnStartup; }
    bool clipboardMonitorEnabled()    const { return m_clipboardMonitorEnabled; }
    int  doubleClickAction()          const { return m_doubleClickAction; }
    bool speedScheduleEnabled()       const { return m_speedScheduleEnabled; }
    QString speedScheduleJson()       const { return m_speedScheduleJson; }
    bool autoCheckUpdates()           const { return m_autoCheckUpdates; }
    QString skippedUpdateVersion()    const { return m_skippedUpdateVersion; }
    int  lastTryDateStyle()           const { return m_lastTryDateStyle; }
    bool lastTryUse24Hour()           const { return m_lastTryUse24Hour; }
    bool lastTryShowSeconds()         const { return m_lastTryShowSeconds; }
    int  mainWindowX()                const { return m_mainWindowX; }
    int  mainWindowY()                const { return m_mainWindowY; }
    int  mainWindowWidth()            const { return m_mainWindowWidth; }
    int  mainWindowHeight()           const { return m_mainWindowHeight; }
    QString ytdlpCustomBinaryPath()   const { return m_ytdlpCustomBinaryPath; }
    bool    ytdlpAutoUpdate()         const { return m_ytdlpAutoUpdate; }
    QString ytdlpJsRuntimePath()      const { return m_ytdlpJsRuntimePath; }
    bool    torrentEnableDht()        const { return m_torrentEnableDht; }
    bool    torrentEnableLsd()        const { return m_torrentEnableLsd; }
    bool    torrentEnableUpnp()       const { return m_torrentEnableUpnp; }
    bool    torrentEnableNatPmp()     const { return m_torrentEnableNatPmp; }
    bool    torrentEnablePex()        const { return m_torrentEnablePex; }
    int     torrentListenPort()       const { return m_torrentListenPort; }
    int     torrentConnectionsLimit() const { return m_torrentConnectionsLimit; }
    int     torrentConnectionsLimitPerTorrent() const { return m_torrentConnectionsLimitPerTorrent; }
    int     torrentUploadSlotsLimit() const { return m_torrentUploadSlotsLimit; }
    int     torrentUploadSlotsLimitPerTorrent() const { return m_torrentUploadSlotsLimitPerTorrent; }
    int     torrentProtocol() const { return m_torrentProtocol; }
    int     torrentDownloadLimitKBps() const { return m_torrentDownloadLimitKBps; }
    int     torrentUploadLimitKBps()  const { return m_torrentUploadLimitKBps; }
    int     globalUploadLimitKBps()   const { return m_globalUploadLimitKBps; }
    double  torrentDefaultShareRatio() const { return m_torrentDefaultShareRatio; }
    int     torrentDefaultSeedingTimeMins() const { return m_torrentDefaultSeedingTimeMins; }
    int     torrentDefaultInactiveSeedingTimeMins() const { return m_torrentDefaultInactiveSeedingTimeMins; }
    int     torrentDefaultShareLimitAction() const { return m_torrentDefaultShareLimitAction; }
    QString torrentCustomUserAgent()  const { return m_torrentCustomUserAgent; }
    QString torrentBindInterface()    const { return m_torrentBindInterface; }
    QStringList torrentBannedPeers() const { return m_torrentBannedPeers; }
    QString torrentBlockedPeerUserAgents() const { return m_torrentBlockedPeerUserAgents; }
    QStringList torrentBlockedPeerCountries() const { return m_torrentBlockedPeerCountries; }
    bool torrentAutoBanAbusivePeers() const { return m_torrentAutoBanAbusivePeers; }
    bool torrentAutoBanMediaPlayerPeers() const { return m_torrentAutoBanMediaPlayerPeers; }
    int  torrentEncryptionMode()          const { return m_torrentEncryptionMode; }
    int     proxyType()               const { return m_proxyType; }
    QString proxyHost()               const { return m_proxyHost; }
    int     proxyPort()               const { return m_proxyPort; }
    QString proxyUsername()           const { return m_proxyUsername; }
    QString proxyPassword()           const { return m_proxyPassword; }
    int     perHostConnectionLimit()  const { return m_perHostConnectionLimit; }
    bool    rssEnabled()              const { return m_rssEnabled; }
    int     rssRefreshIntervalMins()  const { return m_rssRefreshIntervalMins; }
    int     rssSameHostDelayMs()      const { return m_rssSameHostDelayMs; }
    int     rssMaxArticlesPerFeed()   const { return m_rssMaxArticlesPerFeed; }
    bool    rssAutoDownloadEnabled()  const { return m_rssAutoDownloadEnabled; }
    bool    rssSmartFilterRepack()    const { return m_rssSmartFilterRepack; }
    QString rssSmartFiltersJson()     const { return m_rssSmartFiltersJson; }
    QString rssDownloadRulesJson()    const { return m_rssDownloadRulesJson; }
    QString motdDismissedHash() const { return m_motdDismissedHash; }
    qint64 motdDismissedUntilUtcMs() const { return m_motdDismissedUntilUtcMs; }

    void setMaxConcurrent(int v);
    void setSegmentsPerDownload(int v);
    void setDefaultSavePath(const QString &v);
    void setTemporaryDirectory(const QString &v);
    void setTorrentCustomSavePath(const QString &v);
    void setTorrentUseCustomSavePathByDefault(bool v);
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
    void setShowCompletionNotification(bool v);
    void setShowErrorNotification(bool v);
    void setShowFinishedCount(bool v);
    void setSpeedInTrayTooltip(bool v);
    void setSpeedInTitleBar(bool v);
    void setSpeedInStatusBar(bool v);
    void setEstimatedOnlineUsersInStatusBar(bool v);
    void setRatioInStatusBar(bool v);
    void setShowPublicIpInStatusBar(bool v);
    void setStartDownloadWhileFileInfo(bool v);
    void setShowQueueSelectionOnDownloadLater(bool v);
    void setShowQueueSelectionOnBatchDownload(bool v);
    void setUseCustomUserAgent(bool v);
    void setCustomUserAgent(const QString &v);
    void setDownloadTableColumns(const QString &v);
    void setGrabberFilesToExploreAtOnce(int v);
    void setGrabberFilesToDownloadAtOnce(int v);
    void setGrabberUseLinkTextAsDescription(bool v);
    void setGrabberUseAdvancedProcessing(bool v);
    void setGrabberIncludeFiltersJson(const QString &v);
    void setGrabberExcludeFiltersJson(const QString &v);
    void setSidebarOrder(const QStringList &v);
    void setTorrentSubcatOrder(const QStringList &v);
    void setBypassInterceptKey(int v);
    void setLaunchOnStartup(bool v);
    void setClipboardMonitorEnabled(bool v);
    void setDoubleClickAction(int v);
    void setSpeedScheduleEnabled(bool v);
    void setSpeedScheduleJson(const QString &v);
    void setAutoCheckUpdates(bool v);
    void setSkippedUpdateVersion(const QString &v);
    void setLastTryDateStyle(int v);
    void setLastTryUse24Hour(bool v);
    void setLastTryShowSeconds(bool v);
    void setMainWindowX(int v);
    void setMainWindowY(int v);
    void setMainWindowWidth(int v);
    void setMainWindowHeight(int v);
    void setYtdlpCustomBinaryPath(const QString &v);
    void setYtdlpAutoUpdate(bool v);
    void setYtdlpJsRuntimePath(const QString &v);
    void setTorrentEnableDht(bool v);
    void setTorrentEnableLsd(bool v);
    void setTorrentEnableUpnp(bool v);
    void setTorrentEnableNatPmp(bool v);
    void setTorrentEnablePex(bool v);
    void setTorrentListenPort(int v);
    void setTorrentConnectionsLimit(int v);
    void setTorrentConnectionsLimitPerTorrent(int v);
    void setTorrentUploadSlotsLimit(int v);
    void setTorrentUploadSlotsLimitPerTorrent(int v);
    void setTorrentProtocol(int v);
    void setTorrentDownloadLimitKBps(int v);
    void setTorrentUploadLimitKBps(int v);
    void setGlobalUploadLimitKBps(int v);
    void setTorrentDefaultShareRatio(double v);
    void setTorrentDefaultSeedingTimeMins(int v);
    void setTorrentDefaultInactiveSeedingTimeMins(int v);
    void setTorrentDefaultShareLimitAction(int v);
    void setTorrentCustomUserAgent(const QString &v);
    void setTorrentBindInterface(const QString &v);
    void setTorrentBannedPeers(const QStringList &v);
    void setTorrentBlockedPeerUserAgents(const QString &v);
    void setTorrentBlockedPeerCountries(const QStringList &v);
    void setTorrentAutoBanAbusivePeers(bool v);
    void setTorrentAutoBanMediaPlayerPeers(bool v);
    void setTorrentEncryptionMode(int v);
    qint64 torrentHistoricalUploadedBytes() const { return m_torrentHistoricalUploadedBytes; }
    qint64 torrentHistoricalDownloadedBytes() const { return m_torrentHistoricalDownloadedBytes; }
    void accumulateTorrentStats(qint64 uploadedBytes, qint64 downloadedBytes);
    void resetTorrentHistoricalStats();

    // Install date — set once on the first run, never changed again.
    QDate installDate() const { return m_installDate; }
    // Total accumulated uptime in seconds across all sessions.
    qint64 totalUptimeSecs() const { return m_totalUptimeSecs; }
    // Call on app exit with the number of seconds elapsed in this session.
    void accumulateUptimeSecs(qint64 secs);
    // Number of times the app has been launched (incremented once per run on load).
    int totalStartups() const { return m_totalStartups; }
    void setProxyType(int v);
    void setProxyHost(const QString &v);
    void setProxyPort(int v);
    void setProxyUsername(const QString &v);
    void setPerHostConnectionLimit(int v);
    void setProxyPassword(const QString &v);
    void setRssEnabled(bool v);
    void setRssRefreshIntervalMins(int v);
    void setRssSameHostDelayMs(int v);
    void setRssMaxArticlesPerFeed(int v);
    void setRssAutoDownloadEnabled(bool v);
    void setRssSmartFilterRepack(bool v);
    void setRssSmartFiltersJson(const QString &v);
    void setRssDownloadRulesJson(const QString &v);
    void setMotdDismissal(const QString &hash, qint64 untilUtcMs);
    void clearMotdDismissal();

    Q_INVOKABLE void save();
    Q_INVOKABLE void load();

signals:
    void maxConcurrentChanged();
    void segmentsPerDownloadChanged();
    void defaultSavePathChanged();
    void temporaryDirectoryChanged();
    void torrentCustomSavePathChanged();
    void torrentCustomSavePathByDefaultChanged();
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
    void showCompletionNotificationChanged();
    void showErrorNotificationChanged();
    void showFinishedCountChanged();
    void speedInTrayTooltipChanged();
    void speedInTitleBarChanged();
    void speedInStatusBarChanged();
    void estimatedOnlineUsersInStatusBarChanged();
    void ratioInStatusBarChanged();
    void showPublicIpInStatusBarChanged();
    void startDownloadWhileFileInfoChanged();
    void showQueueSelectionOnDownloadLaterChanged();
    void showQueueSelectionOnBatchDownloadChanged();
    void useCustomUserAgentChanged();
    void customUserAgentChanged();
    void downloadTableColumnsChanged();
    void grabberFilesToExploreAtOnceChanged();
    void grabberFilesToDownloadAtOnceChanged();
    void grabberUseLinkTextAsDescriptionChanged();
    void grabberUseAdvancedProcessingChanged();
    void grabberIncludeFiltersJsonChanged();
    void grabberExcludeFiltersJsonChanged();
    void sidebarOrderChanged();
    void torrentSubcatOrderChanged();
    void bypassInterceptKeyChanged();
    void launchOnStartupChanged();
    void clipboardMonitorEnabledChanged();
    void doubleClickActionChanged();
    void speedScheduleEnabledChanged();
    void speedScheduleJsonChanged();
    void autoCheckUpdatesChanged();
    void skippedUpdateVersionChanged();
    void lastTryDateStyleChanged();
    void lastTryUse24HourChanged();
    void lastTryShowSecondsChanged();
    void mainWindowXChanged();
    void mainWindowYChanged();
    void mainWindowWidthChanged();
    void mainWindowHeightChanged();
    void ytdlpCustomBinaryPathChanged();
    void ytdlpAutoUpdateChanged();
    void ytdlpJsRuntimePathChanged();
    void torrentSettingsChanged();
    void globalUploadLimitKBpsChanged();
    void proxyTypeChanged();
    void proxyHostChanged();
    void proxyPortChanged();
    void proxyUsernameChanged();
    void perHostConnectionLimitChanged();
    void proxyPasswordChanged();
    void rssEnabledChanged();
    void rssRefreshIntervalMinsChanged();
    void rssSameHostDelayMsChanged();
    void rssMaxArticlesPerFeedChanged();
    void rssAutoDownloadEnabledChanged();
    void rssSmartFilterRepackChanged();
    void rssSmartFiltersJsonChanged();
    void rssDownloadRulesJsonChanged();

private:
    int     m_maxConcurrent{3};
    int     m_segmentsPerDownload{8};
    QString m_defaultSavePath;
    QString m_temporaryDirectory;
    QString m_torrentCustomSavePath;
    bool    m_torrentUseCustomSavePathByDefault{false};
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
    bool        m_showCompletionNotification{true};
    bool        m_showErrorNotification{true};
    bool        m_showFinishedCount{true};
    bool        m_speedInTrayTooltip{true};
    bool        m_speedInTitleBar{false};
    bool        m_speedInStatusBar{false};
    bool        m_estimatedOnlineUsersInStatusBar{false};
    bool        m_ratioInStatusBar{false};
    bool        m_showPublicIpInStatusBar{false};
    bool        m_startDownloadWhileFileInfo{true};
    bool        m_showQueueSelectionOnDownloadLater{true};
    bool        m_showQueueSelectionOnBatchDownload{true};
    bool        m_useCustomUserAgent{false};
    QString     m_customUserAgent;
    QString     m_downloadTableColumns;
    int         m_grabberFilesToExploreAtOnce{4};
    int         m_grabberFilesToDownloadAtOnce{4};
    bool        m_grabberUseLinkTextAsDescription{true};
    bool        m_grabberUseAdvancedProcessing{true};
    QString     m_grabberIncludeFiltersJson;
    QString     m_grabberExcludeFiltersJson;
    QStringList m_sidebarOrder{{"downloads", "unfinished", "finished", "grabber", "queues", "torrents"}};
    QStringList m_torrentSubcatOrder{{"torrent_downloading", "torrent_seeding", "torrent_stopped",
                                      "torrent_active", "torrent_inactive", "torrent_checking", "torrent_moving"}};
    int         m_bypassInterceptKey{1};  // 1 = Alt key by default
    bool        m_launchOnStartup{false};
    bool        m_clipboardMonitorEnabled{false};
    int         m_doubleClickAction{0};   // 0=Properties, 1=OpenFile, 2=OpenFolder
    bool        m_speedScheduleEnabled{false};
    QString     m_speedScheduleJson;      // JSON array of schedule rules
    bool        m_autoCheckUpdates{true};
    QString     m_skippedUpdateVersion;
    int         m_lastTryDateStyle{0};    // 0=Apr 10 2026, 1=4/10/2026, 2=10/4/2026, 3=2026-04-10
    bool        m_lastTryUse24Hour{true};
    bool        m_lastTryShowSeconds{true};
    int         m_mainWindowX{-1};      // -1 = not set, let the OS decide on first run
    int         m_mainWindowY{-1};
    int         m_mainWindowWidth{1100};
    int         m_mainWindowHeight{680};
    QString     m_ytdlpCustomBinaryPath;   // empty = auto-detect
    bool        m_ytdlpAutoUpdate{false};  // check for yt-dlp updates on startup
    QString     m_ytdlpJsRuntimePath;      // empty = auto-detect from PATH/app dir
    bool        m_torrentEnableDht{true};
    bool        m_torrentEnableLsd{true};
    bool        m_torrentEnableUpnp{true};
    bool        m_torrentEnableNatPmp{true};
    bool        m_torrentEnablePex{true};
    int         m_torrentListenPort{6881};
    int         m_torrentConnectionsLimit{200};            // libtorrent default: 200
    int         m_torrentConnectionsLimitPerTorrent{0};   // 0 = use libtorrent default (-1 = unlimited)
    int         m_torrentUploadSlotsLimit{8};             // libtorrent default: 8
    int         m_torrentUploadSlotsLimitPerTorrent{0};   // 0 = use libtorrent default (-1 = unlimited)
    int         m_torrentProtocol{0};                     // 0=TCP+μTP, 1=μTP only, 2=TCP only
    int         m_torrentDownloadLimitKBps{0};
    int         m_torrentUploadLimitKBps{0};
    int         m_globalUploadLimitKBps{0};
    double      m_torrentDefaultShareRatio{0.0};
    int         m_torrentDefaultSeedingTimeMins{0};
    int         m_torrentDefaultInactiveSeedingTimeMins{0};
    int         m_torrentDefaultShareLimitAction{1};
    QString     m_torrentCustomUserAgent;
    QString     m_torrentBindInterface;
    QStringList m_torrentBannedPeers;
    QString     m_torrentBlockedPeerUserAgents;
    QStringList m_torrentBlockedPeerCountries;
    bool        m_torrentAutoBanAbusivePeers{false};
    bool        m_torrentAutoBanMediaPlayerPeers{false};
    int         m_torrentEncryptionMode{0}; // 0=Prefer, 1=Require, 2=Allow
    // All-time torrent transfer accumulators — incremented when a torrent item is deleted
    qint64      m_torrentHistoricalUploadedBytes{0};
    qint64      m_torrentHistoricalDownloadedBytes{0};
    // First-run date (recorded once and never overwritten).
    QDate       m_installDate;
    // Total cumulative app uptime in seconds (accumulated across sessions).
    qint64      m_totalUptimeSecs{0};
    // Incremented on every load() call (i.e. each app launch).
    int         m_totalStartups{0};
    // Proxy — 0=None, 1=System, 2=HTTP/HTTPS, 3=SOCKS5
    int         m_proxyType{0};
    QString     m_proxyHost;
    int         m_proxyPort{8080};
    QString     m_proxyUsername;
    int         m_perHostConnectionLimit{8};
    QString     m_proxyPassword;
    bool        m_rssEnabled{true};
    int         m_rssRefreshIntervalMins{30};
    int         m_rssSameHostDelayMs{2000};
    int         m_rssMaxArticlesPerFeed{50};
    bool        m_rssAutoDownloadEnabled{false};
    bool        m_rssSmartFilterRepack{true};
    QString     m_rssSmartFiltersJson{QStringLiteral("[\"s(\\\\d+)e(\\\\d+)\",\"(\\\\d+)x(\\\\d+)\",\"(\\\\d{4}[.\\\\-]\\\\d{1,2}[.\\\\-]\\\\d{1,2})\",\"(\\\\d{1,2}[.\\\\-]\\\\d{1,2}[.\\\\-]\\\\d{4})\"]")};
    QString     m_rssDownloadRulesJson{QStringLiteral("[]")};
    QString     m_motdDismissedHash;
    qint64      m_motdDismissedUntilUtcMs{0};

    // Apply or remove OS startup entry depending on v
    void applyStartupRegistration(bool v) const;

    QSettings m_settings;

};
