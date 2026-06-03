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
#include <QTimer>
#include <QDate>

// ============================================================================
// X-Macro property table — single source of truth for all simple settings.
// Included in each class section with different X definitions to generate
// Q_PROPERTY, getters, setters, signals, and members.
//
// Columns:
//   ptype - type for Q_PROPERTY, getter return, and member variable
//   sparam - setter parameter type (int, const QString &, etc.)
//   mem - member name in camelCase (also property name)
//   camel - CamelCase variant for setter method
//   def - C++ expression for member initializer and load() fallback
//   key - QSettings key string
//   flags - N=normal, T=torrent (shared signal), S=scheduleSave
// ============================================================================
#define APP_SETTINGS(X) \
    /* ── Download engine ── */ \
    X(int, int, maxConcurrent, MaxConcurrent, 3, "maxConcurrent", N) \
    X(int, int, segmentsPerDownload, SegmentsPerDownload, 8, "segmentsPerDownload", N) \
    X(int, int, globalSpeedLimitKBps, GlobalSpeedLimitKBps, 0, "globalSpeedLimitKBps", N) \
    X(bool, bool, speedLimiterEnabled, SpeedLimiterEnabled, false, "speedLimiterEnabled", N) \
    X(int, int, maxRetries, MaxRetries, 3, "maxRetries", N) \
    X(int, int, connectionTimeoutSecs, ConnectionTimeoutSecs, 30, "connectionTimeoutSecs", N) \
    X(int, int, perHostConnectionLimit, PerHostConnectionLimit, 8, "perHostConnectionLimit", N) \
    X(int, int, globalUploadLimitKBps, GlobalUploadLimitKBps, 0, "globalUploadLimitKBps", N) \
    /* ── UI: general ── */ \
    X(bool, bool, minimizeToTray, MinimizeToTray, true, "minimizeToTray", N) \
    X(bool, bool, closeToTray, CloseToTray, true, "closeToTray", N) \
    X(bool, bool, showTips, ShowTips, true, "showTips", N) \
    X(bool, bool, showExceptionsDialog, ShowExceptionsDialog, true, "showExceptionsDialog", N) \
    X(bool, bool, showFinishedCount, ShowFinishedCount, true, "showFinishedCount", N) \
    X(bool, bool, speedInTrayTooltip, SpeedInTrayTooltip, true, "speedInTrayTooltip", N) \
    X(bool, bool, speedInTitleBar, SpeedInTitleBar, false, "speedInTitleBar", N) \
    X(bool, bool, speedInStatusBar, SpeedInStatusBar, false, "speedInStatusBar", N) \
    X(bool, bool, estimatedOnlineUsersInStatusBar, EstimatedOnlineUsersInStatusBar, false, "estimatedOnlineUsersInStatusBar", N) \
    X(bool, bool, ratioInStatusBar, RatioInStatusBar, false, "ratioInStatusBar", N) \
    X(bool, bool, showPublicIpInStatusBar, ShowPublicIpInStatusBar, false, "showPublicIpInStatusBar", N) \
    X(bool, bool, showStatusBar, ShowStatusBar, true, "showStatusBar", N) \
    X(bool, bool, toolbarSmallButtons, ToolbarSmallButtons, false, "toolbarSmallButtons", N) \
    X(bool, bool, showSearchEngine, ShowSearchEngine, false, "showSearchEngine", N) \
    X(bool, bool, showRssReader, ShowRssReader, false, "showRssReader", N) \
    X(int, int, sidebarWidth, SidebarWidth, 188, "sidebarWidth", S) \
    X(bool, bool, sidebarOnRight, SidebarOnRight, false, "sidebarOnRight", S) \
    X(int, int, mainWindowX, MainWindowX, -1, "mainWindowX", N) \
    X(int, int, mainWindowY, MainWindowY, -1, "mainWindowY", N) \
    X(int, int, mainWindowWidth, MainWindowWidth, 1100, "mainWindowWidth", N) \
    X(int, int, mainWindowHeight, MainWindowHeight, 680, "mainWindowHeight", N) \
    X(QString, const QString &, downloadTableColumns, DownloadTableColumns, QString(), "downloadTableColumns", N) \
    X(QString, const QString &, toolbarButtonDefs, ToolbarButtonDefs, QString(), "toolbarButtonDefs", N) \
    X(double, double, uiScaleFactor, UiScaleFactor, 0.0, "uiScaleFactor", N) \
    X(int, int, uiFontPointSize, UiFontPointSize, 0, "uiFontPointSize", N) \
    /* ── UI: downloads ── */ \
    X(int, int, duplicateAction, DuplicateAction, 0, "duplicateAction", N) \
    X(bool, bool, startImmediately, StartImmediately, false, "startImmediately", N) \
    X(bool, bool, showDownloadComplete, ShowDownloadComplete, true, "showDownloadComplete", N) \
    X(bool, bool, showCompletionNotification, ShowCompletionNotification, true, "showCompletionNotification", N) \
    X(bool, bool, showErrorNotification, ShowErrorNotification, true, "showErrorNotification", N) \
    X(bool, bool, startDownloadWhileFileInfo, StartDownloadWhileFileInfo, true, "startDownloadWhileFileInfo", N) \
    X(bool, bool, showQueueSelectionOnDownloadLater, ShowQueueSelectionOnDownloadLater, true, "showQueueSelectionOnDownloadLater", N) \
    X(bool, bool, showQueueSelectionOnBatchDownload, ShowQueueSelectionOnBatchDownload, true, "showQueueSelectionOnBatchDownload", N) \
    X(int, int, doubleClickAction, DoubleClickAction, 0, "doubleClickAction", N) \
    /* ── Speed limiter scheduler ── */ \
    X(bool, bool, speedLimiterOnStartup, SpeedLimiterOnStartup, false, "speedLimiterOnStartup", N) \
    X(int, int, savedSpeedLimitKBps, SavedSpeedLimitKBps, 500, "savedSpeedLimitKBps", N) \
    X(int, int, savedUploadLimitKBps, SavedUploadLimitKBps, 0, "savedUploadLimitKBps", N) \
    X(bool, bool, speedScheduleEnabled, SpeedScheduleEnabled, false, "speedScheduleEnabled", N) \
    X(QString, const QString &, speedScheduleJson, SpeedScheduleJson, QString(), "speedScheduleJson", N) \
    /* ── Clipboard monitor ── */ \
    X(bool, bool, clipboardMonitorEnabled, ClipboardMonitorEnabled, false, "clipboardMonitorEnabled", N) \
    /* ── Browser interception ── */ \
    X(int, int, bypassInterceptKey, BypassInterceptKey, 1, "bypassInterceptKey", N) \
    /* ── User-Agent ── */ \
    X(bool, bool, useCustomUserAgent, UseCustomUserAgent, false, "useCustomUserAgent", N) \
    /* ── Grabber ── */ \
    X(int, int, grabberFilesToExploreAtOnce, GrabberFilesToExploreAtOnce, 4, "grabberFilesToExploreAtOnce", N) \
    X(int, int, grabberFilesToDownloadAtOnce, GrabberFilesToDownloadAtOnce, 4, "grabberFilesToDownloadAtOnce", N) \
    X(bool, bool, grabberUseLinkTextAsDescription, GrabberUseLinkTextAsDescription, true, "grabberUseLinkTextAsDescription", N) \
    X(bool, bool, grabberUseAdvancedProcessing, GrabberUseAdvancedProcessing, true, "grabberUseAdvancedProcessing", N) \
    X(QString, const QString &, grabberIncludeFiltersJson, GrabberIncludeFiltersJson, QString(), "grabberIncludeFiltersJson", N) \
    X(QString, const QString &, grabberExcludeFiltersJson, GrabberExcludeFiltersJson, QString(), "grabberExcludeFiltersJson", N) \
    /* ── Updates ── */ \
    X(bool, bool, autoCheckUpdates, AutoCheckUpdates, true, "autoCheckUpdates", N) \
    X(QString, const QString &, skippedUpdateVersion, SkippedUpdateVersion, QString(), "skippedUpdateVersion", N) \
    /* ── Date/time display ── */ \
    X(int, int, lastTryDateStyle, LastTryDateStyle, 0, "lastTryDateStyle", N) \
    X(bool, bool, lastTryUse24Hour, LastTryUse24Hour, true, "lastTryUse24Hour", N) \
    X(bool, bool, lastTryShowSeconds, LastTryShowSeconds, true, "lastTryShowSeconds", N) \
    /* ── yt-dlp ── */ \
    X(QString, const QString &, ytdlpCustomBinaryPath, YtdlpCustomBinaryPath, QString(), "ytdlpCustomBinaryPath", N) \
    X(bool, bool, ytdlpAutoUpdate, YtdlpAutoUpdate, false, "ytdlpAutoUpdate", N) \
    X(QString, const QString &, ytdlpJsRuntimePath, YtdlpJsRuntimePath, QString(), "ytdlpJsRuntimePath", N) \
    X(QString, const QString &, ytdlpDefaultCookieBrowser, YtdlpDefaultCookieBrowser, QString(), "ytdlpDefaultCookieBrowser", N) \
    /* ── Proxy ── */ \
    X(int, int, proxyType, ProxyType, 0, "proxyType", N) \
    X(QString, const QString &, proxyHost, ProxyHost, QString(), "proxyHost", N) \
    X(int, int, proxyPort, ProxyPort, 8080, "proxyPort", N) \
    /* ── RSS ── */ \
    X(bool, bool, rssEnabled, RssEnabled, true, "rssEnabled", N) \
    X(int, int, rssRefreshIntervalMins, RssRefreshIntervalMins, 30, "rssRefreshIntervalMins", N) \
    X(int, int, rssSameHostDelayMs, RssSameHostDelayMs, 2000, "rssSameHostDelayMs", N) \
    X(int, int, rssMaxArticlesPerFeed, RssMaxArticlesPerFeed, 50, "rssMaxArticlesPerFeed", N) \
    X(bool, bool, rssAutoDownloadEnabled, RssAutoDownloadEnabled, false, "rssAutoDownloadEnabled", N) \
    X(bool, bool, rssSmartFilterRepack, RssSmartFilterRepack, true, "rssSmartFilterRepack", N) \
    /* ── i18n & appearance ── */ \
    X(QString, const QString &, uiLanguage, UiLanguage, QString(), "uiLanguage", N) \
    X(int, int, trayIconStyle, TrayIconStyle, 0, "trayIconStyle", N) \
    X(bool, bool, darkMode, DarkMode, true, "ui/darkMode", N) \
    /* ── Torrent: torrentSettingsChanged signal ── */ \
    X(int, int, torrentListenPort, TorrentListenPort, 6881, "torrentListenPort", T) \
    X(int, int, torrentConnectionsLimit, TorrentConnectionsLimit, 200, "torrentConnectionsLimit", T) \
    X(int, int, torrentConnectionsLimitPerTorrent, TorrentConnectionsLimitPerTorrent, 0, "torrentConnectionsLimitPerTorrent", T) \
    X(int, int, torrentUploadSlotsLimit, TorrentUploadSlotsLimit, 8, "torrentUploadSlotsLimit", T) \
    X(int, int, torrentUploadSlotsLimitPerTorrent, TorrentUploadSlotsLimitPerTorrent, 0, "torrentUploadSlotsLimitPerTorrent", T) \
    X(int, int, torrentProtocol, TorrentProtocol, 0, "torrentProtocol", T) \
    X(int, int, torrentDownloadLimitKBps, TorrentDownloadLimitKBps, 0, "torrentDownloadLimitKBps", T) \
    X(int, int, torrentUploadLimitKBps, TorrentUploadLimitKBps, 0, "torrentUploadLimitKBps", T) \
    X(double, double, torrentDefaultShareRatio, TorrentDefaultShareRatio, 0.0, "torrentDefaultShareRatio", T) \
    X(int, int, torrentDefaultSeedingTimeMins, TorrentDefaultSeedingTimeMins, 0, "torrentDefaultSeedingTimeMins", T) \
    X(int, int, torrentDefaultInactiveSeedingTimeMins, TorrentDefaultInactiveSeedingTimeMins, 0, "torrentDefaultInactiveSeedingTimeMins", T) \
    X(int, int, torrentDefaultShareLimitAction, TorrentDefaultShareLimitAction, 1, "torrentDefaultShareLimitAction", T) \
    X(QString, const QString &, torrentCustomUserAgent, TorrentCustomUserAgent, QString(), "torrentCustomUserAgent", T) \
    X(QString, const QString &, torrentBindInterface, TorrentBindInterface, QString(), "torrentBindInterface", T) \
    X(QStringList, const QStringList &, torrentBannedPeers, TorrentBannedPeers, QStringList(), "torrentBannedPeers", T) \
    X(QString, const QString &, torrentBlockedPeerUserAgents, TorrentBlockedPeerUserAgents, QString(), "torrentBlockedPeerUserAgents", T) \
    X(QStringList, const QStringList &, torrentBlockedPeerCountries, TorrentBlockedPeerCountries, QStringList(), "torrentBlockedPeerCountries", T) \
    X(bool, bool, torrentEnableDht, TorrentEnableDht, true, "torrentEnableDht", T) \
    X(bool, bool, torrentEnableLsd, TorrentEnableLsd, true, "torrentEnableLsd", T) \
    X(bool, bool, torrentEnableUpnp, TorrentEnableUpnp, true, "torrentEnableUpnp", T) \
    X(bool, bool, torrentEnableNatPmp, TorrentEnableNatPmp, true, "torrentEnableNatPmp", T) \
    X(bool, bool, torrentEnablePex, TorrentEnablePex, true, "torrentEnablePex", T) \
    X(bool, bool, torrentAutoBanAbusivePeers, TorrentAutoBanAbusivePeers, false, "torrentAutoBanAbusivePeers", T) \
    X(bool, bool, torrentAutoBanMediaPlayerPeers, TorrentAutoBanMediaPlayerPeers, false, "torrentAutoBanMediaPlayerPeers", T) \
    X(int, int, torrentEncryptionMode, TorrentEncryptionMode, 0, "torrentEncryptionMode", T) \
    X(int, int, torrentStorageMode, TorrentStorageMode, 0, "torrentStorageMode", T) \
    X(bool, bool, torrentPieceExtentAffinity, TorrentPieceExtentAffinity, false, "torrentPieceExtentAffinity", T) \
    X(bool, bool, torrentCoalesceReads, TorrentCoalesceReads, false, "torrentCoalesceReads", T) \
    X(bool, bool, torrentCoalesceWrites, TorrentCoalesceWrites, false, "torrentCoalesceWrites", T) \
    X(int, int, torrentDiskIoType, TorrentDiskIoType, 0, "torrentDiskIoType", T) \
    X(int, int, torrentDiskWriteQueueMiB, TorrentDiskWriteQueueMiB, 64, "torrentDiskWriteQueueMiB", T) \
    /* ── Torrent: startup behavior ── */ \
    X(bool, bool, torrentStopOnStartup, TorrentStopOnStartup, false, "torrentStopOnStartup", N)


class AppSettings : public QObject {
    Q_OBJECT

    // ========================================================================
    // Generated Q_PROPERTY declarations
    // ========================================================================
#define QPROP_N(ptype, sp, mem, camel, def, key) Q_PROPERTY(ptype mem READ mem WRITE set##camel NOTIFY mem##Changed)
#define QPROP_T(ptype, sp, mem, camel, def, key) Q_PROPERTY(ptype mem READ mem WRITE set##camel NOTIFY torrentSettingsChanged)
#define QPROP_S(ptype, sp, mem, camel, def, key) Q_PROPERTY(ptype mem READ mem WRITE set##camel NOTIFY mem##Changed)
#define QPROP(ptype, sp, mem, camel, def, key, flags) QPROP_##flags(ptype, sp, mem, camel, def, key)
#define X(ptype, sp, mem, camel, def, key, flags) QPROP(ptype, sp, mem, camel, def, key, flags)
    APP_SETTINGS(X)
#undef X
#undef QPROP
#undef QPROP_S
#undef QPROP_T
#undef QPROP_N

    // --- Manual Q_PROPERTY declarations ---
    Q_PROPERTY(QString defaultSavePath      READ defaultSavePath      WRITE setDefaultSavePath      NOTIFY defaultSavePathChanged)
    Q_PROPERTY(QString temporaryDirectory   READ temporaryDirectory   WRITE setTemporaryDirectory   NOTIFY temporaryDirectoryChanged)
    Q_PROPERTY(QString torrentCustomSavePath READ torrentCustomSavePath WRITE setTorrentCustomSavePath NOTIFY torrentCustomSavePathChanged)
    Q_PROPERTY(bool torrentUseCustomSavePathByDefault READ torrentUseCustomSavePathByDefault WRITE setTorrentUseCustomSavePathByDefault NOTIFY torrentCustomSavePathByDefaultChanged)
    Q_PROPERTY(QStringList monitoredExtensions READ monitoredExtensions WRITE setMonitoredExtensions NOTIFY monitoredExtensionsChanged)
    Q_PROPERTY(QStringList excludedSites      READ excludedSites       WRITE setExcludedSites       NOTIFY excludedSitesChanged)
    Q_PROPERTY(QStringList excludedAddresses  READ excludedAddresses   WRITE setExcludedAddresses   NOTIFY excludedAddressesChanged)
    Q_PROPERTY(bool swarmMapShowInactive READ swarmMapShowInactive WRITE setSwarmMapShowInactive NOTIFY swarmMapShowInactiveChanged)
    Q_PROPERTY(bool swarmMapShowTrackers READ swarmMapShowTrackers WRITE setSwarmMapShowTrackers NOTIFY swarmMapShowTrackersChanged)
    Q_PROPERTY(bool showSwarmMapWhileFetchingMetadata READ showSwarmMapWhileFetchingMetadata WRITE setShowSwarmMapWhileFetchingMetadata NOTIFY showSwarmMapWhileFetchingMetadataChanged)
    Q_PROPERTY(QString customUserAgent READ customUserAgent WRITE setCustomUserAgent NOTIFY customUserAgentChanged)
    Q_PROPERTY(QStringList sidebarOrder READ sidebarOrder WRITE setSidebarOrder NOTIFY sidebarOrderChanged)
    Q_PROPERTY(QStringList torrentSubcatOrder READ torrentSubcatOrder WRITE setTorrentSubcatOrder NOTIFY torrentSubcatOrderChanged)
    Q_PROPERTY(bool launchOnStartup READ launchOnStartup WRITE setLaunchOnStartup NOTIFY launchOnStartupChanged)
    Q_PROPERTY(bool torrentEnabled   READ torrentEnabled   WRITE setTorrentEnabled   NOTIFY torrentEnabledChanged)
    Q_PROPERTY(QString rssSmartFiltersJson  READ rssSmartFiltersJson  WRITE setRssSmartFiltersJson  NOTIFY rssSmartFiltersJsonChanged)
    Q_PROPERTY(QString rssDownloadRulesJson READ rssDownloadRulesJson WRITE setRssDownloadRulesJson NOTIFY rssDownloadRulesJsonChanged)
    Q_PROPERTY(QString proxyUsername READ proxyUsername WRITE setProxyUsername NOTIFY proxyUsernameChanged)
    Q_PROPERTY(QString proxyPassword READ proxyPassword WRITE setProxyPassword NOTIFY proxyPasswordChanged)

public:
    explicit AppSettings(QObject *parent = nullptr);

    static QStringList defaultMonitoredExtensions();
    static QStringList defaultExcludedSites();
    static QStringList defaultExcludedAddresses();

    // ========================================================================
    // Generated getters
    // ========================================================================
#define X(ptype, sp, mem, camel, def, key, flags) ptype mem() const { return m_##mem; }
    APP_SETTINGS(X)
#undef X

    // --- Manual getters ---
    QString defaultSavePath()      const { return m_defaultSavePath; }
    QString temporaryDirectory()   const { return m_temporaryDirectory; }
    QString torrentCustomSavePath() const { return m_torrentCustomSavePath; }
    bool torrentUseCustomSavePathByDefault() const { return m_torrentUseCustomSavePathByDefault; }
    QStringList monitoredExtensions() const { return m_monitoredExtensions; }
    QStringList excludedSites()       const { return m_excludedSites; }
    QStringList excludedAddresses()   const { return m_excludedAddresses; }
    bool        swarmMapShowInactive() const { return m_swarmMapShowInactive; }
    bool        swarmMapShowTrackers() const { return m_swarmMapShowTrackers; }
    bool        showSwarmMapWhileFetchingMetadata() const { return m_showSwarmMapWhileFetchingMetadata; }
    QString customUserAgent()     const { return m_customUserAgent; }
    QStringList sidebarOrder()         const { return m_sidebarOrder; }
    QStringList torrentSubcatOrder()   const { return m_torrentSubcatOrder; }
    bool launchOnStartup()            const { return m_launchOnStartup; }
    bool torrentEnabled()           const { return m_torrentEnabled; }
    QString rssSmartFiltersJson()     const { return m_rssSmartFiltersJson; }
    QString rssDownloadRulesJson()    const { return m_rssDownloadRulesJson; }
    QString proxyUsername()           const { return m_proxyUsername; }
    QString proxyPassword()           const { return m_proxyPassword; }
    qint64 torrentHistoricalUploadedBytes() const { return m_torrentHistoricalUploadedBytes; }
    qint64 torrentHistoricalDownloadedBytes() const { return m_torrentHistoricalDownloadedBytes; }
    QDate installDate() const { return m_installDate; }
    qint64 totalUptimeSecs() const { return m_totalUptimeSecs; }
    int totalStartups() const { return m_totalStartups; }
    QString motdDismissedHash() const { return m_motdDismissedHash; }
    qint64 motdDismissedUntilUtcMs() const { return m_motdDismissedUntilUtcMs; }

    // ========================================================================
    // Generated setter declarations
    // ========================================================================
#define X(ptype, sp, mem, camel, def, key, flags) void set##camel(sp v);
    APP_SETTINGS(X)
#undef X

    // --- Manual setter declarations ---
    void setDefaultSavePath(const QString &v);
    void setTemporaryDirectory(const QString &v);
    void setTorrentCustomSavePath(const QString &v);
    void setTorrentUseCustomSavePathByDefault(bool v);
    void setMonitoredExtensions(const QStringList &v);
    void setExcludedSites(const QStringList &v);
    void setExcludedAddresses(const QStringList &v);
    void setSwarmMapShowInactive(bool v);
    void setSwarmMapShowTrackers(bool v);
    void setShowSwarmMapWhileFetchingMetadata(bool v);
    void setCustomUserAgent(const QString &v);
    void setSidebarOrder(const QStringList &v);
    void setTorrentSubcatOrder(const QStringList &v);
    void setLaunchOnStartup(bool v);
    void setTorrentEnabled(bool v);
    void setRssSmartFiltersJson(const QString &v);
    void setRssDownloadRulesJson(const QString &v);
    void setProxyUsername(const QString &v);
    void setProxyPassword(const QString &v);
    void setMotdDismissal(const QString &hash, qint64 untilUtcMs);
    void clearMotdDismissal();

    void accumulateTorrentStats(qint64 uploadedBytes, qint64 downloadedBytes);
    void resetTorrentHistoricalStats();
    void accumulateUptimeSecs(qint64 secs);

    Q_INVOKABLE void save();
    Q_INVOKABLE void load();

signals:
    // ========================================================================
    // Generated signals (N + S flags only; T shares manual torrentSettingsChanged)
    // ========================================================================
#define SIG_N(ptype, sp, mem, camel, def, key) void mem##Changed();
#define SIG_T(ptype, sp, mem, camel, def, key) /* covered by manual torrentSettingsChanged */
#define SIG_S(ptype, sp, mem, camel, def, key) void mem##Changed();
#define SIG(ptype, sp, mem, camel, def, key, flags) SIG_##flags(ptype, sp, mem, camel, def, key)
#define X(ptype, sp, mem, camel, def, key, flags) SIG(ptype, sp, mem, camel, def, key, flags)
    APP_SETTINGS(X)
#undef X
#undef SIG
#undef SIG_S
#undef SIG_T
#undef SIG_N

    // --- Manual signals ---
    void defaultSavePathChanged();
    void temporaryDirectoryChanged();
    void torrentEnabledChanged();
    void torrentCustomSavePathChanged();
    void torrentCustomSavePathByDefaultChanged();
    void monitoredExtensionsChanged();
    void excludedSitesChanged();
    void excludedAddressesChanged();
    void swarmMapShowInactiveChanged();
    void swarmMapShowTrackersChanged();
    void showSwarmMapWhileFetchingMetadataChanged();
    void customUserAgentChanged();
    void sidebarOrderChanged();
    void torrentSubcatOrderChanged();
    void launchOnStartupChanged();
    void rssSmartFiltersJsonChanged();
    void rssDownloadRulesJsonChanged();
    void proxyUsernameChanged();
    void proxyPasswordChanged();
    void torrentSettingsChanged();

private:
    // ========================================================================
    // Generated members
    // ========================================================================
#define X(ptype, sp, mem, camel, def, key, flags) ptype m_##mem{def};
    APP_SETTINGS(X)
#undef X

    // --- Manual members ---
    QString m_defaultSavePath;
    QString m_temporaryDirectory;
    QString m_torrentCustomSavePath;
    bool    m_torrentUseCustomSavePathByDefault{false};
    QStringList m_monitoredExtensions;
    QStringList m_excludedSites;
    QStringList m_excludedAddresses;
    bool        m_swarmMapShowInactive{true};
    bool        m_swarmMapShowTrackers{true};
    bool        m_showSwarmMapWhileFetchingMetadata{true};
    QString     m_customUserAgent;
    QStringList m_sidebarOrder{{"downloads", "unfinished", "finished", "grabber", "queues", "torrents"}};
    QStringList m_torrentSubcatOrder{{"torrent_downloading", "torrent_seeding", "torrent_stopped",
                                      "torrent_active", "torrent_inactive", "torrent_checking", "torrent_moving"}};
    bool        m_launchOnStartup{false};
    bool        m_torrentEnabled{false};
    QString     m_rssSmartFiltersJson{QStringLiteral("[\"s(\\\\d+)e(\\\\d+)\",\"(\\\\d+)x(\\\\d+)\",\"(\\\\d{4}[.\\\\-]\\\\d{1,2}[.\\\\-]\\\\d{1,2})\",\"(\\\\d{1,2}[.\\\\-]\\\\d{1,2}[.\\\\-]\\\\d{4})\"]")};
    QString     m_rssDownloadRulesJson{QStringLiteral("[]")};
    // All-time torrent transfer accumulators
    qint64      m_torrentHistoricalUploadedBytes{0};
    qint64      m_torrentHistoricalDownloadedBytes{0};
    // First-run date (recorded once and never overwritten)
    QDate       m_installDate;
    // Total cumulative app uptime in seconds
    qint64      m_totalUptimeSecs{0};
    // Incremented on every load() call (each app launch)
    int         m_totalStartups{0};
    // Proxy credentials stored obfuscated
    QString     m_proxyUsername;
    QString     m_proxyPassword;
    // MOTD dismissal
    QString     m_motdDismissedHash;
    qint64      m_motdDismissedUntilUtcMs{0};

    // Apply or remove OS startup entry depending on v
    void applyStartupRegistration(bool v) const;
    void scheduleSave();

    QSettings m_settings;
    QTimer    m_saveTimer;
};
