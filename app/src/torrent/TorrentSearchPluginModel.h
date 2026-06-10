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

#pragma once

#include <QAbstractListModel>
#include <QByteArray>
#include <QHash>
#include <QVariantMap>
#include <QVector>

class TorrentSearchPluginModel : public QAbstractListModel {
    Q_OBJECT
public:
    enum Role {
        FileNameRole = Qt::UserRole + 1,
        DisplayNameRole,
        VersionRole,
        UrlRole,
        EnabledRole,
        QuarantinedRole
    };

    struct Entry {
        QString fileName;
        QString displayName;
        QString version;
        QString url;
        bool enabled{true};
        bool quarantined{false}; // true = found on disk but not approved by the user
    };

    explicit TorrentSearchPluginModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    void setEntries(const QVector<Entry> &entries);
    Q_INVOKABLE QVariantMap pluginData(int row) const;
    Q_INVOKABLE bool setEnabled(int row, bool enabled);

private:
    QVector<Entry> m_entries;
};
