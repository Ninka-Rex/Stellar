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
#include <QPointer>
#include <QSet>
#include <QTimer>
#include <QVariantMap>
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
    bool addTracker(const QString &downloadId, const QString &url);
    bool removeTracker(const QString &downloadId, const QString &url);
    void setPerTorrentDownloadLimit(const QString &downloadId, int kbps);
    void setPerTorrentUploadLimit(const QString &downloadId, int kbps);
    bool moveStorage(const QString &downloadId, const QString &newSavePath);
    bool renameTorrentFile(const QString &downloadId, int fileIndex, const QString &newName);
    bool renameTorrentPath(const QString &downloadId, const QString &currentPath, const QString &newName);
    bool exportTorrentFile(const QString &downloadId, const QString &outputPath) const;
    void setTorrentFlags(const QString &downloadId, bool disableDht, bool disablePex, bool disableLsd = false);
    void forceRecheck(const QString &downloadId);
    QString detectedExternalAddress() const {
#if defined(STELLAR_HAS_LIBTORRENT)
        return m_externalAddress;
#else
        return {};
#endif
    }
    void setDetectedExternalAddress(const QString &ipAddress);
    void setDetectedExternalAddress(const QString &ipAddress, double latitude, double longitude, bool hasCoordinates);
    QVariantMap geoDatabaseInfo();
    void releaseGeoDatabaseForUpdate();

signals:
    void torrentFinished(const QString &downloadId);
    void torrentErrored(const QString &downloadId, const QString &reason);
    void torrentShareLimitReached(const QString &downloadId, int action);

private:
#if defined(STELLAR_HAS_LIBTORRENT)
    struct PeerLocation;
    struct GeoDbState;
    void ensureSession();
    void configureSession(const AppSettings *settings);
    void processAlerts();
    void handleAlert(libtorrent::alert *alert);
    QString idForHandle(const libtorrent::torrent_handle &handle) const;
    void updateItemFromStatus(DownloadItem *item, const libtorrent::torrent_handle &handle);
    void updateModels(const QString &downloadId, const libtorrent::torrent_handle &handle);
    bool addTorrentInternal(DownloadItem *item, bool startPaused, const QString &torrentFilePath);
    void checkShareLimits(const QString &id, DownloadItem *item, const AppSettings *settings);
    void ensureGeoDb();
    void lookupPeerLocation(const QString &endpoint, QString *countryCode,
                            QString *regionCode, QString *regionName, QString *cityName,
                            double *latitude, double *longitude);

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
    QHash<QString, QString> m_trackerIpCache;
    QString m_externalAddress;
    double m_localLatitude{0.0};
    double m_localLongitude{0.0};
    bool m_hasLocalCoordinates{false};
    const AppSettings *m_settings{nullptr};
    int m_modelTick{0};
#endif
    QTimer m_alertTimer;
};

// When libtorrent is absent the .cpp stubs may be in a stale cached obj.
// Provide inline fallbacks here so callers always resolve these symbols.
#if !defined(STELLAR_HAS_LIBTORRENT)
inline bool TorrentSessionManager::moveStorage(const QString &, const QString &) { return false; }
inline bool TorrentSessionManager::renameTorrentFile(const QString &, int, const QString &) { return false; }
inline void TorrentSessionManager::setTorrentFlags(const QString &, bool, bool, bool) {}
inline void TorrentSessionManager::setDetectedExternalAddress(const QString &) {}
inline void TorrentSessionManager::setDetectedExternalAddress(const QString &, double, double, bool) {}
inline QVariantMap TorrentSessionManager::geoDatabaseInfo() { return {}; }
inline void TorrentSessionManager::releaseGeoDatabaseForUpdate() {}
#endif
