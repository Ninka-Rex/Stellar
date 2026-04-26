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
#include <QHash>
#include <QDateTime>
#include <QPointer>
#include <QSet>
#include <QTimer>
#include <QVariantMap>
#include <QStringList>
#include <QElapsedTimer>
#include <QByteArray>
#include <QVector>
#include <memory>

class AppSettings;
class DownloadItem;
class TorrentFileModel;
class TorrentPeerModel;
class TorrentTrackerModel;

#if defined(STELLAR_HAS_LIBTORRENT)
#include <libtorrent/torrent_handle.hpp>
#include <memory>
namespace libtorrent {
class session;
class alert;
}
#endif

class TorrentSessionManager : public QObject {
    Q_OBJECT
public:
    explicit TorrentSessionManager(QObject *parent = nullptr);
    ~TorrentSessionManager() override;

    bool available() const;
    bool isTorrentUri(const QString &value) const;
    void applySettings(const AppSettings *settings);
    bool addMagnet(DownloadItem *item, bool startPaused);
    bool addTorrentFile(DownloadItem *item, const QString &torrentFilePath, bool startPaused);
    bool restoreTorrent(DownloadItem *item);
    void pause(const QString &downloadId);
    void resume(DownloadItem *item);
    void remove(const QString &downloadId, bool deleteFiles = false);
    void saveResumeData(const QString &downloadId);
    QObject *fileModel(const QString &downloadId) const;
    QObject *peerModel(const QString &downloadId) const;
    QObject *trackerModel(const QString &downloadId) const;
    bool setFileWanted(const QString &downloadId, int row, bool wanted);
    bool setFileWantedByFileIndex(const QString &downloadId, int fileIndex, bool wanted);
    bool setFileWantedByPath(const QString &downloadId, const QString &path, bool wanted);
    bool addTracker(const QString &downloadId, const QString &url);
    void mergeTrackers(const QString &downloadId, const QStringList &trackers);
    QString infoHashFromSource(const QString &source) const;
    bool removeTracker(const QString &downloadId, const QString &url);
    bool addWebSeed(const QString &downloadId, const QString &url);
    bool removeWebSeed(const QString &downloadId, const QString &url);
    QStringList trackerUrls(const QString &downloadId) const;
    void setPerTorrentDownloadLimit(const QString &downloadId, int kbps);
    void setPerTorrentUploadLimit(const QString &downloadId, int kbps);
    bool moveStorage(const QString &downloadId, const QString &newSavePath);
    bool renameTorrentFile(const QString &downloadId, int fileIndex, const QString &newName);
    bool renameTorrentPath(const QString &downloadId, const QString &currentPath, const QString &newName);
    // Returns the current on-disk root name (top-level folder or single file name)
    // by reading the live file_storage paths from libtorrent. Empty if unavailable.
    QString torrentCurrentRootName(const QString &downloadId) const;
    bool exportTorrentFile(const QString &downloadId, const QString &outputPath) const;
    void setTorrentFlags(const QString &downloadId, bool disableDht, bool disablePex, bool disableLsd = false);
    void forceRecheck(const QString &downloadId);
    void forceReannounce(const QString &downloadId, const QStringList &trackerUrls = {});
    bool banPeer(const QString &downloadId, const QString &endpoint, int port,
                 const QString &client = {}, const QString &countryCode = {});
    bool unbanPeer(const QString &endpoint);
    QVariantList bannedPeers() const;
    // Returns a flat list of ints, one per piece:
    //   -2 = have (fully downloaded)
    //   -1 = partial (block(s) in flight / write-queue)
    //    0 = missing, no peer has it
    //    N = missing, N peers have it
    QVariantList torrentPieceMap(const QString &downloadId) const;
    QString detectedExternalAddress() const {
#if defined(STELLAR_HAS_LIBTORRENT)
        return m_externalAddress;
#else
        return {};
#endif
    }
    bool hasIncomingConnection() const { return m_hasIncomingConnection; }
    void setDetectedExternalAddress(const QString &ipAddress);
    void setDetectedExternalAddress(const QString &ipAddress, double latitude, double longitude, bool hasCoordinates);
    QVariantMap geoDatabaseInfo();
    void releaseGeoDatabaseForUpdate();
    qint64 dhtGlobalNodesEstimate();
    int dhtEstimateWarmupPercent() const;
    QString dhtEstimateDebugText() const;
    bool dhtCrawlInProgress() const;
    void startDhtCrawlNow();

signals:
    void externalAddressChanged();
    void hasIncomingConnectionChanged();
    void torrentFinished(const QString &downloadId);
    void torrentErrored(const QString &downloadId, const QString &reason);
    void torrentShareLimitReached(const QString &downloadId, int action);
    void bannedPeersChanged();

private:
#if defined(STELLAR_HAS_LIBTORRENT)
    struct BannedPeer {
        QString endpoint;
        QString client;
        QString countryCode;
        QString reason;
        bool permanent{false};
    };

    struct TrackerAlertSnapshot {
        QString status;
        QString message;
        int seeders{-1};
        int peers{-1};
        QDateTime updatedAt;
    };

    struct DhtCrawlNode {
        QByteArray id;
        QString host;
        int port{0};
    };

    struct PeerLocation;
    struct GeoDbState;
    void ensureSession();
    void configureSession(const AppSettings *settings);
    void processAlerts();
    void handleAlert(libtorrent::alert *alert);
    QString idForHandle(const libtorrent::torrent_handle &handle) const;
    void updateItemFromStatus(DownloadItem *item, const libtorrent::torrent_handle &handle);
    void updateModels(const QString &downloadId, const libtorrent::torrent_handle &handle, bool forceTrackerUpdate = false);
    bool addTorrentInternal(DownloadItem *item, bool startPaused, const QString &torrentFilePath);
    void checkShareLimits(const QString &id, DownloadItem *item, const AppSettings *settings);
    void refreshPeerBanRules(const AppSettings *settings);
    void rebuildIpFilter();
    void setTemporaryPeerBan(const QString &endpoint, const QString &client,
                             const QString &countryCode, const QString &reason);
    void clearTemporaryPeerBans();
    bool matchAutoBanRule(const libtorrent::peer_info &peer, const QString &client,
                          const QString &countryCode, QString *reason) const;
    void ensureGeoDb();
    void lookupPeerLocation(const QString &endpoint, QString *countryCode,
                            QString *regionCode, QString *regionName, QString *cityName,
                            double *latitude, double *longitude);
    void enqueueDhtCrawlNode(const QByteArray &nodeId, const QString &host, int port);
    void pumpDhtEstimatorCrawler();
    void handleDhtDirectResponse(const libtorrent::dht_direct_response_alert *alert);
    void maybePublishDhtMeasurementEpoch(const QDateTime &now);

    std::unique_ptr<libtorrent::session> m_session;
    std::unique_ptr<GeoDbState> m_geoDb;
    QHash<QString, libtorrent::torrent_handle> m_handles;
    QHash<QString, QPointer<DownloadItem>> m_items;
    QHash<QString, TorrentFileModel *> m_fileModels;
    QHash<QString, TorrentPeerModel *> m_peerModels;
    QHash<QString, TorrentTrackerModel *> m_trackerModels;
    QSet<QString> m_pausedIds;
    QSet<QString> m_movingIds;
    QHash<QString, QDateTime> m_seedingStartTimes;
    QHash<QString, qint64> m_lastUploadBytesForInactive;
    QHash<QString, QDateTime> m_lastUploadActivityTime;
    QHash<QString, QDateTime> m_lastResumeSaveRequest;
    QHash<QString, QHash<QString, QDateTime>> m_trackerReannounceUntil;
    QHash<QString, QHash<QString, TrackerAlertSnapshot>> m_trackerAlertSnapshots;
    QHash<QString, QString> m_trackerIpCache;
    QHash<QString, BannedPeer> m_bannedPeers;
    QString m_externalAddress;
    bool    m_hasIncomingConnection{false};
    bool    m_hasIncomingPending{false};
    bool    m_didInspectPeersThisTick{false};
    QString m_localCountryCode;
    QString m_localRegionName;
    QString m_localCityName;
    double m_localLatitude{0.0};
    double m_localLongitude{0.0};
    bool m_hasLocalCoordinates{false};
    QSet<QString> m_manualBannedPeers;
    QSet<QString> m_temporaryBannedPeers;
    QStringList m_blockedPeerUserAgentTerms;
    QSet<QString> m_blockedPeerCountries;
    bool m_autoBanAbusivePeers{false};
    bool m_autoBanMediaPlayerPeers{false};
    const AppSettings *m_settings{nullptr};
    int m_modelTick{0};
    int m_dhtNodesMetricIndex{-1};
    qint64 m_lastDhtNodes{-1};
    int m_lastDhtBucketCount{0};
    qint64 m_lastDhtGlobalNodes{-1};
    qint64 m_cachedDhtGlobalEstimate{-1};
    int m_lastDhtWarmupPercent{0};
    QVector<qint64> m_recentPublishedDhtEstimates;
    QVector<DhtCrawlNode> m_dhtCrawlQueue;
    QSet<QByteArray> m_enqueuedDhtNodeIds;
    QHash<QString, QDateTime> m_pendingDhtRequests;
    QHash<QByteArray, QDateTime> m_dhtMeasurementZoneNodes;
    QDateTime m_dhtMeasurementStartedAt;
    QDateTime m_dhtMeasurementLastPublishedAt;
    bool m_dhtMeasurementPublished{false};
    QElapsedTimer m_lastSessionStatsRequest;
    QElapsedTimer m_lastDhtLiveNodesRequest;
    QElapsedTimer m_lastDhtLiveNodesUpdate;
    QByteArray m_lastDhtNodeId;
    QHash<QByteArray, QDateTime> m_recentDhtNodeIds;
    // Last published zone-node count — preserved across epoch rollovers so
    // the tooltip doesn't flash "Closest samples: 0" while the next crawl
    // is warming up.
    int m_lastPublishedZoneCount{0};
    // Sliding-window history of live zone-node counts, used by the plateau
    // detector in maybePublishDhtMeasurementEpoch() to publish early once
    // the BFS has saturated and the count has stopped meaningfully growing.
    // Trimmed to ~2 × kPlateauWindowSecs of samples; tiny in practice.
    struct ZoneSample {
        QDateTime takenAt;
        int liveCount{0};
    };
    QList<ZoneSample> m_zoneCountHistory;
    // Counts pump-timer ticks since the current measurement started, used to
    // pace bootstrap-walk re-pulls of dht_live_nodes inside pumpDhtEstimator-
    // Crawler(). Reset when a new epoch begins.
    int m_dhtBootstrapTickCount{0};
    // Per-crawl diagnostic counters, reset on epoch start, written to the CSV
    // log so we can tell whether undersaturation is caused by sending too few
    // probes or by the network simply not yielding more in-zone nodes.
    int m_dhtCrawlProbesSent{0};
    int m_dhtCrawlResponsesReceived{0};
    int m_dhtCrawlPeakLiveZone{0};
    // Dedicated high-frequency pump timer (100ms) that runs only while a
    // measurement window is active, so dht_direct_request queries saturate
    // the 5–10s crawl instead of trickling out at the 2s alert-timer rate.
    QTimer m_dhtFastPumpTimer;
#endif
    QTimer m_alertTimer;
};

// When libtorrent is absent the .cpp stubs may be in a stale cached obj.
// Provide inline fallbacks here so callers always resolve these symbols.
#if !defined(STELLAR_HAS_LIBTORRENT)
inline bool TorrentSessionManager::moveStorage(const QString &, const QString &) { return false; }
inline bool TorrentSessionManager::renameTorrentFile(const QString &, int, const QString &) { return false; }
inline QString TorrentSessionManager::torrentCurrentRootName(const QString &) const { return {}; }
inline bool TorrentSessionManager::setFileWantedByFileIndex(const QString &, int, bool) { return false; }
inline bool TorrentSessionManager::setFileWantedByPath(const QString &, const QString &, bool) { return false; }
inline void TorrentSessionManager::setTorrentFlags(const QString &, bool, bool, bool) {}
inline bool TorrentSessionManager::banPeer(const QString &, const QString &, int, const QString &, const QString &) { return false; }
inline bool TorrentSessionManager::unbanPeer(const QString &) { return false; }
inline QVariantList TorrentSessionManager::bannedPeers() const { return {}; }
inline void TorrentSessionManager::setDetectedExternalAddress(const QString &) {}
inline void TorrentSessionManager::setDetectedExternalAddress(const QString &, double, double, bool) {}
inline QVariantMap TorrentSessionManager::geoDatabaseInfo() { return {}; }
inline void TorrentSessionManager::releaseGeoDatabaseForUpdate() {}
inline qint64 TorrentSessionManager::dhtGlobalNodesEstimate() { return -1; }
inline int TorrentSessionManager::dhtEstimateWarmupPercent() const { return 0; }
inline QString TorrentSessionManager::dhtEstimateDebugText() const { return {}; }
inline bool TorrentSessionManager::dhtCrawlInProgress() const { return false; }
inline void TorrentSessionManager::startDhtCrawlNow() {}
#endif
