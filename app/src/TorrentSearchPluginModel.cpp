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

#include "TorrentSearchPluginModel.h"

TorrentSearchPluginModel::TorrentSearchPluginModel(QObject *parent)
    : QAbstractListModel(parent) {}

int TorrentSearchPluginModel::rowCount(const QModelIndex &parent) const {
    return parent.isValid() ? 0 : m_entries.size();
}

QVariant TorrentSearchPluginModel::data(const QModelIndex &index, int role) const {
    if (!index.isValid() || index.row() < 0 || index.row() >= m_entries.size())
        return {};
    const Entry &entry = m_entries.at(index.row());
    switch (role) {
    case FileNameRole: return entry.fileName;
    case DisplayNameRole: return entry.displayName;
    case VersionRole: return entry.version;
    case UrlRole: return entry.url;
    case EnabledRole: return entry.enabled;
    case QuarantinedRole: return entry.quarantined;
    case Qt::DisplayRole: return entry.displayName.isEmpty() ? entry.fileName : entry.displayName;
    default: return {};
    }
}

QHash<int, QByteArray> TorrentSearchPluginModel::roleNames() const {
    return {
        { FileNameRole, "fileName" },
        { DisplayNameRole, "displayName" },
        { VersionRole, "version" },
        { UrlRole, "url" },
        { EnabledRole, "pluginEnabled" },
        { QuarantinedRole, "quarantined" }
    };
}

void TorrentSearchPluginModel::setEntries(const QVector<Entry> &entries) {
    beginResetModel();
    m_entries = entries;
    endResetModel();
}

QVariantMap TorrentSearchPluginModel::pluginData(int row) const {
    if (row < 0 || row >= m_entries.size())
        return {};
    const Entry &entry = m_entries.at(row);
    return {
        { QStringLiteral("fileName"), entry.fileName },
        { QStringLiteral("displayName"), entry.displayName },
        { QStringLiteral("version"), entry.version },
        { QStringLiteral("url"), entry.url },
        { QStringLiteral("enabled"), entry.enabled },
        { QStringLiteral("quarantined"), entry.quarantined }
    };
}

bool TorrentSearchPluginModel::setEnabled(int row, bool enabled) {
    if (row < 0 || row >= m_entries.size())
        return false;
    Entry &entry = m_entries[row];
    if (entry.enabled == enabled)
        return true;
    entry.enabled = enabled;
    const QModelIndex idx = index(row, 0);
    emit dataChanged(idx, idx, { EnabledRole });
    return true;
}
