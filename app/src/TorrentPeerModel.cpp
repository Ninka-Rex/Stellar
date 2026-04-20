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

#include "TorrentPeerModel.h"

#include <QHash>
#include <QStringList>
#include <QRegularExpression>

#include <algorithm>

TorrentPeerModel::TorrentPeerModel(QObject *parent)
    : QAbstractListModel(parent) {}

namespace {
constexpr int kPeerRemovalGraceTicks = 3;

QString flagFromCode(const QString &countryCode) {
    const QString code = countryCode.trimmed().toUpper();
    if (code.size() != 2)
        return QStringLiteral("?");
    const ushort a = code.at(0).unicode();
    const ushort b = code.at(1).unicode();
    if (a < 'A' || a > 'Z' || b < 'A' || b > 'Z')
        return QStringLiteral("?");
    return QString::fromUcs4(QVector<uint>{0x1F1E6u + (a - 'A'), 0x1F1E6u + (b - 'A')}.constData(), 2);
}

QString peerKey(const TorrentPeerModel::Entry &entry) {
    // Peer identity must stay stable across refreshes. Client strings and
    // seed state can change mid-session, and treating them as identity
    // forces unnecessary remove/insert/layout churn in the view.
    return QStringLiteral("%1|%2")
        .arg(entry.endpoint, QString::number(entry.port));
}

QString normalizeClientName(const QString &client) {
    const QString raw = client.trimmed();
    return raw.isEmpty() ? QStringLiteral("Unknown") : raw;
}

int compareIdentity(const TorrentPeerModel::Entry &a, const TorrentPeerModel::Entry &b) {
    return QString::compare(peerKey(a), peerKey(b), Qt::CaseInsensitive);
}

bool peerLess(const TorrentPeerModel::Entry &a, const TorrentPeerModel::Entry &b,
              const QString &key, bool ascending) {
    int cmp = 0;
    if (key == QStringLiteral("country")) {
        cmp = QString::compare(a.countryCode, b.countryCode, Qt::CaseInsensitive);
    } else if (key == QStringLiteral("port")) {
        cmp = a.port < b.port ? -1 : (a.port > b.port ? 1 : 0);
    } else if (key == QStringLiteral("region")) {
        cmp = QString::compare(a.regionCode, b.regionCode, Qt::CaseInsensitive);
    } else if (key == QStringLiteral("city")) {
        cmp = QString::compare(a.cityName, b.cityName, Qt::CaseInsensitive);
    } else if (key == QStringLiteral("client")) {
        cmp = QString::compare(a.client, b.client, Qt::CaseInsensitive);
    } else if (key == QStringLiteral("progress")) {
        cmp = a.progress < b.progress ? -1 : (a.progress > b.progress ? 1 : 0);
    } else if (key == QStringLiteral("down")) {
        cmp = a.downSpeed < b.downSpeed ? -1 : (a.downSpeed > b.downSpeed ? 1 : 0);
    } else if (key == QStringLiteral("up")) {
        cmp = a.upSpeed < b.upSpeed ? -1 : (a.upSpeed > b.upSpeed ? 1 : 0);
    } else if (key == QStringLiteral("downloaded")) {
        cmp = a.downloaded < b.downloaded ? -1 : (a.downloaded > b.downloaded ? 1 : 0);
    } else if (key == QStringLiteral("uploaded")) {
        cmp = a.uploaded < b.uploaded ? -1 : (a.uploaded > b.uploaded ? 1 : 0);
    } else if (key == QStringLiteral("type")) {
        cmp = a.isSeed == b.isSeed ? 0 : (a.isSeed ? 1 : -1);
    } else {
        cmp = QString::compare(a.endpoint, b.endpoint, Qt::CaseInsensitive);
    }

    if (cmp == 0)
        cmp = compareIdentity(a, b);
    return ascending ? (cmp < 0) : (cmp > 0);
}

QStringList keysFor(const QVector<TorrentPeerModel::Entry> &entries) {
    QStringList keys;
    keys.reserve(entries.size());
    for (const auto &entry : entries)
        keys.push_back(peerKey(entry));
    return keys;
}

QVector<int> changedRolesFor(const TorrentPeerModel::Entry &a, const TorrentPeerModel::Entry &b) {
    QVector<int> changed;
    if (a.downSpeed != b.downSpeed) changed << TorrentPeerModel::DownSpeedRole;
    if (a.upSpeed   != b.upSpeed)   changed << TorrentPeerModel::UpSpeedRole;
    if (a.downloaded != b.downloaded) changed << TorrentPeerModel::DownloadedRole;
    if (a.uploaded   != b.uploaded)   changed << TorrentPeerModel::UploadedRole;
    if (a.rtt       != b.rtt)       changed << TorrentPeerModel::RttRole;
    if (!qFuzzyCompare(a.progress + 1.0, b.progress + 1.0)) changed << TorrentPeerModel::ProgressRole;
    if (a.flags     != b.flags)     changed << TorrentPeerModel::FlagsRole;
    if (a.client    != b.client)    changed << TorrentPeerModel::ClientRole;
    if (a.isSeed    != b.isSeed)    changed << TorrentPeerModel::SeedRole;
    if (a.countryCode != b.countryCode) changed << TorrentPeerModel::CountryCodeRole << TorrentPeerModel::CountryFlagRole;
    if (a.regionCode  != b.regionCode)  changed << TorrentPeerModel::RegionCodeRole;
    if (a.regionName  != b.regionName)  changed << TorrentPeerModel::RegionNameRole;
    if (a.cityName    != b.cityName)    changed << TorrentPeerModel::CityNameRole;
    if (!qFuzzyCompare(a.latitude + 1.0, b.latitude + 1.0)) changed << TorrentPeerModel::LatitudeRole;
    if (!qFuzzyCompare(a.longitude + 1.0, b.longitude + 1.0)) changed << TorrentPeerModel::LongitudeRole;
    if (a.source    != b.source)    changed << TorrentPeerModel::SourceRole;
    return changed;
}
}

int TorrentPeerModel::rowCount(const QModelIndex &parent) const {
    return parent.isValid() ? 0 : m_entries.size();
}

QVariant TorrentPeerModel::data(const QModelIndex &index, int role) const {
    if (!index.isValid() || index.row() < 0 || index.row() >= m_entries.size())
        return {};

    const Entry &entry = m_entries.at(index.row());
    switch (role) {
    case EndpointRole: return entry.endpoint;
    case PortRole: return entry.port;
    case ClientRole: return entry.client;
    case ProgressRole: return entry.progress;
    case DownSpeedRole: return entry.downSpeed;
    case UpSpeedRole: return entry.upSpeed;
    case DownloadedRole: return entry.downloaded;
    case UploadedRole: return entry.uploaded;
    case SeedRole: return entry.isSeed;
    case CountryCodeRole: return entry.countryCode;
    case CountryFlagRole: return entry.countryFlag;
    case RegionCodeRole: return entry.regionCode;
    case RegionNameRole: return entry.regionName;
    case CityNameRole: return entry.cityName;
    case LatitudeRole: return entry.latitude;
    case LongitudeRole: return entry.longitude;
    case RttRole: return entry.rtt;
    case SourceRole: return entry.source;
    case FlagsRole: return entry.flags;
    default: return {};
    }
}

QHash<int, QByteArray> TorrentPeerModel::roleNames() const {
    return {
        { EndpointRole, "endpoint" },
        { PortRole, "port" },
        { ClientRole, "client" },
        { ProgressRole, "progress" },
        { DownSpeedRole, "downSpeed" },
        { UpSpeedRole, "upSpeed" },
        { DownloadedRole, "downloaded" },
        { UploadedRole, "uploaded" },
        { SeedRole, "isSeed" },
        { CountryCodeRole, "countryCode" },
        { CountryFlagRole, "countryFlag" },
        { RegionCodeRole, "regionCode" },
        { RegionNameRole, "regionName" },
        { CityNameRole, "cityName" },
        { LatitudeRole, "latitude" },
        { LongitudeRole, "longitude" },
        { RttRole, "rtt" },
        { SourceRole, "source" },
        { FlagsRole, "flags" }
    };
}

void TorrentPeerModel::setLocalLocation(bool hasLocation, double latitude, double longitude) {
    const bool changed = m_hasLocalLocation != hasLocation
        || !qFuzzyCompare(m_localLatitude, latitude)
        || !qFuzzyCompare(m_localLongitude, longitude);
    if (!changed)
        return;
    m_hasLocalLocation = hasLocation;
    m_localLatitude = latitude;
    m_localLongitude = longitude;
    emit localLocationChanged();
}

void TorrentPeerModel::setLocalInfo(const QString &ip, int port, const QString &countryCode,
                                    const QString &regionName, const QString &cityName,
                                    const QString &clientName) {
    m_localIp = ip;
    m_localPort = port;
    m_localCountryCode = countryCode;
    m_localRegionName = regionName;
    m_localCityName = cityName;
    m_localClientName = clientName;
    emit localLocationChanged();
}

void TorrentPeerModel::setEntries(const QVector<Entry> &entries) {
    if (!m_liveUpdatesEnabled)
        return;

    if (entries.isEmpty()) {
        m_pendingEntries.clear();
        m_missingPeerStreaks.clear();
        if (m_entries.isEmpty())
            return;
        beginResetModel();
        m_entries.clear();
        endResetModel();
        return;
    }

    QVector<Entry> sorted = entries;
    for (Entry &entry : sorted) {
        if (entry.countryFlag.isEmpty())
            entry.countryFlag = flagFromCode(entry.countryCode);
    }

    QHash<QString, Entry> freshByKey;
    freshByKey.reserve(sorted.size());
    for (const auto &entry : sorted)
        freshByKey.insert(peerKey(entry), entry);

    for (const auto &entry : m_entries) {
        const QString key = peerKey(entry);
        if (freshByKey.contains(key)) {
            m_missingPeerStreaks.remove(key);
            continue;
        }

        const int misses = m_missingPeerStreaks.value(key, 0) + 1;
        m_missingPeerStreaks.insert(key, misses);
        if (misses < kPeerRemovalGraceTicks)
            sorted.push_back(entry);
    }

    for (auto it = m_missingPeerStreaks.begin(); it != m_missingPeerStreaks.end(); ) {
        if (freshByKey.contains(it.key()) || it.value() < kPeerRemovalGraceTicks) {
            ++it;
        } else {
            it = m_missingPeerStreaks.erase(it);
        }
    }

    // Build a lookup of incoming data by key for in-place updates.
    QHash<QString, Entry> sortedByKey;
    sortedByKey.reserve(sorted.size());
    for (const auto &entry : sorted)
        sortedByKey.insert(peerKey(entry), entry);

    // Determine whether the peer set has structurally changed (peers added/removed).
    QStringList currentKeys = keysFor(m_entries);
    QStringList incomingKeys;
    incomingKeys.reserve(sorted.size());
    for (const auto &entry : sorted)
        incomingKeys.append(peerKey(entry));
    const bool structuralChange = QSet<QString>(currentKeys.begin(), currentKeys.end())
                                  != QSet<QString>(incomingKeys.begin(), incomingKeys.end());

    if (m_structuralUpdatesDeferred && !m_entries.isEmpty()) {
        // While the user is scrolling, always defer structural changes and
        // only push data updates in place. Store full sorted snapshot for later.
        std::stable_sort(sorted.begin(), sorted.end(), [&](const Entry &a, const Entry &b) {
            return peerLess(a, b, m_sortKey, m_sortAscending);
        });
        m_pendingEntries = sorted;

        for (int i = 0; i < m_entries.size(); ++i) {
            const QString key = peerKey(m_entries.at(i));
            const auto it = sortedByKey.constFind(key);
            if (it == sortedByKey.constEnd())
                continue;
            const QVector<int> changed = changedRolesFor(m_entries.at(i), it.value());
            if (!changed.isEmpty()) {
                m_entries[i] = it.value();
                emit dataChanged(index(i, 0), index(i, 0), changed);
            }
        }
        return;
    }

    if (m_entries.isEmpty() || sorted.isEmpty()) {
        std::stable_sort(sorted.begin(), sorted.end(), [&](const Entry &a, const Entry &b) {
            return peerLess(a, b, m_sortKey, m_sortAscending);
        });
        beginResetModel();
        m_entries = sorted;
        endResetModel();
        return;
    }

    if (!structuralChange) {
        // Same set of peers — update values in-place without changing row order.
        // This avoids layoutChanged on every live tick when a sort column is active,
        // which caused the ListView to jump back to the top continuously.
        for (int i = 0; i < m_entries.size(); ++i) {
            const auto it = sortedByKey.constFind(peerKey(m_entries.at(i)));
            if (it == sortedByKey.constEnd())
                continue;
            const QVector<int> changed = changedRolesFor(m_entries.at(i), it.value());
            if (!changed.isEmpty()) {
                m_entries[i] = it.value();
                emit dataChanged(index(i, 0), index(i, 0), changed);
            }
        }
        return;
    }

    // Structural change: peers were added or removed. Sort the target list and
    // apply minimal row inserts/removes, then reorder if needed.
    std::stable_sort(sorted.begin(), sorted.end(), [&](const Entry &a, const Entry &b) {
        return peerLess(a, b, m_sortKey, m_sortAscending);
    });
    const QStringList targetKeys = keysFor(sorted);

    for (int i = m_entries.size() - 1; i >= 0; --i) {
        if (!sortedByKey.contains(peerKey(m_entries.at(i)))) {
            beginRemoveRows(QModelIndex(), i, i);
            m_entries.removeAt(i);
            endRemoveRows();
        }
    }

    currentKeys = keysFor(m_entries);
    for (int i = 0; i < sorted.size(); ++i) {
        const QString key = targetKeys.at(i);
        if (i < currentKeys.size() && currentKeys.at(i) == key)
            continue;
        if (!currentKeys.contains(key)) {
            beginInsertRows(QModelIndex(), i, i);
            m_entries.insert(i, sorted.at(i));
            endInsertRows();
            currentKeys.insert(i, key);
        }
    }

    // Update data values for surviving peers at their new positions.
    for (int i = 0; i < m_entries.size(); ++i) {
        const auto it = sortedByKey.constFind(peerKey(m_entries.at(i)));
        if (it == sortedByKey.constEnd())
            continue;
        const QVector<int> changed = changedRolesFor(m_entries.at(i), it.value());
        if (!changed.isEmpty()) {
            m_entries[i] = it.value();
            emit dataChanged(index(i, 0), index(i, 0), changed);
        }
    }

    if (keysFor(m_entries) != targetKeys) {
        emit layoutAboutToBeChanged();
        m_entries = sorted;
        emit layoutChanged();
    }
}

void TorrentPeerModel::sortBy(const QString &key, bool ascending) {
    m_sortKey = key;
    m_sortAscending = ascending;
    emit layoutAboutToBeChanged();
    std::stable_sort(m_entries.begin(), m_entries.end(), [&](const Entry &a, const Entry &b) {
        return peerLess(a, b, m_sortKey, m_sortAscending);
    });
    emit layoutChanged();
}

QString TorrentPeerModel::peerKeyAt(int row) const {
    if (row < 0 || row >= m_entries.size())
        return {};
    return peerKey(m_entries.at(row));
}

int TorrentPeerModel::indexOfPeerKey(const QString &key) const {
    if (key.isEmpty())
        return -1;
    for (int i = 0; i < m_entries.size(); ++i) {
        if (peerKey(m_entries.at(i)) == key)
            return i;
    }
    return -1;
}

bool TorrentPeerModel::removePeerByKey(const QString &key) {
    const int row = indexOfPeerKey(key);
    if (row < 0)
        return false;
    beginRemoveRows(QModelIndex(), row, row);
    m_missingPeerStreaks.remove(key);
    m_entries.removeAt(row);
    endRemoveRows();
    return true;
}

bool TorrentPeerModel::removePeer(const QString &endpoint, int port) {
    Entry entry;
    entry.endpoint = endpoint;
    entry.port = port;
    return removePeerByKey(peerKey(entry));
}

QVariantMap TorrentPeerModel::breakdownByClient() const {
    QVariantMap out;
    for (const Entry &entry : m_entries) {
        const QString label = normalizeClientName(entry.client);
        out.insert(label, out.value(label).toInt() + 1);
    }
    return out;
}

QVariantMap TorrentPeerModel::breakdownByCountry() const {
    QVariantMap out;
    for (const Entry &entry : m_entries) {
        const QString label = entry.countryCode.trimmed().isEmpty()
            ? QStringLiteral("Unknown")
            : entry.countryCode.trimmed().toUpper();
        out.insert(label, out.value(label).toInt() + 1);
    }
    return out;
}

void TorrentPeerModel::setLiveUpdatesEnabled(bool enabled) {
    if (m_liveUpdatesEnabled == enabled)
        return;
    m_liveUpdatesEnabled = enabled;
    if (!enabled) {
        m_pendingEntries.clear();
        m_structuralUpdatesDeferred = false;
        m_missingPeerStreaks.clear();
    }
}

void TorrentPeerModel::setStructuralUpdatesDeferred(bool deferred) {
    if (m_structuralUpdatesDeferred == deferred)
        return;
    m_structuralUpdatesDeferred = deferred;
    if (!m_structuralUpdatesDeferred && !m_pendingEntries.isEmpty()) {
        const QVector<Entry> pending = m_pendingEntries;
        m_pendingEntries.clear();
        setEntries(pending);
    }
}
