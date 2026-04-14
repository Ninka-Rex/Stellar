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
#include <QVector>

class TorrentTrackerModel : public QAbstractListModel {
    Q_OBJECT
public:
    enum Roles {
        UrlRole = Qt::UserRole + 1,
        StatusRole,
        TierRole,
        SourceRole,
        CountRole,
        SystemEntryRole,
        LatitudeRole,
        LongitudeRole,
        CountryCodeRole,
        MessageRole,
        SeedersRole,
        PeersRole
    };

    struct Entry {
        QString url;
        QString status;
        int tier{0};
        QString source;
        int count{0};
        bool systemEntry{false};
        double latitude{0.0};
        double longitude{0.0};
        QString countryCode;
        QString message;
        int seeders{0};
        int peers{0};
    };

    explicit TorrentTrackerModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    void setEntries(const QVector<Entry> &entries);

private:
    QVector<Entry> m_entries;
};
