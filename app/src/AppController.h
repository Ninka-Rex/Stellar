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
#include <QtQml/QJSValue>
#include <QNetworkAccessManager>
#include <QLocalServer>
#include <QLocalSocket>
#include <QTimer>
#include <QSet>
#include <QMap>
#include <QVariantMap>
#include <QVariantList>
#include <QDateTime>
#include <QElapsedTimer>
#include <functional>

#include "DownloadQueue.h"
#include "DownloadTableModel.h"
#include "CategoryModel.h"
#include "NativeMessagingHost.h"
#include "AppSettings.h"
#include "SystemTrayIcon.h"
#include "DownloadDatabase.h"
#include "GrabberCrawler.h"
#include "GrabberProjectModel.h"
#include "GrabberResultModel.h"
#include "QueueDatabase.h"
#include "QueueModel.h"
#include "RssManager.h"
#include "TorrentSearchManager.h"
#include "YtdlpManager.h"
#include "YtdlpTransfer.h"
#include "TorrentSessionManager.h"

class AppController : public QObject {
    Q_OBJECT
    Q_PROPERTY(DownloadTableModel *downloadModel READ downloadModel CONSTANT)
    Q_PROPERTY(CategoryModel      *categoryModel READ categoryModel CONSTANT)
    Q_PROPERTY(GrabberProjectModel *grabberProjectModel READ grabberProjectModel CONSTANT)
    Q_PROPERTY(GrabberResultModel *grabberResultModel READ grabberResultModel CONSTANT)
    Q_PROPERTY(class QueueModel   *queueModel    READ queueModel    CONSTANT)
    Q_PROPERTY(AppSettings        *settings      READ settings      CONSTANT)
    Q_PROPERTY(int     activeDownloads    READ activeDownloads    NOTIFY activeDownloadsChanged)
    Q_PROPERTY(qint64  totalDownSpeed     READ totalDownSpeed     NOTIFY totalSpeedChanged)
    Q_PROPERTY(qint64  totalUpSpeed       READ totalUpSpeed       NOTIFY totalSpeedChanged)
    Q_PROPERTY(int     seedingCount       READ seedingCount       NOTIFY seedingCountChanged)
    Q_PROPERTY(QString selectedCategory  READ selectedCategory   WRITE setSelectedCategory NOTIFY selectedCategoryChanged)
    Q_PROPERTY(QString selectedQueue     READ selectedQueue      WRITE setSelectedQueue    NOTIFY selectedQueueChanged)
    Q_PROPERTY(QString appVersion   READ appVersion   CONSTANT)
    Q_PROPERTY(QString buildTime    READ buildTime    CONSTANT)
    Q_PROPERTY(QString buildTimeFormatted READ buildTimeFormatted CONSTANT)
    Q_PROPERTY(QString qtVersion    READ qtVersion    CONSTANT)
    Q_PROPERTY(bool grabberBusy READ grabberBusy NOTIFY grabberBusyChanged)
    Q_PROPERTY(QString grabberStatusText READ grabberStatusText NOTIFY grabberStatusTextChanged)
    Q_PROPERTY(int minutesUntilNextQueue READ minutesUntilNextQueue NOTIFY minutesUntilNextQueueChanged)
    Q_PROPERTY(int completedDownloads READ completedDownloads NOTIFY completedDownloadsChanged)
    Q_PROPERTY(int recentErrorDownloads READ recentErrorDownloads NOTIFY recentErrorDownloadsChanged)
    Q_PROPERTY(bool updateAvailable READ updateAvailable NOTIFY updateAvailableChanged)
    Q_PROPERTY(QString updateVersion READ updateVersion NOTIFY updateAvailableChanged)
    Q_PROPERTY(QString updateChangelog READ updateChangelog NOTIFY updateAvailableChanged)
    Q_PROPERTY(QString updateStatusText READ updateStatusText NOTIFY updateStatusTextChanged)
    Q_PROPERTY(bool checkingForUpdates READ checkingForUpdates NOTIFY checkingForUpdatesChanged)
    Q_PROPERTY(QString torrentBindingStatusText READ torrentBindingStatusText NOTIFY torrentBindingStatusTextChanged)
    Q_PROPERTY(bool torrentPortTestInProgress READ torrentPortTestInProgress NOTIFY torrentPortTestChanged)
    Q_PROPERTY(QString torrentPortTestStatus READ torrentPortTestStatus NOTIFY torrentPortTestChanged)
    Q_PROPERTY(QString torrentPortTestMessage READ torrentPortTestMessage NOTIFY torrentPortTestChanged)
    Q_PROPERTY(QVariantMap ipToCityDbInfo READ ipToCityDbInfo NOTIFY ipToCityDbInfoChanged)
    Q_PROPERTY(QString ipToCityDbUpdateUrl READ ipToCityDbUpdateUrl NOTIFY ipToCityDbUpdateUrlChanged)
    Q_PROPERTY(bool ipToCityDbUpdating READ ipToCityDbUpdating NOTIFY ipToCityDbUpdateStateChanged)
    Q_PROPERTY(QString ipToCityDbUpdateStatus READ ipToCityDbUpdateStatus NOTIFY ipToCityDbUpdateStateChanged)
    Q_PROPERTY(bool ffmpegUpdating READ ffmpegUpdating NOTIFY ffmpegUpdateStateChanged)
    Q_PROPERTY(QString ffmpegUpdateStatus READ ffmpegUpdateStatus NOTIFY ffmpegUpdateStateChanged)
    // yt-dlp integration — exposes YtdlpManager to QML for binary status/download UI
    Q_PROPERTY(YtdlpManager *ytdlpManager READ ytdlpManager CONSTANT)
    Q_PROPERTY(TorrentSearchManager *torrentSearchManager READ torrentSearchManager CONSTANT)
    Q_PROPERTY(RssManager *rssManager READ rssManager CONSTANT)
    // True when a custom proxy (HTTP or SOCKS5) is currently active
    Q_PROPERTY(bool proxyActive READ proxyActive NOTIFY proxyActiveChanged)
    Q_PROPERTY(bool ytdlpBatchActive READ ytdlpBatchActive NOTIFY ytdlpBatchChanged)
    Q_PROPERTY(bool ytdlpBatchCanResume READ ytdlpBatchCanResume NOTIFY ytdlpBatchChanged)
    Q_PROPERTY(QString ytdlpBatchLabel READ ytdlpBatchLabel NOTIFY ytdlpBatchChanged)
    Q_PROPERTY(QVariantList ytdlpBatchItems READ ytdlpBatchItems NOTIFY ytdlpBatchChanged)
    Q_PROPERTY(QVariantList torrentBannedPeers READ torrentBannedPeers NOTIFY torrentBannedPeersChanged)

public:
    explicit AppController(QObject *parent = nullptr);
    ~AppController();

    DownloadTableModel *downloadModel() const { return m_downloadModel; }
    CategoryModel      *categoryModel() const { return m_categoryModel; }
    GrabberProjectModel *grabberProjectModel() const { return m_grabberProjectModel; }
    GrabberResultModel *grabberResultModel() const { return m_grabberResultModel; }
    class QueueModel   *queueModel()    const { return m_queueModel; }
    AppSettings        *settings()      const { return m_settings; }
    int    activeDownloads() const;
    qint64 totalDownSpeed()  const { return m_totalDownSpeed; }
    qint64 totalUpSpeed()    const { return m_totalUpSpeed; }
    int    seedingCount()    const { return m_seedingCount; }
    QString selectedCategory() const { return m_selectedCategory; }
    QString selectedQueue() const    { return m_selectedQueue; }
    void setSelectedCategory(const QString &v);
    void setSelectedQueue(const QString &v);
    QString appVersion() const;
    QString buildTime() const;
    QString buildTimeFormatted() const;
    QString qtVersion() const;
    bool grabberBusy() const { return m_grabberBusy; }
    QString grabberStatusText() const { return m_grabberStatusText; }
    int minutesUntilNextQueue() const;
    int completedDownloads() const { return m_completedCount; }
    int recentErrorDownloads() const;
    bool updateAvailable() const { return m_updateAvailable; }
    QString updateVersion() const { return m_updateVersion; }
    QString updateChangelog() const { return m_updateChangelog; }
    QString updateStatusText() const { return m_updateStatusText; }
    bool checkingForUpdates() const { return m_checkingForUpdates; }
    QString torrentBindingStatusText() const;
    bool torrentPortTestInProgress() const { return m_torrentPortTestInProgress; }
    QString torrentPortTestStatus() const { return m_torrentPortTestStatus; }
    QString torrentPortTestMessage() const { return m_torrentPortTestMessage; }
    QVariantMap ipToCityDbInfo() const { return m_ipToCityDbInfo; }
    QString ipToCityDbUpdateUrl() const { return m_ipToCityDbUpdateUrl; }
    bool ipToCityDbUpdating() const { return m_ipToCityDbUpdating; }
    QString ipToCityDbUpdateStatus() const { return m_ipToCityDbUpdateStatus; }
    bool ffmpegUpdating() const { return m_ffmpegUpdating; }
    QString ffmpegUpdateStatus() const { return m_ffmpegUpdateStatus; }
    YtdlpManager *ytdlpManager() const { return m_ytdlpManager; }
    TorrentSearchManager *torrentSearchManager() const { return m_torrentSearchManager; }
    RssManager *rssManager() const { return m_rssManager; }
    bool proxyActive() const { return m_proxyActive; }
    bool ytdlpBatchActive() const { return !m_activeYtdlpBatchId.isEmpty(); }
    bool ytdlpBatchCanResume() const { return !m_lastYtdlpBatchId.isEmpty(); }
    QString ytdlpBatchLabel() const { return m_activeYtdlpBatchLabel; }
    QVariantList ytdlpBatchItems() const { return m_activeYtdlpBatchItems; }
    QVariantList torrentBannedPeers() const;

    // ── yt-dlp public API ────────────────────────────────────────────────────────
    // Returns true if the URL looks like a site supported by yt-dlp (YouTube, Vimeo, etc.)
    // Set the icon of a QML Window (QQuickWindow) from a QRC resource path.
    // Called from QML as App.setWindowIcon(root, ":/path/to/icon.ico").
    Q_INVOKABLE void setWindowIcon(QObject *window, const QString &iconPath);

    // Dispatch a raw IPC JSON payload (same object the IPC socket receives).
    // If QML is not yet ready the payload is buffered and replayed on setQmlReady().
    void handleIpcPayload(const QByteArray &json);

    // Called from QML's root Component.onCompleted once all signal Connections
    // are wired.  Drains any IPC payloads that arrived before QML was ready.
    Q_INVOKABLE void setQmlReady();

    Q_INVOKABLE bool isLikelyYtdlpUrl(const QString &url) const;

    // Asynchronously probe the URL with "yt-dlp --dump-json".
    // Emits ytdlpInfoReady(formats) on success or ytdlpInfoFailed(reason) on error.
    // Returns a probe ID so callers can match response signals to requests.
    Q_INVOKABLE QString beginYtdlpInfo(const QString &url, const QString &cookiesBrowser = {});

    // Cancel a running --dump-json probe (identified by probeId from beginYtdlpInfo).
    Q_INVOKABLE void cancelYtdlpInfo(const QString &probeId);

    // One-stop create + start for yt-dlp downloads.
    // Creates a new DownloadItem from `url`, configures it with the chosen format
    // and save directory, then immediately starts the transfer.  The item only
    // appears in the download list once this is called (not before the user
    // confirms the format in YtdlpDialog), so there is never a "Watch" ghost entry.
    Q_INVOKABLE void finalizeYtdlpDownload(const QString &url,
                                           const QString &saveDir,
                                           const QString &category,
                                           const QString &formatId,
                                           const QString &containerFormat,
                                           bool uniqueFilename = false,
                                           const QString &videoTitle = {},
                                           bool playlistMode = false,
                                           int  maxItems = 0,
                                           const QVariantMap &extraOptions = {});

    // Start a yt-dlp download.  Item must already be in the queue as a held item
    // (enqueueHeld) so it appears in the UI.  formatId is a yt-dlp format selector.
    Q_INVOKABLE void startYtdlpDownload(const QString &downloadId, const QString &formatId,
                                        const QString &containerFormat = {});

    // Download the yt-dlp binary (delegates to YtdlpManager).
    Q_INVOKABLE void downloadYtdlpBinary();
    Q_INVOKABLE void stopActiveYtdlpBatch();
    Q_INVOKABLE void resumeLastYtdlpBatch();
    Q_INVOKABLE bool retryYtdlpWithBrowserCookies(const QString &downloadId, const QString &browser);
    Q_INVOKABLE bool isTorrentUri(const QString &value) const;
    Q_INVOKABLE QObject *downloadById(const QString &id) const;
    Q_INVOKABLE QObject *torrentFileModel(const QString &id) const;
    Q_INVOKABLE QObject *torrentPeerModel(const QString &id) const;
    Q_INVOKABLE QObject *torrentTrackerModel(const QString &id) const;
    Q_INVOKABLE QVariantList torrentCountryOptions() const;
    Q_INVOKABLE QVariantList torrentNetworkAdapters() const;
    Q_INVOKABLE bool banTorrentPeer(const QString &downloadId, const QString &endpoint, int port,
                                    const QString &client = {}, const QString &countryCode = {});
    Q_INVOKABLE bool unbanTorrentPeer(const QString &endpoint);
    Q_INVOKABLE void testTorrentPort();
    Q_INVOKABLE void refreshIpToCityDbInfo();
    Q_INVOKABLE void updateIpToCityDbFromCachedUrl();
    Q_INVOKABLE void updateFfmpegBinary();
    Q_INVOKABLE bool setTorrentFileWanted(const QString &downloadId, int row, bool wanted);
    Q_INVOKABLE bool setTorrentFileWantedByIndex(const QString &downloadId, int fileIndex, bool wanted);
    Q_INVOKABLE bool setTorrentFileWantedByPath(const QString &downloadId, const QString &path, bool wanted);
    Q_INVOKABLE bool addTorrentTracker(const QString &downloadId, const QString &url);
    Q_INVOKABLE bool removeTorrentTracker(const QString &downloadId, const QString &url);
    Q_INVOKABLE bool renameTorrentFile(const QString &downloadId, int fileIndex, const QString &newName);
    Q_INVOKABLE bool renameTorrentPath(const QString &downloadId, const QString &currentPath, const QString &newName);
    Q_INVOKABLE void setTorrentFlags(const QString &downloadId, bool disableDht, bool disablePex, bool disableLsd = false);
    Q_INVOKABLE QString addMagnetLink(const QString &uri, const QString &savePath = {},
                                      const QString &category = {}, const QString &description = {},
                                      bool startNow = true, const QString &queueId = {});
    Q_INVOKABLE QString addTorrentFile(const QString &filePath, const QString &savePath = {},
                                       const QString &category = {}, const QString &description = {},
                                       bool startNow = true, const QString &queueId = {});
    Q_INVOKABLE QString beginTorrentMetadataDownload(const QString &source, const QString &savePath = {},
                                                     const QString &category = {}, const QString &description = {},
                                                     bool startWhenReady = true);
    void silentlyAddTorrent(const QString &source, const QString &savePath = {},
                            const QString &category = {}, const QString &description = {},
                            const QString &queueId = {});
    Q_INVOKABLE bool confirmTorrentDownload(const QString &downloadId, const QString &savePath = {},
                                            const QString &category = {}, const QString &description = {},
                                            bool startNow = true, const QString &queueId = {});
    Q_INVOKABLE void discardTorrentDownload(const QString &downloadId);

    Q_INVOKABLE void checkUrl(const QString &url, QJSValue callback);
    Q_INVOKABLE void addUrl(const QString &url, const QString &savePath = {},
                            const QString &category = {}, const QString &description = {},
                            bool startNow = true, const QString &cookies = {},
                            const QString &referrer = {}, const QString &parentUrl = {},
                            const QString &username = {}, const QString &password = {},
                            const QString &filenameOverride = {}, const QString &queueId = {});
    Q_INVOKABLE QString beginPendingDownload(const QString &url,
                                             const QString &filenameOverride = {},
                                             const QString &cookies = {},
                                             const QString &referrer = {},
                                             const QString &parentUrl = {},
                                             const QString &username = {},
                                             const QString &password = {});
    Q_INVOKABLE bool finalizePendingDownload(const QString &downloadId,
                                             const QString &fullSavePath,
                                             const QString &category,
                                             const QString &description,
                                             bool startNow,
                                             const QString &queueId = {});
    Q_INVOKABLE void discardPendingDownload(const QString &downloadId);
    Q_INVOKABLE void deleteAllCompleted(int mode = 0, bool includeSeedingTorrents = false);
    Q_INVOKABLE void deleteDownloads(const QStringList &ids, int mode = 0);
    Q_INVOKABLE void pauseAllDownloads();
    Q_INVOKABLE void sortDownloads(const QString &column, bool ascending);
    Q_INVOKABLE void pauseDownload(const QString &id);
    Q_INVOKABLE void resumeDownload(const QString &id);
    Q_INVOKABLE void deleteDownload(const QString &id, int mode = 0);
    Q_INVOKABLE void openFile(const QString &id);
    Q_INVOKABLE void openFolder(const QString &id);
    Q_INVOKABLE void openFolderSelectFile(const QString &id);
    Q_INVOKABLE void moveFileToDesktop(const QString &id);
    Q_INVOKABLE void copyDownloadFilename(const QString &id);
    Q_INVOKABLE QString downloadShareLink(const QString &id) const;
    Q_INVOKABLE bool exportTorrentFilesToDirectory(const QStringList &downloadIds, const QString &directoryPath);
    Q_INVOKABLE QString      torrentCurrentRootName(const QString &downloadId) const;
    Q_INVOKABLE QVariantList torrentSpeedHistory(const QString &downloadId, int maxAgeSeconds = 0, int maxPoints = 0) const;
    Q_INVOKABLE QVariantList torrentPieceMap(const QString &downloadId) const;
    Q_INVOKABLE void clearTorrentSpeedHistory(const QString &downloadId);
    Q_INVOKABLE QVariantMap torrentAllTimeStats() const;
    Q_INVOKABLE void resetTorrentAllTimeStats();
    Q_INVOKABLE QString clipboardUrl() const;
    Q_INVOKABLE void setDownloadCategory(const QString &downloadId, const QString &categoryId);
    Q_INVOKABLE void setDownloadQueue(const QString &downloadId, const QString &queueId);
    Q_INVOKABLE QStringList queueIds() const;
    Q_INVOKABLE QStringList queueNames() const;
    Q_INVOKABLE void moveUpInQueue(const QString &downloadId);
    Q_INVOKABLE void moveDownInQueue(const QString &downloadId);
    Q_INVOKABLE QObject *findDuplicateUrl(const QString &url) const;
    Q_INVOKABLE QString  generateNumberedFilename(const QString &filename) const;
    Q_INVOKABLE bool     fileExists(const QString &path) const;
    Q_INVOKABLE QString  normalizeTorrentSaveDirectory(const QString &path) const;
    Q_INVOKABLE void     copyToClipboard(const QString &text) const;
    Q_INVOKABLE void     openExtensionFolder() const;
    Q_INVOKABLE void     addExcludedAddress(const QString &pattern);
    Q_INVOKABLE void     notifyInterceptRejected(const QString &url);
    Q_INVOKABLE void     setDownloadSpeedLimit(const QString &downloadId, int kbps);
    Q_INVOKABLE void setTorrentSpeedLimits(const QString &downloadId, int downKBps, int upKBps);
    Q_INVOKABLE void setTorrentShareLimits(const QString &downloadId, double ratio, int seedTimeMins, int inactiveTimeMins, int action);
    Q_INVOKABLE void forceRecheckTorrent(const QString &downloadId);
    Q_INVOKABLE void forceReannounceTorrent(const QString &downloadId, const QStringList &trackerUrls = {});
    Q_INVOKABLE void     setDownloadFilename(const QString &downloadId, const QString &filename);
    Q_INVOKABLE void     setDownloadUsername(const QString &downloadId, const QString &username);
    Q_INVOKABLE void     setDownloadPassword(const QString &downloadId, const QString &password);
    Q_INVOKABLE void     setDownloadDescription(const QString &downloadId, const QString &description);
    Q_INVOKABLE bool     moveDownloadFile(const QString &downloadId, const QString &newFilePath);
    Q_INVOKABLE void     enableSpeedLimiter();
    Q_INVOKABLE void     disableSpeedLimiter();
    Q_INVOKABLE void     redownload(const QString &id);
    Q_INVOKABLE void    setPendingCookies(const QString &url, const QString &cookies);
    Q_INVOKABLE QString takePendingCookies(const QString &url);
    Q_INVOKABLE QString takePendingReferrer(const QString &url);
    Q_INVOKABLE QString takePendingPageUrl(const QString &url);
    Q_INVOKABLE QString  registerNativeHost() const;
    Q_INVOKABLE QString  nativeHostManifestPath() const;
    Q_INVOKABLE QString  nativeHostDiagnostics() const;
    Q_INVOKABLE void createQueue(const QString &name);
    Q_INVOKABLE void deleteQueue(const QString &queueId);
    Q_INVOKABLE void saveQueues();
    Q_INVOKABLE void startQueue(const QString &queueId);
    Q_INVOKABLE void stopQueue(const QString &queueId);
    Q_INVOKABLE bool shutdownComputer() const;
    Q_INVOKABLE void setTrayTooltip(const QString &tip);
    Q_INVOKABLE QVariantMap grabberProjectData(const QString &projectId) const;
    Q_INVOKABLE bool isGrabberProjectId(const QString &projectId) const;
    Q_INVOKABLE QString saveGrabberProject(const QVariantMap &projectMap);
    Q_INVOKABLE void deleteGrabberProject(const QString &projectId);
    Q_INVOKABLE void runGrabber(const QVariantMap &projectMap);
    Q_INVOKABLE void cancelGrabber();
    Q_INVOKABLE void setGrabberResultChecked(int row, bool checked);
    Q_INVOKABLE void setAllGrabberResultsChecked(bool checked);
    Q_INVOKABLE int checkedGrabberResultCount() const;
    Q_INVOKABLE void sortGrabberResults(const QString &column, bool ascending);
    Q_INVOKABLE void loadGrabberProjectResults(const QString &projectId);
    Q_INVOKABLE void downloadGrabberResults(const QString &projectId, bool startNow, const QString &queueId = {});
    Q_INVOKABLE void stopGrabberResultDownloads(const QString &projectId);
    Q_INVOKABLE QVariantMap grabberStatistics(const QString &projectId) const;
    Q_INVOKABLE void saveGrabberProjectSchedule(const QString &projectId, const QVariantMap &scheduleMap);
    Q_INVOKABLE QString readTextResource(const QString &path) const;
    Q_INVOKABLE void checkForUpdates(bool manual = false);
    Q_INVOKABLE void testProxy();
    Q_INVOKABLE void fetchChangelog();
    Q_INVOKABLE void dismissAvailableUpdate();
    Q_INVOKABLE bool startUpdateInstall();

signals:
    void activeDownloadsChanged();
    void totalSpeedChanged();
    void seedingCountChanged();
    void selectedCategoryChanged();
    void selectedQueueChanged();
    void errorOccurred(const QString &message);
    void showWindowRequested();
    void torrentMetadataRequested(const QString &downloadId, bool startWhenReady);
    void downloadAdded(QObject *item);
    void downloadCompleted(QObject *item);
    void trayGithubRequested();
    void trayAboutRequested();
    void traySpeedLimiterRequested();
    void contextMenuRequested(int x, int y);
    void exceptionDialogRequested(const QString &url);
    void interceptedDownloadRequested(const QString &url, const QString &filename);
    void grabberBusyChanged();
    void grabberStatusTextChanged();
    void grabberExploreFinished(const QString &projectId);
    void grabberError(const QString &message);
    void minutesUntilNextQueueChanged();
    void completedDownloadsChanged();
    void recentErrorDownloadsChanged();
    void updateAvailableChanged();
    void updateStatusTextChanged();
    void checkingForUpdatesChanged();
    void updateDialogRequested();
    void updateUpToDate();
    void updateError(const QString &message);
    void ipToCityDbInfoChanged();
    void ipToCityDbUpdateUrlChanged();
    void ipToCityDbUpdateStateChanged();
    void ffmpegUpdateStateChanged();
    void proxyActiveChanged();
    // success=true means GitHub was reachable; message holds latency or error text
    void proxyTestResult(bool success, const QString &message);
    void ytdlpBatchChanged();
    void torrentBindingStatusTextChanged();
    void torrentPortTestChanged();
    // Emitted when clipboard monitoring is on and a matching URL is detected.
    // url is the full URL string; the QML side shows the Add URL dialog.
    void clipboardUrlDetected(const QString &url);

    // ── yt-dlp signals ───────────────────────────────────────────────────────────
    // Emitted when a --dump-json probe completes successfully.
    // probeId matches the return value from beginYtdlpInfo().
    // title is the video title; formats is a list of QVariantMaps:
    //   { "id": string, "label": string, "ext": string,
    //     "width": int, "height": int, "tbr": double, "vcodec": string,
    //     "acodec": string, "filesize": qint64 }
    void ytdlpInfoReady(const QString &probeId, const QString &url,
                        const QString &title, const QVariantList &formats);
    // Emitted when a --dump-json probe fails or yt-dlp is not available.
    void ytdlpInfoFailed(const QString &probeId, const QString &url, const QString &reason);
    // Emitted when a clipboard URL looks like a yt-dlp site (no file extension needed).
    void ytdlpClipboardUrlDetected(const QString &url);
    void ytdlpCookieRetryRequested(const QString &downloadId, const QString &reason,
                                   const QString &suggestedBrowser);
    void torrentBannedPeersChanged();

private:
    QString generateId() const;
    DownloadQueue          *m_queue{nullptr};
    DownloadTableModel     *m_downloadModel{nullptr};
    CategoryModel          *m_categoryModel{nullptr};
    GrabberProjectModel    *m_grabberProjectModel{nullptr};
    GrabberResultModel     *m_grabberResultModel{nullptr};
    GrabberCrawler         *m_grabberCrawler{nullptr};
    NativeMessagingHost    *m_nativeHost{nullptr};
    QNetworkAccessManager  *m_nam{nullptr};
    AppSettings            *m_settings{nullptr};
    SystemTrayIcon         *m_tray{nullptr};
    DownloadDatabase       *m_db{nullptr};
    class QueueDatabase    *m_queueDb{nullptr};
    class QueueModel       *m_queueModel{nullptr};
    QTimer                 *m_saveTimer{nullptr};
    QTimer                 *m_torrentStatsFlushTimer{nullptr};
    QTimer                 *m_tooltipTimer{nullptr};
    qint64                  m_totalDownSpeed{0};
    qint64                  m_totalUpSpeed{0};
    int                     m_seedingCount{0};
    QString                 m_lastTrayTooltip;
    QLocalServer           *m_ipcServer{nullptr};
    bool                    m_qmlReady{false};
    QList<QByteArray>       m_pendingIpcPayloads; // buffered until QML is ready
    QSet<QString>           m_dirtyIds;
    QMap<QString, int>      m_cancelCounts;
    QMap<QString, int>      m_interceptRejectCounts;
    QMap<QString, qint64>    m_lastProgressPersistBytes;
    QMap<QString, QDateTime> m_lastProgressPersistAt;
    // Throttle state for torrent upload/download counters (see watchItem).
    // Saves only when counters move ≥ 1 MB or 60 s have elapsed.
    QMap<QString, qint64>    m_lastTorrentPersistUploaded;
    QMap<QString, qint64>    m_lastTorrentPersistDownloaded;
    bool                    m_restoring{false};
    // IDs of torrents that were already seeding/complete when restored from the
    // database. Completion alerts for these IDs are suppressed — they are not
    // new downloads finishing, just libtorrent re-emitting state on reconnect.
    QSet<QString>           m_restoredSeedingIds;
    QMap<QString, QString>  m_pendingCookies;
    QMap<QString, QString>  m_pendingReferrers;
    QMap<QString, QString>  m_pendingPageUrls;
    QString                 m_selectedCategory{QStringLiteral("all")};
    QString                 m_selectedQueue;
    bool                    m_grabberBusy{false};
    QString                 m_grabberStatusText;
    QString                 m_activeGrabberProjectId;
    int                     m_grabberPagesProcessed{0};
    int                     m_grabberAdvancedPagesProcessed{0};
    int                     m_grabberMatchedFiles{0};
    QSet<QString>           m_pendingFileInfoDownloads;
    QString                 m_lastClipboardUrl;  // dedup clipboard monitor signals

    void watchItem(DownloadItem *item);
    void scheduleSave(const QString &id);
    void flushDirty();
    void flushTorrentStats();
    bool canStartDownloadItem(DownloadItem *item) const;
    qint64 queueTransferredBytesInWindow(const QString &queueId, int hours) const;
    void recordQueueTransferSample(const QString &queueId, qint64 bytes);
    void pruneQueueTransferHistory(const QString &queueId, int hours) const;
    void enforceQueueDownloadLimits(const QString &queueId);
    void cleanupTemporaryDirectory();
    void checkQueueSchedules();
    int calculateMinutesUntilNextQueue() const;
    void scheduleGrabberResultsPersist();
    void persistActiveGrabberResults();
    void pruneRecentErrorDownloads();
    void setCheckingForUpdates(bool checking);
    void finishUpdateCheckUi(const std::function<void()> &finishWork);
    void setTorrentPortTestState(bool inProgress, const QString &status, const QString &message);
    void cacheIpToCityDbUpdateUrl(const QVariantMap &map);
    void cacheFfmpegUpdateMetadata(const QVariantMap &map);
    static int compareVersionStrings(const QString &lhs, const QString &rhs);
    void applyUpdateMetadata(const QVariantMap &map, bool manual);
    static QString updateMetadataUrl();
    static QString updateChangelogUrl();
    DownloadItem *createDownloadItem(const QString &url, const QString &savePath,
                                     const QString &category, const QString &description,
                                     bool startNow, const QString &cookies,
                                     const QString &referrer, const QString &parentUrl,
                                     const QString &username, const QString &password,
                                     const QString &filenameOverride, const QString &queueId,
                                     bool emitUiSignal);
    DownloadItem *createTorrentItem(const QString &source, const QString &savePath,
                                    const QString &category, const QString &description,
                                    bool startNow, const QString &queueId, bool emitUiSignal,
                                    bool staged = false);
    QString resolveGrabberSaveDirectory(const QVariantMap &project,
                                        const QUrl &url,
                                        const QString &filename,
                                        QString *resolvedCategory) const;

    QTimer                 *m_schedulerTimer{nullptr};
    QTimer                 *m_grabberPersistTimer{nullptr};
    QMap<QString, QDateTime> m_lastQueueRun;
    mutable QMap<QString, QList<QPair<QDateTime, qint64>>> m_queueTransferHistory;
    QSet<QString>           m_queueLimitNotifications;
    QMap<QString, int>      m_queueRetryCounts;
    int                     m_completedCount{0};
    QMap<QString, QDateTime> m_recentErrorDownloads;
    QTimer                 *m_recentErrorTimer{nullptr};
    bool                    m_updateAvailable{false};
    QString                 m_updateVersion;
    QString                 m_updateInstallerUrl;
    QString                 m_updateLinuxInstallerUrl;
    QString                 m_updateSha256;
    QString                 m_updateLinuxSha256;
    QString                 m_ipToCityDbUpdateUrl;
    QString                 m_ffmpegUpdateUrl;
    QString                 m_updateChangelog;
    QString                 m_updateStatusText;
    bool                    m_checkingForUpdates{false};
    bool                    m_updateCheckManual{false};
    QDateTime               m_updateCheckStartedAt;
    QString                 m_pendingUpdateDownloadId;
    QString                 m_pendingUpdateInstallerPath;
    QString                 m_pendingUpdateSha256;
    QString                 m_pendingIpToCityDbDownloadId;
    QString                 m_pendingFfmpegDownloadId;

    // ── yt-dlp ───────────────────────────────────────────────────────────────────
    YtdlpManager                    *m_ytdlpManager{nullptr};
    TorrentSearchManager           *m_torrentSearchManager{nullptr};
    RssManager                     *m_rssManager{nullptr};
    TorrentSessionManager          *m_torrentSession{nullptr};
    // Active YtdlpTransfer workers keyed by download item ID
    QMap<QString, YtdlpTransfer *>   m_ytdlpWorkers;
    QString                           m_activeYtdlpBatchId;
    QString                           m_lastYtdlpBatchId;
    QString                           m_activeYtdlpBatchLabel;
    QVariantList                      m_activeYtdlpBatchItems;
    QMap<QString, DownloadItem *>    m_pendingTorrentItems;
    QTimer                 *m_torrentSpeedHistoryTimer{nullptr};
    struct TorrentSpeedSample {
        qint64 timestampMs{0};
        int downBps{0};
        int upBps{0};
    };
    QMap<QString, QVector<TorrentSpeedSample>> m_torrentSpeedHistory;
    // Running --dump-json info probes keyed by probe ID (QUuid string)
    struct YtdlpProbe {
        QProcess  *process{nullptr};
        QString    url;
        QByteArray output;       // stdout (JSON)
        QByteArray stderrOutput; // stderr (error messages)
    };
    QMap<QString, YtdlpProbe>        m_ytdlpProbes;

    bool m_proxyActive{false};
    bool m_torrentPortTestInProgress{false};
    QString m_torrentPortTestStatus;
    QString m_torrentPortTestMessage;
    QVariantMap m_ipToCityDbInfo;
    bool m_ipToCityDbUpdating{false};
    QString m_ipToCityDbUpdateStatus;
    bool m_ffmpegUpdating{false};
    QString m_ffmpegUpdateStatus;
    QElapsedTimer m_torrentPortTestCooldown;

    // Helpers
    void applyProxy(); // reads proxy settings and applies QNetworkProxy::setApplicationProxy
    void fetchPublicIp(); // fetches external IP via ipify then geo via ipwho.is; always uses current proxy
    // formatId and containerFormat are stored together in ytdlpFormatId as
    // "<formatId>|<containerFormat>" so resume/redownload can retrieve both.
    void startYtdlpWorker(DownloadItem *item, const QString &formatId,
                          const QString &containerFormat, bool resume,
                          const QString &outputTemplate = {},
                          bool playlistMode = false, int maxItems = 0,
                          const YtdlpOptions &options = {});
    void onYtdlpWorkerFinished(const QString &id);
    void onYtdlpWorkerFailed(const QString &id, const QString &reason);
    // Returns the path to ffmpeg if found next to yt-dlp or on system PATH.
    static QString detectFfmpegPath(const QString &ytdlpBinaryPath);
    static bool ytdlpErrorSuggestsCookies(const QString &reason);
    static QString normalizeYtdlpBrowserName(const QString &browser);
    static QString preferredBrowserFromReason(const QString &reason);
};
