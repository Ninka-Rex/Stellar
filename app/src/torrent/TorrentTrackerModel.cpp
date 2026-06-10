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

#include "TorrentTrackerModel.h"

#include <algorithm>

namespace {
QString trackerKey(const TorrentTrackerModel::Entry &entry) {
    return QStringLiteral("%1|%2|%3")
        .arg(entry.url,
             entry.source,
             entry.systemEntry ? QStringLiteral("1") : QStringLiteral("0"));
}
}

TorrentTrackerModel::TorrentTrackerModel(QObject *parent)
    : QAbstractListModel(parent) {}

int TorrentTrackerModel::rowCount(const QModelIndex &parent) const {
    return parent.isValid() ? 0 : m_entries.size();
}

QVariant TorrentTrackerModel::data(const QModelIndex &index, int role) const {
    if (!index.isValid() || index.row() < 0 || index.row() >= m_entries.size())
        return {};
    const Entry &entry = m_entries.at(index.row());
    switch (role) {
    case UrlRole: return entry.url;
    case StatusRole: return entry.status;
    case TierRole: return entry.tier;
    case SourceRole: return entry.source;
    case CountRole: return entry.count;
    case SystemEntryRole: return entry.systemEntry;
    case LatitudeRole: return entry.latitude;
    case LongitudeRole: return entry.longitude;
    case CountryCodeRole: return entry.countryCode;
    case MessageRole: return entry.message;
    case SeedersRole: return entry.seeders;
    case PeersRole: return entry.peers;
    case NextAnnounceRole: return entry.nextAnnounceSecs;
    default: return {};
    }
}

QHash<int, QByteArray> TorrentTrackerModel::roleNames() const {
    return {
        { UrlRole, "url" },
        { StatusRole, "status" },
        { TierRole, "tier" },
        { SourceRole, "source" },
        { CountRole, "count" },
        { SystemEntryRole, "isSystemEntry" },
        { LatitudeRole, "latitude" },
        { LongitudeRole, "longitude" },
        { CountryCodeRole, "countryCode" },
        { MessageRole, "message" },
        { SeedersRole, "seeders" },
        { PeersRole, "peers" },
        { NextAnnounceRole, "nextAnnounceSecs" }
    };
}

void TorrentTrackerModel::setEntries(const QVector<Entry> &entries) {
    if (m_entries.isEmpty() || entries.isEmpty()) {
        beginResetModel();
        m_entries = entries;
        endResetModel();
        return;
    }

    QStringList currentKeys;
    currentKeys.reserve(m_entries.size());
    for (const auto &entry : m_entries)
        currentKeys.push_back(trackerKey(entry));

    QStringList targetKeys;
    targetKeys.reserve(entries.size());
    for (const auto &entry : entries)
        targetKeys.push_back(trackerKey(entry));

    if (currentKeys == targetKeys) {
        for (int i = 0; i < entries.size(); ++i) {
            const Entry &a = m_entries.at(i);
            const Entry &b = entries.at(i);
            QVector<int> changed;
            if (a.status != b.status) changed << StatusRole;
            if (a.tier != b.tier) changed << TierRole;
            if (a.count != b.count) changed << CountRole;
            if (a.latitude != b.latitude) changed << LatitudeRole;
            if (a.longitude != b.longitude) changed << LongitudeRole;
            if (a.countryCode != b.countryCode) changed << CountryCodeRole;
            if (a.message != b.message) changed << MessageRole;
            if (a.seeders != b.seeders) changed << SeedersRole;
            if (a.peers != b.peers) changed << PeersRole;
            if (a.nextAnnounceSecs != b.nextAnnounceSecs) changed << NextAnnounceRole;
            if (!changed.isEmpty())
                emit dataChanged(index(i, 0), index(i, 0), changed);
        }
        m_entries = entries;
        return;
    }

    emit layoutAboutToBeChanged();
    m_entries = entries;
    applySortOrder();
    emit layoutChanged();
}

void TorrentTrackerModel::sortBy(const QString &key, bool ascending) {
    m_sortKey = key;
    m_sortAscending = ascending;
    if (m_entries.isEmpty())
        return;
    emit layoutAboutToBeChanged();
    applySortOrder();
    emit layoutChanged();
}

void TorrentTrackerModel::applySortOrder() {
    if (m_sortKey.isEmpty())
        return;

    const QString key = m_sortKey;
    const bool asc = m_sortAscending;

    // System entries (DHT, PeX, LSD) always stay at the top regardless of sort.
    auto partitionPoint = std::stable_partition(m_entries.begin(), m_entries.end(),
        [](const Entry &e) { return e.systemEntry; });

    std::stable_sort(partitionPoint, m_entries.end(), [&](const Entry &a, const Entry &b) {
        auto cmpStr = [&](const QString &x, const QString &y) {
            return asc ? (x.compare(y, Qt::CaseInsensitive) < 0)
                       : (x.compare(y, Qt::CaseInsensitive) > 0);
        };
        auto cmpInt = [&](int x, int y) {
            // -1 means unknown — sort unknown values last regardless of direction.
            if (x < 0 && y < 0) return false;
            if (x < 0) return false;
            if (y < 0) return true;
            return asc ? (x < y) : (x > y);
        };

        if (key == QLatin1String("tracker"))      return cmpStr(a.url,     b.url);
        if (key == QLatin1String("status"))       return cmpStr(a.status,  b.status);
        if (key == QLatin1String("source"))       return cmpStr(a.source,  b.source);
        if (key == QLatin1String("message"))      return cmpStr(a.message, b.message);
        if (key == QLatin1String("seeders"))      return cmpInt(a.seeders, b.seeders);
        if (key == QLatin1String("peers"))        return cmpInt(a.peers,   b.peers);
        if (key == QLatin1String("nextAnnounce")) return cmpInt(a.nextAnnounceSecs, b.nextAnnounceSecs);
        return false;
    });
}
