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
#include "StellarPaths.h"
#include "TorrentFileModel.h"
#include "TorrentPeerModel.h"
#include "TorrentTrackerModel.h"

#include <QByteArray>
#include <QCoreApplication>
#include <QDateTime>
#include <QDebug>
#include <QElapsedTimer>
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
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRandomGenerator>
#include <QSaveFile>
#include <QTextStream>
#include <QThreadPool>
#include <QtConcurrent>
#include <algorithm>
#include <tuple>
#include <cmath>
#include <cstdint>
#include <limits>
#include <utility>

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
#include <libtorrent/time.hpp>
#include <libtorrent/address.hpp>
#include <libtorrent/ip_filter.hpp>
#include <libtorrent/string_view.hpp>
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

// Tracker URLs must use udp://, http://, or https:// only.
// Rejects file://, UNC paths, and any other scheme that could probe local
// services or the filesystem when libtorrent attempts to announce.
bool isValidTrackerUrl(const QString &url) {
    const QString lower = url.toLower();
    return lower.startsWith(QLatin1String("udp://"))
        || lower.startsWith(QLatin1String("http://"))
        || lower.startsWith(QLatin1String("https://"));
}

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
    // Sanity ceiling before handing to libtorrent. A magnet with dozens of
    // trackers legitimately runs to several KB, so the cap is generous (64 KB);
    // anything larger is malformed or hostile. REJECT rather than truncate —
    // truncating could chop a magnet mid-"&tr=" and silently corrupt it.
    static constexpr int kMaxMagnetLen = 64 * 1024;
    if (trimmed.size() > kMaxMagnetLen)
        return QString();   // caller treats empty as invalid
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

// Working snapshots persist indefinitely so trackers don't revert to Idle between announces
// (typical announce interval is 30 min). Non-working snapshots expire after two full announce
// cycles so stale errors/warnings eventually clear themselves.
constexpr qint64 kTrackerSnapshotWorkingExpiryNever = std::numeric_limits<qint64>::max();
constexpr qint64 kTrackerSnapshotErrorExpirySecs = 7200; // two announce cycles

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
    // Cap to a sane length — real interface names are well under 64 chars on
    // any platform; anything longer cannot match a real interface.
    const QString trimmed = bindTarget.trimmed().left(64);
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

void applyInterfaceBinding(libtorrent::settings_pack &pack, const QStringList &bindAddresses, int listenPort) {
    if (!bindAddresses.isEmpty()) {
        QStringList listenInterfaces;
        for (const QString &addressText : bindAddresses) {
            const QHostAddress address(addressText);
            if (address.isNull())
                continue;
            listenInterfaces.push_back(formatListenInterface(address, listenPort));
        }

        if (!listenInterfaces.isEmpty()) {
            pack.set_str(libtorrent::settings_pack::listen_interfaces,
                         listenInterfaces.join(QStringLiteral(",")).toStdString());
            pack.set_str(libtorrent::settings_pack::outgoing_interfaces,
                         bindAddresses.join(QStringLiteral(",")).toStdString());
            return;
        }
    }

    pack.set_str(libtorrent::settings_pack::listen_interfaces,
                 QStringLiteral("0.0.0.0:%1,[::]:%1").arg(listenPort).toStdString());
    pack.set_str(libtorrent::settings_pack::outgoing_interfaces, std::string());
}

// Scan a directory for any dbip-city-lite-*.mmdb file, sort newest first.
static QStringList geoDbFilesInDir(const QString &dirPath) {
    QDir dir(dirPath);
    const QStringList filters = {QStringLiteral("dbip-city-lite-*.mmdb")};
    QStringList entries = dir.entryList(filters, QDir::Files | QDir::Readable, QDir::Name);
    // Name sort ascending (2026-04 < 2026-05); reverse so newest comes first.
    std::reverse(entries.begin(), entries.end());
    QStringList result;
    result.reserve(entries.size());
    for (const QString &entry : entries)
        result.append(dir.absoluteFilePath(entry));
    return result;
}

QStringList geoDbCandidates() {
    const QString appDir = QCoreApplication::applicationDirPath();
    // Primary: the unified geo/ directory under the Stellar data root.
    // Fallbacks cover side-by-side installs and Flatpak bundle layouts.
    // Each directory is scanned for any dbip-city-lite-*.mmdb so that
    // monthly DB updates don't require a code change.
    QStringList candidates;
    candidates.append(geoDbFilesInDir(StellarPaths::geoDir()));
    candidates.append(geoDbFilesInDir(appDir + QStringLiteral("/data")));
    candidates.append(geoDbFilesInDir(appDir));
    candidates.append(geoDbFilesInDir(appDir + QStringLiteral("/../data")));
    candidates.append(geoDbFilesInDir(QDir::cleanPath(appDir + QStringLiteral("/../../app/data"))));
    candidates.append(geoDbFilesInDir(QDir::cleanPath(appDir + QStringLiteral("/../../../app/data"))));
    return candidates;
}

QString defaultTorrentUserAgent(const AppSettings *settings) {
    if (settings) {
        const QString custom = settings->torrentCustomUserAgent().trimmed().left(512);
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
    // Insertion order for FIFO eviction. QHash iteration order is unspecified,
    // so the prior eviction loop effectively dropped random entries — which
    // could (and did) evict hot peers immediately after insertion, thrashing
    // the cache when swarm size approached the cap. A FIFO ring evicts the
    // genuinely oldest entries.
    QList<QString> insertionOrder;
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
            // Refresh global DHT node count; arrives async as dht_stats_alert.
            if (m_settings && m_settings->torrentEnableDht()) {
                m_session->post_dht_stats();
            } else if (m_dhtNodes != 0) {
                m_dhtNodes = 0;
                emit dhtNodesChanged();
            }

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
    if (!settings->torrentEnabled()) {
        // Fully shut down the libtorrent session so it makes no network connections.
        m_alertTimer.stop();
        m_session.reset();
        // Clear stale handle/item maps so re-enable starts with a clean slate.
        m_handles.clear();
        m_handleToId.clear();
        m_items.clear();
        m_pausedIds.clear();
        m_firedFinishedIds.clear();
        return;
    }
    ensureSession();
    refreshPeerBanRules(settings);
    configureSession(settings);
    if (!m_alertTimer.isActive())
        m_alertTimer.start();
#else
    Q_UNUSED(settings);
#endif
}

bool TorrentSessionManager::addMagnet(DownloadItem *item, bool startPaused, bool deferModels) {
#if defined(STELLAR_HAS_LIBTORRENT)
    return addTorrentInternal(item, startPaused, QString(), deferModels);
#else
    Q_UNUSED(item);
    Q_UNUSED(startPaused);
    Q_UNUSED(deferModels);
    return false;
#endif
}

bool TorrentSessionManager::addTorrentFile(DownloadItem *item, const QString &torrentFilePath, bool startPaused, bool deferModels) {
#if defined(STELLAR_HAS_LIBTORRENT)
    return addTorrentInternal(item, startPaused, torrentFilePath, deferModels);
#else
    Q_UNUSED(item);
    Q_UNUSED(torrentFilePath);
    Q_UNUSED(startPaused);
    Q_UNUSED(deferModels);
    return false;
#endif
}

bool TorrentSessionManager::restoreTorrent(DownloadItem *item, bool deferModels) {
#if defined(STELLAR_HAS_LIBTORRENT)
    if (!item || !item->isTorrent())
        return false;
    if (!m_session)
        return false;
    if (item->statusEnum() == DownloadItem::Status::Error)
        return true;
    // Pre-mark as already-finished to suppress spurious torrent_finished_alert
    // re-fires that libtorrent emits during startup resume-data checking.
    // Cover Seeding/Completed (obvious) and Checking (torrent was mid-recheck
    // when app closed — it was already fully downloaded). Downloading/Paused
    // with incomplete data must NOT be pre-inserted so they notify on genuine
    // completion after resuming.
    const auto s = item->statusEnum();
    if (s == DownloadItem::Status::Seeding
            || s == DownloadItem::Status::Completed
            || s == DownloadItem::Status::Checking)
        m_firedFinishedIds.insert(item->id());
    const bool paused = s == DownloadItem::Status::Paused;
    if (item->torrentSource().startsWith(QStringLiteral("magnet:?"), Qt::CaseInsensitive))
        return addMagnet(item, paused, deferModels);
    return addTorrentFile(item, item->torrentSource(), paused, deferModels);
#else
    Q_UNUSED(item);
    Q_UNUSED(deferModels);
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
    const bool removedEntry = m_bannedPeers.remove(normalized) != 0;
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
    item->setLastTryAt(QDateTime::currentDateTime());
    // Don't call updateItemFromStatus here — it acquires the session mutex per torrent
    // and causes UI freezes when resuming many torrents at once. The alert timer fires
    // post_torrent_updates() every second, so status propagates within one tick.
#else
    Q_UNUSED(item);
#endif
}

bool TorrentSessionManager::isBindInterfaceAvailable(const QString &bindTarget) const {
    const QString trimmed = bindTarget.trimmed();
    if (trimmed.isEmpty())
        return true; // no constraint configured → always "available"
    const QNetworkInterface iface = findNetworkInterfaceForBinding(trimmed);
    return !interfaceBindAddresses(iface).isEmpty();
}

void TorrentSessionManager::suspendSession() {
#if defined(STELLAR_HAS_LIBTORRENT)
    if (m_session)
        m_session->pause();
    // Deliberately keep m_alertTimer running. Pausing stops peer traffic (the leak
    // guard) but the alert loop must keep processing: save_resume_data alerts (else a
    // crash during suspend loses recent resume data), checkShareLimits, and UI status
    // updates. post_torrent_updates() on a paused-but-valid session is safe.
#endif
}

void TorrentSessionManager::unsuspendSession() {
#if defined(STELLAR_HAS_LIBTORRENT)
    if (m_session) {
        m_session->resume();
        if (!m_alertTimer.isActive())
            m_alertTimer.start();
    }
#endif
}

void TorrentSessionManager::remove(const QString &downloadId, bool deleteFiles) {
#if defined(STELLAR_HAS_LIBTORRENT)
    const auto handle = m_handles.take(downloadId);
    m_handleToId.remove(handle);
    m_items.remove(downloadId);
    m_pausedIds.remove(downloadId);
    m_movingIds.remove(downloadId);
    m_firedFinishedIds.remove(downloadId);
    m_staticMetadataApplied.remove(downloadId);
    m_pendingAsyncAdds.remove(downloadId);
    m_lastResumeSaveRequest.remove(downloadId);
    m_trackerReannounceUntil.remove(downloadId);
    m_trackerAlertSnapshots.remove(downloadId);
    m_seedingStartTimes.remove(downloadId);
    m_lastUploadBytesForInactive.remove(downloadId);
    m_lastUploadActivityTime.remove(downloadId);
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

#if defined(STELLAR_HAS_LIBTORRENT)
bool TorrentSessionManager::applyFilePriorities(const QString &downloadId) {
    auto *model = m_fileModels.value(downloadId, nullptr);
    const auto handle = m_handles.value(downloadId);
    if (!model || !handle.is_valid())
        return false;
    auto *fileModel = qobject_cast<TorrentFileModel *>(model);
    if (!fileModel)
        return false;

    const QVector<TorrentFileModel::Entry> entries = fileModel->fileEntries();
    std::vector<libtorrent::download_priority_t> priorities;
    priorities.reserve(entries.size());
    for (const auto &entry : entries) {
        if (!entry.wanted) {
            priorities.push_back(libtorrent::dont_download);
            continue;
        }
        // Defensive clamp: the value crosses from QML and resume data; never
        // hand libtorrent an out-of-range priority.
        const int p = std::clamp(entry.priority, 1, 7);
        priorities.push_back(libtorrent::download_priority_t(std::uint8_t(p)));
    }
    handle.prioritize_files(priorities);
    saveResumeData(downloadId);
    return true;
}
#else
bool TorrentSessionManager::applyFilePriorities(const QString &) { return false; }
#endif

bool TorrentSessionManager::setFileWanted(const QString &downloadId, int row, bool wanted) {
#if defined(STELLAR_HAS_LIBTORRENT)
    auto *model = m_fileModels.value(downloadId, nullptr);
    auto *fileModel = qobject_cast<TorrentFileModel *>(model);
    if (!fileModel || !fileModel->setWanted(row, wanted))
        return false;
    return applyFilePriorities(downloadId);
#else
    Q_UNUSED(downloadId); Q_UNUSED(row); Q_UNUSED(wanted);
    return false;
#endif
}

bool TorrentSessionManager::setFileWantedByFileIndex(const QString &downloadId, int fileIndex, bool wanted) {
#if defined(STELLAR_HAS_LIBTORRENT)
    auto *model = m_fileModels.value(downloadId, nullptr);
    auto *fileModel = qobject_cast<TorrentFileModel *>(model);
    if (!fileModel || !fileModel->setWantedByFileIndex(fileIndex, wanted))
        return false;
    return applyFilePriorities(downloadId);
#else
    Q_UNUSED(downloadId); Q_UNUSED(fileIndex); Q_UNUSED(wanted);
    return false;
#endif
}

bool TorrentSessionManager::setFileWantedByPath(const QString &downloadId, const QString &path, bool wanted) {
#if defined(STELLAR_HAS_LIBTORRENT)
    auto *model = m_fileModels.value(downloadId, nullptr);
    auto *fileModel = qobject_cast<TorrentFileModel *>(model);
    if (!fileModel || !fileModel->setWantedByPath(path, wanted))
        return false;
    return applyFilePriorities(downloadId);
#else
    Q_UNUSED(downloadId); Q_UNUSED(path); Q_UNUSED(wanted);
    return false;
#endif
}

bool TorrentSessionManager::setFilePriority(const QString &downloadId, int row, int priority) {
#if defined(STELLAR_HAS_LIBTORRENT)
    auto *model = m_fileModels.value(downloadId, nullptr);
    auto *fileModel = qobject_cast<TorrentFileModel *>(model);
    if (!fileModel || !fileModel->setPriority(row, priority))
        return false;
    return applyFilePriorities(downloadId);
#else
    Q_UNUSED(downloadId); Q_UNUSED(row); Q_UNUSED(priority);
    return false;
#endif
}

bool TorrentSessionManager::setFilePriorityByFileIndex(const QString &downloadId, int fileIndex, int priority) {
#if defined(STELLAR_HAS_LIBTORRENT)
    auto *model = m_fileModels.value(downloadId, nullptr);
    auto *fileModel = qobject_cast<TorrentFileModel *>(model);
    if (!fileModel || !fileModel->setPriorityByFileIndex(fileIndex, priority))
        return false;
    return applyFilePriorities(downloadId);
#else
    Q_UNUSED(downloadId); Q_UNUSED(fileIndex); Q_UNUSED(priority);
    return false;
#endif
}

bool TorrentSessionManager::setFilePriorityByPath(const QString &downloadId, const QString &path, int priority) {
#if defined(STELLAR_HAS_LIBTORRENT)
    auto *model = m_fileModels.value(downloadId, nullptr);
    auto *fileModel = qobject_cast<TorrentFileModel *>(model);
    if (!fileModel || !fileModel->setPriorityByPath(path, priority))
        return false;
    return applyFilePriorities(downloadId);
#else
    Q_UNUSED(downloadId); Q_UNUSED(path); Q_UNUSED(priority);
    return false;
#endif
}

bool TorrentSessionManager::addTracker(const QString &downloadId, const QString &url) {
#if defined(STELLAR_HAS_LIBTORRENT)
    const auto handle = m_handles.value(downloadId);
    static constexpr int kMaxTrackerUrlLen = 2048;
    const QString trimmedUrl = url.trimmed().left(kMaxTrackerUrlLen);
    if (!handle.is_valid() || trimmedUrl.isEmpty() || !isValidTrackerUrl(trimmedUrl))
        return false;
    handle.add_tracker(libtorrent::announce_entry(trimmedUrl.toStdString()));
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

void TorrentSessionManager::mergeTrackers(const QString &downloadId, const QStringList &trackers) {
#if defined(STELLAR_HAS_LIBTORRENT)
    const auto handle = m_handles.value(downloadId);
    if (!handle.is_valid() || trackers.isEmpty())
        return;
    // Collect existing tracker URLs to avoid duplicates
    QSet<QString> existing;
    for (const auto &ae : handle.trackers())
        existing.insert(QString::fromStdString(ae.url));
    bool added = false;
    for (const QString &url : trackers) {
        const QString t = url.trimmed();
        if (t.isEmpty() || !isValidTrackerUrl(t) || existing.contains(t))
            continue;
        handle.add_tracker(libtorrent::announce_entry(t.toStdString()));
        added = true;
    }
    if (added) {
        handle.post_trackers();
        if (DownloadItem *item = m_items.value(downloadId, nullptr).data())
            item->setTorrentTrackers(trackerUrls(downloadId));
        saveResumeData(downloadId);
    }
#else
    Q_UNUSED(downloadId); Q_UNUSED(trackers);
#endif
}

QString TorrentSessionManager::infoHashFromSource(const QString &source) const {
#if defined(STELLAR_HAS_LIBTORRENT)
    const QString s = source.trimmed();
    // Magnet URI: extract xt=urn:btih:<hash>
    if (s.startsWith(QStringLiteral("magnet:"), Qt::CaseInsensitive)) {
        const QUrl url(s);
        const QString query = url.query();
        static const QString kBtih = QStringLiteral("xt=urn:btih:");
        int idx = query.indexOf(kBtih, 0, Qt::CaseInsensitive);
        if (idx >= 0) {
            QString hash = query.mid(idx + kBtih.length());
            int end = hash.indexOf(QLatin1Char('&'));
            if (end >= 0)
                hash = hash.left(end);
            // Base32 → hex: libtorrent parse_magnet_uri handles this,
            // but for comparison just normalise to lowercase.
            return hash.toLower().trimmed();
        }
        return {};
    }
    // .torrent file: parse with libtorrent
    libtorrent::error_code ec;
    auto ti = std::make_shared<libtorrent::torrent_info>(s.toStdString(), ec);
    if (!ec && ti->is_valid()) {
        const auto bestHash = ti->info_hashes().get_best();
        return toHexString(bestHash.to_string());
    }
#else
    Q_UNUSED(source);
#endif
    return {};
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

bool TorrentSessionManager::addWebSeed(const QString &downloadId, const QString &url) {
#if defined(STELLAR_HAS_LIBTORRENT)
    const auto handle = m_handles.value(downloadId);
    if (!handle.is_valid() || url.trimmed().isEmpty())
        return false;
    // libtorrent distinguishes BEP-19 url_seeds from BEP-17 http_seeds;
    // add_url_seed covers the common case (BEP-19 GetRight-style).
    handle.add_url_seed(url.trimmed().toStdString());
    if (DownloadItem *item = m_items.value(downloadId, nullptr).data()) {
        QStringList seeds = item->torrentUrlSeeds();
        if (!seeds.contains(url.trimmed())) {
            seeds.append(url.trimmed());
            item->setTorrentUrlSeeds(seeds);
        }
    }
    saveResumeData(downloadId);
    return true;
#else
    Q_UNUSED(downloadId);
    Q_UNUSED(url);
    return false;
#endif
}

bool TorrentSessionManager::removeWebSeed(const QString &downloadId, const QString &url) {
#if defined(STELLAR_HAS_LIBTORRENT)
    const auto handle = m_handles.value(downloadId);
    if (!handle.is_valid() || url.trimmed().isEmpty())
        return false;
    const std::string u = url.trimmed().toStdString();
    // Try url_seed (BEP-19) first, then http_seed (BEP-17)
    handle.remove_url_seed(u);
    handle.remove_http_seed(u);
    if (DownloadItem *item = m_items.value(downloadId, nullptr).data()) {
        QStringList urlSeeds  = item->torrentUrlSeeds();
        QStringList httpSeeds = item->torrentHttpSeeds();
        urlSeeds.removeAll(url.trimmed());
        httpSeeds.removeAll(url.trimmed());
        item->setTorrentUrlSeeds(urlSeeds);
        item->setTorrentHttpSeeds(httpSeeds);
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

void TorrentSessionManager::requestIpFilterRebuild() {
    m_ipFilterRebuildPending = true;
}

void TorrentSessionManager::flushIpFilterRebuild() {
    if (!m_ipFilterRebuildPending)
        return;
    m_ipFilterRebuildPending = false;
    rebuildIpFilter();
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
        // Cap the temporary ban set so a public swarm with a steady stream of
        // abusive peers cannot grow it without bound. Each rebuild allocates
        // a libtorrent::ip_filter rule per entry; without a cap a multi-hour
        // seeding session could push this past 10k entries and turn every
        // alert tick into seconds of work on the GUI thread.
        if (m_temporaryBannedPeers.size() >= kMaxTemporaryBans) {
            // Drop a chunk so we don't thrash at the boundary. QSet iteration
            // order is unspecified — random eviction is acceptable for what is
            // effectively a session-scope blacklist (re-bans on next inspection
            // if still abusive).
            const int toDrop = kMaxTemporaryBans / 8;
            int dropped = 0;
            for (auto it = m_temporaryBannedPeers.begin();
                 it != m_temporaryBannedPeers.end() && dropped < toDrop; ) {
                const QString ep = *it;
                it = m_temporaryBannedPeers.erase(it);
                auto bp = m_bannedPeers.find(ep);
                if (bp != m_bannedPeers.end() && !bp.value().permanent)
                    m_bannedPeers.erase(bp);
                ++dropped;
            }
        }
        m_temporaryBannedPeers.insert(normalized);
        // Coalesce: defer the actual ip_filter rebuild until the end of the
        // current processAlerts() pass. Without this, every newly-banned peer
        // during a single alert burst triggered a full O(N) rebuild — under
        // auto-ban this scaled as N² over a multi-hour session.
        requestIpFilterRebuild();
    }
    BannedPeer entry;
    entry.endpoint = normalized;
    entry.client = client;
    entry.countryCode = countryCode.trimmed().toUpper();
    entry.reason = reason;
    entry.permanent = false;
    // Cap m_bannedPeers in tandem with m_temporaryBannedPeers, otherwise the
    // permanent-or-not record persists across temp evictions and the QHash
    // grows past either set's nominal cap.
    if (m_bannedPeers.size() >= kMaxBannedPeers) {
        for (auto it = m_bannedPeers.begin(); it != m_bannedPeers.end(); ) {
            if (!it.value().permanent && !m_temporaryBannedPeers.contains(it.key()))
                it = m_bannedPeers.erase(it);
            else
                ++it;
            if (m_bannedPeers.size() < kMaxBannedPeers * 7 / 8)
                break;
        }
    }
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
        | libtorrent::alert_category::tracker
        | libtorrent::alert_category::dht;
    pack.set_int(libtorrent::settings_pack::alert_mask,
                 static_cast<int>(static_cast<std::uint32_t>(alertMask)));

    // Network interface binding (leak protection). Single user-facing control,
    // qBittorrent-style: torrentBindInterface is either empty ("Any interface":
    // unbound, follow the system route, which already goes through the VPN when the
    // VPN is the default route) or a named adapter (hard bind to that interface only;
    // if it goes away, no traffic leaks onto another route).
    // boundToInterface = a specific adapter is selected.
    const QString bindTarget = settings->torrentBindInterface().trimmed();
    const bool boundToInterface = !bindTarget.isEmpty();
    QStringList bindAddrs;
    if (boundToInterface)
        bindAddrs = interfaceBindAddresses(findNetworkInterfaceForBinding(bindTarget));
    // Fail-closed: a configured adapter that currently has no usable address binds to
    // nothing rather than falling back to all interfaces (which would leak).
    const bool bindFailClosed = boundToInterface && bindAddrs.isEmpty();

    pack.set_bool(libtorrent::settings_pack::enable_dht, settings->torrentEnableDht());
    // Auto-harden when bound to a specific interface: UPnP and NAT-PMP map ports via
    // the LAN gateway (off-VPN, exposing the listen port) and LSD broadcasts to the
    // local network, so all three leak around the bound interface. Disable them while
    // bound unless the user explicitly opts in via torrentAllowDiscoveryWhenBound (e.g.
    // binding to a plain LAN adapter where UPnP is legitimately wanted). When following
    // the system route (unbound) the user's settings are always honoured. DHT stays
    // user-controlled: it routes over the bound interface and maps no LAN ports. Both
    // the v4 and v6 addresses of the bound interface are used (see applyInterfaceBinding),
    // so IPv6 rides the VPN when the VPN provides a v6 address; a v4-only VPN simply
    // yields a v4-only bind and never falls back to an all-interfaces [::] catch-all
    // that would leak native IPv6.
    const bool hardenDiscovery = boundToInterface && !settings->torrentAllowDiscoveryWhenBound();
    pack.set_bool(libtorrent::settings_pack::enable_lsd,
                  hardenDiscovery ? false : settings->torrentEnableLsd());
    pack.set_bool(libtorrent::settings_pack::enable_upnp,
                  hardenDiscovery ? false : settings->torrentEnableUpnp());
    pack.set_bool(libtorrent::settings_pack::enable_natpmp,
                  hardenDiscovery ? false : settings->torrentEnableNatPmp());

    // PeX has no session-level settings_pack key; propagate to all existing handles.
    for (auto &h : m_session->get_torrents()) {
        if (h.is_valid()) {
            if (settings->torrentEnablePex())
                h.unset_flags(libtorrent::torrent_flags::disable_pex);
            else
                h.set_flags(libtorrent::torrent_flags::disable_pex);
        }
    }

    // Global connection and upload slot limits
    pack.set_int(libtorrent::settings_pack::connections_limit,
                 settings->torrentConnectionsLimit());
    pack.set_int(libtorrent::settings_pack::unchoke_slots_limit,
                 settings->torrentUploadSlotsLimit() > 0
                     ? settings->torrentUploadSlotsLimit() : -1);
    // Protocol: 0=TCP+μTP (default), 1=μTP only, 2=TCP only
    switch (settings->torrentProtocol()) {
    case 1: // μTP only
        pack.set_bool(libtorrent::settings_pack::enable_outgoing_tcp, false);
        pack.set_bool(libtorrent::settings_pack::enable_incoming_tcp, false);
        pack.set_bool(libtorrent::settings_pack::enable_outgoing_utp, true);
        pack.set_bool(libtorrent::settings_pack::enable_incoming_utp, true);
        break;
    case 2: // TCP only
        pack.set_bool(libtorrent::settings_pack::enable_outgoing_tcp, true);
        pack.set_bool(libtorrent::settings_pack::enable_incoming_tcp, true);
        pack.set_bool(libtorrent::settings_pack::enable_outgoing_utp, false);
        pack.set_bool(libtorrent::settings_pack::enable_incoming_utp, false);
        break;
    default: // TCP + μTP
        pack.set_bool(libtorrent::settings_pack::enable_outgoing_tcp, true);
        pack.set_bool(libtorrent::settings_pack::enable_incoming_tcp, true);
        pack.set_bool(libtorrent::settings_pack::enable_outgoing_utp, true);
        pack.set_bool(libtorrent::settings_pack::enable_incoming_utp, true);
        break;
    }
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
    // Apply the bind decision computed above. When fail-closed (mode 1 with the
    // configured adapter unavailable), bind to NOTHING — empty interfaces stop all
    // traffic rather than letting libtorrent's all-interfaces default leak the real
    // IP. Otherwise applyInterfaceBinding pins listen+outgoing to bindAddrs, or — for
    // genuinely-unbound modes (mode 2, or Automatic with no VPN) where bindAddrs is
    // empty and we are NOT fail-closed — uses the default-route fallback.
    if (bindFailClosed) {
        pack.set_str(libtorrent::settings_pack::listen_interfaces, std::string());
        pack.set_str(libtorrent::settings_pack::outgoing_interfaces, std::string());
    } else {
        applyInterfaceBinding(pack, bindAddrs, settings->torrentListenPort());
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

    // Storage / disk I/O settings (libtorrent 2.0+)
    pack.set_bool(libtorrent::settings_pack::piece_extent_affinity,
                  settings->torrentPieceExtentAffinity());
    // coalesce_reads/writes moved to deprecated_ prefix in lt 2.0 ABI; use the versioned alias.
    pack.set_bool(libtorrent::settings_pack::deprecated_coalesce_reads,
                  settings->torrentCoalesceReads());
    pack.set_bool(libtorrent::settings_pack::deprecated_coalesce_writes,
                  settings->torrentCoalesceWrites());
    // Disk I/O read/write mode (io_buffer_mode_t):
    //   0=Default (enable_os_cache), 1=mmap (enable_os_cache, libtorrent 2.0 default on most
    //   platforms), 2=POSIX (disable_os_cache — bypass page cache, use direct I/O where available).
    // Note: libtorrent 2.0 chooses mmap_disk_io vs posix_disk_io internally; these flags
    // control OS cache behaviour of whichever backend is active.
    {
        int readMode  = libtorrent::settings_pack::enable_os_cache;
        int writeMode = libtorrent::settings_pack::enable_os_cache;
        switch (settings->torrentDiskIoType()) {
        case 2: // POSIX / bypass OS page cache
            readMode  = libtorrent::settings_pack::disable_os_cache;
            writeMode = libtorrent::settings_pack::disable_os_cache;
            break;
        default: // Default and mmap both use the OS cache (let libtorrent select the backend)
            break;
        }
        pack.set_int(libtorrent::settings_pack::disk_io_read_mode,  readMode);
        pack.set_int(libtorrent::settings_pack::disk_io_write_mode, writeMode);
    }
    // 0 means "use libtorrent default"; otherwise convert MiB → bytes.
    if (settings->torrentDiskWriteQueueMiB() > 0)
        pack.set_int(libtorrent::settings_pack::max_queued_disk_bytes,
                     settings->torrentDiskWriteQueueMiB() * 1024 * 1024);

    // ── High-throughput tuning (always on, "balanced-fast") ───────────────────
    // libtorrent's stock defaults are tuned for modest connections and bottleneck
    // seeding/downloading on fast links. These overrides raise the network send
    // pipeline and disk/request parallelism for gigabit-class connections at a
    // modest RAM cost (tens of MB). We deliberately DO NOT touch the keys that are
    // user-controlled above — connections_limit, unchoke_slots_limit, the rate
    // limits, and max_queued_disk_bytes are owned by the user's settings and must
    // not be clobbered here.
    //
    // send_buffer_watermark: stock 512 KB caps per-peer upload ramp — on a fat
    // pipe the buffer drains faster than the 16 KB-block refill can keep up.
    // Raise to 3 MB so a single fast leecher can be saturated.
    pack.set_int(libtorrent::settings_pack::send_buffer_watermark, 3 * 1024 * 1024);
    // watermark = current_upload_rate × factor%. Stock 50 halves the dynamic
    // target; 150 lets the watermark track high upload rates (per lt docs:
    // "For high speed upload, this should be set to a greater value than 100").
    pack.set_int(libtorrent::settings_pack::send_buffer_watermark_factor, 150);
    // Larger initial send window → faster ramp-up to a new peer (stock 10 KB).
    pack.set_int(libtorrent::settings_pack::send_buffer_low_watermark, 1 * 1024 * 1024);
    // Disk I/O worker threads (stock 10). More parallelism keeps the send buffers
    // fed and write-back flowing on multi-core machines with fast storage.
    pack.set_int(libtorrent::settings_pack::aio_threads, 16);
    // Outstanding block requests we'll pipeline to peers (stock 500) — deeper
    // queue keeps the download pipe full at high bandwidth-delay product.
    pack.set_int(libtorrent::settings_pack::max_out_request_queue, 1500);
    // Inbound request queue we allow a peer to keep against us while seeding
    // (stock 2000) — raise so fast leechers aren't request-starved.
    pack.set_int(libtorrent::settings_pack::max_allowed_in_request_queue, 4000);
    // New outgoing connection attempts per tick (stock 30) and the initial burst
    // when a torrent is added (stock 30) — connect to a swarm faster.
    pack.set_int(libtorrent::settings_pack::connection_speed, 100);
    pack.set_int(libtorrent::settings_pack::torrent_connect_boost, 100);
    // Let the OS size the socket buffers automatically (0). Some platforms cap
    // these low by default; auto-sizing avoids a hidden TCP throughput ceiling.
    pack.set_int(libtorrent::settings_pack::send_socket_buffer_size, 0);
    pack.set_int(libtorrent::settings_pack::recv_socket_buffer_size, 0);

    m_session->apply_settings(pack);

    // Per-torrent limits are not in settings_pack — apply to all existing handles.
    // 0 = unlimited (-1 in libtorrent API).
    const int maxConnsPerTorrent  = settings->torrentConnectionsLimitPerTorrent() > 0
                                        ? settings->torrentConnectionsLimitPerTorrent() : -1;
    const int maxUploadsPerTorrent = settings->torrentUploadSlotsLimitPerTorrent() > 0
                                        ? settings->torrentUploadSlotsLimitPerTorrent() : -1;
    for (auto &handle : m_handles) {
        if (handle.is_valid()) {
            handle.set_max_connections(maxConnsPerTorrent);
            handle.set_max_uploads(maxUploadsPerTorrent);
        }
    }
}

QString TorrentSessionManager::idForHandle(const libtorrent::torrent_handle &handle) const {
    return m_handleToId.value(handle);
}

bool TorrentSessionManager::addTorrentInternal(DownloadItem *item, bool startPaused, const QString &torrentFilePath, bool deferModels) {
    if (!item)
        return false;

    ensureSession();
    if (!m_alertTimer.isActive())
        m_alertTimer.start();

    libtorrent::error_code ec;
    libtorrent::add_torrent_params params;

    // Resume blob is stored on disk under StellarPaths::resumeFile() rather
    // than preloaded into the DownloadItem at startup. Read it here, on the
    // hot path where we actually need the bytes — DownloadDatabase::loadAll
    // used to preload + Base64 every blob synchronously before the QML window
    // could even paint.
    QByteArray resumeBlob = item->torrentResumeData();
    if (resumeBlob.isEmpty()) {
        QFile rf(StellarPaths::resumeFile(item->id()));
        if (rf.exists() && rf.open(QIODevice::ReadOnly))
            resumeBlob = rf.readAll();
    }
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
    // storage_mode must be set at add time — it cannot be changed after the torrent is added.
    if (m_settings && m_settings->torrentStorageMode() == 1)
        params.storage_mode = libtorrent::storage_mode_allocate;
    else
        params.storage_mode = libtorrent::storage_mode_sparse;
    if (m_settings && !m_settings->torrentEnablePex())
        params.flags |= libtorrent::torrent_flags::disable_pex;
    else
        params.flags &= ~libtorrent::torrent_flags::disable_pex;

    if (torrentFilePath.isEmpty()) {
        const QString magnetSource = normalizeTorrentUri(item->torrentSource());
        // Reject up front: an empty result means the magnet was malformed or
        // over-length. Guard before the assignment below, otherwise we'd clobber
        // the item's real source with "".
        if (magnetSource.isEmpty()) {
            emit torrentErrored(item->id(),
                QStringLiteral("Magnet link is malformed or exceeds the maximum allowed length."));
            return false;
        }
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

    // Restore path: add asynchronously. The synchronous add_torrent() is a
    // session-thread round-trip per torrent — restoring dozens at startup
    // serialised those round-trips and was a large share of the cold-start
    // "Loading downloads…" delay. async_add_torrent() returns immediately; the
    // handle and post-add registration are completed in the add_torrent_alert
    // handler. The item pointer is carried back via userdata (type-safe void*),
    // and is guaranteed to outlive the add (owned by the model for the app
    // lifetime). Interactive adds stay synchronous so the metadata dialog can
    // populate its file list without waiting an alert tick.
    if (deferModels) {
        params.userdata = item;
        m_pendingAsyncAdds.insert(item->id());
        m_session->async_add_torrent(std::move(params));
        return true;
    }

    const libtorrent::torrent_handle handle = m_session->add_torrent(params, ec);
    if (ec || !handle.is_valid()) {
        emit torrentErrored(item->id(), ec ? QString::fromStdString(ec.message()) : QStringLiteral("Failed to add torrent"));
        return false;
    }
    finalizeTorrentAdd(item, handle, startPaused, deferModels, torrentFilePath);
    return true;
}

void TorrentSessionManager::finalizeTorrentAdd(DownloadItem *item, const libtorrent::torrent_handle &handle,
                                               bool startPaused, bool deferModels, const QString &torrentFilePath) {
    if (!item || !handle.is_valid())
        return;

    // Apply per-torrent connection and upload-slot limits from settings.
    if (m_settings) {
        const int maxConns = m_settings->torrentConnectionsLimitPerTorrent() > 0
                                 ? m_settings->torrentConnectionsLimitPerTorrent() : -1;
        const int maxUploads = m_settings->torrentUploadSlotsLimitPerTorrent() > 0
                                   ? m_settings->torrentUploadSlotsLimitPerTorrent() : -1;
        handle.set_max_connections(maxConns);
        handle.set_max_uploads(maxUploads);
    }

    // Apply stored per-torrent flags before registering the handle.
    if (item->torrentDisableDht())
        handle.set_flags(libtorrent::torrent_flags::disable_dht);
    if (item->torrentDisablePex())
        handle.set_flags(libtorrent::torrent_flags::disable_pex);
    if (item->torrentDisableLsd())
        handle.set_flags(libtorrent::torrent_flags::disable_lsd);
    if (item->torrentSequential())
        handle.set_flags(libtorrent::torrent_flags::sequential_download);
    // first/last piece deadline is re-applied via setTorrentDownloadMode after
    // metadata arrives (piece count is not yet known at add time for magnets).

    m_handles[item->id()] = handle;
    m_handleToId[handle] = item->id();
    m_items[item->id()] = item;
    // Stagger resume-data saves so all torrents added at the same time don't
    // pile their save_resume_data requests into one alert tick. A hash-derived
    // offset spreads them across 0-59 seconds of the first 60-second window.
    m_lastResumeSaveRequest[item->id()] =
        QDateTime::currentDateTimeUtc().addSecs(-qint64(qHash(item->id()) % 60u));
    // A pause() may have arrived while an async add was still in flight (e.g.
    // torrentStopOnStartup pausing a restored seeding torrent before its
    // add_torrent_alert landed). In that case m_pausedIds already holds the id
    // but the freshly-added handle is running — honour the pause now so it
    // doesn't leak around a VPN. Otherwise reflect the requested start state.
    const bool pausePending = m_pausedIds.contains(item->id());
    if (startPaused || pausePending) {
        m_pausedIds.insert(item->id());
        if (pausePending && !startPaused) {
            handle.unset_flags(libtorrent::torrent_flags::auto_managed);
            handle.pause();
        }
    } else {
        m_pausedIds.remove(item->id());
    }
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
            if (!trimmed.isEmpty() && isValidTrackerUrl(trimmed))
                entries.emplace_back(trimmed.toStdString());
        }
        if (!entries.empty()) {
            handle.replace_trackers(entries);
            handle.post_trackers();
        }
    }

    item->setTorrentTrackers(trackerUrls(item->id()));

    // Re-apply persisted web seeds so they survive an app restart
    for (const QString &seedUrl : item->torrentUrlSeeds()) {
        const QString u = seedUrl.trimmed();
        if (!u.isEmpty())
            handle.add_url_seed(u.toStdString());
    }
    for (const QString &seedUrl : item->torrentHttpSeeds()) {
        const QString u = seedUrl.trimmed();
        if (!u.isEmpty())
            handle.add_http_seed(u.toStdString());
    }

    // Apply persisted per-torrent speed limits here, on the handle we already
    // hold. The restore path adds asynchronously, so the m_handles entry isn't
    // populated until this point — AppController's post-restore call to
    // applyPerTorrentSpeedLimits() would otherwise no-op against an empty handle.
    const int downKbps = item->perTorrentDownLimitKBps();
    const int upKbps   = item->perTorrentUpLimitKBps();
    handle.set_download_limit(downKbps > 0 ? downKbps * 1024 : -1);
    handle.set_upload_limit(upKbps > 0 ? upKbps * 1024 : -1);

    item->setIsTorrent(true);
    const bool effectivePaused = startPaused || m_pausedIds.contains(item->id());
    if (!effectivePaused)
        item->setLastTryAt(QDateTime::currentDateTime());
    item->setStatus(effectivePaused ? DownloadItem::Status::Paused : DownloadItem::Status::Checking);
    // On the restore path (deferModels) skip the immediate status read: it calls
    // handle.status(), a session-lock IPC round-trip per item that serialised the
    // cold-start restore loop. Restored items already carry status/doneBytes from
    // downloads.json; the first state_update_alert (~1 s later) fills live stats.
    if (!deferModels)
        updateItemFromStatus(item, handle);

    // For .torrent files the metadata is already present — populate the file
    // model immediately so the metadata dialog shows files without waiting for
    // the first alert tick (which previously made it appear to "ping the swarm").
    if (!torrentFilePath.isEmpty() && !deferModels)
        updateModels(item->id(), handle, false);
}

void TorrentSessionManager::processAlerts() {
    if (!m_session)
        return;
    std::vector<libtorrent::alert *> alerts;
    m_session->pop_alerts(&alerts);
    for (libtorrent::alert *alert : alerts) {
        handleAlert(alert);
    }
    // Apply any IP-filter rebuilds requested during this alert burst as a
    // single operation. Per-ban rebuilds during the loop turned a heavy alert
    // burst into N² work; coalescing brings it back to one O(N) rebuild.
    flushIpFilterRebuild();
}

void TorrentSessionManager::handleAlert(libtorrent::alert *alert) {
    if (!alert)
        return;

    if (auto *externalIp = libtorrent::alert_cast<libtorrent::external_ip_alert>(alert)) {
        setDetectedExternalAddress(QString::fromStdString(externalIp->external_address.to_string()));
        return;
    }

    if (auto *dhtStats = libtorrent::alert_cast<libtorrent::dht_stats_alert>(alert)) {
        // Total nodes = sum of live nodes across every routing-table bucket.
        int nodes = 0;
        for (const auto &bucket : dhtStats->routing_table)
            nodes += bucket.num_nodes;
        if (m_dhtNodes != nodes) {
            m_dhtNodes = nodes;
            emit dhtNodesChanged();
        }
        return;
    }

    if (auto *update = libtorrent::alert_cast<libtorrent::state_update_alert>(alert)) {
        m_hasIncomingPending = false;
        m_didInspectPeersThisTick = false;
        for (const auto &status : update->status) {
            const QString id = idForHandle(status.handle);
            DownloadItem *item = m_items.value(id, nullptr).data();
            if (item) {
                // Pass the already-fetched torrent_status directly — avoids a
                // redundant handle.status() IPC call (acquires session mutex)
                // per torrent per alert tick.
                updateItemFromStatus(item, status.handle, status);
                updateModels(id, status.handle, status);
            }
        }
        emit torrentBatchUpdated();

        // Full peer inspection skipped (no dialog open, no auto-ban rules).
        // Still check incoming connections via one active handle so the
        // status-bar indicator doesn't require opening properties dialog.
        if (!m_didInspectPeersThisTick) {
            for (const auto &st : update->status) {
                if (st.num_peers > 0) {
                    std::vector<libtorrent::peer_info> infos;
                    st.handle.get_peer_info(infos);
                    for (const auto &peer : infos) {
                        if ((peer.flags & libtorrent::peer_info::local_connection) == libtorrent::peer_flags_t{}) {
                            m_hasIncomingPending = true;
                            break;
                        }
                    }
                    break; // one handle sufficient
                }
            }
        }

        if (m_hasIncomingPending != m_hasIncomingConnection) {
            if (m_hasIncomingPending) {
                // false → true: single-handle scan reliable enough
                m_hasIncomingConnection = true;
                emit hasIncomingConnectionChanged();
            } else if (m_didInspectPeersThisTick) {
                // true → false: only from full inspection (all torrents),
                // never from lightweight one-handle scan — avoids flicker
                // when the single checked handle has no peers transiently.
                m_hasIncomingConnection = false;
                emit hasIncomingConnectionChanged();
            }
        }
        return;
    }

    if (auto *added = libtorrent::alert_cast<libtorrent::add_torrent_alert>(alert)) {
        // Completion of an async_add_torrent() submitted on the restore path.
        // Recover the DownloadItem* from userdata; ignore alerts we didn't tag
        // (e.g. synchronous interactive adds don't set userdata).
        DownloadItem *item = added->params.userdata.get<DownloadItem>();
        if (!item)
            return;
        m_pendingAsyncAdds.remove(item->id());
        if (added->error || !added->handle.is_valid()) {
            emit torrentErrored(item->id(),
                added->error ? QString::fromStdString(added->error.message())
                             : QStringLiteral("Failed to add torrent"));
            return;
        }
        const bool startPaused =
            (added->params.flags & libtorrent::torrent_flags::paused) != libtorrent::torrent_flags_t{};
        // torrentFilePath is only used to decide the immediate metadata-model
        // populate, which is skipped on the restore path anyway — pass empty.
        finalizeTorrentAdd(item, added->handle, startPaused, /*deferModels=*/true, QString());
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
            item->setSpeed(0);
            item->setEtaSpeed(0);
            updateItemFromStatus(item, finished->handle);
            updateModels(id, finished->handle);
        }
        // Only emit torrentFinished once per torrent lifetime. Rechecks
        // (Checking → Seeding) and startup re-fires are suppressed because
        // restoreTorrent pre-populates m_firedFinishedIds for already-done torrents.
        // Status-based detection was unreliable: post_torrent_updates could set
        // Seeding before the alert arrived, making a genuine completion look like a recheck.
        if (m_firedFinishedIds.contains(id))
            return;
        m_firedFinishedIds.insert(id);
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
            // Store the raw libtorrent buffer directly. Previously the blob
            // was Base64-encoded into a QString here, then Base64-decoded again
            // on the AppController side before write — and Base64-encoded once
            // more on startup load before being decoded a final time. Two full
            // round-trips of redundant Base64 (plus QString's UTF-16 doubling)
            // for an opaque blob the QML layer never sees.
            const auto buf = libtorrent::write_resume_data_buf(resume->params);
            QByteArray raw(buf.data(), static_cast<qsizetype>(buf.size()));
            item->setTorrentResumeData(std::move(raw));
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
            m_trackerAlertSnapshots[id][trackerStatusKey(QString::fromUtf8(announce->tracker_url()).left(1024))] = snapshot;
            updateModels(id, announce->handle, /*forceTrackerUpdate=*/false, /*trackerOnly=*/true);
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
            m_trackerAlertSnapshots[id][trackerStatusKey(QString::fromUtf8(reply->tracker_url()).left(1024))] = snapshot;
            updateModels(id, reply->handle, /*forceTrackerUpdate=*/false, /*trackerOnly=*/true);
        }
        return;
    }

    if (auto *warning = libtorrent::alert_cast<libtorrent::tracker_warning_alert>(alert)) {
        const QString id = idForHandle(warning->handle);
        if (!id.isEmpty()) {
            TrackerAlertSnapshot snapshot;
            snapshot.status = QStringLiteral("Warning");
            snapshot.message = QString::fromUtf8(warning->warning_message()).left(512);
            snapshot.updatedAt = QDateTime::currentDateTimeUtc();
            m_trackerAlertSnapshots[id][trackerStatusKey(QString::fromUtf8(warning->tracker_url()).left(1024))] = snapshot;
            updateModels(id, warning->handle, /*forceTrackerUpdate=*/false, /*trackerOnly=*/true);
        }
        return;
    }

    if (auto *trackerError = libtorrent::alert_cast<libtorrent::tracker_error_alert>(alert)) {
        const QString id = idForHandle(trackerError->handle);
        if (!id.isEmpty()) {
            TrackerAlertSnapshot snapshot;
            snapshot.status = QStringLiteral("Error");
            const QString reason = QString::fromUtf8(trackerError->failure_reason()).left(512);
            snapshot.message = reason.isEmpty()
                ? QString::fromStdString(trackerError->error.message()).left(512)
                : reason;
            snapshot.updatedAt = QDateTime::currentDateTimeUtc();
            m_trackerAlertSnapshots[id][trackerStatusKey(QString::fromUtf8(trackerError->tracker_url()).left(1024))] = snapshot;
            updateModels(id, trackerError->handle, /*forceTrackerUpdate=*/false, /*trackerOnly=*/true);
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
            m_trackerAlertSnapshots[id][trackerStatusKey(QString::fromUtf8(scrapeReply->tracker_url()).left(1024))] = snapshot;
            updateModels(id, scrapeReply->handle, /*forceTrackerUpdate=*/false, /*trackerOnly=*/true);
        }
        return;
    }

    if (auto *scrapeFailed = libtorrent::alert_cast<libtorrent::scrape_failed_alert>(alert)) {
        const QString id = idForHandle(scrapeFailed->handle);
        if (!id.isEmpty()) {
            TrackerAlertSnapshot snapshot;
            snapshot.status = QStringLiteral("Error");
            const QString reason = QString::fromUtf8(scrapeFailed->error_message()).left(512);
            snapshot.message = reason.isEmpty()
                ? QString::fromStdString(scrapeFailed->error.message()).left(512)
                : reason;
            snapshot.updatedAt = QDateTime::currentDateTimeUtc();
            m_trackerAlertSnapshots[id][trackerStatusKey(QString::fromUtf8(scrapeFailed->tracker_url()).left(1024))] = snapshot;
            updateModels(id, scrapeFailed->handle, /*forceTrackerUpdate=*/false, /*trackerOnly=*/true);
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
                {
                    const int p = i < int(priorities.size()) ? int(std::uint8_t(priorities[std::size_t(i)])) : 4;
                    entry.wanted = p != 0;
                    // Skipped files keep Normal as their remembered level so
                    // re-enabling them restores a sane priority.
                    entry.priority = p == 0 ? 4 : p;
                }
                entry.fileIndex = i;
                entry.downloaded = i < int(progress.size()) ? qint64(progress[std::size_t(i)]) : 0;
                entries.push_back(entry);
            }
            model->setEntries(entries);
        }
        return;
    }
}

void TorrentSessionManager::updateModels(const QString &downloadId, const libtorrent::torrent_handle &handle, bool forceTrackerUpdate, bool trackerOnly) {
    if (!handle.is_valid())
        return;
    updateModels(downloadId, handle, handle.status(), forceTrackerUpdate, trackerOnly);
}

void TorrentSessionManager::updateModels(const QString &downloadId, const libtorrent::torrent_handle &handle, const libtorrent::torrent_status &st, bool forceTrackerUpdate, bool trackerOnly) {
    if (!handle.is_valid())
        return;

    int dhtPeerCount = 0;
    int dhtSeederCount = 0;
    int pexPeerCount = 0;
    int pexSeederCount = 0;
    int lsdPeerCount = 0;
    int lsdSeederCount = 0;

    // Tracker-alert refresh path: tracker alerts don't change the connected
    // peer set or file-progress, so the heavy peer-info scan (with per-peer
    // geo-IP lookups, QStringList allocs, and auto-ban regex matching) is
    // wasted work that scaled with N_torrents × N_trackers and was the
    // dominant cause of UI lag while seeding many torrents. We still refresh
    // the tracker model below — the DHT/PEX/LSD counts shown there will be
    // stale until the next state_update_alert tick (~2s), which is fine
    // because those rows are derived from the live peer set anyway.
    if (trackerOnly)
        goto tracker_refresh;

    {
    auto *fileModel = qobject_cast<TorrentFileModel *>(m_fileModels.value(downloadId, nullptr));
    const auto ti = st.torrent_file.lock();
    if (fileModel && ti) {
        const auto &files = ti->files();

        if (fileModel->fileCount() != files.num_files()) {
            const auto priorities = handle.get_file_priorities();
            QVector<TorrentFileModel::Entry> entries;
            entries.reserve(files.num_files());
            for (int i = 0; i < files.num_files(); ++i) {
                TorrentFileModel::Entry entry;
                const auto fileIndex = libtorrent::file_index_t{i};
                entry.name = QString::fromStdString(std::string(files.file_name(fileIndex)));
                entry.path = QString::fromStdString(files.file_path(fileIndex));
                entry.size = files.file_size(fileIndex);
                {
                    const int p = i < int(priorities.size()) ? int(std::uint8_t(priorities[std::size_t(i)])) : 4;
                    entry.wanted = p != 0;
                    entry.priority = p == 0 ? 4 : p;
                }
                entry.fileIndex = i;
                entries.push_back(entry);
            }
            fileModel->setEntries(entries);
        }

        // file_progress() iterates every piece for every file inside libtorrent
        // — non-trivial CPU on large torrents — so skip the call entirely when
        // no view is observing the model. The dialog re-enables live updates
        // and triggers a refresh on the next alert tick when it becomes visible.
        if (fileModel->liveUpdatesEnabled()) {
            const std::vector<std::int64_t> progress = handle.file_progress(libtorrent::torrent_handle::piece_granularity);
            QVector<qint64> downloaded;
            downloaded.reserve(int(progress.size()));
            for (std::int64_t value : progress)
                downloaded.push_back(value);
            fileModel->updateProgress(downloaded);
        }
    }

    if (m_pausedIds.contains(downloadId)) {
        if (auto *peerModel = qobject_cast<TorrentPeerModel *>(m_peerModels.value(downloadId, nullptr))) {
            if (peerModel->liveUpdatesEnabled()) {
                peerModel->setLocalLocation(m_hasLocalCoordinates, m_localLatitude, m_localLongitude);
                if (!m_externalAddress.isEmpty()) {
                    const int listenPort = m_session ? m_session->listen_port() : 0;
                    peerModel->setLocalInfo(m_externalAddress, listenPort, m_localCountryCode,
                                            m_localRegionName, m_localCityName,
                                            defaultTorrentUserAgent(m_settings));
                }
            }
            peerModel->setEntries({});
        }
        return;
    }

    auto *peerModel = qobject_cast<TorrentPeerModel *>(m_peerModels.value(downloadId, nullptr));
    if (peerModel && peerModel->liveUpdatesEnabled()) {
        // setLocalLocation/setLocalInfo drive the peer world-map overlay — only
        // needed when the dialog is open. listen_port() acquires the session lock;
        // calling it for 32 torrents every 2s with no dialog open was a major
        // source of lock contention (each call ~3-4ms under load).
        peerModel->setLocalLocation(m_hasLocalCoordinates, m_localLatitude, m_localLongitude);
        if (!m_externalAddress.isEmpty()) {
            const int listenPort = m_session ? m_session->listen_port() : 0;
            peerModel->setLocalInfo(m_externalAddress, listenPort, m_localCountryCode,
                                    m_localRegionName, m_localCityName,
                                    defaultTorrentUserAgent(m_settings));
        }
    } else {
        peerModel = nullptr;
    }

    const bool shouldInspectPeers = peerModel
        || !m_manualBannedPeers.isEmpty()
        || !m_blockedPeerUserAgentTerms.isEmpty()
        || !m_blockedPeerCountries.isEmpty()
        || m_autoBanAbusivePeers
        || m_autoBanMediaPlayerPeers;
    std::vector<libtorrent::peer_info> peerInfos;
    if (shouldInspectPeers) {
        handle.get_peer_info(peerInfos);
    }
    if (shouldInspectPeers) {
        m_didInspectPeersThisTick = true;
        // Only allocate the entries vector when there's actually a peer model
        // observing it. When auto-ban or manual bans alone drive the scan,
        // entries are pushed but immediately discarded — the allocation,
        // QStringList flags construction, and geo-IP lookup per peer are all
        // wasted work that scaled with N_torrents × peers-per-torrent.
        const bool needFullEntry = (peerModel != nullptr);
        QVector<TorrentPeerModel::Entry> entries;
        if (needFullEntry)
            entries.reserve(int(peerInfos.size()));
        bool anyBanChanged = false;
        for (const auto &peer : peerInfos) {
            TorrentPeerModel::Entry entry;
            entry.endpoint = QString::fromStdString(peer.ip.address().to_string());
            entry.port = peer.ip.port();
            entry.client = QString::fromStdString(peer.client).left(200);
            entry.progress = peer.progress;
            entry.downSpeed = peer.payload_down_speed;
            entry.upSpeed = peer.payload_up_speed;
            entry.downloaded = static_cast<qint64>(peer.total_download);
            entry.uploaded = static_cast<qint64>(peer.total_upload);
            entry.rtt = peer.rtt;
            entry.isSeed = (peer.flags & libtorrent::peer_info::seed) != libtorrent::peer_flags_t{};

            // Track incoming connections unconditionally — this drives the
            // hasIncomingConnection indicator independent of the peer model.
            if ((peer.flags & libtorrent::peer_info::local_connection) == libtorrent::peer_flags_t{})
                m_hasIncomingPending = true;

            // Build flags string only when a peer model is observing — flag
            // string is otherwise unused and the QStringList allocations
            // accounted for a significant share of per-tick CPU when seeding
            // many torrents.
            if (needFullEntry) {
                QStringList fl;
                if ((peer.flags & libtorrent::peer_info::local_connection) != libtorrent::peer_flags_t{}) {
                    fl << QStringLiteral("OUT");
                } else {
                    fl << QStringLiteral("IN");
                }
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

            if (needFullEntry) {
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
            }
            // Geo lookup needed whenever the peer model is visible OR when the
            // user has a country-based ban list active. Otherwise it's pure waste.
            const bool needGeo = needFullEntry || !m_blockedPeerCountries.isEmpty();
            if (needGeo) {
                lookupPeerLocation(entry.endpoint, &entry.countryCode, &entry.regionCode, &entry.regionName,
                                   &entry.cityName, &entry.latitude, &entry.longitude);
            }

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

            if (needFullEntry)
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
    } // end !trackerOnly peer/file scan block

tracker_refresh:
    // Tracker models are notably heavier because they also resolve and
    // geo-locate tracker endpoints, so keep those on the slower cadence
    // without penalizing the peer list refresh rate.
    // forceTrackerUpdate bypasses the cadence gate (e.g. after a manual reannounce
    // so the status change is visible immediately rather than up to 3s later).
    if (!forceTrackerUpdate && m_modelTick % 3 != 0)
        return;

    // Skip tracker model rebuild entirely if no consumer is watching the model
    // (properties dialog closed). The tracker model still exists in m_trackerModels
    // but its data isn't visible — rebuilding it allocates QVectors of entries,
    // does QUrl parsing, geo-IP lookups, and string formatting that nothing reads.
    {
        auto *tm = qobject_cast<TorrentTrackerModel *>(m_trackerModels.value(downloadId, nullptr));
        if (tm && !tm->liveUpdatesEnabled())
            return;
    }

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
            libtorrent::time_point32 earliestNextAnnounce = (libtorrent::time_point32::max)();
            for (const auto &endpoint : tracker.endpoints) {
                for (const auto &infohash : endpoint.info_hashes) {
                    anyUpdating = anyUpdating || infohash.updating;
                    anyStarted = anyStarted || infohash.start_sent;
                    anyCompleted = anyCompleted || infohash.complete_sent;
                    anyFailures = anyFailures || (infohash.fails > 0);
                    if (infohash.next_announce != (libtorrent::time_point32::min)()
                            && infohash.next_announce < earliestNextAnnounce)
                        earliestNextAnnounce = infohash.next_announce;
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

            // Compute seconds until next announce (-1 = unknown/not applicable).
            if (earliestNextAnnounce != (libtorrent::time_point32::max)()) {
                const auto nowLt = libtorrent::time_point_cast<libtorrent::seconds32>(
                    libtorrent::clock_type::now());
                const auto deltaSecs = libtorrent::total_seconds(earliestNextAnnounce - nowLt);
                entry.nextAnnounceSecs = deltaSecs > 0 ? static_cast<int>(deltaSecs) : 0;
            }

            if (!endpointError.isEmpty()) {
                // Map timeout errors to the dedicated "Not working / Timed out" state so
                // the user sees a distinct, human-readable status instead of a raw OS error.
                const bool isTimeout = endpointError.contains(QLatin1String("timed out"),
                                                               Qt::CaseInsensitive);
                entry.status = isTimeout ? QStringLiteral("Not working") : QStringLiteral("Error");
                entry.message = isTimeout ? QStringLiteral("Timed out") : endpointError;
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
                entry.status = QStringLiteral("Not working");
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
            // Live transient states derived directly from libtorrent must never be
            // overridden by a cached snapshot — the snapshot only fills in the gap
            // when the tracker is Idle between announces.
            const bool entryIsTransient = entry.status == QLatin1String("Announcing")
                                       || entry.status == QLatin1String("Reannouncing")
                                       || ((entry.status == QLatin1String("Error")
                                            || entry.status == QLatin1String("Not working"))
                                           && anyFailures);
            if (snapshot.updatedAt.isValid() && !entryIsTransient) {
                const bool isWorking = snapshot.status == QLatin1String("Working");
                const qint64 expirySecs = isWorking ? kTrackerSnapshotWorkingExpiryNever
                                                    : kTrackerSnapshotErrorExpirySecs;
                const qint64 ageSecs = snapshot.updatedAt.secsTo(QDateTime::currentDateTimeUtc());
                if (ageSecs <= expirySecs) {
                    if (!snapshot.status.isEmpty())
                        entry.status = snapshot.status;
                    if (!snapshot.message.isEmpty())
                        entry.message = snapshot.message;
                    if (snapshot.seeders >= 0)
                        entry.seeders = snapshot.seeders;
                    if (snapshot.peers >= 0)
                        entry.peers = snapshot.peers;
                }
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
                        if (info.error() == QHostInfo::NoError && !info.addresses().isEmpty()) {
                            // Evict oldest half when cap reached — tracker hostnames are stable
                            // across the session so this rarely fires, but prevents unbounded growth
                            // when torrents are added/removed over a long session.
                            constexpr int kTrackerIpCacheMax = 512;
                            if (m_trackerIpCache.size() >= kTrackerIpCacheMax) {
                                auto it = m_trackerIpCache.begin();
                                const int toRemove = kTrackerIpCacheMax / 2;
                                for (int i = 0; i < toRemove && it != m_trackerIpCache.end(); ++i)
                                    it = m_trackerIpCache.erase(it);
                            }
                            m_trackerIpCache[hostname] = info.addresses().first().toString();
                        }
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
    m_geoDb->insertionOrder.clear();
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
            const double lat = coordData.type == MMDB_DATA_TYPE_DOUBLE ? coordData.double_value : coordData.float_value;
            if (lat >= -90.0 && lat <= 90.0) {
                resolved.latitude = lat;
                resolved.hasCoordinates = true;
            }
        }
        if (MMDB_aget_value(&entry, &coordData, longitudePath) == MMDB_SUCCESS && coordData.has_data
            && (coordData.type == MMDB_DATA_TYPE_DOUBLE || coordData.type == MMDB_DATA_TYPE_FLOAT)) {
            const double lon = coordData.type == MMDB_DATA_TYPE_DOUBLE ? coordData.double_value : coordData.float_value;
            if (lon >= -180.0 && lon <= 180.0)
                resolved.longitude = lon;
        }
    }

    // Evict oldest quarter of entries when the cache reaches its limit so a
    // swarm with thousands of unique peers cannot grow it without bound.
    // Eviction follows insertion order (FIFO) — QHash iteration order is
    // unspecified and previously dropped random entries, occasionally evicting
    // freshly-inserted hot peers and forcing immediate re-lookup.
    constexpr int kGeoCacheMaxEntries = 8192;
    if (m_geoDb->cache.size() >= kGeoCacheMaxEntries) {
        int toRemove = kGeoCacheMaxEntries / 4;
        while (toRemove-- > 0 && !m_geoDb->insertionOrder.isEmpty()) {
            const QString oldest = m_geoDb->insertionOrder.takeFirst();
            m_geoDb->cache.remove(oldest);
        }
    }
    m_geoDb->cache.insert(ip, resolved);
    m_geoDb->insertionOrder.append(ip);
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
    updateItemFromStatus(item, handle, handle.status());
}

void TorrentSessionManager::updateItemFromStatus(DownloadItem *item, const libtorrent::torrent_handle &handle,
                                                 const libtorrent::torrent_status &st) {
    if (!item || !handle.is_valid())
        return;

    item->setTorrentHasMetadata(st.has_metadata);
    // st.torrent_file is populated by post_torrent_updates() (default flags include
    // query_torrent_file). Locking a weak_ptr is a lock-free atomic op — zero
    // session-mutex cost. Using handle.torrent_file() instead acquires the session
    // read-lock for every torrent every 2-second tick and was the dominant source
    // of updateItemFromStatus latency (2-6 ms per torrent = 64-200 ms per tick).
    const auto ti = st.torrent_file.lock();
    // All fields derived from torrent_info are immutable once metadata is
    // present. Deriving them every alert tick (string conversions, a QLocale
    // construction for the creation date, web-seed list pulls) was pure wasted
    // CPU that scaled with N seeding torrents — the setters dedupe, so no
    // signals fired, but the conversions still ran. Apply them once per torrent.
    if (st.has_metadata && ti && !m_staticMetadataApplied.contains(item->id())) {
        m_staticMetadataApplied.insert(item->id());
        const QString torrentName = QString::fromStdString(ti->name());
        // Never clobber a filename the user manually renamed in the metadata
        // dialog or file-properties dialog; once set it stays until the user
        // renames again.
        if (!torrentName.isEmpty() && !item->isFilenameManuallySet())
            item->setFilename(torrentName);
        const auto bestHash = ti->info_hashes().get_best();
        item->setTorrentInfoHash(toHexString(bestHash.to_string()));
        item->setTorrentIsSingleFile(ti->num_files() == 1);
        item->setTorrentIsPrivate(ti->priv());
        item->setTorrentComment(QString::fromStdString(ti->comment()));
        item->setTorrentCreator(QString::fromStdString(ti->creator()));
        item->setTorrentPiecesTotal(ti->num_pieces());
        // creation_date() returns time_t; 0 means not set.
        const std::time_t cd = ti->creation_date();
        if (cd != 0) {
            const QDateTime dt = QDateTime::fromSecsSinceEpoch(static_cast<qint64>(cd)).toLocalTime();
            item->setTorrentCreatedOn(QLocale().toString(dt, QLocale::ShortFormat));
        } else {
            item->setTorrentCreatedOn(QString());
        }
        QStringList urlSeeds, httpSeeds;
        for (const auto &seed : handle.url_seeds())
            urlSeeds.push_back(QString::fromStdString(seed));
        for (const auto &seed : handle.http_seeds())
            httpSeeds.push_back(QString::fromStdString(seed));
        item->setTorrentUrlSeeds(urlSeeds);
        item->setTorrentHttpSeeds(httpSeeds);
    }

    // st.flags carries the same data as handle.flags() — read from the
    // already-fetched status struct rather than making a separate session IPC call.
    const auto flags = st.flags;
    item->setTorrentDisableDht(
        (flags & libtorrent::torrent_flags::disable_dht) != libtorrent::torrent_flags_t{});
    item->setTorrentDisablePex(
        (flags & libtorrent::torrent_flags::disable_pex) != libtorrent::torrent_flags_t{});
    item->setTorrentDisableLsd(
        (flags & libtorrent::torrent_flags::disable_lsd) != libtorrent::torrent_flags_t{});
    item->setTorrentSequential(
        (flags & libtorrent::torrent_flags::sequential_download) != libtorrent::torrent_flags_t{});

    if (st.errc)
        item->setErrorString(QString::fromStdString(st.errc.message()));
    item->setTotalBytes(st.total_wanted > 0 ? st.total_wanted : item->totalBytes());
    item->setDoneBytes(st.total_wanted_done);
    item->setSpeed(st.download_payload_rate);
    item->setTorrentUploadSpeed(st.upload_payload_rate);
    item->setTorrentSeeders(st.num_seeds);
    // num_complete/num_incomplete come from tracker scrape data (-1 = no scrape yet).
    // list_seeds/list_peers count known peers in libtorrent's peer list, which is
    // unrelated to what trackers report as the total swarm size.
    item->setTorrentListSeeders(st.num_complete >= 0 ? st.num_complete : st.list_seeds);
    item->setTorrentPeers(st.num_peers);
    item->setTorrentListPeers(st.num_incomplete >= 0 ? st.num_incomplete : st.list_peers);
    item->setTorrentUploaded(st.all_time_upload);
    item->setTorrentDownloaded(st.all_time_download);
    item->setTorrentRatio(st.all_time_download > 0
                              ? double(st.all_time_upload) / double(st.all_time_download)
                              : 0.0);
    item->setTorrentAvailability(st.distributed_copies);
    item->setTorrentPiecesDone(st.num_pieces);
    // setTorrentPiecesTotal is applied once in the static-metadata block above
    // (it's immutable once metadata arrives).
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
        || (flags & libtorrent::torrent_flags::paused) != libtorrent::torrent_flags_t{}) {
        item->setStatus(DownloadItem::Status::Paused);
        // libtorrent can report stale nonzero rates on the tick immediately
        // after pausing; zero them explicitly so the torrent doesn't appear
        // in the Active category filter.
        item->setSpeed(0);
        item->setTorrentUploadSpeed(0);
    } else if (st.is_seeding || st.state == libtorrent::torrent_status::finished) {
        item->setStatus(DownloadItem::Status::Seeding);
        item->setSpeed(0);
        item->setEtaSpeed(0);
        if (!m_seedingStartTimes.contains(id)) {
            m_seedingStartTimes[id] = QDateTime::currentDateTimeUtc();
            m_lastUploadActivityTime[id] = QDateTime::currentDateTimeUtc();
        }
        checkShareLimits(id, item, m_settings);
    } else if (st.state == libtorrent::torrent_status::checking_resume_data
               || st.state == libtorrent::torrent_status::checking_files) {
        item->setStatus(DownloadItem::Status::Checking);
        // st.progress is the authoritative check progress (0..1); override the
        // doneBytes value set above so the generic progress() formula reflects it.
        if (st.total_wanted > 0)
            item->setDoneBytes(static_cast<qint64>(st.progress * st.total_wanted));
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

QString TorrentSessionManager::torrentCurrentRootName(const QString &downloadId) const {
#if defined(STELLAR_HAS_LIBTORRENT)
    const auto handle = m_handles.value(downloadId);
    if (!handle.is_valid() || !handle.torrent_file())
        return {};
    const auto &files = handle.torrent_file()->files();
    if (files.num_files() == 0)
        return {};
    // The root is the first path component of the first file path.
    QString path = QString::fromStdString(files.file_path(libtorrent::file_index_t{0}));
    path.replace(QLatin1Char('\\'), QLatin1Char('/'));
    const int sep = path.indexOf(QLatin1Char('/'));
    return sep > 0 ? path.left(sep) : path;
#else
    Q_UNUSED(downloadId);
    return {};
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

void TorrentSessionManager::setTorrentDownloadMode(const QString &downloadId, bool sequential, bool firstLastPieces) {
#if defined(STELLAR_HAS_LIBTORRENT)
    const auto handle = m_handles.value(downloadId);
    if (!handle.is_valid())
        return;

    if (sequential)
        handle.set_flags(libtorrent::torrent_flags::sequential_download);
    else
        handle.unset_flags(libtorrent::torrent_flags::sequential_download);

    // Clear any previously set piece deadlines before applying new ones.
    handle.clear_piece_deadlines();

    if (firstLastPieces) {
        // Prioritize first and last pieces by setting tight deadlines on them.
        // libtorrent downloads these at highest priority while using normal
        // rarity-based selection for the rest of the torrent.
        const auto ti = handle.torrent_file();
        if (ti) {
            const int numPieces = ti->num_pieces();
            if (numPieces > 0) {
                handle.set_piece_deadline(libtorrent::piece_index_t{0}, 0);
                if (numPieces > 1)
                    handle.set_piece_deadline(libtorrent::piece_index_t{numPieces - 1}, 0);
                // A few extra tail pieces for container footers (e.g. MP4 moov atom).
                const int tailStart = std::max(1, numPieces - std::max(1, numPieces / 50));
                for (int i = tailStart; i < numPieces - 1; ++i)
                    handle.set_piece_deadline(libtorrent::piece_index_t{i}, 0);
            }
        }
    }

    DownloadItem *item = m_items.value(downloadId, nullptr).data();
    if (item) {
        item->setTorrentSequential(sequential);
        item->setTorrentFirstLastPieces(firstLastPieces);
    }
    saveResumeData(downloadId);
#else
    Q_UNUSED(downloadId); Q_UNUSED(sequential); Q_UNUSED(firstLastPieces);
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

void TorrentSessionManager::refreshModelsNow(const QString &downloadId) {
#if defined(STELLAR_HAS_LIBTORRENT)
    const auto handle = m_handles.value(downloadId);
    if (!handle.is_valid())
        return;
    // Pass forceTrackerUpdate=true so the tracker model is rebuilt even though
    // this isn't triggered by a tracker alert.
    updateModels(downloadId, handle, /*forceTrackerUpdate=*/true, /*trackerOnly=*/false);
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
    } catch (...) {
        qWarning() << "[Torrent] piece_availability query failed";
    }
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
    } catch (...) {
        qWarning() << "[Torrent] get_piece_priorities query failed";
    }
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
    } catch (...) {
        qWarning() << "[Torrent] get_download_queue query failed";
    }

    return out;
#else
    Q_UNUSED(downloadId);
    return {};
#endif
}

int TorrentSessionManager::listenPort() const {
#if defined(STELLAR_HAS_LIBTORRENT)
    return m_session ? m_session->listen_port() : 0;
#else
    return 0;
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
    emit externalAddressChanged();
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
    emit externalAddressChanged();
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

// ── Torrent Creator ───────────────────────────────────────────────────────────
// Runs set_piece_hashes() (the slow SHA-1/SHA-256 hashing step) on a
// QtConcurrent thread so the UI stays responsive. Progress is reported as a
// percent via torrentCreationProgress(). On completion torrentCreationFinished
// carries success=true and the output path, or success=false and an error string.

void TorrentSessionManager::cancelTorrentCreation() {
    m_torrentCreationCancelled.store(true, std::memory_order_release);
}

void TorrentSessionManager::createTorrentFile(const QVariantMap &params) {
    m_torrentCreationCancelled.store(false, std::memory_order_release);

    const QStringList inputPaths   = params.value(QStringLiteral("inputPaths")).toStringList();
    const QString     outputPath   = params.value(QStringLiteral("outputPath")).toString();
    const QString     name         = params.value(QStringLiteral("name")).toString();
    const QString     comment      = params.value(QStringLiteral("comment")).toString();
    const QString     description  = params.value(QStringLiteral("description")).toString();
    const QStringList trackers     = params.value(QStringLiteral("trackers")).toStringList();
    const QStringList webSeeds     = params.value(QStringLiteral("webSeeds")).toStringList();
    const bool        isPrivate    = params.value(QStringLiteral("isPrivate")).toBool();
    const int         pieceSizeArg = params.value(QStringLiteral("pieceSize")).toInt(); // 0 = auto
    const QString     creatorTag   = params.value(QStringLiteral("creatorTag")).toString();

    if (inputPaths.isEmpty() || outputPath.isEmpty()) {
        emit torrentCreationFinished(false, QStringLiteral("No input files or output path specified"));
        return;
    }

    // Capture the cancel-flag pointer so the lambda doesn't hold 'this'.
    std::atomic<bool> *cancelFlag = &m_torrentCreationCancelled;

    // We need a QObject* to emit signals from the thread; use a direct connection
    // back to the main thread via QMetaObject::invokeMethod.
    QPointer<TorrentSessionManager> self = this;

    // Fire-and-forget: the worker reports completion via QMetaObject::invokeMethod
    // through 'self', so the returned QFuture is intentionally discarded.
    // std::ignore silences QtConcurrent::run's [[nodiscard]] (MSVC C4858).
    std::ignore = QtConcurrent::run([=]() {
        namespace lt = libtorrent;

        try {
            lt::file_storage fs;

            // Build file_storage from each dropped input path.
            for (const QString &inputPath : inputPaths) {
                const std::string stdPath = inputPath.toStdString();
                QFileInfo fi(inputPath);
                if (!fi.exists()) {
                    QMetaObject::invokeMethod(self, [=]() {
                        if (self) emit self->torrentCreationFinished(
                            false,
                            QStringLiteral("Path not found: %1").arg(inputPath));
                    }, Qt::QueuedConnection);
                    return;
                }
                // add_files handles both single files and whole directory trees.
                lt::add_files(fs, stdPath);
            }

            if (fs.num_files() == 0 || fs.total_size() == 0) {
                QMetaObject::invokeMethod(self, [=]() {
                    if (self) emit self->torrentCreationFinished(false, QStringLiteral("No files found to hash"));
                }, Qt::QueuedConnection);
                return;
            }

            lt::create_torrent creator(fs, pieceSizeArg);

            // Set metadata.
            if (!comment.isEmpty())
                creator.set_comment(comment.toUtf8().constData());
            if (!creatorTag.isEmpty())
                creator.set_creator(creatorTag.toUtf8().constData());
            creator.set_priv(isPrivate);

            // Add trackers — each on its own tier so they are tried in order.
            int tier = 0;
            for (const QString &url : trackers) {
                const QString trimmed = url.trimmed();
                if (!trimmed.isEmpty())
                    creator.add_tracker(trimmed.toStdString(), tier++);
            }

            // Add HTTP/URL web seeds.
            for (const QString &url : webSeeds) {
                const QString trimmed = url.trimmed();
                if (!trimmed.isEmpty())
                    creator.add_url_seed(trimmed.toStdString());
            }

            // Embed the description as a custom key in the info dictionary
            // using a comment field (no standard key for this; we use "x-description"
            // in the root — not info — dict, appended after generate()).
            // We cannot inject into the info dict from create_torrent, so store
            // it as the comment when description is provided and comment is not.
            // This is the most widely-supported approach.
            if (comment.isEmpty() && !description.isEmpty())
                creator.set_comment(description.toUtf8().constData());

            const int totalPieces = creator.num_pieces();

            // Determine the base path for set_piece_hashes: parent of the first input.
            // For multiple inputs they should share a common parent; use that.
            QString basePath;
            if (!inputPaths.isEmpty()) {
                basePath = QFileInfo(inputPaths.first()).absolutePath();
            }

            lt::error_code ec;
            // set_piece_hashes reads every file and SHA-hashes each piece.
            // We use the callback overload to report progress and honour cancellation.
            lt::set_piece_hashes(creator, basePath.toStdString(),
                [&](lt::piece_index_t p) {
                    if (cancelFlag->load(std::memory_order_acquire))
                        throw std::runtime_error("cancelled");

                    if (totalPieces > 0) {
                        const int pct = static_cast<int>(
                            (static_cast<int>(p) + 1) * 100 / totalPieces);
                        QMetaObject::invokeMethod(self, [=]() {
                            if (self) emit self->torrentCreationProgress(pct);
                        }, Qt::QueuedConnection);
                    }
                }, ec);

            if (ec) {
                const QString msg = QString::fromStdString(ec.message());
                QMetaObject::invokeMethod(self, [=]() {
                    if (self) emit self->torrentCreationFinished(false, msg);
                }, Qt::QueuedConnection);
                return;
            }

            if (cancelFlag->load(std::memory_order_acquire)) {
                QMetaObject::invokeMethod(self, [=]() {
                    if (self) emit self->torrentCreationFinished(false, QStringLiteral("cancelled"));
                }, Qt::QueuedConnection);
                return;
            }

            // Generate and write the .torrent file.
            const std::vector<char> buf = creator.generate_buf();

            QSaveFile file(outputPath);
            if (!file.open(QIODevice::WriteOnly)) {
                const QString msg = file.errorString();
                QMetaObject::invokeMethod(self, [=]() {
                    if (self) emit self->torrentCreationFinished(false, msg);
                }, Qt::QueuedConnection);
                return;
            }
            file.write(buf.data(), static_cast<qint64>(buf.size()));
            if (!file.commit()) {
                const QString msg = file.errorString();
                QMetaObject::invokeMethod(self, [=]() {
                    if (self) emit self->torrentCreationFinished(false, msg);
                }, Qt::QueuedConnection);
                return;
            }

            QMetaObject::invokeMethod(self, [=]() {
                if (self) emit self->torrentCreationFinished(true, outputPath);
            }, Qt::QueuedConnection);

        } catch (const std::exception &ex) {
            const QString msg = QString::fromLocal8Bit(ex.what());
            QMetaObject::invokeMethod(self, [=]() {
                if (self) emit self->torrentCreationFinished(false, msg);
            }, Qt::QueuedConnection);
        }
    });
}

#endif
