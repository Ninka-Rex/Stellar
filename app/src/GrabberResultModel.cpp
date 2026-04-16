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

#include "GrabberResultModel.h"

#include <QUrl>

#include <algorithm>

namespace {
QString hostFromUrl(const QString &value)
{
    const QUrl url(value);
    const QString host = url.host().trimmed().toLower();
    return host;
}
}

GrabberResultModel::GrabberResultModel(QObject *parent)
    : QAbstractListModel(parent)
{
}

int GrabberResultModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : m_results.size();
}

QVariant GrabberResultModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_results.size())
        return {};

    const GrabberResult &result = m_results.at(index.row());
    switch (role) {
    case CheckedRole: return result.checked;
    case UrlRole: return result.url;
    case FilenameRole: return result.filename;
    case SourcePageRole: return result.sourcePage;
    case SizeBytesRole: return result.sizeBytes;
    case SizeTextRole: return sizeText(result.sizeBytes);
    case Qt::DisplayRole: return result.filename;
    default: return {};
    }
}

QHash<int, QByteArray> GrabberResultModel::roleNames() const
{
    return {
        { CheckedRole, "resultChecked" },
        { UrlRole, "url" },
        { FilenameRole, "filename" },
        { SourcePageRole, "sourcePage" },
        { SizeBytesRole, "sizeBytes" },
        { SizeTextRole, "sizeText" }
    };
}

bool GrabberResultModel::setData(const QModelIndex &index, const QVariant &value, int role)
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_results.size())
        return false;

    GrabberResult &result = m_results[index.row()];
    if (role == CheckedRole) {
        const bool checked = value.toBool();
        if (result.checked == checked)
            return false;
        m_checkedCount += checked ? 1 : -1;
        result.checked = checked;
        emit dataChanged(index, index, { role });
        return true;
    }
    return false;
}

Qt::ItemFlags GrabberResultModel::flags(const QModelIndex &index) const
{
    Qt::ItemFlags base = QAbstractListModel::flags(index);
    return index.isValid() ? (base | Qt::ItemIsUserCheckable | Qt::ItemIsEditable) : base;
}

void GrabberResultModel::setResults(const QVariantList &results)
{
    beginResetModel();
    m_results.clear();
    m_results.reserve(results.size());
    m_checkedCount = 0;
    for (const QVariant &value : results) {
        const QVariantMap map = value.toMap();
        GrabberResult result;
        result.checked = map.value(QStringLiteral("checked"), true).toBool();
        result.url = map.value(QStringLiteral("url")).toString();
        result.filename = map.value(QStringLiteral("filename")).toString();
        result.sourcePage = map.value(QStringLiteral("sourcePage")).toString();
        result.sizeBytes = map.value(QStringLiteral("sizeBytes"), -1).toLongLong();
        if (!result.url.isEmpty()) {
            if (result.checked) ++m_checkedCount;
            m_results.append(result);
        }
    }
    endResetModel();
}

void GrabberResultModel::appendResult(const QVariantMap &map)
{
    GrabberResult result;
    result.checked = map.value(QStringLiteral("checked"), true).toBool();
    result.url = map.value(QStringLiteral("url")).toString();
    result.filename = map.value(QStringLiteral("filename")).toString();
    result.sourcePage = map.value(QStringLiteral("sourcePage")).toString();
    result.sizeBytes = map.value(QStringLiteral("sizeBytes"), -1).toLongLong();
    if (result.url.isEmpty())
        return;

    const int row = m_results.size();
    beginInsertRows(QModelIndex(), row, row);
    if (result.checked) ++m_checkedCount;
    m_results.append(result);
    endInsertRows();
}

void GrabberResultModel::appendResults(const QList<GrabberResult> &results)
{
    if (results.isEmpty())
        return;
    const int first = m_results.size();
    const int last  = first + static_cast<int>(results.size()) - 1;
    beginInsertRows(QModelIndex(), first, last);
    for (const GrabberResult &r : results) {
        if (r.checked) ++m_checkedCount;
        m_results.append(r);
    }
    endInsertRows();

    // Keep the live sort order without resetting scroll position.
    if (!m_sortColumn.isEmpty())
        applySortLayout();
}

void GrabberResultModel::updateResultSize(const QString &url, qint64 sizeBytes)
{
    if (url.isEmpty())
        return;

    for (int row = 0; row < m_results.size(); ++row) {
        GrabberResult &result = m_results[row];
        if (result.url != url)
            continue;
        if (result.sizeBytes == sizeBytes)
            return;
        result.sizeBytes = sizeBytes;
        const QModelIndex modelIndex = index(row);
        emit dataChanged(modelIndex, modelIndex, { SizeBytesRole, SizeTextRole });

        // If the list is currently sorted by size, re-sort in-place so the updated
        // row moves to its correct position without resetting the scroll position.
        if (m_sortColumn == QStringLiteral("size"))
            applySortLayout();
        return;
    }
}

void GrabberResultModel::setChecked(int row, bool checked)
{
    setData(index(row), checked, CheckedRole); // counter updated inside setData
}

void GrabberResultModel::setAllChecked(bool checked)
{
    if (m_results.isEmpty())
        return;

    for (GrabberResult &result : m_results)
        result.checked = checked;
    m_checkedCount = checked ? static_cast<int>(m_results.size()) : 0;
    emit dataChanged(index(0), index(m_results.size() - 1), { CheckedRole });
}

// O(1) — counter is maintained incrementally by all mutating methods.
int GrabberResultModel::checkedCount() const
{
    return m_checkedCount;
}

QVariantList GrabberResultModel::allResults() const
{
    QVariantList results;
    results.reserve(m_results.size());
    for (const GrabberResult &result : m_results) {
        results.append(QVariantMap{
            { QStringLiteral("checked"), result.checked },
            { QStringLiteral("url"), result.url },
            { QStringLiteral("filename"), result.filename },
            { QStringLiteral("sourcePage"), result.sourcePage },
            { QStringLiteral("sizeBytes"), result.sizeBytes }
        });
    }
    return results;
}

QVariantList GrabberResultModel::checkedResults() const
{
    QVariantList results;
    for (const GrabberResult &result : m_results) {
        if (!result.checked)
            continue;
        results.append(QVariantMap{
            { QStringLiteral("url"), result.url },
            { QStringLiteral("filename"), result.filename },
            { QStringLiteral("sourcePage"), result.sourcePage },
            { QStringLiteral("sizeBytes"), result.sizeBytes }
        });
    }
    return results;
}

QVariantMap GrabberResultModel::resultData(int row) const
{
    if (row < 0 || row >= m_results.size())
        return {};

    const GrabberResult &result = m_results.at(row);
    return QVariantMap{
        { QStringLiteral("checked"), result.checked },
        { QStringLiteral("url"), result.url },
        { QStringLiteral("filename"), result.filename },
        { QStringLiteral("sourcePage"), result.sourcePage },
        { QStringLiteral("sizeBytes"), result.sizeBytes },
        { QStringLiteral("sizeText"), sizeText(result.sizeBytes) }
    };
}

static QString sortValueForResult(const QString &column, const GrabberResult &result)
{
    if (column == QStringLiteral("filename"))
        return result.filename.toLower();
    if (column == QStringLiteral("filetype")) {
        const QString source = !result.filename.isEmpty() ? result.filename : result.url;
        const int dot = source.lastIndexOf(QLatin1Char('.'));
        return dot >= 0 ? source.mid(dot + 1).toLower() : QStringLiteral("unknown");
    }
    if (column == QStringLiteral("downloadfrom"))
        return result.url.toLower();
    if (column == QStringLiteral("linktext"))
        return hostFromUrl(result.sourcePage.isEmpty() ? result.url : result.sourcePage);
    if (column == QStringLiteral("saveto"))
        return result.filename.toLower();
    if (column == QStringLiteral("status"))
        return QStringLiteral("ready");
    return result.filename.toLower();
}

void GrabberResultModel::sortBy(const QString &column, Qt::SortOrder order)
{
    m_sortColumn = column;
    m_sortOrder  = order;

    if (m_results.size() < 2) {
        // Nothing to sort but store state for future appends.
        return;
    }

    // User-triggered sort: full reset so the view scrolls back to top (expected UX).
    beginResetModel();
    std::stable_sort(m_results.begin(), m_results.end(),
                     [&](const GrabberResult &lhs, const GrabberResult &rhs) {
        if (column == QStringLiteral("size")) {
            const bool lUnknown = lhs.sizeBytes < 0;
            const bool rUnknown = rhs.sizeBytes < 0;
            if (lUnknown != rUnknown) return rUnknown; // unknown always sorts last
            if (lUnknown) return false;                // both unknown — equal
            return order == Qt::AscendingOrder ? lhs.sizeBytes < rhs.sizeBytes
                                               : lhs.sizeBytes > rhs.sizeBytes;
        }
        const QString left  = sortValueForResult(column, lhs);
        const QString right = sortValueForResult(column, rhs);
        return order == Qt::AscendingOrder ? left < right : left > right;
    });
    endResetModel();
}

void GrabberResultModel::applySortLayout()
{
    if (m_sortColumn.isEmpty() || m_results.size() < 2)
        return;

    const QString column = m_sortColumn;
    const Qt::SortOrder order = m_sortOrder;

    emit layoutAboutToBeChanged();
    std::stable_sort(m_results.begin(), m_results.end(),
                     [&](const GrabberResult &lhs, const GrabberResult &rhs) {
        if (column == QStringLiteral("size")) {
            const bool lUnknown = lhs.sizeBytes < 0;
            const bool rUnknown = rhs.sizeBytes < 0;
            if (lUnknown != rUnknown) return rUnknown; // unknown always sorts last
            if (lUnknown) return false;                // both unknown — equal
            return order == Qt::AscendingOrder ? lhs.sizeBytes < rhs.sizeBytes
                                               : lhs.sizeBytes > rhs.sizeBytes;
        }
        const QString left  = sortValueForResult(column, lhs);
        const QString right = sortValueForResult(column, rhs);
        return order == Qt::AscendingOrder ? left < right : left > right;
    });
    emit layoutChanged();
}

QString GrabberResultModel::sizeText(qint64 sizeBytes)
{
    static constexpr double kKB = 1024.0;
    static constexpr double kMB = kKB * 1024.0;
    static constexpr double kGB = kMB * 1024.0;
    if (sizeBytes < 0)
        return QStringLiteral("Unknown");
    if (sizeBytes < 1024)
        return QString::number(sizeBytes) + QStringLiteral(" B");
    if (sizeBytes < kMB)
        return QString::number(sizeBytes / kKB, 'f', 1) + QStringLiteral(" KB");
    if (sizeBytes < kGB)
        return QString::number(sizeBytes / kMB, 'f', 1) + QStringLiteral(" MB");
    return QString::number(sizeBytes / kGB, 'f', 1) + QStringLiteral(" GB");
}
