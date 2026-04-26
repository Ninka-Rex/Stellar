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

constexpr int kDhtZoneBits = 12; // scan a 12 bit zone...
constexpr qint64 kDhtZoneMultiplier = qint64(1) << kDhtZoneBits;
constexpr int kDhtMeasurementIntervalSecs = 300;
// Hard ceiling on how long the active crawl runs. With the bootstrap-walk
// added in pumpDhtEstimatorCrawler() this typically saturates in 15–25 s on
// a healthy network; the cap is the pessimistic upper bound for when the
// routing table is small or the network is dropping packets.
constexpr int kDhtMeasurementWindowSecs = 45;
// Initial routing-table bootstrap: at the start of every crawl, fan out
// find_node queries to *every* live node in our routing table targeting
// random IDs in our zone. Each reply yields up to 8 zone-candidate nodes,
// turning a 372-entry routing table into ~3000 zone-candidate replies in
// the first second of the crawl. Without this the BFS only re-queries the
// ~9% of the routing table that happens to already be in-zone.
constexpr int kDhtBootstrapWalkSecs = 5;
// Re-pull dht_live_nodes every N pump ticks during the bootstrap window.
// At the 20 ms pump cadence this is once per ~100 ms during bootstrap.
constexpr int kDhtBootstrapLivePullEveryTicks = 5;
// Sliding-window length for "currently live" zone membership. A zone node is
// counted toward the live population only if we've heard from it within the
// last kZoneFreshnessSecs. With insert() overwriting prior timestamps on
// re-observation, this naturally tracks the *instantaneous* zone population
// instead of accumulating churn across the entire crawl. Picking too short
// a value undercounts live nodes that haven't responded to a recent probe;
// too long lets churn leak in. ~12 s lines up roughly with the median DHT
// response RTT plus retry, which empirically tracks population well.
constexpr int kZoneFreshnessSecs = 45;
// Convergence detection: if the live zone count grows by less than this
// fraction over the last kPlateauWindowSecs of crawling AND the in-zone
// discovery rate has dropped below kPlateauNewIdsThresholdPerSec, we declare
// the estimate stable and publish early. The previous 5%/4 s threshold was
// far too easy to trip — empirically the BFS would plateau because it had
// run out of routing-table seed material, not because it had saturated the
// 4096-node zone. Tightened to 1%/8 s plus a discovery-rate gate.
constexpr double kPlateauGrowthThreshold = 0.01;
constexpr int kPlateauWindowSecs = 8;
constexpr int kPlateauNewIdsThresholdPerSec = 2;
// Minimum wall-clock time before plateau detection is allowed to fire. Stops
// the early-exit from triggering during the initial burst when the BFS hasn't
// even reached the zone yet. Bumped from 6 → 12 s now that we aggressively
// seed the BFS from the full routing table (see seedDhtCrawlFromRoutingTable
// in pumpDhtEstimatorCrawler) — the seeding burst lasts ~5 s and we want the
// plateau detector to wait until well after that finishes.
constexpr int kPlateauMinSampleSecs = 12;
constexpr int kDhtMinPaperZoneNodes = 128;
// Hard ceilings on the long-lived DHT bookkeeping hashes. Without these the
// crawler accumulates every node it has ever seen across the entire session
// (m_recentDhtNodeIds), which after several hours of uptime balloons memory
// into the gigabytes and starves the main thread, manifesting as the window
// reporting "(Not responding)" while Windows pages the working set.
constexpr int kDhtRecentNodeIdsCap = 32 * 1024;
// Per-window cap on the BFS zone-node set. The estimator only needs a
// statistically meaningful zone count; once we are well past the publish
// threshold, additional inserts only inflate the cost of pumpDhtEstimatorCrawler
// (which calls m_dhtMeasurementZoneNodes.keys() on every in-zone pump).
constexpr int kDhtZoneNodesCap = 8 * 1024;
// Coverage correction from the published BitTorrent DHT crawler papers
// (Wolchok/Halderman, Wang/Kangasharju). Both ran controlled ground-truth
// tests by injecting their own nodes and observed that a zone scanner only
// picks up ~87% of nodes that are actually live and reachable in its zone.
// The remaining ~13% are missed because of NAT timeouts, asymmetric/CGNAT
// firewalls dropping inbound UDP, ISP-level rate limits, and ordinary
// packet loss — none of which our sliding-window methodology changes.
//
// This correction is orthogonal to whether we count cumulatively or via a
// sliding freshness window: NAT'd nodes get missed under either approach,
// because the failure is at the network layer before any methodology kicks
// in. Keep the correction so the published estimate matches the count of
// nodes that are actually online, not the (smaller) count we were able to
// elicit responses from.
constexpr double kDhtPaperCoverageProbability = 0.87;
constexpr double kDhtPaperCorrectionFactor = 1.0 / kDhtPaperCoverageProbability;

bool isNodeInSameDhtZone(const QByteArray &localId, const QByteArray &candidateId) {
    if (localId.size() != 20 || candidateId.size() != 20)
        return false;

    const unsigned char xor0 = static_cast<unsigned char>(localId[0]) ^ static_cast<unsigned char>(candidateId[0]);
    const unsigned char xor1 = static_cast<unsigned char>(localId[1]) ^ static_cast<unsigned char>(candidateId[1]);
    return xor0 == 0 && (xor1 & 0xF0U) == 0;
}

// Counts entries in a {nodeId → lastSeen} hash whose timestamp falls within
// the sliding freshness window ending at `now`. This is the time-bounded
// "currently live" zone population — distinct from hash size, which would
// include every node ever observed during the crawl (cumulative counting was
// the bug that made longer crawls produce monotonically larger estimates).
//
// O(N) over the hash. The hash is capped at kDhtZoneNodesCap (8 K), and
// pruneStaleZoneNodes() below shrinks it on every pump tick, so N stays
// bounded in practice.
int countLiveZoneNodes(const QHash<QByteArray, QDateTime> &table, const QDateTime &now, int freshnessSecs) {
    if (!now.isValid() || freshnessSecs <= 0)
        return table.size();
    int live = 0;
    for (auto it = table.constBegin(); it != table.constEnd(); ++it) {
        if (it.value().isValid() && it.value().secsTo(now) < freshnessSecs)
            ++live;
    }
    return live;
}

// Drops entries whose timestamps are older than the freshness window.
// Called from the pump so stale entries don't accumulate to the cap during
// a long active window — without this, a sparse-response network would
// eventually fill the 8 K cap with zombie entries and starve fresh inserts.
void pruneStaleZoneNodes(QHash<QByteArray, QDateTime> &table, const QDateTime &now, int freshnessSecs) {
    if (!now.isValid() || freshnessSecs <= 0)
        return;
    for (auto it = table.begin(); it != table.end();) {
        if (!it.value().isValid() || it.value().secsTo(now) >= freshnessSecs)
            it = table.erase(it);
        else
            ++it;
    }
}

// Appends one row of crawl results to <StellarRoot>/dht_crawl_log.csv. Called
// from the publish path in maybePublishDhtMeasurementEpoch(), so each row
// corresponds to exactly one completed crawl. The file is opened in append
// mode and a header row is written if the file did not previously exist.
//
// Schema (one row per crawl):
//   iso_utc          ISO-8601 timestamp at publish time (UTC)
//   epoch_ms         Unix epoch milliseconds
//   wall_secs        Wall-clock seconds the crawl ran before publish
//   trigger          "plateau" if the rate-plateau early-exit fired,
//                    otherwise "window" if the hard time cap was reached
//   live_zone_count  Zone nodes seen within the freshness window
//   raw_hash_size    Total entries in the zone hash (live + just-stale)
//   estimate         Published global-population estimate
//   correction       The 1/coverage factor applied (currently 1/0.87)
//   freshness_secs   Sliding-window length used for "live" counting
//   buckets          Routing-table bucket count from libtorrent
//   routing_nodes    Total nodes across all routing-table buckets
//   local_node_id    Hex-encoded local DHT node id at crawl time
//
// CSV is unquoted because every field is plain ASCII (no commas, no quotes).
// If you ever add a string field that could contain a comma, quote it.
void appendDhtCrawlLogRow(const QDateTime &publishedAt,
                          qint64 wallSecs,
                          const char *trigger,
                          int liveZoneCount,
                          int rawHashSize,
                          qint64 estimate,
                          double correctionFactor,
                          int freshnessSecs,
                          int buckets,
                          qint64 routingNodes,
                          const QByteArray &localNodeId,
                          int probesSent,
                          int responsesReceived,
                          int peakLiveZone) {
    const QString path = StellarPaths::root() + QStringLiteral("/dht_crawl_log.csv");
    QFileInfo info(path);
    QDir().mkpath(info.absolutePath());
    const bool needsHeader = !info.exists() || info.size() == 0;

    QFile f(path);
    if (!f.open(QIODevice::Append | QIODevice::Text))
        return; // Logging is best-effort; never let it disturb the crawl.

    QTextStream out(&f);
    if (needsHeader) {
        out << "iso_utc,epoch_ms,wall_secs,trigger,live_zone_count,raw_hash_size,"
               "estimate,correction,freshness_secs,buckets,routing_nodes,local_node_id,"
               "probes_sent,responses_received,peak_live_zone\n";
    }
    out << publishedAt.toString(Qt::ISODateWithMs) << ','
        << publishedAt.toMSecsSinceEpoch() << ','
        << wallSecs << ','
        << trigger << ','
        << liveZoneCount << ','
        << rawHashSize << ','
        << estimate << ','
        << QString::number(correctionFactor, 'f', 4) << ','
        << freshnessSecs << ','
        << buckets << ','
        << routingNodes << ','
        << QString::fromLatin1(localNodeId.toHex()) << ','
        << probesSent << ','
        << responsesReceived << ','
        << peakLiveZone << '\n';
}

qint64 estimateCorrectedGlobalDhtNodesFromZoneCount(int zoneNodeCount) {
    if (zoneNodeCount <= 0)
        return -1;

    const long double estimated =
        static_cast<long double>(zoneNodeCount)
        * static_cast<long double>(kDhtZoneMultiplier)
        * static_cast<long double>(kDhtPaperCorrectionFactor);
    if (estimated >= static_cast<long double>(std::numeric_limits<qint64>::max()))
        return std::numeric_limits<qint64>::max();
    return static_cast<qint64>(std::llround(estimated));
}

// Trims a {nodeId → timestamp} hash to at most `cap` entries by removing the
// oldest 25% whenever the cap is exceeded. Called from each insert site so
// the hash cannot grow without bound across a long-running session. The 25%
// drop amortises the cost: the next 25% × cap inserts run with no pruning.
void enforceDhtIdCap(QHash<QByteArray, QDateTime> &table, int cap) {
    if (cap <= 0 || table.size() <= cap)
        return;
    const int target = std::max(1, cap * 3 / 4);
    QVector<QDateTime> stamps;
    stamps.reserve(table.size());
    for (auto it = table.constBegin(); it != table.constEnd(); ++it)
        stamps.push_back(it.value());
    // nth_element gives us the cutoff timestamp in O(N) without a full sort.
    const int dropCount = table.size() - target;
    if (dropCount <= 0)
        return;
    auto pivot = stamps.begin() + dropCount;
    std::nth_element(stamps.begin(), pivot, stamps.end());
    const QDateTime cutoff = *(pivot - 1);
    for (auto it = table.begin(); it != table.end();) {
        if (it.value() <= cutoff && (table.size() > target))
            it = table.erase(it);
        else
            ++it;
    }
}

QByteArray xorSuffixMask(const QByteArray &nodeId, quint64 mask) {
    if (nodeId.size() != 20)
        return {};
    QByteArray out = nodeId;
    for (int i = 0; i < 8; ++i) {
        const int pos = out.size() - 1 - i;
        out[pos] = char(static_cast<unsigned char>(out[pos])
                        ^ static_cast<unsigned char>((mask >> (i * 8)) & 0xffU));
    }
    return out;
}

QString dhtRequestKey(const QString &host, int port, const QByteArray &target) {
    return QStringLiteral("%1:%2:%3")
        .arg(host, QString::number(port), QString::fromLatin1(target.toHex()));
}

bool parseCompactDhtNodes(libtorrent::string_view compactNodes, QVector<QPair<QByteArray, QPair<QString, int>>> *out) {
    if (!out)
        return false;
    constexpr int kNodeRecordBytes = 26;
    if (compactNodes.size() <= 0 || (compactNodes.size() % kNodeRecordBytes) != 0)
        return false;

    const char *data = compactNodes.data();
    const int count = int(compactNodes.size() / kNodeRecordBytes);
    out->reserve(out->size() + count);
    for (int i = 0; i < count; ++i) {
        const char *record = data + i * kNodeRecordBytes;
        const QByteArray nodeId(record, 20);
        const quint32 ipv4 = (quint32(quint8(record[20])) << 24)
            | (quint32(quint8(record[21])) << 16)
            | (quint32(quint8(record[22])) << 8)
            | quint32(quint8(record[23]));
        const int port = (int(quint8(record[24])) << 8) | int(quint8(record[25]));
        const QString host = QHostAddress(ipv4).toString();
        if (nodeId.size() == 20 && !host.isEmpty() && port > 0)
            out->push_back(qMakePair(nodeId, qMakePair(host, port)));
    }
    return !out->isEmpty();
}

// nodes6 compact format: 20-byte node ID + 16-byte IPv6 + 2-byte port = 38 bytes per record.
bool parseCompactDhtNodes6(libtorrent::string_view compactNodes6, QVector<QPair<QByteArray, QPair<QString, int>>> *out) {
    if (!out)
        return false;
    constexpr int kNodeRecordBytes = 38;
    if (compactNodes6.size() <= 0 || (compactNodes6.size() % kNodeRecordBytes) != 0)
        return false;

    const char *data = compactNodes6.data();
    const int count = int(compactNodes6.size() / kNodeRecordBytes);
    out->reserve(out->size() + count);
    for (int i = 0; i < count; ++i) {
        const char *record = data + i * kNodeRecordBytes;
        const QByteArray nodeId(record, 20);
        Q_IPV6ADDR addr6;
        std::memcpy(addr6.c, record + 20, 16);
        const int port = (int(quint8(record[36])) << 8) | int(quint8(record[37]));
        const QString host = QHostAddress(addr6).toString();
        if (nodeId.size() == 20 && !host.isEmpty() && port > 0)
            out->push_back(qMakePair(nodeId, qMakePair(host, port)));
    }
    return !out->isEmpty();
}

// Plausibility bounds for MLDHT global size (post-2013 regime).
// Anything outside this range is almost certainly a sampling artefact.
constexpr qint64 kDhtPlausibleMinEstimate = 500'000;   // 500K
constexpr qint64 kDhtPlausibleMaxEstimate = 50'000'000; // 50M

// Minimum zone nodes for a "good" sample. The paper targets ~4000; we
// accept 1000+ as High, 400+ as Medium. Below 400 the correction factor
// cannot reliably recover the true size.
constexpr int kDhtGoodSampleZoneCount = 1000;
constexpr int kDhtAdequateSampleZoneCount = 400;

// Deviation bounds vs. the running median. Outside these, the current
// estimate is suspicious even if the sample itself is large.
constexpr double kDhtOutlierLowRatio = 0.4;
constexpr double kDhtOutlierHighRatio = 2.5;

QString assessDhtConfidence(qint64 estimate, int zoneCount, const QVector<qint64> &recent) {
    if (estimate <= 0 || zoneCount <= 0)
        return QStringLiteral("Low");

    // Hard plausibility gate.
    if (estimate < kDhtPlausibleMinEstimate || estimate > kDhtPlausibleMaxEstimate)
        return QStringLiteral("Low");

    // Deviation from running median (once we have enough history).
    if (recent.size() >= 5) {
        QVector<qint64> sorted = recent;
        std::sort(sorted.begin(), sorted.end());
        const qint64 median = sorted[sorted.size() / 2];
        if (median > 0) {
            const double ratio = double(estimate) / double(median);
            if (ratio < kDhtOutlierLowRatio || ratio > kDhtOutlierHighRatio)
                return QStringLiteral("Low");
        }
    }

    if (zoneCount >= kDhtGoodSampleZoneCount)
        return QStringLiteral("High");
    if (zoneCount >= kDhtAdequateSampleZoneCount)
        return QStringLiteral("Medium");
    return QStringLiteral("Low");
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
    // Fast pump drives dht_direct_request dispatches at 100ms cadence while
    // a measurement window is active. The alert timer (2s) is too slow to
    // saturate the 12-bit zone crawl in the paper's 5-second target window.
    m_dhtFastPumpTimer.setInterval(20);
    m_dhtFastPumpTimer.setSingleShot(false);
    connect(&m_dhtFastPumpTimer, &QTimer::timeout, this, [this]() {
        if (!m_dhtMeasurementStartedAt.isValid()) {
            m_dhtFastPumpTimer.stop();
            return;
        }
        const QDateTime now = QDateTime::currentDateTimeUtc();
        const qint64 elapsed = m_dhtMeasurementStartedAt.secsTo(now);
        if (elapsed >= kDhtMeasurementWindowSecs) {
            m_dhtFastPumpTimer.stop();
            return;
        }
        // Drive epoch/warmup state forward even when no responses are arriving,
        // otherwise the tooltip sticks at 0% when the BFS queue is dry.
        maybePublishDhtMeasurementEpoch(now);
        // Plateau detection inside maybePublishDhtMeasurementEpoch may have
        // published the estimate early. Once published, there's nothing left
        // to do until the next epoch rotation — stop the 50 Hz pump so we
        // don't burn CPU and UDP bandwidth for the rest of the window.
        if (m_dhtMeasurementPublished) {
            m_dhtFastPumpTimer.stop();
            return;
        }
        // Bootstrap walk: during the first kDhtBootstrapWalkSecs of the
        // measurement window, repeatedly pull dht_live_nodes from libtorrent
        // every kDhtBootstrapLivePullEveryTicks ticks. Each pull yields up
        // to N (typically 16–64) routing-table entries that get fed into
        // the BFS queue; we also re-pull frequently because libtorrent's
        // dht_live_nodes selection rotates between calls.
        //
        // After bootstrap, fall back to the previous "only re-seed on near-
        // empty queue" behavior so we don't keep hammering the routing table
        // once the BFS is self-sustaining on follow-up nodes.
        ++m_dhtBootstrapTickCount;
        if (m_session && m_lastDhtNodeId.size() == 20) {
            const bool inBootstrap = elapsed < kDhtBootstrapWalkSecs;
            const bool queueLow = m_dhtCrawlQueue.isEmpty() || m_dhtCrawlQueue.size() < 10;
            const bool bootstrapTick =
                inBootstrap && (m_dhtBootstrapTickCount % kDhtBootstrapLivePullEveryTicks == 0);
            if (bootstrapTick || queueLow) {
                libtorrent::sha1_hash nid(m_lastDhtNodeId.constData());
                m_session->dht_live_nodes(nid);
            }
        }
        pumpDhtEstimatorCrawler();
    });
#endif
    m_alertTimer.setInterval(2000);
    connect(&m_alertTimer, &QTimer::timeout, this, [this]() {
#if defined(STELLAR_HAS_LIBTORRENT)
        ++m_modelTick;
        processAlerts();
        // Keep the DHT estimator epoch/warmup ticking even when no DHT responses
        // are arriving (silent crawler stalls would otherwise freeze warmup at 0%).
        if (m_lastDhtNodeId.size() == 20)
            maybePublishDhtMeasurementEpoch(QDateTime::currentDateTimeUtc());
        pumpDhtEstimatorCrawler();
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

void TorrentSessionManager::startDhtCrawlNow() {
#if defined(STELLAR_HAS_LIBTORRENT)
    // Drain any DHT-related alerts that are already queued in libtorrent
    // before resetting state. Without this drain, dht_live_nodes_alert and
    // dht_direct_response_alert messages produced by the *previous* crawl
    // (or by the auto-crawl trigger that fires on first dht_stats arrival)
    // can flow into the alert handlers AFTER the reset below, injecting
    // their nodes into the new measurement and causing the visible "count
    // jumps mid-crawl" symptom. processAlerts() consumes pending alerts;
    // running it once here flushes the in-flight backlog so only post-reset
    // alerts contribute to the new measurement.
    if (m_session)
        processAlerts();

    // Reset all per-epoch state so the next measurement window starts clean,
    // then immediately kick a dht_live_nodes request to seed the BFS queue.
    m_dhtMeasurementZoneNodes.clear();
    m_dhtMeasurementStartedAt = {};
    m_dhtMeasurementPublished = false;
    m_pendingDhtRequests.clear();
    m_dhtCrawlQueue.clear();
    m_enqueuedDhtNodeIds.clear();
    m_zoneCountHistory.clear();
    m_dhtBootstrapTickCount = 0;
    m_dhtCrawlProbesSent = 0;
    m_dhtCrawlResponsesReceived = 0;
    m_dhtCrawlPeakLiveZone = 0;
    m_lastDhtWarmupPercent = 0;

    if (m_session && m_lastDhtNodeId.size() == 20) {
        libtorrent::sha1_hash nid(m_lastDhtNodeId.constData());
        m_session->dht_live_nodes(nid);
        m_session->post_dht_stats();
        if (!m_lastDhtLiveNodesRequest.isValid())
            m_lastDhtLiveNodesRequest.start();
        else
            m_lastDhtLiveNodesRequest.restart();
        // Start a fresh epoch immediately and arm the fast pump so queries
        // begin flowing on 100ms cadence without waiting for the 2s alert.
        m_dhtMeasurementStartedAt = QDateTime::currentDateTimeUtc();
        m_dhtMeasurementPublished = false;
        if (!m_dhtFastPumpTimer.isActive())
            m_dhtFastPumpTimer.start();
    }
#endif
}

void TorrentSessionManager::enqueueDhtCrawlNode(const QByteArray &nodeId, const QString &host, int port) {
#if defined(STELLAR_HAS_LIBTORRENT)
    if (nodeId.size() != 20 || host.trimmed().isEmpty() || port <= 0 || nodeId == m_lastDhtNodeId)
        return;
    if (m_enqueuedDhtNodeIds.contains(nodeId))
        return;
    m_enqueuedDhtNodeIds.insert(nodeId);
    m_dhtCrawlQueue.push_back({nodeId, host.trimmed(), port});
#else
    Q_UNUSED(nodeId);
    Q_UNUSED(host);
    Q_UNUSED(port);
#endif
}

void TorrentSessionManager::pumpDhtEstimatorCrawler() {
#if defined(STELLAR_HAS_LIBTORRENT)
    if (!m_session || m_lastDhtNodeId.size() != 20)
        return;
    const QDateTime now = QDateTime::currentDateTimeUtc();

    // Prune timed-out pending requests up front, regardless of window state.
    // The previous version bailed before this loop when the window had ended,
    // leaving any requests that never received a response sitting in the hash
    // until the next 30-minute window rotation. They were eventually cleared
    // on rotate, so this was not a long-term leak — but with bursts of dead
    // peers the hash could carry hundreds of stale entries between windows
    // for no good reason.
    constexpr int kMaxOutstandingRequests = 256;
    constexpr int kMaxRequestsPerPump = 64;
    constexpr int kPendingRequestTimeoutSecs = 5;
    for (auto it = m_pendingDhtRequests.begin(); it != m_pendingDhtRequests.end();) {
        if (!it.value().isValid() || it.value().secsTo(now) >= kPendingRequestTimeoutSecs)
            it = m_pendingDhtRequests.erase(it);
        else
            ++it;
    }

    if (!m_dhtMeasurementStartedAt.isValid())
        return;
    const qint64 sampleAgeSecs = std::max<qint64>(0, m_dhtMeasurementStartedAt.secsTo(now));
    if (sampleAgeSecs >= kDhtMeasurementWindowSecs)
        return;

    // Drop stale zone entries every pump so the cap is occupied by *currently
    // live* nodes only. Without this, on a long active window the cap fills
    // with zombie entries and fresh inserts get rejected at line ~970, which
    // would freeze the live count at the cap value regardless of true
    // population.
    pruneStaleZoneNodes(m_dhtMeasurementZoneNodes, now, kZoneFreshnessSecs);

    // Precompute a {nodeId → (host, port)} lookup for the current crawl queue
    // so the in-zone probe-fanout below can resolve a peer host/port in O(1)
    // instead of scanning the entire queue per probe. With a queue of several
    // thousand entries and up to 256 probes per pump, the original linear scan
    // produced visible single-core CPU spikes (and stalled paint events) every
    // pump tick during the 60 s active measurement window.
    QHash<QByteArray, QPair<QString, int>> queueLookup;
    queueLookup.reserve(m_dhtCrawlQueue.size() * 2);
    for (const DhtCrawlNode &qn : m_dhtCrawlQueue)
        queueLookup.insert(qn.id, qMakePair(qn.host, qn.port));

    int sent = 0;
    while (!m_dhtCrawlQueue.isEmpty()
           && sent < kMaxRequestsPerPump
           && m_pendingDhtRequests.size() < kMaxOutstandingRequests) {
        const DhtCrawlNode node = m_dhtCrawlQueue.front();
        m_dhtCrawlQueue.pop_front();
        // Intentionally do NOT remove node.id from m_enqueuedDhtNodeIds here.
        // The set is the per-window dedup guard for enqueueDhtCrawlNode(); it
        // is cleared on window rotation in maybePublishDhtMeasurementEpoch().
        // Removing it mid-window allowed a freshly discovered duplicate to be
        // re-enqueued and re-probed immediately, looping the same node back
        // through the crawl repeatedly while inflating m_pendingDhtRequests.

        const bool inZone = isNodeInSameDhtZone(m_lastDhtNodeId, node.id);

        // For in-zone nodes: send 4 XOR-perturbed find_node probes to 4 *different*
        // zone nodes (if available) so each gets a distinct routing table view.
        // For non-zone nodes: always query toward our own ID to converge on the zone.
        // The 2000-node cap was removed — capping BFS fan-out at ~50% saturation was
        // the primary cause of premature crawl termination.
        struct ZoneProbe { QByteArray target; QString host; int port; };
        QVector<ZoneProbe> probes;
        if (inZone) {
            probes.push_back({node.id, node.host, node.port});
            // Collect up to 4 other in-zone nodes to fan probes across.
            QVector<QByteArray> zoneKeys = m_dhtMeasurementZoneNodes.keys();
            int probeIdx = 0;
            for (quint64 i = 1; i <= 4; ++i) {
                const QByteArray perturbedTarget = xorSuffixMask(node.id, (quint64(1) << (i * 3)) - 1);
                if (perturbedTarget.size() != 20)
                    continue;
                // Find a different zone node to send this probe to.
                QString probeHost = node.host;
                int probePort = node.port;
                while (probeIdx < zoneKeys.size()) {
                    const QByteArray &zk = zoneKeys[probeIdx++];
                    if (zk == node.id)
                        continue;
                    // Look up host/port for this zone node via the precomputed
                    // lookup hash — was an O(|queue|) linear scan per probe.
                    const auto it = queueLookup.constFind(zk);
                    if (it != queueLookup.constEnd()) {
                        probeHost = it.value().first;
                        probePort = it.value().second;
                    }
                    break;
                }
                probes.push_back({perturbedTarget, probeHost, probePort});
            }
        } else {
            probes.push_back({m_lastDhtNodeId, node.host, node.port});
        }

        for (const ZoneProbe &probe : probes) {
            if (probe.target.size() != 20)
                continue;
            const QString requestKey = dhtRequestKey(probe.host, probe.port, probe.target);
            if (m_pendingDhtRequests.contains(requestKey))
                continue;

            libtorrent::entry request;
            request[QStringLiteral("q").toStdString()] = std::string("find_node");
            libtorrent::entry args(libtorrent::entry::dictionary_t);
            args[QStringLiteral("id").toStdString()] =
                std::string(m_lastDhtNodeId.constData(), std::size_t(m_lastDhtNodeId.size()));
            args[QStringLiteral("target").toStdString()] =
                std::string(probe.target.constData(), std::size_t(probe.target.size()));
            request[QStringLiteral("a").toStdString()] = args;

            const QHostAddress address(probe.host);
            const auto proto = address.protocol();
            if (proto == QAbstractSocket::IPv4Protocol) {
                m_session->dht_direct_request(
                    libtorrent::udp::endpoint(libtorrent::make_address_v4(address.toIPv4Address()), std::uint16_t(probe.port)),
                    request);
            } else if (proto == QAbstractSocket::IPv6Protocol) {
                Q_IPV6ADDR raw6 = address.toIPv6Address();
                boost::asio::ip::address_v6::bytes_type bytes6;
                std::memcpy(bytes6.data(), raw6.c, 16);
                m_session->dht_direct_request(
                    libtorrent::udp::endpoint(libtorrent::make_address_v6(bytes6), std::uint16_t(probe.port)),
                    request);
            } else {
                continue;
            }
            m_pendingDhtRequests.insert(requestKey, now);
            ++sent;
            ++m_dhtCrawlProbesSent;
            if (sent >= kMaxRequestsPerPump || m_pendingDhtRequests.size() >= kMaxOutstandingRequests)
                break;
        }
    }
#endif
}

void TorrentSessionManager::handleDhtDirectResponse(const libtorrent::dht_direct_response_alert *alert) {
#if defined(STELLAR_HAS_LIBTORRENT)
    if (!alert || m_lastDhtNodeId.size() != 20)
        return;

    const QString host = QString::fromStdString(alert->endpoint.address().to_string());
    const int port = alert->endpoint.port();
    for (auto it = m_pendingDhtRequests.begin(); it != m_pendingDhtRequests.end();) {
        const QString prefix = QStringLiteral("%1:%2:").arg(host, QString::number(port));
        if (it.key().startsWith(prefix))
            it = m_pendingDhtRequests.erase(it);
        else
            ++it;
    }

    const libtorrent::bdecode_node response = alert->response();
    if (response.type() != libtorrent::bdecode_node::dict_t)
        return;
    const libtorrent::bdecode_node reply = response.dict_find_dict("r");
    if (reply.type() != libtorrent::bdecode_node::dict_t)
        return;
    // Count any structurally-valid response — even an empty "r" dict means a
    // node responded, which distinguishes "we sent X probes and Y came back"
    // from "we sent X probes and Y of them returned nodes." Both numbers are
    // useful for diagnosing why the BFS isn't growing.
    ++m_dhtCrawlResponsesReceived;

    QVector<QPair<QByteArray, QPair<QString, int>>> discovered;
    parseCompactDhtNodes(reply.dict_find_string_value("nodes"), &discovered);
    parseCompactDhtNodes6(reply.dict_find_string_value("nodes6"), &discovered);
    const QDateTime nowStamp = QDateTime::currentDateTimeUtc();
    for (const auto &entry : discovered) {
        m_recentDhtNodeIds.insert(entry.first, nowStamp);
        enqueueDhtCrawlNode(entry.first, entry.second.first, entry.second.second);
    }
    enforceDhtIdCap(m_recentDhtNodeIds, kDhtRecentNodeIdsCap);
    if (!discovered.isEmpty()) {
        for (const auto &entry : discovered) {
            if (isNodeInSameDhtZone(m_lastDhtNodeId, entry.first)
                && m_dhtMeasurementZoneNodes.size() < kDhtZoneNodesCap)
                m_dhtMeasurementZoneNodes.insert(entry.first, nowStamp);
        }
        maybePublishDhtMeasurementEpoch(nowStamp);
        pumpDhtEstimatorCrawler();
    }
#else
    Q_UNUSED(alert);
#endif
}

void TorrentSessionManager::maybePublishDhtMeasurementEpoch(const QDateTime &now) {
#if defined(STELLAR_HAS_LIBTORRENT)
    if (m_lastDhtNodeId.size() != 20)
        return;

    if (!m_dhtMeasurementStartedAt.isValid()) {
        m_dhtMeasurementStartedAt = now;
        m_dhtMeasurementPublished = false;
        if (!m_dhtFastPumpTimer.isActive())
            m_dhtFastPumpTimer.start();
    }

    const qint64 elapsedSecs = std::max<qint64>(0, m_dhtMeasurementStartedAt.secsTo(now));
    if (elapsedSecs >= kDhtMeasurementIntervalSecs) {
        m_dhtMeasurementStartedAt = now;
        m_dhtMeasurementZoneNodes.clear();
        m_dhtMeasurementPublished = false;
        m_pendingDhtRequests.clear();
        m_dhtCrawlQueue.clear();
        m_enqueuedDhtNodeIds.clear();
        m_zoneCountHistory.clear();
        m_dhtBootstrapTickCount = 0;
        m_dhtCrawlProbesSent = 0;
        m_dhtCrawlResponsesReceived = 0;
        m_dhtCrawlPeakLiveZone = 0;
        if (!m_dhtFastPumpTimer.isActive())
            m_dhtFastPumpTimer.start();
    }

    const qint64 activeSampleSecs = std::max<qint64>(0, m_dhtMeasurementStartedAt.secsTo(now));

    // Count only zone nodes seen within the sliding freshness window. This
    // turns the estimate from a cumulative count of every node observed
    // during the crawl (which grew monotonically with window length —
    // double the window, double the number) into an estimate of the
    // *current* live zone population.
    const int zoneCount = countLiveZoneNodes(m_dhtMeasurementZoneNodes, now, kZoneFreshnessSecs);
    if (zoneCount > m_dhtCrawlPeakLiveZone)
        m_dhtCrawlPeakLiveZone = zoneCount;
    const qint64 correctedEstimate = estimateCorrectedGlobalDhtNodesFromZoneCount(zoneCount);

    // Plateau-based early-exit: track the recent history of live counts and
    // declare convergence when the count has stopped meaningfully growing.
    // Without this the crawl ran for the full kDhtMeasurementWindowSecs even
    // after the zone was fully saturated.
    //
    // Sample at most once per second. The fast pump fires at 50 Hz, so an
    // unconditional push would inflate the history to hundreds of entries
    // and make growth comparisons sensitive to per-tick jitter rather than
    // real-second-over-second movement.
    if (m_zoneCountHistory.isEmpty()
        || m_zoneCountHistory.last().takenAt.msecsTo(now) >= 1000) {
        ZoneSample sample;
        sample.takenAt = now;
        sample.liveCount = zoneCount;
        m_zoneCountHistory.push_back(sample);
        const QDateTime trimCutoff = now.addSecs(-(kPlateauWindowSecs * 2));
        while (!m_zoneCountHistory.isEmpty() && m_zoneCountHistory.front().takenAt < trimCutoff)
            m_zoneCountHistory.pop_front();
    }

    bool plateauReached = false;
    if (activeSampleSecs >= kPlateauMinSampleSecs && zoneCount >= kDhtMinPaperZoneNodes) {
        // Find the oldest sample within the plateau window so we can compare
        // current count against count from kPlateauWindowSecs ago.
        const QDateTime plateauStart = now.addSecs(-kPlateauWindowSecs);
        int referenceCount = -1;
        for (const ZoneSample &s : m_zoneCountHistory) {
            if (s.takenAt >= plateauStart) {
                referenceCount = s.liveCount;
                break;
            }
        }

        // Recent-discovery rate: count zone-hash entries whose timestamp is
        // within the last second. This is the rate of *fresh observations*
        // per second; if the BFS were genuinely saturating it would still be
        // re-observing the same zone members at >0 rate. A drop to near zero
        // says "we are not seeing new in-zone responses anymore" which is a
        // stronger signal than count-stopped-growing alone.
        int recentObservations = 0;
        for (auto it = m_dhtMeasurementZoneNodes.constBegin();
             it != m_dhtMeasurementZoneNodes.constEnd(); ++it) {
            if (it.value().isValid() && it.value().msecsTo(now) <= 1000)
                ++recentObservations;
        }

        if (referenceCount > 0) {
            const double growth = double(zoneCount - referenceCount) / double(referenceCount);
            // Both gates must trigger: count flat AND discovery rate dead.
            // Either alone produces false positives — count can be flat
            // because nodes are aging out at the same rate as new ones come
            // in, and discovery rate can briefly dip during a routing-table
            // re-pull.
            if (growth < kPlateauGrowthThreshold
                && recentObservations < kPlateauNewIdsThresholdPerSec) {
                plateauReached = true;
            }
        }
    }

    // Warmup percent reflects whichever finish condition is closest.
    const double timeProgress = std::clamp(double(activeSampleSecs) / double(kDhtMeasurementWindowSecs), 0.0, 1.0);
    m_lastDhtWarmupPercent = std::clamp(int(std::llround(timeProgress * 100.0)), 0, 100);
    if (plateauReached)
        m_lastDhtWarmupPercent = 100;

    if (!plateauReached && activeSampleSecs < kDhtMeasurementWindowSecs)
        return;

    // Publish the *peak* live-zone count seen during the crawl rather than
    // the final live count. Empirically (see CSV diagnostic rows from
    // 2026-04-25) the BFS hits its true zone coverage somewhere mid-crawl,
    // then the count *declines* as nodes age out of the freshness window
    // faster than they are re-confirmed — by the time the plateau detector
    // fires we've lost ~30–40 % of the population we already observed.
    // The peak corresponds to the moment of maximum coverage, which is
    // closer to the snapshot quantity the paper's correction factor was
    // calibrated against.
    const int publishedZoneCount = std::max(zoneCount, m_dhtCrawlPeakLiveZone);
    const qint64 publishedEstimate = estimateCorrectedGlobalDhtNodesFromZoneCount(publishedZoneCount);

    if (publishedZoneCount < kDhtMinPaperZoneNodes || publishedEstimate <= 0)
        return;

    if (m_dhtMeasurementPublished)
        return;

    // Append the raw estimate to the rolling history, then publish the median
    // of the last few crawls rather than the just-completed one. Successive
    // crawls hit slightly different parts of the zone (different BFS seed
    // material, churn, packet loss), so a single crawl's number can wobble
    // ±10–15 % between back-to-back runs even when the true population is
    // constant. The median of the last 5 crawls smooths that wobble out
    // without lagging behind real population changes (a single outlier can't
    // sway the median, but a sustained shift in 3 of 5 most recent values
    // does).
    m_recentPublishedDhtEstimates.push_back(publishedEstimate);
    constexpr int kMaxPublishedHistory = 64;
    if (m_recentPublishedDhtEstimates.size() > kMaxPublishedHistory)
        m_recentPublishedDhtEstimates.remove(0,
            m_recentPublishedDhtEstimates.size() - kMaxPublishedHistory);

    constexpr int kSmoothingWindow = 5;
    qint64 displayedEstimate = publishedEstimate;
    if (m_recentPublishedDhtEstimates.size() >= 2) {
        QVector<qint64> recent;
        const int take = std::min(kSmoothingWindow, int(m_recentPublishedDhtEstimates.size()));
        for (int i = m_recentPublishedDhtEstimates.size() - take;
             i < m_recentPublishedDhtEstimates.size(); ++i) {
            recent.push_back(m_recentPublishedDhtEstimates.at(i));
        }
        std::sort(recent.begin(), recent.end());
        displayedEstimate = recent.at(recent.size() / 2);
    }

    m_cachedDhtGlobalEstimate = displayedEstimate;
    m_lastDhtGlobalNodes = displayedEstimate;
    m_dhtMeasurementPublished = true;
    m_dhtMeasurementLastPublishedAt = now;
    m_lastPublishedZoneCount = publishedZoneCount;

    // Persist one CSV row per completed crawl so the user can compare
    // estimates across runs, look for diurnal patterns, and check
    // self-consistency of back-to-back crawls. Best-effort: log failure
    // never interrupts the estimator.
    appendDhtCrawlLogRow(now,
                         activeSampleSecs,
                         plateauReached ? "plateau" : "window",
                         publishedZoneCount,
                         m_dhtMeasurementZoneNodes.size(),
                         publishedEstimate,
                         kDhtPaperCorrectionFactor,
                         kZoneFreshnessSecs,
                         m_lastDhtBucketCount,
                         std::max<qint64>(0, m_lastDhtNodes),
                         m_lastDhtNodeId,
                         m_dhtCrawlProbesSent,
                         m_dhtCrawlResponsesReceived,
                         m_dhtCrawlPeakLiveZone);

#else
    Q_UNUSED(now);
#endif
}

qint64 TorrentSessionManager::dhtGlobalNodesEstimate() {
#if defined(STELLAR_HAS_LIBTORRENT)
    if (!m_session || !m_settings || !m_settings->torrentEnableDht())
        return -1;
    // Always return the last published estimate if we have one. The crawl
    // runs for ~5s every kDhtMeasurementIntervalSecs; during the in-progress
    // window, confidence and warmup are reset, but the status bar should
    // keep displaying the most recent published value rather than flipping
    // to "estimating".
    if (m_cachedDhtGlobalEstimate > 0)
        return m_cachedDhtGlobalEstimate;
    if (!m_lastDhtLiveNodesUpdate.isValid() || m_lastDhtLiveNodesUpdate.elapsed() > 60000)
        return -1;
    return -1;
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

bool TorrentSessionManager::dhtCrawlInProgress() const {
#if defined(STELLAR_HAS_LIBTORRENT)
    return m_dhtMeasurementStartedAt.isValid()
        && m_dhtMeasurementStartedAt.secsTo(QDateTime::currentDateTimeUtc()) < kDhtMeasurementWindowSecs;
#else
    return false;
#endif
}

QString TorrentSessionManager::dhtEstimateDebugText() const {
#if defined(STELLAR_HAS_LIBTORRENT)
    if (!m_settings || !m_settings->torrentEnableDht())
        return QStringLiteral("Confidence: DHT Off\nLive nodes: 0\nClosest samples: 0\nUnique node IDs: 0");
    const bool crawlInProgress = m_dhtMeasurementStartedAt.isValid()
        && m_dhtMeasurementStartedAt.secsTo(QDateTime::currentDateTimeUtc()) < kDhtMeasurementWindowSecs;
    const int warmupPercent = std::clamp(m_lastDhtWarmupPercent, 0, 100);

    // First-start state: no estimate has ever been published.
    if (m_cachedDhtGlobalEstimate <= 0) {
        return QStringLiteral(
            "DHT status: Estimating…\n"
            "Confidence: —\n"
            "DHT nodes: %1\n"
            "Crawl: %2%")
            .arg(std::max<qint64>(0, m_lastDhtNodes))
            .arg(warmupPercent);
    }

    const QString confidenceLabel = assessDhtConfidence(
        m_cachedDhtGlobalEstimate,
        m_lastPublishedZoneCount,
        m_recentPublishedDhtEstimates);

    QString text = QStringLiteral(
        "DHT status: Active\n"
        "Confidence: %1\n"
        "DHT nodes: %2")
        .arg(confidenceLabel)
        .arg(std::max<qint64>(0, m_lastDhtNodes));
    if (crawlInProgress)
        text += QStringLiteral("\nCrawl: Recrawling (%1%)").arg(warmupPercent);
    return text;
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
    if (m_settings && !m_settings->torrentEnablePex())
        params.flags |= libtorrent::torrent_flags::disable_pex;
    else
        params.flags &= ~libtorrent::torrent_flags::disable_pex;

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

    if (auto *direct = libtorrent::alert_cast<libtorrent::dht_direct_response_alert>(alert)) {
        handleDhtDirectResponse(direct);
        return;
    }

    if (auto *dhtStats = libtorrent::alert_cast<libtorrent::dht_stats_alert>(alert)) {
        const QDateTime now = QDateTime::currentDateTimeUtc();
        const QByteArray previousNodeId = m_lastDhtNodeId;
        m_lastDhtNodeId = QByteArray(dhtStats->nid.data(), int(dhtStats->nid.size()));
        if (!previousNodeId.isEmpty() && previousNodeId != m_lastDhtNodeId) {
            m_recentDhtNodeIds.clear();
            m_recentPublishedDhtEstimates.clear();
            m_lastDhtWarmupPercent = 0;
            m_dhtCrawlQueue.clear();
            m_enqueuedDhtNodeIds.clear();
            m_pendingDhtRequests.clear();
            m_dhtMeasurementZoneNodes.clear();
            m_zoneCountHistory.clear();
            m_dhtBootstrapTickCount = 0;
            m_dhtCrawlProbesSent = 0;
            m_dhtCrawlResponsesReceived = 0;
            m_dhtCrawlPeakLiveZone = 0;
            m_dhtMeasurementStartedAt = {};
            m_dhtMeasurementPublished = false;
        }
        if (m_lastDhtNodeId.size() == 20)
            m_recentDhtNodeIds.insert(m_lastDhtNodeId, now);
        if (m_lastDhtNodeId.size() == 20 && !m_dhtMeasurementStartedAt.isValid()) {
            m_dhtMeasurementStartedAt = now;
            m_dhtMeasurementPublished = false;
            if (!m_dhtFastPumpTimer.isActive())
                m_dhtFastPumpTimer.start();
        }

        qint64 totalNodes = 0;
        for (const auto &bucket : dhtStats->routing_table)
            totalNodes += bucket.num_nodes;
        if (totalNodes > 0)
            m_lastDhtNodes = totalNodes;
        // Capture bucket count separately so the crawl-log row can record both
        // the number of routing-table buckets and the total nodes within them.
        m_lastDhtBucketCount = static_cast<int>(dhtStats->routing_table.size());

        // Intentionally do NOT issue dht_live_nodes() from this alert handler.
        // An older revision did so on a kDhtMeasurementIntervalSecs cadence
        // here as a secondary "auto-crawl" trigger, but the measurement state
        // machine in maybePublishDhtMeasurementEpoch() and the fast-pump timer
        // already drive their own dht_live_nodes() calls (in startDhtCrawlNow,
        // and in the bootstrap walk inside the fast-pump lambda). Keeping a
        // second uncoordinated trigger here meant extra dht_live_nodes results
        // could land mid-crawl and inject nodes into the active measurement —
        // visible to the user as the live-zone count jumping forward partway
        // through a manual crawl.
        return;
    }

    if (auto *live = libtorrent::alert_cast<libtorrent::dht_live_nodes_alert>(alert)) {
        const QByteArray alertNodeId(live->node_id.data(), int(live->node_id.size()));
        if (m_lastDhtNodeId.size() != 20 || alertNodeId.size() != 20 || alertNodeId != m_lastDhtNodeId)
            return;
        const QDateTime now = QDateTime::currentDateTimeUtc();
        if (!m_lastDhtLiveNodesUpdate.isValid())
            m_lastDhtLiveNodesUpdate.start();
        else
            m_lastDhtLiveNodesUpdate.restart();

        const auto nodes = live->nodes();

        // Feed the bounded paper-style sample window and the active crawl queue
        // from the latest live-node snapshot. Both hashes are explicitly bounded
        // — without caps, m_recentDhtNodeIds grew without limit across a long
        // session (it was inserted-to but never read or pruned), accumulating
        // millions of entries and triggering "Not responding" on the GUI thread
        // as Windows paged the working set.
        for (const auto &entry : nodes) {
            const QByteArray nodeId(entry.first.data(), int(entry.first.size()));
            m_recentDhtNodeIds.insert(nodeId, now);
            if (isNodeInSameDhtZone(m_lastDhtNodeId, nodeId)
                && m_dhtMeasurementZoneNodes.size() < kDhtZoneNodesCap)
                m_dhtMeasurementZoneNodes.insert(nodeId, now);

            // Queue both v4 and v6 endpoints — pumpDhtEstimatorCrawler() has
            // a v6 dispatch branch in the dht_direct_request call, so feeding
            // v6 nodes lets us probe the IPv6 side of the zone too. Without
            // this, a routing table that's mostly v6 (some ISPs) would leave
            // most of the BFS material on the floor.
            const QString host = QString::fromStdString(entry.second.address().to_string());
            enqueueDhtCrawlNode(nodeId, host, entry.second.port());
        }
        enforceDhtIdCap(m_recentDhtNodeIds, kDhtRecentNodeIdsCap);
        maybePublishDhtMeasurementEpoch(now);
        pumpDhtEstimatorCrawler();
        return;
    }

    if (auto *externalIp = libtorrent::alert_cast<libtorrent::external_ip_alert>(alert)) {
        setDetectedExternalAddress(QString::fromStdString(externalIp->external_address.to_string()));
        return;
    }

    if (auto *update = libtorrent::alert_cast<libtorrent::state_update_alert>(alert)) {
        m_hasIncomingPending = false;
        m_didInspectPeersThisTick = false;
        for (const auto &status : update->status) {
            const QString id = idForHandle(status.handle);
            DownloadItem *item = m_items.value(id, nullptr).data();
            if (item) {
                updateItemFromStatus(item, status.handle);
                updateModels(id, status.handle);
            }
        }
        if (m_didInspectPeersThisTick && m_hasIncomingPending != m_hasIncomingConnection) {
            m_hasIncomingConnection = m_hasIncomingPending;
            emit hasIncomingConnectionChanged();
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
        m_didInspectPeersThisTick = true;
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
                if ((peer.flags & libtorrent::peer_info::local_connection) != libtorrent::peer_flags_t{}) {
                    fl << QStringLiteral("OUT");
                } else {
                    fl << QStringLiteral("IN");
                    m_hasIncomingPending = true;
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
#endif
