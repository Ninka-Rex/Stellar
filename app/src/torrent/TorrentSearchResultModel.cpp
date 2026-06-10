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

#include "TorrentSearchResultModel.h"

#include <algorithm>
#include <cmath>
#include <QDateTime>
#include <QDate>
#include <limits>

namespace {
QString formatSizeBytes(qint64 bytes) {
    if (bytes < 0)
        return {};
    static const char *units[] = { "B", "KB", "MB", "GB", "TB", "PB" };
    double value = static_cast<double>(bytes);
    int unitIndex = 0;
    while (value >= 1024.0 && unitIndex < 5) {
        value /= 1024.0;
        ++unitIndex;
    }
    const int precision = (value >= 100.0 || unitIndex == 0) ? 0 : (value >= 10.0 ? 1 : 2);
    return QString::number(value, 'f', precision) + QLatin1Char(' ') + QString::fromLatin1(units[unitIndex]);
}

QString formatPublishedOn(const QString &value) {
    const QString trimmed = value.trimmed();

    const auto toMonthDayYear = [](const QDate &date) {
        return date.isValid() ? date.toString(QStringLiteral("M/d/yyyy")) : QString();
    };

    bool ok = false;
    const qint64 epoch = trimmed.toLongLong(&ok);
    if (ok && epoch > 0)
        return toMonthDayYear(QDateTime::fromSecsSinceEpoch(epoch, Qt::UTC).date());

    const QStringList formats = {
        QStringLiteral("M/d/yyyy"),
        QStringLiteral("MM/dd/yyyy"),
        QStringLiteral("M/d/yy"),
        QStringLiteral("MM/dd/yy"),
        QStringLiteral("yyyy-MM-dd"),
        QStringLiteral("yyyy/MM/dd"),
        QStringLiteral("dd/MM/yyyy"),
        QStringLiteral("dd-MM-yyyy")
    };
    for (const QString &format : formats) {
        const QDate date = QDate::fromString(trimmed, format);
        if (date.isValid())
            return toMonthDayYear(date);
    }
    return trimmed;
}

// Parse a raw publishedOn value (Unix-epoch string or any of the known date
// formats) into a QDate.  Returns an invalid QDate when no format matches.
QDate parsePublishedOn(const QString &value) {
    const QString trimmed = value.trimmed();
    if (trimmed.isEmpty())
        return {};

    // Unix epoch (seconds since 1970-01-01)
    bool ok = false;
    const qint64 epoch = trimmed.toLongLong(&ok);
    if (ok && epoch > 0)
        return QDateTime::fromSecsSinceEpoch(epoch, Qt::UTC).date();

    // Named date formats — must match the list in formatPublishedOn() exactly
    // so the comparator and the display function agree on what constitutes a
    // valid date.
    static const QStringList kFormats = {
        QStringLiteral("M/d/yyyy"),
        QStringLiteral("MM/dd/yyyy"),
        QStringLiteral("M/d/yy"),
        QStringLiteral("MM/dd/yy"),
        QStringLiteral("yyyy-MM-dd"),
        QStringLiteral("yyyy/MM/dd"),
        QStringLiteral("dd/MM/yyyy"),
        QStringLiteral("dd-MM-yyyy")
    };
    for (const QString &format : kFormats) {
        const QDate date = QDate::fromString(trimmed, format);
        if (date.isValid())
            return date;
    }
    return {};
}

bool publishedOnLessThan(const QString &a, const QString &b, bool ascending) {
    const QDate aDate = parsePublishedOn(a);
    const QDate bDate = parsePublishedOn(b);

    // Both parsed — compare chronologically.
    if (aDate.isValid() && bDate.isValid())
        return ascending ? aDate < bDate : aDate > bDate;

    // One parsed, one didn't — sort valid dates before unparseable strings.
    if (aDate.isValid() != bDate.isValid())
        return ascending ? aDate.isValid() : bDate.isValid();

    // Neither parsed — fall back to case-insensitive lexicographic order so
    // the sort is at least stable and predictable for unknown formats.
    return ascending ? a.toLower() < b.toLower() : a.toLower() > b.toLower();
}
}

TorrentSearchResultModel::TorrentSearchResultModel(QObject *parent)
    : QAbstractListModel(parent) {}

bool TorrentSearchResultModel::entryLessThan(const Entry &a, const Entry &b) const {
    if (m_sortKey == QStringLiteral("size")) {
        const qint64 av = a.sizeBytes < 0 ? std::numeric_limits<qint64>::max() : a.sizeBytes;
        const qint64 bv = b.sizeBytes < 0 ? std::numeric_limits<qint64>::max() : b.sizeBytes;
        return m_sortAscending ? av < bv : av > bv;
    }
    if (m_sortKey == QStringLiteral("seeders"))
        return m_sortAscending ? a.seeders < b.seeders : a.seeders > b.seeders;
    if (m_sortKey == QStringLiteral("leechers"))
        return m_sortAscending ? a.leechers < b.leechers : a.leechers > b.leechers;
    if (m_sortKey == QStringLiteral("publishedOn"))
        return publishedOnLessThan(a.publishedOn, b.publishedOn, m_sortAscending);

    QString av;
    QString bv;
    if (m_sortKey == QStringLiteral("engine")) {
        av = a.engine.toLower();
        bv = b.engine.toLower();
    } else {
        av = a.name.toLower();
        bv = b.name.toLower();
    }
    return m_sortAscending ? av < bv : av > bv;
}

int TorrentSearchResultModel::rowCount(const QModelIndex &parent) const {
    return parent.isValid() ? 0 : m_entries.size();
}

QVariant TorrentSearchResultModel::data(const QModelIndex &index, int role) const {
    if (!index.isValid() || index.row() < 0 || index.row() >= m_entries.size())
        return {};
    const Entry &entry = m_entries.at(index.row());
    switch (role) {
    case NameRole: return entry.name;
    case SizeTextRole: return !entry.sizeText.isEmpty() ? entry.sizeText : formatSizeBytes(entry.sizeBytes);
    case SizeBytesRole: return entry.sizeBytes;
    case SeedersRole: return entry.seeders;
    case LeechersRole: return entry.leechers;
    case EngineRole: return entry.engine;
    case PublishedOnRole: return formatPublishedOn(entry.publishedOn);
    case MagnetLinkRole: return entry.magnetLink;
    case DescriptionUrlRole: return entry.descriptionUrl;
    case Qt::DisplayRole: return entry.name;
    default: return {};
    }
}

QHash<int, QByteArray> TorrentSearchResultModel::roleNames() const {
    return {
        { NameRole, "name" },
        { SizeTextRole, "sizeText" },
        { SizeBytesRole, "sizeBytes" },
        { SeedersRole, "seeders" },
        { LeechersRole, "leechers" },
        { EngineRole, "engine" },
        { PublishedOnRole, "publishedOn" },
        { MagnetLinkRole, "magnetLink" },
        { DescriptionUrlRole, "descriptionUrl" }
    };
}

void TorrentSearchResultModel::setEntries(const QVector<Entry> &entries) {
    beginResetModel();
    m_entries = entries;
    endResetModel();
}

void TorrentSearchResultModel::clear() {
    if (m_entries.isEmpty())
        return;
    beginResetModel();
    m_entries.clear();
    endResetModel();
}

void TorrentSearchResultModel::appendEntry(const Entry &entry) {
    int row = m_entries.size();
    if (!m_sortKey.isEmpty()) {
        const auto it = std::lower_bound(m_entries.begin(), m_entries.end(), entry,
                                         [this](const Entry &left, const Entry &right) {
            return entryLessThan(left, right);
        });
        row = static_cast<int>(std::distance(m_entries.begin(), it));
    }
    beginInsertRows(QModelIndex(), row, row);
    m_entries.insert(m_entries.begin() + row, entry);
    endInsertRows();
}

QVariantMap TorrentSearchResultModel::resultData(int row) const {
    if (row < 0 || row >= m_entries.size())
        return {};
    const Entry &entry = m_entries.at(row);
    return {
        { QStringLiteral("name"), entry.name },
        { QStringLiteral("sizeText"), !entry.sizeText.isEmpty() ? entry.sizeText : formatSizeBytes(entry.sizeBytes) },
        { QStringLiteral("sizeBytes"), entry.sizeBytes },
        { QStringLiteral("seeders"), entry.seeders },
        { QStringLiteral("leechers"), entry.leechers },
        { QStringLiteral("engine"), entry.engine },
        { QStringLiteral("publishedOn"), formatPublishedOn(entry.publishedOn) },
        { QStringLiteral("pluginFile"), entry.pluginFile },
        { QStringLiteral("downloadLink"), entry.downloadLink },
        { QStringLiteral("magnetLink"), entry.magnetLink },
        { QStringLiteral("descriptionUrl"), entry.descriptionUrl }
    };
}

void TorrentSearchResultModel::sortBy(const QString &key, bool ascending) {
    if (m_entries.size() < 2)
        m_sortKey = key, m_sortAscending = ascending;
    else {
        m_sortKey = key;
        m_sortAscending = ascending;
    }
    if (m_entries.size() < 2)
        return;
    beginResetModel();
    std::stable_sort(m_entries.begin(), m_entries.end(),
                     [this](const Entry &a, const Entry &b) { return entryLessThan(a, b); });
    endResetModel();
}
