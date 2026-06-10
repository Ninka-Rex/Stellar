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
#include <atomic>
#include <memory>

class AppSettings;
class DownloadItem;
class TorrentFileModel;
class TorrentPeerModel;
class TorrentTrackerModel;

#if defined(STELLAR_HAS_LIBTORRENT)
#include <libtorrent/torrent_handle.hpp>
#include <libtorrent/torrent_status.hpp>
#include <memory>
namespace libtorrent {
class session;
class alert;
}
inline size_t qHash(const libtorrent::torrent_handle &h, size_t seed = 0) noexcept {
    return libtorrent::hash_value(h) ^ seed;
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
    bool addMagnet(DownloadItem *item, bool startPaused, bool deferModels = false);
    bool addTorrentFile(DownloadItem *item, const QString &torrentFilePath, bool startPaused, bool deferModels = false);
    bool restoreTorrent(DownloadItem *item, bool deferModels = false);
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
    bool setFilePriority(const QString &downloadId, int row, int priority);
    bool setFilePriorityByFileIndex(const QString &downloadId, int fileIndex, int priority);
    bool setFilePriorityByPath(const QString &downloadId, const QString &path, int priority);
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

    // Create a brand-new .torrent from local files/folders on a background thread.
    // params keys: inputPaths (QStringList), outputPath (QString), name (QString),
    //   comment (QString), description (QString), trackers (QStringList),
    //   webSeeds (QStringList), isPrivate (bool), pieceSize (int, bytes; 0=auto),
    //   creatorTag (QString).
    // Emits torrentCreationProgress(int percent) and
    //   torrentCreationFinished(bool success, QString errorOrPath).
    void createTorrentFile(const QVariantMap &params);
    void cancelTorrentCreation();
    void setTorrentFlags(const QString &downloadId, bool disableDht, bool disablePex, bool disableLsd = false);
    void setTorrentDownloadMode(const QString &downloadId, bool sequential, bool firstLastPieces);
    void forceRecheck(const QString &downloadId);
    void forceReannounce(const QString &downloadId, const QStringList &trackerUrls = {});
    // Immediately push peer and tracker data to their models without waiting for
    // the next alert-timer tick. Called when the user switches to the peers,
    // swarm-map, or trackers tab so the view populates instantly instead of after
    // up to 2 s.
    Q_INVOKABLE void refreshModelsNow(const QString &downloadId);
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
    bool hasIncomingConnection() const {
#if defined(STELLAR_HAS_LIBTORRENT)
        return m_hasIncomingConnection;
#else
        return false;
#endif
    }
    int listenPort() const;
    // Global DHT node count from the routing table (session-wide, all torrents).
    // 0 when DHT disabled or built without libtorrent.
    int dhtNodes() const {
#if defined(STELLAR_HAS_LIBTORRENT)
        return m_dhtNodes;
#else
        return 0;
#endif
    }
    void setDetectedExternalAddress(const QString &ipAddress);
    void setDetectedExternalAddress(const QString &ipAddress, double latitude, double longitude, bool hasCoordinates);
    QVariantMap geoDatabaseInfo();
    void releaseGeoDatabaseForUpdate();
    // Suspend/resume the entire libtorrent session — zero network traffic.
    void suspendSession();
    void unsuspendSession();
    // True iff the user-supplied bind target resolves to a usable, up+running
    // network interface with at least one bindable IP. Used by AppController to
    // detect VPN connect/disconnect so the libtorrent session can be suspended
    // when the bound interface goes away (otherwise traffic leaks through the
    // default route, because libtorrent treats an empty listen_interfaces as
    // "bind to 0.0.0.0").
    bool isBindInterfaceAvailable(const QString &bindTarget) const;

signals:
    void externalAddressChanged();
    void hasIncomingConnectionChanged();
    void dhtNodesChanged();
    void torrentBatchUpdated();
    void torrentFinished(const QString &downloadId);
    void torrentErrored(const QString &downloadId, const QString &reason);
    void torrentShareLimitReached(const QString &downloadId, int action);
    void bannedPeersChanged();
    void torrentCreationProgress(int percent);
    void torrentCreationFinished(bool success, const QString &errorOrPath);

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

    struct PeerLocation;
    struct GeoDbState;
    void ensureSession();
    void configureSession(const AppSettings *settings);
    void processAlerts();
    void handleAlert(libtorrent::alert *alert);
    QString idForHandle(const libtorrent::torrent_handle &handle) const;
    // Primary overload: uses pre-fetched status (avoids redundant handle.status() IPC call).
    void updateItemFromStatus(DownloadItem *item, const libtorrent::torrent_handle &handle,
                              const libtorrent::torrent_status &st);
    // Convenience wrapper for call sites that only have a handle (fetches status internally).
    void updateItemFromStatus(DownloadItem *item, const libtorrent::torrent_handle &handle);
    // trackerOnly: skip full peer-info scan / file-model / peer-model refresh —
    // only refresh the tracker model. Tracker alerts (announce/reply/scrape/etc.)
    // do not change the connected peer set, so re-scanning every peer (with
    // geo-IP lookups, auto-ban regex, QStringList allocs) on every tracker
    // alert is wasted work that scales with N_torrents × N_trackers.
    void updateModels(const QString &downloadId, const libtorrent::torrent_handle &handle,
                      const libtorrent::torrent_status &st,
                      bool forceTrackerUpdate = false, bool trackerOnly = false);
    void updateModels(const QString &downloadId, const libtorrent::torrent_handle &handle,
                      bool forceTrackerUpdate = false, bool trackerOnly = false);
    // Rebuilds the libtorrent file-priority vector for downloadId from its
    // TorrentFileModel entries and applies it via prioritize_files(). Skipped
    // files (wanted=false) get dont_download; wanted files get their stored
    // priority (clamped to [0,7]). Persists resume data. Shared by all the
    // setFileWanted*/setFilePriority* mutators.
    bool applyFilePriorities(const QString &downloadId);
    void requestIpFilterRebuild(); // coalesced via m_ipFilterRebuildPending
    void flushIpFilterRebuild();
    bool addTorrentInternal(DownloadItem *item, bool startPaused, const QString &torrentFilePath, bool deferModels);
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

    std::unique_ptr<libtorrent::session> m_session;
    std::unique_ptr<GeoDbState> m_geoDb;
    QHash<QString, libtorrent::torrent_handle> m_handles;
    QHash<libtorrent::torrent_handle, QString> m_handleToId;
    QHash<QString, QPointer<DownloadItem>> m_items;
    QHash<QString, TorrentFileModel *> m_fileModels;
    QHash<QString, TorrentPeerModel *> m_peerModels;
    QHash<QString, TorrentTrackerModel *> m_trackerModels;
    QSet<QString> m_pausedIds;
    QSet<QString> m_movingIds;
    QSet<QString> m_firedFinishedIds;
    QSet<QString> m_staticMetadataApplied; // torrent IDs whose immutable metadata (name, hash, comment, web seeds…) has been applied once
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
    int     m_dhtNodes{0};
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
    // Coalesce IP-filter rebuilds within one processAlerts() pass. Each ban
    // previously rebuilt the libtorrent ip_filter with all N rules; under
    // auto-ban with a steady stream of abusive peers this turned every alert
    // tick into an N² operation that froze the UI thread.
    bool m_ipFilterRebuildPending{false};
    static constexpr int kMaxTemporaryBans = 5000;
    static constexpr int kMaxBannedPeers   = 8000;
    const AppSettings *m_settings{nullptr};
    int m_modelTick{0};
#endif
    QTimer m_alertTimer;
    // Atomic flag so the hashing thread can check for cancellation each piece.
    std::atomic<bool> m_torrentCreationCancelled{false};
};

// When libtorrent is absent the .cpp stubs may be in a stale cached obj.
// Provide inline fallbacks here so callers always resolve these symbols.
#if !defined(STELLAR_HAS_LIBTORRENT)
inline bool TorrentSessionManager::moveStorage(const QString &, const QString &) { return false; }
inline bool TorrentSessionManager::renameTorrentFile(const QString &, int, const QString &) { return false; }
inline QString TorrentSessionManager::torrentCurrentRootName(const QString &) const { return {}; }
inline bool TorrentSessionManager::setFileWantedByFileIndex(const QString &, int, bool) { return false; }
inline bool TorrentSessionManager::setFileWantedByPath(const QString &, const QString &, bool) { return false; }
inline bool TorrentSessionManager::setFilePriority(const QString &, int, int) { return false; }
inline bool TorrentSessionManager::setFilePriorityByFileIndex(const QString &, int, int) { return false; }
inline bool TorrentSessionManager::setFilePriorityByPath(const QString &, const QString &, int) { return false; }
inline void TorrentSessionManager::setTorrentFlags(const QString &, bool, bool, bool) {}
inline void TorrentSessionManager::setTorrentDownloadMode(const QString &, bool, bool) {}
inline bool TorrentSessionManager::banPeer(const QString &, const QString &, int, const QString &, const QString &) { return false; }
inline bool TorrentSessionManager::unbanPeer(const QString &) { return false; }
inline QVariantList TorrentSessionManager::bannedPeers() const { return {}; }
inline void TorrentSessionManager::setDetectedExternalAddress(const QString &) {}
inline void TorrentSessionManager::setDetectedExternalAddress(const QString &, double, double, bool) {}
inline QVariantMap TorrentSessionManager::geoDatabaseInfo() { return {}; }
inline void TorrentSessionManager::releaseGeoDatabaseForUpdate() {}
inline void TorrentSessionManager::createTorrentFile(const QVariantMap &) {
    emit torrentCreationFinished(false, QStringLiteral("BitTorrent support not compiled in"));
}
inline void TorrentSessionManager::cancelTorrentCreation() {}
#endif
