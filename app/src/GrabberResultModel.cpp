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
#include <limits>

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
    for (const QVariant &value : results) {
        const QVariantMap map = value.toMap();
        GrabberResult result;
        result.checked = map.value(QStringLiteral("checked"), true).toBool();
        result.url = map.value(QStringLiteral("url")).toString();
        result.filename = map.value(QStringLiteral("filename")).toString();
        result.sourcePage = map.value(QStringLiteral("sourcePage")).toString();
        result.sizeBytes = map.value(QStringLiteral("sizeBytes"), -1).toLongLong();
        if (!result.url.isEmpty())
            m_results.append(result);
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
    m_results.append(result);
    endInsertRows();
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
        return;
    }
}

void GrabberResultModel::setChecked(int row, bool checked)
{
    setData(index(row), checked, CheckedRole);
}

void GrabberResultModel::setAllChecked(bool checked)
{
    if (m_results.isEmpty())
        return;

    for (GrabberResult &result : m_results)
        result.checked = checked;
    emit dataChanged(index(0), index(m_results.size() - 1), { CheckedRole });
}

int GrabberResultModel::checkedCount() const
{
    int count = 0;
    for (const GrabberResult &result : m_results) {
        if (result.checked)
            ++count;
    }
    return count;
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

void GrabberResultModel::sortBy(const QString &column, Qt::SortOrder order)
{
    if (m_results.size() < 2)
        return;

    auto sortValue = [&](const GrabberResult &result) -> QString {
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
    };

    beginResetModel();
    std::stable_sort(m_results.begin(), m_results.end(),
                     [&](const GrabberResult &lhs, const GrabberResult &rhs) {
        if (column == QStringLiteral("size")) {
            const qint64 left = lhs.sizeBytes < 0 ? std::numeric_limits<qint64>::max() : lhs.sizeBytes;
            const qint64 right = rhs.sizeBytes < 0 ? std::numeric_limits<qint64>::max() : rhs.sizeBytes;
            return order == Qt::AscendingOrder ? left < right : left > right;
        }

        const QString left = sortValue(lhs);
        const QString right = sortValue(rhs);
        return order == Qt::AscendingOrder ? left < right : left > right;
    });
    endResetModel();
}

QString GrabberResultModel::sizeText(qint64 sizeBytes)
{
    if (sizeBytes < 0)
        return QStringLiteral("Unknown");
    if (sizeBytes < 1024)
        return QString::number(sizeBytes) + QStringLiteral(" B");
    if (sizeBytes < 1024 * 1024)
        return QString::number(sizeBytes / 1024.0, 'f', 1) + QStringLiteral(" KB");
    if (sizeBytes < 1024ll * 1024ll * 1024ll)
        return QString::number(sizeBytes / 1048576.0, 'f', 1) + QStringLiteral(" MB");
    return QString::number(sizeBytes / 1073741824.0, 'f', 2) + QStringLiteral(" GB");
}
