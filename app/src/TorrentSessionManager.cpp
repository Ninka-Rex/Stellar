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

#include "TorrentSessionManager.h"

#include "AppSettings.h"
#include "AppVersion.h"
#include "DownloadItem.h"
#include "TorrentFileModel.h"
#include "TorrentPeerModel.h"
#include "TorrentTrackerModel.h"

#include <QByteArray>
#include <QCoreApplication>
#include <QDateTime>
#include <QDir>
#include <QFileInfo>
#include <QHostAddress>
#include <QHostInfo>
#include <QNetworkInterface>
#include <QNetworkProxy>
#include <QNetworkProxyFactory>
#include <QRegularExpression>
#include <QUrl>
#include <QFile>
#include <QStandardPaths>
#include <algorithm>

#if defined(STELLAR_HAS_LIBTORRENT)
#include <libtorrent/add_torrent_params.hpp>
#include <libtorrent/alert_types.hpp>
#include <libtorrent/bencode.hpp>
#include <libtorrent/create_torrent.hpp>
#include <libtorrent/error_code.hpp>
#include <libtorrent/magnet_uri.hpp>
#include <libtorrent/read_resume_data.hpp>
#include <libtorrent/session.hpp>
#include <libtorrent/settings_pack.hpp>
#include <libtorrent/hex.hpp>
#include <libtorrent/announce_entry.hpp>
#include <libtorrent/address.hpp>
#include <libtorrent/ip_filter.hpp>
#include <libtorrent/torrent_flags.hpp>
#include <libtorrent/torrent_info.hpp>
#include <libtorrent/torrent_status.hpp>
#include <libtorrent/write_resume_data.hpp>
#if defined(STELLAR_HAS_MAXMINDDB)
#include <maxminddb.h>
#endif
#else
void TorrentSessionManager::setPerTorrentDownloadLimit(const QString &downloadId, int kbps) {
    Q_UNUSED(downloadId);
    Q_UNUSED(kbps);
}

void TorrentSessionManager::setPerTorrentUploadLimit(const QString &downloadId, int kbps) {
    Q_UNUSED(downloadId);
    Q_UNUSED(kbps);
}
#endif

#if defined(STELLAR_HAS_LIBTORRENT)
namespace {
bool isBareTorrentInfoHash(const QString &value) {
    const QString trimmed = value.trimmed();
    if (trimmed.size() != 40)
        return false;
    for (const QChar ch : trimmed) {
        if (!ch.isDigit() && (ch.toLower() < QLatin1Char('a') || ch.toLower() > QLatin1Char('f')))
            return false;
    }
    return true;
}

QString normalizeTorrentUri(const QString &value) {
    const QString trimmed = value.trimmed();
    if (isBareTorrentInfoHash(trimmed))
        return QStringLiteral("magnet:?xt=urn:btih:%1").arg(trimmed.toLower());
    return trimmed;
}

QString trackerStatusKey(const QString &urlText) {
    const QString trimmed = urlText.trimmed();
    if (trimmed.isEmpty())
        return {};

    QUrl url(trimmed);
    if (!url.isValid() || url.scheme().isEmpty() || url.host().isEmpty())
        return trimmed;

    QString path = url.path();
    while (path.endsWith(QLatin1Char('/')) && path.size() > 1)
        path.chop(1);
    url.setPath(path);

    QString scheme = url.scheme().toLower();
    QString host = url.host().toLower();
    url.setScheme(scheme);
    url.setHost(host);
    return url.toString(QUrl::FullyEncoded);
}

libtorrent::span<char const> asSpan(const QByteArray &data) {
    return libtorrent::span<char const>(data.constData(), data.size());
}

const libtorrent::announce_infohash *firstTrackerInfohash(const libtorrent::announce_entry &tracker) {
    for (const auto &endpoint : tracker.endpoints) {
        for (const auto &infohash : endpoint.info_hashes)
            return &infohash;
    }
    return nullptr;
}

QString toHexString(std::string const &value) {
    static constexpr char kHex[] = "0123456789abcdef";
    QString result;
    result.reserve(int(value.size() * 2));
    for (unsigned char ch : value) {
        result.append(QLatin1Char(kHex[(ch >> 4) & 0x0f]));
        result.append(QLatin1Char(kHex[ch & 0x0f]));
    }
    return result;
}

void mergeMagnetParams(libtorrent::add_torrent_params &target,
                       const libtorrent::add_torrent_params &source) {
    target.info_hashes = source.info_hashes;
    target.trackers = source.trackers;
    target.tracker_tiers = source.tracker_tiers;
    target.dht_nodes = source.dht_nodes;
    target.url_seeds = source.url_seeds;
    target.peers = source.peers;
    if (target.name.empty())
        target.name = source.name;
}

QString formatListenInterface(const QHostAddress &address, int port) {
    const QString ip = address.toString();
    if (address.protocol() == QAbstractSocket::IPv6Protocol)
        return QStringLiteral("[%1]:%2").arg(ip, QString::number(port));
    return QStringLiteral("%1:%2").arg(ip, QString::number(port));
}

QNetworkInterface findNetworkInterfaceForBinding(const QString &bindTarget) {
    const QString trimmed = bindTarget.trimmed();
    if (trimmed.isEmpty())
        return {};

    const QNetworkInterface byName = QNetworkInterface::interfaceFromName(trimmed);
    if (byName.isValid())
        return byName;

    const QList<QNetworkInterface> interfaces = QNetworkInterface::allInterfaces();
    for (const QNetworkInterface &iface : interfaces) {
        if (QString::compare(iface.humanReadableName().trimmed(), trimmed, Qt::CaseInsensitive) == 0)
            return iface;
    }

    return {};
}

QStringList interfaceBindAddresses(const QNetworkInterface &iface) {
    QStringList addresses;
    if (!iface.isValid())
        return addresses;

    const auto flags = iface.flags();
    if (!flags.testFlag(QNetworkInterface::IsUp) ||
        !flags.testFlag(QNetworkInterface::IsRunning) ||
        flags.testFlag(QNetworkInterface::IsLoopBack)) {
        return addresses;
    }

    const QList<QNetworkAddressEntry> entries = iface.addressEntries();
    for (const QNetworkAddressEntry &entry : entries) {
        const QHostAddress address = entry.ip();
        if (address.isNull() || address.isLoopback())
            continue;
        if (address.protocol() != QAbstractSocket::IPv4Protocol &&
            address.protocol() != QAbstractSocket::IPv6Protocol) {
            continue;
        }

        addresses.push_back(address.toString());
    }

    addresses.removeDuplicates();
    return addresses;
}

QStringList geoDbCandidates() {
    const QString appDir = QCoreApplication::applicationDirPath();
    QString writableDataDir = QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation);
    if (writableDataDir.isEmpty())
        writableDataDir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    writableDataDir = writableDataDir.isEmpty()
        ? QString()
        : QDir::cleanPath(writableDataDir + QStringLiteral("/data"));
    return {
        writableDataDir + QStringLiteral("/dbip-city-lite-2026-04.mmdb"),
        appDir + QStringLiteral("/data/dbip-city-lite-2026-04.mmdb"),
        appDir + QStringLiteral("/dbip-city-lite-2026-04.mmdb"),
        appDir + QStringLiteral("/../data/dbip-city-lite-2026-04.mmdb"),
        QDir::cleanPath(QCoreApplication::applicationDirPath() + QStringLiteral("/../../app/data/dbip-city-lite-2026-04.mmdb")),
        QDir::cleanPath(QCoreApplication::applicationDirPath() + QStringLiteral("/../../../app/data/dbip-city-lite-2026-04.mmdb"))
    };
}

QString defaultTorrentUserAgent(const AppSettings *settings) {
    if (settings) {
        const QString custom = settings->torrentCustomUserAgent().trimmed();
        if (!custom.isEmpty())
            return custom;
    }
    return QStringLiteral("Stellar/%1").arg(QStringLiteral(STELLAR_VERSION));
}

QString normalizePeerEndpoint(const QString &endpoint) {
    return QHostAddress(endpoint.trimmed()).toString();
}

QStringList normalizedLines(const QString &text) {
    QStringList out;
    const QStringList lines = text.split(QRegularExpression(QStringLiteral("[\\r\\n]+")),
                                         Qt::SkipEmptyParts);
    for (const QString &raw : lines) {
        const QString trimmed = raw.trimmed();
        if (!trimmed.isEmpty())
            out.push_back(trimmed);
    }
    out.removeDuplicates();
    return out;
}

QStringList normalizedCountryCodes(const QStringList &values) {
    QStringList out;
    for (const QString &raw : values) {
        const QString code = raw.trimmed().toUpper();
        if (code.length() == 2)
            out.push_back(code);
    }
    out.removeDuplicates();
    std::sort(out.begin(), out.end());
    return out;
}

bool containsSubstringRule(const QStringList &needles, const QString &haystack) {
    const QString lower = haystack.toLower();
    for (const QString &rule : needles) {
        if (!rule.isEmpty() && lower.contains(rule.toLower()))
            return true;
    }
    return false;
}

QString peerIdPrefix(const libtorrent::peer_info &peer) {
    return QString::fromLatin1(peer.pid.data(), 8);
}

bool matchesAbusivePeerPreset(const libtorrent::peer_info &peer, const QString &client,
                              const QString &countryCode) {
    static const QRegularExpression pidFilter(QStringLiteral("-(XL|XF|QD|BN|DL)(\\d+)-"));
    static const QRegularExpression consumeFilter(
        QStringLiteral("((dt|hp|xm)/torrent|Gopeed dev|Rain 0.0.0|(Taipei-torrent( dev)?))"),
        QRegularExpression::CaseInsensitiveOption);
    static const QRegularExpression fakeOfflineId(QStringLiteral("-LT(1220|2070)-"));

    const QString pid = peerIdPrefix(peer);
    const QString cc = countryCode.trimmed().toUpper();
    if (pidFilter.match(pid).hasMatch())
        return true;
    if (cc == QStringLiteral("CN") && consumeFilter.match(client).hasMatch())
        return true;

    const unsigned short port = peer.ip.port();
    const bool fakeTransmission = port >= 65000
        && cc == QStringLiteral("CN")
        && client.contains(QStringLiteral("Transmission"), Qt::CaseInsensitive);
    const bool fakeLibtorrent = (cc == QStringLiteral("NL") || cc == QStringLiteral("CN"))
        && fakeOfflineId.match(pid).hasMatch();
    return fakeTransmission || fakeLibtorrent;
}

bool matchesMediaPlayerPreset(const libtorrent::peer_info &peer, const QString &client) {
    if (client.contains(QStringLiteral("StellarPlayer"), Qt::CaseInsensitive)
        || client.contains(QStringLiteral("Elementum"), Qt::CaseInsensitive)) {
        return true;
    }
    static const QRegularExpression playerFilter(QStringLiteral("-(UW\\w{4}|SP(([0-2]\\d{3})|(3[0-5]\\d{2})))-"));
    return playerFilter.match(peerIdPrefix(peer)).hasMatch();
}

#if defined(STELLAR_HAS_MAXMINDDB)
QString mmdbString(MMDB_entry_s *entry, const char *const *path) {
    MMDB_entry_data_s data;
    const int status = MMDB_aget_value(entry, &data, path);
    if (status != MMDB_SUCCESS || !data.has_data || data.type != MMDB_DATA_TYPE_UTF8_STRING)
        return {};
    return QString::fromUtf8(data.utf8_string, static_cast<qsizetype>(data.data_size));
}
#endif
}
#endif

#if defined(STELLAR_HAS_LIBTORRENT)
struct TorrentSessionManager::PeerLocation {
    QString countryCode;
    QString regionCode;
    QString regionName;
    QString cityName;
    double latitude{0.0};
    double longitude{0.0};
    bool hasCoordinates{false};
};

struct TorrentSessionManager::GeoDbState {
#if defined(STELLAR_HAS_MAXMINDDB)
    MMDB_s db{};
#endif
    bool open{false};
    bool attempted{false};
    QString path;
    QHash<QString, PeerLocation> cache;
};
#endif

TorrentSessionManager::TorrentSessionManager(QObject *parent)
    : QObject(parent) {
    m_alertTimer.setInterval(2000);
    connect(&m_alertTimer, &QTimer::timeout, this, [this]() {
#if defined(STELLAR_HAS_LIBTORRENT)
        ++m_modelTick;
        processAlerts();
        if (m_session) {
            m_session->post_torrent_updates();

            // For magnets waiting on metadata, post_torrent_updates() only
            // fires state_update_alert when the torrent's state actually changes.
            // If no peers have connected yet the state is static and the metadata
            // dialog shows a stale peer count. Force a refresh for every torrent
            // that still lacks metadata so the UI stays live.
            for (auto it = m_items.constBegin(); it != m_items.constEnd(); ++it) {
                DownloadItem *item = it.value().data();
                if (!item || item->torrentHasMetadata())
                    continue;
                if (m_pausedIds.contains(it.key()))
                    continue;
                const auto handle = m_handles.value(it.key());
                if (handle.is_valid()) {
                    updateItemFromStatus(item, handle);
                    updateModels(it.key(), handle);
                }
            }
        }
#endif
    });
}

TorrentSessionManager::~TorrentSessionManager() {
#if defined(STELLAR_HAS_LIBTORRENT) && defined(STELLAR_HAS_MAXMINDDB)
    if (m_geoDb && m_geoDb->open)
        MMDB_close(&m_geoDb->db);
#endif
}

bool TorrentSessionManager::available() const {
#if defined(STELLAR_HAS_LIBTORRENT)
    return true;
#else
    return false;
#endif
}

bool TorrentSessionManager::isTorrentUri(const QString &value) const {
    const QString trimmed = value.trimmed();
    return trimmed.startsWith(QStringLiteral("magnet:?"), Qt::CaseInsensitive)
        || isBareTorrentInfoHash(trimmed);
}

QVariantList TorrentSessionManager::bannedPeers() const {
#if defined(STELLAR_HAS_LIBTORRENT)
    QVariantList out;
    QStringList keys = m_bannedPeers.keys();
    std::sort(keys.begin(), keys.end());
    for (const QString &key : keys) {
        const BannedPeer &entry = m_bannedPeers[key];
        QVariantMap row;
        row.insert(QStringLiteral("endpoint"), entry.endpoint);
        row.insert(QStringLiteral("client"), entry.client);
        row.insert(QStringLiteral("countryCode"), entry.countryCode);
        row.insert(QStringLiteral("reason"), entry.reason);
        row.insert(QStringLiteral("permanent"), entry.permanent);
        out.push_back(row);
    }
    return out;
#else
    return {};
#endif
}

void TorrentSessionManager::applySettings(const AppSettings *settings) {
#if defined(STELLAR_HAS_LIBTORRENT)
    m_settings = settings;
    ensureSession();
    refreshPeerBanRules(settings);
    configureSession(settings);
    if (!m_alertTimer.isActive())
        m_alertTimer.start();
#else
    Q_UNUSED(settings);
#endif
}

bool TorrentSessionManager::addMagnet(DownloadItem *item, bool startPaused) {
#if defined(STELLAR_HAS_LIBTORRENT)
    return addTorrentInternal(item, startPaused, QString());
#else
    Q_UNUSED(item);
    Q_UNUSED(startPaused);
    return false;
#endif
}

bool TorrentSessionManager::addTorrentFile(DownloadItem *item, const QString &torrentFilePath, bool startPaused) {
#if defined(STELLAR_HAS_LIBTORRENT)
    return addTorrentInternal(item, startPaused, torrentFilePath);
#else
    Q_UNUSED(item);
    Q_UNUSED(torrentFilePath);
    Q_UNUSED(startPaused);
    return false;
#endif
}

bool TorrentSessionManager::restoreTorrent(DownloadItem *item) {
#if defined(STELLAR_HAS_LIBTORRENT)
    if (!item || !item->isTorrent())
        return false;
    if (item->statusEnum() == DownloadItem::Status::Error)
        return true;
    const bool paused = item->statusEnum() == DownloadItem::Status::Paused;
    if (item->torrentSource().startsWith(QStringLiteral("magnet:?"), Qt::CaseInsensitive))
        return addMagnet(item, paused);
    return addTorrentFile(item, item->torrentSource(), paused);
#else
    Q_UNUSED(item);
    return false;
#endif
}

void TorrentSessionManager::pause(const QString &downloadId) {
#if defined(STELLAR_HAS_LIBTORRENT)
    const auto handle = m_handles.value(downloadId);
    m_pausedIds.insert(downloadId);
    if (handle.is_valid()) {
        handle.unset_flags(libtorrent::torrent_flags::auto_managed);
        handle.pause();
    }
    if (DownloadItem *item = m_items.value(downloadId, nullptr).data()) {
        item->setStatus(DownloadItem::Status::Paused);
        item->setSpeed(0);
        item->setTorrentUploadSpeed(0);
        item->setTorrentConnections(0);
        item->setTorrentPeers(0);
        item->setTorrentListPeers(0);
    }
    if (auto *peerModel = qobject_cast<TorrentPeerModel *>(m_peerModels.value(downloadId, nullptr)))
        peerModel->setEntries({});
#else
    Q_UNUSED(downloadId);
#endif
}

bool TorrentSessionManager::banPeer(const QString &downloadId, const QString &endpoint, int port,
                                    const QString &client, const QString &countryCode) {
#if defined(STELLAR_HAS_LIBTORRENT)
    Q_UNUSED(downloadId);
    Q_UNUSED(port);
    const QString normalized = normalizePeerEndpoint(endpoint);
    if (normalized.isEmpty())
        return false;
    m_manualBannedPeers.insert(normalized);
    BannedPeer entry;
    entry.endpoint = normalized;
    entry.client = client;
    entry.countryCode = countryCode.trimmed().toUpper();
    entry.reason = QStringLiteral("Manually banned");
    entry.permanent = true;
    m_bannedPeers.insert(normalized, entry);
    rebuildIpFilter();
    emit bannedPeersChanged();
    return true;
#else
    Q_UNUSED(downloadId);
    Q_UNUSED(endpoint);
    Q_UNUSED(port);
    Q_UNUSED(client);
    Q_UNUSED(countryCode);
    return false;
#endif
}

bool TorrentSessionManager::unbanPeer(const QString &endpoint) {
#if defined(STELLAR_HAS_LIBTORRENT)
    const QString normalized = normalizePeerEndpoint(endpoint);
    if (normalized.isEmpty())
        return false;
    const bool removedManual = m_manualBannedPeers.remove(normalized);
    const bool removedTemp = m_temporaryBannedPeers.remove(normalized);
    const bool removedEntry = m_bannedPeers.remove(normalized) > 0;
    if (!removedManual && !removedTemp && !removedEntry)
        return false;
    rebuildIpFilter();
    emit bannedPeersChanged();
    return true;
#else
    Q_UNUSED(endpoint);
    return false;
#endif
}

void TorrentSessionManager::resume(DownloadItem *item) {
#if defined(STELLAR_HAS_LIBTORRENT)
    if (!item)
        return;
    const auto handle = m_handles.value(item->id());
    if (!handle.is_valid())
        return;
    m_pausedIds.remove(item->id());
    handle.unset_flags(libtorrent::torrent_flags::auto_managed);
    handle.resume();
    updateItemFromStatus(item, handle);
#else
    Q_UNUSED(item);
#endif
}

void TorrentSessionManager::remove(const QString &downloadId, bool deleteFiles) {
#if defined(STELLAR_HAS_LIBTORRENT)
    const auto handle = m_handles.take(downloadId);
    m_items.remove(downloadId);
    m_pausedIds.remove(downloadId);
    m_movingIds.remove(downloadId);
    m_lastResumeSaveRequest.remove(downloadId);
    m_trackerReannounceUntil.remove(downloadId);
    m_trackerAlertSnapshots.remove(downloadId);
    if (handle.is_valid() && m_session) {
        libtorrent::remove_flags_t flags{};
        if (deleteFiles)
            flags |= libtorrent::session_handle::delete_files;
        m_session->remove_torrent(handle, flags);
    }
#else
    Q_UNUSED(downloadId);
    Q_UNUSED(deleteFiles);
#endif
}

void TorrentSessionManager::saveResumeData(const QString &downloadId) {
#if defined(STELLAR_HAS_LIBTORRENT)
    const auto handle = m_handles.value(downloadId);
    if (handle.is_valid())
        handle.save_resume_data(libtorrent::torrent_handle::save_info_dict);
#else
    Q_UNUSED(downloadId);
#endif
}

QObject *TorrentSessionManager::fileModel(const QString &downloadId) const {
#if defined(STELLAR_HAS_LIBTORRENT)
    return m_fileModels.value(downloadId, nullptr);
#else
    Q_UNUSED(downloadId);
    return nullptr;
#endif
}

QObject *TorrentSessionManager::peerModel(const QString &downloadId) const {
#if defined(STELLAR_HAS_LIBTORRENT)
    return m_peerModels.value(downloadId, nullptr);
#else
    Q_UNUSED(downloadId);
    return nullptr;
#endif
}

QObject *TorrentSessionManager::trackerModel(const QString &downloadId) const {
#if defined(STELLAR_HAS_LIBTORRENT)
    return m_trackerModels.value(downloadId, nullptr);
#else
    Q_UNUSED(downloadId);
    return nullptr;
#endif
}

bool TorrentSessionManager::setFileWanted(const QString &downloadId, int row, bool wanted) {
#if defined(STELLAR_HAS_LIBTORRENT)
    auto *model = m_fileModels.value(downloadId, nullptr);
    const auto handle = m_handles.value(downloadId);
    if (!model || !handle.is_valid())
        return false;
    auto *fileModel = qobject_cast<TorrentFileModel *>(model);
    if (!fileModel || !fileModel->setWanted(row, wanted))
        return false;

    const QVector<TorrentFileModel::Entry> entries = fileModel->fileEntries();
    std::vector<libtorrent::download_priority_t> priorities;
    priorities.reserve(entries.size());
    for (const auto &entry : entries)
        priorities.push_back(entry.wanted ? libtorrent::default_priority : libtorrent::dont_download);
    handle.prioritize_files(priorities);
    saveResumeData(downloadId);
    return true;
#else
    Q_UNUSED(downloadId);
    Q_UNUSED(row);
    Q_UNUSED(wanted);
    return false;
#endif
}

bool TorrentSessionManager::setFileWantedByFileIndex(const QString &downloadId, int fileIndex, bool wanted) {
#if defined(STELLAR_HAS_LIBTORRENT)
    auto *model = m_fileModels.value(downloadId, nullptr);
    const auto handle = m_handles.value(downloadId);
    if (!model || !handle.is_valid())
        return false;
    auto *fileModel = qobject_cast<TorrentFileModel *>(model);
    if (!fileModel || !fileModel->setWantedByFileIndex(fileIndex, wanted))
        return false;

    const QVector<TorrentFileModel::Entry> entries = fileModel->fileEntries();
    std::vector<libtorrent::download_priority_t> priorities;
    priorities.reserve(entries.size());
    for (const auto &entry : entries)
        priorities.push_back(entry.wanted ? libtorrent::default_priority : libtorrent::dont_download);
    handle.prioritize_files(priorities);
    saveResumeData(downloadId);
    return true;
#else
    Q_UNUSED(downloadId); Q_UNUSED(fileIndex); Q_UNUSED(wanted);
    return false;
#endif
}

bool TorrentSessionManager::setFileWantedByPath(const QString &downloadId, const QString &path, bool wanted) {
#if defined(STELLAR_HAS_LIBTORRENT)
    auto *model = m_fileModels.value(downloadId, nullptr);
    const auto handle = m_handles.value(downloadId);
    if (!model || !handle.is_valid())
        return false;
    auto *fileModel = qobject_cast<TorrentFileModel *>(model);
    if (!fileModel || !fileModel->setWantedByPath(path, wanted))
        return false;

    const QVector<TorrentFileModel::Entry> entries = fileModel->fileEntries();
    std::vector<libtorrent::download_priority_t> priorities;
    priorities.reserve(entries.size());
    for (const auto &entry : entries)
        priorities.push_back(entry.wanted ? libtorrent::default_priority : libtorrent::dont_download);
    handle.prioritize_files(priorities);
    saveResumeData(downloadId);
    return true;
#else
    Q_UNUSED(downloadId); Q_UNUSED(path); Q_UNUSED(wanted);
    return false;
#endif
}

bool TorrentSessionManager::addTracker(const QString &downloadId, const QString &url) {
#if defined(STELLAR_HAS_LIBTORRENT)
    const auto handle = m_handles.value(downloadId);
    if (!handle.is_valid() || url.trimmed().isEmpty())
        return false;
    handle.add_tracker(libtorrent::announce_entry(url.trimmed().toStdString()));
    handle.post_trackers();
    if (DownloadItem *item = m_items.value(downloadId, nullptr).data())
        item->setTorrentTrackers(trackerUrls(downloadId));
    saveResumeData(downloadId);
    return true;
#else
    Q_UNUSED(downloadId);
    Q_UNUSED(url);
    return false;
#endif
}

bool TorrentSessionManager::removeTracker(const QString &downloadId, const QString &url) {
#if defined(STELLAR_HAS_LIBTORRENT)
    const auto handle = m_handles.value(downloadId);
    if (!handle.is_valid() || url.trimmed().isEmpty())
        return false;
    std::vector<libtorrent::announce_entry> trackers = handle.trackers();
    trackers.erase(std::remove_if(trackers.begin(), trackers.end(),
                                  [&](const libtorrent::announce_entry &entry) {
                                      return QString::fromStdString(entry.url) == url.trimmed();
                                  }),
                   trackers.end());
    handle.replace_trackers(trackers);
    handle.post_trackers();
    if (DownloadItem *item = m_items.value(downloadId, nullptr).data()) {
        QStringList urls;
        urls.reserve(static_cast<int>(trackers.size()));
        for (const auto &tracker : trackers)
            urls.push_back(QString::fromStdString(tracker.url));
        item->setTorrentTrackers(urls);
    }
    saveResumeData(downloadId);
    return true;
#else
    Q_UNUSED(downloadId);
    Q_UNUSED(url);
    return false;
#endif
}

#if defined(STELLAR_HAS_LIBTORRENT)
void TorrentSessionManager::ensureSession() {
    if (!m_session)
        m_session = std::make_unique<libtorrent::session>();
}

void TorrentSessionManager::refreshPeerBanRules(const AppSettings *settings) {
    const QSet<QString> previousTemporary = m_temporaryBannedPeers;
    if (settings) {
        m_manualBannedPeers.clear();
        for (const QString &raw : settings->torrentBannedPeers()) {
            const QString normalized = normalizePeerEndpoint(raw);
            if (!normalized.isEmpty())
                m_manualBannedPeers.insert(normalized);
        }
        m_blockedPeerUserAgentTerms = normalizedLines(settings->torrentBlockedPeerUserAgents());
        const QStringList countryCodes = normalizedCountryCodes(settings->torrentBlockedPeerCountries());
        m_blockedPeerCountries = QSet<QString>(countryCodes.begin(), countryCodes.end());
        m_autoBanAbusivePeers = settings->torrentAutoBanAbusivePeers();
        m_autoBanMediaPlayerPeers = settings->torrentAutoBanMediaPlayerPeers();
    } else {
        m_manualBannedPeers.clear();
        m_blockedPeerUserAgentTerms.clear();
        m_blockedPeerCountries.clear();
        m_autoBanAbusivePeers = false;
        m_autoBanMediaPlayerPeers = false;
    }

    QStringList removeKeys;
    for (auto it = m_bannedPeers.cbegin(); it != m_bannedPeers.cend(); ++it) {
        if (it.value().permanent && !m_manualBannedPeers.contains(it.key()))
            removeKeys.push_back(it.key());
    }
    for (const QString &key : removeKeys)
        m_bannedPeers.remove(key);

    clearTemporaryPeerBans();
    rebuildIpFilter();
    if (previousTemporary != m_temporaryBannedPeers || !removeKeys.isEmpty())
        emit bannedPeersChanged();
}

void TorrentSessionManager::rebuildIpFilter() {
    if (!m_session)
        return;
    libtorrent::ip_filter filter;
    QSet<QString> allBans = m_manualBannedPeers;
    for (const QString &endpoint : m_temporaryBannedPeers)
        allBans.insert(endpoint);
    for (const QString &endpoint : allBans) {
        libtorrent::error_code ec;
        libtorrent::address addr = libtorrent::make_address(endpoint.toStdString(), ec);
        if (ec)
            continue;
        filter.add_rule(addr, addr, libtorrent::ip_filter::blocked);
    }
    m_session->set_ip_filter(std::move(filter));
}

void TorrentSessionManager::setTemporaryPeerBan(const QString &endpoint, const QString &client,
                                                const QString &countryCode, const QString &reason) {
    const QString normalized = normalizePeerEndpoint(endpoint);
    if (normalized.isEmpty())
        return;
    if (!m_temporaryBannedPeers.contains(normalized)) {
        m_temporaryBannedPeers.insert(normalized);
        rebuildIpFilter();
    }
    BannedPeer entry;
    entry.endpoint = normalized;
    entry.client = client;
    entry.countryCode = countryCode.trimmed().toUpper();
    entry.reason = reason;
    entry.permanent = false;
    m_bannedPeers.insert(normalized, entry);
}

void TorrentSessionManager::clearTemporaryPeerBans() {
    if (m_temporaryBannedPeers.isEmpty()) {
        for (auto it = m_bannedPeers.begin(); it != m_bannedPeers.end(); ) {
            if (!it.value().permanent)
                it = m_bannedPeers.erase(it);
            else
                ++it;
        }
        return;
    }
    m_temporaryBannedPeers.clear();
    for (auto it = m_bannedPeers.begin(); it != m_bannedPeers.end(); ) {
        if (!it.value().permanent)
            it = m_bannedPeers.erase(it);
        else
            ++it;
    }
}

bool TorrentSessionManager::matchAutoBanRule(const libtorrent::peer_info &peer, const QString &client,
                                             const QString &countryCode, QString *reason) const {
    if (!countryCode.trimmed().isEmpty()
        && m_blockedPeerCountries.contains(countryCode.trimmed().toUpper())) {
        if (reason) *reason = QStringLiteral("Blocked country");
        return true;
    }
    if (containsSubstringRule(m_blockedPeerUserAgentTerms, client)) {
        if (reason) *reason = QStringLiteral("Blocked user agent");
        return true;
    }
    if (m_autoBanAbusivePeers && matchesAbusivePeerPreset(peer, client, countryCode)) {
        if (reason) *reason = QStringLiteral("Auto-banned abusive peer client");
        return true;
    }
    if (m_autoBanMediaPlayerPeers && matchesMediaPlayerPreset(peer, client)) {
        if (reason) *reason = QStringLiteral("Auto-banned media player peer");
        return true;
    }
    return false;
}

void TorrentSessionManager::configureSession(const AppSettings *settings) {
    if (!m_session || !settings)
        return;

    libtorrent::settings_pack pack;

    // Enable the alert categories needed for progress, metadata, peer lists,
    // file renames, and error reporting. The libtorrent default is
    // alert_category::error only — without status the metadata dialog never
    // receives metadata_received_alert or state_update_alert.
    const auto alertMask = libtorrent::alert_category::error
                         | libtorrent::alert_category::status
                         | libtorrent::alert_category::storage
                         | libtorrent::alert_category::tracker;
    pack.set_int(libtorrent::settings_pack::alert_mask,
                 static_cast<int>(static_cast<std::uint32_t>(alertMask)));

    pack.set_bool(libtorrent::settings_pack::enable_dht, settings->torrentEnableDht());
    pack.set_bool(libtorrent::settings_pack::enable_lsd, settings->torrentEnableLsd());
    pack.set_bool(libtorrent::settings_pack::enable_upnp, settings->torrentEnableUpnp());
    pack.set_bool(libtorrent::settings_pack::enable_natpmp, settings->torrentEnableNatPmp());
    pack.set_int(libtorrent::settings_pack::connections_limit, settings->torrentConnectionsLimit());
    const int effectiveDownloadLimitKBps = settings->globalSpeedLimitKBps() > 0
        ? settings->globalSpeedLimitKBps()
        : 0;
    pack.set_int(libtorrent::settings_pack::download_rate_limit, effectiveDownloadLimitKBps * 1024);
    const int effectiveUploadLimitKBps = settings->globalUploadLimitKBps() > 0
        ? settings->globalUploadLimitKBps()
        : 0;
    pack.set_int(libtorrent::settings_pack::upload_rate_limit, effectiveUploadLimitKBps * 1024);
    const QString userAgent = defaultTorrentUserAgent(settings);
    pack.set_str(libtorrent::settings_pack::user_agent, userAgent.toStdString());
    // Azureus-style peer ID prefix: -SL<major><minor><patch>- followed by random bytes
    // generated by libtorrent. 'SL' is the Stellar client code; version digits come from
    // the CMake project version so this never needs manual updating.
    {
        char fp[10];
        std::snprintf(fp, sizeof(fp), "-SL%02d%02d-",
                      STELLAR_VERSION_MAJOR * 10 + STELLAR_VERSION_MINOR,
                      STELLAR_VERSION_PATCH);
        pack.set_str(libtorrent::settings_pack::peer_fingerprint, fp);
    }
    const QString bindTarget = settings->torrentBindInterface().trimmed();
    if (!bindTarget.isEmpty()) {
        const QNetworkInterface iface = findNetworkInterfaceForBinding(bindTarget);
        const QStringList bindAddresses = interfaceBindAddresses(iface);
        if (!bindAddresses.isEmpty()) {
            QStringList listenInterfaces;
            for (const QString &addressText : bindAddresses) {
                const QHostAddress address(addressText);
                if (address.isNull())
                    continue;
                listenInterfaces.push_back(formatListenInterface(address, settings->torrentListenPort()));
            }

            if (!listenInterfaces.isEmpty()) {
                pack.set_str(libtorrent::settings_pack::listen_interfaces,
                             listenInterfaces.join(QStringLiteral(",")).toStdString());
                pack.set_str(libtorrent::settings_pack::outgoing_interfaces,
                             bindAddresses.join(QStringLiteral(",")).toStdString());
            } else {
                pack.set_str(libtorrent::settings_pack::listen_interfaces,
                             QStringLiteral("0.0.0.0:%1,[::]:%1")
                                 .arg(settings->torrentListenPort())
                                 .toStdString());
                pack.set_str(libtorrent::settings_pack::outgoing_interfaces, std::string());
            }
        } else {
            pack.set_str(libtorrent::settings_pack::listen_interfaces,
                         QStringLiteral("0.0.0.0:%1,[::]:%1")
                             .arg(settings->torrentListenPort())
                             .toStdString());
            pack.set_str(libtorrent::settings_pack::outgoing_interfaces, std::string());
        }
    } else {
        pack.set_str(libtorrent::settings_pack::listen_interfaces,
                     QStringLiteral("0.0.0.0:%1,[::]:%1").arg(settings->torrentListenPort()).toStdString());
        pack.set_str(libtorrent::settings_pack::outgoing_interfaces, std::string());
    }
    // Apply proxy settings so tracker announces and peer connections are routed
    // through the same proxy the rest of the app uses.
    const int proxyType = settings->proxyType();
    if (proxyType == 0) {
        // No proxy — clear any previously configured proxy.
        pack.set_int(libtorrent::settings_pack::proxy_type,
                     libtorrent::settings_pack::none);
        pack.set_str(libtorrent::settings_pack::proxy_hostname, std::string());
        pack.set_int(libtorrent::settings_pack::proxy_port, 0);
        pack.set_str(libtorrent::settings_pack::proxy_username, std::string());
        pack.set_str(libtorrent::settings_pack::proxy_password, std::string());
        pack.set_bool(libtorrent::settings_pack::proxy_peer_connections,   false);
        pack.set_bool(libtorrent::settings_pack::proxy_tracker_connections,  false);
        pack.set_bool(libtorrent::settings_pack::proxy_hostnames,          false);
    } else if (proxyType == 1) {
        // System proxy — query Qt for the resolved proxy and forward it.
        const QNetworkProxyQuery q(QUrl(QStringLiteral("http://example.com")));
        const QList<QNetworkProxy> list = QNetworkProxyFactory::systemProxyForQuery(q);
        const QNetworkProxy &sys = (!list.isEmpty() && list.first().type() != QNetworkProxy::NoProxy)
                                   ? list.first()
                                   : QNetworkProxy(QNetworkProxy::NoProxy);
        if (sys.type() == QNetworkProxy::Socks5Proxy) {
            pack.set_int(libtorrent::settings_pack::proxy_type,
                         libtorrent::settings_pack::socks5);
        } else if (sys.type() == QNetworkProxy::HttpProxy) {
            pack.set_int(libtorrent::settings_pack::proxy_type,
                         libtorrent::settings_pack::http);
        } else {
            pack.set_int(libtorrent::settings_pack::proxy_type,
                         libtorrent::settings_pack::none);
        }
        if (sys.type() != QNetworkProxy::NoProxy) {
            pack.set_str(libtorrent::settings_pack::proxy_hostname,
                         sys.hostName().toStdString());
            pack.set_int(libtorrent::settings_pack::proxy_port, sys.port());
            pack.set_str(libtorrent::settings_pack::proxy_username,
                         sys.user().toStdString());
            pack.set_str(libtorrent::settings_pack::proxy_password,
                         sys.password().toStdString());
            pack.set_bool(libtorrent::settings_pack::proxy_peer_connections,  true);
            pack.set_bool(libtorrent::settings_pack::proxy_tracker_connections, true);
            pack.set_bool(libtorrent::settings_pack::proxy_hostnames,         true);
        } else {
            pack.set_bool(libtorrent::settings_pack::proxy_peer_connections,  false);
            pack.set_bool(libtorrent::settings_pack::proxy_tracker_connections, false);
            pack.set_bool(libtorrent::settings_pack::proxy_hostnames,         false);
        }
    } else {
        // Manual HTTP or SOCKS5 proxy.
        const int ltType = (proxyType == 3)
            ? (settings->proxyUsername().isEmpty()
               ? libtorrent::settings_pack::socks5
               : libtorrent::settings_pack::socks5_pw)
            : (settings->proxyUsername().isEmpty()
               ? libtorrent::settings_pack::http
               : libtorrent::settings_pack::http_pw);
        pack.set_int(libtorrent::settings_pack::proxy_type, ltType);
        pack.set_str(libtorrent::settings_pack::proxy_hostname,
                     settings->proxyHost().trimmed().toStdString());
        pack.set_int(libtorrent::settings_pack::proxy_port,
                     settings->proxyPort());
        pack.set_str(libtorrent::settings_pack::proxy_username,
                     settings->proxyUsername().toStdString());
        pack.set_str(libtorrent::settings_pack::proxy_password,
                     settings->proxyPassword().toStdString());
        // Route ALL libtorrent traffic through the proxy — peer connections,
        // tracker announces, and DNS lookups. Without these three flags,
        // libtorrent makes direct connections for most traffic even when a
        // proxy is configured, bypassing VPNs and leaking the real IP.
        pack.set_bool(libtorrent::settings_pack::proxy_peer_connections,  true);
        pack.set_bool(libtorrent::settings_pack::proxy_tracker_connections, true);
        pack.set_bool(libtorrent::settings_pack::proxy_hostnames,         true);
    }

    // Encryption mode: 0=Prefer (try encrypted, fall back to plaintext),
    // 1=Require (encrypted only, reject plaintext peers),
    // 2=Allow (plaintext preferred, encrypted accepted).
    {
        int ltPolicy;
        switch (settings->torrentEncryptionMode()) {
        case 1:  ltPolicy = libtorrent::settings_pack::pe_forced;   break; // Require
        case 2:  ltPolicy = libtorrent::settings_pack::pe_disabled; break; // Allow (no encryption preferred)
        default: ltPolicy = libtorrent::settings_pack::pe_enabled;  break; // Prefer (default)
        }
        pack.set_int(libtorrent::settings_pack::out_enc_policy, ltPolicy);
        pack.set_int(libtorrent::settings_pack::in_enc_policy,  ltPolicy);
        pack.set_int(libtorrent::settings_pack::allowed_enc_level,
                     libtorrent::settings_pack::pe_both);
    }

    m_session->apply_settings(pack);
}

QString TorrentSessionManager::idForHandle(const libtorrent::torrent_handle &handle) const {
    for (auto it = m_handles.constBegin(); it != m_handles.constEnd(); ++it) {
        if (it.value() == handle)
            return it.key();
    }
    return {};
}

bool TorrentSessionManager::addTorrentInternal(DownloadItem *item, bool startPaused, const QString &torrentFilePath) {
    if (!item)
        return false;

    ensureSession();
    if (!m_alertTimer.isActive())
        m_alertTimer.start();

    libtorrent::error_code ec;
    libtorrent::add_torrent_params params;

    const QByteArray resumeBlob = QByteArray::fromBase64(item->torrentResumeData().toLatin1());
    if (!resumeBlob.isEmpty()) {
        params = libtorrent::read_resume_data(asSpan(resumeBlob), ec);
        if (ec)
            params = libtorrent::add_torrent_params{};
    }

    if (params.save_path.empty())
        params.save_path = item->savePath().toStdString();
    params.flags |= libtorrent::torrent_flags::update_subscribe;
    params.flags &= ~libtorrent::torrent_flags::auto_managed;
    if (startPaused)
        params.flags |= libtorrent::torrent_flags::paused;
    else
        params.flags &= ~libtorrent::torrent_flags::paused;

    if (torrentFilePath.isEmpty()) {
        const QString magnetSource = normalizeTorrentUri(item->torrentSource());
        if (magnetSource != item->torrentSource())
            item->setTorrentSource(magnetSource);
        libtorrent::add_torrent_params magnetParams =
            libtorrent::parse_magnet_uri(magnetSource.toStdString(), ec);
        if (ec) {
            emit torrentErrored(item->id(), QString::fromStdString(ec.message()));
            return false;
        }
        mergeMagnetParams(params, magnetParams);
        params.save_path = item->savePath().toStdString();
        params.flags |= libtorrent::torrent_flags::update_subscribe;
        params.flags &= ~libtorrent::torrent_flags::auto_managed;
        if (startPaused)
            params.flags |= libtorrent::torrent_flags::paused;
        else
            params.flags &= ~libtorrent::torrent_flags::paused;
    } else if (!params.ti) {
        params.ti = std::make_shared<libtorrent::torrent_info>(torrentFilePath.toStdString(), ec);
        if (ec) {
            emit torrentErrored(item->id(), QString::fromStdString(ec.message()));
            return false;
        }
    }

    const libtorrent::torrent_handle handle = m_session->add_torrent(params, ec);
    if (ec || !handle.is_valid()) {
        emit torrentErrored(item->id(), ec ? QString::fromStdString(ec.message()) : QStringLiteral("Failed to add torrent"));
        return false;
    }

    // Apply stored per-torrent flags before registering the handle.
    if (item->torrentDisableDht())
        handle.set_flags(libtorrent::torrent_flags::disable_dht);
    if (item->torrentDisablePex())
        handle.set_flags(libtorrent::torrent_flags::disable_pex);
    if (item->torrentDisableLsd())
        handle.set_flags(libtorrent::torrent_flags::disable_lsd);

    m_handles[item->id()] = handle;
    m_items[item->id()] = item;
    if (startPaused)
        m_pausedIds.insert(item->id());
    else
        m_pausedIds.remove(item->id());
    if (!m_fileModels.contains(item->id()))
        m_fileModels[item->id()] = new TorrentFileModel(this);
    if (!m_peerModels.contains(item->id()))
        m_peerModels[item->id()] = new TorrentPeerModel(this);
    if (!m_trackerModels.contains(item->id()))
        m_trackerModels[item->id()] = new TorrentTrackerModel(this);

    const QStringList persistedTrackers = item->torrentTrackers();
    if (!persistedTrackers.isEmpty()) {
        std::vector<libtorrent::announce_entry> entries;
        entries.reserve(persistedTrackers.size());
        for (const QString &trackerUrl : persistedTrackers) {
            const QString trimmed = trackerUrl.trimmed();
            if (!trimmed.isEmpty())
                entries.emplace_back(trimmed.toStdString());
        }
        if (!entries.empty()) {
            handle.replace_trackers(entries);
            handle.post_trackers();
        }
    }

    item->setTorrentTrackers(trackerUrls(item->id()));
    item->setIsTorrent(true);
    item->setStatus(startPaused ? DownloadItem::Status::Paused : DownloadItem::Status::Checking);
    updateItemFromStatus(item, handle);
    return true;
}

void TorrentSessionManager::processAlerts() {
    if (!m_session)
        return;
    std::vector<libtorrent::alert *> alerts;
    m_session->pop_alerts(&alerts);
    for (libtorrent::alert *alert : alerts)
        handleAlert(alert);
}

void TorrentSessionManager::handleAlert(libtorrent::alert *alert) {
    if (!alert)
        return;

    if (auto *externalIp = libtorrent::alert_cast<libtorrent::external_ip_alert>(alert)) {
        setDetectedExternalAddress(QString::fromStdString(externalIp->external_address.to_string()));
        return;
    }

    if (auto *update = libtorrent::alert_cast<libtorrent::state_update_alert>(alert)) {
        for (const auto &status : update->status) {
            const QString id = idForHandle(status.handle);
            DownloadItem *item = m_items.value(id, nullptr).data();
            if (item) {
                updateItemFromStatus(item, status.handle);
                updateModels(id, status.handle);
            }
        }
        return;
    }

    if (auto *metadata = libtorrent::alert_cast<libtorrent::metadata_received_alert>(alert)) {
        const QString id = idForHandle(metadata->handle);
        DownloadItem *item = m_items.value(id, nullptr).data();
        if (item) {
            updateItemFromStatus(item, metadata->handle);
            updateModels(id, metadata->handle);
        }
        return;
    }

    if (auto *finished = libtorrent::alert_cast<libtorrent::torrent_finished_alert>(alert)) {
        const QString id = idForHandle(finished->handle);
        DownloadItem *item = m_items.value(id, nullptr).data();
        if (item) {
            item->setStatus(DownloadItem::Status::Seeding);
            updateItemFromStatus(item, finished->handle);
            updateModels(id, finished->handle);
        }
        emit torrentFinished(id);
        return;
    }

    if (auto *error = libtorrent::alert_cast<libtorrent::torrent_error_alert>(alert)) {
        emit torrentErrored(idForHandle(error->handle), QString::fromStdString(error->error.message()));
        return;
    }

    if (auto *resume = libtorrent::alert_cast<libtorrent::save_resume_data_alert>(alert)) {
        const QString id = idForHandle(resume->handle);
        DownloadItem *item = m_items.value(id, nullptr).data();
        if (item) {
            const auto buf = libtorrent::write_resume_data_buf(resume->params);
            const QByteArray encoded(buf.data(), static_cast<qsizetype>(buf.size()));
            item->setTorrentResumeData(QString::fromLatin1(encoded.toBase64()));
        }
        return;
    }

    if (auto *announce = libtorrent::alert_cast<libtorrent::tracker_announce_alert>(alert)) {
        const QString id = idForHandle(announce->handle);
        if (!id.isEmpty()) {
            TrackerAlertSnapshot snapshot;
            snapshot.status = QStringLiteral("Announcing");
            snapshot.message = QStringLiteral("Announce sent");
            snapshot.updatedAt = QDateTime::currentDateTimeUtc();
            m_trackerAlertSnapshots[id][trackerStatusKey(QString::fromUtf8(announce->tracker_url()))] = snapshot;
            updateModels(id, announce->handle);
        }
        return;
    }

    if (auto *reply = libtorrent::alert_cast<libtorrent::tracker_reply_alert>(alert)) {
        const QString id = idForHandle(reply->handle);
        if (!id.isEmpty()) {
            TrackerAlertSnapshot snapshot;
            snapshot.status = QStringLiteral("Working");
            snapshot.message = QStringLiteral("Tracker replied (%1 peers)").arg(reply->num_peers);
            snapshot.peers = std::max(0, reply->num_peers);
            snapshot.updatedAt = QDateTime::currentDateTimeUtc();
            m_trackerAlertSnapshots[id][trackerStatusKey(QString::fromUtf8(reply->tracker_url()))] = snapshot;
            updateModels(id, reply->handle);
        }
        return;
    }

    if (auto *warning = libtorrent::alert_cast<libtorrent::tracker_warning_alert>(alert)) {
        const QString id = idForHandle(warning->handle);
        if (!id.isEmpty()) {
            TrackerAlertSnapshot snapshot;
            snapshot.status = QStringLiteral("Warning");
            snapshot.message = QString::fromUtf8(warning->warning_message());
            snapshot.updatedAt = QDateTime::currentDateTimeUtc();
            m_trackerAlertSnapshots[id][trackerStatusKey(QString::fromUtf8(warning->tracker_url()))] = snapshot;
            updateModels(id, warning->handle);
        }
        return;
    }

    if (auto *trackerError = libtorrent::alert_cast<libtorrent::tracker_error_alert>(alert)) {
        const QString id = idForHandle(trackerError->handle);
        if (!id.isEmpty()) {
            TrackerAlertSnapshot snapshot;
            snapshot.status = QStringLiteral("Error");
            const QString reason = QString::fromUtf8(trackerError->failure_reason());
            snapshot.message = reason.isEmpty()
                ? QString::fromStdString(trackerError->error.message())
                : reason;
            snapshot.updatedAt = QDateTime::currentDateTimeUtc();
            m_trackerAlertSnapshots[id][trackerStatusKey(QString::fromUtf8(trackerError->tracker_url()))] = snapshot;
            updateModels(id, trackerError->handle);
        }
        return;
    }

    if (auto *scrapeReply = libtorrent::alert_cast<libtorrent::scrape_reply_alert>(alert)) {
        const QString id = idForHandle(scrapeReply->handle);
        if (!id.isEmpty()) {
            TrackerAlertSnapshot snapshot;
            snapshot.status = QStringLiteral("Working");
            snapshot.message = QStringLiteral("Scrape reply received");
            snapshot.seeders = std::max(0, scrapeReply->complete);
            snapshot.peers = std::max(0, scrapeReply->incomplete);
            snapshot.updatedAt = QDateTime::currentDateTimeUtc();
            m_trackerAlertSnapshots[id][trackerStatusKey(QString::fromUtf8(scrapeReply->tracker_url()))] = snapshot;
            updateModels(id, scrapeReply->handle);
        }
        return;
    }

    if (auto *scrapeFailed = libtorrent::alert_cast<libtorrent::scrape_failed_alert>(alert)) {
        const QString id = idForHandle(scrapeFailed->handle);
        if (!id.isEmpty()) {
            TrackerAlertSnapshot snapshot;
            snapshot.status = QStringLiteral("Error");
            const QString reason = QString::fromUtf8(scrapeFailed->error_message());
            snapshot.message = reason.isEmpty()
                ? QString::fromStdString(scrapeFailed->error.message())
                : reason;
            snapshot.updatedAt = QDateTime::currentDateTimeUtc();
            m_trackerAlertSnapshots[id][trackerStatusKey(QString::fromUtf8(scrapeFailed->tracker_url()))] = snapshot;
            updateModels(id, scrapeFailed->handle);
        }
        return;
    }

    if (auto *renamed = libtorrent::alert_cast<libtorrent::file_renamed_alert>(alert)) {
        const QString id = idForHandle(renamed->handle);
        auto *model = qobject_cast<TorrentFileModel *>(m_fileModels.value(id, nullptr));
        if (model && renamed->handle.is_valid() && renamed->handle.torrent_file()) {
            const auto ti = renamed->handle.torrent_file();
            const auto &files = ti->files();
            const auto priorities = renamed->handle.get_file_priorities();
            const std::vector<std::int64_t> progress = renamed->handle.file_progress(libtorrent::torrent_handle::piece_granularity);

            QVector<TorrentFileModel::Entry> entries;
            entries.reserve(files.num_files());
            for (int i = 0; i < files.num_files(); ++i) {
                TorrentFileModel::Entry entry;
                const auto fileIndex = libtorrent::file_index_t{i};
                entry.name = QString::fromStdString(std::string(files.file_name(fileIndex)));
                entry.path = QString::fromStdString(files.file_path(fileIndex));
                entry.size = files.file_size(fileIndex);
                entry.wanted = i < int(priorities.size()) ? priorities[std::size_t(i)] != libtorrent::dont_download : true;
                entry.fileIndex = i;
                entry.downloaded = i < int(progress.size()) ? qint64(progress[std::size_t(i)]) : 0;
                entries.push_back(entry);
            }
            model->setEntries(entries);
        }
        return;
    }
}

void TorrentSessionManager::updateModels(const QString &downloadId, const libtorrent::torrent_handle &handle, bool forceTrackerUpdate) {
    if (!handle.is_valid())
        return;

    auto *fileModel = qobject_cast<TorrentFileModel *>(m_fileModels.value(downloadId, nullptr));
    if (fileModel && handle.torrent_file()) {
        const auto ti = handle.torrent_file();
        const auto &files = ti->files();

        if (fileModel->rowCount() != files.num_files()) {
            const auto priorities = handle.get_file_priorities();
            QVector<TorrentFileModel::Entry> entries;
            entries.reserve(files.num_files());
            for (int i = 0; i < files.num_files(); ++i) {
                TorrentFileModel::Entry entry;
                const auto fileIndex = libtorrent::file_index_t{i};
                entry.name = QString::fromStdString(std::string(files.file_name(fileIndex)));
                entry.path = QString::fromStdString(files.file_path(fileIndex));
                entry.size = files.file_size(fileIndex);
                entry.wanted = i < int(priorities.size()) ? priorities[std::size_t(i)] != libtorrent::dont_download : true;
                entry.fileIndex = i;
                entries.push_back(entry);
            }
            fileModel->setEntries(entries);
        }

        const std::vector<std::int64_t> progress = handle.file_progress(libtorrent::torrent_handle::piece_granularity);
        QVector<qint64> downloaded;
        downloaded.reserve(int(progress.size()));
        for (std::int64_t value : progress)
            downloaded.push_back(value);
        fileModel->updateProgress(downloaded);
    }

    if (m_pausedIds.contains(downloadId)
        || (handle.flags() & libtorrent::torrent_flags::paused) != libtorrent::torrent_flags_t{}) {
        if (auto *peerModel = qobject_cast<TorrentPeerModel *>(m_peerModels.value(downloadId, nullptr))) {
            peerModel->setLocalLocation(m_hasLocalCoordinates, m_localLatitude, m_localLongitude);
            if (!m_externalAddress.isEmpty()) {
                const int listenPort = m_session ? m_session->listen_port() : 0;
                peerModel->setLocalInfo(m_externalAddress, listenPort, m_localCountryCode,
                                        m_localRegionName, m_localCityName,
                                        defaultTorrentUserAgent(m_settings));
            }
            peerModel->setEntries({});
        }
        return;
    }

    auto *peerModel = qobject_cast<TorrentPeerModel *>(m_peerModels.value(downloadId, nullptr));
    if (peerModel) {
        peerModel->setLocalLocation(m_hasLocalCoordinates, m_localLatitude, m_localLongitude);
        if (!m_externalAddress.isEmpty()) {
            const int listenPort = m_session ? m_session->listen_port() : 0;
            peerModel->setLocalInfo(m_externalAddress, listenPort, m_localCountryCode,
                                    m_localRegionName, m_localCityName,
                                    defaultTorrentUserAgent(m_settings));
        }
        if (!peerModel->liveUpdatesEnabled())
            peerModel = nullptr;
    }

    int dhtPeerCount = 0;
    int dhtSeederCount = 0;
    int pexPeerCount = 0;
    int pexSeederCount = 0;
    int lsdPeerCount = 0;
    int lsdSeederCount = 0;
    const bool shouldInspectPeers = peerModel
        || !m_manualBannedPeers.isEmpty()
        || !m_blockedPeerUserAgentTerms.isEmpty()
        || !m_blockedPeerCountries.isEmpty()
        || m_autoBanAbusivePeers
        || m_autoBanMediaPlayerPeers;
    std::vector<libtorrent::peer_info> peerInfos;
    if (shouldInspectPeers)
        handle.get_peer_info(peerInfos);
    if (shouldInspectPeers) {
        QVector<TorrentPeerModel::Entry> entries;
        entries.reserve(int(peerInfos.size()));
        bool anyBanChanged = false;
        for (const auto &peer : peerInfos) {
            TorrentPeerModel::Entry entry;
            entry.endpoint = QString::fromStdString(peer.ip.address().to_string());
            entry.port = peer.ip.port();
            entry.client = QString::fromStdString(peer.client);
            entry.progress = peer.progress;
            entry.downSpeed = peer.payload_down_speed;
            entry.upSpeed = peer.payload_up_speed;
            entry.downloaded = static_cast<qint64>(peer.total_download);
            entry.uploaded = static_cast<qint64>(peer.total_upload);
            entry.rtt = peer.rtt;
            entry.isSeed = (peer.flags & libtorrent::peer_info::seed) != libtorrent::peer_flags_t{};

            // Build flags string
            {
                QStringList fl;
                // Connection direction
                if ((peer.flags & libtorrent::peer_info::local_connection) != libtorrent::peer_flags_t{})
                    fl << QStringLiteral("OUT");
                else
                    fl << QStringLiteral("IN");
                // Sources
                if ((peer.source & libtorrent::peer_info::tracker) != libtorrent::peer_source_flags_t{})
                    fl << QStringLiteral("TRK");
                if ((peer.source & libtorrent::peer_info::dht) != libtorrent::peer_source_flags_t{})
                    fl << QStringLiteral("DHT");
                if ((peer.source & libtorrent::peer_info::pex) != libtorrent::peer_source_flags_t{})
                    fl << QStringLiteral("PEX");
                if ((peer.source & libtorrent::peer_info::lsd) != libtorrent::peer_source_flags_t{})
                    fl << QStringLiteral("LSD");
                // Transport / encryption
                if ((peer.flags & libtorrent::peer_info::utp_socket) != libtorrent::peer_flags_t{})
                    fl << QStringLiteral("UTP");
                if ((peer.flags & libtorrent::peer_info::rc4_encrypted) != libtorrent::peer_flags_t{}
                    || (peer.flags & libtorrent::peer_info::plaintext_encrypted) != libtorrent::peer_flags_t{})
                    fl << QStringLiteral("ENC");
                // Peer state
                if ((peer.flags & libtorrent::peer_info::snubbed) != libtorrent::peer_flags_t{})
                    fl << QStringLiteral("SNB");
                if ((peer.flags & libtorrent::peer_info::upload_only) != libtorrent::peer_flags_t{})
                    fl << QStringLiteral("UPO");
                if ((peer.flags & libtorrent::peer_info::optimistic_unchoke) != libtorrent::peer_flags_t{})
                    fl << QStringLiteral("OPT");
                if ((peer.flags & libtorrent::peer_info::holepunched) != libtorrent::peer_flags_t{})
                    fl << QStringLiteral("HPX");
                if ((peer.flags & libtorrent::peer_info::i2p_socket) != libtorrent::peer_flags_t{})
                    fl << QStringLiteral("I2P");
                entry.flags = fl.join(QLatin1Char(' '));
            }

            if ((peer.source & libtorrent::peer_info::tracker) != libtorrent::peer_source_flags_t{})
                entry.source = QStringLiteral("Tracker");
            else if ((peer.source & libtorrent::peer_info::dht) != libtorrent::peer_source_flags_t{})
                entry.source = QStringLiteral("DHT");
            else if ((peer.source & libtorrent::peer_info::pex) != libtorrent::peer_source_flags_t{})
                entry.source = QStringLiteral("PeX");
            else if ((peer.source & libtorrent::peer_info::lsd) != libtorrent::peer_source_flags_t{})
                entry.source = QStringLiteral("LSD");
            else
                entry.source = QStringLiteral("Peer");
            lookupPeerLocation(entry.endpoint, &entry.countryCode, &entry.regionCode, &entry.regionName,
                               &entry.cityName, &entry.latitude, &entry.longitude);

            entry.endpoint = normalizePeerEndpoint(entry.endpoint);
            const QString normalizedCountry = entry.countryCode.trimmed().toUpper();
            entry.countryCode = normalizedCountry;

            if (!entry.endpoint.isEmpty() && m_manualBannedPeers.contains(entry.endpoint)) {
                if (!m_bannedPeers.contains(entry.endpoint) || !m_bannedPeers.value(entry.endpoint).permanent) {
                    BannedPeer banned;
                    banned.endpoint = entry.endpoint;
                    banned.client = entry.client;
                    banned.countryCode = normalizedCountry;
                    banned.reason = QStringLiteral("Manually banned");
                    banned.permanent = true;
                    m_bannedPeers.insert(entry.endpoint, banned);
                    anyBanChanged = true;
                }
                continue;
            }

            QString autoBanReason;
            if (matchAutoBanRule(peer, entry.client, normalizedCountry, &autoBanReason)) {
                setTemporaryPeerBan(entry.endpoint, entry.client, normalizedCountry, autoBanReason);
                anyBanChanged = true;
                continue;
            }

            entries.push_back(entry);
            if ((peer.source & libtorrent::peer_info::dht) != libtorrent::peer_source_flags_t{}) {
                ++dhtPeerCount;
                if (entry.isSeed)
                    ++dhtSeederCount;
            }
            if ((peer.source & libtorrent::peer_info::pex) != libtorrent::peer_source_flags_t{}) {
                ++pexPeerCount;
                if (entry.isSeed)
                    ++pexSeederCount;
            }
            if ((peer.source & libtorrent::peer_info::lsd) != libtorrent::peer_source_flags_t{}) {
                ++lsdPeerCount;
                if (entry.isSeed)
                    ++lsdSeederCount;
            }
        }
        if (peerModel)
            peerModel->setEntries(entries);

        DownloadItem *modelItem = m_items.value(downloadId, nullptr).data();
        if (modelItem && !modelItem->torrentHasMetadata()) {
            const int connectedPeerCount = int(entries.size());
            const int metadataPeerCount = std::max({connectedPeerCount,
                                                    dhtPeerCount,
                                                    pexPeerCount,
                                                    lsdPeerCount,
                                                    modelItem->torrentPeers(),
                                                    modelItem->torrentListPeers()});
            modelItem->setTorrentPeers(metadataPeerCount);
        }
        if (anyBanChanged)
            emit bannedPeersChanged();
    }

    // Tracker models are notably heavier because they also resolve and
    // geo-locate tracker endpoints, so keep those on the slower cadence
    // without penalizing the peer list refresh rate.
    // forceTrackerUpdate bypasses the cadence gate (e.g. after a manual reannounce
    // so the status change is visible immediately rather than up to 3s later).
    if (!forceTrackerUpdate && m_modelTick % 3 != 0)
        return;

    if (auto *trackerModel = qobject_cast<TorrentTrackerModel *>(m_trackerModels.value(downloadId, nullptr))) {
        const auto trackers = handle.trackers();
        QVector<TorrentTrackerModel::Entry> trackerEntries;
        trackerEntries.reserve(int(trackers.size()) + 3);

        TorrentTrackerModel::Entry dhtEntry;
        dhtEntry.url = QStringLiteral("Distributed Hash Table (DHT)");
        dhtEntry.status = QStringLiteral("Peer discovery");
        dhtEntry.tier = -1;
        dhtEntry.source = QStringLiteral("DHT");
        dhtEntry.peers = dhtPeerCount;
        dhtEntry.seeders = dhtSeederCount;
        dhtEntry.systemEntry = true;
        dhtEntry.message = QStringLiteral("Live connected peers discovered via DHT");
        trackerEntries.push_back(dhtEntry);

        TorrentTrackerModel::Entry pexEntry;
        pexEntry.url = QStringLiteral("Peer Exchange (PeX)");
        pexEntry.status = QStringLiteral("Peer discovery");
        pexEntry.tier = -1;
        pexEntry.source = QStringLiteral("PeX");
        pexEntry.peers = pexPeerCount;
        pexEntry.seeders = pexSeederCount;
        pexEntry.systemEntry = true;
        pexEntry.message = QStringLiteral("Live connected peers discovered via peer exchange");
        trackerEntries.push_back(pexEntry);

        TorrentTrackerModel::Entry lsdEntry;
        lsdEntry.url = QStringLiteral("Local Service Discovery (LSD)");
        lsdEntry.status = QStringLiteral("Peer discovery");
        lsdEntry.tier = -1;
        lsdEntry.source = QStringLiteral("LSD");
        lsdEntry.peers = lsdPeerCount;
        lsdEntry.seeders = lsdSeederCount;
        lsdEntry.systemEntry = true;
        lsdEntry.message = QStringLiteral("Live connected peers discovered on the local network");
        trackerEntries.push_back(lsdEntry);

        for (const auto &tracker : trackers) {
            TorrentTrackerModel::Entry entry;
            entry.url = QString::fromStdString(tracker.url);
            entry.tier = tracker.tier;
            entry.source = QStringLiteral("Tracker");
            entry.systemEntry = false;
            const QDateTime nowUtc = QDateTime::currentDateTimeUtc();
            const QString trackerKey = trackerStatusKey(entry.url);
            const QDateTime reannounceUntil =
                m_trackerReannounceUntil.value(downloadId).value(trackerKey);
            const bool reannouncePending = reannounceUntil.isValid() && nowUtc < reannounceUntil;
            QString endpointMessage;
            QString endpointError;
            bool anyUpdating = false;
            bool anyStarted = false;
            bool anyCompleted = false;
            bool anyFailures = false;
            for (const auto &endpoint : tracker.endpoints) {
                for (const auto &infohash : endpoint.info_hashes) {
                    anyUpdating = anyUpdating || infohash.updating;
                    anyStarted = anyStarted || infohash.start_sent;
                    anyCompleted = anyCompleted || infohash.complete_sent;
                    anyFailures = anyFailures || (infohash.fails > 0);
                    if (endpointMessage.isEmpty() && !infohash.message.empty())
                        endpointMessage = QString::fromStdString(infohash.message);
                    if (endpointError.isEmpty() && infohash.last_error)
                        endpointError = QString::fromStdString(infohash.last_error.message());
                    if (!endpointMessage.isEmpty() && !endpointError.isEmpty())
                        break;
                }
                if (!endpointMessage.isEmpty() && !endpointError.isEmpty())
                    break;
            }
            if (!endpointError.isEmpty()) {
                entry.status = QStringLiteral("Error");
                entry.message = endpointError;
            } else if (anyUpdating) {
                entry.status = QStringLiteral("Announcing");
                entry.message = endpointMessage;
            } else if (tracker.verified) {
                entry.status = QStringLiteral("Working");
                entry.message = endpointMessage;
            } else if (anyStarted || anyCompleted) {
                entry.status = QStringLiteral("Working");
                entry.message = endpointMessage;
            } else if (anyFailures) {
                entry.status = QStringLiteral("Error");
                entry.message = endpointMessage;
            } else if (!endpointMessage.isEmpty()) {
                entry.status = QStringLiteral("Announcing");
                entry.message = endpointMessage;
            } else if (reannouncePending) {
                entry.status = QStringLiteral("Reannouncing");
                entry.message = QStringLiteral("Reannounce requested, waiting for tracker response");
            } else {
                entry.status = QStringLiteral("Idle");
            }

            if (const auto *infohash = firstTrackerInfohash(tracker)) {
                entry.seeders = infohash->scrape_complete >= 0 ? infohash->scrape_complete : 0;
                entry.peers = infohash->scrape_incomplete >= 0 ? infohash->scrape_incomplete : 0;
                if (entry.message.isEmpty())
                    entry.message = QString::fromStdString(infohash->message);
            }

            const TrackerAlertSnapshot snapshot =
                m_trackerAlertSnapshots.value(downloadId).value(trackerKey);
            if (snapshot.updatedAt.isValid()
                && snapshot.updatedAt.secsTo(QDateTime::currentDateTimeUtc()) <= 120) {
                if (!snapshot.status.isEmpty())
                    entry.status = snapshot.status;
                if (!snapshot.message.isEmpty())
                    entry.message = snapshot.message;
                if (snapshot.seeders >= 0)
                    entry.seeders = snapshot.seeders;
                if (snapshot.peers >= 0)
                    entry.peers = snapshot.peers;
            }

            // Geo-locate tracker hostname
            const QString hostname = QUrl(entry.url).host();
            if (!hostname.isEmpty()) {
                if (m_trackerIpCache.contains(hostname)) {
                    const QString &ip = m_trackerIpCache[hostname];
                    QString cc, rc, rn, cn;
                    lookupPeerLocation(ip, &cc, &rc, &rn, &cn, &entry.latitude, &entry.longitude);
                    entry.countryCode = cc;
                } else {
                    // Async resolve; geo data will appear on the next refresh cycle
                    QHostInfo::lookupHost(hostname, this, [this, hostname](const QHostInfo &info) {
                        if (info.error() == QHostInfo::NoError && !info.addresses().isEmpty())
                            m_trackerIpCache[hostname] = info.addresses().first().toString();
                    });
                }
            }

            trackerEntries.push_back(entry);
        }
        trackerModel->setEntries(trackerEntries);
    } else if (auto *trackerModel = qobject_cast<TorrentTrackerModel *>(m_trackerModels.value(downloadId, nullptr))) {
        trackerModel->setEntries({});
    }
}

void TorrentSessionManager::ensureGeoDb() {
    if (m_geoDb && m_geoDb->attempted)
        return;

    if (!m_geoDb)
        m_geoDb = std::make_unique<GeoDbState>();
    m_geoDb->attempted = true;

#if defined(STELLAR_HAS_MAXMINDDB)
    const QStringList candidates = geoDbCandidates();

    for (const QString &candidate : candidates) {
        if (!QFileInfo::exists(candidate))
            continue;
        if (MMDB_open(candidate.toUtf8().constData(), MMDB_MODE_MMAP, &m_geoDb->db) == MMDB_SUCCESS) {
            m_geoDb->open = true;
            m_geoDb->path = candidate;
            return;
        }
    }
#endif
}

QVariantMap TorrentSessionManager::geoDatabaseInfo() {
    QVariantMap info;
    ensureGeoDb();

    QString path;
    bool loaded = false;
    qulonglong entryCount = 0;

#if defined(STELLAR_HAS_MAXMINDDB)
    if (m_geoDb && m_geoDb->open) {
        path = m_geoDb->path;
        loaded = true;
        entryCount = static_cast<qulonglong>(m_geoDb->db.metadata.node_count);
    }
#endif

    if (path.isEmpty()) {
        const QStringList candidates = geoDbCandidates();
        for (const QString &candidate : candidates) {
            if (QFileInfo::exists(candidate)) {
                path = candidate;
                break;
            }
        }
    }

    const QFileInfo fi(path);
    info.insert(QStringLiteral("path"), path);
    info.insert(QStringLiteral("exists"), fi.exists());
    info.insert(QStringLiteral("loaded"), loaded);
    info.insert(QStringLiteral("sizeBytes"), static_cast<qulonglong>(fi.exists() ? fi.size() : 0));
    info.insert(QStringLiteral("lastModified"), fi.exists() ? fi.lastModified().toString(Qt::ISODate) : QString());
    info.insert(QStringLiteral("entryCount"), entryCount);
    return info;
}

void TorrentSessionManager::releaseGeoDatabaseForUpdate() {
#if defined(STELLAR_HAS_LIBTORRENT)
    if (!m_geoDb)
        return;
#if defined(STELLAR_HAS_MAXMINDDB)
    if (m_geoDb->open)
        MMDB_close(&m_geoDb->db);
#endif
    m_geoDb->open = false;
    m_geoDb->attempted = false;
    m_geoDb->path.clear();
    m_geoDb->cache.clear();
#endif
}

void TorrentSessionManager::lookupPeerLocation(const QString &endpoint, QString *countryCode,
                                               QString *regionCode, QString *regionName, QString *cityName,
                                               double *latitude, double *longitude) {
    if (countryCode)
        countryCode->clear();
    if (regionCode)
        regionCode->clear();
    if (regionName)
        regionName->clear();
    if (cityName)
        cityName->clear();
    if (latitude)
        *latitude = 0.0;
    if (longitude)
        *longitude = 0.0;

    ensureGeoDb();
    if (!m_geoDb || !m_geoDb->open)
        return;

    const QString ip = QHostAddress(endpoint).toString();
    if (ip.isEmpty())
        return;

    const auto cached = m_geoDb->cache.constFind(ip);
    if (cached != m_geoDb->cache.constEnd()) {
        if (countryCode)
            *countryCode = cached.value().countryCode;
        if (regionCode)
            *regionCode = cached.value().regionCode;
        if (regionName)
            *regionName = cached.value().regionName;
        if (cityName)
            *cityName = cached.value().cityName;
        if (latitude)
            *latitude = cached.value().latitude;
        if (longitude)
            *longitude = cached.value().longitude;
        return;
    }

#if defined(STELLAR_HAS_MAXMINDDB)
    int gaiError = 0;
    int mmdbError = MMDB_SUCCESS;
    const MMDB_lookup_result_s result =
        MMDB_lookup_string(&m_geoDb->db, ip.toUtf8().constData(), &gaiError, &mmdbError);

    PeerLocation resolved;
    if (gaiError == 0 && mmdbError == MMDB_SUCCESS && result.found_entry) {
        MMDB_entry_s entry = result.entry;
        static const char *const countryPath[] = { "country", "iso_code", nullptr };
        static const char *const regionCodePath[] = { "subdivisions", "0", "iso_code", nullptr };
        static const char *const regionNamePath[] = { "subdivisions", "0", "names", "en", nullptr };
        static const char *const cityPath[] = { "city", "names", "en", nullptr };
        static const char *const latitudePath[] = { "location", "latitude", nullptr };
        static const char *const longitudePath[] = { "location", "longitude", nullptr };
        resolved.countryCode = mmdbString(&entry, countryPath);
        resolved.regionCode = mmdbString(&entry, regionCodePath);
        resolved.regionName = mmdbString(&entry, regionNamePath);
        resolved.cityName = mmdbString(&entry, cityPath);
        MMDB_entry_data_s coordData;
        if (MMDB_aget_value(&entry, &coordData, latitudePath) == MMDB_SUCCESS && coordData.has_data
            && (coordData.type == MMDB_DATA_TYPE_DOUBLE || coordData.type == MMDB_DATA_TYPE_FLOAT)) {
            resolved.latitude = coordData.type == MMDB_DATA_TYPE_DOUBLE ? coordData.double_value : coordData.float_value;
            resolved.hasCoordinates = true;
        }
        if (MMDB_aget_value(&entry, &coordData, longitudePath) == MMDB_SUCCESS && coordData.has_data
            && (coordData.type == MMDB_DATA_TYPE_DOUBLE || coordData.type == MMDB_DATA_TYPE_FLOAT)) {
            resolved.longitude = coordData.type == MMDB_DATA_TYPE_DOUBLE ? coordData.double_value : coordData.float_value;
            resolved.hasCoordinates = resolved.hasCoordinates || true;
        }
    }

    m_geoDb->cache.insert(ip, resolved);
    if (countryCode)
        *countryCode = resolved.countryCode;
    if (regionCode)
        *regionCode = resolved.regionCode;
    if (regionName)
        *regionName = resolved.regionName;
    if (cityName)
        *cityName = resolved.cityName;
    if (latitude)
        *latitude = resolved.latitude;
    if (longitude)
        *longitude = resolved.longitude;
#else
    Q_UNUSED(ip);
#endif
}

void TorrentSessionManager::updateItemFromStatus(DownloadItem *item, const libtorrent::torrent_handle &handle) {
    if (!item || !handle.is_valid())
        return;

    const libtorrent::torrent_status st = handle.status();
    item->setTorrentHasMetadata(st.has_metadata);
    if (st.has_metadata && handle.torrent_file()) {
        const auto ti = handle.torrent_file();
        const QString torrentName = QString::fromStdString(ti->name());
        if (!torrentName.isEmpty())
            item->setFilename(torrentName);
        const auto bestHash = ti->info_hashes().get_best();
        item->setTorrentInfoHash(toHexString(bestHash.to_string()));
        item->setTorrentIsSingleFile(ti->num_files() == 1);
        item->setTorrentIsPrivate(ti->priv());
    }

    // Reflect per-torrent flag state so the UI stays in sync with libtorrent.
    const auto flags = handle.flags();
    item->setTorrentDisableDht(
        (flags & libtorrent::torrent_flags::disable_dht) != libtorrent::torrent_flags_t{});
    item->setTorrentDisablePex(
        (flags & libtorrent::torrent_flags::disable_pex) != libtorrent::torrent_flags_t{});
    item->setTorrentDisableLsd(
        (flags & libtorrent::torrent_flags::disable_lsd) != libtorrent::torrent_flags_t{});

    if (st.errc)
        item->setErrorString(QString::fromStdString(st.errc.message()));
    item->setTotalBytes(st.total_wanted > 0 ? st.total_wanted : item->totalBytes());
    item->setDoneBytes(st.total_wanted_done);
    item->setSpeed(st.download_payload_rate);
    item->setTorrentUploadSpeed(st.upload_payload_rate);
    item->setTorrentSeeders(st.num_seeds);
    item->setTorrentListSeeders(st.list_seeds);
    item->setTorrentPeers(st.num_peers);
    item->setTorrentListPeers(st.list_peers);
    item->setTorrentUploaded(st.all_time_upload);
    item->setTorrentDownloaded(st.all_time_download);
    item->setTorrentRatio(st.all_time_download > 0
                              ? double(st.all_time_upload) / double(st.all_time_download)
                              : 0.0);
    item->setTorrentAvailability(st.distributed_copies);
    item->setTorrentPiecesDone(st.num_pieces);
    // Total pieces only knowable once torrent metadata has arrived
    item->setTorrentPiecesTotal(
        (st.has_metadata && handle.torrent_file())
            ? handle.torrent_file()->num_pieces() : 0);
    item->setTorrentActiveTimeSecs(static_cast<qint64>(st.active_duration.count()));
    item->setTorrentSeedingTimeSecs(static_cast<qint64>(st.seeding_duration.count()));
    item->setTorrentWastedBytes(st.total_failed_bytes + st.total_redundant_bytes);
    item->setTorrentConnections(st.num_connections);

    const QString id = item->id();
    if (m_movingIds.contains(id)) {
        if (st.moving_storage) {
            item->setStatus(DownloadItem::Status::Moving);
            return;
        }
        m_movingIds.remove(id);
    }
    if (st.errc) {
        item->setStatus(DownloadItem::Status::Error);
    } else if (m_pausedIds.contains(id)
        || (handle.flags() & libtorrent::torrent_flags::paused) != libtorrent::torrent_flags_t{}) {
        item->setStatus(DownloadItem::Status::Paused);
    } else if (st.is_seeding || st.state == libtorrent::torrent_status::finished) {
        item->setStatus(DownloadItem::Status::Seeding);
        if (!m_seedingStartTimes.contains(id)) {
            m_seedingStartTimes[id] = QDateTime::currentDateTimeUtc();
            m_lastUploadActivityTime[id] = QDateTime::currentDateTimeUtc();
        }
        checkShareLimits(id, item, m_settings);
    } else if (st.state == libtorrent::torrent_status::checking_resume_data
               || st.state == libtorrent::torrent_status::checking_files) {
        item->setStatus(DownloadItem::Status::Checking);
    } else {
        item->setStatus(DownloadItem::Status::Downloading);
    }

    const QDateTime now = QDateTime::currentDateTimeUtc();
    const QDateTime lastSave = m_lastResumeSaveRequest.value(id);
    if ((!lastSave.isValid() || lastSave.secsTo(now) >= 60)
        && item->statusEnum() != DownloadItem::Status::Error) {
        handle.save_resume_data(libtorrent::torrent_handle::save_info_dict);
        m_lastResumeSaveRequest[id] = now;
    }
}

void TorrentSessionManager::setPerTorrentDownloadLimit(const QString &downloadId, int kbps) {
    const auto handle = m_handles.value(downloadId);
    if (handle.is_valid())
        handle.set_download_limit(kbps > 0 ? kbps * 1024 : -1);
}

void TorrentSessionManager::setPerTorrentUploadLimit(const QString &downloadId, int kbps) {
    const auto handle = m_handles.value(downloadId);
    if (handle.is_valid())
        handle.set_upload_limit(kbps > 0 ? kbps * 1024 : -1);
}

bool TorrentSessionManager::moveStorage(const QString &downloadId, const QString &newSavePath) {
#if defined(STELLAR_HAS_LIBTORRENT)
    const auto handle = m_handles.value(downloadId);
    if (!handle.is_valid() || newSavePath.trimmed().isEmpty())
        return false;
    m_movingIds.insert(downloadId);
    if (auto *item = m_items.value(downloadId, nullptr).data())
        item->setStatus(DownloadItem::Status::Moving);
    handle.move_storage(newSavePath.trimmed().toStdString());
    return true;
#else
    Q_UNUSED(downloadId); Q_UNUSED(newSavePath);
    return false;
#endif
}

bool TorrentSessionManager::renameTorrentFile(const QString &downloadId, int fileIndex, const QString &newName) {
#if defined(STELLAR_HAS_LIBTORRENT)
    const auto handle = m_handles.value(downloadId);
    if (!handle.is_valid() || fileIndex < 0)
        return false;
    const QString trimmed = newName.trimmed();
    if (trimmed.isEmpty())
        return false;

    if (!handle.torrent_file())
        return false;
    const auto ti = handle.torrent_file();
    const auto &files = ti->files();
    if (fileIndex >= files.num_files())
        return false;

    QString currentPath =
        QString::fromStdString(files.file_path(libtorrent::file_index_t{fileIndex}));
    currentPath.replace(QLatin1Char('\\'), QLatin1Char('/'));
    if (currentPath.trimmed().isEmpty())
        return false;

    // Replace only the last path component.
    const int sep = currentPath.lastIndexOf(QLatin1Char('/'));
    const QString newPath = (sep >= 0) ? currentPath.left(sep + 1) + trimmed : trimmed;

    // Tell libtorrent to rename the file; the model is updated optimistically.
    handle.rename_file(libtorrent::file_index_t{fileIndex}, newPath.toStdString());
    saveResumeData(downloadId);
    return true;
#else
    Q_UNUSED(downloadId); Q_UNUSED(fileIndex); Q_UNUSED(newName);
    return false;
#endif
}

bool TorrentSessionManager::renameTorrentPath(const QString &downloadId, const QString &currentPath, const QString &newName) {
#if defined(STELLAR_HAS_LIBTORRENT)
    const auto handle = m_handles.value(downloadId);
    if (!handle.is_valid() || !handle.torrent_file())
        return false;

    QString trimmedPath = currentPath.trimmed();
    trimmedPath.replace(QLatin1Char('\\'), QLatin1Char('/'));
    const QString trimmedName = newName.trimmed();
    if (trimmedPath.isEmpty() || trimmedName.isEmpty())
        return false;

    const int sep = trimmedPath.lastIndexOf(QLatin1Char('/'));
    const QString renamedBasePath = (sep >= 0) ? trimmedPath.left(sep + 1) + trimmedName : trimmedName;
    const QString folderPrefix = trimmedPath + QLatin1Char('/');

    bool renamedAny = false;
    const auto ti = handle.torrent_file();
    const auto &files = ti->files();
    for (int i = 0; i < files.num_files(); ++i) {
        QString sourcePath =
            QString::fromStdString(files.file_path(libtorrent::file_index_t{i}));
        sourcePath.replace(QLatin1Char('\\'), QLatin1Char('/'));
        if (sourcePath.isEmpty())
            continue;

        QString targetPath;
        if (sourcePath == trimmedPath) {
            targetPath = renamedBasePath;
        } else if (sourcePath.startsWith(folderPrefix)) {
            targetPath = renamedBasePath + sourcePath.mid(trimmedPath.size());
        } else {
            continue;
        }

        handle.rename_file(libtorrent::file_index_t{i}, targetPath.toStdString());
        renamedAny = true;
    }

    if (!renamedAny)
        return false;

    saveResumeData(downloadId);
    return true;
#else
    Q_UNUSED(downloadId); Q_UNUSED(currentPath); Q_UNUSED(newName);
    return false;
#endif
}

bool TorrentSessionManager::exportTorrentFile(const QString &downloadId, const QString &outputPath) const {
#if defined(STELLAR_HAS_LIBTORRENT)
    const auto handle = m_handles.value(downloadId);
    if (!handle.is_valid())
        return false;
    const auto info = handle.torrent_file();
    if (!info)
        return false;

    libtorrent::create_torrent creator(*info);
    std::vector<char> encoded;
    libtorrent::bencode(std::back_inserter(encoded), creator.generate());

    QFile file(outputPath);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate))
        return false;
    const qint64 bytesWritten = file.write(encoded.data(), encoded.size());
    return bytesWritten == static_cast<qint64>(encoded.size());
#else
    Q_UNUSED(downloadId);
    Q_UNUSED(outputPath);
    return false;
#endif
}

void TorrentSessionManager::setTorrentFlags(const QString &downloadId, bool disableDht, bool disablePex, bool disableLsd) {
#if defined(STELLAR_HAS_LIBTORRENT)
    const auto handle = m_handles.value(downloadId);
    if (!handle.is_valid())
        return;

    if (disableDht)
        handle.set_flags(libtorrent::torrent_flags::disable_dht);
    else
        handle.unset_flags(libtorrent::torrent_flags::disable_dht);

    if (disablePex)
        handle.set_flags(libtorrent::torrent_flags::disable_pex);
    else
        handle.unset_flags(libtorrent::torrent_flags::disable_pex);

    if (disableLsd)
        handle.set_flags(libtorrent::torrent_flags::disable_lsd);
    else
        handle.unset_flags(libtorrent::torrent_flags::disable_lsd);

    DownloadItem *item = m_items.value(downloadId, nullptr).data();
    if (item) {
        item->setTorrentDisableDht(disableDht);
        item->setTorrentDisablePex(disablePex);
        item->setTorrentDisableLsd(disableLsd);
    }
    saveResumeData(downloadId);
#else
    Q_UNUSED(downloadId); Q_UNUSED(disableDht); Q_UNUSED(disablePex); Q_UNUSED(disableLsd);
#endif
}

void TorrentSessionManager::forceRecheck(const QString &downloadId) {
#if defined(STELLAR_HAS_LIBTORRENT)
    const auto handle = m_handles.value(downloadId);
    if (!handle.is_valid())
        return;
    handle.force_recheck();
#else
    Q_UNUSED(downloadId);
#endif
}

void TorrentSessionManager::forceReannounce(const QString &downloadId, const QStringList &trackerUrls) {
#if defined(STELLAR_HAS_LIBTORRENT)
    const auto handle = m_handles.value(downloadId);
    if (!handle.is_valid())
        return;

    // ignore_min_interval bypasses the tracker's minimum announce interval so
    // the request actually fires even if we just announced a minute ago.
    const auto flags = libtorrent::torrent_handle::ignore_min_interval;

    const QDateTime reannounceUntil = QDateTime::currentDateTimeUtc().addSecs(15);

    // Always iterate by index — passing tracker_index=-1 doesn't reliably
    // propagate ignore_min_interval to all trackers in all libtorrent versions.
    const auto trackers = handle.trackers();
    auto &untilByUrl = m_trackerReannounceUntil[downloadId];
    const bool all = trackerUrls.isEmpty();
    for (int i = 0; i < static_cast<int>(trackers.size()); ++i) {
        const QString url = QString::fromStdString(trackers[i].url);
        if (all || trackerUrls.contains(url)) {
            handle.force_reannounce(0, i, flags);
            untilByUrl[trackerStatusKey(url)] = reannounceUntil;
        }
    }
    handle.post_trackers();
    updateModels(downloadId, handle, /*forceTrackerUpdate=*/true);
#else
    Q_UNUSED(downloadId); Q_UNUSED(trackerUrls);
#endif
}

QStringList TorrentSessionManager::trackerUrls(const QString &downloadId) const {
#if defined(STELLAR_HAS_LIBTORRENT)
    const auto handle = m_handles.value(downloadId);
    if (!handle.is_valid())
        return {};
    const auto trackers = handle.trackers();
    QStringList urls;
    urls.reserve(static_cast<int>(trackers.size()));
    for (const auto &tracker : trackers)
        urls.push_back(QString::fromStdString(tracker.url));
    return urls;
#else
    Q_UNUSED(downloadId);
    return {};
#endif
}

// Piece map encoding (one int per piece):
//   -2               : have (fully downloaded and verified)
//   -3               : skipped (user deselected — dont_download priority)
//   -(4 + pct)       : actively downloading; pct = 0..99 block progress %
//                      so the range is -4 (0%) .. -103 (99%)
//   0                : unavailable — piece is missing AND no peers have it
//   N                : missing, N peers have it (normal priority)
//   N | 0x10000      : missing, N peers have it AND the piece is high-priority
QVariantList TorrentSessionManager::torrentPieceMap(const QString &downloadId) const {
#if defined(STELLAR_HAS_LIBTORRENT)
    const auto handle = m_handles.value(downloadId);
    if (!handle.is_valid())
        return {};

    libtorrent::torrent_status st;
    try {
        st = handle.status(libtorrent::torrent_handle::query_pieces);
    } catch (...) {
        return {};
    }

    // Determine total piece count. status().num_pieces counts only pieces we
    // have verified, so prefer the torrent file's authoritative value when available.
    int total = 0;
    if (auto tf = handle.torrent_file())
        total = tf->num_pieces();
    if (total <= 0)
        total = st.num_pieces;
    if (total <= 0)
        return {};

    std::vector<int> avail;
    try {
        handle.piece_availability(avail);
    } catch (...) {}
    // In seed mode libtorrent returns an empty availability vector because it
    // no longer tracks per-piece peer counts. Treat that as fully seeded.
    const bool seedMode = avail.empty();

    const bool hasBitfield = (static_cast<int>(st.pieces.size()) == total);
    // In seed mode libtorrent may return an empty pieces bitfield even though
    // all pieces are present. num_pieces is the reliable fallback.
    const bool isComplete = (st.num_pieces == total);

    // Piece priorities: detect skipped (dont_download = 0) and high-priority (top_priority = 7).
    std::vector<libtorrent::download_priority_t> priorities;
    try {
        priorities = handle.get_piece_priorities();
    } catch (...) {}
    const bool hasPriorities = (static_cast<int>(priorities.size()) == total);

    QVariantList out;
    out.reserve(total);
    for (int i = 0; i < total; ++i) {
        if ((hasBitfield && st.pieces[libtorrent::piece_index_t{i}]) || (!hasBitfield && isComplete) || seedMode) {
            out.push_back(-2);  // have
            continue;
        }
        if (hasPriorities && priorities[i] == libtorrent::dont_download) {
            out.push_back(-3);  // skipped — user deselected this file/piece
            continue;
        }
        int val = static_cast<int>(avail.size()) > i ? avail[i] : 0;
        if (hasPriorities && priorities[i] == libtorrent::top_priority && val > 0)
            val |= 0x10000;  // flag: high-priority missing piece
        out.push_back(val);
    }

    // Overwrite downloading pieces with block-level progress encoded as -(4 + pct).
    // get_download_queue() returns only active pieces, so this loop is cheap.
    try {
        const auto queue = handle.get_download_queue();
        for (const auto &pp : queue) {
            const int idx = static_cast<int>(pp.piece_index);
            if (idx < 0 || idx >= total)
                continue;
            if (out[idx] == -2 || out[idx] == -3)
                continue;  // already have / skipped — don't overwrite
            const int blocks = pp.blocks_in_piece;
            // finished = written to disk, writing = in write queue; both count as progress
            const int done   = pp.finished + pp.writing;
            const int pct    = (blocks > 0) ? qBound(0, done * 100 / blocks, 99) : 0;
            out[idx] = -(4 + pct);
        }
    } catch (...) {}

    return out;
#else
    Q_UNUSED(downloadId);
    return {};
#endif
}

void TorrentSessionManager::setDetectedExternalAddress(const QString &ipAddress) {
#if defined(STELLAR_HAS_LIBTORRENT)
    const QString ip = QHostAddress(ipAddress.trimmed()).toString();
    if (ip.isEmpty() || ip == m_externalAddress)
        return;

    m_externalAddress = ip;
    QString countryCode;
    QString regionCode;
    QString regionName;
    QString cityName;
    double latitude = 0.0;
    double longitude = 0.0;
    lookupPeerLocation(ip, &countryCode, &regionCode, &regionName, &cityName, &latitude, &longitude);

    m_hasLocalCoordinates = !qFuzzyIsNull(latitude) || !qFuzzyIsNull(longitude);
    m_localLatitude = latitude;
    m_localLongitude = longitude;
    m_localCountryCode = countryCode;
    m_localRegionName = regionName;
    m_localCityName = cityName;
    const int listenPort = m_session ? m_session->listen_port() : 0;
    for (auto it = m_peerModels.begin(); it != m_peerModels.end(); ++it) {
        if (auto *peerModel = qobject_cast<TorrentPeerModel *>(it.value())) {
            peerModel->setLocalLocation(m_hasLocalCoordinates, m_localLatitude, m_localLongitude);
            peerModel->setLocalInfo(ip, listenPort, countryCode, regionName, cityName,
                                    defaultTorrentUserAgent(m_settings));
        }
    }
#else
    Q_UNUSED(ipAddress);
#endif
}

void TorrentSessionManager::setDetectedExternalAddress(const QString &ipAddress, double latitude, double longitude, bool hasCoordinates) {
#if defined(STELLAR_HAS_LIBTORRENT)
    const QString ip = QHostAddress(ipAddress.trimmed()).toString();
    if (ip.isEmpty())
        return;

    m_externalAddress = ip;
    QString countryCode;
    QString regionCode;
    QString regionName;
    QString cityName;
    if (hasCoordinates) {
        m_hasLocalCoordinates = true;
        m_localLatitude = latitude;
        m_localLongitude = longitude;
        lookupPeerLocation(ip, &countryCode, &regionCode, &regionName, &cityName, nullptr, nullptr);
    } else {
        double fallbackLatitude = 0.0;
        double fallbackLongitude = 0.0;
        lookupPeerLocation(ip, &countryCode, &regionCode, &regionName, &cityName, &fallbackLatitude, &fallbackLongitude);
        m_hasLocalCoordinates = !qFuzzyIsNull(fallbackLatitude) || !qFuzzyIsNull(fallbackLongitude);
        m_localLatitude = fallbackLatitude;
        m_localLongitude = fallbackLongitude;
    }
    m_localCountryCode = countryCode;
    m_localRegionName = regionName;
    m_localCityName = cityName;

    const int listenPort = m_session ? m_session->listen_port() : 0;
    for (auto it = m_peerModels.begin(); it != m_peerModels.end(); ++it) {
        if (auto *peerModel = qobject_cast<TorrentPeerModel *>(it.value())) {
            peerModel->setLocalLocation(m_hasLocalCoordinates, m_localLatitude, m_localLongitude);
            peerModel->setLocalInfo(ip, listenPort, countryCode, regionName, cityName,
                                    defaultTorrentUserAgent(m_settings));
        }
    }
#else
    Q_UNUSED(ipAddress); Q_UNUSED(latitude); Q_UNUSED(longitude); Q_UNUSED(hasCoordinates);
#endif
}

void TorrentSessionManager::checkShareLimits(const QString &id, DownloadItem *item, const AppSettings *settings) {
    if (m_pausedIds.contains(id))
        return;
    if (!settings)
        return;

    const double effectiveRatio = item->torrentShareRatioLimit() >= 0.0
        ? item->torrentShareRatioLimit()
        : settings->torrentDefaultShareRatio();
    const int effectiveSeedingMins = item->torrentSeedingTimeLimitMins() >= 0
        ? item->torrentSeedingTimeLimitMins()
        : settings->torrentDefaultSeedingTimeMins();
    const int effectiveInactiveMins = item->torrentInactiveSeedingTimeLimitMins() >= 0
        ? item->torrentInactiveSeedingTimeLimitMins()
        : settings->torrentDefaultInactiveSeedingTimeMins();
    const int effectiveAction = item->torrentShareLimitAction() >= 0
        ? item->torrentShareLimitAction()
        : settings->torrentDefaultShareLimitAction();

    bool limitReached = false;

    if (effectiveRatio > 0.0 && item->torrentRatio() >= effectiveRatio)
        limitReached = true;

    if (!limitReached && effectiveSeedingMins > 0 && m_seedingStartTimes.contains(id)) {
        const qint64 elapsedMins = m_seedingStartTimes[id].secsTo(QDateTime::currentDateTimeUtc()) / 60;
        if (elapsedMins >= effectiveSeedingMins)
            limitReached = true;
    }

    if (!limitReached && effectiveInactiveMins > 0) {
        const qint64 currentUploaded = item->torrentUploaded();
        if (m_lastUploadBytesForInactive.value(id, -1) != currentUploaded) {
            m_lastUploadBytesForInactive[id] = currentUploaded;
            m_lastUploadActivityTime[id] = QDateTime::currentDateTimeUtc();
        } else if (m_lastUploadActivityTime.contains(id)) {
            const qint64 inactiveMins = m_lastUploadActivityTime[id].secsTo(QDateTime::currentDateTimeUtc()) / 60;
            if (inactiveMins >= effectiveInactiveMins)
                limitReached = true;
        }
    }

    if (limitReached) {
        m_pausedIds.insert(id);
        emit torrentShareLimitReached(id, effectiveAction);
    }
}
#endif
