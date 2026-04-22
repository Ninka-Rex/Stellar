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
#include <QCryptographicHash>
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
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSaveFile>
#include <algorithm>
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
#include <libtorrent/session_stats.hpp>
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

bool interfaceLooksLikeVpn(const QNetworkInterface &iface) {
    if (!iface.isValid())
        return false;

    const QString name = iface.name().trimmed().toLower();
    const QString human = iface.humanReadableName().trimmed().toLower();

    const QStringList strongTokens{
        QStringLiteral("tun"),
        QStringLiteral("tap"),
        QStringLiteral("wg"),
        QStringLiteral("wireguard"),
        QStringLiteral("ppp"),
        QStringLiteral("ipsec"),
        QStringLiteral("openvpn"),
        QStringLiteral("protonvpn"),
        QStringLiteral("nord"),
        QStringLiteral("mullvad"),
        QStringLiteral("surfshark"),
        QStringLiteral("expressvpn"),
        QStringLiteral("windscribe"),
        QStringLiteral("ivpn"),
        QStringLiteral("zerotier"),
        QStringLiteral("tailscale")
    };

    for (const QString &token : strongTokens) {
        if (name.contains(token) || human.contains(token))
            return true;
    }

    return false;
}

QNetworkInterface findPreferredVpnInterface() {
    const QList<QNetworkInterface> interfaces = QNetworkInterface::allInterfaces();

    QNetworkInterface bestCandidate;
    int bestScore = -1;

    for (const QNetworkInterface &iface : interfaces) {
        const QStringList bindAddresses = interfaceBindAddresses(iface);
        if (bindAddresses.isEmpty())
            continue;

        int score = -1;
        const QString name = iface.name().trimmed().toLower();
        const QString human = iface.humanReadableName().trimmed().toLower();

        if (name.startsWith(QStringLiteral("wg")) || human.contains(QStringLiteral("wireguard"))) {
            score = 400;
        } else if (name.startsWith(QStringLiteral("tun")) || name.startsWith(QStringLiteral("tap"))
                   || human.contains(QStringLiteral("openvpn"))) {
            score = 300;
        } else if (name.startsWith(QStringLiteral("ppp")) || human.contains(QStringLiteral("ppp"))
                   || human.contains(QStringLiteral("ipsec"))) {
            score = 200;
        } else if (interfaceLooksLikeVpn(iface)) {
            score = 100;
        }

        if (score < 0)
            continue;

        const bool hasIpv4 = std::any_of(bindAddresses.cbegin(), bindAddresses.cend(),
                                         [](const QString &addressText) {
                                             return QHostAddress(addressText).protocol()
                                                 == QAbstractSocket::IPv4Protocol;
                                         });
        if (hasIpv4)
            score += 10;

        if (score > bestScore) {
            bestScore = score;
            bestCandidate = iface;
        }
    }

    return bestCandidate;
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

QStringList geoDbCandidates() {
    const QString appDir = QCoreApplication::applicationDirPath();
    // Primary: the unified geo/ directory under the Stellar data root.
    // Fallbacks cover side-by-side installs and Flatpak bundle layouts.
    return {
        StellarPaths::geoDir() + QStringLiteral("/dbip-city-lite-2026-04.mmdb"),
        appDir + QStringLiteral("/data/dbip-city-lite-2026-04.mmdb"),
        appDir + QStringLiteral("/dbip-city-lite-2026-04.mmdb"),
        appDir + QStringLiteral("/../data/dbip-city-lite-2026-04.mmdb"),
        QDir::cleanPath(appDir + QStringLiteral("/../../app/data/dbip-city-lite-2026-04.mmdb")),
        QDir::cleanPath(appDir + QStringLiteral("/../../../app/data/dbip-city-lite-2026-04.mmdb"))
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

long double log2DistanceBytes(const QByteArray &bytes) {
    if (bytes.size() != 20)
        return -std::numeric_limits<long double>::infinity();

    int firstNonZero = -1;
    for (int i = 0; i < bytes.size(); ++i) {
        if (static_cast<unsigned char>(bytes[i]) != 0) {
            firstNonZero = i;
            break;
        }
    }
    if (firstNonZero < 0)
        return -std::numeric_limits<long double>::infinity();

    const int remainingBytes = bytes.size() - firstNonZero;
    const int take = std::min(8, remainingBytes);
    std::uint64_t top = 0;
    for (int i = 0; i < take; ++i)
        top = (top << 8) | static_cast<unsigned char>(bytes[firstNonZero + i]);

    int msb = 63;
    while (msb > 0 && ((top >> msb) & 1ULL) == 0ULL)
        --msb;

    const int bitsTop = take * 8;
    const int leadingExtra = bitsTop - (msb + 1);
    const int bitlen = remainingBytes * 8 - leadingExtra;
    const long double normalized =
        static_cast<long double>(top) / std::ldexp(static_cast<long double>(1.0), bitsTop - 1);
    return static_cast<long double>(bitlen - 1) + std::log2(normalized);
}

bool distanceLess(const QByteArray &lhs, const QByteArray &rhs) {
    return std::lexicographical_compare(lhs.begin(), lhs.end(), rhs.begin(), rhs.end(),
        [](char l, char r) {
            return static_cast<unsigned char>(l) < static_cast<unsigned char>(r);
        });
}

QByteArray localPivotIdForRound(const QByteArray &localNodeId, std::uint64_t roundSeed, int pivotIndex) {
    QByteArray pivot = localNodeId;
    if (pivot.size() != 20)
        return {};

    QByteArray seed;
    seed.reserve(localNodeId.size() + int(sizeof(roundSeed)) + int(sizeof(pivotIndex)));
    seed.append(localNodeId);
    seed.append(reinterpret_cast<const char *>(&roundSeed), int(sizeof(roundSeed)));
    seed.append(reinterpret_cast<const char *>(&pivotIndex), int(sizeof(pivotIndex)));
    const QByteArray noise = QCryptographicHash::hash(seed, QCryptographicHash::Sha1);

    // Keep pivots near the local node-ID neighborhood by perturbing only the
    // low-order bytes instead of jumping to distant random keyspace regions.
    constexpr int kMixedBytes = 3;
    for (int i = 0; i < kMixedBytes; ++i) {
        const int pos = pivot.size() - 1 - i;
        pivot[pos] = char(static_cast<unsigned char>(pivot[pos])
                          ^ static_cast<unsigned char>(noise[i]));
    }
    return pivot;
}

QString confidenceLabelForPercent(int percent) {
    if (percent >= 85)
        return QStringLiteral("Very High");
    if (percent >= 70)
        return QStringLiteral("High");
    if (percent >= 50)
        return QStringLiteral("Medium");
    return QStringLiteral("Low");
}

QString dhtEstimatorCacheFilePath() {
    return StellarPaths::dataDir() + QStringLiteral("/dht_estimator_cache.json");
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
#if defined(STELLAR_HAS_LIBTORRENT)
    loadDhtEstimatorCache();
#endif
    m_alertTimer.setInterval(2000);
    connect(&m_alertTimer, &QTimer::timeout, this, [this]() {
#if defined(STELLAR_HAS_LIBTORRENT)
        ++m_modelTick;
        processAlerts();
        if (m_session) {
            m_session->post_torrent_updates();
            if (!m_lastSessionStatsRequest.isValid() || m_lastSessionStatsRequest.elapsed() >= 5000) {
                m_session->post_session_stats();
                m_session->post_dht_stats();
                m_lastSessionStatsRequest.restart();
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
#if defined(STELLAR_HAS_LIBTORRENT)
    saveDhtEstimatorCache(true);
#endif
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

void TorrentSessionManager::clearDhtEstimatorCache() {
#if defined(STELLAR_HAS_LIBTORRENT)
    m_recentDhtNodeIds.clear();
    m_recentPublishedDhtEstimates.clear();
    m_lastDhtNodeId.clear();
    m_cachedDhtGlobalEstimate = -1;
    m_lastDhtGlobalNodes = -1;
    m_lastDhtWarmupPercent = 0;
    m_lastDhtConfidencePercent = 0;
    m_lastDhtClosestSampleCount = 0;
    m_lastDhtPivotCount = 0;
    m_lastDhtKUsed = 0;
    m_lastDhtNodes = -1;
    m_lastDhtLiveNodesUpdate.invalidate();
    saveDhtEstimatorCache(true);
#endif
}

void TorrentSessionManager::loadDhtEstimatorCache() {
#if defined(STELLAR_HAS_LIBTORRENT)
    m_recentDhtNodeIds.clear();
    m_recentPublishedDhtEstimates.clear();

    QFile file(dhtEstimatorCacheFilePath());
    if (!file.exists() || !file.open(QIODevice::ReadOnly))
        return;

    const QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
    if (!doc.isObject())
        return;
    const QJsonObject root = doc.object();
    const QDateTime now = QDateTime::currentDateTimeUtc();
    const QDateTime cutoff = now.addSecs(-(60 * 60));

    const QJsonArray nodes = root.value(QStringLiteral("recentNodeIds")).toArray();
    for (const QJsonValue &value : nodes) {
        const QJsonObject obj = value.toObject();
        const QByteArray nodeId = QByteArray::fromHex(obj.value(QStringLiteral("idHex")).toString().toLatin1());
        const QDateTime seenAt = QDateTime::fromString(obj.value(QStringLiteral("seenAtUtc")).toString(), Qt::ISODate);
        if (nodeId.size() != 20 || !seenAt.isValid() || seenAt < cutoff)
            continue;
        m_recentDhtNodeIds.insert(nodeId, seenAt);
    }

    const QJsonArray estimates = root.value(QStringLiteral("recentPublishedRawEstimates")).toArray();
    for (const QJsonValue &value : estimates) {
        const qint64 n = static_cast<qint64>(value.toDouble(-1));
        if (n > 0)
            m_recentPublishedDhtEstimates.push_back(n);
    }
    constexpr int kMaxPublishedHistory = 40;
    if (m_recentPublishedDhtEstimates.size() > kMaxPublishedHistory)
        m_recentPublishedDhtEstimates.remove(0, m_recentPublishedDhtEstimates.size() - kMaxPublishedHistory);
#endif
}

void TorrentSessionManager::saveDhtEstimatorCache(bool force) {
#if defined(STELLAR_HAS_LIBTORRENT)
    if (!force) {
        const int saveIntervalMs = (m_cachedDhtGlobalEstimate > 0) ? (2 * 60 * 1000) : 15000;
        if (m_lastDhtCacheSave.isValid() && m_lastDhtCacheSave.elapsed() < saveIntervalMs)
            return;
    }

    QJsonObject root;
    QJsonArray nodes;
    for (auto it = m_recentDhtNodeIds.constBegin(); it != m_recentDhtNodeIds.constEnd(); ++it) {
        if (it.key().size() != 20 || !it.value().isValid())
            continue;
        QJsonObject obj;
        obj.insert(QStringLiteral("idHex"), QString::fromLatin1(it.key().toHex()));
        obj.insert(QStringLiteral("seenAtUtc"), it.value().toString(Qt::ISODate));
        nodes.push_back(obj);
    }
    root.insert(QStringLiteral("recentNodeIds"), nodes);

    QJsonArray estimates;
    for (qint64 n : m_recentPublishedDhtEstimates)
        estimates.push_back(static_cast<double>(n));
    root.insert(QStringLiteral("recentPublishedRawEstimates"), estimates);
    root.insert(QStringLiteral("savedAtUtc"), QDateTime::currentDateTimeUtc().toString(Qt::ISODate));

    QSaveFile out(dhtEstimatorCacheFilePath());
    if (out.open(QIODevice::WriteOnly)) {
        out.write(QJsonDocument(root).toJson(QJsonDocument::Compact));
        out.commit();
    }
    if (!m_lastDhtCacheSave.isValid())
        m_lastDhtCacheSave.start();
    else
        m_lastDhtCacheSave.restart();
#endif
}

qint64 TorrentSessionManager::dhtGlobalNodesEstimate() {
#if defined(STELLAR_HAS_LIBTORRENT)
    if (!m_session || !m_settings || !m_settings->torrentEnableDht())
        return -1;
    if (!m_lastDhtLiveNodesUpdate.isValid() || m_lastDhtLiveNodesUpdate.elapsed() > 60000)
        return -1;
    if (m_lastDhtConfidencePercent < 30)
        return -1;
    return m_cachedDhtGlobalEstimate > 0 ? m_cachedDhtGlobalEstimate : -1;
#else
    return -1;
#endif
}

int TorrentSessionManager::dhtEstimateWarmupPercent() const {
#if defined(STELLAR_HAS_LIBTORRENT)
    if (!m_settings || !m_settings->torrentEnableDht())
        return 0;
    return std::clamp(m_lastDhtWarmupPercent, 0, 100);
#else
    return 0;
#endif
}

QString TorrentSessionManager::dhtEstimateDebugText() const {
#if defined(STELLAR_HAS_LIBTORRENT)
    if (!m_settings || !m_settings->torrentEnableDht())
        return QStringLiteral("Confidence: DHT Off\nLive nodes: 0\nClosest samples: 0\nUnique node IDs: 0");
    if (m_cachedDhtGlobalEstimate <= 0)
        return QStringLiteral("Confidence: Estimating\nLive nodes: %1\nClosest samples: %2\nUnique node IDs: %3")
            .arg(std::max<qint64>(0, m_lastDhtNodes))
            .arg(std::max(0, m_lastDhtClosestSampleCount))
            .arg(m_recentDhtNodeIds.size());
    const int confidencePercent = std::clamp(m_lastDhtConfidencePercent, 0, 100);
    return QStringLiteral("Confidence: %1\nLive nodes: %2\nClosest samples: %3\nUnique node IDs: %4")
        .arg(confidenceLabelForPercent(confidencePercent))
        .arg(std::max<qint64>(0, m_lastDhtNodes))
        .arg(std::max(0, m_lastDhtClosestSampleCount))
        .arg(m_recentDhtNodeIds.size());
#else
    return QStringLiteral("DHT unavailable (libtorrent not built)");
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
        if (t.isEmpty() || existing.contains(t))
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
        | libtorrent::alert_category::tracker
        | libtorrent::alert_category::dht;
    pack.set_int(libtorrent::settings_pack::alert_mask,
                 static_cast<int>(static_cast<std::uint32_t>(alertMask)));

    pack.set_bool(libtorrent::settings_pack::enable_dht, settings->torrentEnableDht());
    pack.set_bool(libtorrent::settings_pack::enable_lsd, settings->torrentEnableLsd());
    pack.set_bool(libtorrent::settings_pack::enable_upnp, settings->torrentEnableUpnp());
    pack.set_bool(libtorrent::settings_pack::enable_natpmp, settings->torrentEnableNatPmp());
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
    const QString bindTarget = settings->torrentBindInterface().trimmed();
    if (!bindTarget.isEmpty()) {
        const QNetworkInterface iface = findNetworkInterfaceForBinding(bindTarget);
        applyInterfaceBinding(pack, interfaceBindAddresses(iface), settings->torrentListenPort());
    } else {
        const QNetworkInterface vpnIface = findPreferredVpnInterface();
        applyInterfaceBinding(pack, interfaceBindAddresses(vpnIface), settings->torrentListenPort());
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

    item->setIsTorrent(true);
    item->setStatus(startPaused ? DownloadItem::Status::Paused : DownloadItem::Status::Checking);
    updateItemFromStatus(item, handle);

    // For .torrent files the metadata is already present — populate the file
    // model immediately so the metadata dialog shows files without waiting for
    // the first alert tick (which previously made it appear to "ping the swarm").
    if (!torrentFilePath.isEmpty())
        updateModels(item->id(), handle, false);

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

    if (auto *stats = libtorrent::alert_cast<libtorrent::session_stats_alert>(alert)) {
        if (m_dhtNodesMetricIndex < 0)
            m_dhtNodesMetricIndex = libtorrent::find_metric_idx("dht.dht_nodes");

        const auto counters = stats->counters();
        const int counterCount = static_cast<int>(counters.size());
        if (m_dhtNodesMetricIndex >= 0 && m_dhtNodesMetricIndex < counterCount)
            m_lastDhtNodes = static_cast<qint64>(counters[std::size_t(m_dhtNodesMetricIndex)]);
        return;
    }

    if (auto *dhtStats = libtorrent::alert_cast<libtorrent::dht_stats_alert>(alert)) {
        const QDateTime now = QDateTime::currentDateTimeUtc();
        m_lastDhtNodeId = QByteArray(dhtStats->nid.data(), int(dhtStats->nid.size()));
        if (m_lastDhtNodeId.size() == 20)
            m_recentDhtNodeIds.insert(m_lastDhtNodeId, now);
        qint64 totalNodes = 0;
        for (const auto &bucket : dhtStats->routing_table)
            totalNodes += bucket.num_nodes;
        if (totalNodes > 0)
            m_lastDhtNodes = totalNodes;
        if (m_session && m_lastDhtNodeId.size() == 20
            && (!m_lastDhtLiveNodesRequest.isValid() || m_lastDhtLiveNodesRequest.elapsed() >= 5000)) {
            m_session->dht_live_nodes(dhtStats->nid);
            if (!m_lastDhtLiveNodesRequest.isValid())
                m_lastDhtLiveNodesRequest.start();
            else
                m_lastDhtLiveNodesRequest.restart();
        }
        return;
    }

    if (auto *live = libtorrent::alert_cast<libtorrent::dht_live_nodes_alert>(alert)) {
        if (m_lastDhtNodeId.size() != 20)
            return;
        auto persistCache = [this]() { saveDhtEstimatorCache(false); };
        const QDateTime now = QDateTime::currentDateTimeUtc();
        if (!m_lastDhtLiveNodesUpdate.isValid())
            m_lastDhtLiveNodesUpdate.start();
        else
            m_lastDhtLiveNodesUpdate.restart();

        const auto nodes = live->nodes();
        for (const auto &entry : nodes)
            m_recentDhtNodeIds.insert(QByteArray(entry.first.data(), int(entry.first.size())), now);

        // Keep a longer rolling memory for restart/warmup, but estimate from a
        // short recency window. A long union of rotating node IDs causes
        // one-way upward drift in density-based estimates.
        const int retentionSecs = 60 * 60;
        const int activeWindowSecs = 3 * 60;
        const QDateTime retentionCutoff = now.addSecs(-retentionSecs);
        const QDateTime activeCutoff = now.addSecs(-activeWindowSecs);

        for (auto it = m_recentDhtNodeIds.begin(); it != m_recentDhtNodeIds.end();) {
            if (!it.value().isValid() || it.value() < retentionCutoff)
                it = m_recentDhtNodeIds.erase(it);
            else
                ++it;
        }

        std::vector<std::pair<QByteArray, QDateTime>> activeCandidates;
        activeCandidates.reserve(std::size_t(m_recentDhtNodeIds.size()));
        for (auto it = m_recentDhtNodeIds.constBegin(); it != m_recentDhtNodeIds.constEnd(); ++it) {
            const QByteArray &nodeId = it.key();
            if (nodeId.size() != 20 || nodeId == m_lastDhtNodeId || it.value() < activeCutoff)
                continue;
            activeCandidates.push_back({nodeId, it.value()});
        }
        std::sort(activeCandidates.begin(), activeCandidates.end(),
            [](const auto &a, const auto &b) { return a.second > b.second; });

        // Bound estimator sample size to prevent long-session ID churn from
        // pushing the estimate steadily upward.
        const int activeCap = std::clamp(int(nodes.size()) * 3, 240, 960);
        if (static_cast<int>(activeCandidates.size()) > activeCap)
            activeCandidates.resize(std::size_t(activeCap));

        std::vector<QByteArray> activeNodeIds;
        activeNodeIds.reserve(activeCandidates.size());
        for (const auto &entry : activeCandidates)
            activeNodeIds.push_back(entry.first);
        if (m_recentDhtNodeIds.size() > 2000) {
            std::vector<std::pair<QByteArray, QDateTime>> allSeen;
            allSeen.reserve(std::size_t(m_recentDhtNodeIds.size()));
            for (auto it = m_recentDhtNodeIds.constBegin(); it != m_recentDhtNodeIds.constEnd(); ++it)
                allSeen.push_back({it.key(), it.value()});
            std::sort(allSeen.begin(), allSeen.end(),
                [](const auto &a, const auto &b) { return a.second > b.second; });
            for (int i = 2000; i < static_cast<int>(allSeen.size()); ++i)
                m_recentDhtNodeIds.remove(allSeen[std::size_t(i)].first);
        }
        const int closestSamples = static_cast<int>(activeNodeIds.size());
        m_lastDhtClosestSampleCount = closestSamples;
        const double warmLiveProgress = std::clamp(double(std::max<qint64>(0, m_lastDhtNodes)) / 500.0, 0.0, 1.0);
        const double warmClosestProgress = std::clamp(double(closestSamples) / 720.0, 0.0, 1.0);
        const double warmUniqueProgress = std::clamp(double(m_recentDhtNodeIds.size()) / 720.0, 0.0, 1.0);
        m_lastDhtWarmupPercent = std::clamp(int(std::llround(
            (warmLiveProgress * 0.25 + warmClosestProgress * 0.40 + warmUniqueProgress * 0.35) * 100.0)), 0, 100);
        if (closestSamples < 2) {
            m_lastDhtKUsed = 0;
            m_lastDhtPivotCount = 0;
            m_cachedDhtGlobalEstimate = -1;
            m_lastDhtConfidencePercent = 0;
            persistCache();
            return;
        }

        const int kMaxDynamicK = std::clamp(closestSamples / 16, 8, 24);
        m_lastDhtKUsed = kMaxDynamicK;

        int targetPivotCount = std::clamp(closestSamples / 30, 8, 24);
        const std::uint64_t roundSeed = std::uint64_t(now.toSecsSinceEpoch() / 90);
        std::vector<QByteArray> pivotIds;
        pivotIds.reserve(std::size_t(targetPivotCount));
        pivotIds.push_back(m_lastDhtNodeId);
        for (int i = 0; static_cast<int>(pivotIds.size()) < targetPivotCount && i < targetPivotCount * 3; ++i) {
            QByteArray pivot = localPivotIdForRound(m_lastDhtNodeId, roundSeed, i);
            if (pivot.size() != 20 || pivot == m_lastDhtNodeId)
                continue;
            bool duplicate = false;
            for (const QByteArray &existing : pivotIds) {
                if (existing == pivot) {
                    duplicate = true;
                    break;
                }
            }
            if (!duplicate)
                pivotIds.push_back(pivot);
        }

        std::vector<long double> pivotLogEstimates;
        pivotLogEstimates.reserve(pivotIds.size());
        for (const QByteArray &pivot : pivotIds) {
            std::vector<QByteArray> distances;
            distances.reserve(activeNodeIds.size());
            for (const QByteArray &nodeId : activeNodeIds) {
                if (nodeId.size() != 20 || nodeId == pivot)
                    continue;
                QByteArray dist(20, '\0');
                for (int i = 0; i < 20; ++i) {
                    dist[i] = char(static_cast<unsigned char>(pivot[i])
                                   ^ static_cast<unsigned char>(nodeId[i]));
                }
                distances.push_back(dist);
            }
            const int k = std::min(kMaxDynamicK, static_cast<int>(distances.size()));
            if (k < 2)
                continue;
            std::nth_element(distances.begin(), distances.begin() + (k - 1), distances.end(), distanceLess);
            const long double log2Distance = log2DistanceBytes(distances[std::size_t(k - 1)]);
            if (!std::isfinite(log2Distance))
                continue;
            const long double log2Estimate = std::log2(static_cast<long double>(k - 1))
                + 160.0L - log2Distance;
            if (!std::isfinite(log2Estimate))
                continue;
            pivotLogEstimates.push_back(log2Estimate);
        }
        m_lastDhtPivotCount = static_cast<int>(pivotLogEstimates.size());
        if (pivotLogEstimates.empty()) {
            m_cachedDhtGlobalEstimate = -1;
            m_lastDhtConfidencePercent = 0;
            persistCache();
            return;
        }

        std::sort(pivotLogEstimates.begin(), pivotLogEstimates.end());
        const int trimCount = pivotLogEstimates.size() >= 10
            ? static_cast<int>(pivotLogEstimates.size() / 6)
            : 0;
        const int begin = trimCount;
        const int end = static_cast<int>(pivotLogEstimates.size()) - trimCount;
        const int used = std::max(1, end - begin);

        long double meanLog2 = 0.0L;
        for (int i = begin; i < end; ++i)
            meanLog2 += pivotLogEstimates[std::size_t(i)];
        meanLog2 /= static_cast<long double>(used);

        long double variance = 0.0L;
        for (int i = begin; i < end; ++i) {
            const long double delta = pivotLogEstimates[std::size_t(i)] - meanLog2;
            variance += delta * delta;
        }
        if (used > 1)
            variance /= static_cast<long double>(used - 1);
        else
            variance = 0.0L;
        const long double stddevLog2 = std::sqrt(std::max<long double>(0.0L, variance));

        long double rawEstimated = std::exp2(meanLog2);
        qint64 rawEstimate = -1;
        if (std::isfinite(rawEstimated) && rawEstimated > 0.0L) {
            if (rawEstimated > static_cast<long double>(std::numeric_limits<qint64>::max()))
                rawEstimated = static_cast<long double>(std::numeric_limits<qint64>::max());
            rawEstimate = static_cast<qint64>(std::llround(rawEstimated));
        }

        const double liveProgress = std::clamp(double(std::max<qint64>(0, m_lastDhtNodes)) / 450.0, 0.0, 1.0);
        const double closestProgress = std::clamp(double(closestSamples) / 720.0, 0.0, 1.0);
        const double uniqueProgress = std::clamp(double(m_recentDhtNodeIds.size()) / 720.0, 0.0, 1.0);
        const double pivotProgress = std::clamp(double(m_lastDhtPivotCount) / 14.0, 0.0, 1.0);
        const double stability = std::clamp(1.0 - (double(stddevLog2) / 1.1), 0.0, 1.0);
        const double score = liveProgress * 0.22
            + closestProgress * 0.30
            + uniqueProgress * 0.28
            + pivotProgress * 0.12
            + stability * 0.08;
        const int computedConfidence = std::clamp(int(std::llround(score * 100.0)), 0, 100);

        // Keep "estimating..." for longer and only publish once we have enough
        // independent pivots and a meaningful active sample size.
        const bool warmedEnough = closestSamples >= 260
            && m_recentDhtNodeIds.size() >= 700
            && m_lastDhtPivotCount >= 10;

        qint64 adaptiveFloor = -1;
        if (m_recentPublishedDhtEstimates.size() >= 8) {
            QVector<qint64> sorted = m_recentPublishedDhtEstimates;
            std::sort(sorted.begin(), sorted.end());
            const int sortedCount = static_cast<int>(sorted.size());
            const int p10Index = std::clamp((sortedCount - 1) / 10, 0, sortedCount - 1);
            const qint64 p10 = sorted[p10Index];
            adaptiveFloor = std::max<qint64>(200000, static_cast<qint64>(std::llround(double(p10) * 0.35)));
        }
        const bool saneRaw = rawEstimate > 0 && (adaptiveFloor <= 0 || rawEstimate >= adaptiveFloor);
        if (!warmedEnough || !saneRaw) {
            m_cachedDhtGlobalEstimate = -1;
            m_lastDhtConfidencePercent = 0;
        } else {
            long double finalLog2 = meanLog2;
            if (m_cachedDhtGlobalEstimate > 0) {
                const long double prevLog2 = std::log2(static_cast<long double>(m_cachedDhtGlobalEstimate));
                const long double alpha = std::clamp(
                    0.24L + 0.26L * std::clamp(static_cast<long double>(closestSamples) / 720.0L, 0.0L, 1.0L),
                    0.24L, 0.50L);
                finalLog2 = prevLog2 * (1.0L - alpha) + finalLog2 * alpha;
            }
            long double finalEstimated = std::exp2(finalLog2);
            if (finalEstimated > static_cast<long double>(std::numeric_limits<qint64>::max()))
                finalEstimated = static_cast<long double>(std::numeric_limits<qint64>::max());
            m_lastDhtGlobalNodes = static_cast<qint64>(std::llround(finalEstimated));
            m_cachedDhtGlobalEstimate = m_lastDhtGlobalNodes;
            m_lastDhtConfidencePercent = computedConfidence;
            m_recentPublishedDhtEstimates.push_back(rawEstimate);
            constexpr int kMaxPublishedHistory = 40;
            if (m_recentPublishedDhtEstimates.size() > kMaxPublishedHistory)
                m_recentPublishedDhtEstimates.remove(0, m_recentPublishedDhtEstimates.size() - kMaxPublishedHistory);
        }
        persistCache();
        return;
    }

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

    // Populate web seeds (url_seeds = BEP-19 GetRight, http_seeds = BEP-17 Hoffman)
    {
        QStringList urlSeeds, httpSeeds;
        for (const auto &seed : handle.url_seeds())
            urlSeeds.push_back(QString::fromStdString(seed));
        for (const auto &seed : handle.http_seeds())
            httpSeeds.push_back(QString::fromStdString(seed));
        item->setTorrentUrlSeeds(urlSeeds);
        item->setTorrentHttpSeeds(httpSeeds);
    }

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
